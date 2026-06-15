import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../art/fx/juice.dart';
import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/push_arena.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'sumo_fx.dart';
import 'sumo_render.dart';

/// Sumo Smash — "Schianto & Brace": a readable LUNGE-vs-BRACE mind-game in a
/// circular dohyo. Not shove-spam — a duel of reads.
///
/// SCORED BRAWL (kept from the original): the round runs the FULL [_timeLimit]
/// and your SCORE is the number of ring-outs you CAUSE. A knocked-out wrestler
/// does NOT end the round — it RESPAWNS ~[_respawnSec] later, flung back in from
/// its spawn edge with a brief spawn-invuln, so a 1v1 becomes a sustained duel:
/// ring the rival, it comes back, most KOs in [_timeLimit] wins. A ring-out
/// credits the LAST wrestler who launched the victim; ringing YOURSELF out (no
/// recent attacker) scores nobody and docks [_selfRingPenalty].
///
/// CONTROL — one touch, two intents (the heart of it):
///  * SHORT TAP (down→up within [_braceThresholdSec]) = **LUNGE**: one strong
///    committed dash in the aim direction (aim = your drag if the finger dragged
///    past the deadzone, else auto toward the nearest opponent — kid-safe). A
///    lunge is followed by a **RECOVERY** window ([_recoverySec]): you cannot act
///    and you decelerate. That recovery IS the commitment cost.
///  * HOLD (finger stays down past [_braceThresholdSec]) = **BRACE**: plant your
///    feet. While braced you are rooted (near-immovable) and incoming knockback
///    is cut to [_braceKnockbackRetain]. Releasing a brace does NOT fire a lunge.
///
/// THE READ (core fun): a LUNGE into a BRACED foe → the LUNGER is REPELLED
/// backward + STUNNED ([_stunSec], exposed, can't act, drifts) and the braced
/// foe barely moves. A LUNGE into a NON-braced / moving foe → LAUNCHES them
/// (ring-out). So you bait the brace, wait for the drop, then lunge. Bracing too
/// early/long means you cannot attack while a smart foe repositions.
///
/// WHY SPAM LOSES (a tested design law): each lunge exposes a recovery window;
/// lunging into a braced/aware opponent is repelled + stunned and drifts toward
/// the rim → you self-ring. A blind masher who only lunges therefore loses to a
/// measured player who baits, braces and counters.
///
/// Feel: low-friction clay so a launch carries the victim off the ring; the
/// dohyo shrinks after a grace (SUDDEN DEATH) so the late duel tightens; the
/// star pickup buffs your next lunges. FINAL TWO / WINNER confetti spectacle.
///
/// Bots cannot drag, so they aim at the nearest opponent and either BRACE (when
/// a foe is lunging at them, reaction/accuracy gated) or LUNGE (when a foe is in
/// range and not braced). Easy bots mistime (lunge into braces, brace at random,
/// mis-aim); hard bots read well. [BotProfile] + [ReactionClock] + a warmup
/// grace govern timing so they never instantly ring an idle human.
class SumoSmash extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
    id: 'sumo_smash',
    name: 'Sumo Smash',
    minPlayers: 1,
    maxPlayers: 4,
    modes: [GameMode.ffa, GameMode.duel1v1],
    inputHint: 'TAP / HOLD',
  );

  // ── Arena / sim tuning ──────────────────────────────────────────────────────
  // Tuned for a sustained ~28s duel: small bodies + big ring + grippy clay so a
  // stray bump never ejects an idle player; ring-outs come from a committed
  // lunge into an unbraced foe near the edge. KO'd wrestlers respawn, so the
  // round always plays the FULL limit.
  static const double _timeLimit = 28;
  static const double _ringRadiusFactor = 0.46;
  static const double _bodyRadiusFactor = 0.05;
  static const double _ringFriction = 0.96; // settles fast, less idle slide-off
  static const double _ringRestitution = 0.9;
  static const double _spawnRadiusFactor = 0.55;

  // ── Lunge / brace control tuning ─────────────────────────────────────────────
  // Down→up within this is a TAP → LUNGE; holding past it plants a BRACE.
  static const double _braceThresholdSec = 0.16;
  // One committed lunge DASH: the SET launch speed (× ringRadius). The dash runs
  // at full speed for [_lungeCarrySec], then RECOVERY brakes it hard — so a lunge
  // is a punchy BOUNDED dash (it closes a combat gap and slams a foe, ejecting an
  // unbraced rival near the rim) that does NOT coast across the whole ring and
  // off the far edge. Over-committing only self-rings you when you lunge while
  // ALREADY near the rim — a positioning mistake, not every lunge.
  static const double _lungeImpulse = 3.1; // × ringRadius (peak dash speed)
  static const double _lungeSelfPushback = 0.06; // tiny recoil opposite a lunge
  // After a lunge: cannot act for this long (the commitment cost). The dash
  // carries free for [_lungeCarrySec] then the rest of recovery brakes it.
  static const double _recoverySec = 0.35;
  static const double _lungeCarrySec = 0.13; // full-speed dash window
  static const double _lungeBrakeRetain = 0.55; // speed kept per 1/60s post-carry
  // While braced, retain only this share of incoming knockback (near-immovable),
  // and root the body to a hard stop so a braced wrestler holds the centre.
  static const double _braceKnockbackRetain = 0.10;
  static const double _braceRootRetain = 0.55; // speed kept per 1/60s when braced
  // A LUNGE into a BRACED foe repels the lunger backward this hard and stuns it.
  // Tuned (above the ~2.5 starting point) so a repelled lunger reliably slides
  // toward — and often off — the rim during its stun: that is the decisive
  // punishment that makes blind lunging into a wall LOSE. The stun outlasts the
  // typical slide so the masher cannot re-aim inward to save itself mid-flight.
  static const double _repelImpulse = 3.2; // × ringRadius
  static const double _stunSec = 0.6; // repelled-lunger lockout (drifts, exposed)
  // Drag aim: the touch must travel at least this far (fraction of the min screen
  // side) from the press point before it counts as a deliberate aim; a smaller
  // wiggle is a no-drag tap (→ aim at nearest, the kid-safe default).
  static const double _aimDragDeadzone = 0.018;
  static const double _trailLifeSec = 0.26;

  // ── Knockback (contact) tuning ──────────────────────────────────────────────
  // A launch's strength scales with the lunger's contact speed; only a body that
  // is mid-lunge launches a victim off the ring. An incidental bump (no active
  // lunge) transfers only [_idleHitFloor] of the knockback so it cannot luck-KO.
  static const double _contactSpeedRef = 760.0;
  static const double _contactBonusScale = 0.30;
  static const double _headOnExtra = 0.85;
  static const double _heavyHitSpeed = 380.0;
  static const double _idleHitFloor = 0.22; // non-lunge bump knockback share
  // Contact is detected within this × the summed radii. A margin > 1 catches the
  // frame the bodies are closest even though the arena's own elastic step has
  // already nudged them apart, so the LUNGE-vs-BRACE read never slips through.
  static const double _contactMargin = 1.3;

  // ── Shrinking ring tuning ───────────────────────────────────────────────────
  static const double _shrinkDelaySec = 9.0;
  static const double _minRingFactor = 0.5;
  static const double _shrinkPerSec = 0.024;

  // ── Climax (sudden death) tuning ────────────────────────────────────────────
  static const double _suddenDeathFrac = 0.72; // enters at this share of time
  static const double _suddenDeathShrinkMul = 2.6;
  static const double _suddenDeathFloorMul = 0.78;
  static const double _showdownMargin = 1.0; // within this many KOs of the lead

  // ── Star pickup (chaos) tuning ──────────────────────────────────────────────
  // One star floats near the centre; grabbing it buffs your next lunges. Any
  // wrestler can take it, so it creates a scramble + swings.
  static const double _starRadiusFactor = 0.55;
  static const double _starFirstSpawnSec = 4.0;
  static const double _starRespawnSec = 7.5;
  static const double _starSpawnSpreadFactor = 0.42;
  static const double _starAppearPerSec = 3.0;
  static const double _starSpinPerSec = 3.2;
  static const double _starLifeSec = 6.0;
  static const double _buffSec = 4.0; // how long the lunge buff lasts
  static const double _buffLungeMul = 1.55; // lunge magnitude × this while buffed

  // ── Kid-assist (comeback) tuning ────────────────────────────────────────────
  // A wrestler teetering in the last sliver before the edge while moving SLOWLY
  // gets a gentle inward brake — a young player merely drifting out is nudged
  // back, but a genuine launch (fast) still ejects them.
  static const double _rescueBandFactor = 0.93;
  static const double _rescueMaxSpeed = 150.0;
  static const double _rescueBrakePerSec = 2.6;

  // ── Ring-out fling tuning ───────────────────────────────────────────────────
  static const double _flingBaseFactor = 0.5;
  static const double _flingSpeedFactor = 0.55;

  // ── Scored brawl: KO credit + respawn ───────────────────────────────────────
  static const double _respawnSec = 1.2; // delay before a KO'd wrestler returns
  static const double _spawnInvulnSec = 0.9; // post-respawn grace (no KO either way)
  static const double _attackerCreditSec = 1.1; // a hit credits a KO this recently
  static const double _selfRingPenalty = 1.0; // score docked for a self-ring-out

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botWarmupSec = 2.0; // grace before bots engage
  static const double _botLungeRangeFactor = 3.6; // lunge when foe within this×bodyR
  static const double _botApproachRangeFactor = 8.0; // dash to close within this×bodyR
  static const double _botEdgeBackoff = 0.62; // dist/ring above → save inward
  static const double _botAimErrorRad = 0.55; // max aim jitter at accuracy 0
  static const double _botCarrySpeed = 120.0; // skip act while already fast
  // How long a bot holds a defensive BRACE once it commits to one (then it must
  // re-read). Short, so a braced bot is not a wall — a measured human waits it
  // out and lunges the moment it drops.
  static const double _botBraceHoldSec = 0.42;
  // A bot only reacts to an incoming lunge it can actually "see": the threat
  // must be inside this range (×bodyR) AND roughly aimed at the bot.
  static const double _botThreatRangeFactor = 5.5;
  static const double _botThreatAimDot = 0.35; // min alignment to read a threat

  // ── Figure build ────────────────────────────────────────────────────────────
  static const double _figureScale = 1.25;
  static const double _torsoWiden = 1.8;
  static const double _limbWiden = 1.55;
  static const double _runSpeed = 40.0;

  // ── Visuals ─────────────────────────────────────────────────────────────────
  static const Color _accent = Color(0xFFFFC062);
  static const Color _starColor = Color(0xFFFFE45C); // pickup gold
  static const Color _braceColor = Color(0xFF7FE3FF); // cool shield blue
  static const int _dustMotes = 22;

  late Juice _juice;
  late PushArena _arena;
  double _elapsed = 0;
  double _animClock = 0;

  late Size _size;
  late Offset _center;
  late double _ringRadius;
  late double _currentRingRadius;
  late double _bodyRadius;
  late StickProportions _proportions;
  late double _footReach;

  final Map<int, StickFigure> _figures = <int, StickFigure>{};
  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final Map<int, _Fighter> _fighters = <int, _Fighter>{};
  final Set<int> _ragdolled = <int>{}; // bodies currently flung out (visual)
  final Set<int> _contactPairs = <int>{}; // launch-contact debounce (post-step)
  final Set<int> _braceContacts = <int>{}; // brace-read debounce (pre-step)
  final List<Offset> _dust = <Offset>[];

  /// Spawn position per player, reused to fling a respawn back in from its edge.
  final Map<int, Offset> _spawnPos = <int, Offset>{};

  /// KO'd wrestlers waiting to respawn (id → seconds remaining).
  final Map<int, double> _respawnTimers = <int, double>{};

  late StarController _stars;
  bool _suddenDeathAnnounced = false;
  bool _showdownAnnounced = false; // one-shot: the FINAL-2 KO-race callout
  bool _winnerCheered = false; // one-shot: the leader cheers when time expires

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
    _proportions = _sumoProportions();
    _footReach = _proportions.thigh + _proportions.shin;

    // The arena's own ring-falloff must NOT cull bodies: this game owns
    // elimination via [_detectRingOuts] against the *shrinking* radius so the KO
    // juice, ragdoll fling and credit all fire. Use a radius beyond the screen
    // so the arena never falls a body off.
    _arena = PushArena(
      center: _center,
      ringRadius: _size.width + _size.height,
      friction: _ringFriction,
      restitution: _ringRestitution,
    );

    _buildBodies();
    _seedDust();
    begin();
  }

  void _buildBodies() {
    final count = ctx.players.length;
    final spawnRadius = _ringRadius * _spawnRadiusFactor;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      // Start at +90° (bottom) so player 0 spawns in their own bottom zone and
      // 2-player duels face off north/south up the tall screen.
      final angle = (i / count) * math.pi * 2 + math.pi / 2;
      final pos =
          _center + Offset(math.cos(angle), math.sin(angle)) * spawnRadius;
      _spawnPos[p.id] = pos;
      _arena.add(Body(id: p.id, pos: pos, radius: _bodyRadius));

      final facing = pos.dx <= _center.dx ? 1.0 : -1.0;
      _figures[p.id] = StickFigure(
        proportions: _proportions,
        style: _styleFor(Color(p.colorArgb)),
        facing: facing,
      )..setLoco(LocoState.idle);

      // Aim starts pointing toward the centre so the first lunge is sensible.
      final towardCenter = math.atan2(_center.dy - pos.dy, _center.dx - pos.dx);
      _fighters[p.id] = _Fighter(aim: towardCenter);
      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
      }
    }
  }

  StickProportions _sumoProportions() {
    final base = StickProportions.hero.scaled(_figureScale);
    return StickProportions(
      spine: base.spine,
      neck: base.neck,
      head: base.head,
      upperArm: base.upperArm,
      foreArm: base.foreArm,
      thigh: base.thigh,
      shin: base.shin,
      torsoWidth: base.torsoWidth * _torsoWiden,
      limbWidth: base.limbWidth * _limbWiden,
    );
  }

  StickStyle _styleFor(Color color) => StickStyle(
    fill: color,
    outline: _brighten(color, 0.45),
    glowSigma: 5,
    lineWidth: 1.1,
    rimAlpha: 0.3,
    shadowAlpha: 0.0,
    gradientBottom: 0.5,
    smearAlpha: 0.28,
  );

  void _seedDust() {
    final rng = ctx.rng;
    for (var i = 0; i < _dustMotes; i++) {
      _dust.add(Offset(rng.range(0, _size.width), rng.range(0, _size.height)));
    }
  }

  // ── Input: tap = lunge, hold = brace ─────────────────────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final f = _fighters[input.playerId];
    final body = _bodyOf(input.playerId);
    if (f == null || body == null || !body.alive) return;

    switch (input.phase) {
      case InputPhase.down:
        // Begin a press. We do not yet know tap-vs-hold; that is decided on
        // release (or when the hold crosses the brace threshold mid-press).
        if (f.canAct) {
          f.pressing = true;
          f.pressHeld = 0;
          f.hasDragAim = false; // a plain tap stays on the nearest-rival aim
          f.downPos = Offset(
            input.normPos.dx * _size.width,
            input.normPos.dy * _size.height,
          );
        }
      case InputPhase.holdTick:
        // A real DRAG (finger travels from the press point) re-aims by hand.
        _applyDragAim(input, body, f);
      case InputPhase.up:
        if (!f.pressing) break;
        _applyDragAim(input, body, f); // a final flick can still steer the lunge
        final wasBracing = f.bracing;
        final held = f.pressHeld;
        f.pressing = false;
        f.bracing = false;
        if (!wasBracing && held < _braceThresholdSec) {
          // SHORT TAP → LUNGE. A deliberate drag aims by hand; a plain tap
          // lunges at the nearest rival (readable + kid-safe).
          final aim =
              f.hasDragAim ? f.aim : (_aimAtNearest(input.playerId) ?? f.aim);
          _commitLunge(input.playerId, body, aim);
        }
        // Releasing a brace fires nothing — the wrestler simply unplants.
        f.hasDragAim = false;
    }
  }

  /// Set the fighter's aim from the drag vector (touch [input.normPos] relative
  /// to the wrestler), in true screen pixels so the angle is not skewed by the
  /// portrait aspect. A move shorter than [_aimDragDeadzone] (or a synthetic
  /// hold-tick with no position) is ignored, leaving the prior chosen aim — or
  /// the nearest-opponent fallback — intact.
  void _applyDragAim(PlayerInput input, Body body, _Fighter f) {
    if (!f.pressing) return;
    if (input.normPos == Offset.zero) return; // a bare per-frame tick has no pos
    final touch = Offset(
      input.normPos.dx * _size.width,
      input.normPos.dy * _size.height,
    );
    final minSide = math.min(_size.width, _size.height);
    if ((touch - f.downPos).distance < minSide * _aimDragDeadzone) return;
    f.aim = math.atan2(touch.dy - body.pos.dy, touch.dx - body.pos.dx);
    f.hasDragAim = true;
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _tickFighters(dt);
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

    // THE READ must be resolved BEFORE the arena integrates/collides: a lunge
    // into a brace cancels the lunger's velocity (so the arena cannot then
    // transfer its momentum into the rooted foe) and repels + stuns the lunger.
    _resolveBraceReads();

    _arena.update(sdt);

    SumoFx.applyRescueAssist(
      _arena.aliveBodies,
      _center,
      _currentRingRadius,
      bandFactor: _rescueBandFactor,
      maxSpeed: _rescueMaxSpeed,
      brakePerSec: _rescueBrakePerSec,
      dt: sdt,
    );
    _collectStars();
    _resolveContacts();
    _syncFigures(sdt);
    _detectRingOuts();
    _resolveOutcome();
  }

  /// True once the match has entered its climax (sudden death) window.
  bool get _isSuddenDeath => _elapsed >= _timeLimit * _suddenDeathFrac;

  /// Advance per-fighter timers and mode transitions. While PRESSING, a hold that
  /// crosses [_braceThresholdSec] plants a BRACE (rooted). BRACE/RECOVERY/STUN all
  /// damp velocity so those states read as committed and are punishable.
  void _tickFighters(double dt) {
    for (final entry in _fighters.entries) {
      final id = entry.key;
      final f = entry.value;
      final body = _bodyOf(id);
      final alive = body?.alive ?? false;
      final isBot = _botClocks.containsKey(id);

      if (alive && f.pressing) {
        f.pressHeld += dt;
        if (!f.bracing && f.pressHeld >= _braceThresholdSec) {
          f.bracing = true; // held long enough → plant the brace
          final fig = _figures[id];
          if (fig != null && !fig.actionPlaying) fig.hurt(); // arms-up plant tell
        }
        // A no-drag press tracks the nearest rival so the aim arrow always shows
        // where a release-as-lunge would fire.
        if (!f.hasDragAim) {
          final a = _aimAtNearest(id);
          if (a != null) f.aim = a;
        }
      } else if (alive && !isBot && f.canAct) {
        // Idle preview: a ready human's aim tracks the nearest rival so the faint
        // "lunge here" arrow is always shown (teaches the control at a glance).
        final a = _aimAtNearest(id);
        if (a != null) f.aim = a;
      }

      // Velocity damping for the committed states:
      //  * BRACE roots the body to a near-stop (holds the centre).
      //  * a LUNGE dash brakes hard once its free-carry window has elapsed, so
      //    the dash is bounded (it won't coast off the far rim).
      //  * STUN adds no braking — a repelled lunger keeps sliding toward the rim
      //    (the punishment), and a clean recovery after carry is already braked.
      if (alive && body != null) {
        if (f.bracing) {
          body.vel *= math.pow(_braceRootRetain, dt * 60.0).toDouble();
        } else if (!f.stunned && f.recovery > 0 && f.lungeCarry <= 0) {
          body.vel *= math.pow(_lungeBrakeRetain, dt * 60.0).toDouble();
        }
      }
      f.tick(dt);
    }
  }

  /// Angle from a player to the nearest alive opponent, or null if none.
  double? _aimAtNearest(int playerId) {
    final self = _bodyOf(playerId);
    final target = _nearestOpponentPos(playerId);
    if (self == null || target == null) return null;
    final d = target - self.pos;
    if (d.distance < 1e-6) return null;
    return math.atan2(d.dy, d.dx);
  }

  void _driveBots(double dt) {
    if (_elapsed < _botWarmupSec) return; // let the human get a beat first
    for (final entry in _botClocks.entries) {
      final id = entry.key;
      final f = _fighters[id];
      if (!_isAlive(id) || f == null) continue;

      // A committed defensive brace auto-releases after a short hold so a bot is
      // never a permanent wall — it must re-read and a human can wait it out.
      if (f.bracing) {
        f.botBraceTimer -= dt;
        if (f.botBraceTimer <= 0) {
          f.pressing = false;
          f.bracing = false;
        }
        continue;
      }
      if (!entry.value.tick(dt)) continue;
      entry.value.arm(ctx.botProfile, ctx.rng);
      _botDecide(id);
    }
  }

  /// Bots read the duel: BRACE a threat (a foe lunging at them) when they react
  /// in time, else LUNGE a foe in range that is not bracing, else nudge-approach.
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    final f = _fighters[playerId];
    if (self == null || !self.alive || f == null || !f.canAct) return;
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return; // hesitate / mistake

    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    final err = (1.0 - acc) * _botAimErrorRad;

    // 1) DEFENSE — is someone lunging at me? A skilled bot reads it and braces;
    // a weak bot misses the read (low accuracy → low brace chance) and eats it.
    final threat = _incomingThreat(playerId);
    if (threat != null && ctx.rng.chance(0.35 + 0.6 * acc)) {
      _botStartBrace(f);
      return;
    }

    // 2) EDGE SAVE — near the rim, lunge back toward the centre to recover. A
    // low-accuracy bot mis-judges the save by [err] and can over-commit off the
    // edge — exactly the beatable behaviour the human exploits.
    if (_isNearEdge(self)) {
      final aim = math.atan2(
            _center.dy - self.pos.dy,
            _center.dx - self.pos.dx,
          ) +
          ctx.rng.jitter(err);
      f.aim = aim;
      _commitLunge(playerId, self, aim);
      return;
    }

    if (self.vel.distance > _botCarrySpeed) return; // ride out current motion

    // 3) OPPORTUNITY — a foe that is EXPOSED (stunned / mid-recovery) and within
    // striking range is a free, clean launch; a competent bot pounces. This is
    // the main source of credited ring-outs in bot play. Easy bots still hesitate
    // (errorRate above) and mis-aim ([err]), so they cash fewer of these.
    final exposed = _nearestExposedOpponent(
        playerId, _bodyRadius * _botLungeRangeFactor);
    if (exposed != null) {
      final ep = _bodyOf(exposed)!.pos;
      final ea = math.atan2(ep.dy - self.pos.dy, ep.dx - self.pos.dx) +
          ctx.rng.jitter(err);
      f.aim = ea;
      _commitLunge(playerId, self, ea);
      return;
    }

    final targetId = _nearestOpponentId(playerId);
    final targetPos = targetId == null ? null : _bodyOf(targetId)?.pos;
    if (targetPos == null) return;
    final to = targetPos - self.pos;
    final dist = to.distance;
    final aim = math.atan2(to.dy, to.dx) + ctx.rng.jitter(err);
    f.aim = aim;

    // 4) ATTACK — a foe in lunge range. A SKILLED bot only lunges when the foe is
    // NOT bracing (a read it wins by accuracy); a WEAK bot lunges anyway and gets
    // repelled + stunned, drifting toward the rim.
    if (dist <= _bodyRadius * _botLungeRangeFactor) {
      final targetBracing = _fighters[targetId]?.bracing ?? false;
      final readsTheBrace = ctx.rng.chance(acc); // skill = seeing the brace
      if (targetBracing && readsTheBrace) {
        // Saw the brace → hold (don't feed a stun). A patient bot beats a wall.
        return;
      }
      _commitLunge(playerId, self, aim);
      return;
    }

    // 5) APPROACH — a foe just outside striking range: a gentle committed dash to
    // close the gap so engagements actually happen (otherwise low-friction drift
    // leaves bots idling apart). Only from WELL inside the ring (so the dash can't
    // fling the bot off), only when the foe is not bracing (don't dash into a
    // wall), and only sometimes (accuracy-gated) so a bot does not robotically
    // chain dashes into self-rings. Beyond the approach band the bot waits.
    final wellInside =
        (self.pos - _center).distance < _currentRingRadius * 0.45;
    final targetBracing = _fighters[targetId]?.bracing ?? false;
    if (wellInside &&
        !targetBracing &&
        dist <= _bodyRadius * _botApproachRangeFactor &&
        ctx.rng.chance(0.35 + 0.4 * acc)) {
      _commitLunge(playerId, self, aim);
    }
  }

  /// The nearest alive opponent of [playerId] that is currently EXPOSED (stunned
  /// or in post-lunge recovery, i.e. cannot act) within [maxDist], or null.
  int? _nearestExposedOpponent(int playerId, double maxDist) {
    final self = _bodyOf(playerId);
    if (self == null) return null;
    int? best;
    var bestDist = maxDist;
    for (final b in _arena.aliveBodies) {
      if (b.id == playerId) continue;
      final ef = _fighters[b.id];
      if (ef == null || ef.canAct || ef.invulnerable || ef.bracing) continue;
      final d = (b.pos - self.pos).distance;
      if (d <= bestDist) {
        bestDist = d;
        best = b.id;
      }
    }
    return best;
  }

  void _botStartBrace(_Fighter f) {
    f.pressing = true;
    f.bracing = true;
    f.hasDragAim = false;
    f.botBraceTimer = _botBraceHoldSec;
  }

  /// A foe that is mid-lunge, close, and roughly aimed at [playerId] — the cue a
  /// bot should brace. Null when no such threat exists.
  int? _incomingThreat(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null) return null;
    for (final b in _arena.aliveBodies) {
      if (b.id == playerId) continue;
      final ef = _fighters[b.id];
      if (ef == null || !ef.lungeActive) continue;
      final to = self.pos - b.pos;
      final dist = to.distance;
      if (dist > _bodyRadius * _botThreatRangeFactor || dist < 1e-6) continue;
      final speed = b.vel.distance;
      if (speed < 1) continue;
      final dot = (b.vel.dx * to.dx + b.vel.dy * to.dy) / (speed * dist);
      if (dot >= _botThreatAimDot) return b.id;
    }
    return null;
  }

  /// Fire one committed LUNGE for [playerId] in [aimAngle], then enter RECOVERY.
  void _commitLunge(int playerId, Body self, double aimAngle) {
    final f = _fighters[playerId];
    if (f == null || !f.canAct) return;

    final dir = Offset(math.cos(aimAngle), math.sin(aimAngle));
    // A collected star briefly amplifies the lunge — the buffed wrestler hits
    // noticeably harder, the core of the chaos swing.
    final buffMul = f.buffed ? _buffLungeMul : 1.0;
    final magnitude = _ringRadius * _lungeImpulse * buffMul;
    // A lunge SETS the launch velocity (not stacks) so repeated taps can't pile
    // speed into a super-shot; each lunge is one clean committed dash.
    _arena.impulse(playerId, dir * magnitude - self.vel);
    _arena.impulse(playerId, -dir * magnitude * _lungeSelfPushback);

    f.markLunge(); // contact resolver reads this: an active lunge LAUNCHES
    f.enterRecovery(_recoverySec);
    f.lungeCarry = _lungeCarrySec; // free full-speed dash before recovery brakes
    f.trail = _DashTrail(from: self.pos, dir: dir, life: _trailLifeSec);
    // A fresh lunge must produce a FRESH contact even against a foe this body is
    // already touching — clear its contact-debounce keys so the new dash's hit
    // (launch + KO credit, or brace repel) resolves instead of being suppressed.
    _contactPairs.removeWhere((key) => key ~/ 8 == playerId || key % 8 == playerId);
    _braceContacts.removeWhere((key) => key ~/ 8 == playerId || key % 8 == playerId);

    final fig = _figures[playerId];
    if (fig != null) {
      fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
      fig.dash();
    }

    _juice.particles.burst(
      at: self.pos - dir * _bodyRadius,
      count: 10,
      color: const Color(0xFFE7C58C),
      speed: 220,
      baseAngle: math.atan2(-dir.dy, -dir.dx),
      spread: math.pi * 0.7,
      size: 5,
      gravity: 200,
      life: 0.35,
    );
    _juice.hit(self.pos, _colorOf(playerId), sparks: 6);
    _juice.shake.light();
  }

  bool _isNearEdge(Body b) =>
      (b.pos - _center).distance > _currentRingRadius * _botEdgeBackoff;

  Offset? _nearestOpponentPos(int playerId) {
    final id = _nearestOpponentId(playerId);
    return id == null ? null : _bodyOf(id)?.pos;
  }

  int? _nearestOpponentId(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null) return null;
    int? best;
    var bestDist = double.infinity;
    for (final b in _arena.aliveBodies) {
      if (b.id == playerId) continue;
      final d = (b.pos - self.pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = b.id;
      }
    }
    return best;
  }

  // ── Contact: the LUNGE-vs-BRACE read ─────────────────────────────────────────

  /// THE READ, resolved BEFORE the arena step. For each near-contact pair where
  /// a lunger meets a braced foe, the lunger is REPELLED straight back + STUNNED
  /// and its velocity is killed so the arena's elastic step has no momentum to
  /// shove into the rooted foe (which therefore barely moves). Uses a proximity
  /// margin so it still fires the frame the bodies are closest. Debounced via
  /// [_braceContacts] so one continuous press resolves a read only once.
  void _resolveBraceReads() {
    final alive = _arena.aliveBodies;
    final current = <int>{};
    for (var i = 0; i < alive.length; i++) {
      for (var j = i + 1; j < alive.length; j++) {
        final a = alive[i];
        final b = alive[j];
        final delta = b.pos - a.pos;
        final dist = delta.distance;
        if (dist >= (a.radius + b.radius) * _contactMargin) continue;

        // Identify the lunger (mid-lunge) vs the braced foe in this pair.
        final aF = _fighters[a.id];
        final bF = _fighters[b.id];
        final aLunge = aF?.lungeActive ?? false;
        final bLunge = bF?.lungeActive ?? false;
        final aBrace = aF?.bracing ?? false;
        final bBrace = bF?.bracing ?? false;
        Body? lunger;
        Body? braced;
        if (aLunge && bBrace) {
          lunger = a;
          braced = b;
        } else if (bLunge && aBrace) {
          lunger = b;
          braced = a;
        } else {
          continue; // not a lunge-vs-brace pair
        }

        final key = _pairKey(a.id, b.id);
        current.add(key);
        if (_braceContacts.contains(key)) continue;
        _applyBraceRead(lunger, braced);
      }
    }
    _braceContacts
      ..clear()
      ..addAll(current);
  }

  /// Repel + stun [lunger] (it lunged into [braced]) and plant the braced foe.
  void _applyBraceRead(Body lunger, Body braced) {
    final lungerF = _fighters[lunger.id];
    final speed = lunger.vel.distance;
    final back = speed > 1e-6
        ? -lunger.vel / speed
        : _normalize(lunger.pos - braced.pos);
    // SET (not add) the lunger's velocity to a hard backward repel — overriding
    // its inbound lunge so the arena cannot carry it into the foe.
    lunger.vel = back * _ringRadius * _repelImpulse;
    lungerF?.enterStun(_stunSec);
    lungerF?.clearLunge(); // the lunge is spent (repelled)
    // Plant the braced foe: kill any inbound nudge so it holds its ground (the
    // brace's near-immovability). A whisper of give keeps it from feeling static.
    braced.vel = braced.vel * _braceKnockbackRetain;

    final at = Offset.lerp(lunger.pos, braced.pos, 0.5) ?? braced.pos;
    _juice.hit(at, _braceColor, sparks: 14);
    _juice.shake.medium();
    _juice.popup(
      braced.pos.translate(0, -_bodyRadius * 1.9),
      'BLOCK!',
      _braceColor,
      size: 26,
    );
  }

  void _resolveContacts() {
    final alive = _arena.aliveBodies;
    final current = <int>{};
    for (var i = 0; i < alive.length; i++) {
      for (var j = i + 1; j < alive.length; j++) {
        final a = alive[i];
        final b = alive[j];
        final delta = b.pos - a.pos;
        final dist = delta.distance;
        // Use the same proximity margin as the brace read: the arena's elastic
        // step may have already separated the bodies this frame, so a strict
        // overlap test would miss the contact (and skip the KO credit + bonus).
        if (dist >= (a.radius + b.radius) * _contactMargin) continue;
        final key = _pairKey(a.id, b.id);
        current.add(key);
        if (_contactPairs.contains(key)) continue;
        // A pair currently resolving as a LUNGE-vs-BRACE read (handled pre-step)
        // must not also take a launch knockback — the braced foe stays planted.
        if (_braceContacts.contains(key)) continue;
        _applyContact(a, b, delta, dist);
      }
    }
    _contactPairs
      ..clear()
      ..addAll(current);
  }

  /// Resolve one fresh launch contact (a brace read was already handled before
  /// the arena step). The ATTACKER is the LUNGING body (the launcher) — not
  /// merely the faster one, because the arena's elastic step may have already
  /// transferred the lunge's momentum into the victim, leaving the victim faster.
  /// The victim is knocked back, scaled by how committed the hit was (full for an
  /// active lunge, [_idleHitFloor] for an incidental bump — so a drift can't
  /// luck-KO), and credited to the attacker for a follow-up ring-out.
  void _applyContact(Body a, Body b, Offset delta, double dist) {
    final normal = dist > 1e-6 ? delta / dist : const Offset(1, 0);
    final aLunge = _fighters[a.id]?.lungeActive ?? false;
    final bLunge = _fighters[b.id]?.lungeActive ?? false;
    // Pick the attacker: the lone lunger if exactly one is lunging, else the
    // faster body (an incidental bump between two non-lungers).
    final Body attacker;
    if (aLunge && !bLunge) {
      attacker = a;
    } else if (bLunge && !aLunge) {
      attacker = b;
    } else {
      attacker = a.vel.distance >= b.vel.distance ? a : b;
    }
    final victim = identical(attacker, a) ? b : a;
    final toVictim = identical(attacker, a) ? normal : -normal;

    // Impact energy: the faster of the pair (the arena may have flipped which
    // body carries the speed after the elastic exchange).
    final speed = math.max(a.vel.distance, b.vel.distance);
    if (speed < 1) return;

    final atkF = _fighters[attacker.id];
    final vicF = _fighters[victim.id];
    final attackerLunging = atkF?.lungeActive ?? false;
    final at = Offset.lerp(a.pos, b.pos, 0.5) ?? a.pos;

    // A normal launch. Remember who launched the victim so a follow-up ring-out
    // credits them (an invulnerable just-respawned attacker's hit does not count).
    if (!(atkF?.invulnerable ?? false)) {
      vicF?.markHitBy(attacker.id);
    }

    final speedFactor = (speed / _contactSpeedRef).clamp(0.0, 1.5);
    // COMMIT GATE: only an ACTIVE LUNGE transfers full knockback; an incidental
    // bump (no live lunge) transfers only [_idleHitFloor], so a rival is launched
    // off the ring solely by a committed lunge — drifting into someone cannot
    // luck-KO. A star-buffed lunge always counts as fully committed. The push
    // rides the attacker→victim contact normal, with a fixed head-on boost (the
    // dash is always aimed straight into the foe).
    final commit = attackerLunging ? 1.0 : _idleHitFloor;
    final bonus = _ringRadius *
        _contactBonusScale *
        speedFactor *
        commit *
        (1.0 + _headOnExtra);
    _arena.impulse(victim.id, toVictim * bonus);

    if (speed >= _heavyHitSpeed && attackerLunging) {
      _juice.hit(at, _colorOf(attacker.id), sparks: 12);
      _juice.shake.medium();
    } else {
      _juice.particles.burst(
        at: at,
        count: 6,
        color: _colorOf(attacker.id),
        speed: 200,
        size: 5,
        life: 0.35,
      );
      _juice.shake.light();
    }
  }

  // ── Shrinking ring ──────────────────────────────────────────────────────────

  void _shrinkRing(double dt) {
    if (_elapsed < _shrinkDelaySec) return;
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

  /// Any wrestler overlapping a ready star collects it: brief lunge buff + a
  /// burst + popup. The grabber gets a swingy edge — pure chaos for the table.
  void _collectStars() {
    final star = _stars.star;
    if (star == null || !star.ready) return;
    for (final b in _arena.aliveBodies) {
      if ((b.pos - star.pos).distance > b.radius + star.radius) continue;
      final f = _fighters[b.id];
      if (f != null) f.buff = _buffSec;
      _stars.consume();
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

  // ── Figures ─────────────────────────────────────────────────────────────────

  void _syncFigures(double dt) {
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      final fig = entry.value;
      if (body != null && body.alive && !fig.isRagdoll) {
        fig.setLoco(
          body.vel.distance > _runSpeed ? LocoState.run : LocoState.idle,
        );
        _reactNearFall(entry.key, body, fig);
      }
      fig.update(dt);
    }
  }

  /// Charm: a wrestler teetering in the rescue band while moving SLOWLY (the
  /// same about-to-fall case the rescue assist saves) flails an arms-up [hurt]
  /// flinch ONCE so the near-fall reads, re-arming only after it recovers back
  /// inside the band. A fast launch sails out (ejected) and never flails.
  void _reactNearFall(int id, Body body, StickFigure fig) {
    final f = _fighters[id];
    if (f == null) return;
    final dist = (body.pos - _center).distance;
    final teetering = dist >= _currentRingRadius * _rescueBandFactor &&
        body.vel.distance <= _rescueMaxSpeed;
    if (teetering) {
      if (!f.nearFallReacted) {
        f.nearFallReacted = true;
        if (!fig.actionPlaying) fig.hurt();
      }
    } else {
      f.nearFallReacted = false; // recovered — re-arm for the next teeter
    }
  }

  // ── Ring-out ────────────────────────────────────────────────────────────────

  void _detectRingOuts() {
    var firedBig = false; // one cinematic ring-out beat per frame (kid-tasteful)
    for (final b in _arena.bodies) {
      if (!b.alive || _ragdolled.contains(b.id)) continue;
      // A just-respawned wrestler cannot be rung out during its spawn grace.
      if (_fighters[b.id]?.invulnerable ?? false) continue;
      if ((b.pos - _center).distance <= _currentRingRadius) continue;

      final outVel = b.vel;
      b.alive = false;
      b.vel = Offset.zero;
      _ragdolled.add(b.id);
      _scoreRingOut(b.id);
      _respawnTimers[b.id] = _respawnSec;

      if (!firedBig) {
        firedBig = true;
        _juice.bigMoment(b.pos, _colorOf(b.id), banner: 'RING OUT!');
      } else {
        _juice.ko(b.pos, _colorOf(b.id));
      }
      final outDir = _normalize(b.pos - _center);
      _juice.particles.burst(
        at: b.pos,
        count: 16,
        color: _colorOf(b.id),
        speed: 360,
        baseAngle: math.atan2(outDir.dy, outDir.dx),
        spread: math.pi * 0.9,
        size: 7,
        gravity: 260,
        life: 0.7,
      );

      final fig = _figures[b.id];
      if (fig != null) {
        final outward = _normalize(b.pos - _center);
        final fling =
            outward * _ringRadius * _flingBaseFactor +
            outVel * _flingSpeedFactor;
        final groundY = b.pos.dy + b.radius * 2;
        fig.enterRagdoll(_figureRoot(b), groundY, fling);
      }
    }
  }

  /// Award a ring-out: credit the wrestler who last launched [victimId] (if the
  /// hit was recent enough), bumping their [koScore]. A self-ring-out — no fresh
  /// attacker — scores nobody and docks the victim [_selfRingPenalty], so a blind
  /// lunger who flings itself off the edge actively loses ground. Live scores are
  /// mirrored to the engine so the on-field HUD shows the KO race.
  void _scoreRingOut(int victimId) {
    final victim = _fighters[victimId];
    final attackerId = victim?.lastAttacker ?? -1;
    final recent = (victim?.attackerAge ?? double.infinity) <=
        _attackerCreditSec;
    if (victim != null) {
      victim.lastAttacker = -1; // consumed — a later eject must be re-earned
    }
    if (attackerId >= 0 && attackerId != victimId && recent) {
      final attacker = _fighters[attackerId];
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
    // go NEGATIVE on purpose — that is the anti-spam signal that a blind lunger
    // who rockets itself off the edge has actively LOST ground (the SPAM-LOSES
    // tests rely on it). The winner is still whoever banked the most KOs.
    if (victim != null) {
      victim.koScore -= _selfRingPenalty;
      victim.selfRings += 1;
      setScore(victimId, victim.koScore);
    }
  }

  /// Count down each KO'd wrestler's respawn timer; when it elapses, fling the
  /// wrestler back in from its spawn edge at rest, clear its ragdoll, and grant
  /// [_spawnInvulnSec] of grace so it cannot be re-ejected the instant it lands.
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

  /// Bring [id] back into the dohyo from its spawn edge (clamped inside the
  /// current shrunk ring), upright and invulnerable for a beat.
  void _respawn(int id) {
    final body = _bodyOf(id);
    if (body == null) return;
    final spawn = _spawnPos[id] ?? _center;
    final fromCenter = spawn - _center;
    final maxR = _currentRingRadius * 0.7;
    final pos = fromCenter.distance > maxR
        ? _center + _normalize(fromCenter) * maxR
        : spawn;
    body.pos = pos;
    body.vel = Offset.zero; // flung back in at rest; the player re-aims
    body.alive = true;
    _ragdolled.remove(id);
    _contactPairs.removeWhere((key) => key ~/ 8 == id || key % 8 == id);
    _braceContacts.removeWhere((key) => key ~/ 8 == id || key % 8 == id);
    final f = _fighters[id];
    if (f != null) {
      f
        ..pressing = false
        ..bracing = false
        ..hasDragAim = false
        ..pressHeld = 0
        ..invuln = _spawnInvulnSec
        ..recovery = 0
        ..lungeCarry = 0
        ..stun = 0
        ..lastAttacker = -1
        ..trail = null;
    }
    final fig = _figures[id];
    if (fig != null) {
      fig.exitRagdoll();
      fig.facing = pos.dx <= _center.dx ? 1.0 : -1.0;
      fig.setLoco(LocoState.idle);
    }
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

  // ── Outcome ─────────────────────────────────────────────────────────────────

  void _resolveOutcome() {
    if (!_suddenDeathAnnounced && _isSuddenDeath && ctx.players.length > 1) {
      _suddenDeathAnnounced = true;
      _juice.shake.medium();
      _juice.popup(
        _center.translate(0, -_currentRingRadius * 0.2),
        'SUDDEN DEATH',
        _accent,
        size: 38,
      );
    }
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
    // SCORED BRAWL: the round runs the FULL limit (KO'd wrestlers respawn), so it
    // NEVER ends early. Most ring-outs wins.
    if (_elapsed >= _timeLimit) _finishScored();
  }

  void _finishScored() {
    if (!_winnerCheered) {
      _winnerCheered = true;
      final leader = _leaderId();
      final fig = leader == null ? null : _figures[leader];
      if (fig != null && !fig.isRagdoll) {
        fig.setLoco(LocoState.idle);
        fig.victory();
      }
      _juice.confetti(_size, colors: [_accent, _starColor, _colorOfLeader(leader)]);
      if (ctx.players.length > 1) {
        final at = (leader != null ? _bodyOf(leader)?.pos : null) ?? _center;
        _juice.bigMoment(at, _colorOfLeader(leader), banner: 'WINNER!');
      }
    }
    finishByScore();
  }

  /// True when EXACTLY two players are within [_showdownMargin] KOs of the top
  /// score and that top score is a real lead (> 0) — a genuine two-way race.
  bool _isTwoWayShowdown() {
    var top = double.negativeInfinity;
    for (final p in ctx.players) {
      final s = _fighters[p.id]?.koScore ?? 0;
      if (s > top) top = s;
    }
    if (top <= 0) return false;
    var contenders = 0;
    for (final p in ctx.players) {
      final s = _fighters[p.id]?.koScore ?? 0;
      if (top - s <= _showdownMargin) contenders++;
    }
    return contenders == 2;
  }

  /// The id with the highest [koScore] (ties → lowest id), or null if empty.
  int? _leaderId() {
    int? best;
    double bestScore = double.negativeInfinity;
    for (final p in ctx.players) {
      final s = _fighters[p.id]?.koScore ?? 0;
      if (s > bestScore) {
        bestScore = s;
        best = p.id;
      }
    }
    return best;
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    _juice.applyWorldTransform(canvas);

    SumoRenderer.drawBackground(canvas, size, _center, _ringRadius);
    SumoRenderer.drawAmbientDust(canvas, _dust, _animClock);
    SumoRenderer.drawDohyo(
      canvas,
      _center,
      _currentRingRadius,
      accent: _accent,
      dangerPulse: _dangerPulse(),
    );

    final star = _stars.star;
    if (star != null) SumoFx.drawStar(canvas, star);

    _drawWrestlers(canvas);

    _juice.render(canvas);
    canvas.restore();

    if (_isSuddenDeath) {
      SumoFx.drawSuddenDeathBanner(
        canvas,
        size,
        _suddenDeathBannerPulse(),
        _animClock,
      );
    }
    _juice.renderOverlay(canvas, size);
  }

  double _suddenDeathBannerPulse() => ctx.players.length > 1 ? 1.0 : 0.0;

  double _dangerPulse() {
    final shrink =
        1.0 - (_currentRingRadius / _ringRadius).clamp(_minRingFactor, 1.0);
    final throb = 0.5 + 0.5 * math.sin(_animClock * 4.0);
    return (0.35 + shrink + 0.25 * throb).clamp(0.0, 1.0);
  }

  void _drawWrestlers(Canvas canvas) {
    for (final b in _arena.bodies) {
      final fig = _figures[b.id];
      if (fig == null) continue;
      if (fig.isRagdoll) {
        SumoRenderer.drawWrestler(canvas, fig, b.pos);
        continue;
      }
      if (!b.alive) continue;

      final feet = _feetOf(b);
      final color = _colorOf(b.id);
      final f = _fighters[b.id];

      // Lunge dash trail.
      if (f?.trail != null) {
        final tr = f!.trail!;
        SumoRenderer.drawDashTrail(
          canvas,
          tr.from,
          tr.from + tr.dir * (_bodyRadius * 2.2),
          _bodyRadius,
          color,
          tr.strength,
        );
      }

      // Star buff aura.
      if (f != null && f.buffed) {
        final pulse = 0.5 + 0.5 * math.sin(_animClock * 6.0);
        canvas.drawCircle(
          b.pos,
          _bodyRadius * (1.45 + 0.15 * pulse),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _bodyRadius * 0.18
            ..color = _starColor.withValues(
              alpha: (0.45 + 0.35 * pulse).clamp(0.0, 1.0),
            ),
        );
      }

      SumoRenderer.drawContactShadow(canvas, feet, _bodyRadius);
      SumoRenderer.drawIdMarker(canvas, feet, _bodyRadius, color, b.id + 1);

      // BRACE shield — a glowing planted-feet ring while braced (drawn under the
      // figure so the wrestler reads on top).
      if (f != null && f.bracing) {
        SumoFx.drawBraceShield(
          canvas,
          b.pos,
          _bodyRadius,
          _braceColor,
          _animClock,
        );
      }

      // The wrestler + belt.
      SumoRenderer.drawWrestler(canvas, fig, _figureRoot(b));
      SumoRenderer.drawBelt(
        canvas,
        _pelvisOf(b),
        _bodyRadius,
        fig.facing,
        color,
      );

      // STUN read — dizzy orbiting stars over a repelled lunger.
      if (f != null && f.stunned) {
        SumoFx.drawStunStars(
          canvas,
          b.pos.translate(0, -_bodyRadius * 1.7),
          _bodyRadius,
          _animClock,
          (f.stun / _stunSec).clamp(0.0, 1.0),
        );
      }

      // The aim arrow — the player's control, drawn on top. Shown faint at rest
      // (idle preview) and bright while pressing for a human who can act. Hidden
      // while braced (the shield is the tell) and while stunned/recovering.
      final showAim = f != null &&
          !f.bracing &&
          !f.stunned &&
          (f.pressing ||
              (!_botClocks.containsKey(b.id) && f.canAct));
      if (showAim) {
        SumoRenderer.drawAim(
          canvas,
          b.pos,
          _bodyRadius,
          color,
          aim: f.aim,
          charge: f.pressing ? 1.0 : 0.0,
        );
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Offset _feetOf(Body b) => Offset(b.pos.dx, b.pos.dy + b.radius);
  Offset _figureRoot(Body b) =>
      Offset(b.pos.dx, b.pos.dy + b.radius - _footReach);
  Offset _pelvisOf(Body b) => _figureRoot(b);

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

  Color _colorOfLeader(int? leader) => leader == null ? _accent : _colorOf(leader);

  static int _pairKey(int a, int b) => a < b ? a * 8 + b : b * 8 + a;

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }

  // ── @visibleForTesting debug hooks ────────────────────────────────────────────
  // Let a deterministic test drive a "blind lunger" vs a "measured brace-then-
  // counter" actor and read the resulting state, without exposing internals to
  // the engine. These never branch game logic — they only force / observe.

  /// Force [id] to fire one LUNGE this instant in its current aim (auto-aim at
  /// the nearest rival if it has no manual aim). No-op if it cannot act
  /// (recovering / stunned / KO'd / invulnerable / mid-press).
  @visibleForTesting
  void debugForceLunge(int id) {
    final body = _bodyOf(id);
    final f = _fighters[id];
    if (body == null || !body.alive || f == null || !f.canAct) return;
    final aim = f.hasDragAim ? f.aim : (_aimAtNearest(id) ?? f.aim);
    f.aim = aim;
    _commitLunge(id, body, aim);
  }

  /// Force [id] to fire one LUNGE this instant in an explicit [angle] (radians),
  /// bypassing the nearest-rival auto-aim. No-op if it cannot act. Lets a
  /// deterministic test aim a lunge at a hand-placed foe.
  @visibleForTesting
  void debugLungeToward(int id, double angle) {
    final body = _bodyOf(id);
    final f = _fighters[id];
    if (body == null || !body.alive || f == null || !f.canAct) return;
    f
      ..aim = angle
      ..hasDragAim = true;
    _commitLunge(id, body, angle);
  }

  /// Teleport [id]'s body to an absolute arena position [pos] at rest (test
  /// fixture only). No-op if the body is missing.
  @visibleForTesting
  void debugPlace(int id, Offset pos) {
    final body = _bodyOf(id);
    if (body == null) return;
    body
      ..pos = pos
      ..vel = Offset.zero;
  }

  /// Force [id] into a BRACE that holds for [holdSec] seconds (rooted,
  /// knockback cut). No-op if it cannot act.
  @visibleForTesting
  void debugForceBrace(int id, {double holdSec = 0.4}) {
    final body = _bodyOf(id);
    final f = _fighters[id];
    if (body == null || !body.alive || f == null || !f.canAct) return;
    f
      ..pressing = true
      ..bracing = true
      ..hasDragAim = false
      ..botBraceTimer = holdSec;
    final fig = _figures[id];
    if (fig != null && !fig.actionPlaying) fig.hurt();
  }

  /// Release any held BRACE for [id] (fires nothing — brace release is inert).
  @visibleForTesting
  void debugReleaseBrace(int id) {
    final f = _fighters[id];
    if (f == null) return;
    f
      ..pressing = false
      ..bracing = false;
  }

  /// The ring-outs [id] has CAUSED (equal to the engine score this game reports).
  @visibleForTesting
  double debugScoreOf(int id) => _fighters[id]?.koScore ?? 0;

  /// Number of times [id] rang ITSELF out (no fresh attacker) this round.
  @visibleForTesting
  int debugSelfRingsOf(int id) => _fighters[id]?.selfRings ?? 0;

  /// True if [id] is currently BRACING.
  @visibleForTesting
  bool debugIsBracing(int id) => _fighters[id]?.bracing ?? false;

  /// True if [id] is currently STUNNED (was repelled by a brace).
  @visibleForTesting
  bool debugIsStunned(int id) => _fighters[id]?.stunned ?? false;

  /// True if [id] can act right now (not recovering / stunned / KO'd / pressing).
  @visibleForTesting
  bool debugCanAct(int id) {
    final body = _bodyOf(id);
    final f = _fighters[id];
    return (body?.alive ?? false) && (f?.canAct ?? false);
  }

  /// True if [id] is mid-lunge (its committed-lunge window is live).
  @visibleForTesting
  bool debugIsLungeActive(int id) => _fighters[id]?.lungeActive ?? false;

  /// The current sim radius of the dohyo (shrinks over the round).
  @visibleForTesting
  double get debugRingRadius => _currentRingRadius;

  /// The arena centre in px.
  @visibleForTesting
  Offset get debugCenter => _center;

  /// Distance of [id] from the ring centre (px), or infinity if missing.
  @visibleForTesting
  double debugDistFromCenter(int id) {
    final b = _bodyOf(id);
    return b == null ? double.infinity : (b.pos - _center).distance;
  }

  /// Elapsed sim seconds this round.
  @visibleForTesting
  double get debugElapsed => _elapsed;
}

/// Per-player control + brawl state for the LUNGE/BRACE model.
///
/// Mode is a small explicit state machine read off these flags/timers:
///  * READY      — can act ([canAct] true): pressing == false, recovery/stun 0.
///  * PRESSING   — finger down, intent not yet resolved. Crosses to BRACING once
///                 [pressHeld] >= the brace threshold (driven by the game).
///  * BRACING    — planted, rooted, knockback cut. Releasing fires nothing.
///  * RECOVERY   — post-lunge lockout ([recovery] > 0): cannot act, decelerates.
///  * STUN       — repelled-by-a-brace lockout ([stun] > 0): cannot act, drifts.
///
/// Mutable round-scoped state (allowed for the duration of one round).
class _Fighter {
  double aim; // current aim angle (radians) — set by the player's drag / nearest
  Offset downPos = Offset.zero; // touch point at press, to tell a tap from a drag

  // ── Press / mode ──
  bool pressing = false; // finger is down (intent not yet resolved)
  bool bracing = false; // press held past the brace threshold → planted
  double pressHeld = 0; // seconds the current press has been held
  bool hasDragAim = false; // true once this press has a thumb-chosen angle
  double recovery = 0; // post-lunge lockout, seconds
  double lungeCarry = 0; // remaining full-speed dash window (no brake while > 0)
  double stun = 0; // repelled-lunge lockout, seconds
  double botBraceTimer = 0; // a bot's auto-release brace countdown

  double buff = 0; // seconds of star lunge-buff remaining
  bool nearFallReacted = false; // latched while teetering slowly near the edge
  _DashTrail? trail;

  // ── Scored brawl ──
  double koScore = 0; // ring-outs this wrestler has CAUSED (the score)
  int selfRings = 0; // times this wrestler rang ITSELF out (for tests)
  double invuln = 0; // post-respawn grace, seconds (no KO either way)
  int lastAttacker = -1; // id of the wrestler who last launched this one
  double attackerAge = 0; // seconds since [lastAttacker] was recorded

  // Lunge-active window: a fired lunge stays "live" briefly so the contact
  // resolver can tell a committed lunge from incidental carry.
  double _lungeAge = double.infinity;

  _Fighter({required this.aim});

  /// A wrestler can start a new action only when idle: not mid-press, not
  /// recovering, not stunned, not in its spawn grace.
  bool get canAct => !pressing && recovery <= 0 && stun <= 0 && invuln <= 0;
  bool get stunned => stun > 0;
  bool get buffed => buff > 0;
  bool get invulnerable => invuln > 0;

  // A fired lunge "counts" as committed for this long so the contact resolver
  // can tell a real lunge from incidental carry: long enough that the dash
  // crosses the gap and connects, short enough that later collision carries are
  // not read as a fresh lunge.
  static const double _lungeWindow = 0.55;

  /// True while a fired lunge is still "live" (within the connect window).
  bool get lungeActive => _lungeAge < _lungeWindow;

  /// Record that a lunge just fired (opens the connect window).
  void markLunge() => _lungeAge = 0;

  /// End the live-lunge window early (the lunge was spent — e.g. repelled).
  void clearLunge() => _lungeAge = double.infinity;

  /// Enter the post-lunge RECOVERY lockout.
  void enterRecovery(double sec) {
    recovery = sec;
    pressing = false;
    bracing = false;
  }

  /// Enter the STUN lockout after being repelled by a braced foe.
  void enterStun(double sec) {
    stun = math.max(stun, sec);
    pressing = false;
    bracing = false;
    recovery = 0;
    lungeCarry = 0; // not dashing — the repel slide is unbraked instead
  }

  /// Record [attackerId] as the most recent launcher of this wrestler (for KO
  /// credit). Self-hits never overwrite a real attacker.
  void markHitBy(int attackerId) {
    if (attackerId < 0) return;
    lastAttacker = attackerId;
    attackerAge = 0;
  }

  void tick(double dt) {
    if (recovery > 0) recovery = math.max(0, recovery - dt);
    if (lungeCarry > 0) lungeCarry = math.max(0, lungeCarry - dt);
    if (stun > 0) stun = math.max(0, stun - dt);
    if (buff > 0) buff = math.max(0, buff - dt);
    if (invuln > 0) invuln = math.max(0, invuln - dt);
    attackerAge += dt;
    if (_lungeAge.isFinite) _lungeAge += dt;
    if (trail != null) {
      trail!.life -= dt;
      if (trail!.life <= 0) trail = null;
    }
  }
}

/// A short-lived directional trail anchor for a lunge dash.
class _DashTrail {
  final Offset from;
  final Offset dir;
  double life;
  final double maxLife;
  _DashTrail({required this.from, required this.dir, required this.life})
    : maxLife = life;

  double get strength => maxLife <= 0 ? 0 : (life / maxLife).clamp(0.0, 1.0);
}
