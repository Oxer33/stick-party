import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Geometry of one high-striker tower in render space. Pure value — the sim
/// builds it and both the sim and [MasherRenderer] read its anchors so they
/// agree on where the puck, lever plate and bell sit.
class TowerSpec {
  final double center; // x of the tower center
  final double width; // base width (drives every other size)
  final double railTop; // y of the top of the climb rail (under the bell)
  final double railBottom; // y of the lever plate (puck at height 0)

  const TowerSpec({
    required this.center,
    required this.width,
    required this.railTop,
    required this.railBottom,
  });

  double get railSpan => railBottom - railTop;

  /// World position of the puck for a 0..1 height (0 = plate, 1 = top).
  Offset puckAt(double frac) =>
      Offset(center, railBottom - railSpan * frac.clamp(0.0, 1.0));

  Offset get leverPlate => Offset(center, railBottom);
  Offset get bell => Offset(center, railTop - width * 0.7);
}

/// Pure-Canvas rendering for [ButtonMasher]'s carnival "high striker". Holds NO
/// game state and never mutates the simulation — callers pass plain value
/// snapshots. Kept in its own file so the gameplay module stays lean and the
/// drawing stays cohesive (mirrors the sumo_smash / tug_of_war split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class MasherRenderer {
  MasherRenderer._();

  // ── Shared palette (no magic colors inline elsewhere) ───────────────────────
  static const Color bellGold = Color(0xFFFFD23C);

  static const Color _bgTop = Color(0xFF2A1640);
  static const Color _bgMid = Color(0xFF1A0E2B);
  static const Color _bgBottom = Color(0xFF0A0614);
  static const Color _stageGlow = Color(0x22FFD27A);
  static const Color _ground = Color(0xFF241634);
  static const Color _groundLine = Color(0x22FFFFFF);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  // Tower hardware palette.
  static const Color _railDark = Color(0xFF120A1E);
  static const Color _railSteel = Color(0xFF6A6478);
  static const Color _railSteelHi = Color(0xFFB9B4C6);
  static const Color _plateSteel = Color(0xFFD7D2E0);
  static const Color _plateMid = Color(0xFF9A94A8);
  static const Color _plateDark = Color(0xFF4A4456);
  static const Color _bellShadow = Color(0xFF7A4E08);
  static const Color _bellHi = Color(0xFFFFF1AE);
  static const Color _woodDark = Color(0xFF6B4A2A);
  static const Color _woodLight = Color(0xFF9A6E3E);
  static const Color _steelHead = Color(0xFF4A4456);

  // Bunting / festive flag colors strung across the top.
  static const List<Color> _bunting = <Color>[
    Color(0xFFFF5A5A),
    Color(0xFF4D9BFF),
    Color(0xFF54E08A),
    Color(0xFFFFC93C),
  ];

  // ── Tuning (fractions of tower width / arena; no inline magic numbers) ──────
  static const double _railWidthFrac = 0.26; // rail width / tower width
  static const double _levelGapFrac = 0.06; // gap between lit levels / span
  static const double _puckWidthFrac = 0.92; // puck width / tower width
  static const double _puckHeightFrac = 0.42; // puck height / tower width
  static const int _trailSegments = 7; // puck trail tick count
  static const double _bellRadiusFrac = 0.62; // bell radius / tower width
  static const double _plateWidthFrac = 1.0; // lever plate width / tower width
  static const double _hammerHeadFrac = 0.62; // hammer head length / tower width
  static const int _groundLines = 4;
  static const int _buntingFlags = 14;
  static const int _hotLevels = 3; // top levels that glow gold ("ding zone")

  // ── Background: festive gradient + stage glow + bunting + ground ────────────
  static void drawBackground(Canvas canvas, Size size, double t) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgMid, _bgBottom],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // Soft warm stage glow pooling over the towers.
    final glowR = size.width * 0.85;
    if (glowR > 0) {
      final center = Offset(size.width / 2, size.height * 0.34);
      canvas.drawCircle(
        center,
        glowR,
        Paint()
          ..shader = Gradient.radial(
            center,
            glowR,
            const [_stageGlow, Color(0x00000000)],
          ),
      );
    }

    _drawSpotlightSweep(canvas, size, t);
    _drawBunting(canvas, size, t);
    _drawGround(canvas, size);
  }

  /// Two slow rotating spotlight cones for a fairground stage feel.
  static void _drawSpotlightSweep(Canvas canvas, Size size, double t) {
    final apexL = Offset(size.width * 0.16, -size.height * 0.05);
    final apexR = Offset(size.width * 0.84, -size.height * 0.05);
    _spotCone(canvas, size, apexL, math.sin(t * 0.5) * 0.35 + 0.55);
    _spotCone(
        canvas, size, apexR, math.pi - math.sin(t * 0.43 + 1) * 0.35 - 0.55);
  }

  static void _spotCone(Canvas canvas, Size size, Offset apex, double angle) {
    final len = size.height * 0.7;
    const half = 0.13;
    final p1 =
        apex + Offset(math.cos(angle - half), math.sin(angle - half)) * len;
    final p2 =
        apex + Offset(math.cos(angle + half), math.sin(angle + half)) * len;
    final path = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = Gradient.linear(
          apex,
          Offset(apex.dx, apex.dy + len),
          const [Color(0x22FFE9B0), Color(0x00000000)],
        ),
    );
  }

  /// A string of triangular pennants gently swaying across the top.
  static void _drawBunting(Canvas canvas, Size size, double t) {
    final y0 = size.height * 0.05;
    final sag = size.height * 0.035;
    final cord = Path()
      ..moveTo(0, y0)
      ..quadraticBezierTo(size.width / 2, y0 + sag, size.width, y0);
    canvas.drawPath(
      cord,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _white.withValues(alpha: 0.18),
    );

    for (var i = 0; i < _buntingFlags; i++) {
      final u = (i + 0.5) / _buntingFlags;
      final x = size.width * u;
      final y = y0 + sag * 4 * u * (1 - u); // follow the cord sag
      final flutter = math.sin(t * 2.0 + i * 0.7) * 3;
      final w = size.width / _buntingFlags * 0.6;
      final h = w * 1.4;
      final flag = Path()
        ..moveTo(x - w / 2, y)
        ..lineTo(x + w / 2, y)
        ..lineTo(x + flutter, y + h)
        ..close();
      canvas.drawPath(
        flag,
        Paint()..color = _bunting[i % _bunting.length].withValues(alpha: 0.9),
      );
    }
  }

  static void _drawGround(Canvas canvas, Size size) {
    final top = size.height * 0.84;
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, size.height - top),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, top),
          Offset(0, size.height),
          const [_ground, _bgBottom],
        ),
    );
    final line = Paint()
      ..color = _groundLine
      ..strokeWidth = 1.5;
    final span = size.height - top;
    for (var i = 1; i <= _groundLines; i++) {
      final f = i / (_groundLines + 1);
      final y = top + span * f * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  // ── Tower: post, rail, numbered light levels ────────────────────────────────
  static void drawTower(
    Canvas canvas,
    TowerSpec t, {
    required Color color,
    required int levels,
    required double litFraction,
    required int number,
    required double glowPulse,
  }) {
    if (t.railSpan <= 1 || t.width <= 1) return;
    final railW = t.width * _railWidthFrac;

    // Drop shadow of the whole post.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          t.center - railW * 0.6 + 4,
          t.railTop + 6,
          t.center + railW * 0.6 + 4,
          t.railBottom,
        ),
        Radius.circular(railW * 0.4),
      ),
      Paint()
        ..color = _black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, railW * 0.4),
    );

    // Steel rail with a vertical sheen.
    final railRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        t.center - railW * 0.5,
        t.railTop,
        t.center + railW * 0.5,
        t.railBottom,
      ),
      Radius.circular(railW * 0.4),
    );
    canvas.drawRRect(railRect, Paint()..color = _railDark);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          t.center - railW * 0.34,
          t.railTop,
          t.center + railW * 0.1,
          t.railBottom,
        ),
        Radius.circular(railW * 0.3),
      ),
      Paint()
        ..shader = Gradient.linear(
          Offset(t.center - railW * 0.34, 0),
          Offset(t.center + railW * 0.1, 0),
          const [_railSteelHi, _railSteel],
        ),
    );

    _drawLevels(canvas, t, color, levels, litFraction, glowPulse, railW);
    _drawLeverPlate(canvas, t, color);
    _drawBasePlaque(canvas, t, color, number);
  }

  /// The numbered strength levels beside the rail. Levels below the puck light
  /// up; the top few are warm/hot for the "ding zone".
  static void _drawLevels(
    Canvas canvas,
    TowerSpec t,
    Color color,
    int levels,
    double litFraction,
    double glowPulse,
    double railW,
  ) {
    if (levels <= 0) return;
    final gap = t.railSpan * _levelGapFrac;
    final cellH = (t.railSpan - gap * (levels + 1)) / levels;
    if (cellH <= 0) return;
    final tabW = t.width * 0.5;
    final litCount = (litFraction.clamp(0.0, 1.0) * levels).round();
    final left = t.center + railW * 0.55;

    for (var i = 0; i < levels; i++) {
      // i=0 is the bottom level, levels-1 the top (next to the bell).
      final top = t.railBottom - gap - (i + 1) * cellH - i * gap;
      final cy = top + cellH / 2;
      final lit = i < litCount;
      final hot = i >= levels - _hotLevels; // top band glows gold
      final baseCol = hot ? bellGold : color;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, tabW, cellH),
        Radius.circular(cellH * 0.3),
      );

      if (lit) {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = baseCol.withValues(alpha: 0.35 + 0.25 * glowPulse)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellH * 0.4),
        );
        canvas.drawRRect(rect, Paint()..color = baseCol);
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, cellH * 0.12)
            ..color = _blend(baseCol, _white, 0.5),
        );
      } else {
        canvas.drawRRect(
            rect, Paint()..color = baseCol.withValues(alpha: 0.12));
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = baseCol.withValues(alpha: 0.3),
        );
      }

      _drawText(
        canvas,
        '${i + 1}',
        Offset(left + tabW / 2, cy),
        cellH * 0.62,
        lit ? _readableText(baseCol) : _white.withValues(alpha: 0.5),
      );
    }
  }

  /// The lever plate the hammer strikes at the base of the rail.
  static void _drawLeverPlate(Canvas canvas, TowerSpec t, Color color) {
    final w = t.width * _plateWidthFrac;
    final h = t.width * 0.3;
    final center = t.leverPlate;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.4),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset(0, center.dy - h / 2),
          Offset(0, center.dy + h / 2),
          const [_plateSteel, _plateMid, _plateDark],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, h * 0.14)
        ..color = _railSteelHi,
    );
    // Player-color strike-target stripe across the pad.
    canvas.drawLine(
      Offset(center.dx - w * 0.32, center.dy),
      Offset(center.dx + w * 0.32, center.dy),
      Paint()
        ..strokeWidth = math.max(2.0, h * 0.22)
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  /// A slim colored ground nameplate carrying the player number, set well below
  /// the lever plate so it labels the tower without covering the striker.
  static void _drawBasePlaque(
      Canvas canvas, TowerSpec t, Color color, int number) {
    final w = t.width * 0.84;
    final h = t.width * 0.34;
    final center = Offset(t.center, t.leverPlate.dy + t.width * 0.7);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.32),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, h * 0.12)
        ..color = _blend(color, _white, 0.45),
    );
    _drawText(canvas, 'P$number', center, h * 0.6, _readableText(color),
        bold: true);
  }

  // ── Puck (rises with a trail) ───────────────────────────────────────────────
  static void drawPuck(
    Canvas canvas,
    TowerSpec t, {
    required double heightFrac,
    required Color color,
  }) {
    final frac = heightFrac.clamp(0.0, 1.0);
    final pos = t.puckAt(frac);
    final w = t.width * _puckWidthFrac;
    final h = t.width * _puckHeightFrac;

    // Rising trail: a few fading echoes below the puck.
    for (var i = _trailSegments; i >= 1; i--) {
      final tf = i / _trailSegments;
      final below = (frac - 0.05 * i).clamp(0.0, 1.0);
      if (below <= 0) break;
      final a = (1 - tf) * 0.35 * (frac > 0.02 ? 1 : 0);
      if (a <= 0.01) continue;
      final p = t.puckAt(below);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: p, width: w * (0.6 + 0.4 * (1 - tf)), height: h * 0.7),
          Radius.circular(h * 0.3),
        ),
        Paint()..color = color.withValues(alpha: a),
      );
    }

    // Puck glow.
    canvas.drawCircle(
      pos,
      w * 0.6,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.4),
    );

    // Puck body (a chunky rounded slug) with a top sheen.
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: pos, width: w, height: h),
      Radius.circular(h * 0.42),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset(0, pos.dy - h / 2),
          Offset(0, pos.dy + h / 2),
          [_blend(color, _white, 0.5), color, _blend(color, _black, 0.3)],
          const [0.0, 0.45, 1.0],
        ),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, h * 0.12)
        ..color = _blend(color, _white, 0.6),
    );
  }

  // ── Bell at the top ─────────────────────────────────────────────────────────
  static void drawBell(
    Canvas canvas,
    TowerSpec t, {
    required Color color,
    required bool rung,
    required double glowPulse,
  }) {
    final r = t.width * _bellRadiusFrac;
    final center = t.bell;
    if (r <= 1) return;

    // Mount cap the bell hangs from.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: center.translate(0, -r * 1.05),
            width: r * 0.7,
            height: r * 0.5),
        Radius.circular(r * 0.2),
      ),
      Paint()..color = _railSteel,
    );

    // Excited glow when rung.
    if (rung) {
      canvas.drawCircle(
        center,
        r * (1.4 + 0.3 * glowPulse),
        Paint()
          ..color = bellGold.withValues(alpha: 0.4 + 0.3 * glowPulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
      );
    }

    // Bell dome (a rounded bell shape via a cubic path).
    final dome = Path()
      ..moveTo(center.dx - r, center.dy + r * 0.7)
      ..cubicTo(
        center.dx - r,
        center.dy - r * 0.8,
        center.dx + r,
        center.dy - r * 0.8,
        center.dx + r,
        center.dy + r * 0.7,
      )
      ..close();
    canvas.drawPath(
      dome,
      Paint()
        ..shader = Gradient.linear(
          Offset(center.dx - r, center.dy),
          Offset(center.dx + r, center.dy),
          const [_bellHi, bellGold, _bellShadow],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawPath(
      dome,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.1)
        ..color = _bellShadow,
    );
    // Lip + clapper.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: center.translate(0, r * 0.72),
            width: r * 2.1,
            height: r * 0.32),
        Radius.circular(r * 0.16),
      ),
      Paint()..color = _bellShadow,
    );
    canvas.drawCircle(
        center.translate(0, r * 0.5), r * 0.18, Paint()..color = _bellShadow);
    // Player-color top knob so each bell reads as "yours".
    canvas.drawCircle(center.translate(0, -r * 0.45), r * 0.18,
        Paint()..color = _blend(color, _white, 0.2));
  }

  // ── Striker stickman + drawn hammer ─────────────────────────────────────────
  static void drawStriker(
    Canvas canvas,
    StickFigure figure,
    Offset root, {
    required double hammerSwing,
    required Offset hammerHead,
    required Color color,
    required double scale,
  }) {
    // Figure first (its front hand is roughly where the hammer is gripped).
    figure.render(canvas, root);
    _drawHammer(canvas, root, hammerSwing, hammerHead, color, scale);
  }

  /// A drawn mallet held in the striker's front hand, swinging on a rigid arc
  /// from raised-overhead (rest) down onto the lever plate (struck). [swing]
  /// 0 = raised, 1 = head on the plate.
  static void _drawHammer(
    Canvas canvas,
    Offset root,
    double swing,
    Offset plate,
    Color color,
    double scale,
  ) {
    final s = swing.clamp(0.0, 1.0);
    // Grip at the figure's front (right) hand, around chest height.
    final grip = root.translate(scale * 0.32, -scale * 1.45);
    // Rigid shaft length: long enough to reach the plate when struck.
    final toPlate = plate - grip;
    final shaftLen = math.max(scale * 1.4, toPlate.distance);
    // Struck angle points grip→plate; rest angle is swung up-and-back from it.
    final struck = math.atan2(toPlate.dy, toPlate.dx);
    const swingArc = 2.3; // radians from overhead to the plate
    final angle = struck - swingArc * (1 - s);
    final headPos =
        grip + Offset(math.cos(angle), math.sin(angle)) * shaftLen;

    final shaftW = math.max(2.0, scale * 0.12);
    canvas.drawLine(
      grip,
      headPos,
      Paint()
        ..color = _woodDark
        ..strokeWidth = shaftW
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      grip,
      headPos,
      Paint()
        ..color = _woodLight
        ..strokeWidth = shaftW * 0.45
        ..strokeCap = StrokeCap.round,
    );

    // Head: a steel block centered on headPos, oriented along the shaft.
    final dir = headPos - grip;
    final len = dir.distance;
    final n = len < 1e-3 ? const Offset(0, -1) : dir / len;
    final perp = Offset(-n.dy, n.dx);
    final headLen = scale * _hammerHeadFrac;
    final headThick = scale * 0.42;
    final c = headPos;
    final corners = <Offset>[
      c + n * (headLen / 2) + perp * (headThick / 2),
      c + n * (headLen / 2) - perp * (headThick / 2),
      c - n * (headLen / 2) - perp * (headThick / 2),
      c - n * (headLen / 2) + perp * (headThick / 2),
    ];
    canvas.drawPath(
      Path()..addPolygon(corners, true),
      Paint()..color = _steelHead,
    );
    canvas.drawPath(
      Path()..addPolygon(corners, true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, scale * 0.06)
        ..color = _blend(color, _white, 0.4),
    );
    // Bright steel band.
    canvas.drawCircle(c, headThick * 0.22, Paint()..color = _railSteelHi);

    // Impact flash at the head when fully struck.
    if (s > 0.85) {
      canvas.drawCircle(
        headPos,
        scale * 0.3 * (s - 0.85) / 0.15,
        Paint()
          ..color = _white.withValues(alpha: 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * 0.12),
      );
    }
  }

  // ── Tap flash ring ──────────────────────────────────────────────────────────
  /// An expanding ring + soft fill over the lever plate on every tap. [t] is the
  /// remaining-life fraction (1 = fresh, 0 = gone).
  static void drawTapFlash(
      Canvas canvas, Offset at, double t, Color color, double scale) {
    final k = t.clamp(0.0, 1.0);
    if (k <= 0.01) return;
    final grow = 1 - k; // 0 → 1 as it ages
    final r = scale * (0.4 + 1.1 * grow);
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, scale * 0.12 * k)
        ..color = _blend(color, _white, 0.4).withValues(alpha: 0.7 * k),
    );
    canvas.drawCircle(
      at,
      r * 0.5,
      Paint()
        ..color = color.withValues(alpha: 0.3 * k)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * 0.2),
    );
  }

  // ── Power bar ───────────────────────────────────────────────────────────────
  /// A centered power meter under the striker. [power] 0..1 fills from the
  /// middle outward and goes gold near full (the "fired up" band).
  static void drawPowerBar(
    Canvas canvas,
    Offset center,
    double width,
    double power,
    Color color,
  ) {
    final p = power.clamp(0.0, 1.0);
    final h = math.max(5.0, width * 0.09);
    final track = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: h),
      Radius.circular(h / 2),
    );
    canvas.drawRRect(track, Paint()..color = _black.withValues(alpha: 0.4));

    final fillW = width * p;
    if (fillW <= 1) return;
    final hot = Color.lerp(color, bellGold, p * p)!;
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: fillW, height: h),
      Radius.circular(h / 2),
    );
    canvas.drawRRect(fillRect, Paint()..color = hot);
    if (p > 0.6) {
      canvas.drawRRect(
        fillRect,
        Paint()
          ..color = bellGold.withValues(alpha: 0.4 * (p - 0.6) / 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.6),
      );
    }
  }

  // ── Combo badge ───────────────────────────────────────────────────────────
  /// A live "xN" combo multiplier badge floating above the striker. [combo] is
  /// the current streak (0 hides it until the player chains a couple), [comboMax]
  /// scales the gold "fired up" tint, and [pulse] 0..1 animates a heartbeat
  /// scale so a hot streak visibly throbs. Centered at [anchor].
  static void drawComboBadge(
    Canvas canvas,
    Offset anchor,
    int combo,
    int comboMax,
    Color color, {
    double pulse = 0,
  }) {
    if (combo < 2 || !anchor.dx.isFinite || !anchor.dy.isFinite) return;
    final t = (combo / math.max(1, comboMax)).clamp(0.0, 1.0);
    final p = pulse.clamp(0.0, 1.0);
    final hot = Color.lerp(color, bellGold, t)!;
    final fontSize = 18.0 + 16.0 * t + 3.0 * p;

    // Glow puck behind the text so it reads over the busy carnival background.
    canvas.drawCircle(
      anchor,
      fontSize * (0.9 + 0.2 * p),
      Paint()
        ..color = hot.withValues(alpha: 0.28 + 0.22 * t)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, fontSize * 0.6),
    );
    _drawText(
      canvas,
      'x$combo',
      anchor,
      fontSize,
      _white,
      bold: true,
    );
    // A thin colored under-stroke via a slightly offset tinted copy for punch.
    _drawText(
      canvas,
      'x$combo',
      anchor.translate(0, fontSize * 0.06),
      fontSize,
      hot.withValues(alpha: 0.55),
    );
  }

  // ── Contact shadow ──────────────────────────────────────────────────────────
  static void drawContactShadow(Canvas canvas, Offset groundCenter, double w) {
    canvas.drawOval(
      Rect.fromCenter(center: groundCenter, width: w * 2.4, height: w * 0.7),
      Paint()
        ..color = _black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.22),
    );
  }

  // ── Small private helpers ───────────────────────────────────────────────────
  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  /// Pick black or white text for legibility against [bg].
  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color, {
    bool bold = false,
  }) {
    if (fontSize <= 0) return;
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: fontSize * 4));
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - fontSize * 2, center.dy - fontSize * 0.62),
    );
  }
}
