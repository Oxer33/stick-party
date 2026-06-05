import 'dart:math' as math;
import 'dart:ui';

import '../../core/constants.dart';
import '../../core/rng.dart';
import 'particles.dart';

/// Stacking camera-shake pulses with ease-out decay. Per-axis randomization.
class ScreenShake {
  final List<_ShakePulse> _pulses = <_ShakePulse>[];
  final SeededRng _rng;
  double intensity; // accessibility scale 0..1

  ScreenShake({SeededRng? rng, this.intensity = 1}) : _rng = rng ?? SeededRng();

  void shake(double duration, double magnitude) {
    if (duration <= 0 || magnitude <= 0) return;
    _pulses.add(_ShakePulse(duration, magnitude));
  }

  void light() => shake(0.15, 3);
  void medium() => shake(0.25, 4.5);
  void heavy() => shake(0.4, Feel.maxShakePx);

  bool get isActive => _pulses.isNotEmpty;

  void update(double dt) {
    for (final p in _pulses) {
      p.elapsed += dt;
    }
    _pulses.removeWhere((p) => p.elapsed >= p.duration);
  }

  Offset get offset {
    if (_pulses.isEmpty || intensity <= 0) return Offset.zero;
    var amp = 0.0;
    for (final p in _pulses) {
      final k = 1 - (p.elapsed / p.duration).clamp(0.0, 1.0);
      amp = math.max(amp, p.magnitude * k * k);
    }
    amp = math.min(amp * intensity, Feel.maxShakePx);
    return Offset(_rng.jitter(amp), _rng.jitter(amp));
  }

  void reset() => _pulses.clear();
}

class _ShakePulse {
  final double duration;
  final double magnitude;
  double elapsed = 0;
  _ShakePulse(this.duration, this.magnitude);
}

/// Brief time-scale dip to sell impact. Caller multiplies its sim dt by
/// [timeScale].
class HitStop {
  double _remaining = 0;
  double _duration = 0;
  double _scale = 1;

  void trigger(double duration, {double scale = 0.05}) {
    if (duration <= _remaining) return;
    _remaining = duration;
    _duration = duration;
    _scale = scale.clamp(0.0, 1.0);
  }

  bool get isActive => _remaining > 0;
  double get timeScale => _remaining > 0 ? _scale : 1.0;

  void update(double dt) {
    if (_remaining > 0) _remaining = (_remaining - dt).clamp(0.0, _duration);
  }
}

/// A floating "+1" / "KO!" / "WIN!" popup. Rises and fades.
class ScorePopup {
  Offset pos;
  final String text;
  final Color color;
  final double size;
  double life;
  final double maxLife;

  ScorePopup({
    required this.pos,
    required this.text,
    required this.color,
    this.size = 28,
    this.life = Feel.scorePopupRiseSec,
  }) : maxLife = life;

  bool get dead => life <= 0;
}

/// One-stop game-feel facade: particles + shake + hit-stop + score popups.
/// Pure dart:ui (no Flutter widgets) so it works inside any MiniGame.render.
class Juice {
  final ParticleSystem particles;
  final ScreenShake shake;
  final HitStop hitStop;
  final List<ScorePopup> _popups = <ScorePopup>[];

  Juice({SeededRng? rng})
      : particles = ParticleSystem(rng),
        shake = ScreenShake(rng: rng),
        hitStop = HitStop();

  /// Standard hit: sparks + light shake + tiny hit-stop.
  void hit(Offset at, Color color, {int sparks = 8}) {
    particles.burst(at: at, count: sparks, color: color, speed: 240);
    shake.light();
    hitStop.trigger(Feel.hitStopDefaultSec);
  }

  /// KO: big burst + heavy shake + longer hit-stop + popup.
  void ko(Offset at, Color color) {
    particles.burst(
        at: at, count: 22, color: color, speed: 360, size: 8, life: 0.8);
    shake.heavy();
    hitStop.trigger(Feel.hitStopHeavySec, scale: 0.08);
    popup(at, 'KO!', color, size: 40);
  }

  void popup(Offset at, String text, Color color, {double size = 28}) {
    _popups.add(ScorePopup(pos: at, text: text, color: color, size: size));
  }

  void confetti(Size area, {List<Color> colors = const []}) =>
      particles.confetti(area, colors: colors);

  void update(double dt) {
    particles.update(dt);
    shake.update(dt);
    hitStop.update(dt);
    for (final p in _popups) {
      p.life -= dt;
      p.pos = Offset(p.pos.dx, p.pos.dy - 60 * dt);
    }
    _popups.removeWhere((p) => p.dead);
  }

  void render(Canvas canvas) {
    particles.render(canvas);
    for (final p in _popups) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      _drawText(canvas, p.text, p.pos, p.color.withValues(alpha: a), p.size);
    }
  }

  void _drawText(Canvas canvas, String text, Offset center, Color color,
      double fontSize) {
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(const ParagraphConstraints(width: 240));
    canvas.drawParagraph(
        paragraph, Offset(center.dx - 120, center.dy - fontSize));
  }

  void clear() {
    particles.clear();
    shake.reset();
    _popups.clear();
  }
}
