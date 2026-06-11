import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../core/rng.dart';

/// Round-scoped extras for [TankDuel] kept out of the main file so it stays
/// under the line budget: a shoot-it AIRDROP crate pickup + its spawn controller,
/// plus the pure-Canvas FRENZY banner and airdrop drawing. Holds only its own
/// pickup state; the game owns the tanks and shells.

/// A floating supply crate any tank can shoot. Whoever pops it gets a brief
/// OVERCHARGE buff (heavier, double-damage shells) — a swingy surprise. Mutable
/// round-scoped state.
class AirdropCrate {
  /// Center in arena px.
  final Offset pos;

  /// Half-size (a square crate) in arena px.
  final double half;

  /// Bob phase for the gentle hover (advanced each frame).
  double bob;

  /// 0 = just dropped, eases to 1 (drop-in scale).
  double appear = 0;

  AirdropCrate({required this.pos, required this.half, this.bob = 0});

  /// True once the drop-in finished (only then can it be shot).
  bool get ready => appear >= 1;

  /// Axis-aligned hit rect at the current scale.
  Rect get rect {
    final h = half * appear.clamp(0.0, 1.0);
    return Rect.fromCenter(center: pos, width: h * 2, height: h * 2);
  }
}

/// Owns the single airdrop crate + its drop cadence so the game just consumes
/// it. Deterministic via the supplied [SeededRng]; drops land inside [field].
class AirdropController {
  final double half;
  final double firstDropSec;
  final double respawnSec;
  final double lifeSec;
  final double appearPerSec;
  final double bobPerSec;

  AirdropCrate? _crate;
  double _timer;

  AirdropController({
    required this.half,
    required this.firstDropSec,
    required this.respawnSec,
    required this.lifeSec,
    required this.appearPerSec,
    required this.bobPerSec,
  }) : _timer = firstDropSec;

  /// The live crate, or null when none is in play.
  AirdropCrate? get crate => _crate;

  /// Spawn / age the crate. It despawns if nobody pops it within its life. Drops
  /// land in the central band of [field] so they sit in contested midfield.
  void tick(double dt, SeededRng rng, Rect field) {
    final c = _crate;
    if (c != null) {
      c.bob += dt * bobPerSec;
      if (c.appear < 1) c.appear = math.min(1.0, c.appear + dt * appearPerSec);
      _timer -= dt;
      if (_timer <= 0) {
        _crate = null; // floated/never shot; re-arm
        _timer = respawnSec;
      }
      return;
    }
    _timer -= dt;
    if (_timer > 0) return;
    final x = rng.range(
        field.left + field.width * 0.2, field.right - field.width * 0.2);
    final y = rng.range(
        field.top + field.height * 0.32, field.bottom - field.height * 0.32);
    _crate = AirdropCrate(pos: Offset(x, y), half: half);
    _timer = lifeSec;
  }

  /// True when [point] is inside a ready crate (a shell hit). Does not consume.
  bool contains(Offset point) {
    final c = _crate;
    return c != null && c.ready && c.rect.contains(point);
  }

  /// Clear the crate (it was popped) and re-arm the drop timer.
  void consume() {
    _crate = null;
    _timer = respawnSec;
  }
}

/// Pure-Canvas drawing for the tank extras. Side-effect free beyond the canvas;
/// guards its own inputs and never throws (safe to call from render).
class TankFx {
  TankFx._();

  static const Color _crateBody = Color(0xFF8FD64A);
  static const Color _crateEdge = Color(0xFF3F7A1E);
  static const Color _crateStripe = Color(0xFFFFE45C);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _bannerColor = Color(0xFFFF7A2E);

  /// Draw the airdrop: a hovering crate with a hazard cross + a soft pulsing
  /// halo so it reads as "shoot me for a power-up". Solid fills only.
  static void drawAirdrop(Canvas canvas, AirdropCrate crate) {
    final h = crate.half * crate.appear.clamp(0.0, 1.0);
    if (h <= 0.5) return;
    final hover = math.sin(crate.bob) * h * 0.12;
    final c = crate.pos.translate(0, hover);
    final pulse = 0.5 + 0.5 * math.sin(crate.bob * 1.6);

    canvas.drawCircle(
      c,
      h * (1.5 + 0.2 * pulse),
      Paint()..color = _crateStripe.withValues(alpha: 0.14 + 0.1 * pulse),
    );

    final rect = Rect.fromCenter(center: c, width: h * 2, height: h * 2);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.18));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [_brighten(_crateBody, 0.25), _crateBody],
        ),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, h * 0.16)
        ..color = _crateEdge,
    );
    // Yellow hazard cross — the "supply" read.
    final stripe = Paint()
      ..strokeWidth = math.max(1.5, h * 0.22)
      ..strokeCap = StrokeCap.round
      ..color = _crateStripe;
    canvas.drawLine(
        Offset(c.dx - h * 0.55, c.dy), Offset(c.dx + h * 0.55, c.dy), stripe);
    canvas.drawLine(
        Offset(c.dx, c.dy - h * 0.55), Offset(c.dx, c.dy + h * 0.55), stripe);
  }

  /// A bold pulsing "FRENZY!" banner across the top in the final stretch.
  /// [pulse] 0..1 drives the throb.
  static void drawFrenzyBanner(
      Canvas canvas, Size size, double pulse, double t) {
    final p = pulse.clamp(0.0, 1.0);
    if (p <= 0.01) return;
    final throb = 0.78 + 0.22 * (0.5 + 0.5 * math.sin(t * 8.0));
    final y = size.height * 0.12;
    final h = size.height * 0.062;
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

  static const Color _explosionTint = Color(0xFFFFE6A0);

  /// Impact explosion: a hot two-tone particle burst + shake + hit-stop. [heavy]
  /// is a tank hit (bigger); else a crate shatter / airdrop pop. Pure feedback.
  ///
  /// Set [jolt] false to draw only the particle burst and leave the screen-jolt
  /// (shake + hit-stop) to the caller — used on a downing / KO hit where
  /// [Juice.bigMoment] / [Juice.ko] already own a heavier shake + hit-stop, so
  /// firing explode's jolt too would double the screen-shake on one event.
  static void explode(Juice juice, Offset at, Color color,
      {required bool heavy, bool jolt = true}) {
    juice.particles.burst(
      at: at,
      count: heavy ? 20 : 12,
      color: color,
      speed: heavy ? 360 : 260,
      spread: math.pi * 2,
      size: heavy ? 8 : 6,
      gravity: 520,
      life: heavy ? 0.7 : 0.5,
    );
    juice.particles.burst(
      at: at,
      count: heavy ? 12 : 7,
      color: _explosionTint,
      speed: heavy ? 300 : 220,
      spread: math.pi * 2,
      size: heavy ? 6 : 4,
      gravity: 400,
      life: 0.4,
    );
    if (!jolt) return;
    if (heavy) {
      juice.shake.heavy();
      juice.hitStop.trigger(0.1, scale: 0.1);
    } else {
      juice.shake.medium();
      juice.hitStop.trigger(0.05);
    }
  }

  /// Probe [candidates] launch angles across [lo]..[hi]; return the one whose
  /// simulated gravity arc from [muzzle] passes closest to any of [targets], or
  /// null when the best arc never grazes within [reach]. Cheap, bounded, never
  /// throws — used by the bot to lead its shot. Pure (no game state).
  static double? bestLaunchAngle({
    required double lo,
    required double hi,
    required Offset muzzle,
    required List<Offset> targets,
    required double shellSpeed,
    required double gravity,
    required int candidates,
    required int steps,
    required double arcDt,
    required double reach,
    required Size bounds,
    required double outPad,
  }) {
    if (targets.isEmpty) return null;
    double? bestAngle;
    var bestMiss = double.infinity;
    for (var i = 0; i < candidates; i++) {
      final f = candidates == 1 ? 0.5 : i / (candidates - 1);
      final angle = lo + (hi - lo) * f;
      final miss = _arcClosestMiss(
          muzzle, angle, targets, shellSpeed, gravity, steps, arcDt, bounds,
          outPad);
      if (miss < bestMiss) {
        bestMiss = miss;
        bestAngle = angle;
      }
    }
    return (bestAngle != null && bestMiss <= reach) ? bestAngle : null;
  }

  static double _arcClosestMiss(
      Offset muzzle,
      double angle,
      List<Offset> targets,
      double shellSpeed,
      double gravity,
      int steps,
      double arcDt,
      Size bounds,
      double outPad) {
    var pos = muzzle;
    var vel = Offset(math.cos(angle), math.sin(angle)) * shellSpeed;
    var best = double.infinity;
    for (var step = 0; step < steps; step++) {
      vel = vel + Offset(0, gravity * arcDt);
      pos = pos + vel * arcDt;
      if (pos.dx < -outPad ||
          pos.dy < -outPad ||
          pos.dx > bounds.width + outPad ||
          pos.dy > bounds.height + outPad) {
        break;
      }
      for (final t in targets) {
        final d = (t - pos).distance;
        if (d < best) best = d;
      }
    }
    return best;
  }

  static Color _brighten(Color a, double t) =>
      Color.lerp(a, _white, t.clamp(0.0, 1.0)) ?? a;

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
