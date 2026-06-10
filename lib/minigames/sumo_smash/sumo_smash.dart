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
/// RISK: while charging you are slowed to a near-root, so a whiffed charge
/// leaves you a sitting duck — committing to a big shove is a real decision.
///
/// Feel: low-friction clay so shoves carry; collisions transfer momentum so a
/// well-aimed charge launches the victim (ragdoll) off the ring. The dohyo
/// shrinks after a grace period (sudden death) so matches always resolve.
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
  // Tuned on-device for a ~15-25s match: smaller bodies + bigger ring + grippier
  // clay + weaker base shoves so a single hit never instantly ejects an idle
  // player; ring-outs come from positioning + charged shoves near the edge.
  static const double _timeLimit = 35;
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
  final List<int> _eliminationOrder = <int>[];
  final Set<int> _ragdolled = <int>{};
  final Set<int> _contactPairs = <int>{};
  final List<Offset> _dust = <Offset>[];

  late StarController _stars;
  bool _suddenDeathAnnounced = false;

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
        if (f.ready) {
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
          // Player-chosen aim wins; with no drag, fall back to nearest (kids).
          final aim = f.hasDragAim
              ? f.aim
              : (_aimAtNearest(input.playerId) ?? f.aim);
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
        // player sees matches where a release would actually fire.
        if (!f.hasDragAim) {
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
    if (ctx.rng.chance(ctx.botProfile.errorRate)) return; // hesitate / mistake

    final err =
        (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botAimErrorRad;

    // Near the edge: save self with a moderate shove back toward the centre.
    if (_isNearEdge(self)) {
      final aim = math.atan2(
        _center.dy - self.pos.dy,
        _center.dx - self.pos.dx,
      );
      f.aim = aim;
      _commitDash(playerId, self, aim, 0.5);
      return;
    }

    final targetPos = _nearestOpponentPos(playerId);
    if (targetPos == null) return;
    if (self.vel.distance > _botCarrySpeed) return; // ride out current motion

    final to = targetPos - self.pos;
    final aim = math.atan2(to.dy, to.dx) + ctx.rng.jitter(err);
    // Far → a light nudge to close in; close → a charged shove into the rival.
    final charge = to.distance > _bodyRadius * _botCloseRangeFactor
        ? 0.06
        : (ctx.botProfile.accuracy * ctx.rng.range(0.25, 0.55)).clamp(0.0, 1.0);
    f.aim = aim;
    _commitDash(playerId, self, aim, charge);
  }

  /// Apply an aimed shove of the given [charge] (0..1) in [aimAngle].
  void _commitDash(int playerId, Body self, double aimAngle, double charge) {
    final f = _fighters[playerId];
    if (f == null || !f.ready) return;

    final dir = Offset(math.cos(aimAngle), math.sin(aimAngle));
    // A collected star briefly amplifies every shove — the buffed wrestler hits
    // noticeably harder, the core of the chaos swing.
    final buffMul = f.buffed ? _buffDashMul : 1.0;
    final magnitude =
        _ringRadius * (_dashBase + _dashCharge * charge) * buffMul;
    _arena.impulse(playerId, dir * magnitude);
    _arena.impulse(playerId, -dir * magnitude * _selfPushback);

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

    final attackerDir = attacker.vel / speed;
    final headOn = (attackerDir.dx * toVictim.dx + attackerDir.dy * toVictim.dy)
        .clamp(0.0, 1.0);
    final speedFactor = (speed / _contactSpeedRef).clamp(0.0, 1.4);
    final bonus =
        _ringRadius *
        _contactBonusScale *
        speedFactor *
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
      }
      fig.update(dt);
    }
  }

  // ── Ring-out ────────────────────────────────────────────────────────────────

  void _detectRingOuts() {
    for (final b in _arena.bodies) {
      if (!b.alive || _ragdolled.contains(b.id)) continue;
      if ((b.pos - _center).distance <= _currentRingRadius) continue;

      final outVel = b.vel;
      b.alive = false;
      b.vel = Offset.zero;
      _ragdolled.add(b.id);
      _eliminationOrder.add(b.id);

      _juice.ko(b.pos, _colorOf(b.id));
      // A fatter ring-out flourish: an extra outward spark fan + a punchier
      // popup so the eject reads as a big moment kids cheer for.
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
      _juice.popup(
        b.pos.translate(0, -_bodyRadius * 1.7),
        'RING OUT!',
        _accent,
        size: 40,
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

  // ── Outcome ─────────────────────────────────────────────────────────────────

  void _resolveOutcome() {
    // Announce the climax exactly once with a screen shake + center popup, then
    // the fast-shrink ring + banner carry the moment.
    if (!_suddenDeathAnnounced &&
        _isSuddenDeath &&
        _arena.aliveBodies.length > 1) {
      _suddenDeathAnnounced = true;
      _juice.shake.medium();
      _juice.popup(
        _center.translate(0, -_currentRingRadius * 0.2),
        'SUDDEN DEATH',
        _accent,
        size: 38,
      );
    }
    final alive = _arena.aliveBodies;
    if (alive.length <= 1 || _elapsed >= _timeLimit) _finishRanked(alive);
  }

  void _finishRanked(List<Body> alive) {
    final ranked = alive.map((b) => b.id).toList()
      ..sort((a, b) => _distToCenter(a).compareTo(_distToCenter(b)));
    finishByOrder(
      _dedupeAllPlayers([...ranked, ..._eliminationOrder.reversed]),
    );
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

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

    if (_isSuddenDeath) {
      SumoFx.drawSuddenDeathBanner(
        canvas,
        size,
        _suddenDeathBannerPulse(),
        _animClock,
      );
    }

    _juice.render(canvas);
    canvas.restore();
  }

  /// Banner intensity: full once in sudden death (held up while ≥2 alive).
  double _suddenDeathBannerPulse() => _arena.aliveBodies.length > 1 ? 1.0 : 0.0;

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

  double _distToCenter(int id) {
    final b = _bodyOf(id);
    return b == null ? double.infinity : (b.pos - _center).distance;
  }

  Color _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return Color(p.colorArgb);
    }
    return const Color(0xFFFFFFFF);
  }

  static int _pairKey(int a, int b) => a < b ? a * 8 + b : b * 8 + a;

  List<int> _dedupeAllPlayers(List<int> order) {
    final seen = <int>{};
    final result = <int>[];
    for (final id in order) {
      if (seen.add(id)) result.add(id);
    }
    for (final p in ctx.players) {
      if (seen.add(p.id)) result.add(p.id);
    }
    return result;
  }

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t.clamp(0.0, 1.0)) ?? c;

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }
}

/// Per-player control state: player-chosen drag aim, charge while held,
/// cooldown, trail. Mutable round-scoped state (allowed for one round).
class _Fighter {
  double aim; // current aim angle (radians) — set by the player's drag
  bool charging = false;
  bool hasDragAim = false; // true once this charge has a thumb-chosen angle
  double charge = 0; // 0..1 while held
  double _cooldown = 0;
  double buff = 0; // seconds of star shove-buff remaining
  _DashTrail? trail;

  _Fighter({required this.aim});

  bool get ready => _cooldown <= 0;
  bool get buffed => buff > 0;

  void tick(double dt) {
    if (_cooldown > 0) _cooldown = math.max(0, _cooldown - dt);
    if (buff > 0) buff = math.max(0, buff - dt);
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
