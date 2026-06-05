import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Pure-Canvas rendering for [TugOfWar]. Holds NO game state and never mutates
/// the simulation — callers pass plain value snapshots. Kept in its own file so
/// the gameplay module stays lean and the drawing stays cohesive (mirrors the
/// sumo_smash split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class TugRenderer {
  TugRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _bgTop = Color(0xFF1A1322);
  static const Color _bgMid = Color(0xFF120C1A);
  static const Color _bgBottom = Color(0xFF070409);
  static const Color _vignette = Color(0x99000000);
  static const Color _spotlight = Color(0x18FFE6B0);
  static const Color _groundTop = Color(0xFF3A2A1C);
  static const Color _groundBottom = Color(0xFF1C140E);
  static const Color _groundLine = Color(0x33FFFFFF);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  // Pit (mud/lava) palette.
  static const Color _pitOuter = Color(0xFF120A06);
  static const Color _pitMud0 = Color(0xFF6E2E0E);
  static const Color _pitMud1 = Color(0xFFB8500F);
  static const Color _pitLava = Color(0xFFFFC23A);
  static const Color _pitRim = Color(0xFFFF7A1A);
  static const Color _pitRimGlow = Color(0xFFFFB54D);

  // Rope palette.
  static const Color _ropeCore = Color(0xFFE8C98C);
  static const Color _ropeDark = Color(0xFF9C6F3A);
  static const Color _ropeShade = Color(0xFF5E3F1F);

  // ── Tuning (fractions of arena/ground; no inline magic numbers) ────────────
  static const double _spotlightFactor = 0.9; // spotlight radius / width
  static const double _vignetteInnerFrac = 0.5; // clear-zone radius / diag
  static const double _vignetteOuterFrac = 0.72; // vignette radius / diag
  static const double _crowdBandFrac = 0.16; // dark crowd band height / height
  static const double _groundTopFrac = 0.5; // ground starts here (frac height)
  static const int _groundLineCount = 5;
  static const double _centerDashLen = 14;
  static const double _centerDashGap = 12;
  static const double _goalLineHalfFrac = 0.07; // goal line half-height / height

  // Pit rim stroke width relative to pit x-radius.
  static const double _pitRimWidthFrac = 0.024;

  // Rope layer widths (px).
  static const double _ropeShadowW = 14;
  static const double _ropeUnderW = 12;
  static const double _ropeBodyW = 9;
  static const double _ropeBraidW = 4;
  static const double _ropeGripW = 11;

  // ── Background: gradient sky + crowd-dark band + soft stage spotlight ───────
  static void drawBackground(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgMid, _bgBottom],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // Soft warm stage spotlight centered above the pit.
    final spotR = size.width * _spotlightFactor;
    if (spotR > 0) {
      final spotCenter = Offset(size.width / 2, size.height * _groundTopFrac);
      final spot = Paint()
        ..shader = Gradient.radial(
          spotCenter,
          spotR,
          const [_spotlight, Color(0x00000000)],
        );
      canvas.drawCircle(spotCenter, spotR, spot);
    }

    // Dark "crowd" band along the horizon for depth.
    final bandH = size.height * _crowdBandFrac;
    final bandTop = size.height * _groundTopFrac - bandH;
    final crowd = Paint()
      ..shader = Gradient.linear(
        Offset(0, bandTop),
        Offset(0, bandTop + bandH),
        const [Color(0x00000000), Color(0x88000000)],
      );
    canvas.drawRect(Rect.fromLTWH(0, bandTop, size.width, bandH), crowd);
  }

  /// Ground slab below the play line: warm gradient + a few perspective lines.
  static void drawGround(Canvas canvas, Size size, double groundY) {
    final top = math.min(groundY, size.height);
    final rect =
        Rect.fromLTWH(0, top, size.width, math.max(0, size.height - top));
    final ground = Paint()
      ..shader = Gradient.linear(
        Offset(0, top),
        Offset(0, size.height),
        const [_groundTop, _groundBottom],
      );
    canvas.drawRect(rect, ground);

    // Receding floor lines (subtle perspective).
    final line = Paint()
      ..color = _groundLine
      ..strokeWidth = 1.5;
    final span = size.height - top;
    for (var i = 1; i <= _groundLineCount; i++) {
      final f = i / (_groundLineCount + 1);
      final y = top + span * f * f; // ease so lines bunch toward horizon
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// Crowd-dark vignette so the action pops (drawn over the field, under the
  /// popups). [pulse] in 0..1 reddens/tightens the frame as the marker nears an
  /// edge — selling the rising tension.
  static void drawVignette(Canvas canvas, Size size, double pulse) {
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final outer = diag * _vignetteOuterFrac;
    final inner = diag * _vignetteInnerFrac;
    final p = pulse.clamp(0.0, 1.0);
    final edge = Color.lerp(_vignette, const Color(0xFF260202), p) ?? _vignette;
    final paint = Paint()
      ..shader = Gradient.radial(
        Offset(size.width / 2, size.height * 0.46),
        outer,
        [const Color(0x00000000), edge],
        [(inner / outer).clamp(0.0, 0.99), 1.0],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  /// The central mud/lava pit: dark socket → radial mud→lava core → bubbling
  /// hot spots → glowing rim. [t] is an animation clock (seconds) for shimmer.
  static void drawPit(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double t,
  ) {
    if (rx <= 1 || ry <= 1) return;

    // Recessed socket shadow under/around the pit.
    final socket = Paint()
      ..color = _pitOuter
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, ry * 0.5);
    canvas.drawOval(
      Rect.fromCenter(
          center: center.translate(0, ry * 0.12),
          width: rx * 2.2,
          height: ry * 2.2),
      socket,
    );

    // Mud → lava radial body (slightly offset highlight for volume).
    final body = Paint()
      ..shader = Gradient.radial(
        center.translate(-rx * 0.12, -ry * 0.18),
        rx * 1.15,
        const [_pitLava, _pitMud1, _pitMud0, _pitOuter],
        const [0.0, 0.4, 0.75, 1.0],
      );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      body,
    );

    // Bubbling hot spots — a few drifting glowing blobs (deterministic from t).
    final blob =
        Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, ry * 0.16);
    for (var i = 0; i < 5; i++) {
      final phase = t * (0.7 + i * 0.13) + i * 1.7;
      final bx = math.sin(phase) * rx * 0.5;
      final by = math.cos(phase * 0.9 + i) * ry * 0.45;
      final pulse = 0.5 + 0.5 * math.sin(phase * 1.6);
      final r = ry * (0.18 + 0.12 * pulse);
      blob.color = Color.lerp(_pitMud1, _pitLava, pulse)!
          .withValues(alpha: 0.55 * pulse + 0.2);
      canvas.drawCircle(center.translate(bx, by), r, blob);
    }

    // Inner heat highlight.
    final heat = Paint()
      ..shader = Gradient.radial(
        center.translate(-rx * 0.1, -ry * 0.2),
        rx * 0.55,
        [
          _pitLava.withValues(alpha: 0.5),
          const Color(0x00000000),
        ],
      );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 1.1, height: ry * 1.1),
      heat,
    );

    // Glowing rim: soft outer halo + crisp hot core line.
    final rimW = math.max(2.0, rx * _pitRimWidthFrac);
    final rimRect =
        Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    final glowPulse = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(t * 3.0));
    canvas.drawOval(
      rimRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW * 2.4
        ..color = _pitRimGlow.withValues(alpha: 0.32 * glowPulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rimW * 1.6),
    );
    canvas.drawOval(
      rimRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW
        ..color = _pitRim.withValues(alpha: 0.9),
    );
  }

  /// Dashed center line + two side goal lines (the win thresholds). [centerX] is
  /// the pit center; [leftGoalX]/[rightGoalX] are the goal verticals.
  static void drawFieldLines(
    Canvas canvas,
    Size size,
    double midY,
    double centerX,
    double leftGoalX,
    double rightGoalX,
  ) {
    final goalHalf = size.height * _goalLineHalfFrac;

    // Dashed vertical center line.
    final dash = Paint()
      ..color = _groundLine
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    var y = midY - goalHalf * 1.4;
    final yEnd = midY + goalHalf * 1.4;
    while (y < yEnd) {
      canvas.drawLine(Offset(centerX, y),
          Offset(centerX, math.min(y + _centerDashLen, yEnd)), dash);
      y += _centerDashLen + _centerDashGap;
    }

    // Side goal lines with small chevrons so they read as "the line".
    _goalLine(canvas, leftGoalX, midY, goalHalf, -1);
    _goalLine(canvas, rightGoalX, midY, goalHalf, 1);
  }

  static void _goalLine(
      Canvas canvas, double x, double midY, double half, double dir) {
    final paint = Paint()
      ..color = _white.withValues(alpha: 0.5)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, midY - half), Offset(x, midY + half), paint);
    // Chevron flags pointing inward.
    final flag = Paint()
      ..color = _white.withValues(alpha: 0.28)
      ..strokeWidth = 2;
    canvas.drawLine(
        Offset(x, midY - half), Offset(x + dir * 12, midY - half + 8), flag);
    canvas.drawLine(
        Offset(x, midY + half), Offset(x + dir * 12, midY + half - 8), flag);
  }

  /// The rope as a catenary curve sagging in the middle, drawn from [leftHand]
  /// to [rightHand] through the [knot] apex, with a braided sheen. [sag] is the
  /// extra droop depth (px). Tinted grip wraps mark each team's grip.
  static void drawRope(
    Canvas canvas,
    Offset leftHand,
    Offset rightHand,
    Offset knot,
    double sag,
    Color leftTint,
    Color rightTint,
  ) {
    final span = rightHand.dx - leftHand.dx;
    if (span.abs() < 1) return;

    // Two control legs so the apex of the sag sits at the knot.
    final leftCtrl = Offset(
        leftHand.dx + (knot.dx - leftHand.dx) * 0.5, knot.dy + sag * 0.6);
    final rightCtrl = Offset(
        knot.dx + (rightHand.dx - knot.dx) * 0.5, knot.dy + sag * 0.6);

    final path = Path()
      ..moveTo(leftHand.dx, leftHand.dy)
      ..quadraticBezierTo(leftCtrl.dx, leftCtrl.dy, knot.dx, knot.dy)
      ..quadraticBezierTo(
          rightCtrl.dx, rightCtrl.dy, rightHand.dx, rightHand.dy);

    // Soft drop shadow of the rope on the ground.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeShadowW
        ..strokeCap = StrokeCap.round
        ..color = _black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Dark underside → body → bright braid (stacked for a round 3-D rope).
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeUnderW
        ..strokeCap = StrokeCap.round
        ..color = _ropeShade,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeBodyW
        ..strokeCap = StrokeCap.round
        ..color = _ropeDark,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeBraidW
        ..strokeCap = StrokeCap.round
        ..color = _ropeCore,
    );

    // Tinted grip wraps near each team's hands.
    _gripWrap(canvas, leftHand, leftCtrl, leftTint);
    _gripWrap(canvas, rightHand, rightCtrl, rightTint);
  }

  static void _gripWrap(Canvas canvas, Offset hand, Offset ctrl, Color tint) {
    final dir = ctrl - hand;
    final len = dir.distance;
    if (len < 1) return;
    final n = dir / len;
    final end = hand + n * (len * 0.32);
    canvas.drawLine(
      hand,
      end,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeGripW
        ..strokeCap = StrokeCap.round
        ..color = tint.withValues(alpha: 0.85),
    );
  }

  /// The center marker: a fabric pennant hanging off the rope knot, tinted
  /// toward whichever side is currently winning ([lead] in -1..1, -1 = left).
  static void drawMarkerFlag(
    Canvas canvas,
    Offset knot,
    double lead,
    Color leftTint,
    Color rightTint,
    double t,
  ) {
    final l = lead.clamp(-1.0, 1.0);
    final tint = l <= 0
        ? Color.lerp(_white, leftTint, (-l).clamp(0.0, 1.0))!
        : Color.lerp(_white, rightTint, l.clamp(0.0, 1.0))!;

    // Pole binding knot on the rope.
    canvas.drawCircle(knot, 9, Paint()..color = _ropeDark);
    canvas.drawCircle(
        knot,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _ropeCore);

    // Triangular pennant flapping below the knot (wave from t + lead bias).
    final wave = math.sin(t * 6.0) * 6 + l * 14;
    final tip = knot + Offset(wave, 34);
    final flag = Path()
      ..moveTo(knot.dx - 3, knot.dy + 4)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(knot.dx + 3, knot.dy + 4)
      ..close();
    canvas.drawPath(flag, Paint()..color = tint);
    canvas.drawPath(
      flag,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _black.withValues(alpha: 0.3),
    );
    // Bright eye on the knot.
    canvas.drawCircle(knot, 3.2, Paint()..color = _white);
  }

  /// Dug-in feet dust puff for a straining puller. [strain] 0..1 scales it.
  static void drawFootDust(
      Canvas canvas, Offset feet, double bodyW, double strain, double t,
      {required double dir}) {
    final s = strain.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    final paint =
        Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, bodyW * 0.4);
    for (var i = 0; i < 3; i++) {
      final phase = t * 3.0 + i * 2.1;
      final puff = 0.5 + 0.5 * math.sin(phase);
      final px = dir * bodyW * (0.5 + i * 0.5);
      final py = -bodyW * 0.1 * puff;
      paint.color = _groundTop.withValues(alpha: (0.18 + 0.22 * puff) * s);
      canvas.drawCircle(feet.translate(px, py),
          bodyW * (0.3 + 0.25 * puff) * (0.6 + s), paint);
    }
  }

  /// Soft contact shadow ellipse beneath a puller at ground level.
  static void drawContactShadow(Canvas canvas, Offset groundCenter, double w) {
    final paint = Paint()
      ..color = _black.withValues(alpha: 0.3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.22);
    canvas.drawOval(
      Rect.fromCenter(center: groundCenter, width: w * 2.4, height: w * 0.7),
      paint,
    );
  }

  /// A side effort bar showing how hard a team is pulling. [effort] 0..1 fills
  /// it from the team's outer edge inward; [heave] 0..1 brightens + adds a surge
  /// glow tip when the rhythm bonus is hot. [dir] -1 = left team, +1 = right.
  static void drawEffortBar(
    Canvas canvas,
    Offset anchor,
    double width,
    double effort,
    double heave,
    Color color, {
    required double dir,
  }) {
    final e = effort.clamp(0.0, 1.0);
    const h = 8.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromCenter(center: anchor, width: width, height: h),
      const Radius.circular(h / 2),
    );
    canvas.drawRRect(track, Paint()..color = _black.withValues(alpha: 0.35));

    final fillW = width * e;
    if (fillW > 1) {
      final left =
          dir < 0 ? anchor.dx + width / 2 - fillW : anchor.dx - width / 2;
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, anchor.dy - h / 2, fillW, h),
        const Radius.circular(h / 2),
      );
      final hot = Color.lerp(color, _white, 0.3 * heave.clamp(0.0, 1.0))!;
      canvas.drawRRect(fillRect, Paint()..color = hot);
    }

    // Heave surge glow tip at the leading edge of the fill.
    if (heave > 0.05) {
      final tipX = dir < 0
          ? anchor.dx + width / 2 - fillW
          : anchor.dx - width / 2 + fillW;
      canvas.drawCircle(
        Offset(tipX, anchor.dy),
        h * (0.8 + heave),
        Paint()
          ..color = _white.withValues(alpha: 0.5 * heave.clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.6),
      );
    }
  }

  /// Expanding ring shockwave near a team when their HEAVE surge fires.
  static void drawHeaveCue(
      Canvas canvas, Offset at, double strength, Color color) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    canvas.drawCircle(
      at,
      18 + 34 * (1 - s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s + 1
        ..color = Color.lerp(color, _white, 0.4)!.withValues(alpha: 0.6 * s),
    );
  }

  /// Render the stick puller itself. Kept here so the painter call lives with
  /// the rest of the visuals; [figure] owns its own pose/ragdoll state.
  static void drawPuller(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }
}
