/// An animated "mesh gradient" backdrop: a deep indigo base with a handful of
/// large, blurred, vivid color blobs that slowly drift in a loop. A faint
/// frosted scrim sits on top so foreground glass always reads.
///
/// Performance: the blob set is precomputed once (const list, no per-frame
/// allocation), painting is done in a single [CustomPainter] driven by one
/// [AnimationController], and the whole thing lives under a [RepaintBoundary].
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// Immutable description of one drifting blob (normalised 0..1 coordinates).
class _Blob {
  const _Blob({
    required this.color,
    required this.center,
    required this.radius,
    required this.driftX,
    required this.driftY,
    required this.phase,
  });

  /// Blob color (drawn at low opacity).
  final Color color;

  /// Base center as a fraction of the canvas.
  final Offset center;

  /// Radius as a fraction of the canvas' shortest side.
  final double radius;

  /// Horizontal drift amplitude (fraction of width).
  final double driftX;

  /// Vertical drift amplitude (fraction of height).
  final double driftY;

  /// Phase offset (0..1) so blobs don't move in lockstep.
  final double phase;
}

/// The precomputed blob field (4 blobs: violet, magenta, cyan, amber).
const List<_Blob> _kBlobs = <_Blob>[
  _Blob(
    color: GlassColors.violet,
    center: Offset(0.22, 0.20),
    radius: 0.62,
    driftX: 0.10,
    driftY: 0.06,
    phase: 0.0,
  ),
  _Blob(
    color: GlassColors.magenta,
    center: Offset(0.82, 0.30),
    radius: 0.55,
    driftX: 0.08,
    driftY: 0.10,
    phase: 0.25,
  ),
  _Blob(
    color: GlassColors.cyan,
    center: Offset(0.30, 0.82),
    radius: 0.58,
    driftX: 0.12,
    driftY: 0.07,
    phase: 0.55,
  ),
  _Blob(
    color: GlassColors.amber,
    center: Offset(0.85, 0.85),
    radius: 0.45,
    driftX: 0.07,
    driftY: 0.09,
    phase: 0.80,
  ),
];

/// Per-blob alpha (kept low so accents stay subtle and text reads).
const double _kBlobAlpha = 0.55;

/// Loop period for the drift animation.
const Duration _kLoopDuration = Duration(seconds: 16);

/// Animated mesh-gradient background. Place once at the root of a screen.
class MeshGradientBackground extends StatefulWidget {
  const MeshGradientBackground({super.key, required this.child});

  /// Foreground content drawn above the mesh + scrim.
  final Widget child;

  @override
  State<MeshGradientBackground> createState() => _MeshGradientBackgroundState();
}

class _MeshGradientBackgroundState extends State<MeshGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kLoopDuration,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Deep base gradient.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[GlassColors.baseHigh, GlassColors.base],
            ),
          ),
        ),
        // Drifting glow blobs. The radial gradients already fade to transparent,
        // so they read soft WITHOUT a full-screen ImageFilter.blur every frame
        // (that blur was the menu's main lag source) — now cheap: 4 gradients/frame.
        RepaintBoundary(
          child: CustomPaint(
            painter: _MeshPainter(_controller),
            size: Size.infinite,
          ),
        ),
        // Faint frosted scrim so foreground glass always reads.
        DecoratedBox(
          decoration: BoxDecoration(
            color: GlassColors.base.withValues(alpha: 0.28),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Paints the blob field for a given animation phase. Cheap: only Paint +
/// gradient shader creation per blob per frame (no widget rebuilds).
class _MeshPainter extends CustomPainter {
  _MeshPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = animation.value; // 0..1
    final double shortest = math.min(size.width, size.height);

    for (final _Blob blob in _kBlobs) {
      final double angle = (t + blob.phase) * 2 * math.pi;
      final double dx = math.cos(angle) * blob.driftX * size.width;
      final double dy = math.sin(angle) * blob.driftY * size.height;
      final Offset center = Offset(
        blob.center.dx * size.width + dx,
        blob.center.dy * size.height + dy,
      );
      final double radius = blob.radius * shortest;

      final Paint paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          <Color>[
            blob.color.withValues(alpha: _kBlobAlpha),
            blob.color.withValues(alpha: 0),
          ],
          <double>[0, 1],
        );
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) => false;
}
