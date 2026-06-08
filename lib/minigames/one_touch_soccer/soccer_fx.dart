import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../core/rng.dart';

/// Round-scoped extras for [OneTouchSoccer] kept out of the main file so it
/// stays under the line budget: a mid-field SPEED PAD pickup model + its
/// spawn/age controller, plus the pure-Canvas DOUBLE GOALS banner and pad
/// drawing. Holds only its own pickup state; the game owns the ball.

/// A glowing pad on the pitch. When the ball rolls over it the ball gets a brief
/// speed kick (and the pad re-arms), so a stray ball can suddenly rocket toward
/// a goal — a swingy surprise. Mutable round-scoped state.
class SpeedPad {
  /// Center in arena px.
  final Offset pos;

  /// Trigger radius in arena px.
  final double radius;

  /// Spin/pulse phase advanced each frame.
  double phase;

  /// 0 = just spawned, eases to 1 (full-size pop-in).
  double appear = 0;

  SpeedPad({required this.pos, required this.radius, this.phase = 0});

  /// True once the appear animation has eased in (only then can it trigger).
  bool get ready => appear >= 1;
}

/// Owns the single speed pad and its spawn cadence so the game just consumes it.
/// Deterministic via the supplied [SeededRng]; pads spawn inside [field].
class SpeedPadController {
  final double radius;
  final double firstSpawnSec;
  final double respawnSec;
  final double lifeSec;
  final double appearPerSec;
  final double phasePerSec;

  SpeedPad? _pad;
  double _timer;

  SpeedPadController({
    required this.radius,
    required this.firstSpawnSec,
    required this.respawnSec,
    required this.lifeSec,
    required this.appearPerSec,
    required this.phasePerSec,
  }) : _timer = firstSpawnSec;

  /// The live pad, or null when none is in play.
  SpeedPad? get pad => _pad;

  /// Spawn / age the pad. It despawns if the ball never rolls over it within its
  /// life. [field] is the inner pitch rect; pads spawn in its central band so
  /// they sit in contested midfield, never inside a goal mouth.
  void tick(double dt, SeededRng rng, Rect field) {
    final p = _pad;
    if (p != null) {
      p.phase += dt * phasePerSec;
      if (p.appear < 1) p.appear = math.min(1.0, p.appear + dt * appearPerSec);
      _timer -= dt;
      if (_timer <= 0) {
        _pad = null; // unused; re-arm
        _timer = respawnSec;
      }
      return;
    }
    _timer -= dt;
    if (_timer > 0) return;
    // Central band: avoid the top/bottom thirds so the pad sits in midfield.
    final x = rng.range(
        field.left + field.width * 0.18, field.right - field.width * 0.18);
    final y = rng.range(
        field.top + field.height * 0.34, field.bottom - field.height * 0.34);
    _pad = SpeedPad(pos: Offset(x, y), radius: radius);
    _timer = lifeSec;
  }

  /// Clear the pad (the ball triggered it) and re-arm the respawn timer.
  void consume() {
    _pad = null;
    _timer = respawnSec;
  }

  /// If a ready pad overlaps the ball at [ballPos] (within [ballRadius]), consume
  /// it and return the unit boost direction: the way the ball already travels, or
  /// toward the nearer goal line when nearly still (so it never stalls). Returns
  /// null when there is nothing to trigger.
  Offset? tryTrigger({
    required Offset ballPos,
    required Offset ballVel,
    required double ballRadius,
    required double minBallSpeed,
    required double topLine,
    required double bottomLine,
  }) {
    final p = _pad;
    if (p == null || !p.ready) return null;
    if ((ballPos - p.pos).distance > p.radius + ballRadius) return null;
    final speed = ballVel.distance;
    final Offset dir;
    if (speed >= minBallSpeed) {
      dir = ballVel / speed;
    } else {
      final toTop = (ballPos.dy - topLine).abs();
      final toBottom = (bottomLine - ballPos.dy).abs();
      dir = Offset(0, toTop <= toBottom ? -1 : 1);
    }
    consume();
    return dir;
  }
}

/// Pure helpers + drawing for the soccer extras. Side-effect free; guards its
/// own inputs and never throws.
class SoccerFx {
  SoccerFx._();

  /// Center of the goal a player attacks (where contact should drive the ball).
  /// [attacksTop] true → the TOP goal line, else the BOTTOM goal line.
  static Offset opponentGoalTarget(
      bool attacksTop, Offset goalMouthCenter, double topLine, double bottomLine) {
    final y = attacksTop ? topLine : bottomLine;
    return Offset(goalMouthCenter.dx, y);
  }

  /// Keeper heading: ease toward a guard slot in front of its own goal, tracking
  /// the ball's horizontal position so it covers shots. Returns [Offset.zero]
  /// (hold) when already in position. Own goal is the BOTTOM when [attacksTop].
  static Offset guardHeading({
    required bool attacksTop,
    required Offset selfPos,
    required Offset ballPos,
    required Rect pitch,
    required double playerRadius,
    required double depthFactor,
    required double laneGain,
  }) {
    final guardY = attacksTop
        ? pitch.bottom - pitch.height * depthFactor
        : pitch.top + pitch.height * depthFactor;
    final targetX = pitch.center.dx + (ballPos.dx - pitch.center.dx) * laneGain;
    final target = Offset(targetX, guardY);
    final to = target - selfPos;
    final d = to.distance;
    if (d < playerRadius * 0.8) return Offset.zero; // in position: hold
    return (to / d) * 0.85;
  }

  /// True when [playerId] is the rear-most (deepest in its own half) of its side
  /// and therefore keeps net. A lone player on a side never keeps net (they must
  /// attack to ever score). [sideDepth] maps a teammate id to its depth toward
  /// its own goal (bigger = deeper).
  static bool isKeeper(
      int playerId, Iterable<int> mates, double Function(int) sideDepth) {
    final list = mates.toList(growable: false);
    if (list.length < 2) return false;
    var rear = list.first;
    var rearDepth = double.negativeInfinity;
    for (final id in list) {
      final depth = sideDepth(id);
      if (depth > rearDepth) {
        rearDepth = depth;
        rear = id;
      }
    }
    return rear == playerId;
  }

  static const Color _padCore = Color(0xFF6BE0FF);
  static const Color _padEdge = Color(0xFF2A8CFF);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _bannerColor = Color(0xFFFFC93C);

  /// Draw the speed pad: a pulsing ringed disc with twin chevrons, all solid
  /// fills (no blur) so it reads as "zoom here" and stays cheap each frame.
  static void drawSpeedPad(Canvas canvas, SpeedPad pad) {
    final r = pad.radius * pad.appear.clamp(0.0, 1.0);
    if (r <= 0.5) return;
    final c = pad.pos;
    final pulse = 0.5 + 0.5 * math.sin(pad.phase * 3.0);

    canvas.drawCircle(
      c,
      r * (1.0 + 0.18 * pulse),
      Paint()..color = _padCore.withValues(alpha: 0.16 + 0.12 * pulse),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.14)
        ..color = _padEdge.withValues(alpha: 0.9),
    );
    // Twin upward chevrons that bob with the pulse — the "speed" read.
    final lift = r * (0.18 + 0.12 * pulse);
    for (var i = 0; i < 2; i++) {
      final cy = c.dy + r * 0.32 - i * r * 0.42 - lift;
      final w = r * 0.5;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.16)
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = _white.withValues(alpha: 0.75 + 0.2 * pulse);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - w, cy + r * 0.18)
          ..lineTo(c.dx, cy - r * 0.18)
          ..lineTo(c.dx + w, cy + r * 0.18),
        paint,
      );
    }
  }

  static const Color _kickSpark = Color(0xFFFFFFFF);
  static const Color _thwack = Color(0xFFFFE08A);
  static const Color _kickDust = Color(0xFFDFF3E4);

  /// React to a ball strike: spark + hit-stop + a THWACK! pop on the hardest
  /// strikes, plus light dust at the striker's feet ([feet]). Returns the squash
  /// amount (0..1) to stamp on the ball. Pure feedback (no sim mutation).
  static double fireKickFeedback(
    Juice juice, {
    required Offset ballPos,
    required double ballSpeed,
    required double ballRadius,
    required Offset feet,
    required double hardKickSpeed,
  }) {
    final squash = (0.6 + (ballSpeed / hardKickSpeed) * 0.4).clamp(0.0, 1.0);
    if (ballSpeed >= hardKickSpeed) {
      juice.hit(ballPos, _kickSpark, sparks: 10);
      juice.shake.light();
      juice.popup(ballPos.translate(0, -ballRadius * 2.4), 'THWACK!', _thwack,
          size: ballRadius * 1.8);
    } else {
      juice.particles.burst(
          at: ballPos, count: 5, color: _kickSpark, speed: 180, size: 4,
          life: 0.28);
    }
    juice.particles.burst(
        at: feet, count: 5, color: _kickDust, speed: 120, size: 4,
        gravity: 220, life: 0.3);
    return squash;
  }

  /// Fire the speed-pad pickup juice: a forward spark fan + light shake + a
  /// SPEED! popup, in the boost [dir]. Pure feedback (no sim mutation).
  static void fireSpeedBurst(
      Juice juice, SpeedPad pad, Offset dir, double ballRadius) {
    juice.particles.burst(
      at: pad.pos,
      count: 14,
      color: _padCore,
      speed: 320,
      baseAngle: math.atan2(dir.dy, dir.dx),
      spread: math.pi * 0.5,
      size: 5,
      gravity: 80,
      life: 0.4,
    );
    juice.shake.light();
    juice.popup(pad.pos.translate(0, -pad.radius * 1.6), 'SPEED!', _padCore,
        size: ballRadius * 1.8);
  }

  /// A bold pulsing "DOUBLE GOALS!" banner across the pitch in the final
  /// stretch. [pulse] 0..1 drives the throb.
  static void drawDoubleGoalsBanner(
      Canvas canvas, Size size, double pulse, double t) {
    final p = pulse.clamp(0.0, 1.0);
    if (p <= 0.01) return;
    final throb = 0.78 + 0.22 * (0.5 + 0.5 * math.sin(t * 6.5));
    final y = size.height * 0.5;
    final h = size.height * 0.05;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, y),
      width: size.width * 0.7,
      height: h,
    );
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.5));
    canvas.drawRRect(
      rr,
      Paint()..color = _bannerColor.withValues(alpha: 0.2 * p * throb),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, h * 0.1)
        ..color =
            _bannerColor.withValues(alpha: (0.92 * p * throb).clamp(0.0, 1.0)),
    );
    _drawCenteredText(canvas, 'DOUBLE GOALS!', rect.center,
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
