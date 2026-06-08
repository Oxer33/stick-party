import 'dart:math' as math;
import 'dart:ui';

/// Round-scoped extras for [ArcherPop] kept out of the main file so it stays
/// under the line budget: the pure-Canvas FRENZY banner shown in the final
/// stretch when balloons rush faster and more golden. Holds no game state.
class ArcherFx {
  ArcherFx._();

  static const Color _bannerColor = Color(0xFFFFB02E);
  static const Color _white = Color(0xFFFFFFFF);

  /// A bold pulsing "FRENZY!" banner across the top of the field, shown once the
  /// balloon rush ramps up. [pulse] 0..1 drives the throb.
  static void drawFrenzyBanner(
      Canvas canvas, Size size, double pulse, double t) {
    final p = pulse.clamp(0.0, 1.0);
    if (p <= 0.01) return;
    final throb = 0.78 + 0.22 * (0.5 + 0.5 * math.sin(t * 7.5));
    final y = size.height * 0.2;
    final h = size.height * 0.06;
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, y), width: size.width * 0.7, height: h);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.5));
    canvas.drawRRect(
        rr, Paint()..color = _bannerColor.withValues(alpha: 0.22 * p * throb));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, h * 0.1)
        ..color =
            _bannerColor.withValues(alpha: (0.92 * p * throb).clamp(0.0, 1.0)),
    );
    _drawCenteredText(canvas, 'FRENZY!', rect.center,
        _white.withValues(alpha: p), h * 0.56 * throb, size.width);
  }

  static void _drawCenteredText(Canvas canvas, String text, Offset center,
      Color color, double fontSize, double maxWidth) {
    if (fontSize <= 1) return;
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph,
        Offset(center.dx - maxWidth / 2, center.dy - fontSize * 0.62));
  }
}
