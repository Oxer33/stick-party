import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/push_arena.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'bumper_fx.dart';
import 'bumper_render.dart';

/// Bumper Balls — neon knockout. Every player is a glowing bumper ball on a
/// circular platform and shoves rivals off the edge.
///
/// SCORED BRAWL (not last-one-standing): the round runs the FULL [_timeLimit]
/// and your SCORE is the number of ring-outs you CAUSE. A knocked-off ball does
/// NOT end the round — it RESPAWNS ~[_respawnSec] later from its spawn edge with
/// a brief spawn-invuln, so a 1v1 becomes a sustained bumper match: knock the
/// rival off, it comes back, most ring-outs in [_timeLimit] wins. A ring-out
/// credits the LAST ball that bumped the victim; bumping YOURSELF off (no recent
/// attacker) scores nobody and docks a small penalty, so blind mash that rockets
/// you off the edge loses ground to paced, aimed caroms.
///
/// CONTROL (the heart of it — full player agency, one touch; the player owns
/// the aim, nothing auto-targets):
///  * DRAG from your ball in the direction you want to fire — the telegraph
///    follows your thumb, so YOU choose the angle every bump.
///  * HOLD builds a charge meter while you keep dragging to re-aim; longer hold
///    = harder bump (power ∝ charge).
///  * RELEASE → a charged release becomes a ROCKET DASH: the ball keeps its
///    momentum and stays bouncy for ~1s, so you carom off rivals (elastic
///    caroms) to knock them into the edge while you ricochet on — a real
///    "trick shot" decision instead of one dead-stop nudge.
///  * A committed HOLD-and-release with no drag fires at the nearest rival (a
///    kid-safe default that is EARNED by holding past [_autoAimMinCharge]). A
///    blind instant tap-mash does NOT get this assist: it fires in the ball's
///    stale aim with no retarget, so flailing whiffs and self-rings.
///
/// WHY SPAM LOSES (the design law): a KO ejection requires an AIMED + CHARGED
/// dash. Charging briefly ROOTS the ball ([_chargeRootRetain]) so a whiffed
/// charge is punishable; contact knockback that ejects a rival scales with the
/// attacker's COMMITTED charge ([_committedCharge]) so a weak/uncharged bump or a
/// stale carom can shove but never luck-launch; and only a committed charge arms
/// the momentum-keep rocket. A blind dasher out-scores nobody and self-rings on
/// the shrinking edge; an aimer who banks rivals into the rim wins.
///
/// Feel: a slick-but-grippy floor so bumps carry without instantly ejecting an
/// idle ball; elastic caroms (PushArena) plus a speed- and head-on-scaled
/// knockback bonus, so a fast square hit flings a rival much further than a
/// graze. Squash & stretch on impact, impact spark rings, motion trails, and a
/// platform that slowly shrinks after a grace period so matches always resolve.
///
/// Bots cannot drag, so they aim at the nearest opponent (via [_aimAtNearest]):
/// a short warmup, then approach with a light nudge and commit a charged rocket
/// only when close; near the edge they save themselves toward the centre.
/// [BotProfile] governs timing, charge and aim error so they read as deliberate,
/// not random — and never eject an idle player in the first several seconds.
class BumperBalls extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
    id: 'bumper_balls',
    name: 'Bumper Balls',
    minPlayers: 1,
    maxPlayers: 4,
    modes: [GameMode.ffa, GameMode.duel1v1],
    inputHint: 'DRAG / HOLD',
  );

  // ── Arena / sim tuning ──────────────────────────────────────────────────────
  // Device-tuned (matched to Sumo Smash) for a sustained ~28s match: small
  // bodies + big ring + grippy floor + a weak base bump so a single hit never
  // instantly ejects an idle ball; ring-outs come from positioning + charged
  // bumps near the edge. KO'd balls respawn, so the round always plays the FULL
  // limit instead of ending on the first knockout.
  static const double _timeLimit = 28;
  static const double _ringRadiusFactor = 0.46;
  static const double _bodyRadiusFactor = 0.05; // glossy bumper footprint
  static const double _ringFriction = 0.95; // grippy so bumps don't slide off
  static const double _ringRestitution = 0.92; // lively caroms, not chaotic
  static const double _spawnRadiusFactor = 0.55;

  // ── Aim + charge control tuning ─────────────────────────────────────────────
  // The aim is owned by the player's DRAG (see [_applyDragAim]); a bot or a
  // no-drag tap resolves it at fire time toward the nearest opponent.
  static const double _chargeTimeSec = 0.6; // hold time to full charge
  static const double _cooldownSec = 0.24; // snappy recovery between bumps
  static const double _dashBase = 1.4; // quick tap = a small nudge
  static const double _dashCharge = 3.8; // full hold = a strong launch
  static const double _selfPushback = 0.08; // recoil opposite the bump
  static const double _trailLifeSec = 0.2;
  static const double _maxSpeedRef =
      700.0; // speed mapped to full trail/stretch
  // Drag aim: the touch must move at least this far (fraction of the min screen
  // side) from the ball before it counts as a deliberate aim; a smaller wiggle
  // is treated as a no-drag tap (→ aim at nearest, a kid-safe default).
  static const double _aimDragDeadzone = 0.018;
  // ── COMMIT GATE (the design law: aim + charge, or whiff/self-ring) ───────────
  // The kid-safe "tap aims at the nearest rival" auto-assist is EARNED by
  // committing to a hold: only a release whose charge reached this threshold
  // gets the nearest-target fallback. An instant down→up MASH (no hold, no drag)
  // fires in the ball's *last committed* aim with NO retarget, so blind tap-spam
  // sprays stale-direction dashes that whiff — and self-ring on the closing edge
  // when the stale aim faces the rim. (Mirrors Sumo's earned auto-aim.)
  static const double _autoAimMinCharge = 0.18;
  // While charging, retain only this share of speed per 1/60s — a near-root so a
  // whiffed charge is punishable (the ball is briefly a sitting duck and cannot
  // mash its way across the platform). A real hold-to-commit COSTS position.
  static const double _chargeRootRetain = 0.62;

  // ── Rocket dash (the bumper differentiator) ─────────────────────────────────
  // A charged release tags the ball "launched": for [_launchSec] the game
  // counteracts ring-friction on it so it keeps its momentum and caroms off
  // rivals (elastic, restitution 0.92) — knocking them toward the edge while it
  // ricochets on — instead of one dead-stop nudge. Only a real charge arms it.
  static const double _launchSec =
      1.0; // momentum-keep window after a charged bump
  // Arm the momentum-keep ROCKET only on a COMMITTED charge (== the contact
  // commit gate), so an under-committed dash both whiffs its eject bonus AND
  // dead-stops on contact (no fast carom) — a blind/weak dash cannot keep speed
  // to luck-launch a rival. Skill (a real hold) is what buys the trick-shot.
  static const double _launchChargeMin = 0.5; // == _committedCharge
  static const double _launchFrictionRetain =
      0.992; // per-1/60s speed kept while launched
  static const double _launchMaxSpeed =
      1100.0; // cap so a rocket never runs away

  // ── Knockback (contact) tuning ──────────────────────────────────────────────
  static const double _contactSpeedRef =
      700.0; // speed mapped to full knockback
  static const double _contactBonusScale =
      0.28; // bonus impulse / attacker speed
  static const double _headOnExtra = 0.85; // extra multiplier for a head-on hit
  static const double _heavyHitSpeed = 380.0; // above → heavy shake + hit-stop
  static const double _squashOnHit = 0.42; // squash amount stamped on impact
  static const double _squashDecayPerSec = 3.2; // how fast squash relaxes
  static const double _impactRingLifeSec = 0.32;
  static const double _impactRingMaxFactor = 2.4; // ring max radius / body R
  // ── COMMIT GATE on contact knockback (the anti-luck-launch rule) ─────────────
  // An UNCHARGED bump (below [_committedCharge]) transfers only
  // [_weakHitKnockbackFloor] of its eject impulse, so a weak/incidental nudge —
  // or a fast carom that wasn't an aimed commit — can shove a rival but cannot
  // luck-launch them off the ring. Only a committed (charged) dash ejects.
  // Scales linearly to full at [_committedCharge]. (Mirrors Sumo's commit gate.)
  static const double _weakHitKnockbackFloor = 0.35;
  static const double _committedCharge = 0.5;

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
  static const double _selfRingPenalty = 1.0; // score docked for a self-ring-out

  // ── Expression tuning ────────────────────────────────────────────────────────
  static const double _scaredEdgeFactor = 0.78; // dist/ring above → looks scared

  // ── Bot tuning (mirrors Sumo's fair model) ──────────────────────────────────
  static const double _botWarmupSec = 2.0; // grace before bots engage
  static const double _botCloseRangeFactor = 4.2; // approach vs shove threshold
  static const double _botEdgeBackoff =
      0.62; // dist/ring above → retreat inward
  static const double _botAimErrorRad = 0.55; // max aim jitter at accuracy 0
  static const double _botCarrySpeed = 120.0; // skip bump while already fast
  static const double _botSaveCharge = 0.5; // charge used to save off the edge
  static const double _botApproachCharge =
      0.06; // light nudge to close distance
  // Charge band for a close-range bot dash, scaled by accuracy in [_botDecide]
  // so the COMMIT GATE makes a real skill gradient: a HARD bot reliably clears
  // [_committedCharge] (lands ejects), an EASY bot stays under it (weak shoves
  // that rarely KO — beatable by a human who aims charged dashes).
  static const double _botShoveChargeMin = 0.25; // floor of the band
  static const double _botShoveChargeMax = 0.7; // hard-bot reach (> commit gate)

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

  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, BallState> _ball = <int, BallState>{};
  final Set<int> _ragdolled = <int>{}; // bodies currently knocked off (respawning)
  final List<ImpactRing> _impacts = <ImpactRing>[];

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
    _seedMotes();
    begin();
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

  // ── Input: hold to charge + aim, release to bump (mirrors Sumo) ─────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final s = _ball[input.playerId];
    final body = _bodyOf(input.playerId);
    if (s == null || body == null || !body.alive) return;

    switch (input.phase) {
      case InputPhase.down:
        if (s.ready && !s.invulnerable) {
          s.charging = true; // begin charging
          s.hasDragAim = false; // no chosen direction until the thumb moves
          _applyDragAim(input, body, s); // a press already away from us aims
        }
      case InputPhase.holdTick:
        // A drag sample re-aims toward the thumb (the player owns the angle).
        _applyDragAim(input, body, s);
      case InputPhase.up:
        if (s.charging) {
          s.charging = false;
          _applyDragAim(input, body, s); // final flick can still steer
          // Aim resolution (the heart of the skill gate):
          //  * a thumb-chosen drag aim ALWAYS wins (full agency); else
          //  * the kid-safe nearest-rival auto-assist is unlocked ONLY by a
          //    committed hold (charge >= [_autoAimMinCharge]); else
          //  * a pure instant down→up MASH keeps the ball's *last* aim with NO
          //    retarget — so blind tap-spam sprays stale-direction dashes that
          //    whiff (and self-ring when the stale aim faces the closing edge).
          final earnedAssist = s.charge >= _autoAimMinCharge;
          final aim = s.hasDragAim
              ? s.aim
              : (earnedAssist ? (_aimAtNearest(input.playerId) ?? s.aim) : s.aim);
          _commitDash(input.playerId, body, aim, s.charge);
          s.charge = 0;
          s.hasDragAim = false;
        }
    }
  }

  /// Set the ball's aim from the drag vector (touch [input.normPos] relative to
  /// the ball), in true screen pixels so the angle is not skewed by the portrait
  /// aspect. A move shorter than [_aimDragDeadzone] (or a synthetic hold-tick
  /// with no position) is ignored, leaving any prior chosen aim — or the
  /// nearest-opponent fallback — intact.
  void _applyDragAim(PlayerInput input, Body body, BallState s) {
    if (!s.charging) return;
    final touch = Offset(
      input.normPos.dx * _size.width,
      input.normPos.dy * _size.height,
    );
    final d = touch - body.pos;
    final minSide = math.min(_size.width, _size.height);
    if (d.distance < minSide * _aimDragDeadzone) return;
    s.aim = math.atan2(d.dy, d.dx);
    s.hasDragAim = true;
  }

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
    _collectStars();
    _resolveContacts();
    _detectRingOuts();
    _resolveOutcome();
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

  /// Fill charge while held, relax squash, age the trail + launch window and
  /// recover cooldown — all frame-rate independent. The aim is NOT touched here:
  /// it is owned by the player's drag (see [_applyDragAim]).
  ///
  /// Two skill gates run here every charging frame:
  ///  * CHARGE-ROOT: a charging ball is slowed to a near-stop ([_chargeRootRetain])
  ///    so committing to a hold COSTS position — a whiffed/mashed charge leaves
  ///    the ball a sitting duck instead of skating across the platform.
  ///  * EARNED nearest-preview: the telegraph only snaps to the nearest rival
  ///    once the hold has earned the auto-assist ([_autoAimMinCharge]); below
  ///    that it holds the stale aim, so an instant tap that releases before
  ///    committing fires unaimed (the skill gate is honest, not a free retarget
  ///    on the very first flick frame).
  void _tickBallStates(double dt) {
    for (final entry in _ball.entries) {
      final s = entry.value;
      if (_isAlive(entry.key) && s.charging) {
        s.charge = math.min(1.0, s.charge + dt / _chargeTimeSec);
        if (!s.hasDragAim && s.charge >= _autoAimMinCharge) {
          final a = _aimAtNearest(entry.key);
          if (a != null) s.aim = a;
        }
        final body = _bodyOf(entry.key);
        if (body != null && body.vel != Offset.zero) {
          final retain = math.pow(_chargeRootRetain, dt * 60.0).toDouble();
          body.vel = body.vel * retain;
        }
      }
      s.tick(dt, _squashDecayPerSec);
    }
  }

  /// Angle from a ball to the nearest alive opponent, or null when none remain
  /// (e.g. the last ball standing) — then the aim simply holds its last heading.
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

  /// Bots pick an aim + charge and commit a bump directly (no hold sim).
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    final s = _ball[playerId];
    if (self == null || !self.alive || s == null || !s.ready) return;
    if (s.invulnerable) return; // just respawned — settle before engaging
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return; // hesitate / mistake

    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    final err = (1.0 - acc) * _botAimErrorRad;

    // Near the edge: a competent bot saves itself with a dash back toward the
    // centre — but a LOW-ACCURACY (easy) bot mis-judges the save by [err], so it
    // can over-commit at an angle and fling ITSELF off the rim. Skill (accuracy)
    // buys a clean recovery; a weak bot self-rings, exactly the beatable
    // behaviour the human exploits. The save is charged enough to carry inward.
    if (_isNearEdge(self)) {
      final aim =
          math.atan2(_center.dy - self.pos.dy, _center.dx - self.pos.dx) +
          ctx.rng.jitter(err);
      s.aim = aim;
      _commitDash(playerId, self, aim, _botSaveCharge + 0.25 * acc);
      return;
    }

    // Don't waste a bump while already carrying lots of speed.
    if (self.vel.distance > _botCarrySpeed) return;

    final targetPos = _nearestOpponentPos(playerId);
    if (targetPos == null) return;

    final to = targetPos - self.pos;
    final aim = math.atan2(to.dy, to.dx) + ctx.rng.jitter(err);
    // Far → a light nudge to close in; close → a charged dash into the rival.
    // The attack charge scales with accuracy so the COMMIT GATE creates a real
    // skill gradient: a HARD bot (high accuracy) charges past [_committedCharge]
    // and lands true ring-out launches, while an EASY bot mostly stays under it
    // — its weak, mis-aimed dashes shove but rarely eject, so a human who aims
    // charged dashes out-KOs it. (Mirrors the human's own hold-to-commit cost.)
    final charge = to.distance > _bodyRadius * _botCloseRangeFactor
        ? _botApproachCharge
        : (_botShoveChargeMin +
                  (_botShoveChargeMax - _botShoveChargeMin) *
                      acc *
                      ctx.rng.range(0.7, 1.0))
              .clamp(0.0, 1.0);
    s.aim = aim;
    _commitDash(playerId, self, aim, charge);
  }

  /// Shared bump commit: an aimed impulse of the given [charge] (0..1) in
  /// [aimAngle], a small self-recoil, cooldown, trail, a forward stretch hint
  /// and a directional spark telegraph. Used by humans and bots so the feel
  /// matches exactly.
  void _commitDash(int playerId, Body self, double aimAngle, double charge) {
    final s = _ball[playerId];
    if (s == null || !s.ready || s.invulnerable) return;

    final dir = Offset(math.cos(aimAngle), math.sin(aimAngle));
    // A collected star briefly amplifies every bump — the buffed ball hits
    // noticeably harder, the core of the chaos swing.
    final buffMul = s.buffed ? _buffDashMul : 1.0;
    final magnitude =
        _ringRadius * (_dashBase + _dashCharge * charge) * buffMul;
    _arena.impulse(playerId, dir * magnitude);
    _arena.impulse(playerId, -dir * magnitude * _selfPushback);

    // Contact knockback reads this: only a COMMITTED (charged) dash ejects a
    // rival; a blind uncharged tap marks ~0 and so cannot luck-launch anyone.
    s.markBump(charge);
    s.fire(_cooldownSec);
    s.trail = DashTrail(dir: dir, life: _trailLifeSec);
    s.stretchDir = dir;
    // A charged release arms the ROCKET DASH: a momentum-keep window so the ball
    // caroms off rivals toward the edge. A light tap (low charge) does not.
    if (charge >= _launchChargeMin) s.launch = _launchSec;

    final intensity = 0.5 + 0.5 * charge;
    _juice.particles.burst(
      at: self.pos - dir * _bodyRadius,
      count: (6 + 8 * charge).round(),
      color: _colorOf(playerId),
      speed: 200 * intensity,
      baseAngle: math.atan2(-dir.dy, -dir.dx),
      spread: math.pi * 0.7,
      size: 4,
      gravity: 120,
      life: 0.3,
    );
    _juice.hit(self.pos, _colorOf(playerId), sparks: (3 + 4 * charge).round());
    if (charge > 0.6) _juice.shake.light();
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
    // COMMIT GATE: a blind, uncharged bump transfers only [_weakHitKnockbackFloor]
    // of its eject impulse; a fully committed (charged) dash transfers the full
    // hit. So a rival is launched off the ring only by an *aimed, charged* dash —
    // an incidental bump or a stale carom can shove someone but not eject them,
    // which is what makes button-spam unable to luck-KO. A star-buffed attacker
    // always counts as committed (the buff IS the commitment).
    final atkS = _ball[attacker.id];
    final commit = (atkS?.buffed ?? false)
        ? 1.0
        : (atkS == null
              ? 1.0
              : (atkS.committedCharge / _committedCharge).clamp(0.0, 1.0));
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
        ..charging = false
        ..hasDragAim = false
        ..charge = 0
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

      // No idle arrow. While charging, a telegraph points the way the player is
      // dragging (where the bump will fire) with a charge ground-arc.
      if (state != null && state.charging) {
        BumperRenderer.drawAim(
          canvas,
          b.pos,
          b.radius,
          color,
          aim: state.aim,
          charge: state.charge,
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
}
