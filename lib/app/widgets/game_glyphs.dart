/// Per-game procedural icons. Instead of a generic colored box with a single
/// letter, every minigame gets a small, distinct, instantly-readable motif drawn
/// from primitives (no image assets): two sumo blobs colliding, a soccer goal +
/// ball, a leaning sprinter, a Simon pad grid, and so on. Used on the game-select
/// cards and the home showcase strip so the catalog reads as a set of real games
/// rather than initials.
///
/// Legibility rule: shapes drawn straight on the accent badge are WHITE or DARK;
/// the accent color is only used on top of white shapes (so nothing vanishes
/// against the same-colored background).
///
/// Performance: a single [CustomPainter] with cached [Paint] objects; the motif
/// is static (`shouldRepaint` only on id/color change) and wrapped in a
/// [RepaintBoundary].
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'glass_tokens.dart';
import 'ui_kit.dart';

/// A square, accent-tinted badge holding a game's procedural motif.
class GameGlyph extends StatelessWidget {
  const GameGlyph({
    super.key,
    required this.id,
    required this.colorArgb,
    this.label = '',
    this.size = 52,
  });

  /// Minigame id (selects the motif).
  final String id;

  /// Accent color (badge tint + motif highlights).
  final int colorArgb;

  /// Fallback label when [id] has no dedicated motif (first letter is drawn).
  final String label;

  /// Edge length of the square badge.
  final double size;

  @override
  Widget build(BuildContext context) {
    // Unknown ids fall back to the letter badge so nothing renders blank.
    if (!_GlyphPainter.has(id)) {
      return ProceduralIcon(label: label, colorArgb: colorArgb, size: size);
    }
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GlyphPainter(id, Color(colorArgb))),
      ),
    );
  }
}

/// Draws the accent badge + the per-id motif. All motif drawing happens in a
/// normalized 0..100 space (see [paint]) so each routine is resolution-free.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.id, this.accent);

  final String id;
  final Color accent;

  /// Inset of the motif inside the badge (fraction of the edge).
  static const double _pad = 0.18;

  static const Color _ink = Color(0xFFFFFFFF);
  static const Color _shadow = Color(0xFF0E0A1F);

  static const Set<String> _known = <String>{
    'sumo_smash',
    'bumper_balls',
    'one_touch_soccer',
    'tank_duel',
    'archer_pop',
    'chicken_jump',
    'falling_dodge',
    'tap_sprint',
    'tug_of_war',
    'button_masher',
    'reaction_duel',
    'snake_arena',
    'paint_splash',
    'catch_the_star',
    'color_memory',
  };

  static bool has(String id) => _known.contains(id);

  // Cached paints (no per-frame allocation).
  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBadge(canvas, size);

    final double pad = size.width * _pad;
    final double inner = size.width - pad * 2;
    canvas.save();
    canvas.translate(pad, pad);
    canvas.scale(inner / 100.0);
    switch (id) {
      case 'sumo_smash':
        _sumo(canvas);
      case 'bumper_balls':
        _bumper(canvas);
      case 'one_touch_soccer':
        _soccer(canvas);
      case 'tank_duel':
        _tank(canvas);
      case 'archer_pop':
        _archer(canvas);
      case 'chicken_jump':
        _chicken(canvas);
      case 'falling_dodge':
        _falling(canvas);
      case 'tap_sprint':
        _sprint(canvas);
      case 'tug_of_war':
        _tug(canvas);
      case 'button_masher':
        _masher(canvas);
      case 'reaction_duel':
        _reaction(canvas);
      case 'snake_arena':
        _snake(canvas);
      case 'paint_splash':
        _paint(canvas);
      case 'catch_the_star':
        _star(canvas);
      case 'color_memory':
        _memory(canvas);
    }
    canvas.restore();
  }

  /// The rounded accent badge behind every motif (matches [ProceduralIcon]).
  void _drawBadge(Canvas canvas, Size size) {
    final RRect r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(GlassTokens.radiusSmall),
    );
    _fill.shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[accent, accent.withValues(alpha: 0.55)],
    ).createShader(Offset.zero & size);
    canvas.drawRRect(r, _fill);
    _fill.shader = null;
    // Top sheen for a little depth.
    _fill.color = _ink.withValues(alpha: 0.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.42),
        const Radius.circular(GlassTokens.radiusSmall),
      ),
      _fill,
    );
  }

  // ── Paint setters ──────────────────────────────────────────────────────────

  void _setInk(double a) => _fill.color = _ink.withValues(alpha: a);
  void _setDark(double a) => _fill.color = _shadow.withValues(alpha: a);
  void _setAccent() => _fill.color = accent;
  void _inkStroke(double w, [double a = 1]) => _stroke
    ..color = _ink.withValues(alpha: a)
    ..strokeWidth = w;
  void _darkStroke(double w, [double a = 1]) => _stroke
    ..color = _shadow.withValues(alpha: a)
    ..strokeWidth = w;

  // ── Motifs (0..100 space) ──────────────────────────────────────────────────

  void _sumo(Canvas c) {
    _setInk(0.95);
    c.drawCircle(const Offset(34, 58), 20, _fill);
    c.drawCircle(const Offset(66, 58), 20, _fill);
    // Impact burst on the white overlap (dark reads on white).
    _darkStroke(5);
    for (int i = 0; i < 4; i++) {
      final double a = (i / 4) * math.pi * 2 + math.pi / 4;
      const Offset o = Offset(50, 52);
      c.drawLine(o + Offset(math.cos(a) * 5, math.sin(a) * 5),
          o + Offset(math.cos(a) * 13, math.sin(a) * 13), _stroke);
    }
  }

  void _bumper(Canvas c) {
    _inkStroke(7);
    c.drawCircle(const Offset(50, 50), 40, _stroke);
    _setInk(0.95);
    c.drawCircle(const Offset(38, 44), 12, _fill);
    _setInk(0.55);
    c.drawCircle(const Offset(64, 60), 12, _fill);
  }

  void _soccer(Canvas c) {
    // Goal frame (top).
    _inkStroke(5);
    final Path goal = Path()
      ..moveTo(24, 36)
      ..lineTo(24, 14)
      ..lineTo(76, 14)
      ..lineTo(76, 36);
    c.drawPath(goal, _stroke);
    // Ball.
    _setInk(0.95);
    c.drawCircle(const Offset(50, 66), 18, _fill);
    _setAccent();
    c.drawCircle(const Offset(50, 66), 5.5, _fill);
    for (int i = 0; i < 5; i++) {
      final double a = (i / 5) * math.pi * 2 - math.pi / 2;
      c.drawCircle(
          Offset(50 + math.cos(a) * 11, 66 + math.sin(a) * 11), 3, _fill);
    }
  }

  void _tank(Canvas c) {
    _setInk(0.95);
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTRB(20, 52, 78, 70), const Radius.circular(5)),
        _fill);
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTRB(38, 40, 60, 54), const Radius.circular(4)),
        _fill);
    _inkStroke(7);
    c.drawLine(const Offset(58, 47), const Offset(86, 47), _stroke);
    _setDark(0.85);
    for (final double x in <double>[30, 42, 54, 66]) {
      c.drawCircle(Offset(x, 70), 4.5, _fill);
    }
  }

  void _archer(Canvas c) {
    _setInk(0.95);
    c.drawCircle(const Offset(64, 34), 17, _fill);
    final Path knot = Path()
      ..moveTo(60, 49)
      ..lineTo(68, 49)
      ..lineTo(64, 55)
      ..close();
    c.drawPath(knot, _fill);
    _inkStroke(2.5);
    c.drawLine(const Offset(64, 55), const Offset(64, 70), _stroke);
    // Arrow.
    _inkStroke(5);
    c.drawLine(const Offset(8, 80), const Offset(46, 46), _stroke);
    _setInk(0.95);
    final Path head = Path()
      ..moveTo(46, 46)
      ..lineTo(39, 47)
      ..lineTo(44, 54)
      ..close();
    c.drawPath(head, _fill);
  }

  void _chicken(Canvas c) {
    // Lava teeth along the bottom (dark on accent).
    _setDark(0.9);
    final Path lava = Path()..moveTo(0, 100);
    for (int i = 0; i <= 5; i++) {
      lava.lineTo(i * 20.0, i.isEven ? 86 : 96);
    }
    lava
      ..lineTo(100, 100)
      ..close();
    c.drawPath(lava, _fill);
    // Hopping chick.
    _setInk(0.95);
    c.drawCircle(const Offset(48, 50), 16, _fill); // body
    c.drawCircle(const Offset(60, 38), 10, _fill); // head
    _setDark(0.9);
    final Path beak = Path()
      ..moveTo(69, 36)
      ..lineTo(78, 39)
      ..lineTo(69, 42)
      ..close();
    c.drawPath(beak, _fill);
    c.drawCircle(const Offset(62, 36), 2.2, _fill); // eye
  }

  void _falling(Canvas c) {
    void block(double x, double y, double s, double rot) {
      c.save();
      c.translate(x, y);
      c.rotate(rot);
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: s, height: s),
              const Radius.circular(3)),
          _fill);
      c.restore();
    }

    _setInk(0.9);
    block(34, 20, 16, 0.3);
    block(64, 30, 13, -0.4);
    block(50, 10, 11, 0.1);
    // Dodging head below.
    _setInk(0.95);
    c.drawCircle(const Offset(50, 74), 13, _fill);
    _setDark(0.9);
    c.drawCircle(const Offset(45, 72), 2.5, _fill);
    c.drawCircle(const Offset(55, 72), 2.5, _fill);
  }

  void _sprint(Canvas c) {
    _inkStroke(4, 0.7);
    c.drawLine(const Offset(6, 40), const Offset(28, 40), _stroke);
    c.drawLine(const Offset(2, 54), const Offset(24, 54), _stroke);
    c.drawLine(const Offset(8, 68), const Offset(30, 68), _stroke);
    _setInk(0.95);
    c.drawCircle(const Offset(60, 26), 9, _fill); // head
    _inkStroke(6);
    c.drawLine(const Offset(56, 34), const Offset(66, 60), _stroke); // torso
    c.drawLine(const Offset(60, 44), const Offset(78, 40), _stroke); // front arm
    c.drawLine(const Offset(60, 44), const Offset(46, 50), _stroke); // back arm
    c.drawLine(const Offset(66, 60), const Offset(80, 74), _stroke); // front leg
    c.drawLine(const Offset(66, 60), const Offset(52, 80), _stroke); // back leg
  }

  void _tug(Canvas c) {
    _inkStroke(5);
    c.drawLine(const Offset(8, 50), const Offset(92, 50), _stroke);
    // Centre flag/knot (white so it reads on the badge).
    _setInk(0.95);
    c.drawRect(const Rect.fromLTRB(47, 30, 51, 50), _fill);
    final Path flag = Path()
      ..moveTo(51, 30)
      ..lineTo(67, 35)
      ..lineTo(51, 40)
      ..close();
    c.drawPath(flag, _fill);
    // Pull arrows.
    _inkStroke(5);
    _arrow(c, const Offset(26, 50), const Offset(10, 50));
    _arrow(c, const Offset(74, 50), const Offset(90, 50));
  }

  void _masher(Canvas c) {
    _inkStroke(4, 0.7);
    for (int i = 0; i < 8; i++) {
      final double a = (i / 8) * math.pi * 2;
      const Offset o = Offset(50, 52);
      c.drawLine(o + Offset(math.cos(a) * 30, math.sin(a) * 30),
          o + Offset(math.cos(a) * 40, math.sin(a) * 40), _stroke);
    }
    _setInk(0.95);
    c.drawCircle(const Offset(50, 52), 26, _fill);
    _setAccent();
    c.drawCircle(const Offset(50, 52), 17, _fill);
    _setInk(0.9);
    c.drawCircle(const Offset(50, 52), 7, _fill);
  }

  void _reaction(Canvas c) {
    _inkStroke(4);
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTRB(36, 8, 64, 80), const Radius.circular(14)),
        _stroke);
    _setDark(0.6);
    c.drawCircle(const Offset(50, 28), 9, _fill); // off
    _setInk(0.97);
    c.drawCircle(const Offset(50, 58), 11, _fill); // GO
  }

  void _snake(Canvas c) {
    _setInk(0.95);
    const List<Offset> body = <Offset>[
      Offset(22, 70),
      Offset(40, 70),
      Offset(40, 50),
      Offset(58, 50),
      Offset(58, 32),
    ];
    for (final Offset o in body) {
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: o, width: 16, height: 16),
              const Radius.circular(4)),
          _fill);
    }
    // Apple.
    _setInk(0.9);
    c.drawCircle(const Offset(78, 24), 8, _fill);
    _setDark(0.8);
    c.drawCircle(const Offset(78, 18), 2.5, _fill); // stalk dot
  }

  void _paint(Canvas c) {
    _setInk(0.95);
    final Path blob = Path();
    const Offset ctr = Offset(48, 52);
    for (int i = 0; i <= 12; i++) {
      final double a = (i / 12) * math.pi * 2;
      final double r = 24 + (i.isEven ? 6 : -3);
      final Offset p = ctr + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        blob.moveTo(p.dx, p.dy);
      } else {
        blob.lineTo(p.dx, p.dy);
      }
    }
    blob.close();
    c.drawPath(blob, _fill);
    _setInk(0.7);
    c.drawCircle(const Offset(84, 28), 6, _fill);
    c.drawCircle(const Offset(20, 82), 4.5, _fill);
    c.drawCircle(const Offset(86, 76), 4, _fill);
  }

  void _star(Canvas c) {
    _setInk(0.95);
    c.drawPath(_starPath(const Offset(50, 48), 30, 13, 5), _fill);
    _setInk(0.7);
    c.drawCircle(const Offset(86, 22), 4, _fill);
    c.drawCircle(const Offset(16, 30), 3, _fill);
    c.drawCircle(const Offset(80, 82), 3, _fill);
  }

  void _memory(Canvas c) {
    const List<int> pal = PlayerPalette.argb;
    final List<Color> cols = <Color>[
      Color(pal[0]),
      Color(pal[1]),
      Color(pal[2]),
      Color(pal[3]),
    ];
    const double gap = 4;
    const List<Rect> quads = <Rect>[
      Rect.fromLTRB(8, 8, 50 - gap, 50 - gap),
      Rect.fromLTRB(50 + gap, 8, 92, 50 - gap),
      Rect.fromLTRB(8, 50 + gap, 50 - gap, 92),
      Rect.fromLTRB(50 + gap, 50 + gap, 92, 92),
    ];
    for (int i = 0; i < 4; i++) {
      _fill.color = cols[i];
      c.drawRRect(
          RRect.fromRectAndRadius(quads[i], const Radius.circular(6)), _fill);
    }
    _setInk(0.95);
    c.drawCircle(const Offset(50, 50), 9, _fill);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _arrow(Canvas c, Offset from, Offset to) {
    c.drawLine(from, to, _stroke);
    final double a = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const double h = 9;
    final Path head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(to.dx - math.cos(a - 0.5) * h, to.dy - math.sin(a - 0.5) * h)
      ..lineTo(to.dx - math.cos(a + 0.5) * h, to.dy - math.sin(a + 0.5) * h)
      ..close();
    _setInk(1);
    c.drawPath(head, _fill);
  }

  Path _starPath(Offset center, double outer, double inner, int points) {
    final Path p = Path();
    for (int i = 0; i < points * 2; i++) {
      final double r = i.isEven ? outer : inner;
      final double a = (i / (points * 2)) * math.pi * 2 - math.pi / 2;
      final Offset o = center + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    return p..close();
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) =>
      oldDelegate.id != id || oldDelegate.accent != accent;
}
