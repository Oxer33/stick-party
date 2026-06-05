import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/helpers/push_arena.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';

/// Bumper Balls: bouncy pucks on a ring. A tap bursts a ball along its current
/// heading (or toward the center if it is nearly still), letting players carom
/// off each other and knock rivals off the platform. Last ball on the platform
/// wins; on time-out the ball closest to the center wins.
class BumperBalls extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'bumper_balls',
        name: 'Bumper Balls',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa, GameMode.duel1v1],
        inputHint: 'TAP',
      );

  // ── Tuning ──────────────────────────────────────────────────────────────────
  static const double _timeLimit = 35;
  static const double _ringRadiusFactor = 0.42;
  static const double _bodyRadiusFactor = 0.05;
  static const double _ringFriction = 0.975;
  static const double _ringRestitution = 0.97; // bouncier than sumo
  static const double _burstPerSecond = 3.6;
  static const double _nearStillSpeed = 18.0; // below this → aim at center
  static const double _faceWobble = 0.18;

  late Juice _juice;
  late PushArena _arena;
  double _elapsed = 0;

  final Map<int, ReactionClock> _botClocks = <int, ReactionClock>{};
  final List<int> _eliminationOrder = <int>[];
  final Set<int> _eliminated = <int>{};

  late Offset _center;
  late double _ringRadius;

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    final size = ctx.arena;
    _center = Offset(size.width / 2, size.height / 2);
    final minSide = math.min(size.width, size.height);
    _ringRadius = minSide * _ringRadiusFactor;
    final bodyRadius = minSide * _bodyRadiusFactor;

    _arena = PushArena(
      center: _center,
      ringRadius: _ringRadius,
      friction: _ringFriction,
      restitution: _ringRestitution,
    );

    _buildBodies(bodyRadius);
    begin();
  }

  void _buildBodies(double bodyRadius) {
    final count = ctx.players.length;
    final spawnRadius = _ringRadius * 0.6;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      final angle = (i / count) * math.pi * 2 - math.pi / 2;
      final pos =
          _center + Offset(math.cos(angle), math.sin(angle)) * spawnRadius;
      _arena.add(Body(id: p.id, pos: pos, radius: bodyRadius));
      if (p.isBot) {
        _botClocks[p.id] = ReactionClock(ctx.botProfile, ctx.rng);
      }
    }
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _act(input.playerId);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _driveBots(dt);
    _arena.update(sdt);

    _detectEliminations();
    _resolveOutcome();
  }

  void _driveBots(double dt) {
    for (final entry in _botClocks.entries) {
      if (!_isAlive(entry.key)) continue;
      if (entry.value.tick(dt)) {
        _act(entry.key);
        entry.value.arm(ctx.botProfile, ctx.rng);
      }
    }
  }

  /// Burst along the ball's heading; if nearly still, aim toward the centroid of
  /// opponents (falling back to the ring center) so the ball never stalls.
  void _act(int playerId) {
    final self = _bodyOf(playerId);
    if (self == null || !self.alive) return;

    var dir = _normalize(self.vel);
    if (self.vel.distance < _nearStillSpeed) {
      final aim = _opponentCentroid(playerId) ?? _center;
      dir = _normalize(aim - self.pos);
      if (dir == Offset.zero) dir = const Offset(0, -1);
    }

    final magnitude = _ringRadius * _burstPerSecond;
    _arena.impulse(playerId, dir * magnitude);
    _juice.hit(self.pos, Color(_colorOf(playerId)), sparks: 6);
  }

  Offset? _opponentCentroid(int playerId) {
    var sum = Offset.zero;
    var n = 0;
    for (final b in _arena.aliveBodies) {
      if (b.id == playerId) continue;
      sum += b.pos;
      n++;
    }
    if (n == 0) return null;
    return sum / n.toDouble();
  }

  void _detectEliminations() {
    for (final b in _arena.bodies) {
      if (b.alive || _eliminated.contains(b.id)) continue;
      _eliminated.add(b.id);
      _eliminationOrder.add(b.id);
      _juice.ko(b.pos, Color(_colorOf(b.id)));
    }
  }

  void _resolveOutcome() {
    final alive = _arena.aliveBodies;
    if (alive.length <= 1) {
      _finishBySurvival(alive);
      return;
    }
    if (_elapsed >= _timeLimit) {
      _finishByCenterProximity(alive);
    }
  }

  void _finishBySurvival(List<Body> alive) {
    final survivors = alive.map((b) => b.id).toList()
      ..sort((a, b) => _distToCenter(a).compareTo(_distToCenter(b)));
    finishByOrder(_dedupeAllPlayers([
      ...survivors,
      ..._eliminationOrder.reversed,
    ]));
  }

  void _finishByCenterProximity(List<Body> alive) {
    final ranked = alive.map((b) => b.id).toList()
      ..sort((a, b) => _distToCenter(a).compareTo(_distToCenter(b)));
    finishByOrder(_dedupeAllPlayers([
      ...ranked,
      ..._eliminationOrder.reversed,
    ]));
  }

  @override
  void render(Canvas canvas, Size size) {
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    _drawBackground(canvas, size);
    _drawRing(canvas);
    for (final b in _arena.aliveBodies) {
      _drawBall(canvas, b);
    }

    _juice.render(canvas);
    canvas.restore();
  }

  // ── Rendering ────────────────────────────────────────────────────────────────

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF101522));
  }

  void _drawRing(Canvas canvas) {
    canvas.drawCircle(
        _center, _ringRadius, Paint()..color = const Color(0xFF202B44));
    canvas.drawCircle(
      _center,
      _ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFFFFC93C),
    );
  }

  /// A bouncy ball: filled disc + rim + two eyes that lean toward travel dir.
  void _drawBall(Canvas canvas, Body b) {
    final color = Color(_colorOf(b.id));
    final body = Paint()..color = color;
    canvas.drawCircle(b.pos, b.radius, body);

    canvas.drawCircle(
      b.pos,
      b.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85),
    );

    // Glossy highlight.
    canvas.drawCircle(
      b.pos + Offset(-b.radius * 0.3, -b.radius * 0.35),
      b.radius * 0.22,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.5),
    );

    _drawFace(canvas, b);
  }

  void _drawFace(Canvas canvas, Body b) {
    final lean = _normalize(b.vel) * (b.radius * _faceWobble);
    final eyeOffset = b.radius * 0.32;
    final eyeR = b.radius * 0.16;
    final pupil = Paint()..color = const Color(0xFF101522);
    final white = Paint()..color = const Color(0xFFFFFFFF);

    for (final sign in const [-1.0, 1.0]) {
      final eye = b.pos + Offset(sign * eyeOffset, -b.radius * 0.1);
      canvas.drawCircle(eye, eyeR, white);
      canvas.drawCircle(eye + lean, eyeR * 0.55, pupil);
    }

    // Small smile arc.
    final smile = Rect.fromCenter(
      center: b.pos + Offset(0, b.radius * 0.28),
      width: b.radius * 0.7,
      height: b.radius * 0.5,
    );
    canvas.drawArc(
      smile,
      0.15 * math.pi,
      0.7 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF101522),
    );
  }

  // ── Pure helpers ──────────────────────────────────────────────────────────────

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

  int _colorOf(int id) {
    for (final p in ctx.players) {
      if (p.id == id) return p.colorArgb;
    }
    return 0xFFFFFFFF;
  }

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

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }
}
