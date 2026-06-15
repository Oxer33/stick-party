import 'dart:math' as math;
import 'dart:ui';

/// Which screen edge a tank is mounted on. Drives the "up" (outward) direction
/// used to orient the hull, tracks, health pips and aim guide so every tank
/// reads correctly whether it sits at the bottom, top, left or right.
enum TankEdge { bottom, top, left, right }

extension TankEdgeGeometry on TankEdge {
  /// Unit vector pointing away from the playfield (the tank's local "up").
  Offset get outward => switch (this) {
        TankEdge.bottom => const Offset(0, 1),
        TankEdge.top => const Offset(0, -1),
        TankEdge.left => const Offset(-1, 0),
        TankEdge.right => const Offset(1, 0),
      };

  /// Unit vector along the edge (the tank's local "right" / track axis).
  Offset get along => switch (this) {
        TankEdge.bottom => const Offset(1, 0),
        TankEdge.top => const Offset(1, 0),
        TankEdge.left => const Offset(0, 1),
        TankEdge.right => const Offset(0, 1),
      };
}

/// Immutable snapshot of one tank handed to the renderer. Carries only what is
/// needed to draw — no gameplay coupling, no mutation.
class TankView {
  final Offset base; // turret pivot in arena px
  final Color color;
  final TankEdge edge;
  final double aimAngle; // barrel angle in radians (screen space)
  final int hp;
  final int maxHp;
  final double flash; // 0..1 white hit-flash
  final double recoil; // 0..1 turret recoil amount
  final double muzzle; // 0..1 muzzle-flash amount
  final double invuln; // 0..1 invulnerability blink phase (0 = none)
  final double scale; // body scale factor (fits the arena)
  final bool precision; // true while the player holds to charge (fine-tune aim)
  final double charge; // 0..1 charge level while holding (0 = snap/tap)
  final double reload; // 0..1 breech reload fill (1 = loaded; < 1 = re-arming)
  final double victory; // 0..1 winner-celebration pulse on the hull (0 = none)

  const TankView({
    required this.base,
    required this.color,
    required this.edge,
    required this.aimAngle,
    required this.hp,
    required this.maxHp,
    required this.flash,
    required this.recoil,
    required this.muzzle,
    required this.invuln,
    required this.scale,
    this.precision = false,
    this.charge = 0,
    this.reload = 1,
    this.victory = 0,
  });
}

/// Immutable snapshot of a DOWNED tank's smoldering wreck, handed to the renderer
/// so a destroyed tank leaves a burning hulk + a rising smoke column instead of
/// vanishing. Carries only what the wreck draw needs — no gameplay coupling.
class WreckView {
  final Offset base; // turret pivot anchor in arena px (same as the live tank)
  final Color color;
  final TankEdge edge;
  final double aimAngle; // last barrel angle, so the broken barrel droops from it
  final double scale;
  final double age; // seconds since downed (drives ember flicker + smoke rise)
  final double t; // ambient clock for flicker/sway phase

  const WreckView({
    required this.base,
    required this.color,
    required this.edge,
    required this.aimAngle,
    required this.scale,
    required this.age,
    required this.t,
  });
}

/// Immutable snapshot of one destructible cover crate.
class CrateView {
  final Rect rect;
  final int hp;
  final int maxHp;
  final double flash; // 0..1 chip flash

  const CrateView({
    required this.rect,
    required this.hp,
    required this.maxHp,
    required this.flash,
  });
}

/// Immutable snapshot of one in-flight shell + its recent trail samples
/// (newest first) for a smoke/spark streak.
class ShellView {
  final Offset pos;
  final Offset vel;
  final Color color;
  final List<Offset> trail;

  const ShellView({
    required this.pos,
    required this.vel,
    required this.color,
    required this.trail,
  });
}

/// Pure-Canvas rendering for [TankDuel]. Holds NO game state and never mutates
/// the simulation — callers pass plain value snapshots. Every method guards its
/// own inputs and never throws, so it is safe to call from `render`.
class TankRenderer {
  TankRenderer._();

  // ── Battlefield palette (no magic colors inline elsewhere) ─────────────────
  static const Color _skyTop = Color(0xFF0B1022);
  static const Color _skyMid = Color(0xFF182A4A);
  static const Color _skyHorizon = Color(0xFF3A4E6B);
  static const Color _groundNear = Color(0xFF1A140E);
  static const Color _groundFar = Color(0xFF2A2118);
  static const Color _gridLine = Color(0x14FFE2A8);
  static const Color _duneShade = Color(0x22000000);
  static const Color _vignette = Color(0x88000000);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _steel = Color(0xFF8A95A6);
  static const Color _steelDark = Color(0xFF2B3340);
  static const Color _scorch = Color(0xFF0A0A0C);
  static const Color _smoke = Color(0xFF6A6F78); // wreck smoke column
  static const Color _dust = Color(0xFFB89A6E); // kicked-up / drifting sand
  static const Color _crateWood = Color(0xFFB07C3C);
  static const Color _crateWoodDark = Color(0xFF6E4A20);
  static const Color _crateBand = Color(0xFF3A2A14);
  static const Color _muzzleHot = Color(0xFFFFF4C2);
  static const Color _muzzleCore = Color(0xFFFFC23C);
  static const Color _shellHot = Color(0xFFFFE6A0);
  static const Color _embers = Color(0xFFFF9A3C);
  static const Color _chargeHot = Color(0xFFFF5A2E); // full-charge gauge tint

  // ── Geometry tuning (fractions of the tank base radius) ────────────────────
  static const double _hullW = 2.5;
  static const double _hullH = 1.1;
  static const double _hullRadius = 0.22;
  static const double _trackW = 2.7;
  static const double _trackH = 0.5;
  static const int _trackSegments = 7;
  static const double _turretR = 0.78;
  static const double _barrelLen = 1.9;
  static const double _barrelW = 0.34;
  static const double _recoilKick = 0.55; // barrel pull-back at full recoil
  static const double _aimGuideLen = 360; // px reticle reach
  static const double _shadowDrop = 0.55;
  // Reference impact radius used to fade kicked-up dust as a scorch shrinks.
  static const double _scorchFullR = 34;

  // ── Background: layered sky → horizon → ground band with grid + dunes ───────
  static void drawBattlefield(
    Canvas canvas,
    Size size, {
    required double horizonY,
    required List<Offset> embers,
    required double t,
  }) {
    final sky = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, horizonY),
        const [_skyTop, _skyMid, _skyHorizon],
        const [0.0, 0.62, 1.0],
      );
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, horizonY), sky);

    final ground = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, horizonY),
        Offset(size.width / 2, size.height),
        const [_groundFar, _groundNear],
      );
    canvas.drawRect(Rect.fromLTRB(0, horizonY, size.width, size.height), ground);

    _drawHorizonGlow(canvas, size, horizonY);
    _drawDunes(canvas, size, horizonY);
    _drawPerspectiveGrid(canvas, size, horizonY);
    _drawAmbientDust(canvas, size, horizonY, t);
    _drawEmbers(canvas, embers, size, t);
    _drawVignette(canvas, size);
  }

  /// A few faint sheets of sand drifting laterally across the ground band — the
  /// battlefield breathing between shots. Deterministic from index + [t] (no
  /// Random/DateTime), parallaxed by row (lower = faster, larger, brighter) so it
  /// reads as ground-level haze, never near the sky or over the reticle's job.
  /// Pure translucent fills — no blur, one reused Paint.
  static void _drawAmbientDust(
      Canvas canvas, Size size, double horizonY, double t) {
    const motes = 9;
    final groundH = size.height - horizonY;
    if (groundH <= 0) return;
    final paint = Paint();
    for (var i = 0; i < motes; i++) {
      // Depth 0 (far/near horizon) → 1 (close foreground); spread down the band.
      final depth = ((i * 0.618) % 1.0);
      final y = horizonY + groundH * (0.12 + 0.82 * depth * depth);
      // Drift speed + size scale with depth (parallax): close haze moves more.
      final speed = size.width * (0.012 + 0.045 * depth);
      final dir = i.isEven ? 1.0 : -1.0;
      // Wrap horizontally with generous over-scan so puffs ease on/off frame.
      final span = size.width * 1.3;
      final raw = (i * 137.0 + dir * t * speed) % span;
      final x = (raw < 0 ? raw + span : raw) - size.width * 0.15;
      final grow = (10 + 26 * depth) * (0.8 + 0.2 * math.sin(t * 0.6 + i));
      final breathe = 0.5 + 0.5 * math.sin(t * 0.5 + i * 1.9);
      final alpha = (0.018 + 0.030 * depth) * breathe;
      paint.color = _dust.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), grow, paint);
    }
  }

  static void _drawHorizonGlow(Canvas canvas, Size size, double horizonY) {
    final glow = Paint()
      ..shader = Gradient.linear(
        Offset(0, horizonY - size.height * 0.10),
        Offset(0, horizonY + size.height * 0.04),
        const [Color(0x00FFB060), Color(0x33FFC27A), Color(0x00FFB060)],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(
      Rect.fromLTRB(0, horizonY - size.height * 0.12, size.width,
          horizonY + size.height * 0.05),
      glow,
    );
  }

  /// Two soft dune silhouettes just below the horizon for depth.
  static void _drawDunes(Canvas canvas, Size size, double horizonY) {
    final paint = Paint()..color = _duneShade;
    for (var layer = 0; layer < 2; layer++) {
      final amp = size.height * (0.018 + layer * 0.016);
      final baseY = horizonY + size.height * (0.02 + layer * 0.05);
      final path = Path()..moveTo(0, baseY);
      final waves = 3 + layer;
      for (var x = 0.0; x <= size.width; x += size.width / 48) {
        final y = baseY +
            math.sin((x / size.width) * math.pi * waves + layer) * amp;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  /// Faint converging perspective grid on the ground band.
  static void _drawPerspectiveGrid(Canvas canvas, Size size, double horizonY) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _gridLine;
    final vanish = Offset(size.width / 2, horizonY - size.height * 0.04);
    const cols = 9;
    for (var i = 0; i <= cols; i++) {
      final fx = i / cols;
      final bottomX = (fx - 0.5) * size.width * 2.4 + size.width / 2;
      canvas.drawLine(vanish, Offset(bottomX, size.height), paint);
    }
    const rows = 6;
    for (var i = 1; i <= rows; i++) {
      final f = i / rows;
      final y = horizonY + (size.height - horizonY) * (f * f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  static void _drawEmbers(
      Canvas canvas, List<Offset> embers, Size size, double t) {
    if (embers.isEmpty) return;
    final paint = Paint()..color = _embers;
    for (var i = 0; i < embers.length; i++) {
      final e = embers[i];
      // Slow upward drift that wraps within the frame.
      final drift = (e.dy - t * (12 + (i % 4) * 6)) % size.height;
      final y = drift < 0 ? drift + size.height : drift;
      final sway = math.sin(t * 1.3 + i) * 6;
      final twinkle = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(t * 2.0 + i * 1.7));
      paint.color = _embers.withValues(alpha: twinkle.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(e.dx + sway, y), 1.2 + (i % 3) * 0.6, paint);
    }
  }

  static void _drawVignette(Canvas canvas, Size size) {
    final r = size.longestSide * 0.72;
    final paint = Paint()
      ..shader = Gradient.radial(
        Offset(size.width / 2, size.height * 0.5),
        r,
        const [Color(0x00000000), _vignette],
        const [0.62, 1.0],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  // ── Scorch decals (drawn under everything else, above the ground) ──────────
  static void drawScorch(Canvas canvas, Offset at, double radius) {
    if (radius <= 0) return;
    final paint = Paint()
      ..shader = Gradient.radial(
        at,
        radius,
        const [_scorch, Color(0x66000000), Color(0x00000000)],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawCircle(at, radius, paint);
    _drawImpactDust(canvas, at, radius);
  }

  /// A low ring of kicked-up dust settling around a fresh impact mark — a few
  /// deterministic puffs splayed outward, fading as the scorch's [radius]
  /// shrinks with its fade. Rides the existing per-impact scorch event (no new
  /// state, no clock): variation comes purely from `at` + the petal index, so it
  /// is stable frame-to-frame. Solid translucent fills only — no per-puff blur.
  static void _drawImpactDust(Canvas canvas, Offset at, double radius) {
    const puffs = 7;
    // Per-impact seed from position so each crater's dust splay differs but is
    // deterministic (never Random()/DateTime in render).
    final seed = (at.dx * 0.7 + at.dy * 1.3);
    final dust = Paint();
    for (var i = 0; i < puffs; i++) {
      final ang = (i / puffs) * math.pi * 2 + math.sin(seed + i) * 0.6;
      // Push out a touch past the scorch edge; younger (bigger-radius) marks
      // throw their dust slightly farther so it reads as "kicked up, settling".
      final reach = radius * (0.92 + 0.28 * (0.5 + 0.5 * math.sin(seed * 1.7 + i)));
      final at2 = at + Offset(math.cos(ang), math.sin(ang)) * reach;
      final grow = radius * (0.16 + 0.10 * (0.5 + 0.5 * math.cos(seed + i * 2.1)));
      // The whole ring fades with the scorch's own radius shrink.
      final fade = (radius / _scorchFullR).clamp(0.0, 1.0);
      dust.color = _dust.withValues(alpha: (0.16 * fade).clamp(0.0, 1.0));
      canvas.drawCircle(at2, grow, dust);
    }
  }

  // ── Destructible cover crate ───────────────────────────────────────────────
  static void drawCrate(Canvas canvas, CrateView c) {
    final rect = c.rect;
    // Cheap soft shadow: two stacked translucent rounded fills (a wider, fainter
    // pad under a tighter one) instead of a GPU-costly blur, drawn every frame.
    final base = rect.translate(0, rect.height * 0.12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(base.inflate(4), const Radius.circular(7)),
      Paint()..color = _black.withValues(alpha: 0.14),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(base.inflate(1.5), const Radius.circular(5)),
      Paint()..color = _black.withValues(alpha: 0.24),
    );

    final damage = c.maxHp <= 0 ? 0.0 : 1.0 - (c.hp / c.maxHp).clamp(0.0, 1.0);
    final body = Paint()
      ..shader = Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [
          _blend(_crateWood, _crateWoodDark, 0.15 + damage * 0.4),
          _blend(_crateWoodDark, _black, damage * 0.5),
        ],
      );
    final rrect =
        RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, body);

    // Plank lines + diagonal brace.
    final plank = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, rect.width * 0.03)
      ..color = _crateBand.withValues(alpha: 0.7);
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      plank,
    );
    canvas.drawLine(rect.topLeft, rect.bottomRight, plank);

    // Outline.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, rect.width * 0.04)
        ..color = _black.withValues(alpha: 0.55),
    );

    // Damage cracks grow with damage.
    if (damage > 0.33) {
      final crack = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, rect.width * 0.025)
        ..color = _black.withValues(alpha: 0.6 * damage);
      final cx = rect.center.dx, top = rect.top, bot = rect.bottom;
      final path = Path()
        ..moveTo(cx, top + rect.height * 0.1)
        ..lineTo(cx - rect.width * 0.12, rect.center.dy)
        ..lineTo(cx + rect.width * 0.08, rect.center.dy)
        ..lineTo(cx - rect.width * 0.05, bot - rect.height * 0.1);
      canvas.drawPath(path, crack);
    }

    // Chip flash.
    if (c.flash > 0.01) {
      canvas.drawRRect(
        rrect,
        Paint()..color = _white.withValues(alpha: (c.flash * 0.7).clamp(0.0, 1.0)),
      );
    }
  }

  // ── Aim guide / reticle from the barrel ────────────────────────────────────
  /// A dashed fading guide line + reticle along the barrel. While the player
  /// holds to charge ([t.precision]) the guide brightens, gains crosshair ticks,
  /// and its reach grows with [t.charge] — so the reticle visibly creeps out
  /// from a near lob toward a far snipe as power builds, and a charging shot
  /// reads clearly distinct from the idle sweep.
  static void drawAimGuide(Canvas canvas, TankView t) {
    final dir = Offset(math.cos(t.aimAngle), math.sin(t.aimAngle));
    final muzzle = _muzzlePoint(t);
    final c = t.charge.clamp(0.0, 1.0);
    // Reach: idle = base; charging starts short (near lob) and extends toward a
    // long snipe as the gauge fills.
    final reachMul = t.precision ? (0.7 + 1.1 * c) : 1.0;
    final reach = _aimGuideLen * reachMul;
    final end = muzzle + dir * reach;
    final boost = t.precision ? 1.0 : 0.0;
    // Dashed fading guide line (brighter + longer dashes while precision-aiming).
    final steps = t.precision ? 18 : 14;
    final paint = Paint()
      ..strokeWidth = 2 + boost
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < steps; i++) {
      if (i.isOdd) continue;
      final a = i / steps;
      final b = (i + 1) / steps;
      final fade = (1 - a) * (0.5 + 0.4 * boost);
      paint.color = t.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.drawLine(
        Offset.lerp(muzzle, end, a)!,
        Offset.lerp(muzzle, end, b)!,
        paint,
      );
    }
    // Reticle ring at the end (brighter while precision-aiming).
    final ringR = 7 * t.scale * (t.precision ? 1.15 : 1.0);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 + boost
      ..color = t.color.withValues(alpha: (0.45 + 0.45 * boost).clamp(0.0, 1.0));
    canvas.drawCircle(end, ringR, ring);
    // Crosshair ticks only when locked in for a careful shot.
    if (t.precision) {
      final tick = ringR * 0.85;
      final perp = Offset(-dir.dy, dir.dx);
      final p = Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = _white.withValues(alpha: 0.7);
      canvas.drawLine(end - dir * tick, end + dir * tick, p);
      canvas.drawLine(end - perp * tick, end + perp * tick, p);
      _drawChargeGauge(canvas, end, ringR, c);
    }
  }

  /// A power arc hugging the reticle that sweeps from empty to a full hot ring as
  /// [charge] fills — the at-a-glance "how hard is this shot" read for kids.
  static void _drawChargeGauge(
      Canvas canvas, Offset center, double ringR, double charge) {
    final c = charge.clamp(0.0, 1.0);
    final gaugeR = ringR * 1.9;
    final rect = Rect.fromCircle(center: center, radius: gaugeR);
    // Faint full backing ring.
    canvas.drawCircle(
      center,
      gaugeR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _white.withValues(alpha: 0.18),
    );
    if (c <= 0.001) return;
    // Filled sweep from straight up, hue shifting cool→hot with power.
    final fill = Color.lerp(_muzzleCore, _chargeHot, c) ?? _muzzleCore;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * c,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round
        ..color = fill.withValues(alpha: 0.95),
    );
  }

  // ── Tank ───────────────────────────────────────────────────────────────────
  static void drawTank(Canvas canvas, TankView t) {
    final r = _baseR * t.scale;
    final up = t.edge.outward;
    final side = t.edge.along;

    // Ground contact shadow: two stacked translucent ovals (wide+faint under
    // tight+darker) fake a soft edge far cheaper than a per-frame blur.
    final shadowCenter = t.base + up * (r * _shadowDrop);
    canvas.save();
    canvas.translate(shadowCenter.dx, shadowCenter.dy);
    canvas.rotate(math.atan2(side.dy, side.dx));
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 3.1, height: r * 1.15),
      Paint()..color = _black.withValues(alpha: 0.16),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 2.7, height: r * 0.85),
      Paint()..color = _black.withValues(alpha: 0.30),
    );
    canvas.restore();

    // Invuln blink: skip the body on the "off" phase, but always keep shadow.
    final blinkHidden = t.invuln > 0 && t.invuln.floor().isOdd;
    if (blinkHidden) return;

    final flashK = t.flash.clamp(0.0, 1.0);
    // The winner pulse brightens the whole tank toward white on top of any hit
    // flash, so a victorious hull visibly glows.
    final vic = t.victory.clamp(0.0, 1.0);
    final fill = _blend(t.color, _white, (flashK * 0.7 + vic * 0.45).clamp(0.0, 1.0));

    if (vic > 0) _drawVictoryPulse(canvas, t, r, vic);
    _drawTracks(canvas, t, r, side, up);
    _drawHull(canvas, t, r, side, up, fill, flashK);
    _drawTurretAndBarrel(canvas, t, r, fill);
    // Reload ring (drawn over the turret, under the pips) — only while re-arming,
    // so the scarce-shot economy is visible: kids see the barrel "filling up"
    // before it can fire again. A charging shot owns the aim-guide gauge instead.
    if (t.reload < 0.999 && !t.precision) _drawReloadRing(canvas, t, r);
    _drawHealthPips(canvas, t, r, side, up);
  }

  /// A re-arm arc sweeping around the turret as the breech reloads: a dim backing
  /// ring + a hot arc that fills 0→full, flashing bright as it tops off. Reads as
  /// "the gun is loading" so a player learns to wait for the shot, not mash.
  static void _drawReloadRing(Canvas canvas, TankView t, double r) {
    final pivot = _turretPivot(t);
    final ringR = r * (_turretR + 0.34);
    final frac = t.reload.clamp(0.0, 1.0);
    final rect = Rect.fromCircle(center: pivot, radius: ringR);
    // Dim backing ring.
    canvas.drawCircle(
      pivot,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.1)
        ..color = _black.withValues(alpha: 0.35),
    );
    // Hot fill arc from straight up; warms cool→hot and brightens as it tops off.
    final hot = _blend(_muzzleCore, _white, frac * 0.5);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.1)
        ..strokeCap = StrokeCap.round
        ..color = hot.withValues(alpha: (0.55 + 0.4 * frac).clamp(0.0, 1.0)),
    );
    // A bright "loaded!" tick blooms at the top as the ring closes.
    if (frac > 0.92) {
      canvas.drawCircle(
        pivot.translate(0, -ringR),
        r * 0.12,
        Paint()..color = _white.withValues(alpha: (frac - 0.92) / 0.08),
      );
    }
  }

  /// A bright celebration halo + ring under/around the winning tank's turret so
  /// the round ends on a clear "this one won" beat. [vic] 0..1 scales it.
  static void _drawVictoryPulse(Canvas canvas, TankView t, double r, double vic) {
    final pivot = _turretPivot(t);
    final glow = _blend(t.color, _white, 0.5);
    canvas.drawCircle(
      pivot,
      r * (1.8 + 0.5 * vic),
      Paint()..color = glow.withValues(alpha: 0.22 * vic),
    );
    canvas.drawCircle(
      pivot,
      r * (1.4 + 0.3 * vic),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.12)
        ..color = glow.withValues(alpha: (0.7 * vic).clamp(0.0, 1.0)),
    );
  }

  // ── Downed wreck (burning hulk + smoke column) ─────────────────────────────
  /// A destroyed tank's smoldering remains: a scorched footprint, a darkened
  /// caved hull, a drooping snapped barrel, flickering embers and a rising smoke
  /// column — so a KO'd tank leaves a wreck instead of popping out of existence.
  /// All cheap solid fills; guards its inputs and never throws.
  static void drawWreck(Canvas canvas, WreckView w) {
    final r = _baseR * w.scale;
    if (r <= 0) return;
    final up = w.edge.outward;
    final side = w.edge.along;
    final pivot = w.base + up * (r * 0.62); // hull center (matches live tank)
    final age = math.max(0.0, w.age);
    // The wreck eases in over the first moment so it doesn't pop.
    final settle = (age / 0.25).clamp(0.0, 1.0);

    // Scorched ground footprint under the hulk.
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(math.atan2(side.dy, side.dx));
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 3.0, height: r * 1.2),
      Paint()..color = _scorch.withValues(alpha: 0.5 * settle),
    );
    // Caved, charred hull body (a dark husk in a dim player tint).
    final husk = _blend(_blend(w.color, _black, 0.72), _scorch, 0.3);
    final hw = r * _hullW * 0.92, hh = r * _hullH * 0.82;
    final rect = Rect.fromCenter(center: Offset.zero, width: hw, height: hh);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r * _hullRadius)),
      Paint()..color = husk.withValues(alpha: settle),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r * _hullRadius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.06)
        ..color = _black.withValues(alpha: 0.6 * settle),
    );
    canvas.restore();

    // Snapped barrel stub drooping off the last aim direction.
    final dir = Offset(math.cos(w.aimAngle), math.sin(w.aimAngle));
    final droop = Offset(dir.dx, dir.dy + 0.5); // sags downward
    final dl = droop.distance < 1e-3 ? const Offset(0, 1) : droop / droop.distance;
    final stub = pivot + dl * (r * _barrelLen * 0.7);
    canvas.drawLine(
      pivot,
      stub,
      Paint()
        ..color = _steelDark.withValues(alpha: settle)
        ..strokeWidth = r * _barrelW
        ..strokeCap = StrokeCap.round,
    );

    // Flickering embers clustered on the hull.
    final flick = 0.5 + 0.5 * math.sin(w.t * 12.0);
    for (var i = 0; i < 3; i++) {
      final off = Offset(
        math.cos(w.t * 3 + i * 2.1) * r * 0.4,
        math.sin(w.t * 2.4 + i) * r * 0.22,
      );
      canvas.drawCircle(
        pivot + off,
        r * (0.10 + 0.05 * flick),
        Paint()..color = _embers.withValues(alpha: (0.5 + 0.4 * flick) * settle),
      );
    }

    _drawSmokeColumn(canvas, pivot, r, up, age, w.t);
  }

  /// A rising, widening, fading smoke column above a wreck. A handful of stacked
  /// soft puffs drift along the tank's "up" (away from the field) with a gentle
  /// sway — a brief plume that reads without a per-frame blur.
  static void _drawSmokeColumn(
      Canvas canvas, Offset hull, double r, Offset up, double age, double t) {
    const puffs = 5;
    for (var i = 0; i < puffs; i++) {
      // Each puff is at a phase along the column; phase scrolls upward with time.
      final phase = ((i / puffs) + t * 0.18) % 1.0;
      final rise = up * (r * (0.6 + 3.2 * phase));
      final sway = Offset(-up.dy, up.dx) * (math.sin(t * 1.6 + i) * r * 0.3 * phase);
      final at = hull + rise + sway;
      final grow = r * (0.45 + 0.9 * phase);
      // Fade in quickly, out toward the top; gated by how long it has burned.
      final ramp = (age / 0.4).clamp(0.0, 1.0);
      final alpha = (0.34 * (1.0 - phase) * ramp).clamp(0.0, 1.0);
      if (alpha <= 0.01) continue;
      final shade = _blend(_smoke, _black, 0.3 * (1.0 - phase));
      canvas.drawCircle(at, grow, Paint()..color = shade.withValues(alpha: alpha));
    }
  }

  static void _drawTracks(
      Canvas canvas, TankView t, double r, Offset side, Offset up) {
    // Two track strips offset slightly out from the hull center, along the edge.
    final trackCenter = t.base + up * (r * 0.18);
    canvas.save();
    canvas.translate(trackCenter.dx, trackCenter.dy);
    canvas.rotate(math.atan2(side.dy, side.dx));
    final w = r * _trackW, h = r * _trackH;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final track = Paint()
      ..shader = Gradient.linear(
        rect.topLeft,
        rect.bottomLeft,
        [_steelDark, _blend(_steelDark, _black, 0.5)],
      );
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(h * 0.5)), track);
    // Tread segments.
    final tread = Paint()
      ..color = _black.withValues(alpha: 0.5)
      ..strokeWidth = math.max(1.0, h * 0.16)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= _trackSegments; i++) {
      final x = -w / 2 + w * (i / _trackSegments);
      canvas.drawLine(Offset(x, -h / 2), Offset(x, h / 2), tread);
    }
    // Road wheels hint (lighter dots).
    final wheel = Paint()..color = _blend(_steel, _black, 0.45);
    for (var i = 0; i < _trackSegments; i++) {
      final x = -w / 2 + w * ((i + 0.5) / _trackSegments);
      canvas.drawCircle(Offset(x, 0), h * 0.22, wheel);
    }
    canvas.restore();
  }

  static void _drawHull(Canvas canvas, TankView t, double r, Offset side,
      Offset up, Color fill, double flashK) {
    final hullCenter = t.base + up * (r * 0.62);
    canvas.save();
    canvas.translate(hullCenter.dx, hullCenter.dy);
    canvas.rotate(math.atan2(side.dy, side.dx));
    final w = r * _hullW, h = r * _hullH;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(r * _hullRadius));

    // Metallic vertical gradient: bright top → mid color → dark belly.
    final body = Paint()
      ..shader = Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        [
          _blend(fill, _white, 0.35),
          fill,
          _blend(fill, _black, 0.45),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRRect(rrect, body);

    // Top highlight strip: a soft translucent sheen (rounded RRect, no blur).
    final hi = Paint()..color = _white.withValues(alpha: 0.18 + flashK * 0.34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(0, -h * 0.28), width: w * 0.78, height: h * 0.22),
        Radius.circular(h * 0.18),
      ),
      hi,
    );

    // Dark outline.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, r * 0.07)
        ..color = _blend(_black, fill, 0.15).withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  static void _drawTurretAndBarrel(
      Canvas canvas, TankView t, double r, Color fill) {
    final dir = Offset(math.cos(t.aimAngle), math.sin(t.aimAngle));
    final pivot = _turretPivot(t);

    // Recoil pulls the whole turret+barrel back along the aim axis.
    final recoilShift = dir * (-r * _recoilKick * t.recoil);
    final tp = pivot + recoilShift;

    // Barrel: a thick rounded bar from the turret to the muzzle.
    final muzzle = tp + dir * (r * _barrelLen);
    final barrelBack = Paint()
      ..color = _steelDark
      ..strokeWidth = r * _barrelW * 1.25
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tp, muzzle, barrelBack);
    final barrel = Paint()
      ..shader = Gradient.linear(
        tp,
        muzzle,
        [_blend(_steel, _white, 0.2), _steelDark],
      )
      ..strokeWidth = r * _barrelW
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tp, muzzle, barrel);
    // Muzzle brake ring.
    canvas.drawCircle(muzzle, r * _barrelW * 0.62,
        Paint()..color = _blend(_steel, _black, 0.3));

    // Turret dome: radial metallic gradient in the player color.
    final turretR = r * _turretR;
    final dome = Paint()
      ..shader = Gradient.radial(
        tp.translate(-turretR * 0.3, -turretR * 0.35),
        turretR * 1.4,
        [
          _blend(fill, _white, 0.45),
          fill,
          _blend(fill, _black, 0.4),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawCircle(tp, turretR, dome);
    canvas.drawCircle(
      tp,
      turretR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, r * 0.06)
        ..color = _blend(_black, fill, 0.15).withValues(alpha: 0.85),
    );
    // Hatch detail.
    canvas.drawCircle(
        tp.translate(-turretR * 0.18, -turretR * 0.18),
        turretR * 0.32,
        Paint()..color = _blend(fill, _black, 0.3));

    // Muzzle flash on fire.
    if (t.muzzle > 0.01) {
      _drawMuzzleFlash(canvas, muzzle, dir, r, t.muzzle);
    }
  }

  static void _drawMuzzleFlash(
      Canvas canvas, Offset muzzle, Offset dir, double r, double amt) {
    final a = amt.clamp(0.0, 1.0);
    final len = r * (1.4 + 1.6 * a);
    final perp = Offset(-dir.dy, dir.dx);
    final tip = muzzle + dir * len;
    // Outer glow: two stacked translucent circles (wide+faint, tight+brighter)
    // approximate the bloom without a per-shot blur.
    canvas.drawCircle(
      muzzle,
      r * (1.1 + 0.9 * a),
      Paint()..color = _muzzleCore.withValues(alpha: 0.22 * a),
    );
    canvas.drawCircle(
      muzzle,
      r * (0.7 + 0.6 * a),
      Paint()..color = _muzzleCore.withValues(alpha: 0.4 * a),
    );
    // Star burst (flame petals).
    final flame = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(muzzle.dx + perp.dx * r * 0.5, muzzle.dy + perp.dy * r * 0.5)
      ..lineTo(muzzle.dx - perp.dx * r * 0.5, muzzle.dy - perp.dy * r * 0.5)
      ..close();
    canvas.drawPath(flame, Paint()..color = _muzzleCore.withValues(alpha: a));
    final innerTip = muzzle + dir * (len * 0.62);
    final inner = Path()
      ..moveTo(innerTip.dx, innerTip.dy)
      ..lineTo(muzzle.dx + perp.dx * r * 0.28, muzzle.dy + perp.dy * r * 0.28)
      ..lineTo(muzzle.dx - perp.dx * r * 0.28, muzzle.dy - perp.dy * r * 0.28)
      ..close();
    canvas.drawPath(inner, Paint()..color = _muzzleHot.withValues(alpha: a));
  }

  static void _drawHealthPips(
      Canvas canvas, TankView t, double r, Offset side, Offset up) {
    if (t.maxHp <= 0) return;
    // Pips sit just outward of the tank (toward the screen edge), laid along
    // the edge axis so they never overlap the hull.
    final row = t.base + up * (r * 1.55);
    final gap = r * 0.5;
    final start = -(t.maxHp - 1) / 2.0 * gap;
    for (var i = 0; i < t.maxHp; i++) {
      final c = row + side * (start + i * gap);
      final filled = i < t.hp;
      final pr = r * 0.18;
      // Backing.
      canvas.drawCircle(
          c, pr * 1.35, Paint()..color = _black.withValues(alpha: 0.5));
      canvas.drawCircle(
        c,
        pr,
        Paint()
          ..color = filled
              ? _blend(t.color, _white, 0.15)
              : _white.withValues(alpha: 0.16),
      );
      if (filled) {
        canvas.drawCircle(
          c,
          pr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, pr * 0.3)
            ..color = _white.withValues(alpha: 0.6),
        );
      }
    }
  }

  // ── Shell + trail ───────────────────────────────────────────────────────────
  static void drawShell(Canvas canvas, ShellView s) {
    // Smoke/spark trail (oldest faintest). A bright hot core over a wider, soft
    // glow streak so the shell reads as a fast tracer.
    final n = s.trail.length;
    if (n >= 2) {
      // A wide, faint stroke under the crisp tracer fakes the soft glow without
      // a per-segment blur (cheap layered-stroke trick).
      final glow = Paint()..strokeCap = StrokeCap.round;
      final paint = Paint()..strokeCap = StrokeCap.round;
      for (var i = 0; i < n - 1; i++) {
        final f = 1 - i / n; // newest strongest
        glow
          ..color =
              _blend(s.color, _shellHot, 0.5).withValues(alpha: (0.35 * f).clamp(0.0, 1.0))
          ..strokeWidth = (3 + 8 * f);
        canvas.drawLine(s.trail[i], s.trail[i + 1], glow);
        paint
          ..color = _blend(s.color, _shellHot, 0.5)
              .withValues(alpha: (0.7 * f).clamp(0.0, 1.0))
          ..strokeWidth = (1.5 + 5 * f);
        canvas.drawLine(s.trail[i], s.trail[i + 1], paint);
      }
      // Faint smoke puffs behind.
      final smoke = Paint();
      for (var i = 0; i < n; i += 2) {
        final f = 1 - i / n;
        smoke.color = _white.withValues(alpha: (0.06 * f).clamp(0.0, 1.0));
        canvas.drawCircle(s.trail[i], (2 + 4 * (1 - f)), smoke);
      }
    }

    // Glow + hot core: two stacked translucent halos (wide+faint, tight+stronger)
    // replace the per-shell blur, then the solid body + bright center.
    final halo = _blend(s.color, _shellHot, 0.5);
    canvas.drawCircle(
        s.pos, _shellR * 2.2, Paint()..color = halo.withValues(alpha: 0.22));
    canvas.drawCircle(
        s.pos, _shellR * 1.5, Paint()..color = halo.withValues(alpha: 0.4));
    canvas.drawCircle(s.pos, _shellR, Paint()..color = s.color);
    canvas.drawCircle(s.pos, _shellR * 0.5, Paint()..color = _shellHot);
  }

  // ── Geometry shared with gameplay (kept here so visuals + hit-tests agree) ──
  static const double _baseR = 26; // logical base radius (scaled per tank)
  static const double _shellR = 7;

  static Offset _turretPivot(TankView t) {
    final r = _baseR * t.scale;
    return t.base + t.edge.outward * (r * 0.62);
  }

  static Offset _muzzlePoint(TankView t) {
    final r = _baseR * t.scale;
    final dir = Offset(math.cos(t.aimAngle), math.sin(t.aimAngle));
    return _turretPivot(t) + dir * (r * _barrelLen);
  }

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;
}
