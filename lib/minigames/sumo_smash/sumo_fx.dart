import 'dart:math' as math;
import 'dart:ui';

import '../../core/rng.dart';
import '../../engine/helpers/push_arena.dart';

/// Round-scoped extras for [SumoSmash] kept out of the main file so it stays
/// lean (and under the line budget): the grab-a-star power pickup model + its
/// spawn/age controller, plus the pure-Canvas SUDDEN DEATH banner and star
/// drawing. Holds only its own pickup state; the game owns the wrestlers.

/// A collectible star that floats in the dohyo. Any wrestler that touches it
/// gets a brief shove buff — a swingy surprise that makes kids lunge for it.
/// Mutable round-scoped state (allowed for the duration of one round).
class StarPickup {
  /// Center in arena px.
  final Offset pos;

  /// Collision radius in arena px.
  final double radius;

  /// Spin phase for the glint (advanced each frame).
  double spin;

  /// 0 = just spawned, grows to 1 (full-size pop-in) so it eases into view.
  double appear = 0;

  StarPickup({required this.pos, required this.radius, this.spin = 0});

  /// True once the appear animation has finished easing in.
  bool get ready => appear >= 1;
}

/// Owns the single floating star and its spawn cadence so the main game file
/// only consumes it. Deterministic via the supplied [SeededRng].
class StarController {
  final double radius;
  final double firstSpawnSec;
  final double respawnSec;
  final double lifeSec;
  final double appearPerSec;
  final double spinPerSec;
  final double spawnSpreadFactor;

  StarPickup? _star;
  double _timer;

  StarController({
    required this.radius,
    required this.firstSpawnSec,
    required this.respawnSec,
    required this.lifeSec,
    required this.appearPerSec,
    required this.spinPerSec,
    required this.spawnSpreadFactor,
  }) : _timer = firstSpawnSec;

  /// The live star, or null when none is in play.
  StarPickup? get star => _star;

  /// Spawn / age the star. A star only exists while [aliveCount] >= 2 (so a solo
  /// practice round stays calm); it despawns if untouched past its life.
  void tick(double dt, int aliveCount, SeededRng rng, Offset center,
      double currentRingRadius) {
    final s = _star;
    if (s != null) {
      s.spin += dt * spinPerSec;
      if (s.appear < 1) s.appear = math.min(1.0, s.appear + dt * appearPerSec);
      _timer -= dt;
      if (_timer <= 0) {
        _star = null; // floated away untouched
        _timer = respawnSec;
      }
      return;
    }
    if (aliveCount < 2) return;
    _timer -= dt;
    if (_timer > 0) return;
    final spread = currentRingRadius * spawnSpreadFactor;
    final angle = rng.range(0, math.pi * 2);
    final pos = center +
        Offset(math.cos(angle), math.sin(angle)) * rng.range(0, spread);
    _star = StarPickup(pos: pos, radius: radius);
    _timer = lifeSec;
  }

  /// Clear the star (it was grabbed) and re-arm the respawn timer.
  void consume() {
    _star = null;
    _timer = respawnSec;
  }
}

/// Pure-Canvas drawing for the sumo extras. Side-effect free beyond the canvas;
/// guards its own inputs and never throws (safe to call from render).
class SumoFx {
  SumoFx._();

  static const Color _starCore = Color(0xFFFFE45C);
  static const Color _starEdge = Color(0xFFFFB02E);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _bannerColor = Color(0xFFFF4B3E);

  // Brace shield tuning.
  static const double _braceRingR = 1.62; // shield radius / bodyR
  static const int _braceTicks = 12; // planted-feet "bracket" ticks
  // Stun "dizzy" tuning.
  static const int _stunStars = 3; // orbiting dizzy stars
  static const double _stunOrbitR = 1.05; // orbit radius / bodyR

  /// Gently brake any alive [bodies] teetering in the last sliver before the
  /// edge while moving slowly, nudging them back toward [center]. A genuine fast
  /// charged hit (speed above [maxSpeed]) sails past, so skill still ejects —
  /// only a young player's slow drift gets saved. Mutates [Body.vel] in place
  /// (the arena owns these for one round).
  static void applyRescueAssist(
    List<Body> bodies,
    Offset center,
    double currentRingRadius, {
    required double bandFactor,
    required double maxSpeed,
    required double brakePerSec,
    required double dt,
  }) {
    if (dt <= 0) return;
    final band = currentRingRadius * bandFactor;
    for (final b in bodies) {
      final dist = (b.pos - center).distance;
      if (dist < band) continue;
      if (b.vel.distance > maxSpeed) continue; // hard launches still go
      final toCenter = center - b.pos;
      final d = toCenter.distance;
      if (d < 1e-6) continue;
      final inward = toCenter / d;
      final t = (1 - math.exp(-brakePerSec * dt)).clamp(0.0, 1.0);
      b.vel = Offset.lerp(b.vel, inward * (maxSpeed * 0.5), t) ?? b.vel;
    }
  }

  /// Draw a 5-point gold star with a soft glow ring and a rotating glint. No
  /// blur — a layered solid star reads as shiny and is cheap every frame.
  static void drawStar(Canvas canvas, StarPickup star) {
    final r = star.radius * star.appear.clamp(0.0, 1.0);
    if (r <= 0.5) return;
    final c = star.pos;

    // Soft pulsing halo (solid translucent disc, no mask filter).
    final pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(star.spin * 2.2));
    canvas.drawCircle(
      c,
      r * (1.7 + 0.2 * pulse),
      Paint()..color = _starCore.withValues(alpha: 0.16 * pulse),
    );

    final path = _starPath(c, r, r * 0.46, star.spin * 0.4);
    canvas.drawPath(
      path,
      Paint()
        ..shader = Gradient.radial(
          c.translate(-r * 0.2, -r * 0.25),
          r * 1.4,
          const [_white, _starCore, _starEdge],
          const [0.0, 0.45, 1.0],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, r * 0.12)
        ..strokeJoin = StrokeJoin.round
        ..color = _starEdge,
    );
    // A small bright sparkle that orbits the star tip.
    final glint =
        c + Offset(math.cos(star.spin), math.sin(star.spin)) * (r * 0.55);
    canvas.drawCircle(glint, r * 0.16, Paint()..color = _white);
  }

  /// Build a 5-point star path centered at [c] with [outer]/[inner] radii.
  static Path _starPath(Offset c, double outer, double inner, double rot) {
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final isOuter = i.isEven;
      final rr = isOuter ? outer : inner;
      final a = rot - math.pi / 2 + i * math.pi / points;
      final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  /// The BRACE tell: a glowing planted shield ring around a braced wrestler with
  /// short radial "anchor" ticks (feet dug in). Cool blue so it reads instantly
  /// as defense vs the warm lunge trail. Deterministic — animated only off the
  /// supplied sim clock [t]. No mask blur in the tick loop (cheap every frame).
  static void drawBraceShield(
    Canvas canvas,
    Offset center,
    double bodyR,
    Color color,
    double t,
  ) {
    if (bodyR <= 1) return;
    final pulse = 0.5 + 0.5 * math.sin(t * 7.0);
    final r = bodyR * _braceRingR;

    // Soft halo disc (single solid, no per-call mask cost).
    canvas.drawCircle(
      center,
      r * 1.12,
      Paint()..color = color.withValues(alpha: (0.10 + 0.06 * pulse).clamp(0.0, 1.0)),
    );
    // The shield ring itself — a bright stroked circle that breathes.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyR * (0.16 + 0.05 * pulse)
        ..color = color.withValues(alpha: (0.55 + 0.35 * pulse).clamp(0.0, 1.0)),
    );
    // Inner crisp hairline for a glassy double-edge.
    canvas.drawCircle(
      center,
      r * 0.9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, bodyR * 0.05)
        ..color = _white.withValues(alpha: (0.28 + 0.22 * pulse).clamp(0.0, 1.0)),
    );
    // Radial "anchor" ticks — feet dug into the clay, planted around the base.
    final tick = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, bodyR * 0.08)
      ..color = color.withValues(alpha: (0.6 + 0.3 * pulse).clamp(0.0, 1.0));
    const step = math.pi * 2 / _braceTicks;
    final inR = r * 1.02;
    final outR = r * (1.14 + 0.05 * pulse);
    for (var i = 0; i < _braceTicks; i++) {
      final a = i * step;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * inR, center + dir * outR, tick);
    }
  }

  /// The STUN read: a ring of dizzy stars orbiting above a wrestler that was
  /// repelled when it lunged into a brace. [fade] 0..1 (remaining stun fraction)
  /// dims the whole flourish as it wears off. Deterministic — orbit phase comes
  /// only from the sim clock [t]. Cheap layered circles + tiny star paths.
  static void drawStunStars(
    Canvas canvas,
    Offset center,
    double bodyR,
    double t,
    double fade,
  ) {
    final a = fade.clamp(0.0, 1.0);
    if (a <= 0.02 || bodyR <= 1) return;
    final orbit = bodyR * _stunOrbitR;
    final starR = bodyR * 0.3;
    for (var i = 0; i < _stunStars; i++) {
      final phase = t * 6.5 + i * (math.pi * 2 / _stunStars);
      // A shallow ellipse so the stars circle the head in perspective.
      final p = center + Offset(math.cos(phase) * orbit, math.sin(phase) * orbit * 0.45);
      final twinkle = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(phase * 1.7));
      final col = _starCore.withValues(alpha: (a * twinkle).clamp(0.0, 1.0));
      final path = _starPath(p, starR, starR * 0.46, phase * 0.5);
      canvas.drawPath(path, Paint()..color = col);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, starR * 0.16)
          ..strokeJoin = StrokeJoin.round
          ..color = _starEdge.withValues(alpha: (a * twinkle).clamp(0.0, 1.0)),
      );
    }
  }

  /// A bold pulsing "SUDDEN DEATH" banner across the top of the arena, shown
  /// once the ring starts collapsing fast. [pulse] 0..1 drives the throb.
  static void drawSuddenDeathBanner(
      Canvas canvas, Size size, double pulse, double t) {
    final p = pulse.clamp(0.0, 1.0);
    if (p <= 0.01) return;
    final throb = 0.78 + 0.22 * (0.5 + 0.5 * math.sin(t * 7.0));
    final y = size.height * 0.13;
    final h = size.height * 0.066;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, y),
      width: size.width * 0.86,
      height: h,
    );
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.5));
    canvas.drawRRect(
      rr,
      Paint()..color = _bannerColor.withValues(alpha: 0.22 * p * throb),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, h * 0.09)
        ..color =
            _bannerColor.withValues(alpha: (0.9 * p * throb).clamp(0.0, 1.0)),
    );
    _drawCenteredText(
      canvas,
      'SUDDEN DEATH',
      rect.center,
      _white.withValues(alpha: p),
      h * 0.5 * throb,
      size.width,
    );
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
