import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Pure-Canvas rendering for [ChickenJump]. Holds NO game state and never
/// mutates the simulation — callers pass plain value snapshots. Kept in its own
/// file so the gameplay module stays lean and the drawing stays cohesive.
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class ChickenRenderer {
  ChickenRenderer._();

  /// Base hop-dust particle size (scaled by the figure scale by the caller).
  static const double dustSize = 4;

  /// Hot accent for the one-shot "HURRY!" climax popup (matches the lava crest).
  static const Color hurryColor = Color(0xFFFFC93C);

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _skyTop = Color(0xFF1A1230); // upper cave sky
  static const Color _skyMid = Color(0xFF241733);
  static const Color _caveBottom = Color(0xFF120A18); // hot depths
  static const Color _heat = Color(0xFFFF6A2A); // escalation wash
  static const Color _columnTop = Color(0xFF1B2436); // column backdrop top
  static const Color _columnBottom = Color(0xFF0C1119);
  static const Color _divider = Color(0xFF2A3550);
  static const Color _star = Color(0xFFBFD0FF); // parallax sparkle
  static const Color _rockNear = Color(0xFF222C42); // near parallax pillars

  static const Color _platHi = Color(0xFFB9C6DA); // stone top edge
  static const Color _platMid = Color(0xFF63708A);
  static const Color _platLo = Color(0xFF333C52);
  static const Color _platEdge = Color(0xFF1A1F2C);

  static const Color _lavaCore = Color(0xFFFF7321); // main molten body
  static const Color _lavaDeep = Color(0xFFB81E12); // deep red toward bottom
  static const Color _lavaCrest = Color(0xFFFFD24A); // bright surface line
  static const Color _ember = Color(0xFFFFC247);

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  // ── Tuning (visual only) ───────────────────────────────────────────────────
  static const double _platHeightFactor = 0.10; // plat height / column width
  static const double _platWidthFactor = 0.78; // plat width / column width
  static const int _starsPerColumn = 14;
  static const int _pillarsPerColumn = 3;
  static const double _parallaxFar = 0.18; // far layer drift factor
  static const double _parallaxNear = 0.42; // near layer drift factor
  static const int _lavaWaves = 7; // surface ripple segments
  static const double _lavaCrestH = 6; // bright crest band thickness
  static const int _emberCount = 7; // floating embers above the lava
  static const double _contactShadowW = 2.0;
  static const double _contactShadowH = 0.42;
  static const double _altBarWFactor = 0.05; // altitude bar width / column width

  // ── Background ──────────────────────────────────────────────────────────────

  /// Full-arena cave gradient backdrop. Drawn once under every column.
  /// [intensity] in 0..1 adds a rising heat wash as the lava escalates.
  static void drawBackground(Canvas canvas, Size size, double intensity) {
    if (size.isEmpty) return;
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_skyTop, _skyMid, _caveBottom],
        const [0.0, 0.45, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bg);

    final heat = intensity.clamp(0.0, 1.0);
    if (heat > 0.01) {
      final wash = Paint()
        ..shader = Gradient.linear(
          Offset(size.width / 2, size.height),
          Offset(size.width / 2, size.height * 0.4),
          [_heat.withValues(alpha: 0.14 * heat), const Color(0x00000000)],
        );
      canvas.drawRect(Offset.zero & size, wash);
    }
  }

  // ── One player column ─────────────────────────────────────────────────────

  /// The column backdrop: a tinted vertical band, a parallax starfield + rock
  /// pillars that drift down as the climber rises ([parallax] = px ascended), a
  /// neon side frame that brightens with [danger], and a divider edge.
  static void drawColumnBackdrop(
    Canvas canvas,
    Rect column,
    Color color,
    double parallax,
    double danger,
    bool alive,
  ) {
    if (column.width <= 1 || column.height <= 1) return;
    final a = alive ? 1.0 : 0.45;
    final d = danger.clamp(0.0, 1.0);

    canvas.save();
    canvas.clipRect(column);

    // Tinted vertical band.
    final band = Paint()
      ..shader = Gradient.linear(
        Offset(column.center.dx, column.top),
        Offset(column.center.dx, column.bottom),
        [
          _blend(_columnTop, color, 0.06 * a),
          _columnBottom,
        ],
      );
    canvas.drawRect(column, band);

    _drawParallaxStars(canvas, column, parallax, a);
    _drawParallaxPillars(canvas, column, parallax, color, a);

    canvas.restore();

    _drawColumnFrame(canvas, column, color, d, a);
  }

  /// A far drifting starfield. Positions are deterministic from the index (no
  /// rng needed) and wrap with [parallax] so it scrolls seamlessly.
  static void _drawParallaxStars(
      Canvas canvas, Rect column, double parallax, double a) {
    final drift = parallax * _parallaxFar;
    final paint = Paint();
    for (var i = 0; i < _starsPerColumn; i++) {
      final fx = _hash(i * 2 + 1);
      final fy = _hash(i * 2 + 7);
      final x = column.left + fx * column.width;
      // Drift downward, wrapping over the column height.
      final y = column.top + ((fy * column.height + drift) % column.height);
      final tw = 0.4 + 0.4 * fx;
      paint.color = _star.withValues(alpha: (0.18 + 0.22 * tw) * a);
      canvas.drawCircle(Offset(x, y), 0.8 + 1.4 * fy, paint);
    }
  }

  /// Near rock pillars on the column sides for depth; drift faster than stars.
  static void _drawParallaxPillars(
      Canvas canvas, Rect column, double parallax, Color color, double a) {
    final drift = parallax * _parallaxNear;
    final w = column.width * 0.16;
    final gap = column.height / _pillarsPerColumn;
    if (gap <= 4) return;
    final fill = Paint()..color = _rockNear.withValues(alpha: 0.6 * a);
    final edgeColor =
        _blend(_rockNear, color, 0.25).withValues(alpha: 0.5 * a);
    for (var side = 0; side < 2; side++) {
      final left = side == 0;
      final x0 = left ? column.left : column.right - w;
      for (var i = -1; i <= _pillarsPerColumn; i++) {
        final base = column.top + ((i * gap + drift) % (column.height + gap));
        final h = gap * 0.5;
        final rect = Rect.fromLTWH(x0, base - h * 0.5, w, h);
        final rr = RRect.fromRectAndCorners(
          rect,
          topRight: left ? Radius.circular(w * 0.5) : Radius.zero,
          bottomRight: left ? Radius.circular(w * 0.5) : Radius.zero,
          topLeft: left ? Radius.zero : Radius.circular(w * 0.5),
          bottomLeft: left ? Radius.zero : Radius.circular(w * 0.5),
        );
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, w * 0.08)
            ..color = edgeColor,
        );
      }
    }
  }

  /// Soft neon side frame around the column; brightens with [danger].
  static void _drawColumnFrame(
      Canvas canvas, Rect column, Color color, double d, double a) {
    final inset = column.deflate(math.max(2.0, column.width * 0.02));
    final rrect = RRect.fromRectAndRadius(
        inset, Radius.circular(math.max(6.0, column.width * 0.06)));

    // Soft neon frame: a wide, faint stroke under the crisp core line fakes the
    // glow without a per-column blur. Widen with danger instead of blurring more.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3.0, column.width * 0.05 + 6 * d)
      ..color = color.withValues(alpha: (0.08 + 0.22 * d) * a);
    canvas.drawRRect(rrect, glow);

    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, column.width * 0.008)
      ..color = color.withValues(alpha: (0.4 + 0.4 * d) * a);
    canvas.drawRRect(rrect, core);

    // Divider edge between adjacent columns.
    canvas.drawLine(
      Offset(column.left, column.top),
      Offset(column.left, column.bottom),
      Paint()
        ..strokeWidth = 1.5
        ..color = _divider.withValues(alpha: 0.7 * a),
    );
  }

  // ── Platform ────────────────────────────────────────────────────────────────

  /// A clear stone/neon platform centered at [center]. [lit] highlights the rung
  /// the climber currently stands on. [anticipate] in 0..1 marks the rung the
  /// climber will hop to NEXT: a pulsing player-colored halo + chevrons so the
  /// target is always readable (it swells as the lava nears, screaming "jump
  /// here now"). Platforms are always solid — a kid only has to learn "tap to
  /// hop up".
  static void drawPlatform(
    Canvas canvas,
    Offset center,
    double columnWidth,
    Color color, {
    required bool lit,
    double anticipate = 0,
  }) {
    if (columnWidth <= 1) return;

    final w = columnWidth * _platWidthFactor;
    final h = math.max(6.0, columnWidth * _platHeightFactor);

    // Next-rung target cue, drawn beneath the platform so the stone reads on top.
    final ant = anticipate.clamp(0.0, 1.0);
    if (ant > 0.01) {
      _drawNextRungCue(canvas, center, w, h, color, ant);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);

    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.4));

    // Lit rung gets a soft halo: two stacked translucent rounded fills (wide+faint
    // under tight+stronger) instead of a per-rung blur.
    if (lit) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(h * 0.8), Radius.circular(h)),
        Paint()..color = color.withValues(alpha: 0.12),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect.inflate(h * 0.4), Radius.circular(h * 0.6)),
        Paint()..color = color.withValues(alpha: 0.2),
      );
    }

    // The anticipated next rung also gets a bright colored rim so it pops even
    // against a busy background.
    if (ant > 0.01) {
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, h * 0.16)
          ..color =
              _blend(color, _white, 0.3).withValues(alpha: 0.35 + 0.45 * ant),
      );
    }

    // Stone body (top-lit gradient).
    final body = Paint()
      ..shader = Gradient.linear(
        Offset(0, -h * 0.5),
        Offset(0, h * 0.5),
        const [_platMid, _platLo],
      );
    canvas.drawRRect(rr, body);

    // Bright top edge — a neon-lit lip tinted toward the player color.
    final lipColor = _blend(_platHi, color, lit ? 0.5 : 0.18);
    canvas.drawLine(
      Offset(-w * 0.5 + h * 0.3, -h * 0.5 + h * 0.18),
      Offset(w * 0.5 - h * 0.3, -h * 0.5 + h * 0.18),
      Paint()
        ..strokeWidth = math.max(1.5, h * 0.22)
        ..strokeCap = StrokeCap.round
        ..color = lipColor,
    );

    // Dark base edge.
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, h * 0.12)
        ..color = _platEdge,
    );
    canvas.restore();
  }

  /// A bobbing "tap to hop" cue floating just above the climber during the
  /// warmup: a stack of upward chevrons + a soft halo, in the player color, so
  /// the one control reads instantly before the lava starts. [t] is a free clock
  /// for the bob; [head] is the climber's render root (pelvis).
  static void drawTapHint(
    Canvas canvas,
    Offset head,
    double columnWidth,
    Color color,
    double t,
  ) {
    if (columnWidth <= 1) return;
    final h = math.max(6.0, columnWidth * _platHeightFactor);
    final bob = math.sin(t * 4.0) * h * 0.5;
    final base = head.translate(0, -columnWidth * 0.42 + bob);
    final chevColor = _blend(color, _white, 0.4);
    final cw = columnWidth * 0.14;
    for (var i = 0; i < 2; i++) {
      final cy = base.dy - i * h * 1.1;
      final path = Path()
        ..moveTo(base.dx - cw, cy + h * 0.6)
        ..lineTo(base.dx, cy - h * 0.2)
        ..lineTo(base.dx + cw, cy + h * 0.6);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, h * 0.3)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = chevColor.withValues(alpha: i == 0 ? 0.95 : 0.55),
      );
    }
  }

  /// The "hop here next" cue under a target rung: a soft halo plus a stack of
  /// chevrons pointing up at the rung. [pulse] in 0..1 scales the brightness and
  /// how high the chevrons float, so it reads calm when safe and urgent when the
  /// lava is close.
  static void _drawNextRungCue(
    Canvas canvas,
    Offset center,
    double w,
    double h,
    Color color,
    double pulse,
  ) {
    final p = pulse.clamp(0.0, 1.0);

    // Soft halo hugging the rung: two stacked translucent ovals (wide+faint
    // under tight+stronger) approximate the glow without a per-cue blur.
    canvas.drawOval(
      Rect.fromCenter(
          center: center, width: w * (1.35 + 0.2 * p), height: h * 3.2),
      Paint()..color = color.withValues(alpha: (0.08 + 0.16 * p)),
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: center, width: w * (1.05 + 0.15 * p), height: h * 2.4),
      Paint()..color = color.withValues(alpha: (0.14 + 0.24 * p)),
    );

    // Two chevrons floating just above the rung, pointing up at the target.
    final chevColor =
        _blend(color, _white, 0.35).withValues(alpha: 0.5 + 0.5 * p);
    final cw = w * 0.22;
    final lift = h * (0.9 + 0.6 * p); // float higher when urgent
    for (var i = 0; i < 2; i++) {
      final cy = center.dy - lift - i * h * 0.8;
      final path = Path()
        ..moveTo(center.dx - cw, cy + h * 0.45)
        ..lineTo(center.dx, cy - h * 0.15)
        ..lineTo(center.dx + cw, cy + h * 0.45);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, h * 0.16)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = chevColor.withValues(
              alpha: chevColor.a * (i == 0 ? 1.0 : 0.55)),
      );
    }
  }

  // ── Lava ──────────────────────────────────────────────────────────────────

  /// Rising lava filling the column from [lavaY] down. A bubbling crest ripples
  /// with [t] (a free-running clock), embers float above, and a danger glow
  /// brightens the crest as it nears the climber. Clipped to the column.
  static void drawLava(
    Canvas canvas,
    Rect column,
    double lavaY,
    double t,
    double danger,
  ) {
    if (column.width <= 1) return;
    // Nothing to draw while the lava is still below the column.
    if (lavaY >= column.bottom + column.width) return;
    final top = lavaY.clamp(column.top - column.height, column.bottom);

    canvas.save();
    canvas.clipRect(column);

    // Molten body gradient (overshoot below keeps it solid past the column).
    final bodyRect = Rect.fromLTRB(
        column.left, top, column.right, column.bottom + column.height);
    canvas.drawRect(
      bodyRect,
      Paint()
        ..shader = Gradient.linear(
          Offset(column.center.dx, top),
          Offset(column.center.dx, column.bottom),
          const [_lavaCore, _lavaDeep],
        ),
    );

    _drawLavaCrest(canvas, column, top, t, danger);
    _drawEmbers(canvas, column, top, t);

    canvas.restore();
  }

  /// Bubbling bright crest: a rippled band riding the lava surface + a soft glow
  /// that intensifies with [danger].
  static void _drawLavaCrest(
      Canvas canvas, Rect column, double top, double t, double danger) {
    final d = danger.clamp(0.0, 1.0);
    final amp = math.max(2.0, column.width * 0.02);
    final seg = column.width / _lavaWaves;

    // Soft danger glow over the surface (filled ripple band).
    final glowPath = Path()..moveTo(column.left, top);
    for (var i = 0; i <= _lavaWaves; i++) {
      final x = column.left + seg * i;
      final y = top + math.sin(t * 3.2 + i * 1.3) * amp;
      glowPath.lineTo(x, y);
    }
    glowPath
      ..lineTo(column.right, top + column.width * 0.5)
      ..lineTo(column.left, top + column.width * 0.5)
      ..close();
    // Filled translucent ripple band (no blur) gives a soft surface wash under
    // the crisp crest line below — cheap per column.
    canvas.drawPath(
      glowPath,
      Paint()..color = _lavaCrest.withValues(alpha: 0.18 + 0.32 * d),
    );

    // Crisp bright crest line riding the ripple.
    final crest = Path()..moveTo(column.left, top);
    for (var i = 0; i <= _lavaWaves; i++) {
      final x = column.left + seg * i;
      final y = top + math.sin(t * 3.2 + i * 1.3) * amp;
      crest.lineTo(x, y);
    }
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _lavaCrestH
        ..strokeCap = StrokeCap.round
        ..color = _lavaCrest.withValues(alpha: 0.85),
    );

    // A few molten bubbles just under the crest.
    final bubble = Paint()..color = _lavaCrest.withValues(alpha: 0.5);
    for (var i = 0; i < _lavaWaves; i++) {
      final phase = (t * 0.9 + i * 0.7) % 1.0;
      final x = column.left + seg * (i + 0.5);
      final y = top + column.width * 0.08 + phase * column.width * 0.1;
      final r = (column.width * 0.02) * (0.5 + 0.5 * math.sin(t * 4 + i));
      if (r > 0.4) canvas.drawCircle(Offset(x, y), r, bubble);
    }
  }

  /// Floating embers drifting up from the lava surface.
  static void _drawEmbers(Canvas canvas, Rect column, double top, double t) {
    final paint = Paint();
    for (var i = 0; i < _emberCount; i++) {
      final fx = _hash(i * 3 + 2);
      // Each ember rises on its own loop above the surface.
      final phase = (t * (0.4 + 0.3 * fx) + fx) % 1.0;
      final x = column.left + fx * column.width;
      final y = top - phase * column.width * 0.9;
      if (y < column.top) continue;
      final r = (column.width * 0.012) * (1.0 - phase);
      if (r <= 0.3) continue;
      paint.color = _ember.withValues(alpha: (1.0 - phase) * 0.9);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  // ── Climber contact shadow + figure ────────────────────────────────────────

  /// Soft contact shadow ellipse beneath the climber at the rung line.
  static void drawContactShadow(
      Canvas canvas, Offset groundCenter, double width, bool alive) {
    if (!alive || width <= 0) return;
    // Two stacked translucent ovals (wide+faint under tight+darker) fake the
    // soft edge without a per-climber blur.
    canvas.drawOval(
      Rect.fromCenter(
        center: groundCenter,
        width: width * (_contactShadowW + 0.5),
        height: width * (_contactShadowH + 0.18),
      ),
      Paint()..color = _black.withValues(alpha: 0.14),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: groundCenter,
        width: width * _contactShadowW,
        height: width * _contactShadowH,
      ),
      Paint()..color = _black.withValues(alpha: 0.26),
    );
  }

  /// Render the stick climber. Kept here so the painter call lives with the
  /// rest of the visuals; [figure] owns its own pose/ragdoll state.
  static void drawClimber(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }

  // ── Altitude indicator ──────────────────────────────────────────────────────

  /// A vertical altitude bar pinned to the column's inner edge: a track plus a
  /// player-colored fill rising with [fraction] (0..1) and a glowing cap. A
  /// clear, font-light progress cue.
  static void drawAltitude(
    Canvas canvas,
    Rect column,
    double fraction,
    Color color,
    bool alive,
  ) {
    if (column.width <= 1 || column.height <= 1) return;
    final a = alive ? 0.95 : 0.4;
    final f = fraction.clamp(0.0, 1.0);

    final w = math.max(4.0, column.width * _altBarWFactor);
    final pad = math.max(6.0, column.width * 0.06);
    final x = column.left + pad + w * 0.5;
    final top = column.top + pad * 1.6;
    final bottom = column.bottom - pad * 1.6;
    if (bottom <= top) return;

    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(x - w * 0.5, top, x + w * 0.5, bottom),
      Radius.circular(w * 0.5),
    );
    // Track.
    canvas.drawRRect(
      trackRect,
      Paint()..color = _black.withValues(alpha: 0.32 * a),
    );

    // Fill from the bottom up.
    final fillTop = bottom - (bottom - top) * f;
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(x - w * 0.5, fillTop, x + w * 0.5, bottom),
      Radius.circular(w * 0.5),
    );
    canvas.drawRRect(
      fillRect,
      Paint()
        ..shader = Gradient.linear(
          Offset(x, bottom),
          Offset(x, fillTop),
          [_blend(color, _black, 0.2), color],
        ),
    );

    // Glowing cap at the fill head: two stacked translucent halos (wide+faint,
    // tight+stronger) under the bright core — no per-column blur.
    canvas.drawCircle(Offset(x, fillTop), w * 1.1,
        Paint()..color = color.withValues(alpha: 0.2 * a));
    canvas.drawCircle(Offset(x, fillTop), w * 0.8,
        Paint()..color = color.withValues(alpha: 0.34 * a));
    canvas.drawCircle(
      Offset(x, fillTop),
      w * 0.5,
      Paint()..color = _blend(color, _white, 0.4).withValues(alpha: a),
    );

    // Track outline for crispness.
    canvas.drawRRect(
      trackRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.16)
        ..color = color.withValues(alpha: 0.4 * a),
    );
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  /// Cheap deterministic 0..1 hash for stable parallax/ember placement.
  static double _hash(int n) {
    final s = math.sin(n * 12.9898) * 43758.5453;
    return s - s.floorToDouble();
  }
}
