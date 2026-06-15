import 'dart:math' as math;
import 'dart:ui';

/// Pure-Canvas rendering for [CatchTheStar] (Star Catcher) — falling stars,
/// golden stars and BOMBS rain down each player's lane while a player-colored
/// basket slides along a catch line to scoop the good ones and dodge the bombs.
/// Holds NO game state and never mutates the simulation: callers pass plain value
/// snapshots. Kept in its own file so the gameplay module stays lean and the
/// drawing stays cohesive (mirrors the sumo_smash / tap_sprint split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its own
/// inputs, and never throws (so it is safe to call from `render`).
class CatchRenderer {
  CatchRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _skyTop = Color(0xFF0B1030); // deep midnight blue
  static const Color _skyMid = Color(0xFF141A47); // indigo band
  static const Color _skyBottom = Color(0xFF1E1140); // violet horizon glow
  static const Color _skyHaze = Color(0xFF2A1A55); // low atmospheric haze
  static const Color _moonCore = Color(0xFFF4F0DC);
  static const Color _moonEdge = Color(0xFFBFC6E8);
  static const Color _moonHalo = Color(0xFF8FA0E8);
  static const Color _moonCrater = Color(0x223A4170);
  static const Color _bgStar = Color(0xFFFFFFFF);
  static const Color _bgStarWarm = Color(0xFFFFE9B8);
  static const Color _bgStarCool = Color(0xFFB9D2FF);
  static const Color _vignette = Color(0xAA04030C);
  static const Color _starGold = Color(0xFFFFF1A8); // normal star body
  static const Color _starGoldHot = Color(0xFFFFFFFF); // star core
  static const Color _starGlow = Color(0xFFFFD24A); // normal star halo
  static const Color _bonusGold = Color(0xFFFFE070); // golden bonus body
  static const Color _bonusGlow = Color(0xFFFF9E1B); // golden bonus halo
  static const Color _bombBody = Color(0xFF2A2E38); // bomb shell
  static const Color _bombEdge = Color(0xFFE5484D); // bomb danger rim
  static const Color _bombHi = Color(0xFF5A6172); // bomb shell highlight
  static const Color _fuse = Color(0xFFB08050); // bomb fuse cord
  static const Color _spark = Color(0xFFFFC85A); // bomb fuse spark
  static const Color _laneSeam = Color(0x33FFFFFF); // lane divider tint
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _urgent = Color(0xFFFF6B6B);
  static const Color _ember = Color(0xFFFB7234); // bomb ember flicker (flame accent)
  // Rainbow shimmer ramp for the golden jackpot star (violet→magenta→amber→cyan).
  static const List<Color> _bonusSpectrum = [
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFFBBF24),
    Color(0xFF22D3EE),
  ];

  // ── Tuning (fractions / px; no inline magic numbers) ───────────────────────
  static const double _moonCenterXFrac = 0.74; // moon x / width
  static const double _moonCenterYFrac = 0.12; // moon y / height
  static const double _moonRadiusFrac = 0.07; // moon radius / width
  static const double _moonHaloFactor = 2.6; // halo radius / moon radius
  static const double _vignInnerFrac = 0.42;
  static const double _vignOuterFrac = 0.82;

  // Item (star / bomb) tuning, in fractions of the item radius `r`.
  static const double _starInnerFactor = 0.44; // inner / outer radius
  static const double _starHaloFactor = 2.4; // glow halo / outer radius
  static const double _starCoreFactor = 0.3; // bright core / outer radius
  static const int _starPoints = 5;
  static const int _goldenRays = 8; // sparkle-crown rays on a gold star
  static const double _bombHaloFactor = 2.2; // danger halo / bomb radius
  static const double _fuseLen = 0.9; // fuse length / bomb radius
  static const int _cometSegments = 4; // stacked trail puffs behind a star
  static const double _cometLenFactor = 3.4; // trail length / star radius
  static const int _emberCount = 5; // crackling embers around a bomb fuse

  // Trajectory-hint tuning (the legible "where it will cross" read).
  static const int _hintDashes = 9; // dashes along an item's predicted path
  static const double _hintMarkerR = 0.018; // intercept marker radius / minSide
  static const double _starHintAlpha = 0.28; // base alpha for a star hint
  static const double _bombHintAlpha = 0.42; // bombs hint a touch louder (warn)

  // Basket tuning, in fractions of the basket half-mouth `mouth`.
  static const double _basketDepthFactor = 0.9; // basket depth / half-mouth
  static const double _basketGlowFactor = 1.35; // soft glow / half-mouth
  static const int _basketWeaveLines = 4; // woven cross-strands

  // ── Background: night-sky gradient + soft horizon haze + a glowing moon ─────
  static void drawBackground(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_skyTop, _skyMid, _skyBottom, _skyHaze],
        const [0.0, 0.45, 0.82, 1.0],
      );
    canvas.drawRect(Offset.zero & size, sky);
    _drawMoon(canvas, size);
  }

  static void _drawMoon(Canvas canvas, Size size) {
    final center =
        Offset(size.width * _moonCenterXFrac, size.height * _moonCenterYFrac);
    final r = size.width * _moonRadiusFrac;
    if (r <= 1) return;

    // Wide dreamy bloom — a very soft outer wash so the moon glows into the sky
    // (stacked under the tighter cool halo for layered depth, not a blur).
    canvas.drawCircle(
      center,
      r * _moonHaloFactor * 1.7,
      Paint()
        ..shader = Gradient.radial(
          center,
          r * _moonHaloFactor * 1.7,
          [_moonHalo.withValues(alpha: 0.12), const Color(0x00000000)],
          const [0.0, 1.0],
        ),
    );
    // Wide cool halo.
    canvas.drawCircle(
      center,
      r * _moonHaloFactor,
      Paint()
        ..shader = Gradient.radial(
          center,
          r * _moonHaloFactor,
          [_moonHalo.withValues(alpha: 0.30), const Color(0x00000000)],
        ),
    );
    // Moon disc with a soft terminator (light from upper-right).
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = Gradient.radial(
          center.translate(r * 0.28, -r * 0.28),
          r * 1.25,
          const [_moonCore, _moonEdge],
          const [0.0, 1.0],
        ),
    );
    // A few faint craters for character.
    final crater = Paint()..color = _moonCrater;
    canvas.drawCircle(center.translate(-r * 0.3, r * 0.18), r * 0.22, crater);
    canvas.drawCircle(center.translate(r * 0.22, r * 0.34), r * 0.14, crater);
    canvas.drawCircle(center.translate(r * 0.12, -r * 0.3), r * 0.1, crater);
  }

  /// Parallax field of twinkling background stars. [stars] are fixed unit-space
  /// points (x,y in 0..1); [seeds] packs a per-star depth in its fractional part
  /// (0..1) plus a phase in its integer part. The sim clock [t] drives the
  /// twinkle so the field shimmers without any state held here.
  static void drawBackgroundStars(
    Canvas canvas,
    Size size,
    List<Offset> stars,
    List<double> seeds,
    double t,
  ) {
    if (stars.isEmpty) return;
    final paint = Paint();
    for (var i = 0; i < stars.length; i++) {
      final s = stars[i];
      final seed = i < seeds.length ? seeds[i] : i.toDouble();
      final depth = seed - seed.floorToDouble(); // fractional part 0..1 = depth
      // Nearer stars (higher depth) are bigger + brighter and twinkle slower.
      final twinkle =
          0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * (1.1 + depth) + seed * 7.0));
      final radius = 0.6 + depth * 1.9;
      final hue = _bgHue(i % 3);
      paint.color =
          hue.withValues(alpha: (twinkle * (0.3 + depth * 0.6)).clamp(0.0, 1.0));
      final px = s.dx * size.width;
      final py = s.dy * size.height;
      canvas.drawCircle(Offset(px, py), radius, paint);
      // Brightest stars get a tiny cross sparkle.
      if (depth > 0.82) {
        final arm = radius * 3.4;
        final spark = Paint()
          ..color = hue.withValues(alpha: (twinkle * 0.5).clamp(0.0, 1.0))
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(px - arm, py), Offset(px + arm, py), spark);
        canvas.drawLine(Offset(px, py - arm), Offset(px, py + arm), spark);
      }
    }
  }

  static Color _bgHue(int i) {
    switch (i) {
      case 0:
        return _bgStarWarm;
      case 1:
        return _bgStarCool;
      default:
        return _bgStar;
    }
  }

  /// Crowd-dark vignette so the action pops (drawn over the sky, under the
  /// lanes + items).
  static void drawVignette(Canvas canvas, Size size) {
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final outer = diag * _vignOuterFrac;
    final inner = diag * _vignInnerFrac;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.52),
          outer,
          [const Color(0x00000000), _vignette],
          [(inner / outer).clamp(0.0, 0.99), 1.0],
        ),
    );
    // Corner accents: soft radial darkenings tucked into each corner so the
    // frame reads cinematic and the play area floats brighter at center.
    final cornerR = math.max(size.width, size.height) * 0.42;
    final rect = Offset.zero & size;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.radial(
            corner,
            cornerR,
            [_vignette.withValues(alpha: 0.5), const Color(0x00000000)],
            const [0.0, 1.0],
          ),
      );
    }
  }

  /// A player's lane: a faint colored seam framing their column, a glowing catch
  /// line at [catchLineY] (pixels) where catches resolve, and — in a multiplayer
  /// split — a small player pip + live score in the corner so each band is
  /// readable at a glance. [zone] is the lane rect in pixels.
  static void drawLane(
    Canvas canvas,
    Rect zone,
    double catchLineY,
    Color color,
    int displayNumber, {
    int score = 0,
    bool multiPlayer = false,
  }) {
    if (zone.width <= 1 || zone.height <= 1) return;

    // Lane seam (vertical edges) so columns read as separate play spaces.
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, zone.width * 0.006)
      ..color = _laneSeam;
    if (multiPlayer) {
      canvas.drawLine(zone.topLeft, zone.bottomLeft, seam);
      canvas.drawLine(zone.topRight, zone.bottomRight, seam);
    }

    // Catch-zone shimmer: a soft horizontal sheen band centered on the catch
    // line, painted UNDER the readability glow so it adds glassy depth without
    // dimming the telegraph. Static (no clock here) — a faint highlight that
    // widens the perceived "active strip".
    final shimmerH = math.max(4.0, zone.width * 0.07);
    final shimmerRect = Rect.fromLTRB(
        zone.left, catchLineY - shimmerH, zone.right, catchLineY + shimmerH);
    canvas.drawRect(
      shimmerRect,
      Paint()
        ..shader = Gradient.linear(
          Offset(zone.left, catchLineY),
          Offset(zone.left, catchLineY - shimmerH),
          [
            color.withValues(alpha: 0.16),
            const Color(0x00000000),
          ],
        ),
    );
    canvas.drawRect(
      shimmerRect,
      Paint()
        ..shader = Gradient.linear(
          Offset(zone.left, catchLineY),
          Offset(zone.left, catchLineY + shimmerH),
          [
            color.withValues(alpha: 0.16),
            const Color(0x00000000),
          ],
        ),
    );

    // Glowing catch line across the lane — the telegraph of WHERE catches happen.
    final lineGlow = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.0, zone.width * 0.025)
      ..color = color.withValues(alpha: 0.30); // brighter: the action zone reads at a glance
    canvas.drawLine(
        Offset(zone.left, catchLineY), Offset(zone.right, catchLineY), lineGlow);
    final lineCore = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, zone.width * 0.01)
      ..color = color.withValues(alpha: 0.8);
    canvas.drawLine(
        Offset(zone.left, catchLineY), Offset(zone.right, catchLineY), lineCore);

    // Per-lane player pip + score (only when the screen is split).
    if (multiPlayer) {
      final pipR = math.max(8.0, zone.width * 0.05);
      final at = Offset(zone.left + pipR * 1.6, zone.top + pipR * 1.6);
      canvas.drawCircle(
        at,
        pipR,
        Paint()
          ..shader = Gradient.radial(
            at.translate(-pipR * 0.3, -pipR * 0.3),
            pipR,
            [_blend(color, _white, 0.4), color],
          ),
      );
      canvas.drawCircle(
        at,
        pipR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, pipR * 0.16)
          ..color = _white.withValues(alpha: 0.85),
      );
      _drawText(canvas, '$displayNumber', at, pipR * 1.3, _readableText(color),
          weight: FontWeight.w900);
      _drawText(
        canvas,
        '$score',
        Offset(at.dx + pipR * 2.4, at.dy),
        pipR * 1.5,
        color,
        weight: FontWeight.w900,
        glow: true,
        glowColor: color,
      );
    }
  }

  /// A falling item: a warm STAR, a brighter GOLD star (with a sparkle crown), or
  /// a clearly-distinct BOMB (dark shell, red danger rim + a lit fuse). [center]
  /// is the pixel position, [r] the outer radius; [spin] rotates it for life; [t]
  /// drives the bomb fuse twinkle. [velDir] is the unit travel direction (pixel
  /// space) so the comet wake streams opposite the ANGLED path — defaults to
  /// straight-down so a legacy vertical drop still trails upward. Distinct
  /// silhouettes + colors telegraph which is which from across the lane.
  static void drawItem(
    Canvas canvas,
    Offset center,
    double r, {
    bool isBomb = false,
    bool gold = false,
    double spin = 0,
    double t = 0,
    Offset velDir = const Offset(0, 1),
  }) {
    if (r <= 0) return;
    if (isBomb) {
      _drawBomb(canvas, center, r, t, velDir);
    } else {
      _drawStar(canvas, center, r, gold: gold, rot: spin, t: t, velDir: velDir);
    }
  }

  /// Normalize a travel direction; fall back to straight-down if degenerate.
  static Offset _safeDir(Offset v) {
    final len = math.sqrt(v.dx * v.dx + v.dy * v.dy);
    if (len <= 0 || !len.isFinite) return const Offset(0, 1);
    return Offset(v.dx / len, v.dy / len);
  }

  /// The legible READ: a faint dashed line from a falling item [from] down to its
  /// predicted intercept [to] on the catch line, capped by a small pulsing
  /// marker. Bombs hint a touch louder/redder so a converging crossing is obvious
  /// — you thread a telegraphed path, you do not guess. [minSide] sizes the
  /// marker; [t] pulses it. Additive, side-effect free, never throws.
  static void drawTrajectoryHint(
    Canvas canvas,
    Offset from,
    Offset to, {
    bool isBomb = false,
    bool gold = false,
    double t = 0,
    double minSide = 0,
  }) {
    final dx = to.dx - from.dx, dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    final base = isBomb ? _bombEdge : (gold ? _bonusGlow : _starGlow);
    final alpha = isBomb ? _bombHintAlpha : _starHintAlpha;
    // Fade the hint IN as the item nears the line (a far item hints faintly, a
    // committing one hints clearly) — read pressure rises with proximity.
    final dir = Offset(dx / dist, dy / dist);
    final dash = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, dist * 0.012)
      ..color = base.withValues(alpha: alpha);
    // Dashes that drift downward along the path so it reads as flowing toward the
    // line (the drift is deterministic off the sim clock).
    final flow = (t * 0.6) % 1.0;
    for (var i = 0; i < _hintDashes; i++) {
      final a = ((i + flow) / _hintDashes).clamp(0.0, 1.0);
      final b = (a + 0.5 / _hintDashes).clamp(0.0, 1.0);
      // Brighter near the intercept end so the eye is led to the catch point.
      dash.color = base.withValues(alpha: (alpha * (0.4 + 0.6 * a)).clamp(0.0, 1.0));
      canvas.drawLine(
        Offset(from.dx + dir.dx * dist * a, from.dy + dir.dy * dist * a),
        Offset(from.dx + dir.dx * dist * b, from.dy + dir.dy * dist * b),
        dash,
      );
    }
    // Pulsing intercept marker on the catch line — a soft halo + a crisp ring.
    final pulse = 0.5 + 0.5 * math.sin(t * 5.0 + (isBomb ? math.pi : 0));
    final mr = math.max(3.0, minSide * _hintMarkerR) * (0.85 + 0.3 * pulse);
    canvas.drawCircle(
      to,
      mr * 2.0,
      Paint()
        ..shader = Gradient.radial(
          to,
          mr * 2.0,
          [base.withValues(alpha: (alpha * 0.9).clamp(0.0, 1.0)),
            const Color(0x00000000)],
        ),
    );
    canvas.drawCircle(
      to,
      mr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, mr * 0.28)
        ..color = base.withValues(alpha: (0.5 + 0.4 * pulse).clamp(0.0, 1.0)),
    );
    // A tiny crosshair tick at the marker so the exact crossing x is unambiguous.
    final tick = math.max(2.0, mr * 0.8);
    final tickPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, mr * 0.22)
      ..color = base.withValues(alpha: (0.55 + 0.3 * pulse).clamp(0.0, 1.0));
    canvas.drawLine(to.translate(-tick, 0), to.translate(tick, 0), tickPaint);
  }

  static void _drawStar(
    Canvas canvas,
    Offset center,
    double r, {
    bool gold = false,
    double rot = 0,
    double t = 0,
    Offset velDir = const Offset(0, 1),
  }) {
    final pulse = 0.5 + 0.5 * math.sin(t * 5.0);
    final body = gold ? _bonusGold : _starGold;
    final glow = gold ? _bonusGlow : _starGlow;

    // Comet trail: stacked translucent puffs streaming behind the travel
    // direction, each smaller + fainter than the last so the star reads as a
    // streaking meteor whose wake reveals its ANGLED path.
    final wake = -_safeDir(velDir); // opposite the direction of motion
    final trailPaint = Paint();
    for (var i = _cometSegments; i >= 1; i--) {
      final f = i / _cometSegments; // 1 at tail .. 1/n near body
      final back = r * _cometLenFactor * f * (gold ? 1.2 : 1.0);
      final segR = r * (0.85 - 0.5 * f);
      // Tail breathes slightly out of phase so it flickers like burning gas.
      final flick = 0.8 + 0.2 * math.sin(t * 6.0 - i * 0.9);
      trailPaint.color = glow.withValues(
        alpha: ((1.05 - f) * 0.24 * flick * (gold ? 1.3 : 1.0)).clamp(0.0, 1.0),
      );
      canvas.drawCircle(center.translate(wake.dx * back, wake.dy * back),
          segR.clamp(0.5, r), trailPaint);
    }

    // Soft halo (breathes; gold blooms larger).
    final haloR = r * _starHaloFactor * (gold ? 1.2 : 1.0) * (0.9 + 0.2 * pulse);
    canvas.drawCircle(
      center,
      haloR,
      Paint()
        ..shader = Gradient.radial(
          center,
          haloR,
          [
            glow.withValues(alpha: (gold ? 0.55 : 0.42) * (0.7 + 0.3 * pulse)),
            const Color(0x00000000),
          ],
        ),
    );

    // Gold gets a sparkle crown of long thin rays — plus a big rainbow jackpot
    // aura that shimmers through the brand spectrum so it screams "BONUS!".
    if (gold) {
      // Outer rainbow bloom: a wide, slow-pulsing sweep-gradient ring. The hue
      // offset advances with the clock so colors orbit the star.
      final auraR = r * _starHaloFactor * 1.7 * (0.85 + 0.3 * pulse);
      final hueShift = t * 0.6; // radians; deterministic spectrum rotation
      canvas.drawCircle(
        center,
        auraR,
        Paint()
          ..shader = Gradient.sweep(
            center,
            [..._bonusSpectrum, _bonusSpectrum.first]
                .map((c) => c.withValues(alpha: 0.34 * (0.7 + 0.3 * pulse)))
                .toList(),
            const [0.0, 0.28, 0.55, 0.8, 1.0],
            TileMode.clamp,
            hueShift,
            hueShift + math.pi * 2,
          ),
      );
      // Bright inner gold halo on top so the body stays warm, not washed out.
      canvas.drawCircle(
        center,
        haloR * 0.95,
        Paint()
          ..shader = Gradient.radial(
            center,
            haloR * 0.95,
            [_bonusGlow.withValues(alpha: 0.4 * (0.7 + 0.3 * pulse)),
              const Color(0x00000000)],
          ),
      );
      // Sparkle crown — each ray tinted from a different spectrum slot so the
      // crown itself glints in rainbow as it spins.
      final rayBase = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, r * 0.08);
      for (var i = 0; i < _goldenRays; i++) {
        final ang = rot * 0.5 + i * (math.pi * 2 / _goldenRays);
        final dir = Offset(math.cos(ang), math.sin(ang));
        final tint = _bonusSpectrum[i % _bonusSpectrum.length];
        rayBase.color =
            _blend(tint, _white, 0.45).withValues(alpha: 0.55 + 0.3 * pulse);
        canvas.drawLine(center + dir * r * 1.2,
            center + dir * r * (2.1 + 0.5 * pulse), rayBase);
      }
    }

    // The 5-point star body (filled) with a gradient, plus a crisp outline.
    final path = _starPath(center, r, r * _starInnerFactor, _starPoints, rot);
    canvas.drawPath(
      path,
      Paint()
        ..shader =
            Gradient.radial(center, r, [_starGoldHot, body], const [0.0, 1.0]),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.08)
        ..color = _blend(glow, _white, 0.3).withValues(alpha: 0.8),
    );
    // White-hot core.
    canvas.drawCircle(center, r * _starCoreFactor,
        Paint()..color = _white.withValues(alpha: 0.9));
  }

  static void _drawBomb(
      Canvas canvas, Offset center, double r, double t, Offset velDir) {
    // Pulsing red danger halo so a bomb screams "DON'T CATCH" from a distance.
    final pulse = 0.5 + 0.5 * math.sin(t * 7.0);
    final haloR = r * _bombHaloFactor * (0.9 + 0.15 * pulse);

    // Faint red motion-streak behind the bomb along its travel line so its
    // ANGLED approach reads (stacked fading puffs, opposite the direction).
    final wake = -_safeDir(velDir);
    final streak = Paint();
    for (var i = _cometSegments; i >= 1; i--) {
      final f = i / _cometSegments;
      final back = r * (_cometLenFactor * 0.7) * f;
      final segR = r * (0.7 - 0.42 * f);
      streak.color = _bombEdge
          .withValues(alpha: ((1.0 - f) * 0.16).clamp(0.0, 1.0));
      canvas.drawCircle(center.translate(wake.dx * back, wake.dy * back),
          segR.clamp(0.5, r), streak);
    }

    canvas.drawCircle(
      center,
      haloR,
      Paint()
        ..shader = Gradient.radial(
          center,
          haloR,
          [
            _bombEdge.withValues(alpha: 0.30 + 0.18 * pulse),
            const Color(0x00000000),
          ],
        ),
    );

    // Fuse cord rising from the top of the shell, with a flickering spark tip.
    final fuseBase = center.translate(r * 0.18, -r * 0.78);
    final fuseTip = center.translate(r * 0.42, -r * (0.78 + _fuseLen * 0.6));
    canvas.drawLine(
      fuseBase,
      fuseTip,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, r * 0.1)
        ..color = _fuse,
    );
    // Crackling spark head: a flickering ember halo (sized by a fast sine) with
    // a hot white core, ringed by deterministic embers that pop in and out.
    final crackle = 0.5 + 0.5 * math.sin(t * 13.0); // fast flame flutter
    final sparkR = r * (0.16 + 0.07 * pulse);
    canvas.drawCircle(
      fuseTip,
      sparkR * (2.2 + 0.9 * crackle),
      Paint()..color = _ember.withValues(alpha: 0.30 + 0.22 * crackle),
    );
    canvas.drawCircle(
      fuseTip,
      sparkR * 1.6,
      Paint()..color = _spark.withValues(alpha: 0.55 + 0.25 * crackle),
    );
    canvas.drawCircle(
        fuseTip, sparkR * (0.9 + 0.2 * crackle), Paint()..color = _white);
    // Embers flung outward — each on its own phase so they twinkle chaotically.
    final emberPaint = Paint();
    for (var i = 0; i < _emberCount; i++) {
      final phase = t * (4.0 + i) + i * 1.7; // per-ember deterministic clock
      final life = 0.5 + 0.5 * math.sin(phase); // 0..1 spawn→fade
      final ang = i * (math.pi * 2 / _emberCount) + t * 1.3;
      final dist = sparkR * (1.4 + 2.6 * life);
      final pos = fuseTip.translate(math.cos(ang) * dist,
          math.sin(ang) * dist - sparkR * life * 1.5); // drift up like sparks
      emberPaint.color = _blend(_spark, _ember, life)
          .withValues(alpha: (0.7 * (1.0 - life)).clamp(0.0, 1.0));
      canvas.drawCircle(pos, sparkR * (0.42 - 0.22 * life), emberPaint);
    }

    // Dark round shell with a soft top-left highlight.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = Gradient.radial(
          center.translate(-r * 0.35, -r * 0.35),
          r * 1.3,
          const [_bombHi, _bombBody],
          const [0.0, 1.0],
        ),
    );
    // Red danger rim.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.12)
        ..color = _bombEdge.withValues(alpha: 0.85),
    );
    // Tiny glint.
    canvas.drawCircle(center.translate(-r * 0.3, -r * 0.3), r * 0.16,
        Paint()..color = _white.withValues(alpha: 0.5));
  }

  /// A player's basket at the catch line. [center] is its pixel position, [mouth]
  /// the half-width of its catching mouth (so its full opening spans 2×mouth).
  /// [flash] in 0..1 (a recent catch) brightens it; [stun] in 0..1 (just caught a
  /// bomb) tints it red and shakes a little so the penalty is unmistakable. [t]
  /// drives a subtle idle wobble.
  static void drawBasket(
    Canvas canvas,
    Offset center,
    double mouth,
    Color color, {
    double flash = 0,
    double stun = 0,
    double t = 0,
  }) {
    if (mouth <= 1) return;
    final f = flash.clamp(0.0, 1.0);
    final s = stun.clamp(0.0, 1.0);
    final tint = s > 0 ? _blend(color, _bombEdge, 0.6 * s) : color;
    // A stunned basket trembles; a fresh catch makes it bob up a touch.
    final shake = s > 0 ? math.sin(t * 40) * mouth * 0.12 * s : 0.0;
    final cx = center.dx + shake;
    final depth = mouth * _basketDepthFactor;
    final top = center.dy;
    final bottom = center.dy + depth;
    final left = cx - mouth;
    final right = cx + mouth;

    // Soft glow under the basket (much stronger on a fresh catch).
    canvas.drawCircle(
      Offset(cx, center.dy + depth * 0.4),
      mouth * _basketGlowFactor,
      Paint()
        ..shader = Gradient.radial(
          Offset(cx, center.dy + depth * 0.4),
          mouth * _basketGlowFactor,
          [
            tint.withValues(alpha: (0.14 + 0.4 * f).clamp(0.0, 1.0)),
            const Color(0x00000000),
          ],
        ),
    );

    // Basket cup: a trapezoid (wider at the top opening), filled with a vertical
    // gradient + a crisp rim, so it reads clearly as a container to scoop into.
    final cup = Path()
      ..moveTo(left, top)
      ..lineTo(right, top)
      ..lineTo(right - mouth * 0.22, bottom)
      ..lineTo(left + mouth * 0.22, bottom)
      ..close();
    canvas.drawPath(
      cup,
      Paint()
        ..shader = Gradient.linear(
          Offset(cx, top),
          Offset(cx, bottom),
          [_blend(tint, _white, 0.35 + 0.3 * f), tint],
        ),
    );
    // Woven cross-strands for a basket look.
    final weave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, mouth * 0.05)
      ..color = _blend(tint, _black, 0.25).withValues(alpha: 0.5);
    for (var i = 1; i < _basketWeaveLines; i++) {
      final ty = top + (bottom - top) * (i / _basketWeaveLines);
      final inset = mouth * 0.22 * (i / _basketWeaveLines);
      canvas.drawLine(
          Offset(left + inset, ty), Offset(right - inset, ty), weave);
    }
    // Subtle player-color rim glow tracing the opening: a soft wide underlay
    // that breathes on the idle clock and flares on a catch, framing the mouth
    // in the lane's color without washing out the bright rim above it.
    final rimBreath = 0.5 + 0.5 * math.sin(t * 3.0);
    canvas.drawLine(
      Offset(left, top),
      Offset(right, top),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(2.0, mouth * (0.26 + 0.18 * f))
        ..color = tint.withValues(
            alpha: ((0.18 + 0.12 * rimBreath) + 0.4 * f).clamp(0.0, 1.0)),
    );
    // Bright top rim (the opening) — thickens + brightens on a catch.
    canvas.drawLine(
      Offset(left, top),
      Offset(right, top),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, mouth * (0.12 + 0.1 * f))
        ..color = _blend(tint, _white, 0.5).withValues(alpha: 0.9),
    );
    // Cup outline.
    canvas.drawPath(
      cup,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, mouth * 0.05)
        ..color = _blend(tint, _white, 0.2).withValues(alpha: 0.8),
    );
  }

  /// Round clock + leader readout at the top center. [secondsLeft] is the
  /// remaining time; [leaderColor]/[leaderScore] highlight the current leader and
  /// [targetScore] shows the objective ("FIRST TO N").
  static void drawHud(
    Canvas canvas,
    Size size,
    double secondsLeft,
    Color? leaderColor,
    int leaderScore,
    int targetScore,
  ) {
    final t = math.max(0.0, secondsLeft);
    final urgent = t <= 5;
    final clockColor = urgent ? _urgent : _white;
    _drawText(
      canvas,
      t.ceil().toString(),
      Offset(size.width / 2, size.height * 0.05),
      size.width * 0.055,
      clockColor.withValues(alpha: 0.92),
      weight: FontWeight.w900,
      glow: true,
      glowColor: urgent ? _urgent : _starGlow,
    );
    // Objective line: the goal is unmistakable to a kid.
    _drawText(
      canvas,
      'CATCH STARS · FIRST TO $targetScore',
      Offset(size.width / 2, size.height * 0.092),
      size.width * 0.026,
      _starGold.withValues(alpha: 0.85),
      weight: FontWeight.w800,
    );
    if (leaderColor != null && leaderScore > 0) {
      _drawText(
        canvas,
        'BEST $leaderScore',
        Offset(size.width / 2, size.height * 0.128),
        size.width * 0.03,
        leaderColor,
        weight: FontWeight.w800,
      );
    }
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  /// Build a [points]-point star path with the given outer/inner radii, rotated
  /// by [rot] radians.
  static Path _starPath(
      Offset c, double outer, double inner, int points, double rot) {
    final path = Path();
    final step = math.pi / points;
    for (var i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outer : inner;
      final a = -math.pi / 2 + rot + i * step;
      final p = Offset(c.dx + math.cos(a) * radius, c.dy + math.sin(a) * radius);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }

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
