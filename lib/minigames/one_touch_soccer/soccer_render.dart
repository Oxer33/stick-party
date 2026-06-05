import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// One side's accent + score, packaged so the renderer never reaches into game
/// state. Immutable value type.
class SoccerSide {
  /// Accent color for this side's goal net, scoreboard chip and ground rings.
  final Color color;

  /// Current score shown on the scoreboard.
  final int score;

  /// Short label (e.g. "L"/"R" or a team letter) shown on the scoreboard chip.
  final String label;

  const SoccerSide({
    required this.color,
    required this.score,
    required this.label,
  });
}

/// A drawable snapshot of one player for the renderer. Immutable value type so
/// the renderer stays a pure function of its inputs.
class SoccerActor {
  final StickFigure figure;

  /// Pelvis/render anchor for the figure (feet planted on the ground line).
  final Offset root;

  /// Ground-contact center (feet) used for the shadow + ground ring.
  final Offset feet;

  /// Footprint radius used to size the shadow / ground ring.
  final double radius;

  /// Side accent color (also the ground-ring color).
  final Color color;

  /// 1-based number drawn in the ground ring.
  final int number;

  /// 0..1 lunge charge used to brighten/scale the ground ring on a kick.
  final double kickFlash;

  const SoccerActor({
    required this.figure,
    required this.root,
    required this.feet,
    required this.radius,
    required this.color,
    required this.number,
    this.kickFlash = 0,
  });
}

/// Pure-Canvas rendering for One-Touch Soccer. Holds NO game state and never
/// mutates the simulation — callers pass plain value snapshots. Kept in its own
/// file so the gameplay module stays lean and the drawing stays cohesive.
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class SoccerRenderer {
  SoccerRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _stadiumTop = Color(0xFF0A1A12);
  static const Color _stadiumBottom = Color(0xFF03070A);
  static const Color _turfLight = Color(0xFF2BA85A);
  static const Color _turfDark = Color(0xFF1F8E49);
  static const Color _turfShadeTop = Color(0x33A8FFC8);
  static const Color _turfShadeBottom = Color(0x33000000);
  static const Color _border = Color(0xFF05130B);
  static const Color _line = Color(0xFFF2FFF6);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _ballSeam = Color(0xFF12202B);
  static const Color _crowdGlow = Color(0x1AFFFFFF);

  // ── Tuning (no magic numbers inline) ───────────────────────────────────────
  static const int _stripeCount = 10;
  static const double _lineWidthFactor = 0.006; // line stroke / pitch shortSide
  static const double _centerCircleFactor = 0.13; // radius / shortSide
  static const double _penaltyDepthFactor = 0.16; // box depth / pitch width
  static const double _penaltyHeightFactor = 0.52; // box height / pitch height
  static const double _netCellFactor = 0.16; // net cell / mouth height
  static const double _postWidthFactor = 0.018; // post stroke / pitch shortSide
  static const double _goalDepthFactor = 0.05; // net depth / pitch width
  static const double _vignetteFactor = 0.62; // vignette inset
  static const double _ballTrailStep = 0.55; // trail node spacing fade
  static const double _shadowDropFactor = 1.1; // ball shadow drop / radius
  static const double _scoreboardHeightFactor = 0.052; // of pitch height
  static const double _twoPi = math.pi * 2;

  // ── Background: stadium gradient + dark crowd haze ─────────────────────────
  static void drawBackground(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_stadiumTop, _stadiumBottom],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // Soft crowd glow band near the top edge for stadium depth.
    final glow = Paint()
      ..shader = Gradient.radial(
        Offset(size.width / 2, size.height * 0.06),
        size.width * 0.7,
        const [_crowdGlow, Color(0x00000000)],
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  /// The pitch: dark stadium border, alternating mowed stripes (with a subtle
  /// top-light / bottom-shade overlay), perimeter line, center line + circle and
  /// both penalty boxes.
  static void drawPitch(Canvas canvas, Rect pitch) {
    if (pitch.width <= 2 || pitch.height <= 2) return;
    final shortSide = pitch.shortestSide;
    final lineW = math.max(1.5, shortSide * _lineWidthFactor);

    // Stadium-dark border ring just outside the pitch.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        pitch.inflate(shortSide * 0.02),
        Radius.circular(shortSide * 0.03),
      ),
      Paint()..color = _border,
    );

    // Mowed vertical stripes.
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      pitch,
      Radius.circular(shortSide * 0.02),
    ));
    final stripeW = pitch.width / _stripeCount;
    final stripePaint = Paint();
    for (var i = 0; i < _stripeCount; i++) {
      stripePaint.color = i.isEven ? _turfLight : _turfDark;
      canvas.drawRect(
        Rect.fromLTWH(
          pitch.left + i * stripeW,
          pitch.top,
          stripeW + 1,
          pitch.height,
        ),
        stripePaint,
      );
    }
    // Vertical light → shade gradient overlay for grassy depth.
    canvas.drawRect(
      pitch,
      Paint()
        ..shader = Gradient.linear(
          pitch.topCenter,
          pitch.bottomCenter,
          const [_turfShadeTop, Color(0x00000000), _turfShadeBottom],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.restore();

    _drawMarkings(canvas, pitch, lineW);
  }

  static void _drawMarkings(Canvas canvas, Rect pitch, double lineW) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineW
      ..color = _line.withValues(alpha: 0.82);

    // Perimeter.
    canvas.drawRect(pitch.deflate(lineW), line);

    // Center line + circle + spot.
    canvas.drawLine(
      Offset(pitch.center.dx, pitch.top + lineW),
      Offset(pitch.center.dx, pitch.bottom - lineW),
      line,
    );
    final circleR = pitch.shortestSide * _centerCircleFactor;
    canvas.drawCircle(pitch.center, circleR, line);
    canvas.drawCircle(
        pitch.center, math.max(2.0, lineW * 1.4), Paint()..color = _line);

    // Penalty boxes on each side, centered vertically.
    final boxDepth = pitch.width * _penaltyDepthFactor;
    final boxHeight = pitch.height * _penaltyHeightFactor;
    final boxTop = pitch.center.dy - boxHeight / 2;
    canvas.drawRect(
      Rect.fromLTWH(pitch.left + lineW, boxTop, boxDepth, boxHeight),
      line,
    );
    canvas.drawRect(
      Rect.fromLTWH(
          pitch.right - lineW - boxDepth, boxTop, boxDepth, boxHeight),
      line,
    );
  }

  /// A goal: a netted mouth on one wall. [onRight] selects the right wall (else
  /// left). [bulge] in 0..1 flashes a net ripple after a recent goal.
  static void drawGoal(
    Canvas canvas,
    Rect pitch,
    Rect mouth, {
    required bool onRight,
    required Color color,
    required double bulge,
  }) {
    if (mouth.height <= 2) return;
    final shortSide = pitch.shortestSide;
    final depth = pitch.width * _goalDepthFactor;
    final x = onRight ? pitch.right : pitch.left;
    final inward = onRight ? -1.0 : 1.0;
    final backX = x - inward * depth;
    final mouthH = mouth.height;
    final cell = math.max(6.0, mouthH * _netCellFactor);

    // Net recess background (dim) so the mesh reads against the turf.
    final recess = Rect.fromLTRB(
      math.min(x, backX),
      mouth.top,
      math.max(x, backX),
      mouth.bottom,
    );
    canvas.drawRect(recess, Paint()..color = _black.withValues(alpha: 0.30));

    // Net bulge ripple after a goal: a soft colored swell pushed into the net.
    final b = bulge.clamp(0.0, 1.0);
    if (b > 0.01) {
      final swell = Paint()
        ..shader = Gradient.radial(
          Offset(backX, mouth.center.dy),
          depth * 1.6,
          [color.withValues(alpha: 0.5 * b), const Color(0x00000000)],
        );
      canvas.drawRect(recess, swell);
    }

    // Net mesh: vertical + horizontal strands, slightly displaced by the bulge.
    final mesh = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, shortSide * 0.0025)
      ..color = _white.withValues(alpha: 0.34 + 0.30 * b);
    final push = inward * depth * 0.4 * b;
    for (var gx = 0.0; gx <= depth; gx += cell) {
      final sx = x - inward * gx;
      canvas.drawLine(
          Offset(sx, mouth.top), Offset(sx, mouth.bottom), mesh);
    }
    for (var gy = mouth.top; gy <= mouth.bottom; gy += cell) {
      // Mid strands sag toward the back when the net bulges.
      final t = ((gy - mouth.top) / mouthH - 0.5).abs() * 2; // 0 mid → 1 edge
      final sag = push * (1 - t);
      canvas.drawLine(
        Offset(x, gy),
        Offset(backX + sag, gy),
        mesh,
      );
    }

    // Posts + crossbars in the side accent.
    final postW = math.max(2.5, shortSide * _postWidthFactor);
    final post = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = postW
      ..strokeCap = StrokeCap.round
      ..color = color;
    // Front goal line (the mouth) glows in the accent.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = postW * 1.6
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, postW);
    canvas.drawLine(Offset(x, mouth.top), Offset(x, mouth.bottom), glow);
    canvas.drawLine(Offset(x, mouth.top), Offset(x, mouth.bottom), post);
    // Top + bottom bars receding to the back of the net.
    canvas.drawLine(Offset(x, mouth.top), Offset(backX, mouth.top), post);
    canvas.drawLine(
        Offset(x, mouth.bottom), Offset(backX, mouth.bottom), post);
    canvas.drawLine(
        Offset(backX, mouth.top), Offset(backX, mouth.bottom), post);
  }

  /// Soft contact shadow ellipse + a colored ground ring with a number, drawn
  /// beneath one player. [kickFlash] in 0..1 brightens the ring on a lunge.
  static void drawActorGround(Canvas canvas, SoccerActor a) {
    final r = a.radius;
    // Shadow.
    canvas.drawOval(
      Rect.fromCenter(center: a.feet, width: r * 2.6, height: r * 0.8),
      Paint()
        ..color = _black.withValues(alpha: 0.34)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );
    // Ground ring (brightens with kick charge).
    final flash = a.kickFlash.clamp(0.0, 1.0);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, r * (0.12 + 0.10 * flash))
      ..color = Color.lerp(a.color.withValues(alpha: 0.9), _white, 0.5 * flash) ??
          a.color;
    canvas.drawOval(
      Rect.fromCenter(center: a.feet, width: r * 3.0, height: r * 1.05),
      ring,
    );
    // Number pip.
    final pip = a.feet.translate(0, r * 0.04);
    final pr = r * 0.42;
    canvas.drawCircle(pip, pr, Paint()..color = a.color);
    canvas.drawCircle(
      pip,
      pr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, pr * 0.2)
        ..color = _white.withValues(alpha: 0.85),
    );
    _drawText(canvas, '${a.number}', pip, pr * 1.3, _readableText(a.color),
        FontWeight.w900);
  }

  /// Render the stick player itself (figure owns its own pose state).
  static void drawActor(Canvas canvas, SoccerActor a) {
    a.figure.render(canvas, a.root);
  }

  /// The ball: motion trail → contact shadow → white body with a faint
  /// pentagon/seam hint and a directional highlight. [squash] in 0..1 flattens
  /// it along [velDir] after a hard hit; [trail] is newest→oldest centers.
  static void drawBall(
    Canvas canvas,
    Offset pos,
    double radius, {
    required List<Offset> trail,
    required Offset velDir,
    required double spin,
    required double squash,
  }) {
    if (radius <= 0) return;

    // Motion trail: fading discs behind the ball.
    if (trail.length > 1) {
      final paint = Paint();
      for (var i = trail.length - 1; i >= 0; i--) {
        final f = (i + 1) / trail.length; // 1 newest → ~0 oldest
        paint.color = _white.withValues(alpha: 0.18 * f * _ballTrailStep);
        canvas.drawCircle(trail[i], radius * (0.5 + 0.5 * f), paint);
      }
    }

    // Contact shadow on the turf.
    canvas.drawOval(
      Rect.fromCenter(
        center: pos.translate(0, radius * _shadowDropFactor),
        width: radius * 2.0,
        height: radius * 0.7,
      ),
      Paint()
        ..color = _black.withValues(alpha: 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.25),
    );

    // Squash transform: flatten along travel direction, stretch across it.
    final s = squash.clamp(0.0, 1.0);
    final ang = velDir == Offset.zero ? 0.0 : math.atan2(velDir.dy, velDir.dx);
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(ang);
    canvas.scale(1.0 - 0.30 * s, 1.0 + 0.22 * s);
    canvas.rotate(-ang);

    // Body with a soft top-left sheen.
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = Gradient.radial(
          Offset(-radius * 0.3, -radius * 0.35),
          radius * 1.5,
          const [_white, Color(0xFFD7E2EC)],
        ),
    );

    // Faint pentagon seam hint, rotated by spin.
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, radius * 0.10)
      ..strokeJoin = StrokeJoin.round
      ..color = _ballSeam.withValues(alpha: 0.55);
    final penta = Path();
    for (var i = 0; i < 5; i++) {
      final a = spin + i * _twoPi / 5 - math.pi / 2;
      final p = Offset(math.cos(a), math.sin(a)) * radius * 0.5;
      if (i == 0) {
        penta.moveTo(p.dx, p.dy);
      } else {
        penta.lineTo(p.dx, p.dy);
      }
    }
    penta.close();
    canvas.drawPath(penta, seam);
    // Short spokes from the pentagon corners to the rim.
    for (var i = 0; i < 5; i++) {
      final a = spin + i * _twoPi / 5 - math.pi / 2;
      final inner = Offset(math.cos(a), math.sin(a)) * radius * 0.5;
      final outer = Offset(math.cos(a), math.sin(a)) * radius * 0.92;
      canvas.drawLine(inner, outer, seam);
    }

    // Crisp outline.
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, radius * 0.12)
        ..color = _ballSeam,
    );
    canvas.restore();
  }

  /// A vignette darkening the screen corners for stadium focus.
  static void drawVignette(Canvas canvas, Size size) {
    final r = size.longestSide * _vignetteFactor;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height / 2),
          r,
          const [Color(0x00000000), Color(0x66000000)],
          const [0.62, 1.0],
        ),
    );
  }

  /// A scoreboard at the top: two color chips with each side's score and a
  /// countdown clock in the middle. [secondsLeft] is clamped to ≥ 0.
  static void drawScoreboard(
    Canvas canvas,
    Rect pitch,
    SoccerSide left,
    SoccerSide right,
    double secondsLeft,
  ) {
    final h = math.max(22.0, pitch.height * _scoreboardHeightFactor);
    final w = math.min(pitch.width * 0.62, h * 7.5);
    final center = Offset(pitch.center.dx, pitch.top + h * 0.9);
    final bar = Rect.fromCenter(center: center, width: w, height: h);
    final rrect = RRect.fromRectAndRadius(bar, Radius.circular(h * 0.32));

    // Backing panel.
    canvas.drawRRect(
        rrect, Paint()..color = _black.withValues(alpha: 0.55));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, h * 0.06)
        ..color = _white.withValues(alpha: 0.16),
    );

    // Left chip.
    final chipW = h * 1.5;
    _drawScoreChip(
      canvas,
      Rect.fromLTWH(bar.left, bar.top, chipW, h),
      left.color,
      '${left.score}',
      left.label,
    );
    // Right chip.
    _drawScoreChip(
      canvas,
      Rect.fromLTWH(bar.right - chipW, bar.top, chipW, h),
      right.color,
      '${right.score}',
      right.label,
    );

    // Clock in the middle.
    final secs = secondsLeft.clamp(0.0, 5999.0);
    final mm = (secs ~/ 60).toString();
    final ss = (secs % 60).floor().toString().padLeft(2, '0');
    _drawText(canvas, '$mm:$ss', center.translate(0, -h * 0.02), h * 0.5,
        _white, FontWeight.w800);
  }

  static void _drawScoreChip(
    Canvas canvas,
    Rect rect,
    Color color,
    String score,
    String label,
  ) {
    final rr = RRect.fromRectAndRadius(
        rect.deflate(rect.height * 0.12), Radius.circular(rect.height * 0.26));
    canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: 0.9));
    _drawText(canvas, score, rect.center.translate(0, -rect.height * 0.02),
        rect.height * 0.5, _readableText(color), FontWeight.w900);
    // Tiny side label above the number.
    _drawText(
        canvas,
        label,
        rect.center.translate(0, -rect.height * 0.42),
        rect.height * 0.22,
        _readableText(color).withValues(alpha: 0.85),
        FontWeight.w700);
  }

  /// A centered kickoff banner during the brief pause before the next kickoff.
  /// [alpha] fades it in/out.
  static void drawKickoffBanner(
    Canvas canvas,
    Rect pitch,
    String text,
    double alpha,
  ) {
    final a = alpha.clamp(0.0, 1.0);
    if (a <= 0.01) return;
    final fontSize = pitch.shortestSide * 0.085;
    _drawText(canvas, text, pitch.center, fontSize,
        _white.withValues(alpha: a), FontWeight.w900);
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color,
    FontWeight weight,
  ) {
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: weight,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: fontSize * 8));
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - fontSize * 4, center.dy - fontSize * 0.62),
    );
  }
}
