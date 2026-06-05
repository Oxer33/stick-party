import 'dart:math' as math;
import 'dart:ui';

import '../../core/constants.dart';
import '../../core/rng.dart';

/// Drawn shape of a particle.
enum ParticleShape { circle, square, spark }

/// One lightweight particle. Mutated in place each frame (hot path).
class Particle {
  Offset pos;
  Offset vel;
  double life; // remaining seconds
  final double maxLife;
  double size;
  final Color color;
  final double gravity;
  final double drag; // per-second velocity retention factor base
  final ParticleShape shape;
  double rot;
  final double rotVel;

  Particle({
    required this.pos,
    required this.vel,
    required this.life,
    required this.size,
    required this.color,
    this.gravity = 0,
    this.drag = 0.9,
    this.shape = ParticleShape.circle,
    this.rot = 0,
    this.rotVel = 0,
  }) : maxLife = life;

  bool get dead => life <= 0;
  double get t => (life / maxLife).clamp(0.0, 1.0); // 1 → 0 over lifetime

  void update(double dt) {
    life -= dt;
    final retain = math.pow(drag, dt * 60).toDouble();
    vel = Offset(vel.dx * retain, vel.dy * retain + gravity * dt);
    pos += vel * dt;
    rot += rotVel * dt;
  }
}

/// Pooled particle emitter + renderer. Pure Canvas; no Flame dependency so it
/// is usable inside any [MiniGame.render]. Soft-capped to protect framerate.
class ParticleSystem {
  final List<Particle> _particles = <Particle>[];
  final SeededRng _rng;

  ParticleSystem([SeededRng? rng]) : _rng = rng ?? SeededRng();

  int get count => _particles.length;
  bool get isEmpty => _particles.isEmpty;

  /// Radial burst (hit / KO / pop).
  void burst({
    required Offset at,
    required int count,
    required Color color,
    double speed = 220,
    double spread = math.pi * 2,
    double baseAngle = -math.pi / 2,
    double size = 6,
    double gravity = 600,
    double life = 0.6,
    ParticleShape shape = ParticleShape.spark,
  }) {
    for (var i = 0; i < count; i++) {
      final a = baseAngle + _rng.jitter(spread / 2);
      final sp = speed * _rng.range(0.5, 1.0);
      _particles.add(Particle(
        pos: at,
        vel: Offset(math.cos(a) * sp, math.sin(a) * sp),
        life: life * _rng.range(0.7, 1.1),
        size: size * _rng.range(0.7, 1.2),
        color: color,
        gravity: gravity,
        drag: 0.86,
        shape: shape,
        rot: _rng.range(0, math.pi),
        rotVel: _rng.jitter(8),
      ));
    }
    _enforceCap();
  }

  /// Celebration confetti raining across [area].
  void confetti(Size area, {int count = 60, List<Color> colors = const []}) {
    final palette = colors.isEmpty
        ? PlayerPalette.argb.map((c) => Color(c)).toList()
        : colors;
    for (var i = 0; i < count; i++) {
      _particles.add(Particle(
        pos: Offset(_rng.range(0, area.width), _rng.range(-area.height * 0.2, 0)),
        vel: Offset(_rng.jitter(60), _rng.range(120, 260)),
        life: _rng.range(1.4, 2.6),
        size: _rng.range(5, 10),
        color: palette[i % palette.length],
        gravity: 80,
        drag: 0.98,
        shape: ParticleShape.square,
        rot: _rng.range(0, math.pi),
        rotVel: _rng.jitter(10),
      ));
    }
    _enforceCap();
  }

  void update(double dt) {
    for (final p in _particles) {
      p.update(dt);
    }
    _particles.removeWhere((p) => p.dead);
  }

  void render(Canvas canvas) {
    final paint = Paint();
    for (final p in _particles) {
      paint.color = p.color.withValues(alpha: p.color.a * p.t.clamp(0.0, 1.0));
      switch (p.shape) {
        case ParticleShape.circle:
          canvas.drawCircle(p.pos, p.size * p.t, paint);
        case ParticleShape.square:
          canvas.save();
          canvas.translate(p.pos.dx, p.pos.dy);
          canvas.rotate(p.rot);
          final s = p.size;
          canvas.drawRect(
              Rect.fromCenter(center: Offset.zero, width: s, height: s), paint);
          canvas.restore();
        case ParticleShape.spark:
          final dir = p.vel.distance < 1
              ? const Offset(0, -1)
              : p.vel / p.vel.distance;
          final tail = p.pos - dir * (p.size * 2.2);
          paint.strokeWidth = p.size * 0.6;
          paint.strokeCap = StrokeCap.round;
          canvas.drawLine(tail, p.pos, paint);
      }
    }
  }

  void clear() => _particles.clear();

  void _enforceCap() {
    final overflow = _particles.length - Feel.particleSoftCap;
    if (overflow > 0) _particles.removeRange(0, overflow);
  }
}
