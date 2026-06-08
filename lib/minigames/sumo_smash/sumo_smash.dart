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
import 'sumo_render.dart';

/// Sumo Smash — every player is a sumo wrestler in a circular dohyo.
///
/// CONTROL (the heart of it — full player agency, one touch):
///  * Each wrestler has an AIM ARROW that constantly sweeps around it.
///  * Quick TAP  → a light shove in the arrow's current direction.
///  * HOLD then release → the aim LOCKS and a charge meter fills; releasing
///    fires a powerful lunge in the locked direction (power ∝ charge).
///  So the player chooses WHERE to push (time the sweep) and HOW HARD (charge):
///  aim a charged shove to send a rival off the edge, or quick-tap inward to
///  save yourself. Nothing is auto-aimed.
///
/// Feel: low-friction clay so shoves carry; collisions transfer momentum so a
/// well-aimed charge launches the victim (ragdoll) off the ring. The dohyo
/// shrinks after a grace period (sudden death) so matches always resolve.
///
/// Bots time an aimed, charged shove toward the nearest opponent and retreat
/// from the edge; [BotProfile] governs timing, charge and aim error.
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

  // ── Knockback (contact) tuning ──────────────────────────────────────────────
  static const double _contactSpeedRef = 700.0;
  static const double _contactBonusScale = 0.28;
  static const double _headOnExtra = 0.85;
  static const double _heavyHitSpeed = 380.0;

  // ── Shrinking ring tuning ───────────────────────────────────────────────────
  static const double _shrinkDelaySec = 9.0;
  static const double _minRingFactor = 0.5;
  static const double _shrinkPerSec = 0.024;

  // ── Ring-out fling tuning ───────────────────────────────────────────────────
  static const double _flingBaseFactor = 0.5;
  static const double _flingSpeedFactor = 0.55;

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botWarmupSec = 2.0; // grace before bots engage
  static const double _botCloseRangeFactor = 4.2; // approach vs shove threshold
  static const double _botEdgeBackoff = 0.62; // dist/ring above → retreat inward
  static const double _botAimErrorRad = 0.55; // max aim jitter at accuracy 0
  static const double _botCarrySpeed = 120.0; // skip shove while already fast

  // ── Figure build ────────────────────────────────────────────────────────────
  static const double _figureScale = 1.25;
  static const double _torsoWiden = 1.8;
  static const double _limbWiden = 1.55;
  static const double _runSpeed = 40.0;

  // ── Visuals ─────────────────────────────────────────────────────────────────
  static const Color _accent = Color(0xFFFFC062);
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
        if (f.ready) f.charging = true; // lock aim, begin charging
      case InputPhase.up:
        if (f.charging) {
          f.charging = false;
          final aim = _aimAtNearest(input.playerId) ?? f.aim;
          _commitDash(input.playerId, body, aim, f.charge);
          f.charge = 0;
        }
      case InputPhase.holdTick:
        break; // charge accrues in update() for frame-rate independence
    }
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

    _arena.update(sdt);

    _resolveContacts();
    _syncFigures(sdt);
    _detectRingOuts();
    _resolveOutcome();
  }

  /// Aim always tracks the nearest opponent (so a tap/charge strikes straight
  /// at it — no rotating arrow to time), fill charge while held, recover cooldown.
  void _tickFighters(double dt) {
    for (final entry in _fighters.entries) {
      final f = entry.value;
      if (_isAlive(entry.key)) {
        final a = _aimAtNearest(entry.key);
        if (a != null) f.aim = a;
        if (f.charging) {
          f.charge = math.min(1.0, f.charge + dt / _chargeTimeSec);
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

    final err = (1.0 - ctx.botProfile.accuracy.clamp(0.0, 1.0)) * _botAimErrorRad;

    // Near the edge: save self with a moderate shove back toward the centre.
    if (_isNearEdge(self)) {
      final aim = math.atan2(_center.dy - self.pos.dy, _center.dx - self.pos.dx);
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
    final magnitude = _ringRadius * (_dashBase + _dashCharge * charge);
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
    final bonus = _ringRadius *
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
          life: 0.35);
      _juice.shake.light();
    }
  }

  // ── Shrinking ring ──────────────────────────────────────────────────────────

  void _shrinkRing(double dt) {
    if (_elapsed < _shrinkDelaySec) return;
    final floor = _ringRadius * _minRingFactor;
    if (_currentRingRadius <= floor) return;
    _currentRingRadius =
        (_currentRingRadius - _ringRadius * _shrinkPerSec * dt)
            .clamp(floor, _ringRadius);
  }

  // ── Figures ─────────────────────────────────────────────────────────────────

  void _syncFigures(double dt) {
    for (final entry in _figures.entries) {
      final body = _bodyOf(entry.key);
      final fig = entry.value;
      if (body != null && body.alive && !fig.isRagdoll) {
        fig.setLoco(
            body.vel.distance > _runSpeed ? LocoState.run : LocoState.idle);
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
      _juice.popup(b.pos.translate(0, -_bodyRadius * 1.6), 'RING OUT!', _accent,
          size: 34);

      final fig = _figures[b.id];
      if (fig != null) {
        final outward = _normalize(b.pos - _center);
        final fling = outward * _ringRadius * _flingBaseFactor +
            outVel * _flingSpeedFactor;
        final groundY = b.pos.dy + b.radius * 2;
        fig.enterRagdoll(_figureRoot(b), groundY, fling);
      }
    }
  }

  // ── Outcome ─────────────────────────────────────────────────────────────────

  void _resolveOutcome() {
    final alive = _arena.aliveBodies;
    if (alive.length <= 1 || _elapsed >= _timeLimit) _finishRanked(alive);
  }

  void _finishRanked(List<Body> alive) {
    final ranked = alive.map((b) => b.id).toList()
      ..sort((a, b) => _distToCenter(a).compareTo(_distToCenter(b)));
    finishByOrder(_dedupeAllPlayers([...ranked, ..._eliminationOrder.reversed]));
  }

  // ── Render ──────────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    SumoRenderer.drawBackground(canvas, size, _center, _ringRadius);
    SumoRenderer.drawAmbientDust(canvas, _dust, _animClock);
    SumoRenderer.drawDohyo(canvas, _center, _currentRingRadius,
        accent: _accent, dangerPulse: _dangerPulse());

    _drawWrestlers(canvas);

    _juice.render(canvas);
    canvas.restore();
  }

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
            tr.strength);
      }

      SumoRenderer.drawContactShadow(canvas, feet, _bodyRadius);
      SumoRenderer.drawIdMarker(canvas, feet, _bodyRadius, color, b.id + 1);

      // The wrestler + belt.
      SumoRenderer.drawWrestler(canvas, fig, _figureRoot(b));
      SumoRenderer.drawBelt(
          canvas, _pelvisOf(b), _bodyRadius, fig.facing, color);

      // The aim arrow + charge — the player's control, drawn on top.
      if (f != null) _drawAim(canvas, b.pos, color, f);
    }
  }

  /// No idle arrow. While charging, a telegraph points straight at the nearest
  /// opponent (where the shove will fire) and a ring shows the charge level.
  void _drawAim(Canvas canvas, Offset center, Color color, _Fighter f) {
    if (!f.charging || f.charge <= 0.01) return;
    final charge = f.charge;
    final dir = Offset(math.cos(f.aim), math.sin(f.aim));
    final base = _bodyRadius * 0.95;
    final len = _bodyRadius * (1.8 + 2.4 * charge);
    final start = center + dir * base;
    final end = center + dir * (base + len);
    final w = _bodyRadius * (0.22 + 0.26 * charge);

    // Solid layered shaft (no blur — cheap to draw every frame).
    canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color.withValues(alpha: 0.95)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(
        start,
        end,
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.6)
          ..strokeWidth = w * 0.4
          ..strokeCap = StrokeCap.round);

    final perp = Offset(-dir.dy, dir.dx);
    final head = _bodyRadius * (0.55 + 0.34 * charge);
    final tip = end + dir * head;
    final l = end + perp * head * 0.66;
    final r = end - perp * head * 0.66;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(l.dx, l.dy)
        ..lineTo(r.dx, r.dy)
        ..close(),
      Paint()..color = color.withValues(alpha: 0.95),
    );

    final groundCenter = center.translate(0, _bodyRadius);
    canvas.drawArc(
      Rect.fromCircle(center: groundCenter, radius: _bodyRadius * 1.25),
      -math.pi / 2,
      math.pi * 2 * charge,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _bodyRadius * 0.18
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(color, const Color(0xFFFFFFFF), charge)!
            .withValues(alpha: 0.9),
    );
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

/// Per-player control state: sweeping aim, charge while held, cooldown, trail.
/// Mutable round-scoped state (allowed for one round).
class _Fighter {
  double aim; // current aim angle (radians)
  bool charging = false;
  double charge = 0; // 0..1 while held
  double _cooldown = 0;
  _DashTrail? trail;

  _Fighter({required this.aim});

  bool get ready => _cooldown <= 0;

  void tick(double dt) {
    if (_cooldown > 0) _cooldown = math.max(0, _cooldown - dt);
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
