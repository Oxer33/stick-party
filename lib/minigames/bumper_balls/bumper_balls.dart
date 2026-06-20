import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/push_arena.dart';
import '../../engine/helpers/zone_aim.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'bumper_fx.dart';
import 'bumper_render.dart';

/// Bumper Balls — "Fionda & sponde" (slingshot + bank shots). Every player is a
/// glowing bumper ball on a circular platform. A SLINGSHOT launch caroms off
/// rivals AND fixed PEGS to bank knock-outs off the edge — a skilful trick-shot
/// game, not a shove-spam.
///
/// SCORED BRAWL (not last-one-standing): the round runs the FULL [_timeLimit]
/// and your SCORE is the number of ring-outs you CAUSE. A knocked-off ball does
/// NOT end the round — it RESPAWNS ~[_respawnSec] later from its spawn edge with
/// a brief spawn-invuln, so a 1v1 becomes a sustained bumper match: knock the
/// rival off, it comes back, most ring-outs in [_timeLimit] wins. A ring-out
/// credits the LAST ball that bumped the victim; ringing YOURSELF out (no recent
/// attacker) scores nobody and docks a small penalty, so a feeble flail that
/// drifts you off the edge loses ground to judged, banked launches.
///
/// CONTROL — the SLINGSHOT (the heart of it; full agency, the player owns aim
/// AND power, nothing auto-targets):
///  * DRAG BACKWARD from your ball (pull back, like pool / Angry-Birds). A live
///    elastic band + a dotted trajectory preview + a power gauge show exactly
///    where and how hard you will fire — the launch vector is OPPOSITE the pull.
///  * POWER is the VISIBLE pull distance (∝ pull, clamped at [_maxPullFrac]). A
///    longer pull = a stronger cross-platform rocket.
///  * RELEASE = LAUNCH: the ball rolls with real momentum and caroms elastically
///    off rivals and off the PEGS (bank shots), staying bouncy for ~1s so a
///    well-judged angle banks a rival into the rim while you ricochet on.
///  * A tiny tap / micro-pull goes NOWHERE — a feeble nudge that drifts. There
///    is no invisible charge and no auto-aim assist: power and angle are earned
///    by the pull you can see.
///
/// WHY SPAM LOSES (the design law): a KO ejection requires a JUDGED pull. Launch
/// momentum is ∝ the pull fraction, so a blind tapper makes only feeble drifts;
/// contact knockback that ejects a rival scales with the attacker's COMMITTED
/// launch power ([_committedPower] window) so a weak nudge or a stale carom can
/// shove but never luck-launch; and only a strong launch arms the momentum-keep
/// rocket that banks off pegs. A blind masher out-scores nobody and self-rings
/// on the shrinking edge; a player who aims a banked slingshot wins.
///
/// Feel: a slick-but-grippy floor so launches carry; elastic caroms (PushArena)
/// off rivals + locally-resolved PEG bounces (restitution ~1) for lively banks;
/// a speed- and head-on-scaled knockback bonus so a fast square hit flings a
/// rival much further than a graze. Squash & stretch on impact, impact spark
/// rings, motion trails, glossy neon pegs that flash on impact, and a platform
/// that slowly shrinks after a grace period so matches always resolve.
///
/// Bots aim a slingshot at the nearest rival (or a bank line) and pull a power
/// scaled by accuracy: a short warmup, then hard bots line up strong banked
/// launches while easy bots mis-aim / under-pull and self-ring near the edge.
/// [BotProfile] governs timing, power and aim error so they read as deliberate,
/// not random — and never eject an idle player in the first several seconds.
class BumperBalls extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
    id: 'bumper_balls',
    name: 'Bumper Balls',
    minPlayers: 1,
    maxPlayers: 4,
    modes: [GameMode.ffa, GameMode.duel1v1],
    inputHint: 'PULL BACK',
  );

  // ── Arena / sim tuning ──────────────────────────────────────────────────────
  // Device-tuned for a sustained ~28s match: small bodies + big ring + grippy
  // floor so launches carry and bank but an idle ball is not instantly ejected;
  // ring-outs come from aimed, banked slingshot launches near the edge. KO'd
  // balls respawn, so the round always plays the FULL limit.
  static const double _timeLimit = 28;
  static const double _ringRadiusFactor = 0.46;
  static const double _bodyRadiusFactor = 0.05; // glossy bumper footprint
  static const double _ringFriction = 0.95; // grippy so launches settle, carry
  static const double _ringRestitution = 0.92; // lively ball-ball caroms
  static const double _spawnRadiusFactor = 0.55;

  // ── SLINGSHOT control tuning (the heart) ────────────────────────────────────
  // The player DRAGS BACKWARD from the ball; power is the VISIBLE pull distance
  // (no invisible charge). Pull is clamped to [_maxPullFrac] of the min screen
  // side; below [_minPullFrac] it is a feeble nudge that goes nowhere. The launch
  // momentum maps the pull fraction onto an impulse so a FULL pull is a strong
  // cross-platform rocket while a tap drifts.
  static const double _maxPullFrac = 0.16; // full pull = this share of min side
  static const double _minPullFrac =
      0.022; // below this the pull is a dud (a tap goes nowhere)
  static const double _cooldownSec = 0.22; // snappy recovery between launches
  // Launch impulse (arena-radius units) at zero vs full pull. A zero/micro pull
  // is a true DUD — it barely dribbles and cannot bank a rival; a full pull is a
  // strong rocket that crosses the platform and banks, but the grippy floor reins
  // it in if it misses (so a wild full launch is not a guaranteed self-ring). The
  // tiny base is what makes a blind every-frame tapper feeble.
  static const double _launchBase = 0.1; // near-nothing floor for a tap
  static const double _launchSpan = 3.4; // added at full pull → strong rocket
  static const double _selfPushback = 0.05; // tiny recoil opposite the launch
  static const double _trailLifeSec = 0.22;
  static const double _maxSpeedRef =
      700.0; // speed mapped to full trail/stretch

  // ── Rocket window (momentum-keep so launches bank off pegs) ─────────────────
  // A strong launch tags the ball "launched": for [_launchSec] the game
  // counteracts ring-friction so it keeps momentum and caroms off rivals + pegs
  // (bank shots) instead of dragging to a stop. Only a pull past
  // [_launchRocketMin] arms it, so a weak nudge dies quickly with no bank.
  static const double _launchSec = 1.0; // momentum-keep window after a launch
  static const double _launchRocketMin = 0.45; // pull frac that arms the rocket
  static const double _launchFrictionRetain =
      0.994; // per-1/60s speed kept while launched (a rocket carries across)
  static const double _launchMaxSpeed =
      1000.0; // cap so a rocket crosses the platform but never runs away

  // ── Pegs (static bumpers — the bank-shot anchors) ───────────────────────────
  // A small deterministic set of fixed circular bumpers. PushArena has no
  // immovable bodies, so the game resolves ball-peg contacts LOCALLY (reflect
  // about the contact normal, restitution [_pegRestitution], push out of
  // overlap) every frame — deterministic + frame-rate independent.
  static const double _pegRadiusFactor = 0.9; // peg R / body R
  static const double _pegRestitution = 1.0; // lively, near-perfectly elastic
  static const double _pegRingFactor =
      0.5; // off-centre pegs sit at this share of the ring R
  static const double _pegCoreOffsetFactor =
      0.2; // core peg nudged this far off centre (clears the spawn axis)
  static const double _pegFlashDecayPerSec = 3.4; // hit-flash relax speed
  // A peg must clear every spawn by this multiple of (body R + peg R), so a
  // respawning ball is never wedged into a bumper but pegs can still sit in the
  // spawn gaps. Kept tight: the bisector placement already maximises the angle.
  static const double _pegSpawnClearFactor = 1.12;

  // ── Knockback (contact) tuning ──────────────────────────────────────────────
  static const double _contactSpeedRef =
      700.0; // speed mapped to full knockback
  static const double _contactBonusScale =
      0.95; // bonus impulse / attacker speed (an aimed hit reliably ejects)
  static const double _headOnExtra = 1.2; // extra multiplier for a head-on hit
  static const double _heavyHitSpeed = 380.0; // above → heavy shake + hit-stop
  static const double _squashOnHit = 0.42; // squash amount stamped on impact
  static const double _squashDecayPerSec = 3.2; // how fast squash relaxes
  static const double _impactRingLifeSec = 0.32;
  static const double _impactRingMaxFactor = 2.4; // ring max radius / body R
  // ── COMMIT GATE on contact knockback (the anti-luck-launch rule) ─────────────
  // A weakly-slung ball (committed power below [_committedPower]) transfers only
  // [_weakHitKnockbackFloor] of its eject impulse, so a feeble nudge — or a ball
  // kept fast only by a later carom, not an aimed launch — can shove a rival but
  // cannot luck-launch them off the ring. Only a committed (strongly-slung) ball
  // ejects. Scales linearly to full at [_committedPower].
  static const double _weakHitKnockbackFloor = 0.32;
  static const double _committedPower = 0.5; // pull frac for full eject credit

  // ── Shrinking platform (sudden death) tuning ────────────────────────────────
  // The shrink does the late-game work: it starts after a grace period (so an
  // idle player is safe early) then closes decisively, forcing contact so a
  // match converges by ~20-24s instead of grinding to the time limit. Reaches
  // the floor at delay + (1-floor)/perSec ~ 9 + 0.56/0.044 ~ 22s, after which a
  // tight ring leaves accurate bots no safe edge to camp.
  static const double _shrinkDelaySec = 9.0;
  static const double _minRingFactor = 0.44; // floor as fraction of initial R
  static const double _shrinkPerSec = 0.044; // fraction of initial R per second

  // ── Climax (sudden death) tuning ────────────────────────────────────────────
  // The final ~28% of the match collapses the platform far faster with a SUDDEN
  // DEATH banner, so the round visibly ramps to a finish.
  static const double _suddenDeathFrac = 0.72; // enters at this share of time
  static const double _suddenDeathShrinkMul = 2.4; // shrink speed multiplier
  static const double _suddenDeathFloorMul =
      0.82; // tighter floor in sudden death
  // FINAL-2 SHOWDOWN: in the climax, if EXACTLY two players are tied for the
  // lead within this KO margin (a genuine race for the win), throw a one-shot
  // "FINAL TWO!" banner + slow-mo so the table feels the stakes.
  static const double _showdownMargin = 1.0; // within this many KOs of the lead

  // ── Star pickup (chaos) tuning ──────────────────────────────────────────────
  static const double _starRadiusFactor = 0.6; // star R / body R
  static const double _starFirstSpawnSec = 4.0;
  static const double _starRespawnSec = 7.5;
  static const double _starLifeSec = 6.0;
  static const double _starAppearPerSec = 3.0;
  static const double _starSpinPerSec = 3.2;
  static const double _starSpawnSpreadFactor = 0.42;
  static const double _buffSec = 4.0; // buff duration
  static const double _buffDashMul = 1.8; // bump magnitude × this while buffed
  static const Color _starColor = Color(0xFFFFE45C);

  // ── Ring-out tuning ─────────────────────────────────────────────────────────
  static const double _ringOutGraceFactor = 1.02; // detect just past current R
  // KO send-off: a knocked-off ball lingers as a spinning, shrinking VISUAL that
  // keeps its velocity and sails off over this many seconds (pure cosmetic — the
  // body is already eliminated). A small outward kick guarantees it clears the
  // platform even on a near-stationary ring-out.
  static const double _flingLifeSec = 0.4;
  static const double _flingMinOutSpeed = 260.0; // floor outward fling speed

  // ── Scored brawl: KO credit + respawn ───────────────────────────────────────
  // The round is a SCORED BRAWL, not last-standing: a ring-out scores the last
  // ball that bumped the victim (within [_attackerCreditSec] of the eject), and
  // the victim RESPAWNS [_respawnSec] later from its spawn edge with
  // [_spawnInvulnSec] of invulnerability (cannot be re-ejected or bump). A
  // self-ring-out — no fresh attacker — scores nobody and docks the victim
  // [_selfRingPenalty], so blind mash that rockets you off the edge loses ground.
  static const double _respawnSec = 1.2; // delay before a KO'd ball returns
  static const double _spawnInvulnSec = 0.9; // post-respawn grace (no KO either way)
  static const double _attackerCreditSec =
      1.1; // a bump credits a KO only this recently
  // A self-ring-out docks this (a soft nudge, not the headline) so a banked KO is
  // the dominant score signal — a feeble spammer that drifts off the shrinking
  // edge still loses ground, but the round is decided by KOs CAUSED, not by who
  // self-ringed least in the chaos.
  static const double _selfRingPenalty = 0.5;

  // ── Expression tuning ────────────────────────────────────────────────────────
  static const double _scaredEdgeFactor = 0.78; // dist/ring above → looks scared

  // ── Bot tuning (slingshot, BotProfile-driven, fair + beatable) ──────────────
  // Bots aim a slingshot and pick a PULL power scaled by accuracy. A warmup grace
  // keeps them passive at the start so they never eject an idle human early.
  static const double _botWarmupSec = 2.0; // grace before bots engage
  static const double _botCarrySpeed = 120.0; // skip a launch while already fast
  static const double _botEdgeBackoff =
      0.62; // dist/ring above → save toward centre
  static const double _botAimErrorRad = 0.55; // max aim jitter at accuracy 0
  static const double _botSavePull = 0.55; // pull used to save off the edge
  // Pull band for a bot launch, scaled by accuracy in [_botDecide] so the COMMIT
  // GATE + the pull→momentum map make a real skill gradient: a HARD bot reliably
  // pulls past [_committedPower] (strong banked launches that eject), an EASY bot
  // mostly stays under it (weak drifts that rarely KO and self-ring near the
  // edge) — beatable by a human who aims a judged slingshot.
  static const double _botPullMin = 0.22; // floor of the band (weak drift)
  static const double _botPullMax = 0.82; // hard-bot reach (strong rocket)
  // Easy bots over-pull/mis-judge a save and can fling THEMSELVES off the rim;
  // hard bots line up a bank toward the nearest rival.
  static const double _botBankAccuracy = 0.7; // ≥ this accuracy attempts banks

  // ── Visuals ─────────────────────────────────────────────────────────────────
  static const Color _accent = Color(0xFF5FE0FF); // neon platform rim accent
  static const Color _popupColor = Color(0xFFFF5A78);
  static const int _ambientMotes = 26;

  late Juice _juice;
  late PushArena _arena;
  double _elapsed = 0;
  double _animClock = 0; // real-time clock for ambient pulse (never scaled)

  late Size _size;
  late Offset _center;
  late double _ringRadius; // initial (max) radius — also the arena's radius
  late double _currentRingRadius; // shrinking radius for ring-out + visuals
  late double _bodyRadius;
  late double _maxPullPx; // full slingshot pull distance in screen px
  late double _previewMaxLen; // trajectory-preview length at full power (px)

  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, BallState> _ball = <int, BallState>{};
  final Set<int> _ragdolled = <int>{}; // bodies currently knocked off (respawning)
  final List<ImpactRing> _impacts = <ImpactRing>[];
  final List<Peg> _pegs = <Peg>[]; // static bumpers (bank-shot anchors)

  /// Spawn position per player, reused to fling a respawn back in from its edge.
  final Map<int, Offset> _spawnPos = <int, Offset>{};

  /// Knocked-off balls waiting to respawn (id → seconds remaining).
  final Map<int, double> _respawnTimers = <int, double>{};

  /// Knocked-off balls still spinning + shrinking off-screen (visual only; the
  /// matching bodies are eliminated until they respawn). Drained as each fling
  /// finishes.
  final List<FlungBall> _flung = <FlungBall>[];

  late StarController _stars;
  bool _suddenDeathAnnounced = false;
  bool _showdownAnnounced = false; // one-shot: the FINAL-2 KO-race callout
  bool _winnerCheered = false; // one-shot: the leader cheers when time expires

  /// Ambient energy mote positions (deterministic; drift handled at render).
  final List<Offset> _motes = <Offset>[];

  /// Pairs (encoded keys) overlapping last frame, so a contact fires its
  /// knockback bonus + impact spark exactly once per impact.
  final Set<int> _contactPairs = <int>{};

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _size = ctx.arena;
    _center = Offset(_size.width / 2, _size.height / 2);
    final minSide = math.min(_size.width, _size.height);
    _ringRadius = minSide * _ringRadiusFactor;
    _currentRingRadius = _ringRadius;
    _bodyRadius = minSide * _bodyRadiusFactor;
    _maxPullPx = minSide * _maxPullFrac;
    _previewMaxLen = _ringRadius * 1.25; // a full pull projects ~across the disc
    _stars = StarController(
      radius: _bodyRadius * _starRadiusFactor,
      firstSpawnSec: _starFirstSpawnSec,
      respawnSec: _starRespawnSec,
      lifeSec: _starLifeSec,
      appearPerSec: _starAppearPerSec,
      spinPerSec: _starSpinPerSec,
      spawnSpreadFactor: _starSpawnSpreadFactor,
    );

    // The arena's own ring-falloff must NOT cull balls: this game owns
    // elimination via [_detectRingOuts] against the *shrinking* radius so the KO
    // juice, impact ring and elimination order all fire. If the arena culled at
    // [_ringRadius] it would silently kill (alive=false) any ball launched out
    // before the platform shrinks, and [_detectRingOuts] would then skip it.
    // Use a radius beyond the screen so the arena never falls a ball off.
    _arena = PushArena(
      center: _center,
      ringRadius: _size.width + _size.height,
      friction: _ringFriction,
      restitution: _ringRestitution,
    );

    _buildBodies();
    _buildPegs();
    _seedMotes();
    begin();
  }

  /// Place a small deterministic set of static PEGS (bank-shot anchors). The
  /// count scales with player count (more balls → more banks worth setting up),
  /// and the layout is fixed by arena size + count so it is identical every run.
  /// Pegs are kept clear of every spawn point so a ball never lands inside one.
  ///
  /// Layout: a near-centre peg (the core bank anchor, nudged OFF the spawn axis
  /// so it never sits dead-on the line between two opposed spawns — otherwise a
  /// straight duel shot would always be blocked), plus off-centre pegs at the
  /// BISECTOR angles between adjacent spawn rays (so they sit in the GAPS, never
  /// on a spawn) at a radius safely inside the spawn ring. Lively banks open up
  /// off these without ever wedging a respawning ball or walling off a lane.
  void _buildPegs() {
    final count = ctx.players.length;
    final pegR = _bodyRadius * _pegRadiusFactor;
    final ringR = _ringRadius * _pegRingFactor;
    // 2 pegs at 1 player, scaling up to 4 at a full table — deterministic.
    final pegCount = (count + 1).clamp(2, 4);
    final ringPegs = pegCount - 1;

    // The core peg is nudged off-centre along a fixed diagonal so it is never
    // collinear with two opposed spawns (which would wall off a straight duel
    // shot); it still anchors bank lines from near the middle.
    final coreOffset = _ringRadius * _pegCoreOffsetFactor;
    final candidates = <Offset>[
      _center + Offset(coreOffset, coreOffset * 0.5),
    ];
    // Spawns are evenly spaced from +90° (see [_buildBodies]); place ring pegs on
    // the spawn-gap BISECTORS so each is maximally far (angularly) from every
    // spawn. With >1 player the slice is 2π/count; for a single player there is
    // no gap, so the lone ring peg goes straight opposite the spawn (north).
    for (var i = 0; i < ringPegs; i++) {
      final double angle;
      if (count <= 1) {
        angle = math.pi / 2 + math.pi; // opposite the single bottom spawn
      } else {
        // Bisector of spawn slice i: spawn angle + half a slice.
        angle = math.pi / 2 + (i + 0.5) / count * math.pi * 2;
      }
      candidates.add(
        _center + Offset(math.cos(angle), math.sin(angle)) * ringR,
      );
    }

    final clear = _bodyRadius * _pegSpawnClearFactor + pegR;
    for (final pos in candidates) {
      // Skip a candidate that would sit too close to any spawn point (so a
      // respawning ball is never wedged into a peg).
      final tooCloseToSpawn = _spawnPos.values.any(
        (sp) => (sp - pos).distance < clear,
      );
      if (tooCloseToSpawn) continue;
      _pegs.add(Peg(pos: pos, radius: pegR));
    }
    // Guarantee at least the centre peg exists even in a degenerate layout, so
    // the bank-shot identity always holds.
    if (_pegs.isEmpty) _pegs.add(Peg(pos: _center, radius: pegR));
  }

  /// Place one ball per player evenly on a spawn circle, with its aim pointing
  /// toward the centre so the very first bump is sensible, plus a bot clock.
  void _buildBodies() {
    final count = ctx.players.length;
    final spawnRadius = _ringRadius * _spawnRadiusFactor;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      // Start at +90° (bottom) so player 0 spawns in their own bottom zone and
      // 2-player duels face off north/south up the tall portrait screen.
      final angle = (i / count) * math.pi * 2 + math.pi / 2;
      final pos =
          _center + Offset(math.cos(angle), math.sin(angle)) * spawnRadius;
      _spawnPos[p.id] = pos;
      _arena.add(Body(id: p.id, pos: pos, radius: _bodyRadius));

      final towardCenter = math.atan2(_center.dy - pos.dy, _center.dx - pos.dx);
      _ball[p.id] = BallState(aim: towardCenter);
      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
      }
    }
  }

  void _seedMotes() {
    final rng = ctx.rng;
    for (var i = 0; i < _ambientMotes; i++) {
      _motes.add(Offset(rng.range(0, _size.width), rng.range(0, _size.height)));
    }
  }

  // ── Input: SLINGSHOT — drag back to aim+power, release to launch ────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final s = _ball[input.playerId];
    final body = _bodyOf(input.playerId);
    if (s == null || body == null || !body.alive) return;

    switch (input.phase) {
      case InputPhase.down:
        if (s.ready && !s.invulnerable) {
          s.aiming = true; // begin a pull
          s.hasPull = false;
          s.pullFrac = 0;
          // Anchor the slingshot to the FULL-SCREEN press point (normalized),
          // NOT the avatar — the zone-aim helper resolves direction from the
          // gesture WITHIN the player's zone, rotation-corrected per seat.
          s.pressNorm = input.normPos;
          s.pullBackVec = Offset.zero;
          s.downPos = _screen(input.normPos);
          s.dragPos = s.downPos;
        }
      case InputPhase.holdTick:
        // The finger travels: capture the live pull (relative to the ball) so the
        // band, preview and power gauge update. The launch fires OPPOSITE it.
        _updatePull(input, body, s);
      case InputPhase.up:
        if (s.aiming) {
          s.aiming = false;
          _updatePull(input, body, s); // a final move still counts
          // A judged pull (cleared the zone deadzone) launches OPPOSITE the drag
          // with power ∝ the resolved pull fraction. KID-SAFE FALLBACK: a tap
          // with no real drag still gently nudges the ball toward the nearest
          // rival (a feeble power-0 dud), so a young player who just taps is not
          // stranded — only a judged pull earns a real launch.
          if (s.hasPull) {
            _launch(input.playerId, body, s.aim, s.pullFrac);
          } else {
            final auto = _aimAtNearest(input.playerId) ?? s.aim;
            _launch(input.playerId, body, auto, 0.0);
          }
          s.pullFrac = 0;
          s.hasPull = false;
          s.pullBackVec = Offset.zero;
        }
    }
  }

  /// Capture the live slingshot pull from the finger position using the shared
  /// ZONE-RELATIVE aim helper. The aim is resolved from the gesture WITHIN the
  /// player's own zone (anchored to the press point, NOT the avatar) and
  /// rotation-corrected per seat, so a top-edge (rot2) player drags INTO the
  /// arena instead of back at their own rim, and a confined zone still reaches
  /// full power. The slingshot fires OPPOSITE the pull, so the launch heading
  /// [BallState.aim] is the resolved drag angle + pi; [BallState.pullFrac] is
  /// the helper's 0..1 pull strength. Below the helper's deadzone (!hasDrag) the
  /// pull is a dud, so a tap-in-place fires nowhere. A bare per-frame tick with
  /// no position is ignored (keeps the last captured pull).
  void _updatePull(PlayerInput input, Body body, BallState s) {
    if (!s.aiming) return;
    if (input.normPos == Offset.zero) return; // a bare tick carries no pos
    s.dragPos = _screen(input.normPos);

    final zone = ctx.zones.forPlayer(input.playerId);
    if (zone == null) {
      s.hasPull = false;
      s.pullFrac = 0;
      return;
    }
    final za = resolveZoneAim(
      zone: zone,
      pressNorm: s.pressNorm,
      curNorm: input.normPos,
      arena: _size,
      deadzoneFrac: _minPullFrac,
      maxPullFrac: _maxPullFrac,
    );
    if (!za.hasDrag) {
      s.hasPull = false; // still within the dead-zone — a dud so far
      s.pullFrac = 0;
      s.pullBackVec = Offset.zero;
      return;
    }
    // The slingshot fires OPPOSITE the pull: the resolved [za.angle] is the pull
    // direction, so the launch heading is angle + pi. Avatar position no longer
    // affects the manual aim DIRECTION.
    s.aim = za.angle + math.pi;
    s.pullFrac = za.pullFrac;
    s.hasPull = true;
    // Finger-anchored pull-back vector for the visible band: points along the
    // pull (away from the launch) so the telegraph matches the resolved aim
    // rather than the raw out-of-zone finger position.
    final pullDir = Offset(math.cos(za.angle), math.sin(za.angle));
    s.pullBackVec = pullDir * (za.pullFrac * _maxPullPx);
  }

  Offset _screen(Offset norm) =>
      Offset(norm.dx * _size.width, norm.dy * _size.height);

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _tickBallStates(dt);
    _tickImpacts(dt);
    _tickFlung(dt);
    _tickRespawns(dt);
    _tickPegs(dt);
    _driveBots(dt);
    _shrinkRing(dt);
    _stars.tick(
      dt,
      _arena.aliveBodies.length,
      ctx.rng,
      _center,
      _currentRingRadius,
    );

    _arena.update(sdt);

    _driveLaunched(sdt);
    // Resolve ball-PEG caroms AFTER integration + the rocket re-boost so the
    // bounce acts on the ball's true post-step velocity (the bank shot). The
    // engine has no immovable bodies, so this is owned locally.
    _resolvePegCollisions();
    _collectStars();
    _resolveContacts();
    _detectRingOuts();
    _resolveOutcome();
  }

  /// Relax each peg's hit-flash toward 0 (visual only), frame-rate independent.
  void _tickPegs(double dt) {
    for (final peg in _pegs) {
      peg.tick(dt, _pegFlashDecayPerSec);
    }
  }

  /// Resolve ball-vs-PEG collisions LOCALLY (PushArena has no immovable bodies):
  /// for each alive ball overlapping a peg, push the ball out of the overlap and
  /// reflect its velocity about the contact normal with [_pegRestitution]. The
  /// peg is treated as infinitely heavy (it never moves), so this is a clean
  /// mirror bounce — deterministic and frame-rate independent (it uses positions
  /// + velocity only, no dt). Stamps a hit flash + spark so a bank reads.
  void _resolvePegCollisions() {
    for (final b in _arena.aliveBodies) {
      for (final peg in _pegs) {
        final delta = b.pos - peg.pos; // peg → ball
        final dist = delta.distance;
        final minDist = b.radius + peg.radius;
        if (dist >= minDist) continue; // not touching

        // Contact normal (peg → ball); a dead-centre overlap gets a deterministic
        // fallback (use the ball's heading, else +x) so we never divide by zero.
        final Offset normal;
        if (dist > 1e-6) {
          normal = delta / dist;
        } else {
          final h = _normalize(b.vel);
          normal = h == Offset.zero ? const Offset(1, 0) : h;
        }
        // Push fully out of the overlap so the ball never tunnels through.
        b.pos = peg.pos + normal * minDist;

        // Reflect velocity about the normal only if moving INTO the peg, damped
        // by restitution. v' = v - (1 + e)(v·n) n.
        final vn = b.vel.dx * normal.dx + b.vel.dy * normal.dy;
        if (vn < 0) {
          b.vel = b.vel - normal * ((1.0 + _pegRestitution) * vn);
        }

        // A peg bank does not change WHO last bumped a rival (it is geometry,
        // not an attacker), so KO credit still belongs to the slinging ball.
        peg.hit();
        _spawnImpact(peg.pos, _colorOf(b.id));
        _ball[b.id]?.bump(_squashOnHit * 0.7, -normal);
        final speed = b.vel.distance;
        if (speed >= _heavyHitSpeed) {
          _juice.hit(peg.pos, _colorOf(b.id), sparks: 8);
          _juice.shake.light();
        } else if (speed > 1) {
          _juice.particles.burst(
            at: peg.pos,
            count: 5,
            color: _colorOf(b.id),
            speed: 180,
            size: 4,
            life: 0.28,
          );
        }
      }
    }
  }

  /// ROCKET DASH momentum-keep: the arena applied its normal friction this frame
  /// (it owns the shared [PushArena]); for any ball still inside its launch
  /// window we counteract most of that decay so the rocket keeps its speed and
  /// caroms off rivals (elastic) toward the edge while it ricochets on. Capped so a
  /// rocket never runs away; the launch tag itself expires on its own timer in
  /// [BallState.tick]. Frame-rate independent via [PushArena.friction].
  void _driveLaunched(double sdt) {
    if (sdt <= 0) return;
    // How much speed the arena's friction removed this frame (a < 1 multiplier).
    final applied = _arena.friction == 1.0
        ? 1.0
        : math.pow(_arena.friction, sdt * kFrictionReferenceFps).toDouble();
    // The slower decay we *want* a launched ball to feel instead.
    final wanted = math
        .pow(_launchFrictionRetain, sdt * kFrictionReferenceFps)
        .toDouble();
    if (applied <= 0) return;
    // Multiply velocity by (wanted/applied) to convert the steep friction the
    // arena already applied into the gentle launch decay.
    final boost = (wanted / applied).clamp(1.0, 4.0);
    for (final b in _arena.aliveBodies) {
      final s = _ball[b.id];
      if (s == null || s.launch <= 0) continue;
      var v = b.vel * boost;
      if (v.distance > _launchMaxSpeed) {
        v = v / v.distance * _launchMaxSpeed;
      }
      b.vel = v;
    }
  }

  /// True once the match has entered its climax (sudden death) window.
  bool get _isSuddenDeath => _elapsed >= _timeLimit * _suddenDeathFrac;

  // ── Per-frame ball state ─────────────────────────────────────────────────────

  /// Relax squash, age the trail + launch window and recover cooldown — all
  /// frame-rate independent. The aim + power are owned by the player's live pull
  /// (see [_updatePull]); nothing is auto-set here. Unlike the old charge model
  /// there is NO root while aiming: the ball is already at rest after a launch
  /// settles, and the slingshot is a discrete pull→release, so the player simply
  /// lines up a shot — power is the visible pull distance, earned, not timed.
  void _tickBallStates(double dt) {
    for (final entry in _ball.entries) {
      entry.value.tick(dt, _squashDecayPerSec);
    }
  }

  /// Angle from a ball to the nearest alive opponent, or null when none remain
  /// (e.g. the last ball standing). Used by the BOTS to aim a slingshot.
  double? _aimAtNearest(int playerId) {
    final self = _bodyOf(playerId);
    final target = _nearestOpponentPos(playerId);
    if (self == null || target == null) return null;
    final d = target - self.pos;
    if (d.distance < 1e-6) return null;
    return math.atan2(d.dy, d.dx);
  }

  void _tickImpacts(double dt) {
    for (final r in _impacts) {
      r.life -= dt;
    }
    _impacts.removeWhere((r) => r.life <= 0);
  }

  // ── Bots: warmup, then approach-nudge / charged-shove (mirrors Sumo) ────────

  /// Bots act on their reaction clock with [BotProfile]-driven timing, charge
  /// and aim error. A warmup keeps them passive at the start so they never eject
  /// an idle human in the first beats of the round.
  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // let the human get a beat first
    for (final entry in _botClocks.entries) {
      final id = entry.key;
      if (!_isAlive(id)) continue;
      if (!entry.value.tick(dt)) continue;
      entry.value.arm(ctx.botProfile, ctx.rng);
      _botDecide(id);
    }
  }

  /// Bots aim a SLINGSHOT and pull a power scaled by accuracy, then launch
  /// directly (no pull sim). The pull→momentum map + the commit gate make a real
  /// skill gradient: a hard bot pulls strong, aimed banked launches; an easy bot
  /// under-pulls / mis-aims and self-rings near the edge.
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    final s = _ball[playerId];
    if (self == null || !self.alive || s == null || !s.ready) return;
    if (s.invulnerable) return; // just respawned — settle before engaging
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return; // hesitate / mistake

    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    final err = (1.0 - acc) * _botAimErrorRad;

    // Near the edge: a competent bot SAVES itself with a launch back toward the
    // centre — but a LOW-ACCURACY (easy) bot mis-judges the save by [err], so it
    // can mis-aim and fling ITSELF off the rim. Skill (accuracy) buys a clean
    // recovery; a weak bot self-rings, exactly the beatable behaviour a human
    // exploits. The save is pulled strong enough to carry inward.
    if (_isNearEdge(self)) {
      final aim =
          math.atan2(_center.dy - self.pos.dy, _center.dx - self.pos.dx) +
          ctx.rng.jitter(err);
      _launch(playerId, self, aim, _botSavePull + 0.25 * acc);
      return;
    }

    // Don't waste a launch while already carrying lots of speed (it would just
    // overshoot) — let the current shot play out.
    if (self.vel.distance > _botCarrySpeed) return;

    final targetPos = _nearestOpponentPos(playerId);
    if (targetPos == null) return;

    // Hard bots (high accuracy) may aim a BANK off the nearest peg instead of a
    // straight line — a deliberate trick-shot that reads as skill. Easy bots aim
    // straight (and badly). Either way the aim carries [err] jitter.
    double aimAngle;
    if (acc >= _botBankAccuracy) {
      aimAngle = _bankAimAngle(self.pos, targetPos) ??
          math.atan2(targetPos.dy - self.pos.dy, targetPos.dx - self.pos.dx);
    } else {
      aimAngle = math.atan2(targetPos.dy - self.pos.dy, targetPos.dx - self.pos.dx);
    }
    aimAngle += ctx.rng.jitter(err);

    // Pull power scales with accuracy so the COMMIT GATE creates the gradient: a
    // HARD bot pulls past [_committedPower] (strong launches that eject), an EASY
    // bot mostly stays under it — weak drifts that rarely KO and risk self-ring.
    final pull = (_botPullMin +
            (_botPullMax - _botPullMin) * acc * ctx.rng.range(0.7, 1.0))
        .clamp(0.0, 1.0);
    _launch(playerId, self, aimAngle, pull);
  }

  /// A launch angle that banks off the nearest peg toward [targetPos]: aim at a
  /// point just off the near side of the peg so the ball glances off it onto the
  /// rival. Returns null if no peg helps (then the caller aims straight). Cheap,
  /// deterministic, used by HARD bots so a bank reads as a deliberate trick-shot.
  double? _bankAimAngle(Offset from, Offset targetPos) {
    Peg? best;
    var bestDist = double.infinity;
    for (final peg in _pegs) {
      // Only banks that sit roughly between the shooter and the target help.
      final toPeg = peg.pos - from;
      final toTarget = targetPos - from;
      if (toPeg.distance < 1e-3) continue;
      final dot = toPeg.dx * toTarget.dx + toPeg.dy * toTarget.dy;
      if (dot <= 0) continue; // peg is behind / sideways — not a useful bank
      if (toPeg.distance < bestDist) {
        bestDist = toPeg.distance;
        best = peg;
      }
    }
    if (best == null) return null;
    // Aim at the side of the peg facing the target so the ball grazes it onto
    // the rival rather than dead-centre (which would bounce straight back).
    final toPeg = best.pos - from;
    final perp = _normalize(Offset(-toPeg.dy, toPeg.dx));
    final side = ((targetPos - best.pos).dx * perp.dx +
            (targetPos - best.pos).dy * perp.dy) >=
        0
        ? 1.0
        : -1.0;
    final aimPoint = best.pos + perp * side * (best.radius + _bodyRadius);
    return math.atan2(aimPoint.dy - from.dy, aimPoint.dx - from.dx);
  }

  /// Shared SLINGSHOT launch: fire the ball along [aimAngle] with momentum ∝
  /// [power] (0..1, the pull fraction), a small self-recoil, cooldown, trail, a
  /// forward stretch hint and a release spark. Used by humans (pull→release) and
  /// bots (direct) so the feel matches exactly. A power below the dud floor still
  /// fires a feeble nudge (it goes nowhere) — the visible pull is the only lever.
  ///
  /// Visible for testing so a deterministic round can drive an exact aim+power
  /// launch without scripting touch geometry (see [debugLaunch]).
  void _launch(int playerId, Body self, double aimAngle, double power) {
    final s = _ball[playerId];
    if (s == null || !s.ready || s.invulnerable) return;

    final p = power.clamp(0.0, 1.0);
    final dir = Offset(math.cos(aimAngle), math.sin(aimAngle));
    // A collected star briefly amplifies a launch — the buffed ball flies harder.
    final buffMul = s.buffed ? _buffDashMul : 1.0;
    // Momentum is the VISIBLE pull mapped onto an impulse: a feeble floor for a
    // micro-pull, a strong cross-platform rocket at a full pull.
    final magnitude = _ringRadius * (_launchBase + _launchSpan * p) * buffMul;
    // A launch SETS velocity (it does not stack onto a still-moving ball) so the
    // shot power is exactly the visible pull — no spam-stacking past the cap.
    self.vel = dir * magnitude;
    self.vel -= dir * magnitude * _selfPushback;

    // Contact knockback reads this: only a strongly-slung ball ejects a rival; a
    // feeble nudge marks low power and so cannot luck-launch anyone.
    s.markLaunch(p);
    s.fire(_cooldownSec);
    s.trail = DashTrail(dir: dir, life: _trailLifeSec);
    s.stretchDir = dir;
    s.aim = aimAngle;
    // A strong pull arms the ROCKET window: a momentum-keep so the ball banks off
    // pegs + rivals toward the edge. A weak nudge does not (it dies quickly).
    if (p >= _launchRocketMin) s.launch = _launchSec;

    final intensity = 0.5 + 0.5 * p;
    _juice.particles.burst(
      at: self.pos - dir * _bodyRadius,
      count: (6 + 8 * p).round(),
      color: _colorOf(playerId),
      speed: 200 * intensity,
      baseAngle: math.atan2(-dir.dy, -dir.dx),
      spread: math.pi * 0.7,
      size: 4,
      gravity: 120,
      life: 0.3,
    );
    _juice.hit(self.pos, _colorOf(playerId), sparks: (3 + 4 * p).round());
    if (p > 0.6) _juice.shake.light();
  }

  bool _isNearEdge(Body b) =>
      (b.pos - _center).distance > _currentRingRadius * _botEdgeBackoff;

  /// Nearest alive opponent's position, or null when none remain.
  Offset? _nearestOpponentPos(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null) return null;
    Offset? best;
    var bestDist = double.infinity;
    for (final b in _arena.aliveBodies) {
      if (b.id == playerId) continue;
      final d = (b.pos - self.pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = b.pos;
      }
    }
    return best;
  }

  // ── Contact knockback (speed + head-on scaling) ─────────────────────────────

  /// Detect newly-touching alive pairs; apply a bonus shove to the slower ball
  /// scaled by the attacker's speed and how head-on the hit is, plus squash and
  /// an impact spark ring. Tracked so each contact fires exactly once.
  void _resolveContacts() {
    final alive = _arena.aliveBodies;
    final current = <int>{};
    for (var i = 0; i < alive.length; i++) {
      for (var j = i + 1; j < alive.length; j++) {
        final a = alive[i];
        final b = alive[j];
        final delta = b.pos - a.pos;
        final dist = delta.distance;
        final minDist = a.radius + b.radius;
        if (dist >= minDist) continue;

        final key = _pairKey(a.id, b.id);
        current.add(key);
        if (_contactPairs.contains(key)) continue; // already counted

        _applyKnockback(a, b, delta, dist);
      }
    }
    _contactPairs
      ..clear()
      ..addAll(current);
  }

  void _applyKnockback(Body a, Body b, Offset delta, double dist) {
    final normal = dist > 1e-6 ? delta / dist : const Offset(1, 0);
    final attacker = a.vel.distance >= b.vel.distance ? a : b;
    final victim = identical(attacker, a) ? b : a;
    // Normal points from attacker toward victim.
    final toVictim = identical(attacker, a) ? normal : -normal;

    final speed = attacker.vel.distance;
    final at = Offset.lerp(a.pos, b.pos, 0.5) ?? a.pos;

    // SCORED BRAWL: remember who bumped the victim so a follow-up ring-out
    // credits them. An invulnerable (just-respawned) attacker's bump does not
    // count, so they cannot farm KOs during their grace.
    if (!(_ball[attacker.id]?.invulnerable ?? false)) {
      _ball[victim.id]?.markHitBy(attacker.id);
    }

    // Always stamp an impact spark + squash, even on gentle taps.
    _spawnImpact(at, _colorOf(attacker.id));
    _ball[a.id]?.bump(_squashOnHit, -normal);
    _ball[b.id]?.bump(_squashOnHit, normal);

    if (speed < 1) {
      _juice.shake.light();
      return;
    }

    final attackerDir = attacker.vel / speed;
    final headOn = (attackerDir.dx * toVictim.dx + attackerDir.dy * toVictim.dy)
        .clamp(0.0, 1.0);
    final speedFactor = (speed / _contactSpeedRef).clamp(0.0, 1.4);
    // COMMIT GATE: a feeble nudge transfers only [_weakHitKnockbackFloor] of its
    // eject impulse; a strongly-slung ball transfers the full hit. So a rival is
    // launched off the ring only by an *aimed, hard* slingshot — an incidental
    // bump or a ball kept fast only by a later carom can shove someone but not
    // eject them, which is what makes button-spam unable to luck-KO. A
    // star-buffed attacker always counts as committed (the buff IS the power).
    final atkS = _ball[attacker.id];
    final commit = (atkS?.buffed ?? false)
        ? 1.0
        : (atkS == null
              ? 1.0
              : (atkS.committedPower / _committedPower).clamp(0.0, 1.0));
    final commitFactor =
        _weakHitKnockbackFloor + (1.0 - _weakHitKnockbackFloor) * commit;
    final bonus =
        _ringRadius *
        _contactBonusScale *
        speedFactor *
        commitFactor *
        (1.0 + _headOnExtra * headOn);
    _arena.impulse(victim.id, toVictim * bonus);

    if (speed >= _heavyHitSpeed) {
      _juice.hit(at, _colorOf(attacker.id), sparks: 12);
      _juice.shake.medium();
    } else {
      _juice.particles.burst(
        at: at,
        count: 6,
        color: _colorOf(attacker.id),
        speed: 200,
        size: 4,
        life: 0.32,
      );
      _juice.shake.light();
    }
  }

  void _spawnImpact(Offset at, Color color) {
    _impacts.add(ImpactRing(at: at, color: color, life: _impactRingLifeSec));
  }

  // ── Shrinking platform ──────────────────────────────────────────────────────

  void _shrinkRing(double dt) {
    if (_elapsed < _shrinkDelaySec) return;
    // Sudden death tightens the floor and speeds the collapse so the round ramps
    // unmistakably toward a finish in its final stretch.
    final sudden = _isSuddenDeath;
    final floor =
        _ringRadius * _minRingFactor * (sudden ? _suddenDeathFloorMul : 1.0);
    if (_currentRingRadius <= floor) return;
    final rate = _shrinkPerSec * (sudden ? _suddenDeathShrinkMul : 1.0);
    _currentRingRadius = (_currentRingRadius - _ringRadius * rate * dt).clamp(
      floor,
      _ringRadius,
    );
  }

  // ── Star pickup (chaos) ─────────────────────────────────────────────────────

  /// Any ball overlapping a ready star collects it: a brief bump buff + a burst
  /// + popup. The grabber gets a swingy edge — pure chaos for the table.
  void _collectStars() {
    final star = _stars.star;
    if (star == null || !star.ready) return;
    for (final b in _arena.aliveBodies) {
      if ((b.pos - star.pos).distance > b.radius + star.radius) continue;
      _ball[b.id]?.buff = _buffSec;
      _stars.consume();
      _spawnImpact(star.pos, _starColor);
      _juice.particles.burst(
        at: star.pos,
        count: 18,
        color: _starColor,
        speed: 280,
        size: 6,
        gravity: 120,
        life: 0.6,
      );
      _juice.hit(b.pos, _colorOf(b.id), sparks: 8);
      _juice.popup(
        b.pos.translate(0, -_bodyRadius * 1.8),
        'POWER!',
        _starColor,
        size: 30,
      );
      return;
    }
  }

  // ── Ring-out detection (uses the shrinking radius) ──────────────────────────

  /// Mark any ball whose center has left the *current* (shrinking) platform as
  /// knocked off, credit the ring-out and queue a respawn (never a permanent
  /// elimination), then fire the KO sequence once each. The arena only culls at
  /// its own larger radius, so we own this.
  void _detectRingOuts() {
    final edge = _currentRingRadius * _ringOutGraceFactor;
    var firedBig = false; // one cinematic knock-off beat per frame (kid-tasteful)
    for (final b in _arena.bodies) {
      if (!b.alive || _ragdolled.contains(b.id)) continue;
      // A just-respawned ball cannot be knocked off during its spawn grace, so
      // it is never re-ejected the instant it lands back in the (shrunk) ring.
      if (_ball[b.id]?.invulnerable ?? false) continue;
      if ((b.pos - _center).distance <= edge) continue;

      // CHARM (visual only): before the body is zeroed, snapshot a spinning,
      // shrinking fling that keeps the ball's knock-off velocity and sails
      // off-platform — so a KO is funny instead of an instant pop. A small
      // outward floor guarantees it clears the edge even on a slow ring-out.
      _spawnFling(b);

      b.alive = false;
      b.vel = Offset.zero;
      _ragdolled.add(b.id);
      // SCORED BRAWL: credit the KO + queue the victim's respawn, so the round
      // keeps going for the full limit instead of ending on the knockout.
      _scoreRingOut(b.id);
      _respawnTimers[b.id] = _respawnSec;

      // The knock-off is the signature beat: a single big-moment (burst + heavy
      // shake + slow-mo + zoom toward the victim + flash + 'OUT!' banner +
      // haptic). A rare same-frame second eject keeps the lighter KO.
      if (!firedBig) {
        firedBig = true;
        _juice.bigMoment(b.pos, _colorOf(b.id), banner: 'OUT!');
      } else {
        _juice.ko(b.pos, _colorOf(b.id));
      }
      _spawnImpact(b.pos, _colorOf(b.id));
      // A fatter eject flourish: an extra outward spark fan so the knockout
      // reads as a big moment kids cheer for. The 'OUT!' callout is now the
      // cinematic banner from bigMoment above (no duplicate world popup).
      final outDir = _normalize(b.pos - _center);
      _juice.particles.burst(
        at: b.pos,
        count: 16,
        color: _colorOf(b.id),
        speed: 360,
        baseAngle: math.atan2(outDir.dy, outDir.dx),
        spread: math.pi * 0.9,
        size: 7,
        gravity: 220,
        life: 0.7,
      );
    }
  }

  /// Snapshot a spinning, shrinking fling for a ball that is about to be retired.
  /// It keeps the ball's knock-off velocity but is nudged outward (away from the
  /// centre) to a guaranteed minimum so it always sails off the platform. Purely
  /// a visual; the caller still flips alive=false and records the ranking.
  void _spawnFling(Body b) {
    final outDir = _normalize(b.pos - _center);
    final dir = outDir == Offset.zero ? const Offset(0, 1) : outDir;
    // Keep the existing velocity, but ensure a brisk outward component so a slow
    // ring-out still launches rather than dribbling at the edge.
    final outwardSpeed = math.max(b.vel.distance, _flingMinOutSpeed);
    final vel = b.vel + dir * outwardSpeed;
    _flung.add(FlungBall(
      pos: b.pos,
      vel: vel,
      color: _colorOf(b.id),
      radius: b.radius,
      displayNumber: b.id + 1,
      life: _flingLifeSec,
      spinDir: b.id.isEven ? 1.0 : -1.0,
    ));
  }

  void _tickFlung(double dt) {
    for (final f in _flung) {
      f.tick(dt);
    }
    _flung.removeWhere((f) => f.done);
  }

  /// Award a ring-out: credit the ball that last bumped [victimId] (if recent
  /// enough), bumping their [BallState.koScore]. A self-ring-out — no fresh
  /// attacker — scores nobody and docks the victim [_selfRingPenalty], so blind
  /// mash off the edge actively loses ground. Live scores are mirrored to the
  /// engine so the on-field HUD shows the KO race.
  void _scoreRingOut(int victimId) {
    final victim = _ball[victimId];
    final attackerId = victim?.lastAttacker ?? -1;
    final recent =
        (victim?.attackerAge ?? double.infinity) <= _attackerCreditSec;
    if (victim != null) {
      victim.lastAttacker = -1; // consumed — a later eject must be re-earned
    }
    if (attackerId >= 0 && attackerId != victimId && recent) {
      final attacker = _ball[attackerId];
      if (attacker != null) {
        attacker.koScore += 1;
        setScore(attackerId, attacker.koScore);
        final pos = _bodyOf(attackerId)?.pos;
        if (pos != null) {
          _juice.popup(
            pos.translate(0, -_bodyRadius * 1.9),
            'KO!',
            _colorOf(attackerId),
            size: 28,
          );
        }
      }
      return;
    }
    // Self-ring-out (or stale attacker): no credit, small penalty. The score may
    // go NEGATIVE on purpose — that is the anti-spam signal that a blind dasher
    // who rockets itself off the edge has actively LOST ground (the SPAM-LOSES
    // tests rely on it). The winner is still whoever banked the most KOs.
    if (victim != null) {
      victim.koScore -= _selfRingPenalty;
      setScore(victimId, victim.koScore);
    }
  }

  /// Count down each knocked-off ball's respawn timer; when it elapses, bring
  /// the ball back from its spawn edge at rest with [_spawnInvulnSec] of grace.
  void _tickRespawns(double dt) {
    if (_respawnTimers.isEmpty) return;
    final ready = <int>[];
    _respawnTimers.updateAll((id, t) => t - dt);
    _respawnTimers.forEach((id, t) {
      if (t <= 0) ready.add(id);
    });
    for (final id in ready) {
      _respawnTimers.remove(id);
      _respawn(id);
    }
  }

  /// Bring [id] back onto the platform from its spawn edge (clamped inside the
  /// current shrunk ring), at rest and invulnerable for a beat.
  void _respawn(int id) {
    final body = _bodyOf(id);
    if (body == null) return;
    final spawn = _spawnPos[id] ?? _center;
    // Pull the spawn point inside the live ring so a tight sudden-death ring
    // never drops the respawn straight back off the edge.
    final fromCenter = spawn - _center;
    final maxR = _currentRingRadius * 0.7;
    final pos = fromCenter.distance > maxR
        ? _center + _normalize(fromCenter) * maxR
        : spawn;
    body.pos = pos;
    body.vel = Offset.zero; // dropped back in at rest; the player re-aims
    body.alive = true;
    _ragdolled.remove(id);
    _contactPairs.removeWhere((key) => key ~/ 8 == id || key % 8 == id);
    final s = _ball[id];
    if (s != null) {
      s
        ..aiming = false
        ..hasPull = false
        ..pullFrac = 0
        ..launch = 0
        ..squash = 0
        ..invuln = _spawnInvulnSec
        ..lastAttacker = -1
        ..trail = null;
    }
    _spawnImpact(pos, _colorOf(id));
    _juice.particles.burst(
      at: pos,
      count: 12,
      color: _colorOf(id),
      speed: 220,
      size: 6,
      gravity: 120,
      life: 0.5,
    );
    _juice.popup(
      pos.translate(0, -_bodyRadius * 1.9),
      'BACK!',
      _colorOf(id),
      size: 24,
    );
  }

  // ── Outcome ──────────────────────────────────────────────────────────────────

  void _resolveOutcome() {
    // Announce the climax exactly once with a shake + center popup; the
    // fast-shrink platform + banner then carry the moment. (≥2 balls in play.)
    if (!_suddenDeathAnnounced && _isSuddenDeath && ctx.players.length > 1) {
      _suddenDeathAnnounced = true;
      _juice.shake.medium();
      _juice.popup(
        _center.translate(0, -_currentRingRadius * 0.2),
        'SUDDEN DEATH',
        _popupColor,
        size: 38,
      );
    }
    // FINAL-2 SHOWDOWN: once in the climax, the FIRST time the lead narrows to a
    // genuine two-player KO race, slam a cinematic "FINAL TWO!" banner + slow-mo
    // so the decisive stretch reads as a duel for the win. One-shot per round.
    if (!_showdownAnnounced &&
        _isSuddenDeath &&
        ctx.players.length > 2 &&
        _isTwoWayShowdown()) {
      _showdownAnnounced = true;
      _juice.slowMo(dur: 0.45, scale: 0.4);
      _juice.flashScreen(_accent, strength: 0.35);
      _juice.bigBanner('FINAL TWO!', color: _accent);
      _juice.shake.medium();
    }
    // SCORED BRAWL: the round runs the FULL limit (KO'd balls respawn), so it
    // NEVER ends early just because only one is on the platform. Most ring-outs
    // wins (ties broken by the engine's stable order).
    if (_elapsed >= _timeLimit) _finishScored();
  }

  /// Bell time: the leader (most KOs, ties → lowest id) gets a one-shot
  /// celebration — confetti rain + a WINNER banner + a big-moment punch on them
  /// — so the round ends on a cheer instead of a freeze. (A lone-practice round
  /// skips the multiplayer banner fanfare.)
  void _finishScored() {
    if (!_winnerCheered) {
      _winnerCheered = true;
      final leader = _leaderId();
      _juice.confetti(
        _size,
        colors: [_accent, _starColor, _colorOfLeader(leader)],
      );
      if (ctx.players.length > 1) {
        final at = (leader != null ? _bodyOf(leader)?.pos : null) ?? _center;
        _juice.bigMoment(at, _colorOfLeader(leader), banner: 'WINNER!');
      }
    }
    finishByScore();
  }

  /// True when EXACTLY two players are within [_showdownMargin] KOs of the top
  /// score and that top score is a real lead (> 0) — a genuine two-way race for
  /// the win, the cue for the FINAL-2 showdown beat. (3+ contenders is a melee,
  /// not a showdown; 0-0 is not yet a race.)
  bool _isTwoWayShowdown() {
    var top = double.negativeInfinity;
    for (final p in ctx.players) {
      final s = _ball[p.id]?.koScore ?? 0;
      if (s > top) top = s;
    }
    if (top <= 0) return false;
    var contenders = 0;
    for (final p in ctx.players) {
      final s = _ball[p.id]?.koScore ?? 0;
      if (top - s <= _showdownMargin) contenders++;
    }
    return contenders == 2;
  }

  /// The id with the highest [BallState.koScore] (ties → lowest id), or null if
  /// there are no players. Used for the bell fanfare so confetti/banner match
  /// the winner.
  int? _leaderId() {
    int? best;
    var bestScore = double.negativeInfinity;
    for (final p in ctx.players) {
      final s = _ball[p.id]?.koScore ?? 0;
      if (s > bestScore) {
        bestScore = s;
        best = p.id;
      }
    }
    return best;
  }

  Color _colorOfLeader(int? id) =>
      id == null ? _accent : _colorOf(id);

  // ── Render ────────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    _juice.applyWorldTransform(canvas);

    BumperRenderer.drawBackground(canvas, size, _center, _ringRadius);
    BumperRenderer.drawAmbientMotes(canvas, _motes, _animClock);
    BumperRenderer.drawPlatform(
      canvas,
      _center,
      _currentRingRadius,
      accent: _accent,
      dangerPulse: _dangerPulse(),
      t: _animClock,
    );

    // Pegs sit on the floor under the balls so a ball rides over a bumper.
    for (final peg in _pegs) {
      BumperFx.drawPeg(canvas, peg, _animClock);
    }

    final star = _stars.star;
    if (star != null) BumperFx.drawStar(canvas, star);

    _drawBalls(canvas);
    _drawFlung(canvas); // spinning/shrinking knocked-off balls (visual send-off)
    _drawImpacts(canvas);

    _juice.render(canvas);
    canvas.restore();

    // Screen-space overlays (after the world transform is restored so they are
    // never shaken or zoomed by the camera punch): the SUDDEN DEATH banner +
    // the cinematic flash/banner from bigMoment.
    if (_isSuddenDeath) {
      // Hold the banner up through the whole climax for a multi-player brawl
      // (a lone respawn window must not blink it off).
      BumperFx.drawSuddenDeathBanner(
        canvas,
        size,
        ctx.players.length > 1 ? 1.0 : 0.0,
        _animClock,
      );
    }
    _juice.renderOverlay(canvas, size);
  }

  /// Danger band pulse: brighter as the platform shrinks + a steady throb.
  double _dangerPulse() {
    final shrink =
        1.0 - (_currentRingRadius / _ringRadius).clamp(_minRingFactor, 1.0);
    final throb = 0.5 + 0.5 * math.sin(_animClock * 4.0);
    return (0.35 + shrink + 0.25 * throb).clamp(0.0, 1.0);
  }

  void _drawBalls(Canvas canvas) {
    for (final b in _arena.aliveBodies) {
      final state = _ball[b.id];
      final color = _colorOf(b.id);
      final speed = b.vel.distance;
      final speedFrac = (speed / _maxSpeedRef).clamp(0.0, 1.0);
      final heading = _normalize(b.vel);
      final ground = Offset(b.pos.dx, b.pos.dy + b.radius * 0.7);

      // Soft contact shadow under the ball, on the platform.
      BumperRenderer.drawContactShadow(canvas, ground, b.radius);

      // Player-colour ground id ring so each ball is always identifiable.
      BumperRenderer.drawIdRing(canvas, ground, b.radius, color, b.id + 1);

      // A pulsing gold aura while the star buff is active so the table sees who
      // is dangerous right now.
      if (state != null && state.buffed) {
        final pulse = 0.5 + 0.5 * math.sin(_animClock * 6.0);
        canvas.drawCircle(
          b.pos,
          b.radius * (1.5 + 0.18 * pulse),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = b.radius * 0.16
            ..color = _starColor.withValues(
              alpha: (0.45 + 0.35 * pulse).clamp(0.0, 1.0),
            ),
        );
      }

      // ROCKET DASH: a hot comet aura while the launch window is live so the
      // table reads "this one is dangerous and caroming off rivals".
      if (state != null && state.launched && heading != Offset.zero) {
        BumperRenderer.drawLaunchAura(
          canvas,
          b.pos,
          heading,
          b.radius,
          color,
          speedFrac,
        );
      }

      // Motion trail behind a recent dash / fast drift (longer while launched).
      final trail = state?.trail;
      final launched = state?.launched ?? false;
      if (trail != null) {
        BumperRenderer.drawTrail(
          canvas,
          b.pos,
          trail.dir,
          b.radius,
          color,
          launched ? 1.0 : trail.strength,
          speedFrac,
        );
      } else if ((launched || speedFrac > 0.25) && heading != Offset.zero) {
        BumperRenderer.drawTrail(
          canvas,
          b.pos,
          heading,
          b.radius,
          color,
          launched ? 1.0 : 0.6,
          speedFrac,
        );
      }

      // Speed-stretch combined with a relaxing impact squash.
      final stretch = speedFrac * 0.28 + (state?.squash ?? 0);
      final stretchDir =
          state?.stretchDir ??
          (heading == Offset.zero ? const Offset(1, 0) : heading);
      final lookDir = heading == Offset.zero ? const Offset(0, 1) : heading;

      BumperRenderer.drawBall(
        canvas,
        b.pos,
        b.radius,
        color,
        squash: stretch,
        stretchDir: stretchDir,
        lookDir: lookDir,
        ready: state?.ready ?? true,
        displayNumber: b.id + 1,
        face: _faceFor(b, state),
      );

      // SLINGSHOT telegraph: only while the player is actively pulling back —
      // the elastic band + dotted trajectory + power gauge show where and how
      // hard the launch will fire (bots never touch-aim, so they show nothing).
      if (state != null && state.aiming && state.hasPull) {
        BumperRenderer.drawSlingshot(
          canvas,
          b.pos,
          b.radius,
          color,
          aim: state.aim,
          power: state.pullFrac,
          // Finger-anchored, rotation-corrected pull (points opposite the launch)
          // so the band matches the resolved zone aim, not the raw finger px.
          pullBack: state.pullBackVec,
          maxPreviewLen: _previewMaxLen,
        );
      }
    }
  }

  /// The live expression for an alive ball: HAPPY while a star buff is up,
  /// SCARED once it has drifted out near the deadly edge, else the determined
  /// NEUTRAL face. (DIZZY is reserved for knocked-off flings.)
  BallFace _faceFor(Body b, BallState? state) {
    if (state != null && state.buffed) return BallFace.happy;
    final edgeDist = (b.pos - _center).distance;
    if (edgeDist > _currentRingRadius * _scaredEdgeFactor) {
      return BallFace.scared;
    }
    return BallFace.neutral;
  }

  /// Draw each knocked-off ball's send-off: the same glossy ball wearing a DIZZY
  /// face, tumbling and shrinking to nothing as it sails off (a transform-only
  /// reuse of [BumperRenderer.drawBall] — no new art).
  void _drawFlung(Canvas canvas) {
    for (final f in _flung) {
      final scale = f.strength; // 1 → 0 over its short life
      if (scale <= 0.02) continue;
      canvas.save();
      canvas.translate(f.pos.dx, f.pos.dy);
      canvas.rotate(f.spin);
      canvas.scale(scale);
      canvas.translate(-f.pos.dx, -f.pos.dy);
      BumperRenderer.drawBall(
        canvas,
        f.pos,
        f.radius,
        f.color,
        squash: 0,
        stretchDir: const Offset(1, 0),
        lookDir: const Offset(1, 0),
        ready: false,
        displayNumber: f.displayNumber,
        face: BallFace.dizzy,
      );
      canvas.restore();
    }
  }

  void _drawImpacts(Canvas canvas) {
    final maxR = _bodyRadius * _impactRingMaxFactor;
    for (final r in _impacts) {
      BumperRenderer.drawImpactRing(canvas, r.at, maxR, r.color, r.progress);
    }
  }

  // ── Small pure helpers ────────────────────────────────────────────────────────

  Body? _bodyOf(int id) {
    for (final b in _arena.bodies) {
      if (b.id == id) return b;
    }
    return null;
  }

  bool _isAlive(int id) => _bodyOf(id)?.alive ?? false;

  Color _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  /// Stable order-independent key for a pair of player ids (0..3).
  static int _pairKey(int a, int b) => a < b ? a * 8 + b : b * 8 + a;

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }

  // ── Test hooks (deterministic drive + read; never used in production) ────────

  /// Fire a SLINGSHOT for [playerId] at [aimAngle] (radians) with [power] (0..1,
  /// the pull fraction) — the same code path a human release takes, without
  /// scripting touch geometry. A no-op if the ball is dead / on cooldown /
  /// invulnerable. Lets a deterministic test drive a "measured slingshotter"
  /// (a strong aimed pull) vs a "blind tapper" (power 0) and compare outcomes.
  @visibleForTesting
  void debugLaunch(int playerId, double aimAngle, double power) {
    final self = _bodyOf(playerId);
    if (self == null || !self.alive) return;
    _launch(playerId, self, aimAngle, power);
  }

  /// Angle from [playerId]'s ball to the nearest alive rival (radians), or null
  /// when none remain — so a test can aim a measured shot at a real target.
  @visibleForTesting
  double? debugAimAtNearest(int playerId) => _aimAtNearest(playerId);

  /// The nearest alive rival's distance from centre as a fraction of the CURRENT
  /// (shrinking) ring radius — so a test can play the bank-shot skill of firing
  /// only when a rival is teetering near the edge (a likely KO). Null when no
  /// rival remains.
  @visibleForTesting
  double? debugNearestRivalEdgeFrac(int playerId) {
    final target = _nearestOpponentPos(playerId);
    if (target == null || _currentRingRadius <= 0) return null;
    return (target - _center).distance / _currentRingRadius;
  }

  /// This ball's own distance from centre as a fraction of the CURRENT ring
  /// radius (1 = at the rim). Lets a test keep a measured player off its own edge.
  @visibleForTesting
  double? debugSelfEdgeFrac(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null || _currentRingRadius <= 0) return null;
    return (self.pos - _center).distance / _currentRingRadius;
  }

  /// Distance (arena px) from [playerId]'s ball to the nearest alive rival, or
  /// null when none remain — so a test can fire only when a shot will connect.
  @visibleForTesting
  double? debugNearestRivalDist(int playerId) {
    final self = _bodyOf(playerId);
    final target = _nearestOpponentPos(playerId);
    if (self == null || target == null) return null;
    return (target - self.pos).distance;
  }

  /// The body radius (arena px) — lets a test scale a "close enough to connect"
  /// launch gate to the ball size.
  @visibleForTesting
  double get debugBodyRadius => _bodyRadius;

  /// The current ring-out score ( KOs caused minus self-ring penalties) for
  /// [playerId]. Mirrors the engine score; lets a test assert the spam-loses
  /// margin directly.
  @visibleForTesting
  double debugScoreOf(int playerId) => _ball[playerId]?.koScore ?? 0;

  /// How many static pegs are on the platform (for the peg-layout test).
  @visibleForTesting
  int get debugPegCount => _pegs.length;

  /// The peg centers (arena px) for the layout / spawn-clearance test.
  @visibleForTesting
  List<Offset> get debugPegPositions =>
      _pegs.map((p) => p.pos).toList(growable: false);

  /// A player's spawn point (arena px) so a test can check pegs stay clear.
  @visibleForTesting
  Offset? debugSpawnOf(int playerId) => _spawnPos[playerId];

  /// A player's ball position (arena px), or null if absent.
  @visibleForTesting
  Offset? debugBallPos(int playerId) => _bodyOf(playerId)?.pos;
}
