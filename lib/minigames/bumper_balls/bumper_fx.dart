import 'dart:math' as math;
import 'dart:ui';

import '../../core/rng.dart';

/// Round-scoped extras for [BumperBalls] kept out of the main file so it stays
/// under the line budget: the grab-a-star power pickup model + its spawn/age
/// controller, plus the pure-Canvas neon SUDDEN DEATH banner and star drawing.
/// Holds only its own pickup state; the game owns the balls.

/// Per-player ball control + bookkeeping: player-chosen drag aim, charge while
/// held, cooldown, impact squash, stretch heading, the star buff, the active
/// trail and the rocket-dash launch window. Mutable round-scoped state (allowed
/// for one round).
class BallState {
  double aim; // current aim angle (radians) — set by the player's drag
  bool charging = false;
  bool hasDragAim = false; // true once this charge has a thumb-chosen angle
  double charge = 0; // 0..1 while held
  double _cooldown = 0; // seconds remaining until ready
  double squash = 0; // current squash amount (relaxes toward 0)
  double buff = 0; // seconds of star bump-buff remaining
  double launch = 0; // seconds of rocket-dash momentum-keep remaining
  Offset stretchDir = const Offset(1, 0); // axis the squash/stretch acts along
  DashTrail? trail;

  // ── Scored brawl ──
  double koScore = 0; // ring-outs this ball has CAUSED (the score)
  double invuln = 0; // post-respawn grace, seconds (no KO either way)
  int lastAttacker = -1; // id of the ball that last bumped this one (-1 none)
  double attackerAge = 0; // seconds since [lastAttacker] was recorded

  BallState({required this.aim});

  bool get ready => _cooldown <= 0;
  bool get buffed => buff > 0;
  bool get invulnerable => invuln > 0;

  /// True while the ball is in its rocket-dash window (keeps momentum, caroms
  /// off rivals) — drives a hotter trail/aura so the table sees the launch.
  bool get launched => launch > 0;

  /// Record [attackerId] as the most recent bumper of this ball (for KO
  /// credit). Self-hits never overwrite a real attacker.
  void markHitBy(int attackerId) {
    if (attackerId < 0) return;
    lastAttacker = attackerId;
    attackerAge = 0;
  }

  void tick(double dt, double squashDecayPerSec) {
    if (_cooldown > 0) _cooldown = math.max(0, _cooldown - dt);
    if (buff > 0) buff = math.max(0, buff - dt);
    if (launch > 0) launch = math.max(0, launch - dt);
    if (invuln > 0) invuln = math.max(0, invuln - dt);
    attackerAge += dt;
    if (squash != 0) {
      final relax = squashDecayPerSec * dt;
      squash = squash > 0
          ? math.max(0, squash - relax)
          : math.min(0, squash + relax);
    }
    if (trail != null) {
      trail!.life -= dt;
      if (trail!.life <= 0) trail = null;
    }
  }

  void fire(double cooldownSec) => _cooldown = cooldownSec;

  /// Stamp an impact squash flattening along [dir] (kept as the larger of the
  /// current and new magnitude so rapid double-hits still read).
  void bump(double amount, Offset dir) {
    if (amount.abs() > squash.abs()) {
      squash = -amount.abs(); // negative = flatten on impact
      if (dir != Offset.zero) stretchDir = dir;
    }
  }
}

/// A short-lived directional trail anchor for a dash / fast drift.
class DashTrail {
  final Offset dir;
  double life;
  final double maxLife;
  DashTrail({required this.dir, required this.life}) : maxLife = life;

  /// 0..1 trail strength (fades over its life).
  double get strength => maxLife <= 0 ? 0 : (life / maxLife).clamp(0.0, 1.0);
}

/// A knocked-off ball's VISUAL send-off: it keeps the velocity it had at the
/// moment of elimination, spins, and shrinks to nothing over [maxLife] seconds as
/// it sails off the platform — so a KO reads as a funny fling instead of an
/// instant vanish. This is purely cosmetic; the game has already marked the body
/// eliminated (alive=false, ranking recorded). Mutable round-scoped state.
class FlungBall {
  Offset pos;
  final Offset vel; // the speed it was knocked off at (kept for the arc)
  final Color color;
  final double radius;
  final int displayNumber;
  final double spinDir; // +1 / -1 so flings tumble either way
  double life;
  final double maxLife;
  double spin = 0;

  FlungBall({
    required this.pos,
    required this.vel,
    required this.color,
    required this.radius,
    required this.displayNumber,
    required this.life,
    this.spinDir = 1,
  }) : maxLife = life;

  /// 0..1 of life remaining (1 = just flung, 0 = gone) — drives scale + fade.
  double get strength => maxLife <= 0 ? 0 : (life / maxLife).clamp(0.0, 1.0);

  /// True once it has fully shrunk away and should be dropped.
  bool get done => life <= 0;

  /// Advance the fling: carry it along its velocity, tumble it, age it.
  void tick(double dt) {
    pos += vel * dt;
    spin += spinDir * dt * 14.0; // a fast comedic tumble
    life = math.max(0, life - dt);
  }
}

/// A short-lived expanding impact spark ring stamped at a collision/KO point.
class ImpactRing {
  final Offset at;
  final Color color;
  double life;
  final double maxLife;
  ImpactRing({required this.at, required this.color, required this.life})
    : maxLife = life;

  /// 0..1 animation progress (0 = just spawned, 1 = done).
  double get progress =>
      maxLife <= 0 ? 1 : (1 - life / maxLife).clamp(0.0, 1.0);
}

/// A collectible star floating on the platform. Any ball that touches it gets a
/// brief bump buff — a swingy surprise the table scrambles for. Mutable
/// round-scoped state (allowed for the duration of one round).
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

/// Owns the single floating star + its spawn cadence so the main game file just
/// consumes it. Deterministic via the supplied [SeededRng].
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
  void tick(
    double dt,
    int aliveCount,
    SeededRng rng,
    Offset center,
    double currentRingRadius,
  ) {
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
    final pos =
        center +
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

/// Pure-Canvas drawing for the bumper extras. Side-effect free beyond the
/// canvas; guards its own inputs and never throws (safe to call from render).
class BumperFx {
  BumperFx._();

  static const Color _starCore = Color(0xFFFFE45C);
  static const Color _starEdge = Color(0xFFFFB02E);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _bannerColor = Color(0xFFFF5A78);

  /// Draw a 5-point gold star with a soft glow ring + rotating glint. Layered
  /// solids only (no blur) — reads as shiny and is cheap every frame.
  static void drawStar(Canvas canvas, StarPickup star) {
    final r = star.radius * star.appear.clamp(0.0, 1.0);
    if (r <= 0.5) return;
    final c = star.pos;

    final pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(star.spin * 2.2));
    canvas.drawCircle(
      c,
      r * (1.7 + 0.2 * pulse),
      Paint()..color = _starCore.withValues(alpha: 0.18 * pulse),
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
    final glint =
        c + Offset(math.cos(star.spin), math.sin(star.spin)) * (r * 0.55);
    canvas.drawCircle(glint, r * 0.16, Paint()..color = _white);
  }

  static Path _starPath(Offset c, double outer, double inner, double rot) {
    final path = Path();
    const points = 5;
    for (var i = 0; i < points * 2; i++) {
      final rr = i.isEven ? outer : inner;
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

  /// A bold pulsing "SUDDEN DEATH" banner across the top, shown once the
  /// platform starts collapsing fast. [pulse] 0..1 drives the throb.
  static void drawSuddenDeathBanner(
    Canvas canvas,
    Size size,
    double pulse,
    double t,
  ) {
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
        ..color = _bannerColor.withValues(
          alpha: (0.9 * p * throb).clamp(0.0, 1.0),
        ),
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

  static void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    Color color,
    double fontSize,
    double maxWidth,
  ) {
    if (fontSize <= 1) return;
    final builder =
        ParagraphBuilder(
            ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
            ),
          )
          ..pushStyle(TextStyle(color: color))
          ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - maxWidth / 2, center.dy - fontSize * 0.62),
    );
  }
}
