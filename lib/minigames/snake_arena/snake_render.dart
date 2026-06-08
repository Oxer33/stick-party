import 'dart:math' as math;
import 'dart:ui';

/// Pure-Canvas rendering for [SnakeArena] — a TRON-style neon grid arena. Holds
/// NO game state and never mutates the simulation; callers pass plain value
/// snapshots (cells resolved to pixels, colors, scalar phases). Kept in its own
/// file so the gameplay module stays lean and the drawing stays cohesive
/// (mirrors the sumo_smash / tap_sprint split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class SnakeRenderer {
  SnakeRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _bgTop = Color(0xFF050912);
  static const Color _bgBottom = Color(0xFF02040A);
  static const Color _vignette = Color(0xCC000000);
  static const Color _gridLine = Color(0xFF11324A);
  static const Color _gridGlow = Color(0xFF0E2740);
  static const Color _gridMajor = Color(0xFF1C5677);
  static const Color _wallNeon = Color(0xFF2FE4FF);
  static const Color _foodCore = Color(0xFFFFF3B0);
  static const Color _foodNeon = Color(0xFFFFC93C);
  static const Color _goldenFood = Color(0xFFFFD24A); // swingy bonus pellet
  static const Color _sdWall = Color(0xFFFF5A3C); // SUDDEN DEATH closing wall
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _hudTrack = Color(0x33FFFFFF);

  // ── Tuning (fractions / px; no inline magic numbers) ───────────────────────
  static const int _majorEvery = 4; // brighter grid line every N cells
  static const double _gridLineW = 1.0;
  static const double _gridMajorW = 1.6;
  static const double _wallGlowW = 10.0;
  static const double _wallCoreW = 2.4;
  static const double _bodyInset = 0.14; // gap around a cell (fraction of cell)
  static const double _headRadiusFactor = 0.46;
  static const double _bodyRadiusFactor = 0.30;
  static const double _eyeRadiusFactor = 0.11;
  static const double _foodPulseAmp = 0.18; // pellet radius pulse amplitude
  static const double _foodBaseFactor = 0.30; // pellet radius / cell
  static const int _foodSparkArms = 4;
  static const double _pipGap = 6.0;
  static const double _pipRadius = 4.0;
  static const double _speedTintMax = 0.16; // max red screen tint alpha

  // Turn indicator (the "tap left / tap right to steer" hint flanking a head).
  static const double _turnArrowGapFactor = 1.05; // arrow distance from head / cell
  static const double _turnArrowSizeFactor = 0.55; // arrowhead size / cell
  static const double _turnGhostFactor = 0.26; // landing-dot radius / cell

  /// Arena backdrop: vertical gradient + soft top-down vignette. Drawn first,
  /// fills the whole surface so the neon reads against deep black.
  static void drawBackground(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgBottom],
      );
    canvas.drawRect(Offset.zero & size, bg);

    final r = math.max(size.width, size.height);
    final vignette = Paint()
      ..shader = Gradient.radial(
        Offset(size.width / 2, size.height / 2),
        r * 0.72,
        const [Color(0x00000000), _vignette],
        const [0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, vignette);
  }

  /// The glowing logical grid inside [field]. [cols]/[rows] size the lattice;
  /// [pulse] (0..1) breathes the line brightness so the arena feels alive.
  static void drawGrid(
    Canvas canvas,
    Rect field,
    int cols,
    int rows,
    double pulse,
  ) {
    if (cols <= 0 || rows <= 0 || field.width <= 1 || field.height <= 1) return;
    final cw = field.width / cols;
    final ch = field.height / rows;
    final breathe = 0.5 + 0.5 * pulse.clamp(0.0, 1.0);

    // Soft glow underlay (wide, faint) then crisp lines on top. A wider faint
    // stroke under each crisp line fakes the glow without a per-line blur — this
    // runs for every grid line each frame, so the blur removal is a big saving.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _gridLineW * 4.0
      ..color = _gridGlow.withValues(alpha: 0.32 * breathe);

    final minor = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _gridLineW
      ..color = _gridLine.withValues(alpha: 0.55 + 0.25 * breathe);
    final major = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _gridMajorW
      ..color = _gridMajor.withValues(alpha: 0.6 + 0.3 * breathe);

    for (var c = 0; c <= cols; c++) {
      final x = field.left + c * cw;
      final p1 = Offset(x, field.top);
      final p2 = Offset(x, field.bottom);
      final isMajor = c % _majorEvery == 0;
      canvas.drawLine(p1, p2, glow);
      canvas.drawLine(p1, p2, isMajor ? major : minor);
    }
    for (var r = 0; r <= rows; r++) {
      final y = field.top + r * ch;
      final p1 = Offset(field.left, y);
      final p2 = Offset(field.right, y);
      final isMajor = r % _majorEvery == 0;
      canvas.drawLine(p1, p2, glow);
      canvas.drawLine(p1, p2, isMajor ? major : minor);
    }
  }

  /// The neon wall border framing the arena: a wide outer glow + a crisp core
  /// line. [intensity] (0..1) flares it (e.g. on a crash or speed-up).
  static void drawWalls(Canvas canvas, Rect field, double intensity) {
    if (field.width <= 1 || field.height <= 1) return;
    final flare = intensity.clamp(0.0, 1.0);
    // Two stacked translucent border strokes (wide+faint over slightly tighter)
    // under the crisp core line fake the neon bloom without a blur.
    canvas.drawRect(
      field,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _wallGlowW * (1.6 + 0.9 * flare)
        ..color = _wallNeon.withValues(alpha: 0.12 + 0.18 * flare),
    );
    canvas.drawRect(
      field,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _wallGlowW * (0.8 + 0.5 * flare)
        ..color = _wallNeon.withValues(alpha: 0.2 + 0.28 * flare),
    );

    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _wallCoreW
      ..color = Color.lerp(_wallNeon, _white, 0.25 + 0.4 * flare) ?? _wallNeon;
    canvas.drawRect(field, core);
  }

  /// The SUDDEN DEATH closing wall: a hot, throbbing red border around the
  /// still-playable [box] (which shrinks as the finale advances). [pulse] (0..1)
  /// breathes it. A wide faint stroke under a crisp core fakes the danger bloom
  /// without a blur — this is the unmistakable "the arena is eating you" cue.
  static void drawClosingWalls(Canvas canvas, Rect box, double pulse) {
    if (box.width <= 1 || box.height <= 1) return;
    final p = pulse.clamp(0.0, 1.0);
    canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _wallGlowW * (1.2 + 0.6 * p)
        ..color = _sdWall.withValues(alpha: 0.16 + 0.16 * p),
    );
    canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _wallCoreW * 1.3
        ..color = Color.lerp(_sdWall, _white, 0.2 + 0.3 * p) ?? _sdWall,
    );
  }

  /// A pulsing food pellet at pixel [center] of radius scaled to [cell]. Layered
  /// glow → core → bright center → rotating sparkle arms. [phase] animates the
  /// pulse + sparkle; [neon] tints it.
  static void drawFood(
    Canvas canvas,
    Offset center,
    double cell,
    double phase, {
    Color neon = _foodNeon,
    bool golden = false,
  }) {
    if (cell <= 0) return;
    // A golden pellet is a swingy bonus: a warm gold neon and a touch bigger so
    // it stands out from the everyday pellets and draws a scramble.
    final tint = golden ? _goldenFood : neon;
    final pulse = 1.0 + _foodPulseAmp * math.sin(phase * 3.0);
    final r = cell * _foodBaseFactor * pulse * (golden ? 1.35 : 1.0);

    // Outer glow halo: two stacked translucent rings (wide+faint, tight+stronger)
    // instead of a per-pellet blur. Golden pellets bloom a little brighter.
    final haloBoost = golden ? 0.10 : 0.0;
    canvas.drawCircle(center, r * 2.8,
        Paint()..color = tint.withValues(alpha: 0.12 + haloBoost));
    canvas.drawCircle(center, r * 2.0,
        Paint()..color = tint.withValues(alpha: 0.2 + haloBoost));
    // Neon body.
    canvas.drawCircle(center, r, Paint()..color = tint);
    // Bright hot core.
    canvas.drawCircle(
      center.translate(-r * 0.22, -r * 0.22),
      r * 0.5,
      Paint()..color = _foodCore,
    );

    // Rotating sparkle arms.
    final spark = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, r * 0.18)
      ..color = _white.withValues(
          alpha: 0.5 + 0.3 * (0.5 + 0.5 * math.sin(phase * 4.0)));
    for (var i = 0; i < _foodSparkArms; i++) {
      final a = phase * 1.5 + i * (math.pi / 2);
      final dir = Offset(math.cos(a), math.sin(a));
      final inner = r * 1.2;
      final outer = r * (1.9 + 0.25 * math.sin(phase * 5.0 + i));
      canvas.drawLine(center + dir * inner, center + dir * outer, spark);
    }
  }

  /// Draw one snake as a fading neon trail of rounded segments. [pixels] are the
  /// per-segment pixel centers, head first. [heading] is the head's unit pixel
  /// direction (for the eyes). [color] is the player neon; [alive] dims the
  /// whole snake when false (post-crash husk).
  static void drawSnake(
    Canvas canvas,
    List<Offset> pixels,
    Offset heading,
    double cell,
    Color color, {
    required bool alive,
  }) {
    if (pixels.isEmpty || cell <= 0) return;
    final n = pixels.length;
    final dim = alive ? 1.0 : 0.22;
    final inset = cell * _bodyInset;
    final bodyR = math.max(1.0, cell * _bodyRadiusFactor);
    final headR = math.max(1.0, cell * _headRadiusFactor);

    // 1) Wide soft glow pass under the body (tail faints out) — the light trail.
    // Wider, faint translucent circles per segment fake the bloom without a
    // per-segment blur (this loop runs for every segment of every snake).
    final glowPaint = Paint();
    for (var i = n - 1; i >= 0; i--) {
      final f = 1.0 - i / n; // 1 at head → ~0 at tail
      final a = (0.07 + 0.22 * f) * dim;
      if (a <= 0.01) continue;
      glowPaint.color = color.withValues(alpha: a);
      canvas.drawCircle(
          pixels[i], (bodyR + inset) * (0.9 + 1.0 * f), glowPaint);
    }

    // 2) Connective neon ribbon so segments read as one continuous body.
    if (n >= 2) {
      final ribbon = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (var i = 0; i < n - 1; i++) {
        final f = 1.0 - i / n;
        ribbon
          ..strokeWidth = (cell - inset * 2) * (0.5 + 0.45 * f)
          ..color = _segColor(color, f)
              .withValues(alpha: (0.85 * dim).clamp(0.0, 1.0));
        canvas.drawLine(pixels[i], pixels[i + 1], ribbon);
      }
    }

    // 3) Crisp rounded segments, gradient head→tail, brightest at the head.
    for (var i = n - 1; i >= 1; i--) {
      final f = 1.0 - i / n;
      final c =
          _segColor(color, f).withValues(alpha: (0.9 * dim).clamp(0.0, 1.0));
      canvas.drawCircle(pixels[i], bodyR * (0.7 + 0.5 * f), Paint()..color = c);
    }

    // 4) The head: bright glow + body + a white-hot core + eyes. Two stacked
    // translucent halos (wide+faint, tight+stronger) replace the per-head blur.
    final head = pixels.first;
    canvas.drawCircle(head, headR * 2.2,
        Paint()..color = color.withValues(alpha: 0.18 * dim));
    canvas.drawCircle(head, headR * 1.5,
        Paint()..color = color.withValues(alpha: 0.32 * dim));
    canvas.drawCircle(head, headR,
        Paint()..color = Color.lerp(color, _white, 0.15) ?? color);
    canvas.drawCircle(head, headR * 0.42,
        Paint()..color = _white.withValues(alpha: 0.85 * dim));

    if (alive) {
      _drawEyes(canvas, head, heading, headR);
    }
  }

  static void _drawEyes(
      Canvas canvas, Offset head, Offset heading, double headR) {
    var dir = heading;
    if (dir.distance < 1e-3) dir = const Offset(0, -1);
    dir = dir / dir.distance;
    final side = Offset(-dir.dy, dir.dx); // perpendicular
    final eyeR = headR * (_eyeRadiusFactor / _headRadiusFactor);
    final fwd = head + dir * headR * 0.4;
    final whitePaint = Paint()..color = _white;
    final pupil = Paint()..color = _black.withValues(alpha: 0.85);
    for (final s in const [1.0, -1.0]) {
      final eye = fwd + side * headR * 0.42 * s;
      canvas.drawCircle(eye, math.max(1.0, eyeR), whitePaint);
      canvas.drawCircle(
          eye + dir * eyeR * 0.4, math.max(0.6, eyeR * 0.55), pupil);
    }
  }

  /// The "tap LEFT = turn left, tap RIGHT = turn right" affordance: two arrows
  /// flanking the head, each pointing where that tap would send the snake, plus a
  /// faint landing dot on the cell each turn would step into. Drawn over every
  /// snake so the one rule of the game is unmistakable. [forward] is the current
  /// unit heading (accepted for API symmetry / future use); [left] and [right]
  /// are the unit headings after a left / right turn. [pulse] (0..1) breathes the
  /// brightness; [emphasis] (0..1) fades it in at the round start then settles to
  /// a calm idle level.
  static void drawTurnHint(
    Canvas canvas,
    Offset head,
    Offset forward,
    Offset left,
    Offset right,
    double cell,
    Color color, {
    double pulse = 1.0,
    double emphasis = 1.0,
  }) {
    if (cell <= 0) return;
    final em = emphasis.clamp(0.0, 1.0);
    if (em <= 0.01) return;
    final a = ((0.30 + 0.45 * pulse.clamp(0.0, 1.0)) * em).clamp(0.0, 1.0);

    _drawTurnArrow(canvas, head, left, cell, color, a, em);
    _drawTurnArrow(canvas, head, right, cell, color, a, em);
  }

  /// One steering arrow: a chevron sitting just beyond the head along [dir] (the
  /// heading that tap produces) and pointing that way, with a faint landing dot
  /// on the cell the snake would move into.
  static void _drawTurnArrow(
    Canvas canvas,
    Offset head,
    Offset dir,
    double cell,
    Color color,
    double a,
    double em,
  ) {
    var d = dir;
    if (d.distance < 1e-3) d = const Offset(1, 0);
    d = d / d.distance;
    final perp = Offset(-d.dy, d.dx);

    // Landing dot: the cell the head reaches after this turn (one cell along d).
    final ghost = head + d * cell;
    final ghostR = cell * _turnGhostFactor;
    canvas.drawCircle(ghost, ghostR * 1.3,
        Paint()..color = color.withValues(alpha: (0.10 * em).clamp(0.0, 1.0)));
    canvas.drawCircle(ghost, ghostR,
        Paint()..color = color.withValues(alpha: (0.20 * em).clamp(0.0, 1.0)));
    canvas.drawCircle(ghost, ghostR * 0.5,
        Paint()..color = _white.withValues(alpha: (0.30 * em).clamp(0.0, 1.0)));

    // Chevron pointing along d, placed just beyond the head.
    final tip = head + d * (cell * _turnArrowGapFactor);
    final size = cell * _turnArrowSizeFactor;
    final back = tip - d * size;
    final path = Path()
      ..moveTo((back + perp * size * 0.5).dx, (back + perp * size * 0.5).dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo((back - perp * size * 0.5).dx, (back - perp * size * 0.5).dy);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = math.max(1.5, cell * 0.12)
        ..color = (Color.lerp(color, _white, 0.25) ?? color)
            .withValues(alpha: (a * 1.1).clamp(0.0, 1.0)),
    );
  }

  /// Per-player status strip: a colored chip with a length/score readout and a
  /// row of "length pips". Drawn in screen space. [slot] is the row index
  /// (0-based, top→down) within [bar]; [total] rows share the bar height.
  static void drawPlayerStat(
    Canvas canvas,
    Rect bar,
    int slot,
    int total,
    Color color,
    int length,
    bool alive,
  ) {
    if (bar.width <= 1 || total <= 0) return;
    final rowH = bar.height / total;
    final top = bar.top + slot * rowH;
    final pad = rowH * 0.22;
    final chip = Rect.fromLTWH(
        bar.left, top + pad, bar.width, math.max(2.0, rowH - pad * 2));
    final dim = alive ? 1.0 : 0.4;

    // Chip background + outline + colored leading dot.
    final rr = RRect.fromRectAndRadius(chip, Radius.circular(chip.height * 0.5));
    canvas.drawRRect(rr, Paint()..color = _black.withValues(alpha: 0.32 * dim));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: 0.7 * dim),
    );
    canvas.drawCircle(
      Offset(chip.left + chip.height * 0.55, chip.center.dy),
      chip.height * 0.30,
      Paint()..color = color.withValues(alpha: dim),
    );

    // Length pips trailing to the right (capped to what fits).
    final firstPipX = chip.left + chip.height * 1.1;
    final available = chip.right - firstPipX - _pipGap;
    final maxPips =
        available <= 0 ? 0 : (available / (_pipRadius * 2 + _pipGap)).floor();
    final pips = length.clamp(0, maxPips);
    final pip = Paint()..color = color.withValues(alpha: dim);
    for (var i = 0; i < pips; i++) {
      final x = firstPipX + i * (_pipRadius * 2 + _pipGap) + _pipRadius;
      canvas.drawCircle(Offset(x, chip.center.dy), _pipRadius, pip);
    }

    // Numeric length readout on the right.
    _drawText(
      canvas,
      '$length',
      Offset(chip.right - chip.height * 0.7, chip.center.dy),
      chip.height * 0.6,
      _white.withValues(alpha: 0.92 * dim),
      maxWidth: chip.height * 2,
    );
  }

  /// Backing track for the whole HUD column (keeps pips legible over the grid).
  static void drawHudBacking(Canvas canvas, Rect bar) {
    if (bar.width <= 1) return;
    final rr =
        RRect.fromRectAndRadius(bar.inflate(4), Radius.circular(bar.height));
    canvas.drawRRect(rr, Paint()..color = _hudTrack.withValues(alpha: 0.10));
  }

  /// A full-screen red speed-up tint. [amount] 0..1 scales the alpha so the
  /// arena visibly "heats up" as the tick accelerates.
  static void drawSpeedTint(Canvas canvas, Size size, double amount) {
    final a = amount.clamp(0.0, 1.0) * _speedTintMax;
    if (a <= 0.001) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFF3B3B).withValues(alpha: a),
    );
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  /// Head→tail gradient: bright (toward white) at the head, deeper toward tail.
  static Color _segColor(Color base, double headFraction) {
    final f = headFraction.clamp(0.0, 1.0);
    if (f >= 0.5) {
      return Color.lerp(base, _white, (f - 0.5) * 0.7) ?? base;
    }
    return Color.lerp(base, _black, (0.5 - f) * 0.5) ?? base;
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color, {
    double maxWidth = 120,
  }) {
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.right,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - maxWidth, center.dy - fontSize * 0.62),
    );
  }
}
