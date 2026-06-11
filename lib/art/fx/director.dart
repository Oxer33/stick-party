/// Cinematic "director" effects layered on top of the basic [Juice] feel:
/// a camera zoom-punch, a full-screen color flash, and a big center banner.
///
/// Pure dart:ui (no Flutter widgets) so it composes inside any MiniGame.render.
/// Each effect is decoupled and self-decaying; [Juice] owns one of each and
/// ticks them every frame. An `intensity` (0..1) lets the settings accessibility
/// slider damp the motion (shared meaning with [ScreenShake.intensity]).
library;

import 'dart:ui';

import '../../core/constants.dart';

/// A brief zoom-punch toward a focus point: snaps in fast, glides back to 1.
/// Applied in the SAME canvas transform where a game applies its shake offset,
/// so the world scales about the action without disturbing screen-space HUD.
class CameraFx {
  double _elapsed = 0;
  double _dur = 0;
  double _peak = 1;
  Offset _focus = Offset.zero;

  /// Accessibility damp, 0..1 (0 disables zoom entirely).
  double intensity;

  CameraFx({this.intensity = 1});

  /// Punch toward [focus] (in world/canvas coordinates), peaking at [scale]×.
  void punch(Offset focus, {double scale = Feel.cameraPunchScale, double? dur}) {
    if (intensity <= 0) return;
    _focus = focus;
    _peak = scale.clamp(1.0, Feel.cameraPunchMax);
    _dur = dur ?? Feel.cameraPunchSec;
    _elapsed = 0;
  }

  bool get isActive => _dur > 0 && _elapsed < _dur;

  Offset get focus => _focus;

  /// Eased scale ≥ 1. Snaps in over the first quarter, eases back out.
  double get scale {
    if (!isActive || intensity <= 0) return 1;
    final double t = (_elapsed / _dur).clamp(0.0, 1.0);
    const double inFrac = 0.22;
    final double k =
        t < inFrac ? (t / inFrac) : 1 - ((t - inFrac) / (1 - inFrac));
    return 1 + (_peak - 1) * (k * k) * intensity;
  }

  void update(double dt) {
    if (_dur > 0) _elapsed += dt;
  }

  /// Scale the canvas about the focus point. Call inside the world transform
  /// (after translating by the shake offset).
  void apply(Canvas canvas) {
    final double s = scale;
    if (s == 1) return;
    canvas
      ..translate(_focus.dx, _focus.dy)
      ..scale(s, s)
      ..translate(-_focus.dx, -_focus.dy);
  }

  void reset() {
    _elapsed = 0;
    _dur = 0;
  }
}

/// A full-screen color wash that fades out — sells a big hit, a goal, a KO.
/// Drawn in SCREEN space (after the world transform is restored).
class ScreenFlash {
  Color _color = const Color(0x00000000);
  double _elapsed = 0;
  double _dur = 0;
  double _peak = 1;

  /// Accessibility damp, 0..1.
  double intensity;

  ScreenFlash({this.intensity = 1});

  static final Paint _paint = Paint();

  /// Flash [color] for [dur] seconds; [strength] 0..1 caps peak opacity.
  void flash(Color color, {double? dur, double strength = 1}) {
    if (intensity <= 0) return;
    _color = color;
    _dur = dur ?? Feel.screenFlashSec;
    _peak = strength.clamp(0.0, 1.0);
    _elapsed = 0;
  }

  bool get isActive => _dur > 0 && _elapsed < _dur;

  void update(double dt) {
    if (_dur > 0) _elapsed += dt;
  }

  void render(Canvas canvas, Size size) {
    if (!isActive || intensity <= 0) return;
    final double t = (_elapsed / _dur).clamp(0.0, 1.0);
    final double a = (1 - t) * (1 - t) * _peak * intensity * 0.6;
    if (a <= 0.002) return;
    _paint.color = _color.withValues(alpha: (_color.a * a).clamp(0.0, 1.0));
    canvas.drawRect(Offset.zero & size, _paint);
  }

  void reset() {
    _elapsed = 0;
    _dur = 0;
  }
}

/// A big celebratory center banner ("GOAL!", "FINAL HEAVE!", "KO!"). Pops in
/// with a scale snap, holds, then fades. Screen space.
class Banner {
  String? _text;
  Color _color = const Color(0xFFFFFFFF);
  double _elapsed = 0;
  double _dur = 0;

  void show(String text,
      {Color color = const Color(0xFFFFFFFF), double? dur}) {
    _text = text;
    _color = color;
    _dur = dur ?? Feel.bannerSec;
    _elapsed = 0;
  }

  bool get isActive => _text != null && _dur > 0 && _elapsed < _dur;

  void update(double dt) {
    if (_dur <= 0) return;
    _elapsed += dt;
    if (_elapsed >= _dur) _text = null;
  }

  void render(Canvas canvas, Size size) {
    final String? text = _text;
    if (text == null || _dur <= 0) return;
    final double t = (_elapsed / _dur).clamp(0.0, 1.0);
    // Pop-in over the first 18%, hold, fade over the last 28%.
    final double pop = t < 0.18 ? (t / 0.18) : 1.0;
    final double fade = t > 0.72 ? (1 - (t - 0.72) / 0.28).clamp(0.0, 1.0) : 1.0;
    final double scale = 0.55 + 0.45 * (pop * (2 - pop)); // ease-out overshoot

    final ParagraphBuilder builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: 56,
      fontWeight: FontWeight.w900,
    ))
      ..pushStyle(TextStyle(
        color: _color.withValues(alpha: fade),
        shadows: <Shadow>[
          Shadow(
            color: const Color(0xFF000000).withValues(alpha: 0.5 * fade),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ))
      ..addText(text);
    final Paragraph paragraph = builder.build()
      ..layout(ParagraphConstraints(width: size.width));

    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.4);
    canvas.scale(scale, scale);
    canvas.drawParagraph(
        paragraph, Offset(-size.width / 2, -paragraph.height / 2));
    canvas.restore();
  }

  void reset() {
    _text = null;
    _dur = 0;
  }
}
