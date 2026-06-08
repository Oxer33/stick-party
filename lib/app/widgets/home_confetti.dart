/// A cheap layer of drifting confetti / sparks for the home menu. A handful of
/// small colored shapes (dots, bars, diamonds) loop slowly upward with a gentle
/// horizontal sway, giving the menu life without any image assets.
///
/// Performance: the particle field is precomputed once (immutable list, no
/// per-frame allocation), a single [Ticker] drives the clock, the painter reuses
/// one [Paint] object, and the whole layer is wrapped in a [RepaintBoundary] +
/// [IgnorePointer] so it never repaints siblings or eats taps.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'glass_tokens.dart';

/// Number of confetti particles (kept low so the layer stays cheap).
const int _kParticleCount = 22;

/// Seconds for one particle to travel the full vertical loop.
const double _kRiseSeconds = 9.0;

/// Palette the particles are tinted from (vivid accents, low alpha).
const List<Color> _kConfettiColors = <Color>[
  GlassColors.violet,
  GlassColors.magenta,
  GlassColors.cyan,
  GlassColors.amber,
  GlassColors.flame,
];

/// The visual kind of one particle.
enum _ConfettiShape { dot, bar, diamond }

/// Immutable description of one drifting particle (normalised 0..1 coords).
class _Particle {
  const _Particle({
    required this.color,
    required this.shape,
    required this.x,
    required this.phase,
    required this.swayAmp,
    required this.swayFreq,
    required this.size,
    required this.spin,
    required this.alpha,
  });

  /// Tint.
  final Color color;

  /// Shape kind.
  final _ConfettiShape shape;

  /// Base horizontal position (fraction of width).
  final double x;

  /// 0..1 offset into the rise loop so particles are spread out in time.
  final double phase;

  /// Horizontal sway amplitude (fraction of width).
  final double swayAmp;

  /// Sway cycles per rise loop.
  final double swayFreq;

  /// Particle size in logical px.
  final double size;

  /// Rotation speed (turns per rise loop) for bars / diamonds.
  final double spin;

  /// Base opacity.
  final double alpha;
}

/// Builds the deterministic particle field once. Seeded by index so the layout
/// is stable across rebuilds (no `Random` per frame).
List<_Particle> _buildParticles() {
  final List<_Particle> out = <_Particle>[];
  final math.Random rng = math.Random(7);
  for (int i = 0; i < _kParticleCount; i++) {
    final _ConfettiShape shape =
        _ConfettiShape.values[i % _ConfettiShape.values.length];
    out.add(
      _Particle(
        color: _kConfettiColors[i % _kConfettiColors.length],
        shape: shape,
        x: rng.nextDouble(),
        phase: rng.nextDouble(),
        swayAmp: 0.02 + rng.nextDouble() * 0.05,
        swayFreq: 0.5 + rng.nextDouble() * 1.5,
        size: 4.0 + rng.nextDouble() * 6.0,
        spin: (rng.nextBool() ? 1 : -1) * (1.0 + rng.nextDouble() * 2.0),
        alpha: 0.18 + rng.nextDouble() * 0.22,
      ),
    );
  }
  return out;
}

/// A drifting confetti layer. Place above the mesh background, below content.
class HomeConfetti extends StatefulWidget {
  const HomeConfetti({super.key});

  @override
  State<HomeConfetti> createState() => _HomeConfettiState();
}

class _HomeConfettiState extends State<HomeConfetti>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  static final List<_Particle> _particles = _buildParticles();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((Duration elapsed) {
      _clock.value = elapsed.inMicroseconds / 1e6;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ConfettiPainter(_clock, _particles),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Paints the particle field for the current clock value. Cheap: reuses a single
/// [Paint], no allocations beyond transient [Offset]s.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.clock, this.particles) : super(repaint: clock);

  final ValueListenable<double> clock;
  final List<_Particle> particles;
  final Paint _paint = Paint()..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = clock.value;
    for (final _Particle p in particles) {
      // Progress 0..1 up the screen (1 = top), looping.
      final double prog = ((t / _kRiseSeconds) + p.phase) % 1.0;
      final double y = (1.0 - prog) * size.height;
      final double sway =
          math.sin(prog * p.swayFreq * math.pi * 2) * p.swayAmp * size.width;
      final double x = p.x * size.width + sway;

      // Fade in at the bottom and out at the top so loops are seamless.
      final double edge = math.min(prog, 1.0 - prog) * 4.0;
      final double a = (p.alpha * edge.clamp(0.0, 1.0)).clamp(0.0, 1.0);
      if (a <= 0.01) continue;

      _paint.color = p.color.withValues(alpha: a);
      _drawShape(canvas, p, Offset(x, y), prog);
    }
  }

  void _drawShape(Canvas canvas, _Particle p, Offset pos, double prog) {
    switch (p.shape) {
      case _ConfettiShape.dot:
        canvas.drawCircle(pos, p.size * 0.5, _paint);
        break;
      case _ConfettiShape.bar:
        _drawRotatedRect(canvas, p, pos, prog, p.size * 1.8, p.size * 0.5);
        break;
      case _ConfettiShape.diamond:
        _drawDiamond(canvas, p, pos, prog);
        break;
    }
  }

  void _drawRotatedRect(Canvas canvas, _Particle p, Offset pos, double prog,
      double w, double h) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(prog * p.spin * math.pi * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Radius.circular(h * 0.5),
      ),
      _paint,
    );
    canvas.restore();
  }

  void _drawDiamond(Canvas canvas, _Particle p, Offset pos, double prog) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(prog * p.spin * math.pi * 2 + math.pi / 4);
    final double r = p.size * 0.6;
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: r, height: r),
      _paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => false;
}
