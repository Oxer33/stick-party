import 'dart:math' as math;
import 'dart:ui';

import '../../core/rng.dart';

/// Round-scoped extras for [BumperBalls] kept out of the main file so it stays
/// under the line budget: the slingshot-aim ball state, the static peg model,
/// the grab-a-star power pickup model + its spawn/age controller, plus the
/// pure-Canvas neon SUDDEN DEATH banner, peg and star drawing. Holds only its
/// own pickup/peg state; the game owns the balls.

/// Per-player SLINGSHOT control + bookkeeping. The player DRAGS BACKWARD from
/// the ball (pool / Angry-Birds style): the live pull vector is captured here,
/// the launch fires OPPOSITE the pull with power proportional to the (clamped)
/// pull distance, and a tiny pull goes nowhere. No invisible charge meter and no
/// commit gate — power is the VISIBLE pull distance, so a blind tap is honestly
/// feeble while a judged, long pull rockets across the platform.
///
/// Also tracks impact squash, stretch heading, the star buff, the active trail
/// and the rocket-keep launch window. Mutable round-scoped state (one round).
class BallState {
  double aim; // launch heading (radians) — OPPOSITE the live pull; for the HUD
  Offset downPos = Offset.zero; // press point (screen px)
  Offset dragPos = Offset.zero; // current finger point while pulling (screen px)
  // Normalized (0..1) FULL-SCREEN press point captured at InputPhase.down. The
  // zone-relative aim helper anchors the pull to THIS, not the avatar, so a
  // top-seat (rotated) player drags INTO the arena, not back at their own rim.
  Offset pressNorm = Offset.zero;
  // Finger-anchored, rotation-corrected pull-back vector (screen px from the
  // ball) for the visible slingshot band — derived from the zone aim, so the
  // telegraph matches where the launch will actually fire.
  Offset pullBackVec = Offset.zero;
  bool aiming = false; // true while the finger is down building a pull
  bool hasPull = false; // true once the pull has cleared the dead-zone
  double pullFrac = 0; // 0..1 pull distance as a share of the max pull
  double _cooldown = 0; // seconds remaining until ready to slingshot again
  double squash = 0; // current squash amount (relaxes toward 0)
  double buff = 0; // seconds of star launch-buff remaining
  double launch = 0; // seconds of rocket momentum-keep remaining
  Offset stretchDir = const Offset(1, 0); // axis the squash/stretch acts along
  DashTrail? trail;

  // ── Scored brawl ──
  double koScore = 0; // ring-outs this ball has CAUSED (the score)
  double invuln = 0; // post-respawn grace, seconds (no KO either way)
  int lastAttacker = -1; // id of the ball that last bumped this one (-1 none)
  double attackerAge = 0; // seconds since [lastAttacker] was recorded
  // ── Launch power (read at contact for the eject-knockback scaling) ──
  // The pull fraction (0..1) of this ball's most recent slingshot, decaying over
  // a short window. Read at contact time so a launched ball delivers an eject
  // proportional to how hard it was SLUNG — a feeble pull can nudge but not
  // launch a rival off the rim, a committed pull banks ring-outs.
  double launchPower = 0;
  double _launchPowerAge = 0;

  BallState({required this.aim});

  bool get ready => _cooldown <= 0;
  bool get buffed => buff > 0;
  bool get invulnerable => invuln > 0;

  /// Window (seconds) over which [launchPower] stays meaningful after a launch —
  /// long enough that a committed rocket still counts when it CONNECTS (the body
  /// usually crosses the gap within this window while it keeps momentum), but
  /// short enough that a body kept fast only by a later carom is treated as
  /// incidental, not an aimed launch.
  static const double _launchPowerWindow = 0.7;

  /// The freshness-weighted launch power of the last slingshot (0..1). Fades to
  /// 0 over [_launchPowerWindow] so only a ball actively mid-launch counts.
  double get committedPower {
    if (_launchPowerAge >= _launchPowerWindow) return 0;
    final f = 1.0 - (_launchPowerAge / _launchPowerWindow);
    return (launchPower * f).clamp(0.0, 1.0);
  }

  /// Record the power of a just-fired slingshot so contact knockback can tell a
  /// committed launch from an incidental bump.
  void markLaunch(double power) {
    launchPower = power.clamp(0.0, 1.0);
    _launchPowerAge = 0;
  }

  /// True while the ball is in its rocket window (keeps momentum, caroms off
  /// rivals + pegs) — drives a hotter trail/aura so the table sees the launch.
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
    _launchPowerAge += dt;
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

/// A fixed circular BUMPER PEG on the platform. Balls carom elastically off it
/// for bank shots; it never moves and is never eliminated. The engine's
/// [PushArena] has no immovable bodies, so the game resolves ball-peg contacts
/// locally and stamps a [flash] here for the render flash. Mutable round-scoped
/// state (only the cosmetic flash changes).
class Peg {
  /// Center in arena px.
  final Offset pos;

  /// Collision radius in arena px.
  final double radius;

  /// 0..1 hit flash, stamped to 1 on impact and relaxing each frame (visual).
  double flash = 0;

  Peg({required this.pos, required this.radius});

  /// Brighten the hit flash (stamped to full so a fresh impact always reads).
  void hit() => flash = 1.0;

  /// Relax the flash toward 0 at [perSec] per second (frame-rate independent).
  void tick(double dt, double perSec) {
    if (flash > 0) flash = math.max(0, flash - perSec * dt);
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
  static const Color _pegCore = Color(0xFFB388FF); // neon-violet bumper face
  static const Color _pegEdge = Color(0xFF6A3CE0); // deeper rim of the peg
  static const Color _pegHot = Color(0xFFE0D2FF); // hit-flash bloom

  /// Draw a glossy neon bumper PEG: a soft aura (pulsing with the sim clock and
  /// brightening on a recent hit), a top-lit domed core, a bright rim and a
  /// specular blob. On impact [peg.flash] climbs to 1 and the whole peg flares +
  /// throws a quick shock ring. Layered solids + a single arc — cheap, no blur,
  /// deterministic off [t]. Safe from render (guards its own inputs, no throw).
  static void drawPeg(Canvas canvas, Peg peg, double t) {
    final r = peg.radius;
    if (r <= 0.5) return;
    final c = peg.pos;
    final f = peg.flash.clamp(0.0, 1.0);
    final breathe = 0.5 + 0.5 * math.sin(t * 2.4 + c.dx * 0.01);

    // Soft outer aura — steady breathing glow, flares on a fresh hit.
    final auraAlpha = (0.14 + 0.10 * breathe + 0.5 * f).clamp(0.0, 1.0);
    canvas.drawCircle(
      c,
      r * (1.55 + 0.25 * breathe + 0.5 * f),
      Paint()..color = _blendC(_pegCore, _pegHot, f).withValues(alpha: auraAlpha),
    );

    // Domed body with a top-lit radial gradient (glossy bumper).
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = Gradient.radial(
          c.translate(-r * 0.3, -r * 0.36),
          r * 1.35,
          [
            _blendC(_white, _pegCore, 0.25 + 0.5 * f),
            _blendC(_pegCore, _pegHot, f),
            _pegEdge,
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    // Bright rim ring (hotter on a hit) so the peg reads as a hard bumper.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.16)
        ..color = _blendC(_pegEdge, _white, 0.4 + 0.5 * f)
            .withValues(alpha: (0.7 + 0.3 * f).clamp(0.0, 1.0)),
    );

    // Specular highlight blob, top-left.
    canvas.drawCircle(
      c + Offset(-r * 0.32, -r * 0.36),
      r * 0.24,
      Paint()..color = _white.withValues(alpha: 0.75),
    );

    // Quick expanding shock ring on a fresh impact (rides the flash down).
    if (f > 0.02) {
      canvas.drawCircle(
        c,
        r * (1.0 + 0.9 * (1.0 - f)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, r * 0.14 * f)
          ..color = _pegHot.withValues(alpha: (0.6 * f).clamp(0.0, 1.0)),
      );
    }
  }

  static Color _blendC(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

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
