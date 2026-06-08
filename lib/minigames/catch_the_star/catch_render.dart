import 'dart:math' as math;
import 'dart:ui';

/// Pure-Canvas rendering for [CatchTheStar] — a glowing star wandering a night
/// sky while player-colored catchers try to snatch it. Holds NO game state and
/// never mutates the simulation: callers pass plain value snapshots. Kept in its
/// own file so the gameplay module stays lean and the drawing stays cohesive
/// (mirrors the sumo_smash / tap_sprint split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class CatchRenderer {
  CatchRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _skyTop = Color(0xFF0B1030); // deep midnight blue
  static const Color _skyMid = Color(0xFF141A47); // indigo band
  static const Color _skyBottom = Color(0xFF1E1140); // violet horizon glow
  static const Color _skyHaze = Color(0xFF2A1A55); // low atmospheric haze
  static const Color _moonCore = Color(0xFFF4F0DC);
  static const Color _moonEdge = Color(0xFFBFC6E8);
  static const Color _moonHalo = Color(0xFF8FA0E8);
  static const Color _moonCrater = Color(0x223A4170);
  static const Color _bgStar = Color(0xFFFFFFFF);
  static const Color _bgStarWarm = Color(0xFFFFE9B8);
  static const Color _bgStarCool = Color(0xFFB9D2FF);
  static const Color _vignette = Color(0xAA04030C);
  static const Color _starGold = Color(0xFFFFF1A8); // normal star body
  static const Color _starGoldHot = Color(0xFFFFFFFF); // star core
  static const Color _starGlow = Color(0xFFFFD24A); // normal star halo
  static const Color _bonusGold = Color(0xFFFFE070); // golden bonus body
  static const Color _bonusGlow = Color(0xFFFF9E1B); // golden bonus halo
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _urgent = Color(0xFFFF6B6B);

  // ── Tuning (fractions / px; no inline magic numbers) ───────────────────────
  static const double _moonCenterXFrac = 0.74; // moon x / width
  static const double _moonCenterYFrac = 0.18; // moon y / height
  static const double _moonRadiusFrac = 0.085; // moon radius / width
  static const double _moonHaloFactor = 2.6; // halo radius / moon radius
  static const double _vignInnerFrac = 0.42;
  static const double _vignOuterFrac = 0.82;

  // Catcher (glowing ring / net / hands) tuning, in fractions of `reach`.
  static const double _catcherRingFactor = 1.0; // outer snatch ring / reach
  static const double _catcherInnerFactor = 0.62; // net inner ring / reach
  static const double _catcherHubFactor = 0.2; // solid hub / reach
  static const int _catcherNetSpokes = 8; // net cross-strands
  static const double _catcherGlowFactor = 1.22; // soft glow ring / reach

  // Target star tuning, in fractions of the star outer radius `r`.
  static const double _starInnerFactor = 0.44; // inner / outer radius
  static const double _starHaloFactor = 2.7; // glow halo / outer radius
  static const double _starCoreFactor = 0.3; // bright core / outer radius
  static const int _starPoints = 5;
  static const int _goldenRays = 8; // sparkle-crown rays on a bonus star

  // Comet trail tuning.
  static const double _trailWidthFactor = 0.9; // head width / star radius

  // ── Background: night-sky gradient + soft horizon haze + a glowing moon ─────
  static void drawBackground(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_skyTop, _skyMid, _skyBottom, _skyHaze],
        const [0.0, 0.45, 0.82, 1.0],
      );
    canvas.drawRect(Offset.zero & size, sky);
    _drawMoon(canvas, size);
  }

  static void _drawMoon(Canvas canvas, Size size) {
    final center =
        Offset(size.width * _moonCenterXFrac, size.height * _moonCenterYFrac);
    final r = size.width * _moonRadiusFrac;
    if (r <= 1) return;

    // Wide cool halo.
    canvas.drawCircle(
      center,
      r * _moonHaloFactor,
      Paint()
        ..shader = Gradient.radial(
          center,
          r * _moonHaloFactor,
          [_moonHalo.withValues(alpha: 0.30), const Color(0x00000000)],
        ),
    );
    // Moon disc with a soft terminator (light from upper-right).
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = Gradient.radial(
          center.translate(r * 0.28, -r * 0.28),
          r * 1.25,
          const [_moonCore, _moonEdge],
          const [0.0, 1.0],
        ),
    );
    // A few faint craters for character.
    final crater = Paint()..color = _moonCrater;
    canvas.drawCircle(center.translate(-r * 0.3, r * 0.18), r * 0.22, crater);
    canvas.drawCircle(center.translate(r * 0.22, r * 0.34), r * 0.14, crater);
    canvas.drawCircle(center.translate(r * 0.12, -r * 0.3), r * 0.1, crater);
  }

  /// Parallax field of twinkling background stars. [stars] are fixed unit-space
  /// points (x,y in 0..1); [seeds] packs a per-star depth in its fractional part
  /// (0..1) plus a phase in its integer part. The sim clock [t] drives the
  /// twinkle so the field shimmers without any state held here.
  static void drawBackgroundStars(
    Canvas canvas,
    Size size,
    List<Offset> stars,
    List<double> seeds,
    double t,
  ) {
    if (stars.isEmpty) return;
    final paint = Paint();
    for (var i = 0; i < stars.length; i++) {
      final s = stars[i];
      final seed = i < seeds.length ? seeds[i] : i.toDouble();
      final depth = seed - seed.floorToDouble(); // fractional part 0..1 = depth
      // Nearer stars (higher depth) are bigger + brighter and twinkle slower.
      final twinkle =
          0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * (1.1 + depth) + seed * 7.0));
      final radius = 0.6 + depth * 1.9;
      final hue = _bgHue(i % 3);
      paint.color =
          hue.withValues(alpha: (twinkle * (0.3 + depth * 0.6)).clamp(0.0, 1.0));
      final px = s.dx * size.width;
      final py = s.dy * size.height;
      canvas.drawCircle(Offset(px, py), radius, paint);
      // Brightest stars get a tiny cross sparkle.
      if (depth > 0.82) {
        final arm = radius * 3.4;
        final spark = Paint()
          ..color = hue.withValues(alpha: (twinkle * 0.5).clamp(0.0, 1.0))
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(px - arm, py), Offset(px + arm, py), spark);
        canvas.drawLine(Offset(px, py - arm), Offset(px, py + arm), spark);
      }
    }
  }

  static Color _bgHue(int i) {
    switch (i) {
      case 0:
        return _bgStarWarm;
      case 1:
        return _bgStarCool;
      default:
        return _bgStar;
    }
  }

  /// Crowd-dark vignette so the action pops (drawn over the sky, under the
  /// catchers + star).
  static void drawVignette(Canvas canvas, Size size) {
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final outer = diag * _vignOuterFrac;
    final inner = diag * _vignInnerFrac;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.52),
          outer,
          [const Color(0x00000000), _vignette],
          [(inner / outer).clamp(0.0, 0.99), 1.0],
        ),
    );
  }

  /// A player's catcher: a glowing ring "net" anchored at [center] in their
  /// [color], sized to its snatch [reach]. [flash] in 0..1 (a recent snatch)
  /// brightens + thickens the ring and blooms a halo. [armed] in 0..1 swells the
  /// ring gently while the star is in range (telegraph). [displayNumber] is the
  /// 1-based player label drawn on the hub. [t] is the sim clock (net spin).
  static void drawCatcher(
    Canvas canvas,
    Offset center,
    double reach,
    Color color,
    int displayNumber, {
    double flash = 0,
    double armed = 0,
    double t = 0,
  }) {
    if (reach <= 1) return;
    final f = flash.clamp(0.0, 1.0);
    final a = armed.clamp(0.0, 1.0);
    final swell = 1.0 + 0.06 * a + 0.18 * f;
    final ringR = reach * _catcherRingFactor * swell;

    // Soft outer bloom (much stronger on a fresh snatch).
    canvas.drawCircle(
      center,
      reach * _catcherGlowFactor * swell,
      Paint()
        ..shader = Gradient.radial(
          center,
          reach * _catcherGlowFactor * swell,
          [
            color.withValues(
                alpha: (0.12 + 0.4 * f + 0.08 * a).clamp(0.0, 1.0)),
            const Color(0x00000000),
          ],
        ),
    );

    // Outer snatch ring.
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, reach * (0.05 + 0.06 * f))
        ..color = color.withValues(alpha: (0.45 + 0.5 * f).clamp(0.0, 1.0)),
    );
    // A brighter ring sheen.
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, reach * 0.018)
        ..color = _blend(color, _white, 0.5)
            .withValues(alpha: (0.3 + 0.5 * f).clamp(0.0, 1.0)),
    );

    // Inner "net" ring + radial strands so it reads as a catching net, with a
    // slow rotation driven by the sim clock.
    final innerR = reach * _catcherInnerFactor;
    final netPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, reach * 0.02)
      ..color = color.withValues(
          alpha: (0.28 + 0.35 * (f + a * 0.5)).clamp(0.0, 1.0));
    canvas.drawCircle(center, innerR, netPaint);
    final spin = t * 0.6;
    for (var i = 0; i < _catcherNetSpokes; i++) {
      final ang = spin + (i / _catcherNetSpokes) * math.pi * 2;
      final dir = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(
        center + dir * (reach * _catcherHubFactor),
        center + dir * innerR,
        netPaint,
      );
    }

    // Solid glowing hub + numbered pip.
    final hubR = reach * _catcherHubFactor;
    canvas.drawCircle(
      center,
      hubR,
      Paint()
        ..shader = Gradient.radial(
          center.translate(-hubR * 0.3, -hubR * 0.3),
          hubR,
          [_blend(color, _white, 0.4 + 0.4 * f), color],
        ),
    );
    canvas.drawCircle(
      center,
      hubR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, hubR * 0.16)
        ..color = _white.withValues(alpha: 0.85),
    );
    _drawText(canvas, '$displayNumber', center, hubR * 1.3, _readableText(color),
        weight: FontWeight.w900);
  }

  /// The wandering target star. [center] is its pixel position, [r] its outer
  /// radius. [pulse] in 0..1 breathes the glow/size; [golden] swaps to the
  /// bonus palette; [rot] rotates the star a touch for life; [spawn] in 0..1 is
  /// a brief pop-in scale right after a respawn/teleport (1 = just appeared).
  static void drawStar(
    Canvas canvas,
    Offset center,
    double r, {
    double pulse = 0,
    bool golden = false,
    double rot = 0,
    double spawn = 0,
  }) {
    if (r <= 0) return;
    final p = pulse.clamp(0.0, 1.0);
    final sp = spawn.clamp(0.0, 1.0);
    // Pop-in: start small after a teleport then settle; gentle pulse on top.
    final scale = (1.0 - 0.25 * sp) + 0.08 * p;
    final rr = r * scale;
    final body = golden ? _bonusGold : _starGold;
    final glow = golden ? _bonusGlow : _starGlow;

    // Soft halo (breathes with the pulse; golden blooms larger).
    final haloR = rr * _starHaloFactor * (golden ? 1.2 : 1.0) * (0.9 + 0.2 * p);
    canvas.drawCircle(
      center,
      haloR,
      Paint()
        ..shader = Gradient.radial(
          center,
          haloR,
          [
            glow.withValues(alpha: (golden ? 0.55 : 0.42) * (0.7 + 0.3 * p)),
            const Color(0x00000000),
          ],
        ),
    );

    // Golden bonus gets a sparkle crown of long thin rays.
    if (golden) {
      final ray = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, rr * 0.08)
        ..color = _blend(glow, _white, 0.4).withValues(alpha: 0.5 + 0.3 * p);
      for (var i = 0; i < _goldenRays; i++) {
        final ang = rot * 0.5 + i * (math.pi * 2 / _goldenRays);
        final dir = Offset(math.cos(ang), math.sin(ang));
        canvas.drawLine(center + dir * rr * 1.2,
            center + dir * rr * (2.0 + 0.4 * p), ray);
      }
    }

    // The 5-point star body (filled) with a gradient, plus a crisp outline.
    final path = _starPath(center, rr, rr * _starInnerFactor, _starPoints, rot);
    canvas.drawPath(
      path,
      Paint()
        ..shader = Gradient.radial(
          center,
          rr,
          [_starGoldHot, body],
          const [0.0, 1.0],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, rr * 0.08)
        ..color = _blend(glow, _white, 0.3).withValues(alpha: 0.8),
    );
    // White-hot core.
    canvas.drawCircle(center, rr * _starCoreFactor,
        Paint()..color = _white.withValues(alpha: 0.9));
  }

  /// A fading comet trail behind the star: [points] are recent pixel positions
  /// newest→oldest. Drawn as a tapering, brightening ribbon toward the head with
  /// a soft glow underlay, plus a sprinkle of deterministic sparkles.
  static void drawCometTrail(
    Canvas canvas,
    List<Offset> points,
    double headRadius,
    Color glow, {
    double pulse = 0,
  }) {
    if (points.length < 2 || headRadius <= 0) return;
    final n = points.length;
    final p = pulse.clamp(0.0, 1.0);

    // Glow underlay: a wide, faint solid stroke per segment widening toward the
    // head. A translucent over-wide stroke reads like a soft halo at a fraction
    // of the cost of a per-segment blur (no MaskFilter in this per-frame loop).
    final glowPaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n - 1; i++) {
      final frac = 1.0 - i / (n - 1); // 1 at head, 0 at tail
      glowPaint
        ..strokeWidth = headRadius * _trailWidthFactor * frac * 2.4 + 1.0
        ..color = glow.withValues(alpha: (0.20 * frac * frac).clamp(0.0, 1.0));
      canvas.drawLine(points[i], points[i + 1], glowPaint);
    }

    // Bright core ribbon on top.
    final corePaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n - 1; i++) {
      final frac = 1.0 - i / (n - 1);
      corePaint
        ..strokeWidth = headRadius * _trailWidthFactor * frac + 0.4
        ..color = _blend(glow, _white, 0.55)
            .withValues(alpha: (0.6 * frac).clamp(0.0, 1.0));
      canvas.drawLine(points[i], points[i + 1], corePaint);
    }

    // Deterministic sparkles peppered along the trail (phase from index).
    final sparkPaint = Paint();
    for (var k = 0; k < n - 1; k++) {
      final frac = 1.0 - k / (n - 1);
      final a = points[k];
      final b = points[k + 1];
      final m = Offset.lerp(a, b, ((k * 53) % 100) / 100.0) ?? a;
      final tw = 0.5 + 0.5 * math.sin((k * 1.7) + p * 6.0);
      sparkPaint.color =
          _white.withValues(alpha: (0.45 * frac * tw).clamp(0.0, 1.0));
      canvas.drawCircle(m, (headRadius * 0.16) * (0.6 + 0.6 * tw), sparkPaint);
    }
  }

  /// An expanding snatch shockwave ring at [center] in [color]. [progress] in
  /// 0..1 grows the radius to [maxRadius] and fades the stroke.
  static void drawShockwave(
    Canvas canvas,
    Offset center,
    double maxRadius,
    Color color,
    double progress,
  ) {
    final t = progress.clamp(0.0, 1.0);
    if (t >= 1 || maxRadius <= 0) return;
    final r = maxRadius * _easeOut(t);
    final alpha = (1.0 - t) * 0.8;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, maxRadius * 0.06 * (1.0 - t))
        ..color =
            _blend(color, _white, 0.4).withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
    // A fainter trailing ring for depth.
    canvas.drawCircle(
      center,
      r * 0.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, maxRadius * 0.03 * (1.0 - t))
        ..color = color.withValues(alpha: (alpha * 0.6).clamp(0.0, 1.0)),
    );
  }

  /// A thin guiding line from the in-range catcher's hub toward the star so a
  /// near-catch reads clearly. [strength] 0..1 fades it.
  static void drawSnatchHint(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color,
    double strength,
  ) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    // Two stacked solid strokes (wide+faint under thin+crisp) read like a soft
    // guide line without a per-frame blur.
    canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4.0 + 3.0 * s
        ..color = color.withValues(alpha: 0.16 * s),
    );
    canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.5 + 1.5 * s
        ..color = color.withValues(alpha: 0.4 * s),
    );
  }

  /// Round clock + "BEST" leader readout at the top center. [secondsLeft] is the
  /// remaining time; [leaderColor]/[leaderScore] highlight the current leader.
  static void drawHud(
    Canvas canvas,
    Size size,
    double secondsLeft,
    Color? leaderColor,
    int leaderScore,
  ) {
    final t = math.max(0.0, secondsLeft);
    final urgent = t <= 5;
    final clockColor = urgent ? _urgent : _white;
    _drawText(
      canvas,
      t.ceil().toString(),
      Offset(size.width / 2, size.height * 0.055),
      size.width * 0.06,
      clockColor.withValues(alpha: 0.92),
      weight: FontWeight.w900,
      glow: true,
      glowColor: urgent ? _urgent : _starGlow,
    );
    if (leaderColor != null && leaderScore > 0) {
      _drawText(
        canvas,
        'BEST $leaderScore',
        Offset(size.width / 2, size.height * 0.105),
        size.width * 0.03,
        leaderColor,
        weight: FontWeight.w800,
      );
    }
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  /// Build a [points]-point star path with the given outer/inner radii, rotated
  /// by [rot] radians.
  static Path _starPath(
      Offset c, double outer, double inner, int points, double rot) {
    final path = Path();
    final step = math.pi / points;
    for (var i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outer : inner;
      final a = -math.pi / 2 + rot + i * step;
      final p = Offset(c.dx + math.cos(a) * radius, c.dy + math.sin(a) * radius);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  /// Cubic ease-out (kept local so the renderer has no Flutter import).
  static double _easeOut(double t) {
    final u = 1.0 - t.clamp(0.0, 1.0);
    return 1.0 - u * u * u;
  }

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }

  /// Centered text with an optional cheap glow halo (offset copies). Never
  /// throws; degenerate sizes are ignored.
  static void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w800,
    bool glow = false,
    Color? glowColor,
  }) {
    if (fontSize <= 0 || text.isEmpty) return;
    final width = fontSize * (text.length + 2);
    if (glow) {
      final gb = ParagraphBuilder(ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: fontSize,
        fontWeight: weight,
      ))
        ..pushStyle(
            TextStyle(color: (glowColor ?? color).withValues(alpha: 0.5)))
        ..addText(text);
      final gp = gb.build()..layout(ParagraphConstraints(width: width));
      for (final o in const [
        Offset(0, 2.5),
        Offset(2.5, 0),
        Offset(-2.5, 0),
        Offset(0, -2.5),
      ]) {
        canvas.drawParagraph(gp,
            Offset(center.dx - width / 2 + o.dx, center.dy - fontSize + o.dy));
      }
    }
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: weight,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: width));
    canvas.drawParagraph(
        paragraph, Offset(center.dx - width / 2, center.dy - fontSize));
  }
}
