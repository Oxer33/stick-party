/// An animated "mesh gradient" backdrop: a deep indigo base with a layered
/// aurora field of vivid color blobs that slowly drift in a loop, a slow
/// diagonal light ribbon, faint twinkling speck dust, and a soft corner
/// vignette. A frosted scrim sits on top so foreground glass always reads.
///
/// Performance: the blob/speck sets are precomputed once (const lists, no
/// per-frame allocation), all painting is done in a single [CustomPainter]
/// driven by one [AnimationController], and the whole thing lives under a
/// [RepaintBoundary]. It deliberately AVOIDS a full-screen [ImageFilter.blur]
/// (the menu's old lag source) — radial gradients already fade soft, the
/// ribbon/vignette are single shaders, and specks are tiny additive circles.
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
    required this.alpha,
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

  /// Peak opacity at the blob's core (fades to 0 at its radius).
  final double alpha;
}

/// The precomputed blob field. Front 4 (violet, magenta, cyan, amber) are the
/// bold drifters; the back 3 (small/slow/varied phase) add aurora depth so the
/// field reads full instead of like four separate spotlights. All const → zero
/// per-frame allocation; each is just one radial shader/frame.
const List<_Blob> _kBlobs = <_Blob>[
  // ---- Foreground drifters (large, vivid) ----
  _Blob(
    color: GlassColors.violet,
    center: Offset(0.22, 0.20),
    radius: 0.62,
    driftX: 0.10,
    driftY: 0.06,
    phase: 0.0,
    alpha: 0.55,
  ),
  _Blob(
    color: GlassColors.magenta,
    center: Offset(0.82, 0.30),
    radius: 0.55,
    driftX: 0.08,
    driftY: 0.10,
    phase: 0.25,
    alpha: 0.55,
  ),
  _Blob(
    color: GlassColors.cyan,
    center: Offset(0.30, 0.82),
    radius: 0.58,
    driftX: 0.12,
    driftY: 0.07,
    phase: 0.55,
    alpha: 0.55,
  ),
  _Blob(
    color: GlassColors.amber,
    center: Offset(0.85, 0.85),
    radius: 0.45,
    driftX: 0.07,
    driftY: 0.09,
    phase: 0.80,
    alpha: 0.55,
  ),
  // ---- Background depth blobs (smaller, dimmer, slower-feeling) ----
  // Deep violet pool drifting through the upper-mid for layered depth.
  _Blob(
    color: GlassColors.violet,
    center: Offset(0.58, 0.12),
    radius: 0.34,
    driftX: 0.05,
    driftY: 0.04,
    phase: 0.40,
    alpha: 0.30,
  ),
  // Warm flame ember low-left — breaks the cool/violet symmetry subtly.
  _Blob(
    color: GlassColors.flame,
    center: Offset(0.10, 0.62),
    radius: 0.30,
    driftX: 0.04,
    driftY: 0.06,
    phase: 0.68,
    alpha: 0.26,
  ),
  // Faint cyan haze mid-right to bridge the magenta/amber corner.
  _Blob(
    color: GlassColors.cyan,
    center: Offset(0.92, 0.58),
    radius: 0.28,
    driftX: 0.05,
    driftY: 0.05,
    phase: 0.12,
    alpha: 0.24,
  ),
];

/// Loop period for the drift animation.
const Duration _kLoopDuration = Duration(seconds: 16);

/// A handful of deterministic light specks for faint texture/grain. Positions
/// are const (normalised 0..1) so there's zero per-frame allocation; they twinkle
/// only by a cheap sine on the shared controller. Kept barely visible on purpose.
const List<Offset> _kSpecks = <Offset>[
  Offset(0.14, 0.16),
  Offset(0.37, 0.09),
  Offset(0.61, 0.22),
  Offset(0.78, 0.13),
  Offset(0.91, 0.34),
  Offset(0.08, 0.41),
  Offset(0.27, 0.55),
  Offset(0.49, 0.38),
  Offset(0.69, 0.49),
  Offset(0.86, 0.66),
  Offset(0.18, 0.72),
  Offset(0.41, 0.84),
  Offset(0.57, 0.74),
  Offset(0.73, 0.88),
  Offset(0.93, 0.91),
  Offset(0.05, 0.93),
];

/// Speck radius in logical px (tiny — texture, not stars).
const double _kSpeckRadius = 1.1;

/// Peak speck alpha (very low so it never competes with foreground glass).
const double _kSpeckAlpha = 0.10;

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
        // Drifting aurora field + ribbon + specks + vignette. The radial
        // gradients already fade to transparent, so everything reads soft
        // WITHOUT a full-screen ImageFilter.blur every frame (that blur was the
        // menu's main lag source) — still cheap: a few gradient shaders/frame.
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

/// Paints the layered field (blobs → ribbon → specks → vignette) for a given
/// animation phase. Cheap: a single reused [Paint] whose shader is reassigned
/// per layer — no per-frame allocation beyond shaders, no widget rebuilds, no
/// full-screen blur.
class _MeshPainter extends CustomPainter {
  _MeshPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  /// Reused across blobs and frames; only its shader is reassigned per blob
  /// (the radial center drifts, so the shader itself must be rebuilt, but the
  /// Paint object need not be reallocated 4× per frame on the always-on menu).
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final double t = animation.value; // 0..1
    final double twoPi = 2 * math.pi;
    final double shortest = math.min(size.width, size.height);

    // 1) Drifting aurora blobs (foreground + depth). One radial shader each.
    for (final _Blob blob in _kBlobs) {
      final double angle = (t + blob.phase) * twoPi;
      final double dx = math.cos(angle) * blob.driftX * size.width;
      final double dy = math.sin(angle) * blob.driftY * size.height;
      final Offset center = Offset(
        blob.center.dx * size.width + dx,
        blob.center.dy * size.height + dy,
      );
      final double radius = blob.radius * shortest;

      _paint
        ..blendMode = BlendMode.srcOver
        ..shader = ui.Gradient.radial(
          center,
          radius,
          <Color>[
            blob.color.withValues(alpha: blob.alpha),
            blob.color.withValues(alpha: 0),
          ],
          <double>[0, 1],
        );
      canvas.drawCircle(center, radius, _paint);
    }

    // 2) Aurora ribbon: one wide soft light band sweeping diagonally. A single
    //    linear gradient whose bright stop slides across the canvas over the
    //    loop — gives slow motion interest without any blur. Plus blend so it
    //    reads as added light, not a grey wash.
    _paintAuroraRibbon(canvas, size, t, twoPi);

    // 3) Faint twinkling specks for texture (deterministic positions, cheap).
    _paintSpecks(canvas, size, t, twoPi);

    // 4) Vignette: corners gently darkened so foreground glass pops. Baked as a
    //    single oversized radial (transparent center → base-tinted edge).
    _paintVignette(canvas, size);
  }

  /// A wide, soft light band that slides diagonally across the field. The bright
  /// position is animated along the gradient axis; alpha is low so it's a sheen,
  /// not a streak. One linear shader per frame.
  void _paintAuroraRibbon(Canvas canvas, Size size, double t, double twoPi) {
    // Slow, gentle sweep position (eases via sine so it breathes at the edges).
    final double sweep = (math.sin(t * twoPi) + 1) / 2; // 0..1
    // Band travels along the main diagonal.
    final Offset from = Offset(-size.width * 0.2, -size.height * 0.1);
    final Offset to = Offset(size.width * 1.2, size.height * 1.1);
    // Center the bright stop around `sweep`, with soft falloff either side.
    final double c = (0.12 + sweep * 0.76).clamp(0.12, 0.88);
    final double lo = (c - 0.22).clamp(0.0, 1.0);
    final double hi = (c + 0.22).clamp(0.0, 1.0);

    _paint
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.linear(
        from,
        to,
        <Color>[
          GlassColors.violet.withValues(alpha: 0),
          GlassColors.violet.withValues(alpha: 0.05),
          GlassColors.cyan.withValues(alpha: 0.07),
          GlassColors.violet.withValues(alpha: 0.05),
          GlassColors.violet.withValues(alpha: 0),
        ],
        <double>[
          lo,
          (lo + c) / 2,
          c,
          (c + hi) / 2,
          hi,
        ],
      );
    canvas.drawRect(Offset.zero & size, _paint);
    _paint.blendMode = BlendMode.srcOver;
  }

  /// Tiny deterministic specks that twinkle via a per-speck sine phase. Drawn
  /// with the additive blend so they read as faint light dust.
  void _paintSpecks(Canvas canvas, Size size, double t, double twoPi) {
    _paint
      ..blendMode = BlendMode.plus
      ..shader = null;
    for (int i = 0; i < _kSpecks.length; i++) {
      final Offset s = _kSpecks[i];
      // Stagger twinkle by index; map sine (-1..1) → (0..1) brightness.
      final double tw = (math.sin((t + i * 0.137) * twoPi) + 1) / 2;
      final double a = _kSpeckAlpha * (0.25 + 0.75 * tw);
      _paint.color = GlassColors.frost.withValues(alpha: a);
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        _kSpeckRadius,
        _paint,
      );
    }
    _paint.blendMode = BlendMode.srcOver;
  }

  /// Soft corner darkening so the center (where UI lives) stays lifted. One
  /// oversized radial: transparent core → faint base tint at the edges.
  void _paintVignette(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    // Reach to the corners so darkening is gentlest mid-screen.
    final double radius = math.sqrt(
      size.width * size.width + size.height * size.height,
    ) / 2;
    _paint
      ..blendMode = BlendMode.srcOver
      ..shader = ui.Gradient.radial(
        center,
        radius,
        <Color>[
          GlassColors.base.withValues(alpha: 0),
          GlassColors.base.withValues(alpha: 0),
          GlassColors.base.withValues(alpha: 0.28),
        ],
        <double>[0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant _MeshPainter oldDelegate) => false;
}
