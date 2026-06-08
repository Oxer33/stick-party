/// The home-menu centerpiece: a row of four animated procedural stickmen in the
/// player palette colors (red / blue / green / yellow). Each idles with a gentle
/// breathing bob and periodically throws a celebratory flourish, so the menu
/// reads as a living party lineup rather than a static logo.
///
/// No image assets — everything is the procedural [StickFigure] art.
///
/// Performance: one [Ticker] drives every figure's `update(dt)`; a single
/// [CustomPainter] renders all of them sequentially (the painter's Paint/Path
/// objects are static and reused); the whole widget sits under a
/// [RepaintBoundary] so it never repaints the rest of the menu.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../art/stick/stick_figure.dart';
import '../../art/stick/stick_skeleton.dart';
import '../../art/stick/stick_style.dart';
import '../../core/constants.dart';

/// How many mascots to show (capped at the 4-player palette per the budget).
const int _kMascotCount = 4;

/// Vertical band the lineup is drawn in.
const double _kBandHeight = 132;

/// Figure scale relative to the base hero proportions.
const double _kFigureScale = 1.18;

/// Seconds between a figure's celebratory flourishes.
const double _kCheerPeriod = 3.2;

/// An animated lineup of player-colored stickmen. Drop into the hero section.
class HomeMascots extends StatefulWidget {
  const HomeMascots({super.key, this.height = _kBandHeight});

  /// Height of the drawing band.
  final double height;

  @override
  State<HomeMascots> createState() => _HomeMascotsState();
}

class _HomeMascotsState extends State<HomeMascots>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  final List<_Mascot> _mascots = <_Mascot>[];
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _buildMascots();
    _ticker = createTicker(_onTick)..start();
  }

  void _buildMascots() {
    final StickProportions proportions =
        StickProportions.hero.scaled(_kFigureScale);
    for (int i = 0; i < _kMascotCount; i++) {
      final Color color =
          Color(PlayerPalette.argb[i % PlayerPalette.argb.length]);
      // Inner figures face the centre so the group reads as a crew facing in.
      final double facing = i < _kMascotCount / 2 ? 1.0 : -1.0;
      final StickFigure figure = StickFigure(
        proportions: proportions,
        style: _styleFor(color),
        facing: facing,
      )..setLoco(LocoState.idle);
      _mascots.add(
        _Mascot(
          figure: figure,
          // Stagger phases so the lineup breathes and cheers out of sync.
          bobPhase: i * 0.7,
          cheerOffset: i * (_kCheerPeriod / _kMascotCount),
        ),
      );
    }
  }

  /// A vivid player-colored neon style for a mascot.
  StickStyle _styleFor(Color color) => StickStyle(
        fill: color,
        outline: _brighten(color, 0.5),
        glowSigma: 5,
        lineWidth: 1.1,
        coreColor: _brighten(color, 0.7),
        rimAlpha: 0.3,
        shadowAlpha: 0.0,
        gradientBottom: 0.55,
        smearAlpha: 0.25,
      );

  static Color _brighten(Color c, double t) =>
      Color.lerp(c, const Color(0xFFFFFFFF), t) ?? c;

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    final double clampedDt = dt.clamp(0.0, 0.05);
    final double now = elapsed.inMicroseconds / 1e6;

    for (final _Mascot m in _mascots) {
      m.figure.update(clampedDt);
      m.bob = math.sin((now + m.bobPhase) * 1.6) * 3.0;
      // Fire a flourish on each period boundary (only once per crossing).
      final double cyclePos = (now + m.cheerOffset) % _kCheerPeriod;
      if (cyclePos < m.lastCyclePos && !m.figure.actionPlaying) {
        m.celebrate();
      }
      m.lastCyclePos = cyclePos;
    }
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _MascotPainter(_frame, _mascots),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Per-figure animation bookkeeping (mutable; lives for the widget's lifetime).
class _Mascot {
  _Mascot({
    required this.figure,
    required this.bobPhase,
    required this.cheerOffset,
  });

  final StickFigure figure;
  final double bobPhase;
  final double cheerOffset;

  /// Current vertical bob offset (px).
  double bob = 0;

  /// Tracks the cheer cycle to detect period wrap-around.
  double lastCyclePos = 0;

  /// Alternates between two celebratory flourishes for variety.
  bool _flip = false;

  void celebrate() {
    if (_flip) {
      figure.special();
    } else {
      figure.dash();
    }
    _flip = !_flip;
  }
}

/// Renders the mascot lineup. The figures are laid out evenly across the width
/// and vertically anchored so their feet sit near the band's bottom.
class _MascotPainter extends CustomPainter {
  _MascotPainter(this.repaintFrame, this.mascots) : super(repaint: repaintFrame);

  final ValueListenable<int> repaintFrame;
  final List<_Mascot> mascots;

  @override
  void paint(Canvas canvas, Size size) {
    if (mascots.isEmpty) return;
    final int n = mascots.length;
    // Pelvis baseline: leave room for the legs below it (~thigh+shin) plus a
    // little ground breathing space.
    final double baseline = size.height * 0.72;
    final double slot = size.width / n;

    for (int i = 0; i < n; i++) {
      final _Mascot m = mascots[i];
      final double cx = slot * (i + 0.5);
      final Offset root = Offset(cx, baseline + m.bob);
      // Soft ground glow under each mascot for grounding.
      _drawGroundGlow(canvas, m, root, slot);
      m.figure.render(canvas, root);
    }
  }

  void _drawGroundGlow(Canvas canvas, _Mascot m, Offset root, double slot) {
    final Color tint = m.figure.style.outline;
    final double gy = root.dy + 56;
    final Paint glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(root.dx, gy),
        slot * 0.42,
        <Color>[
          tint.withValues(alpha: 0.20),
          tint.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(Offset(root.dx, gy), slot * 0.42, glow);
  }

  @override
  bool shouldRepaint(covariant _MascotPainter oldDelegate) => false;
}
