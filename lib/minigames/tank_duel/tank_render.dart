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
  final bool precision; // true while the player holds to slow-aim (fine-tune)

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
  static const Color _crateWood = Color(0xFFB07C3C);
  static const Color _crateWoodDark = Color(0xFF6E4A20);
  static const Color _crateBand = Color(0xFF3A2A14);
  static const Color _muzzleHot = Color(0xFFFFF4C2);
  static const Color _muzzleCore = Color(0xFFFFC23C);
  static const Color _shellHot = Color(0xFFFFE6A0);
  static const Color _embers = Color(0xFFFF9A3C);

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
    _drawEmbers(canvas, embers, size, t);
    _drawVignette(canvas, size);
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
  /// holds to slow-aim ([t.precision]) the guide reaches further and brightens
  /// and the reticle gains crosshair ticks, so a deliberate precision shot reads
  /// clearly distinct from the idle sweep.
  static void drawAimGuide(Canvas canvas, TankView t) {
    final dir = Offset(math.cos(t.aimAngle), math.sin(t.aimAngle));
    final muzzle = _muzzlePoint(t);
    final reach = _aimGuideLen * (t.precision ? 1.5 : 1.0);
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
    }
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
    final fill = _blend(t.color, _white, flashK * 0.7);

    _drawTracks(canvas, t, r, side, up);
    _drawHull(canvas, t, r, side, up, fill, flashK);
    _drawTurretAndBarrel(canvas, t, r, fill);
    _drawHealthPips(canvas, t, r, side, up);
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
