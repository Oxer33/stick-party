import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Pure-Canvas rendering for [ReactionDuel] — a samurai quick-draw standoff at
/// dusk. Holds NO game state and never mutates the simulation: callers pass
/// plain value snapshots. Kept in its own file so the gameplay module stays lean
/// and the drawing stays cohesive (mirrors the sumo_smash / tug_of_war split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class ReactionRenderer {
  ReactionRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _skyTop = Color(0xFF1A1030); // deep dusk violet
  static const Color _skyMid = Color(0xFF59264A); // plum band
  static const Color _skyHot = Color(0xFFC8523A); // sunset ember
  static const Color _skyHaze = Color(0xFFF2A65A); // low haze near horizon
  static const Color _sunCore = Color(0xFFFFE3A0);
  static const Color _sunEdge = Color(0xFFFF7A3C);
  static const Color _bambooDark = Color(0xFF120A1C);
  static const Color _bambooMid = Color(0xFF20122E);
  static const Color _groundTop = Color(0xFF241634);
  static const Color _groundBottom = Color(0xFF0B0712);
  static const Color _groundLine = Color(0x22FFFFFF);
  static const Color _vignette = Color(0xAA050208);
  static const Color _waitRed = Color(0xFFE23B3B);
  static const Color _waitDeep = Color(0xFF7A1414);
  static const Color _strikeGold = Color(0xFFFFF4C2);
  static const Color _strikeEdge = Color(0xFFFFC23A);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _tooSoon = Color(0xFFFF5466);

  // ── Tuning (fractions; no inline magic numbers) ────────────────────────────
  static const double _horizonFrac = 0.46; // sky/ground split height
  static const double _sunCenterFrac = 0.355; // sun height (frac of height)
  static const double _sunRadiusFrac = 0.125; // sun radius / width
  static const int _groundLineCount = 5;
  static const int _bambooCount = 9;
  static const double _bambooWidthFrac = 0.018; // stalk width / width
  static const double _vignInnerFrac = 0.46;
  static const double _vignOuterFrac = 0.78;

  // Center cue tuning.
  static const double _waitFontFrac = 0.085; // WAIT font / width
  static const double _strikeFontFrac = 0.135; // STRIKE font / width

  // Duelist marker tuning (fractions of body scale unit `u`).
  static const double _shadowWFactor = 2.6;
  static const double _shadowHFactor = 0.55;
  static const double _readoutFontU = 0.6;

  // ── Background: dusk gradient sky + sinking sun + bamboo silhouettes ────────
  static void drawBackground(Canvas canvas, Size size, double t) {
    final horizon = size.height * _horizonFrac;

    // Vertical dusk gradient: violet → plum → ember → haze at the horizon.
    final sky = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, horizon),
        const [_skyTop, _skyMid, _skyHot, _skyHaze],
        const [0.0, 0.45, 0.82, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, horizon), sky);

    _drawSun(canvas, size, horizon);
    _drawBamboo(canvas, size, horizon, t);
  }

  /// The sinking sun: a soft outer halo + a bright gradient disc resting on the
  /// haze line, anchored behind the bamboo.
  static void _drawSun(Canvas canvas, Size size, double horizon) {
    final center = Offset(size.width * 0.5, size.height * _sunCenterFrac);
    final r = size.width * _sunRadiusFrac;
    if (r <= 1) return;

    // Wide warm halo.
    canvas.drawCircle(
      center,
      r * 2.4,
      Paint()
        ..shader = Gradient.radial(
          center,
          r * 2.4,
          [
            _sunEdge.withValues(alpha: 0.34),
            const Color(0x00000000),
          ],
        ),
    );
    // Sun disc.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = Gradient.radial(
          center.translate(0, -r * 0.15),
          r,
          const [_sunCore, _sunEdge],
          const [0.0, 1.0],
        ),
    );
    // A couple of dark "atmosphere" bands across the disc for the classic
    // low-sun look.
    final band = Paint()
      ..color = _skyHot.withValues(alpha: 0.4)
      ..strokeWidth = r * 0.10
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx - r * 0.8, center.dy + r * 0.18),
        Offset(center.dx + r * 0.8, center.dy + r * 0.18), band);
    canvas.drawLine(Offset(center.dx - r * 0.6, center.dy + r * 0.5),
        Offset(center.dx + r * 0.6, center.dy + r * 0.5), band);
  }

  /// A row of bamboo stalk silhouettes swaying gently with the clock [t],
  /// fading from the horizon for depth.
  static void _drawBamboo(Canvas canvas, Size size, double horizon, double t) {
    final w = size.width * _bambooWidthFrac;
    final top = horizon - size.height * 0.34;
    for (var i = 0; i < _bambooCount; i++) {
      final f = (i + 0.5) / _bambooCount;
      final baseX = f * size.width;
      final sway = math.sin(t * 0.8 + i * 1.3) * w * 1.2;
      final far = (i.isEven) ? 0.0 : 1.0; // alternate two depth layers
      final color = Color.lerp(_bambooDark, _bambooMid, far)!
          .withValues(alpha: 0.85 - 0.25 * far);
      final stalk = Path()
        ..moveTo(baseX - w * 0.5, horizon)
        ..lineTo(baseX - w * 0.4 + sway, top)
        ..lineTo(baseX + w * 0.4 + sway, top)
        ..lineTo(baseX + w * 0.5, horizon)
        ..close();
      canvas.drawPath(stalk, Paint()..color = color);

      // Node ticks up the stalk.
      final node = Paint()
        ..color = _black.withValues(alpha: 0.35 * (1 - far))
        ..strokeWidth = w * 0.5
        ..strokeCap = StrokeCap.round;
      for (var k = 1; k <= 4; k++) {
        final ky = horizon - (horizon - top) * (k / 5);
        final kx = baseX + sway * (k / 5);
        canvas.drawLine(
            Offset(kx - w * 0.5, ky), Offset(kx + w * 0.5, ky), node);
      }
    }
  }

  /// The dueling ground: a warm-dark gradient slab with a few receding lines
  /// for perspective.
  static void drawGround(Canvas canvas, Size size) {
    final top = size.height * _horizonFrac;
    final rect = Rect.fromLTWH(0, top, size.width, size.height - top);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset(0, top),
          Offset(0, size.height),
          const [_groundTop, _groundBottom],
        ),
    );
    final line = Paint()
      ..color = _groundLine
      ..strokeWidth = 1.5;
    final span = size.height - top;
    for (var i = 1; i <= _groundLineCount; i++) {
      final fr = i / (_groundLineCount + 1);
      final y = top + span * fr * fr; // bunch toward the horizon
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// Crowd-dark vignette so the action pops (drawn over the field, under the
  /// figures). [pulse] in 0..1 tightens/reddens the frame for rising tension.
  static void drawVignette(Canvas canvas, Size size, double pulse) {
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final outer = diag * _vignOuterFrac;
    final inner = diag * _vignInnerFrac;
    final p = pulse.clamp(0.0, 1.0);
    final edge = Color.lerp(_vignette, const Color(0xCC2A0202), p) ?? _vignette;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.5),
          outer,
          [const Color(0x00000000), edge],
          [(inner / outer).clamp(0.0, 0.99), 1.0],
        ),
    );
  }

  /// Soft contact shadow ellipse beneath a duelist at ground level. [u] is the
  /// figure scale unit (≈ torso width).
  static void drawContactShadow(Canvas canvas, Offset feet, double u) {
    // A plain translucent oval grounds the figure without a per-frame blur.
    canvas.drawOval(
      Rect.fromCenter(
        center: feet,
        width: u * _shadowWFactor,
        height: u * _shadowHFactor,
      ),
      Paint()..color = _black.withValues(alpha: 0.28),
    );
  }

  /// A colored glowing footing ring under a duelist so each player's color reads
  /// in multi-player rounds. Dims when [locked] (false-started) this round. The
  /// [displayNumber] is accepted for API symmetry but kept off the field to keep
  /// the duel clean — identity reads from the player color.
  static void drawNamePlate(
    Canvas canvas,
    Offset feet,
    double u,
    Color color,
    int displayNumber, {
    required bool locked,
  }) {
    final a = locked ? 0.18 : 0.7;
    final rect = Rect.fromCenter(
      center: feet,
      width: u * (_shadowWFactor + 0.2),
      height: u * (_shadowHFactor + 0.15),
    );
    // Soft outer glow ring: a wide faint solid stroke under the crisp core ring
    // (no per-frame blur).
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(3.0, u * 0.3)
        ..color = color.withValues(alpha: a * 0.22),
    );
    // Crisp core ring.
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, u * 0.08)
        ..color = color.withValues(alpha: a),
    );
  }

  /// Per-player reaction readout above a duelist: their result this round
  /// ("WAIT" greyed, a slash-time in ms once they react, or "TOO SOON!").
  static void drawReadout(
    Canvas canvas,
    Offset above,
    double u,
    String text,
    Color color,
  ) {
    if (text.isEmpty) return;
    _drawText(canvas, text, above, u * _readoutFontU, color,
        weight: FontWeight.w800, glow: true);
  }

  /// The big central state cue, placed at [centerFrac] of the height (default
  /// high in the sky so it reads as a title card clear of the duelists).
  /// [strikeFlash] in 0..1 drives the blinding STRIKE burst (brief); [strikeWord]
  /// in 0..1 punches in then fades the "STRIKE!" word so it clears the field for
  /// the KO. When [struck] is false it draws the calm red "WAIT…" pulse;
  /// [waitPulse] in 0..1 throbs it.
  static void drawCenterCue(
    Canvas canvas,
    Size size, {
    required bool struck,
    required double strikeFlash,
    required double waitPulse,
    double strikeWord = 1.0,
    double centerFrac = 0.5,
  }) {
    final center = Offset(size.width / 2, size.height * centerFrac);
    if (!struck) {
      _drawWaitCue(canvas, size, center, waitPulse.clamp(0.0, 1.0));
    } else {
      _drawStrikeCue(canvas, size, center, strikeFlash.clamp(0.0, 1.0),
          strikeWord.clamp(0.0, 1.0));
    }
  }

  static void _drawWaitCue(
      Canvas canvas, Size size, Offset center, double pulse) {
    final r = size.width * 0.20 * (0.9 + 0.12 * pulse);
    // Soft red tension halo behind the word — a tight glowing badge.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = Gradient.radial(
          center,
          r,
          [
            _waitDeep.withValues(alpha: 0.4 + 0.16 * pulse),
            const Color(0x00000000),
          ],
        ),
    );
    // Ring that breathes with the pulse.
    canvas.drawCircle(
      center,
      size.width * 0.155 * (0.95 + 0.08 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, size.width * 0.007)
        ..color = _waitRed.withValues(alpha: 0.5 + 0.3 * pulse),
    );
    _drawText(
      canvas,
      'WAIT…',
      center,
      size.width * _waitFontFrac,
      _waitRed.withValues(alpha: 0.9 + 0.1 * pulse),
      weight: FontWeight.w900,
      glow: true,
    );
  }

  static void _drawStrikeCue(
      Canvas canvas, Size size, Offset center, double flash, double word) {
    // A tight gold burst behind the word that fades as `flash` → 0. Kept tight
    // (the full-screen blinding wash is the separate screen-flash overlay) so it
    // reads as a halo around the banner rather than washing the whole sky.
    if (flash > 0.01) {
      final r = size.width * (0.28 + 0.12 * (1 - flash));
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = Gradient.radial(
            center,
            r,
            [
              _strikeGold.withValues(alpha: 0.6 * flash),
              _strikeEdge.withValues(alpha: 0.28 * flash),
              const Color(0x00000000),
            ],
            const [0.0, 0.45, 1.0],
          ),
      );
    }
    // The word punches in big then fades out (alpha + scale from `word`) so it
    // never lingers over the KO that follows.
    if (word <= 0.01) return;
    final scale = 1.0 + 0.45 * (1 - word); // grows as it fades for a "boom" feel
    _drawText(
      canvas,
      'STRIKE!',
      center,
      size.width * _strikeFontFrac * scale,
      _strikeGold.withValues(alpha: word),
      weight: FontWeight.w900,
      glow: true,
      glowColor: _strikeEdge.withValues(alpha: word),
    );
  }

  /// A lightning slash arc sweeping from [from] toward [to] (the loser), with a
  /// bright core, soft glow and a sparkle at the tip. [strength] 0..1 fades it.
  static void drawSlashArc(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color,
    double strength,
  ) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    final delta = to - from;
    final len = delta.distance;
    if (len < 1) return;
    final n = delta / len;
    final perp = Offset(-n.dy, n.dx);
    // Bow the slash so it reads as an arc, not a straight line.
    final bow = perp * (len * 0.18);
    final mid = Offset.lerp(from, to, 0.5)! + bow;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);

    // Soft outer glow: a wide faint solid stroke under the white-hot core
    // (no per-frame blur).
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (12 + 18 * s)
        ..color = color.withValues(alpha: 0.18 * s),
    );
    // White-hot core.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (2.5 + 5 * s)
        ..color = _white.withValues(alpha: 0.9 * s),
    );
    // Tip sparkle.
    canvas.drawCircle(
        to, (4 + 5 * s), Paint()..color = _white.withValues(alpha: 0.8 * s));
  }

  /// Speed lines radiating from the slasher to sell the burst of motion.
  static void drawSpeedLines(
    Canvas canvas,
    Offset origin,
    Offset toward,
    Color color,
    double strength,
  ) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    final delta = toward - origin;
    final baseAngle = math.atan2(delta.dy, delta.dx);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.5 * s);
    const count = 6;
    for (var i = 0; i < count; i++) {
      final spread = (i - (count - 1) / 2) * 0.18;
      final a = baseAngle + spread;
      final dir = Offset(math.cos(a), math.sin(a));
      final inner = origin + dir * (18 + 10 * s);
      final outer = origin + dir * (60 + 70 * s);
      paint.strokeWidth = 2.0 + 2.0 * s;
      canvas.drawLine(inner, outer, paint);
    }
  }

  /// "TOO SOON!" stamp over a false-starter, with a thin strike-through, fading
  /// as [strength] → 0.
  static void drawTooSoon(
      Canvas canvas, Offset at, double u, double strength) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    _drawText(canvas, 'TOO SOON!', at, u * 0.7,
        _tooSoon.withValues(alpha: 0.95 * s),
        weight: FontWeight.w900, glow: true, glowColor: _tooSoon);
    final half = u * 1.6;
    canvas.drawLine(
      at.translate(-half, 0),
      at.translate(half, 0),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(2.0, u * 0.16)
        ..color = _tooSoon.withValues(alpha: 0.85 * s),
    );
  }

  /// Best-of round pips along the top: filled in each player's color for rounds
  /// they have won so far, hollow for the rest.
  static void drawRoundPips(
    Canvas canvas,
    Size size,
    int totalRounds,
    List<Color> wonColors,
  ) {
    if (totalRounds <= 0) return;
    final r = math.max(3.0, size.width * 0.012);
    final gap = r * 3.2;
    final totalW = gap * (totalRounds - 1);
    final startX = size.width / 2 - totalW / 2;
    final y = size.height * 0.085;
    for (var i = 0; i < totalRounds; i++) {
      final cx = startX + gap * i;
      final won = i < wonColors.length ? wonColors[i] : null;
      if (won != null) {
        canvas.drawCircle(Offset(cx, y), r, Paint()..color = won);
        canvas.drawCircle(
          Offset(cx, y),
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, r * 0.3)
            ..color = _white.withValues(alpha: 0.85),
        );
      } else {
        canvas.drawCircle(
          Offset(cx, y),
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, r * 0.3)
            ..color = _white.withValues(alpha: 0.4),
        );
      }
    }
  }

  /// A full-screen white screen-flash overlay. [a] in 0..1 is the opacity.
  static void drawScreenFlash(Canvas canvas, Size size, double a) {
    final v = a.clamp(0.0, 1.0);
    if (v <= 0.01) return;
    canvas.drawRect(
        Offset.zero & size, Paint()..color = _white.withValues(alpha: v));
  }

  /// Render the stick duelist itself. Kept here so the painter call lives with
  /// the rest of the visuals; [figure] owns its own pose/ragdoll state.
  static void drawDuelist(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }

  // ── Small private helpers ──────────────────────────────────────────────────

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
