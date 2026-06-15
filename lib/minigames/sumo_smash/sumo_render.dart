import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Pure-Canvas rendering for [SumoSmash]. Holds NO game state and never mutates
/// the simulation — callers pass plain value snapshots. Kept in its own file so
/// the gameplay module stays lean and the drawing stays cohesive.
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class SumoRenderer {
  SumoRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _bgTop = Color(0xFF131A2B);
  static const Color _bgBottom = Color(0xFF070A12);
  static const Color _spotlight = Color(0x2A6FA8FF);
  static const Color _claySand = Color(0xFFE7C58C);
  static const Color _clayCore = Color(0xFFD7A85F);
  static const Color _clayEdge = Color(0xFFB07C3C);
  static const Color _ringShadow = Color(0x66000000);
  static const Color _innerLine = Color(0x226B4A24);
  static const Color _dangerBand = Color(0xFFFF4B3E);
  static const Color _rimGlow = Color(0xFFFFE08A);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  // ── Tuning ─────────────────────────────────────────────────────────────────
  static const double _spotlightFactor = 1.55; // spotlight radius / ring radius
  static const double _rimWidthFactor = 0.038; // rim stroke / ring radius
  static const int _innerRings = 4;
  static const double _dangerBandFactor = 0.10; // band depth / ring radius
  static const double _shadowDrop = 0.06; // ring drop-shadow offset / radius
  static const double _contactShadowW = 2.6; // contact ellipse width / bodyR
  static const double _contactShadowH = 0.7; // contact ellipse height / bodyR
  static const double _beltWidthFactor = 0.42; // mawashi width / bodyR
  static const double _cooldownArcR = 1.35; // cooldown arc radius / bodyR
  static const double _crownR = 0.34; // id pip radius / bodyR

  // ── Background: arena gradient + soft spotlight on the dohyo ────────────────
  static void drawBackground(Canvas canvas, Size size, Offset center,
      double ringRadius) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgBottom],
      );
    canvas.drawRect(Offset.zero & size, bg);

    final spotR = ringRadius * _spotlightFactor;
    if (spotR > 0) {
      final spot = Paint()
        ..shader = Gradient.radial(
          center,
          spotR,
          const [_spotlight, Color(0x00000000)],
        );
      canvas.drawCircle(center, spotR, spot);
    }
  }

  /// Sparse ambient dust motes for depth (positions supplied by caller so they
  /// stay deterministic and animate with the sim clock).
  static void drawAmbientDust(Canvas canvas, List<Offset> motes, double t) {
    if (motes.isEmpty) return;
    final paint = Paint();
    for (var i = 0; i < motes.length; i++) {
      final m = motes[i];
      final twinkle = 0.18 + 0.16 * (0.5 + 0.5 * math.sin(t * 1.7 + i));
      paint.color = _white.withValues(alpha: twinkle.clamp(0.0, 1.0));
      canvas.drawCircle(m, 1.4 + (i % 3) * 0.5, paint);
    }
  }

  /// The dohyo: drop shadow → clay radial gradient → inner texture rings →
  /// glowing danger band → thick glowing accent rim. [accent] is the theme rim
  /// color; [dangerPulse] in 0..1 brightens the danger band.
  static void drawDohyo(
    Canvas canvas,
    Offset center,
    double ringRadius, {
    required Color accent,
    required double dangerPulse,
  }) {
    if (ringRadius <= 1) return;

    // Soft drop shadow under the platform.
    final shadow = Paint()
      ..color = _ringShadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(
        center + Offset(0, ringRadius * _shadowDrop), ringRadius * 1.02, shadow);

    // Clay / sand radial gradient body.
    final clay = Paint()
      ..shader = Gradient.radial(
        center.translate(-ringRadius * 0.18, -ringRadius * 0.22),
        ringRadius * 1.15,
        const [_claySand, _clayCore, _clayEdge],
        const [0.0, 0.62, 1.0],
      );
    canvas.drawCircle(center, ringRadius, clay);

    // Faint concentric "raked sand" texture.
    final tex = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, ringRadius * 0.006)
      ..color = _innerLine;
    for (var i = 1; i <= _innerRings; i++) {
      final r = ringRadius * (i / (_innerRings + 1));
      canvas.drawCircle(center, r, tex);
    }

    // Glowing red danger band just inside the rim: a soft halo + a crisp red
    // core line so it reads clearly as "the edge will kill you".
    final bandDepth = ringRadius * _dangerBandFactor;
    final bandR = ringRadius - bandDepth * 0.75;
    final bandAlpha = (0.30 + 0.45 * dangerPulse.clamp(0.0, 1.0));
    final bandHalo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bandDepth * 1.1
      ..color = _dangerBand.withValues(alpha: (bandAlpha * 0.5).clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, bandDepth * 0.6);
    canvas.drawCircle(center, bandR, bandHalo);
    final bandCore = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, bandDepth * 0.42)
      ..color = _dangerBand.withValues(alpha: bandAlpha.clamp(0.0, 1.0));
    canvas.drawCircle(center, bandR, bandCore);

    // Thick glowing accent rim (controlled outer glow + crisp core).
    final rimW = math.max(3.0, ringRadius * _rimWidthFactor);
    final rimGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimW * 1.3
      ..color = accent.withValues(alpha: 0.4)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, rimW * 0.7);
    canvas.drawCircle(center, ringRadius, rimGlow);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimW
      ..shader = Gradient.linear(
        center.translate(0, -ringRadius),
        center.translate(0, ringRadius),
        [_blend(accent, _rimGlow, 0.55), accent],
      );
    canvas.drawCircle(center, ringRadius, rim);

    // Inner highlight lip for a thick 3-D edge.
    final lip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, rimW * 0.35)
      ..color = _white.withValues(alpha: 0.18);
    canvas.drawCircle(center, ringRadius - rimW * 0.55, lip);
  }

  /// Soft contact shadow ellipse beneath a wrestler at ground level.
  static void drawContactShadow(
      Canvas canvas, Offset groundCenter, double bodyR) {
    final paint = Paint()
      ..color = _black.withValues(alpha: 0.32)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, bodyR * 0.25);
    canvas.drawOval(
      Rect.fromCenter(
        center: groundCenter,
        width: bodyR * _contactShadowW,
        height: bodyR * _contactShadowH,
      ),
      paint,
    );
  }

  /// A colored ground ring + small numbered pip identifying a player.
  static void drawIdMarker(
    Canvas canvas,
    Offset groundCenter,
    double bodyR,
    Color color,
    int displayNumber,
  ) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, bodyR * 0.12)
      ..color = color.withValues(alpha: 0.9);
    canvas.drawOval(
      Rect.fromCenter(
        center: groundCenter,
        width: bodyR * (_contactShadowW + 0.4),
        height: bodyR * (_contactShadowH + 0.25),
      ),
      ring,
    );

    // Number pip sits at the front of the ground ring.
    final pipCenter = groundCenter.translate(0, bodyR * 0.05);
    final pip = Paint()..color = color;
    final r = bodyR * _crownR;
    canvas.drawCircle(pipCenter, r, pip);
    canvas.drawCircle(
      pipCenter,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.18)
        ..color = _white.withValues(alpha: 0.85),
    );
    _drawNumber(canvas, pipCenter, '$displayNumber', r * 1.25,
        _readableText(color));
  }

  /// The mawashi belt: a thick colored band across the pelvis with a knot.
  static void drawBelt(
    Canvas canvas,
    Offset pelvis,
    double bodyR,
    double facing,
    Color color,
  ) {
    final w = bodyR * 1.05;
    final h = bodyR * _beltWidthFactor;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pelvis, width: w, height: h),
      Radius.circular(h * 0.5),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, h * 0.18)
        ..color = _blend(color, _black, 0.35),
    );
    // Highlight line for a sheen.
    canvas.drawLine(
      Offset(pelvis.dx - w * 0.4, pelvis.dy - h * 0.22),
      Offset(pelvis.dx + w * 0.4, pelvis.dy - h * 0.22),
      Paint()
        ..strokeWidth = math.max(0.8, h * 0.12)
        ..strokeCap = StrokeCap.round
        ..color = _white.withValues(alpha: 0.45),
    );
    // Front knot.
    final knot = pelvis.translate(facing * w * 0.42, h * 0.1);
    canvas.drawCircle(knot, h * 0.55, Paint()..color = _blend(color, _white, 0.2));
  }

  /// Cooldown / charge arc drawn under a wrestler. [fill] in 0..1 sweeps the
  /// arc; [ready] swaps to a bright full ring with a momentum tint.
  static void drawCooldownArc(
    Canvas canvas,
    Offset groundCenter,
    double bodyR,
    double fill,
    bool ready,
    Color color,
    double momentum,
  ) {
    final r = bodyR * _cooldownArcR;
    final rect = Rect.fromCenter(
        center: groundCenter, width: r * 2, height: r * _contactShadowH * 2);
    // Track.
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, bodyR * 0.1)
        ..color = _black.withValues(alpha: 0.25),
    );
    final sweepCol = ready
        ? _blend(color, _white, 0.35 + 0.4 * momentum.clamp(0.0, 1.0))
        : color.withValues(alpha: 0.85);
    final sweep = ready ? math.pi * 2 : (math.pi * 2 * fill.clamp(0.0, 1.0));
    if (sweep <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.6, bodyR * 0.14)
        ..color = sweepCol,
    );
  }

  /// A short directional motion trail behind a dashing wrestler.
  static void drawDashTrail(
    Canvas canvas,
    Offset from,
    Offset to,
    double bodyR,
    Color color,
    double strength,
  ) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.01) return;
    canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = bodyR * (0.6 + 0.8 * s)
        ..color = color.withValues(alpha: 0.28 * s)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, bodyR * 0.3),
    );
  }

  /// Render the stick wrestler itself. Kept here so the painter call lives with
  /// the rest of the visuals; [figure] owns its own pose/ragdoll state.
  static void drawWrestler(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }

  /// The charge telegraph: while charging, a solid layered arrow points where
  /// the shove will fire and a ground arc shows the charge [charge] (0..1). No
  /// blur — cheap to draw every frame. A no-op when not charging.
  static void drawAim(
    Canvas canvas,
    Offset center,
    double bodyR,
    Color color, {
    required double aim,
    required double charge,
  }) {
    final c = charge.clamp(0.0, 1.0);
    final dir = Offset(math.cos(aim), math.sin(aim));
    final base = bodyR * 0.95;
    // A faint short stub at rest (the idle "you'll shove THIS way" preview) that
    // grows long + bright as the charge fills — so the player always sees their
    // aim and never fires in a surprise direction.
    final len = bodyR * (1.2 + 2.4 * c);
    final alpha = 0.4 + 0.55 * c;
    final start = center + dir * base;
    final end = center + dir * (base + len);
    final w = bodyR * (0.2 + 0.28 * c);

    canvas.drawLine(
        start,
        end,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(
        start,
        end,
        Paint()
          ..color = _white.withValues(alpha: 0.55 * alpha)
          ..strokeWidth = w * 0.4
          ..strokeCap = StrokeCap.round);

    final perp = Offset(-dir.dy, dir.dx);
    final head = bodyR * (0.5 + 0.34 * c);
    final tip = end + dir * head;
    final l = end + perp * head * 0.66;
    final r = end - perp * head * 0.66;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(l.dx, l.dy)
        ..lineTo(r.dx, r.dy)
        ..close(),
      Paint()..color = color.withValues(alpha: alpha),
    );

    // The radial charge ring only once a hold is building (skipped at rest).
    if (c > 0.01) {
      final groundCenter = center.translate(0, bodyR);
      canvas.drawArc(
        Rect.fromCircle(center: groundCenter, radius: bodyR * 1.25),
        -math.pi / 2,
        math.pi * 2 * c,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bodyR * 0.18
          ..strokeCap = StrokeCap.round
          ..color = (_blend(color, _white, c)).withValues(alpha: 0.9),
      );
    }
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  /// Pick black or white text for legibility against [bg].
  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }

  static void _drawNumber(
      Canvas canvas, Offset center, String text, double fontSize, Color color) {
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: fontSize * 3));
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - fontSize * 1.5, center.dy - fontSize * 0.62),
    );
  }
}
