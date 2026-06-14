import 'dart:math' as math;
import 'dart:ui';

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

/// Sumo Smash — every player is a sumo wrestler in a circular dohyo.
///
/// SCORED BRAWL (not last-one-standing): the round runs the FULL [_timeLimit]
/// and your SCORE is the number of ring-outs you CAUSE. A knocked-out wrestler
/// does NOT end the round — it RESPAWNS ~[_respawnSec] later, flung back in from
/// its spawn edge with a brief spawn-invuln, so a 1v1 becomes a sustained
/// shoving match: KO the rival, it comes back, most KOs in [_timeLimit] wins.
/// A ring-out credits the LAST wrestler who shoved the victim; ringing YOURSELF
/// out (no recent attacker) scores nobody and costs you a small penalty, so
/// blind shove-spam that launches you into the void loses ground.
///
/// CONTROL (the heart of it — full player agency, one touch; the player owns
/// the aim, nothing auto-targets):
///  * DRAG from your wrestler in the direction you want to shove — the AIM
///    ARROW follows your thumb, so YOU pick the angle every shove.
///  * HOLD builds a charge meter while you keep dragging to re-aim; the longer
///    you hold the harder the lunge (power ∝ charge).
///  * RELEASE → BAM: a lunge fires in the direction you were dragging.
///  * A quick TAP with no drag aims at the nearest rival (a safe default for
///    little kids), so even a mash is sensible.
///  So a clever player drags a charged shove into a rival near the edge to
///  ring them out, or drags inward to save themselves.
///
/// RISK (why spam loses): while charging you are slowed to a near-root, so a
/// whiffed charge leaves you a sitting duck — committing to a big shove is a
/// real decision. A mis-aimed lunge sails into open clay (or off the edge,
/// self-ringing you for a penalty); a paced, aimed shove into a rival near the
/// rim scores. The bot dodges/charges, so shoving into air just cedes position.
///
/// Feel: low-friction clay so shoves carry; collisions transfer momentum so a
/// well-aimed charge launches the victim (ragdoll) off the ring. The dohyo
/// shrinks after a grace period (sudden death) so the late brawl tightens.
///
/// Bots cannot drag, so they aim at the nearest opponent (via [_aimAtNearest])
/// and retreat from the edge; [BotProfile] governs timing, charge and aim error.
class SumoSmash extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
    id: 'sumo_smash',
    name: 'Sumo Smash',
    minPlayers: 1,
    maxPlayers: 4,
    modes: [GameMode.ffa, GameMode.duel1v1],
    inputHint: 'DRAG / HOLD',
  );

  // ── Arena / sim tuning ──────────────────────────────────────────────────────
  // Tuned on-device for a sustained ~28s brawl: smaller bodies + bigger ring +
  // grippier clay + weaker base shoves so a single hit never instantly ejects an
  // idle player; ring-outs come from positioning + charged shoves near the edge.
  // Because KO'd wrestlers respawn, the round always plays the FULL limit.
  static const double _timeLimit = 28;
  static const double _ringRadiusFactor = 0.46;
  static const double _bodyRadiusFactor = 0.05;
  static const double _ringFriction = 0.96; // settles faster, less slide-off
  static const double _ringRestitution = 0.9;
  static const double _spawnRadiusFactor = 0.55;

  // ── Aim + charge control tuning ─────────────────────────────────────────────
  static const double _chargeTimeSec = 0.6; // hold time to full charge
  static const double _cooldownSec = 0.24; // snappy recovery between shoves
  static const double _dashBase = 1.4; // quick tap = a small nudge
  static const double _dashCharge = 3.8; // full hold = a strong launch
  static const double _selfPushback = 0.08; // recoil opposite the shove
  static const double _trailLifeSec = 0.24;
  // Drag aim: the touch must move at least this far (fraction of the min screen
  // side) from the wrestler before it counts as a deliberate aim; a smaller
  // wiggle is treated as a no-drag tap (→ aim at nearest, a kid-safe default).
  static const double _aimDragDeadzone = 0.018;
  // While charging, retain only this share of speed per 1/60s — a near-root so a
  // whiffed charge is punishable (the player is briefly a sitting duck).
  static const double _chargeRootRetain = 0.62;
  // The kid-safe "tap aims at the nearest rival" auto-assist is EARNED by
  // committing to a hold: only a release whose charge reached this threshold
  // gets the nearest-target fallback. An instant down→up MASH (no hold, no
  // drag) fires in the wrestler's *last committed* aim with NO retarget, so
  // blind tap-spam sprays stale-direction shoves that whiff — and self-eject
  // when the stale aim points at the rim. A real player either drags to aim or
  // holds a beat to unlock the assist; flailing the button does neither.
  static const double _autoAimMinCharge = 0.18;
  // An UNCHARGED shove (below this charge) transfers only a fraction of its
  // contact knockback, so a weak blind nudge cannot luck-launch a rival off the
  // ring — only a committed (charged) hit ejects. Scales linearly to full at
  // [_committedCharge].
  static const double _weakHitKnockbackFloor = 0.35;
  static const double _committedCharge = 0.5;

  // ── Knockback (contact) tuning ──────────────────────────────────────────────
  static const double _contactSpeedRef = 700.0;
  static const double _contactBonusScale = 0.28;
  static const double _headOnExtra = 0.85;
  static const double _heavyHitSpeed = 380.0;

  // ── Shrinking ring tuning ───────────────────────────────────────────────────
  static const double _shrinkDelaySec = 9.0;
  static const double _minRingFactor = 0.5;
  static const double _shrinkPerSec = 0.024;

  // ── Climax (sudden death) tuning ────────────────────────────────────────────
  // The final ~28% of the match: the ring collapses far faster and a SUDDEN
  // DEATH banner throbs, so the round visibly ramps to a finish.
  static const double _suddenDeathFrac = 0.72; // enters at this share of time
  static const double _suddenDeathShrinkMul = 2.6; // shrink speed multiplier
  static const double _suddenDeathFloorMul =
      0.78; // tighter floor in sudden death
  // FINAL-2 SHOWDOWN: in the climax, if EXACTLY two players are tied for the
  // lead within this KO margin (a genuine race for the win), throw a one-shot
  // "FINAL TWO!" banner + slow-mo so the table feels the stakes.
  static const double _showdownMargin = 1.0; // within this many KOs of the lead

  // ── Star pickup (chaos) tuning ──────────────────────────────────────────────
  // One star at a time floats near the center; grabbing it grants a brief shove
  // buff. Any wrestler can take it, so it creates a scramble + swings.
  static const double _starRadiusFactor = 0.55; // star R / body R
  static const double _starFirstSpawnSec = 4.0; // first star appears after this
  static const double _starRespawnSec = 7.5; // gap after a star is taken/lost
  static const double _starSpawnSpreadFactor = 0.42; // spawn radius / ring R
  static const double _starAppearPerSec = 3.0; // pop-in ease rate
  static const double _starSpinPerSec = 3.2;
  static const double _starLifeSec = 6.0; // despawns if untouched
  static const double _buffSec = 4.0; // how long the shove buff lasts
  static const double _buffDashMul = 1.8; // shove magnitude × this while buffed

  // ── Kid-assist (comeback) tuning ────────────────────────────────────────────
  // A wrestler teetering in the last sliver before the edge while moving SLOWLY
  // gets a gentle inward brake, so a young player who is merely drifting out is
  // nudged back — but a genuine charged launch (fast) still ejects them.
  static const double _rescueBandFactor = 0.93; // dist/ring above → in the band
  static const double _rescueMaxSpeed = 150.0; // only brake below this speed
  static const double _rescueBrakePerSec = 2.6; // inward pull strength /s

  // ── Ring-out fling tuning ───────────────────────────────────────────────────
  static const double _flingBaseFactor = 0.5;
  static const double _flingSpeedFactor = 0.55;

  // ── Scored brawl: KO credit + respawn ───────────────────────────────────────
  // The round is a SCORED BRAWL, not last-standing: a ring-out scores the last
  // wrestler who shoved the victim (within [_attackerCreditSec] of the eject),
  // and the victim RESPAWNS [_respawnSec] later, flung in from its spawn edge
  // with [_spawnInvulnSec] of invulnerability (cannot be re-ejected or shove,
  // and a brief idle so a kid can re-orient). Self-ring-out — no fresh attacker —
  // scores nobody and docks the victim [_selfRingPenalty], so blind shove-spam
  // that launches you off the edge loses ground to paced, aimed play.
  static const double _respawnSec = 1.2; // delay before a KO'd wrestler returns
  static const double _spawnInvulnSec = 0.9; // post-respawn grace (no KO either way)
  static const double _attackerCreditSec =
      1.1; // a hit credits a KO only this recently
  static const double _selfRingPenalty = 1.0; // score docked for a self-ring-out

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botWarmupSec = 2.0; // grace before bots engage
  static const double _botCloseRangeFactor = 4.2; // approach vs shove threshold
  static const double _botEdgeBackoff =
      0.62; // dist/ring above → retreat inward
  static const double _botAimErrorRad = 0.55; // max aim jitter at accuracy 0
  static const double _botCarrySpeed = 120.0; // skip shove while already fast

  // ── Figure build ────────────────────────────────────────────────────────────
  static const double _figureScale = 1.25;
  static const double _torsoWiden = 1.8;
  static const double _limbWiden = 1.55;
  static const double _runSpeed = 40.0;

  // ── Visuals ─────────────────────────────────────────────────────────────────
  static const Color _accent = Color(0xFFFFC062);
  static const Color _starColor = Color(0xFFFFE45C); // pickup gold
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
  final Set<int> _contactPairs = <int>{};
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
    // juice, ragdoll fling and elimination order all fire. If the arena culled
    // at [_ringRadius] it would silently kill (alive=false) any body launched
    // out before the ring shrinks, and [_detectRingOuts] would then skip it.
    // Use a radius beyond the screen so the arena never falls a body off.
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

      // Aim starts pointing toward the centre so the first shove is sensible.
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

  // ── Input: hold to charge + aim, release to shove ───────────────────────────

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running) return;
    final f = _fighters[input.playerId];
    final body = _bodyOf(input.playerId);
    if (f == null || body == null || !body.alive) return;

    switch (input.phase) {
      case InputPhase.down:
        if (f.ready && !f.invulnerable) {
          f.charging = true; // begin charging
          f.hasDragAim = false; // until the thumb moves, no chosen direction
          _applyDragAim(input, body, f); // a press already away from us aims
        }
      case InputPhase.holdTick:
        // A drag sample re-aims toward the thumb (the player owns the angle).
        _applyDragAim(input, body, f);
      case InputPhase.up:
        if (f.charging) {
          f.charging = false;
          _applyDragAim(input, body, f); // final flick can still steer
          // Aim resolution (the heart of the skill gate):
          //  * a thumb-chosen drag aim ALWAYS wins (full agency); else
          //  * the kid-safe nearest-rival auto-assist is unlocked ONLY by a
          //    committed hold (charge >= [_autoAimMinCharge]); else
          //  * a pure instant down→up MASH keeps the wrestler's *last* aim with
          //    NO retarget — so blind tap-spam sprays stale-direction shoves
          //    that whiff (and self-eject when the stale aim faces the rim).
          final earnedAssist = f.charge >= _autoAimMinCharge;
          final aim = f.hasDragAim
              ? f.aim
              : (earnedAssist ? (_aimAtNearest(input.playerId) ?? f.aim) : f.aim);
          _commitDash(input.playerId, body, aim, f.charge);
          f.charge = 0;
          f.hasDragAim = false;
        }
    }
  }

  /// Set the fighter's aim from the drag vector (touch [input.normPos] relative
  /// to the wrestler), in true screen pixels so the angle is not skewed by the
  /// portrait aspect. A move shorter than [_aimDragDeadzone] (or a synthetic
  /// hold-tick with no position) is ignored, leaving any prior chosen aim — or
  /// the nearest-opponent fallback — intact.
  void _applyDragAim(PlayerInput input, Body body, _Fighter f) {
    if (!f.charging) return;
    final touch = Offset(
      input.normPos.dx * _size.width,
      input.normPos.dy * _size.height,
    );
    final d = touch - body.pos;
    final minSide = math.min(_size.width, _size.height);
    if (d.distance < minSide * _aimDragDeadzone) return;
    f.aim = math.atan2(d.dy, d.dx);
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

  /// Fill charge while held and recover cooldown. The aim is NOT touched here —
  /// it is owned by the player's drag (see [_applyDragAim]); a bot or a no-drag
  /// tap resolves it at fire time via [_aimAtNearest]. While charging, the
  /// wrestler is rooted to a near-stop so a whiffed charge is punishable.
  void _tickFighters(double dt) {
    for (final entry in _fighters.entries) {
      final f = entry.value;
      if (_isAlive(entry.key) && f.charging) {
        f.charge = math.min(1.0, f.charge + dt / _chargeTimeSec);
        // No drag yet → preview the nearest-opponent fallback so the arrow the
        // player sees matches where a release would actually fire — but ONLY
        // once the hold has earned the auto-assist ([_autoAimMinCharge]). Below
        // that, the arrow holds the stale aim, so an instant tap that releases
        // before committing fires unaimed (the skill gate is honest, not a
        // silent free retarget on the very first frame of a flick).
        if (!f.hasDragAim && f.charge >= _autoAimMinCharge) {
          final a = _aimAtNearest(entry.key);
          if (a != null) f.aim = a;
        }
        final body = _bodyOf(entry.key);
        if (body != null) {
          final retain = math.pow(_chargeRootRetain, dt * 60.0).toDouble();
          body.vel *= retain;
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
      if (!_isAlive(id)) continue;
      if (!entry.value.tick(dt)) continue;
      entry.value.arm(ctx.botProfile, ctx.rng);
      _botDecide(id);
    }
  }

  /// Bots pick an aim + charge and commit an aimed shove directly (no hold sim).
  void _botDecide(int playerId) {
    final self = _bodyOf(playerId);
    final f = _fighters[playerId];
    if (self == null || !self.alive || f == null || !f.ready) return;
    if (f.invulnerable) return; // just respawned — settle before engaging
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return; // hesitate / mistake

    final err =
        (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botAimErrorRad;

    // Near the edge: a competent bot saves itself with a shove back toward the
    // centre — but a LOW-ACCURACY (easy) bot mis-judges the save by [err], so it
    // can over-commit and fling ITSELF off the rim. Skill (accuracy) buys a
    // clean recovery; a weak bot self-ejects, exactly the beatable behaviour the
    // human exploits. The save is charged enough to actually carry inward.
    if (_isNearEdge(self)) {
      final aim = math.atan2(
            _center.dy - self.pos.dy,
            _center.dx - self.pos.dx,
          ) +
          ctx.rng.jitter(err);
      f.aim = aim;
      _commitDash(playerId, self, aim, 0.45 + 0.25 * ctx.botProfile.accuracy);
      return;
    }

    final targetPos = _nearestOpponentPos(playerId);
    if (targetPos == null) return;
    if (self.vel.distance > _botCarrySpeed) return; // ride out current motion

    final to = targetPos - self.pos;
    final aim = math.atan2(to.dy, to.dx) + ctx.rng.jitter(err);
    // Far → a light nudge to close in; close → a charged shove into the rival.
    // The attack charge scales with accuracy so the COMMIT GATE creates a real
    // skill gradient: a HARD bot (high accuracy) charges past [_committedCharge]
    // and lands true ring-out launches, while an EASY bot mostly stays under it
    // — its weak, mis-aimed shoves shove but rarely eject, so a human who aims
    // charged shoves out-KOs it. (Mirrors the human's own hold-to-commit cost.)
    final acc = ctx.botProfile.accuracy.clamp(0.0, 1.0);
    final charge = to.distance > _bodyRadius * _botCloseRangeFactor
        ? 0.06
        : (0.22 + 0.6 * acc * ctx.rng.range(0.7, 1.0)).clamp(0.0, 1.0);
    f.aim = aim;
    _commitDash(playerId, self, aim, charge);
  }

  /// Apply an aimed shove of the given [charge] (0..1) in [aimAngle].
  void _commitDash(int playerId, Body self, double aimAngle, double charge) {
    final f = _fighters[playerId];
    if (f == null || !f.ready || f.invulnerable) return;

    final dir = Offset(math.cos(aimAngle), math.sin(aimAngle));
    // A collected star briefly amplifies every shove — the buffed wrestler hits
    // noticeably harder, the core of the chaos swing.
    final buffMul = f.buffed ? _buffDashMul : 1.0;
    final magnitude =
        _ringRadius * (_dashBase + _dashCharge * charge) * buffMul;
    _arena.impulse(playerId, dir * magnitude);
    _arena.impulse(playerId, -dir * magnitude * _selfPushback);

    f.markShove(charge); // contact knockback reads this: only a charged shove KOs
    f.fire(_cooldownSec);
    f.trail = _DashTrail(from: self.pos, dir: dir, life: _trailLifeSec);

    final fig = _figures[playerId];
    if (fig != null) {
      fig.facing = dir.dx >= 0 ? 1.0 : -1.0;
      fig.dash();
    }

    final intensity = 0.5 + 0.5 * charge;
    _juice.particles.burst(
      at: self.pos - dir * _bodyRadius,
      count: (6 + 8 * charge).round(),
      color: const Color(0xFFE7C58C),
      speed: 150 * intensity,
      baseAngle: math.atan2(-dir.dy, -dir.dx),
      spread: math.pi * 0.7,
      size: 5,
      gravity: 200,
      life: 0.35,
    );
    _juice.hit(self.pos, _colorOf(playerId), sparks: (3 + 4 * charge).round());
    if (charge > 0.6) _juice.shake.light();
  }

  bool _isNearEdge(Body b) =>
      (b.pos - _center).distance > _currentRingRadius * _botEdgeBackoff;

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

  // ── Contact knockback ───────────────────────────────────────────────────────

  void _resolveContacts() {
    final alive = _arena.aliveBodies;
    final current = <int>{};
    for (var i = 0; i < alive.length; i++) {
      for (var j = i + 1; j < alive.length; j++) {
        final a = alive[i];
        final b = alive[j];
        final delta = b.pos - a.pos;
        final dist = delta.distance;
        if (dist >= a.radius + b.radius) continue;
        final key = _pairKey(a.id, b.id);
        current.add(key);
        if (_contactPairs.contains(key)) continue;
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
    final toVictim = identical(attacker, a) ? normal : -normal;

    final speed = attacker.vel.distance;
    if (speed < 1) return;

    // SCORED BRAWL: remember who shoved the victim so a follow-up ring-out
    // credits them. An invulnerable (just-respawned) attacker's hit does not
    // count, so they cannot farm KOs during their grace.
    if (!(_fighters[attacker.id]?.invulnerable ?? false)) {
      _fighters[victim.id]?.markHitBy(attacker.id);
    }

    final attackerDir = attacker.vel / speed;
    final headOn = (attackerDir.dx * toVictim.dx + attackerDir.dy * toVictim.dy)
        .clamp(0.0, 1.0);
    final speedFactor = (speed / _contactSpeedRef).clamp(0.0, 1.4);
    // COMMIT GATE: a blind, uncharged nudge transfers only [_weakHitKnockbackFloor]
    // of its contact knockback; a fully committed (charged) shove transfers the
    // full hit. So a rival is launched off the ring only by an *aimed, charged*
    // shove — an incidental or weak bump can shove someone but not eject them,
    // which is what makes button-spam unable to luck-KO. A star-buffed attacker
    // always counts as committed (the buff IS the commitment).
    final atkF = _fighters[attacker.id];
    final commit = (atkF?.buffed ?? false)
        ? 1.0
        : (atkF == null
            ? 1.0
            : (atkF.committedCharge / _committedCharge).clamp(0.0, 1.0));
    final commitFactor = _weakHitKnockbackFloor +
        (1.0 - _weakHitKnockbackFloor) * commit;
    final bonus =
        _ringRadius *
        _contactBonusScale *
        speedFactor *
        commitFactor *
        (1.0 + _headOnExtra * headOn);
    _arena.impulse(victim.id, toVictim * bonus);

    final at = Offset.lerp(a.pos, b.pos, 0.5) ?? a.pos;
    if (speed >= _heavyHitSpeed) {
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
    // Sudden death tightens the floor and accelerates the collapse so the round
    // ramps unmistakably toward a finish in its final stretch.
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

  /// Any wrestler overlapping a ready star collects it: brief shove buff + a
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
  /// flinch ONCE so the near-fall reads, re-arming only after they recover back
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
      // A just-respawned wrestler cannot be rung out during its spawn grace, so
      // it is never ejected the instant it lands back in the (shrunk) ring.
      if (_fighters[b.id]?.invulnerable ?? false) continue;
      if ((b.pos - _center).distance <= _currentRingRadius) continue;

      final outVel = b.vel;
      b.alive = false;
      b.vel = Offset.zero;
      _ragdolled.add(b.id);
      // SCORED BRAWL: credit the KO + queue the victim's respawn (never a
      // permanent elimination), so the round keeps going for the full limit.
      _scoreRingOut(b.id);
      _respawnTimers[b.id] = _respawnSec;

      // The decisive ring-out is the signature beat: a single big-moment
      // (burst + heavy shake + slow-mo + zoom toward the victim + flash +
      // banner + haptic). A rare same-frame second eject keeps the lighter KO.
      if (!firedBig) {
        firedBig = true;
        _juice.bigMoment(b.pos, _colorOf(b.id), banner: 'RING OUT!');
      } else {
        _juice.ko(b.pos, _colorOf(b.id));
      }
      // A fatter ring-out flourish: an extra outward spark fan so the eject
      // reads as a big moment kids cheer for. The 'RING OUT!' callout is now the
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

  /// Award a ring-out: credit the wrestler who last shoved [victimId] (if the
  /// hit was recent enough), bumping their [koScore]. A self-ring-out — no fresh
  /// attacker — scores nobody and docks the victim [_selfRingPenalty], so blind
  /// shove-spam off the edge actively loses ground. Live scores are mirrored to
  /// the engine so the on-field HUD shows the KO race.
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
    // go NEGATIVE on purpose — that is the anti-spam signal that a blind shover
    // who rockets itself off the edge has actively LOST ground (the SPAM-LOSES
    // tests rely on it). The winner is still whoever banked the most KOs.
    if (victim != null) {
      victim.koScore -= _selfRingPenalty;
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
    // Pull the spawn point inside the live ring so a tight sudden-death ring
    // never drops the respawn straight back into the void.
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
    final f = _fighters[id];
    if (f != null) {
      f
        ..charging = false
        ..hasDragAim = false
        ..charge = 0
        ..invuln = _spawnInvulnSec
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
    // Announce the climax exactly once with a screen shake + center popup, then
    // the fast-shrink ring + banner carry the moment. (≥2 wrestlers in play.)
    if (!_suddenDeathAnnounced &&
        _isSuddenDeath &&
        ctx.players.length > 1) {
      _suddenDeathAnnounced = true;
      _juice.shake.medium();
      _juice.popup(
        _center.translate(0, -_currentRingRadius * 0.2),
        'SUDDEN DEATH',
        _accent,
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
    // SCORED BRAWL: the round runs the FULL limit (KO'd wrestlers respawn), so it
    // NEVER ends early just because only one is on the ring. Most ring-outs wins.
    if (_elapsed >= _timeLimit) _finishScored();
  }

  void _finishScored() {
    // Charm: the leader (most KOs, ties broken by lowest id) celebrates once if
    // they are upright when the bell rings; a wrestler mid-fling just stays a
    // ragdoll. Score ties resolve in [finishByScore]'s stable order.
    if (!_winnerCheered) {
      _winnerCheered = true;
      final leader = _leaderId();
      final fig = leader == null ? null : _figures[leader];
      if (fig != null && !fig.isRagdoll) {
        fig.setLoco(LocoState.idle);
        fig.victory();
      }
      // The bell: a celebratory finish — confetti rain, a WINNER banner and a
      // big-moment punch centred on the leader so the round ends on a cheer
      // instead of a freeze. (A lone-practice round skips the banner fanfare.)
      _juice.confetti(_size, colors: [_accent, _starColor, _colorOfLeader(leader)]);
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

    // Screen-space overlays (after the world transform is restored so they are
    // never shaken or zoomed by the camera punch): the SUDDEN DEATH banner +
    // the cinematic flash/banner from bigMoment.
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

  /// Banner intensity: full once in sudden death for a multi-player brawl (held
  /// up through the whole climax; a lone respawn window must not blink it off).
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

      // A pulsing gold aura while the star buff is active so the table can see
      // who is dangerous right now.
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

      // The wrestler + belt.
      SumoRenderer.drawWrestler(canvas, fig, _figureRoot(b));
      SumoRenderer.drawBelt(
        canvas,
        _pelvisOf(b),
        _bodyRadius,
        fig.facing,
        color,
      );

      // The aim arrow + charge — the player's control, drawn on top.
      if (f != null && f.charging) {
        SumoRenderer.drawAim(
          canvas,
          b.pos,
          _bodyRadius,
          color,
          aim: f.aim,
          charge: f.charge,
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

  /// The leader's color, or the theme accent when there is no leader (empty
  /// board). Used for the bell fanfare so the confetti/banner match the winner.
  Color _colorOfLeader(int? leader) => leader == null ? _accent : _colorOf(leader);

  static int _pairKey(int a, int b) => a < b ? a * 8 + b : b * 8 + a;

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }
}

/// Per-player control + brawl state: player-chosen drag aim, charge while held,
/// cooldown, trail, plus the SCORED-BRAWL bookkeeping — ring-outs caused
/// ([koScore]), spawn-invuln after a respawn, and who last shoved this wrestler
/// (for KO credit). Mutable round-scoped state (allowed for one round).
class _Fighter {
  double aim; // current aim angle (radians) — set by the player's drag
  bool charging = false;
  bool hasDragAim = false; // true once this charge has a thumb-chosen angle
  double charge = 0; // 0..1 while held
  double _cooldown = 0;
  double buff = 0; // seconds of star shove-buff remaining
  bool nearFallReacted = false; // latched while teetering slowly near the edge
  _DashTrail? trail;

  // ── Scored brawl ──
  double koScore = 0; // ring-outs this wrestler has CAUSED (the score)
  double invuln = 0; // post-respawn grace, seconds (no KO either way)
  int lastAttacker = -1; // id of the wrestler who last shoved this one (-1 none)
  double attackerAge = 0; // seconds since [lastAttacker] was recorded
  // Charge (0..1) of this wrestler's most recent shove, decaying over a short
  // window. Read at contact time so only a COMMITTED (charged) shove transfers
  // full knockback — a blind uncharged nudge cannot luck-launch a rival out.
  double shoveCharge = 0;
  double _shoveChargeAge = 0;

  _Fighter({required this.aim});

  bool get ready => _cooldown <= 0;
  bool get buffed => buff > 0;
  bool get invulnerable => invuln > 0;

  /// Window (seconds) over which [shoveCharge] stays meaningful after a shove —
  /// long enough that a committed lunge still counts when it CONNECTS (the body
  /// usually crosses the gap within this window), but short enough that a body
  /// kept fast only by later collision carries is treated as incidental, not an
  /// aimed launch. Tuned so legit charged KOs land while luck-bumps stay weak.
  static const double _shoveChargeWindow = 0.6;

  /// The freshness-weighted charge of the last shove (0..1). Fades to 0 over
  /// [_shoveChargeWindow] so only a body actively mid-lunge counts as committed.
  double get committedCharge {
    if (_shoveChargeAge >= _shoveChargeWindow) return 0;
    final f = 1.0 - (_shoveChargeAge / _shoveChargeWindow);
    return (shoveCharge * f).clamp(0.0, 1.0);
  }

  /// Record the charge of a just-fired shove so contact knockback can tell a
  /// committed launch from an incidental bump.
  void markShove(double charge) {
    shoveCharge = charge.clamp(0.0, 1.0);
    _shoveChargeAge = 0;
  }

  /// Record [attackerId] as the most recent shover of this wrestler (for KO
  /// credit). Self-hits never overwrite a real attacker.
  void markHitBy(int attackerId) {
    if (attackerId < 0) return;
    lastAttacker = attackerId;
    attackerAge = 0;
  }

  void tick(double dt) {
    if (_cooldown > 0) _cooldown = math.max(0, _cooldown - dt);
    if (buff > 0) buff = math.max(0, buff - dt);
    if (invuln > 0) invuln = math.max(0, invuln - dt);
    attackerAge += dt;
    _shoveChargeAge += dt;
    if (trail != null) {
      trail!.life -= dt;
      if (trail!.life <= 0) trail = null;
    }
  }

  void fire(double cooldownSec) => _cooldown = cooldownSec;
}

/// A short-lived directional trail anchor for a dash.
class _DashTrail {
  final Offset from;
  final Offset dir;
  double life;
  final double maxLife;
  _DashTrail({required this.from, required this.dir, required this.life})
    : maxLife = life;

  double get strength => maxLife <= 0 ? 0 : (life / maxLife).clamp(0.0, 1.0);
}
