import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Where an archer is anchored. Drives stance + which way the grass strip and
/// aim guide read so 1–4 archers all sit correctly on their screen edge.
enum ArcherSide { bottom, top, left, right }

extension ArcherSideGeometry on ArcherSide {
  /// Unit vector pointing away from the playfield (the archer's local "down").
  Offset get outward => switch (this) {
        ArcherSide.bottom => const Offset(0, 1),
        ArcherSide.top => const Offset(0, -1),
        ArcherSide.left => const Offset(-1, 0),
        ArcherSide.right => const Offset(1, 0),
      };
}

/// Kind of target, mirrored from the sim so the renderer can style each one.
enum TargetKind { plain, gold, bomb }

/// Immutable snapshot of one archer handed to the renderer. Carries only what
/// is needed to draw — no gameplay coupling, no mutation.
class ArcherView {
  final Offset base; // pelvis/render anchor in arena px
  final Color color;
  final ArcherSide side;
  final double facing; // -1 / +1
  final double aimAngle; // bow aim in radians (screen space)
  final double draw; // 0..1 bow draw / power (1 = fully drawn, about to loose)
  final int combo; // current hit streak (0 = none)
  final double scale; // body scale factor
  final double loose; // 0..1 recent-loose flash (1 fresh → 0), kicks the bow

  const ArcherView({
    required this.base,
    required this.color,
    required this.side,
    required this.facing,
    required this.aimAngle,
    required this.draw,
    required this.combo,
    required this.scale,
    this.loose = 0,
  });
}

/// Immutable snapshot of one target balloon.
class TargetView {
  final Offset pos;
  final Color color;
  final double radius;
  final double bobPhase; // for the gentle squash/sway
  final double popT; // 0 = whole, >0 = popping (1 → 0 as it bursts)
  final TargetKind kind;
  final double sparklePhase; // animates the golden glint
  final double fuse; // gold's remaining life 1→0 (a shrinking timer ring)

  const TargetView({
    required this.pos,
    required this.color,
    required this.radius,
    required this.bobPhase,
    this.popT = 0,
    this.kind = TargetKind.plain,
    this.sparklePhase = 0,
    this.fuse = 1,
  });
}

/// Immutable snapshot of one arrow (in flight or stuck) + its recent trail
/// samples (newest first).
class ArrowView {
  final Offset pos;
  final Offset dir; // unit heading
  final Color color;
  final List<Offset> trail;
  final double stuck; // 0 = flying, >0..1 = embedded fade (1 fresh → 0 gone)

  const ArrowView({
    required this.pos,
    required this.dir,
    required this.color,
    required this.trail,
    this.stuck = 0,
  });
}

/// Immutable per-player HUD snapshot: where to draw it (the player's zone +
/// rotation), the score, and the remaining quiver ammo + objective.
class HudView {
  final Rect zone; // normalized 0..1 player zone
  final int rotationQuarters; // 0 upright (bottom) / 2 flipped (top)
  final Color color;
  final num score;
  final int ammo;
  final int maxAmmo;
  final int playerNumber; // 1-based, for the label

  const HudView({
    required this.zone,
    required this.rotationQuarters,
    required this.color,
    required this.score,
    required this.ammo,
    required this.maxAmmo,
    required this.playerNumber,
  });
}

/// Pure-Canvas rendering for ArcherPop / Target Range. Holds NO game state and
/// never mutates the simulation — callers pass plain value snapshots. Every
/// method guards its own inputs and never throws, so it is safe from `render`.
class ArcherRenderer {
  ArcherRenderer._();

  // ── Range palette (no magic colors inline elsewhere) ───────────────────────
  static const Color _skyTop = Color(0xFF1B2A52);
  static const Color _skyMid = Color(0xFF3E5C93);
  static const Color _skyLow = Color(0xFF8FB7D8);
  static const Color _sun = Color(0xFFFFE7AE);
  static const Color _hillFar = Color(0xFF6E83A8);
  static const Color _hillMid = Color(0xFF4E6E7A);
  static const Color _hillNear = Color(0xFF3C5A54);
  static const Color _grassTop = Color(0xFF4F8C46);
  static const Color _grassLow = Color(0xFF2E5A2E);
  static const Color _cloud = Color(0x33FFFFFF);
  static const Color _vignette = Color(0x66000000);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _bowWood = Color(0xFF8A5A2B);
  static const Color _bowWoodHi = Color(0xFFC79A5C);
  static const Color _string = Color(0xFFEDE6D2);
  static const Color _shaft = Color(0xFFE9D9B8);
  static const Color _shaftDark = Color(0xFF9A7B45);
  static const Color _fletch = Color(0xFFF24B3E);
  static const Color _balloonShine = Color(0x88FFFFFF);
  static const Color _arrowHead = Color(0xFFCBD3DE);
  static const Color _gold = Color(0xFFFFD24A);
  static const Color _goldHi = Color(0xFFFFF3C8);
  static const Color _windTint = Color(0xFFCFE6FF);
  static const Color _barrierFill = Color(0xFF6A5236);
  static const Color _barrierHi = Color(0xFF9C7A4E);
  static const Color _bomb = Color(0xFF2A2A2E);
  static const Color _bombHi = Color(0xFFFF5A52);
  static const Color _hudBg = Color(0xAA0A1428);

  // ── Tuning (fractions / px) ────────────────────────────────────────────────
  static const double _bowRadius = 30; // bow limb radius at scale 1
  static const double _bowSpan = 1.5; // limb arc half-angle (radians)
  static const double _drawDepth = 13; // px the string pulls back at full draw
  static const double _arrowLen = 26; // drawn arrow shaft length
  static const int _hillBands = 3;
  static const double _looseKick = 6; // px the riser snaps forward on a loose
  static const double _windRef = 64; // wind speed mapped to full streak strength

  // ── Background: sky gradient → sun glow → layered hills → grass strip ───────
  static void drawRange(
    Canvas canvas,
    Size size, {
    required double horizonY,
    required Offset sun,
    required List<Offset> clouds,
    required double t,
  }) {
    final sky = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, horizonY),
        const [_skyTop, _skyMid, _skyLow],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, horizonY), sky);

    _drawSun(canvas, sun, size);
    _drawClouds(canvas, clouds, size, t);
    _drawHills(canvas, size, horizonY);
    _drawGrass(canvas, size, horizonY);
    _drawVignette(canvas, size);
  }

  static void _drawSun(Canvas canvas, Offset sun, Size size) {
    final glowR = size.shortestSide * 0.5;
    canvas.drawCircle(
      sun,
      glowR,
      Paint()
        ..shader = Gradient.radial(
          sun,
          glowR,
          const [Color(0x55FFE7AE), Color(0x00FFE7AE)],
        ),
    );
    canvas.drawCircle(sun, size.shortestSide * 0.06, Paint()..color = _sun);
  }

  static void _drawClouds(
      Canvas canvas, List<Offset> clouds, Size size, double t) {
    if (clouds.isEmpty) return;
    final paint = Paint()..color = _cloud;
    for (var i = 0; i < clouds.length; i++) {
      final c = clouds[i];
      final span = size.width + 240;
      final x = ((c.dx + t * (8 + (i % 3) * 4)) % span) - 120;
      final y = c.dy;
      final w = 70.0 + (i % 3) * 34;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: w * 0.46),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x + w * 0.3, y + 4),
            width: w * 0.7,
            height: w * 0.36),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x - w * 0.26, y + 3),
            width: w * 0.55,
            height: w * 0.30),
        paint,
      );
    }
  }

  static void _drawHills(Canvas canvas, Size size, double horizonY) {
    const colors = [_hillFar, _hillMid, _hillNear];
    for (var band = 0; band < _hillBands; band++) {
      final f = band / (_hillBands - 1);
      final baseY = horizonY - size.height * (0.06 * (1 - f));
      final amp = size.height * (0.03 + band * 0.022);
      final waves = 2 + band;
      final path = Path()..moveTo(0, baseY);
      for (var x = 0.0; x <= size.width; x += size.width / 40) {
        final y = baseY -
            (math.sin((x / size.width) * math.pi * waves + band * 1.7) * 0.5 +
                    0.5) *
                amp;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, horizonY + size.height)
        ..lineTo(0, horizonY + size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = colors[band]);
    }
  }

  static void _drawGrass(Canvas canvas, Size size, double horizonY) {
    final ground = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, horizonY),
        Offset(size.width / 2, size.height),
        const [_grassTop, _grassLow],
      );
    canvas.drawRect(Rect.fromLTRB(0, horizonY, size.width, size.height), ground);

    final blade = Paint()
      ..color = _white.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    const rows = 7;
    for (var i = 1; i <= rows; i++) {
      final f = i / rows;
      final y = horizonY + (size.height - horizonY) * (f * f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), blade);
    }
  }

  static void _drawVignette(Canvas canvas, Size size) {
    final r = size.longestSide * 0.74;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.5),
          r,
          const [Color(0x00000000), _vignette],
          const [0.6, 1.0],
        ),
    );
  }

  // ── Wind: drifting streaks across the field + a small heading banner ─────────

  static void drawWindStreaks(
    Canvas canvas,
    Size size,
    List<Offset> anchors,
    double windX,
    double t,
  ) {
    final strength = (windX.abs() / _windRef).clamp(0.0, 1.0);
    if (strength <= 0.02) return;
    final dirSign = windX >= 0 ? 1.0 : -1.0;
    // Deepest sub-layer: a faint, slow ambient vector field drifting in the wind
    // direction behind all gameplay, so the breeze reads even with no anchors
    // near. Deterministic (index + sin) — no random, no per-entity blur.
    _drawAmbientWindField(canvas, size, dirSign, strength, t);
    if (anchors.isEmpty) return;
    final len = 26.0 + 40.0 * strength;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6;
    final span = size.width + len * 2;
    for (var i = 0; i < anchors.length; i++) {
      final a = anchors[i];
      final speed = (60 + (i % 4) * 30) * (0.4 + strength);
      final raw = a.dx + dirSign * t * speed;
      final x = ((raw % span) + span) % span - len;
      final y = a.dy;
      final tail = Offset(x - dirSign * len, y + math.sin(t * 2 + i) * 2);
      paint.color = _windTint
          .withValues(alpha: (0.05 + 0.12 * strength).clamp(0.0, 1.0));
      canvas.drawLine(tail, Offset(x, y), paint);
    }
  }

  /// Faint full-field wind streaks drifting across the whole arena in the wind
  /// direction. Lanes are derived deterministically from index (no anchors,
  /// no random); far/upper lanes drift slower + fainter for a parallax breeze.
  static void _drawAmbientWindField(Canvas canvas, Size size, double dirSign,
      double strength, double t) {
    final len = (size.width * 0.05) + (size.width * 0.05) * strength;
    final span = size.width + len * 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.1;
    const rows = 9;
    for (var i = 0; i < rows; i++) {
      final lane = (i + 0.5) / rows; // 0 (top) .. 1 (bottom)
      final y = size.height * (0.06 + 0.86 * lane) +
          math.sin(t * 0.8 + i * 1.7) * (size.height * 0.008);
      final speed = (12.0 + (i % 4) * 6.0) * (0.5 + strength);
      final raw = size.width * lane * 1.7 + dirSign * t * speed;
      final x = ((raw % span) + span) % span - len;
      final a = (0.015 + 0.045 * strength) * (0.5 + 0.5 * lane);
      paint.color = _windTint.withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawLine(Offset(x - dirSign * len, y), Offset(x, y), paint);
    }
  }

  /// A small top banner showing wind heading + strength so players lead a shot.
  static void drawWindBanner(Canvas canvas, Size size, double windX) {
    final strength = (windX.abs() / _windRef).clamp(0.0, 1.0);
    final center = Offset(size.width * 0.5, size.height * 0.052);
    final dirSign = windX >= 0 ? 1.0 : -1.0;
    final w = size.width * 0.30;
    final h = size.height * 0.034;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.5),
    );
    canvas.drawRRect(rect, Paint()..color = _black.withValues(alpha: 0.28));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _windTint.withValues(alpha: 0.35),
    );

    final arrowLen = w * (0.16 + 0.5 * strength);
    final cy = center.dy;
    final from = Offset(center.dx - dirSign * arrowLen * 0.5, cy);
    final to = Offset(center.dx + dirSign * arrowLen * 0.5, cy);
    final col = Color.lerp(_windTint, _gold, strength)!;
    final body = Paint()
      ..color = col.withValues(alpha: 0.9)
      ..strokeWidth = math.max(2.0, h * 0.16)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, body);
    final back = to - Offset(dirSign * h * 0.34, 0);
    final head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(back.dx, back.dy - h * 0.24)
      ..lineTo(back.dx, back.dy + h * 0.24)
      ..close();
    canvas.drawPath(head, Paint()..color = col);
  }

  // ── Barrier (the arc-over-me wall) ──────────────────────────────────────────

  /// A solid wooden plank that eats a flat arrow, forcing an arc. Drawn under
  /// its target. [scale] sizes the plank seam thickness.
  static void drawBarrier(Canvas canvas, Rect rect, double scale) {
    if (rect.isEmpty) return;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(3 * scale));
    // Drop shadow under the plank.
    canvas.drawRRect(
      rr.shift(Offset(0, 2 * scale)),
      Paint()..color = _black.withValues(alpha: 0.3),
    );
    canvas.drawRRect(rr, Paint()..color = _barrierFill);
    // Top highlight strip so the plank reads as solid.
    final hi = Rect.fromLTWH(
        rect.left, rect.top, rect.width, math.max(2.0, rect.height * 0.3));
    canvas.drawRRect(
      RRect.fromRectAndRadius(hi, Radius.circular(3 * scale)),
      Paint()..color = _barrierHi.withValues(alpha: 0.8),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, 1.4 * scale)
        ..color = _black.withValues(alpha: 0.4),
    );
  }

  // ── Target balloon ──────────────────────────────────────────────────────────

  /// A bobbing target. Plain = a player-colored balloon; GOLD = small, metallic
  /// + a shrinking fuse ring (it floats off soon); BOMB = a black orb with a lit
  /// fuse + a danger ring (hitting it costs points). A popping target shows a
  /// quick burst instead.
  static void drawTarget(Canvas canvas, TargetView b) {
    final r = b.radius;
    if (r <= 0) return;

    if (b.popT > 0) {
      final c = switch (b.kind) {
        TargetKind.gold => _gold,
        TargetKind.bomb => _bombHi,
        TargetKind.plain => b.color,
      };
      _drawPopFlash(canvas, b.pos, r, c, b.popT);
      return;
    }

    if (b.kind == TargetKind.bomb) {
      _drawBomb(canvas, b);
      return;
    }

    final golden = b.kind == TargetKind.gold;
    final squash = 1.0 + math.sin(b.bobPhase) * 0.05;
    final sway = math.sin(b.bobPhase * 0.7) * r * 0.12;
    final center = b.pos.translate(sway, 0);

    canvas.save();
    canvas.translate(center.dx, center.dy);

    if (golden) {
      canvas.drawCircle(Offset.zero, r * 1.7,
          Paint()..color = _gold.withValues(alpha: 0.12));
      canvas.drawCircle(Offset.zero, r * 1.34,
          Paint()..color = _gold.withValues(alpha: 0.2));
      // Shrinking fuse ring: how long the prize is still catchable.
      _drawTimerRing(canvas, r, b.fuse, _goldHi);
    }

    // String tail with a small knot.
    final stringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, r * 0.06)
      ..strokeCap = StrokeCap.round
      ..color = _string.withValues(alpha: 0.85);
    final tail = Path()..moveTo(0, r * 0.92);
    final tlen = r * 1.5;
    for (var i = 1; i <= 6; i++) {
      final f = i / 6;
      final y = r * 0.92 + tlen * f;
      final x = math.sin(b.bobPhase + f * 4) * r * 0.18 * f;
      tail.lineTo(x, y);
    }
    canvas.drawPath(tail, stringPaint);

    final bulb = Path()
      ..addOval(Rect.fromCenter(
          center: Offset.zero, width: r * 2 / squash, height: r * 2 * squash))
      ..moveTo(-r * 0.22, r * 0.86 * squash)
      ..lineTo(0, r * 1.04 * squash)
      ..lineTo(r * 0.22, r * 0.86 * squash)
      ..close();

    final baseColor = golden ? _gold : b.color;
    final body = Paint()
      ..shader = Gradient.radial(
        Offset(-r * 0.32, -r * 0.38),
        r * 1.5,
        [
          _blend(baseColor, _white, golden ? 0.55 : 0.4),
          baseColor,
          _blend(baseColor, _black, golden ? 0.3 : 0.4),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawPath(bulb, body);

    canvas.drawPath(
      bulb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.07)
        ..color = _blend(baseColor, _black, 0.35).withValues(alpha: 0.8),
    );

    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(-r * 0.3, -r * 0.2), width: r * 0.42, height: r * 0.9),
      Paint()..color = _balloonShine.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
        Offset(-r * 0.38, -r * 0.42), r * 0.14, Paint()..color = _white);

    if (golden) {
      _drawSparkle(canvas, Offset(r * 0.2, -r * 0.1), r * 0.4, b.sparklePhase);
    }

    canvas.drawCircle(Offset(0, r * 0.96 * squash), r * 0.16,
        Paint()..color = _blend(baseColor, _black, 0.25));

    canvas.restore();
  }

  /// A black bomb decoy: a dark orb with a glossy rim, a danger ring and a lit,
  /// sparking fuse so it reads clearly as "do NOT shoot me".
  static void _drawBomb(Canvas canvas, TargetView b) {
    final r = b.radius;
    final center = b.pos;
    canvas.save();
    canvas.translate(center.dx, center.dy);

    // Pulsing danger halo.
    final pulse = 0.5 + 0.5 * math.sin(b.bobPhase * 2);
    canvas.drawCircle(
      Offset.zero,
      r * (1.35 + 0.12 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, r * 0.12)
        ..color = _bombHi.withValues(alpha: (0.4 + 0.3 * pulse).clamp(0.0, 1.0)),
    );

    // Body.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = Gradient.radial(
          Offset(-r * 0.3, -r * 0.35),
          r * 1.5,
          [_blend(_bomb, _white, 0.4), _bomb, _black],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.07)
        ..color = _bombHi.withValues(alpha: 0.5),
    );
    // Specular dot.
    canvas.drawCircle(Offset(-r * 0.34, -r * 0.36), r * 0.16,
        Paint()..color = _white.withValues(alpha: 0.8));

    // Fuse cap + a sparking tip.
    final fuseBase = Offset(0, -r * 0.96);
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(0, -r * 1.06), width: r * 0.36, height: r * 0.34),
      Paint()..color = _blend(_bomb, _white, 0.25),
    );
    final spark = Offset(math.sin(b.sparklePhase * 3) * r * 0.18, -r * 1.28);
    canvas.drawLine(
      fuseBase,
      spark,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.08)
        ..color = _gold,
    );
    canvas.drawCircle(spark, r * (0.12 + 0.06 * pulse),
        Paint()..color = _goldHi);

    canvas.restore();
  }

  /// A countdown ring drawn around a (gold) target showing fraction [f] left.
  static void _drawTimerRing(Canvas canvas, double r, double f, Color color) {
    final frac = f.clamp(0.0, 1.0);
    if (frac <= 0) return;
    final rect = Rect.fromCircle(center: Offset.zero, radius: r * 1.5);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.12)
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.8),
    );
  }

  static void _drawPopFlash(
      Canvas canvas, Offset at, double r, Color color, double popT) {
    final p = popT.clamp(0.0, 1.0);
    final grow = 1.0 + (1 - p) * 1.4;
    // Soft glow halo so the hit feels juicy: two stacked translucent fills that
    // bloom outward and fade with the flash (no per-entity blur — STACKED fills).
    final glow = color.withValues(alpha: (0.30 * p).clamp(0.0, 1.0));
    canvas.drawCircle(at, r * (grow + 0.55), Paint()..color = glow);
    canvas.drawCircle(
      at,
      r * (grow + 0.18),
      Paint()..color = color.withValues(alpha: (0.22 * p).clamp(0.0, 1.0)),
    );
    canvas.drawCircle(
      at,
      r * grow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.22 * p)
        ..color = color.withValues(alpha: (0.8 * p).clamp(0.0, 1.0)),
    );
    canvas.drawCircle(
      at,
      r * 0.5 * p,
      Paint()..color = _white.withValues(alpha: (0.6 * p).clamp(0.0, 1.0)),
    );
  }

  static void _drawSparkle(
      Canvas canvas, Offset at, double r, double phase) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(phase);
    final paint = Paint()
      ..color = _goldHi
      ..strokeWidth = math.max(0.8, r * 0.2)
      ..strokeCap = StrokeCap.round;
    final s = 0.6 + 0.4 * math.sin(phase * 2.0).abs();
    canvas.drawLine(Offset(-r * s, 0), Offset(r * s, 0), paint);
    canvas.drawLine(Offset(0, -r * s), Offset(0, r * s), paint);
    canvas.drawCircle(Offset.zero, r * 0.18, Paint()..color = _white);
    canvas.restore();
  }

  // ── Aim preview (the drag-aim trajectory + power) ────────────────────────────

  /// While a player is drawing, show a dotted ARC of where the arrow would land
  /// (the gravity+wind path computed by the sim) fading along its length, with a
  /// reticle at the end. An empty [trajectory] (no usable draw) draws nothing —
  /// so a bare tap shows no shot. The dots brighten with [a.draw] (power).
  static void drawAimPreview(
      Canvas canvas, ArcherView a, List<Offset> trajectory) {
    if (trajectory.length < 2) return;
    final ready = a.draw.clamp(0.0, 1.0);
    final dot = Paint()..style = PaintingStyle.fill;
    final n = trajectory.length;
    for (var i = 0; i < n; i++) {
      final f = i / (n - 1);
      final fade = (1 - f) * (0.35 + 0.45 * ready);
      dot.color = a.color.withValues(alpha: fade.clamp(0.0, 1.0));
      final rad = (2.6 - 1.4 * f) * a.scale;
      canvas.drawCircle(trajectory[i], math.max(1.0, rad), dot);
    }
    final end = trajectory.last;
    canvas.drawCircle(
      end,
      7 * a.scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = a.color.withValues(alpha: (0.4 + 0.4 * ready).clamp(0.0, 1.0)),
    );
    // Small power pip at the reticle so the draw strength reads.
    canvas.drawCircle(end, 7 * a.scale * ready,
        Paint()..color = a.color.withValues(alpha: 0.5));
  }

  static void drawArcherBody(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }

  /// The recurve bow: two glowing wooden limbs, a taut string that pulls back
  /// with [a.draw], and a nocked arrow that slides back as the draw deepens.
  /// Anchored at the bow hand so it tracks the aim. A recent [a.loose] snaps the
  /// riser forward + flashes the string for release punch.
  static void drawBow(Canvas canvas, ArcherView a) {
    final dir = Offset(math.cos(a.aimAngle), math.sin(a.aimAngle));
    final perp = Offset(-dir.dy, dir.dx);
    final kick = a.loose.clamp(0.0, 1.0) * _looseKick * a.scale;
    final hand = _bowAnchor(a) + dir * kick;
    final r = _bowRadius * a.scale;
    final draw = a.draw.clamp(0.0, 1.0);

    final tipTop = hand + perp * (math.sin(_bowSpan) * r) + dir * _bowCurve(r);
    final tipBot = hand - perp * (math.sin(_bowSpan) * r) + dir * _bowCurve(r);
    final ctrl = hand - dir * (r * 0.5);

    final bowPath = Path()
      ..moveTo(tipTop.dx, tipTop.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, tipBot.dx, tipBot.dy);
    canvas.drawPath(
      bowPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(4.0, r * 0.34)
        ..strokeCap = StrokeCap.round
        ..color = a.color.withValues(alpha: 0.22),
    );

    canvas.drawPath(
      bowPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.5, r * 0.16)
        ..strokeCap = StrokeCap.round
        ..color = _bowWood,
    );
    canvas.drawPath(
      bowPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.06)
        ..strokeCap = StrokeCap.round
        ..color = _bowWoodHi.withValues(alpha: 0.9),
    );

    final loose = a.loose.clamp(0.0, 1.0);
    final nockBack = draw * _drawDepth * a.scale - loose * _drawDepth * a.scale;
    final nock = hand - dir * nockBack;

    final stringAlpha = (0.95 - 0.3 * loose).clamp(0.0, 1.0);
    final stringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, r * 0.04) + loose * r * 0.05
      ..color = Color.lerp(_string, _white, loose)!
          .withValues(alpha: stringAlpha);
    canvas.drawLine(tipTop, nock, stringPaint);
    canvas.drawLine(tipBot, nock, stringPaint);

    // Nocked arrow (only while drawing): rides from the nock forward past hand.
    if (draw > 0.02 && loose < 0.4) {
      final len = _arrowLen * a.scale;
      final tail = nock;
      final tip = nock + dir * (len + draw * _drawDepth * a.scale);
      _drawArrowShaft(canvas, tail, tip, dir, perp, a.color, a.scale);
    }
  }

  /// One in-flight or stuck arrow with a motion trail, fletched tail and a
  /// metallic tip. Stuck arrows fade via [v.stuck].
  static void drawArrow(Canvas canvas, ArrowView v) {
    final alpha = v.stuck > 0 ? v.stuck.clamp(0.0, 1.0) : 1.0;
    if (alpha <= 0.01) return;
    final dir = v.dir;
    final perp = Offset(-dir.dy, dir.dx);

    if (v.stuck <= 0 && v.trail.length >= 2) {
      final paint = Paint()..strokeCap = StrokeCap.round;
      final n = v.trail.length;
      for (var i = 0; i < n - 1; i++) {
        final f = 1 - i / n;
        paint
          ..color = _blend(v.color, _white, 0.3)
              .withValues(alpha: (0.45 * f).clamp(0.0, 1.0))
          ..strokeWidth = 1.0 + 4 * f;
        canvas.drawLine(v.trail[i], v.trail[i + 1], paint);
      }
    }

    final tip = v.pos;
    final tail = v.pos - dir * _arrowLen;
    _drawArrowShaft(canvas, tail, tip, dir, perp, v.color, 1.0, alpha: alpha);
  }

  static void _drawArrowShaft(Canvas canvas, Offset tail, Offset tip,
      Offset dir, Offset perp, Color color, double scale,
      {double alpha = 1.0}) {
    final w = math.max(1.4, 2.2 * scale);
    canvas.drawLine(
      tail,
      tip,
      Paint()
        ..color = _shaftDark.withValues(alpha: alpha)
        ..strokeWidth = w * 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      tail,
      tip,
      Paint()
        ..color = _shaft.withValues(alpha: alpha)
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );

    final vaneBase = tail + dir * (6 * scale);
    final vaneSpan = 5.0 * scale;
    final vanePaint = Paint()..color = _fletch.withValues(alpha: alpha);
    for (final s in const [1.0, -1.0]) {
      final p = Path()
        ..moveTo(tail.dx + perp.dx * s * 0.5, tail.dy + perp.dy * s * 0.5)
        ..lineTo(tail.dx + perp.dx * s * vaneSpan - dir.dx * 4 * scale,
            tail.dy + perp.dy * s * vaneSpan - dir.dy * 4 * scale)
        ..lineTo(
            vaneBase.dx + perp.dx * s * 0.5, vaneBase.dy + perp.dy * s * 0.5)
        ..close();
      canvas.drawPath(p, vanePaint);
    }
    canvas.drawCircle(
        vaneBase, w * 0.9, Paint()..color = color.withValues(alpha: alpha));

    final headBack = tip - dir * (7 * scale);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
          headBack.dx + perp.dx * 3 * scale, headBack.dy + perp.dy * 3 * scale)
      ..lineTo(
          headBack.dx - perp.dx * 3 * scale, headBack.dy - perp.dy * 3 * scale)
      ..close();
    canvas.drawPath(
        head, Paint()..color = _arrowHead.withValues(alpha: alpha));
    canvas.drawPath(
      head,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _white.withValues(alpha: (0.6 * alpha).clamp(0.0, 1.0)),
    );
  }

  /// A combo badge floating above an archer when its streak is hot (≥2).
  static void drawComboBadge(Canvas canvas, ArcherView a) {
    if (a.combo < 2) return;
    final up = -a.side.outward;
    final at = a.base + up * (66 * a.scale);
    final pulse = 1.0 + 0.12 * math.sin(a.combo.toDouble());
    _drawBadgeText(canvas, at, 'x${a.combo}', 22 * a.scale * pulse, a.color);
  }

  // ── HUD: per-player ammo + score + objective (screen space) ─────────────────

  /// A compact card anchored in the player's zone, rotated to face them: a
  /// "P# HIT TARGETS" objective line, the live SCORE, and a row of arrow pips
  /// showing the remaining quiver (spent pips dim). Makes ammo + objective
  /// unmistakable for 1..4 players.
  static void drawHud(Canvas canvas, Size size, HudView h) {
    final zone = h.zone;
    final flipped = h.rotationQuarters == 2;
    final cx = (zone.left + zone.right) * 0.5 * size.width;
    final pad = size.height * 0.012;
    final cardW = math.min(size.width * 0.42, 230.0);
    final cardH = math.max(36.0, size.height * 0.052);
    // Place the card just inside the player's near edge (facing them).
    final nearY = flipped ? zone.top * size.height : zone.bottom * size.height;
    final cy = flipped ? nearY + cardH * 0.5 + pad : nearY - cardH * 0.5 - pad;

    canvas.save();
    canvas.translate(cx, cy);
    if (flipped) canvas.rotate(math.pi);

    final rect =
        Rect.fromCenter(center: Offset.zero, width: cardW, height: cardH);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(cardH * 0.28));
    canvas.drawRRect(rr, Paint()..color = _hudBg);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = h.color.withValues(alpha: 0.7),
    );

    final fs = cardH * 0.34;
    // Objective (left) + score (right) on the top line of the card.
    _drawLeftText(
        canvas,
        'P${h.playerNumber}  HIT TARGETS',
        Offset(-cardW * 0.5 + cardH * 0.32, -cardH * 0.5 + cardH * 0.12),
        _white.withValues(alpha: 0.85),
        fs * 0.78,
        cardW);
    _drawRightText(
        canvas,
        '${h.score}',
        Offset(cardW * 0.5 - cardH * 0.32, -cardH * 0.5 + cardH * 0.06),
        h.color,
        fs * 1.18,
        cardW);

    // Ammo pips row along the bottom of the card.
    _drawAmmoPips(canvas, rect, h);

    canvas.restore();
  }

  static void _drawAmmoPips(Canvas canvas, Rect card, HudView h) {
    final n = h.maxAmmo.clamp(1, 24);
    final left = card.left + card.height * 0.3;
    final right = card.right - card.height * 0.3;
    final y = card.bottom - card.height * 0.26;
    final span = right - left;
    final step = span / n;
    final r = math.max(1.5, math.min(step * 0.32, card.height * 0.1));
    for (var i = 0; i < n; i++) {
      final x = left + step * (i + 0.5);
      final live = i < h.ammo;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = live ? h.color : _white.withValues(alpha: 0.16),
      );
    }
  }

  // ── Geometry shared with gameplay (so visuals + the loosed arrow agree) ─────

  static Offset bowAnchor(ArcherView a) => _bowAnchor(a);
  static Offset _bowAnchor(ArcherView a) {
    final dir = Offset(math.cos(a.aimAngle), math.sin(a.aimAngle));
    final shoulder = a.base.translate(0, -34 * a.scale);
    return shoulder + dir * (18 * a.scale);
  }

  static double _bowCurve(double r) => r * 0.28;

  // ── Small private helpers ──────────────────────────────────────────────────

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  static void _drawBadgeText(
      Canvas canvas, Offset center, String text, double fontSize, Color color) {
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
    ))
      ..pushStyle(TextStyle(color: _readableText(color)))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: fontSize * 4));

    final w = paragraph.maxIntrinsicWidth + fontSize * 0.8;
    final hgt = fontSize * 1.5;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: hgt),
      Radius.circular(hgt * 0.5),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, fontSize * 0.08)
        ..color = _white.withValues(alpha: 0.6),
    );
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - paragraph.maxIntrinsicWidth / 2,
          center.dy - fontSize * 0.62),
    );
  }

  /// Left-aligned label drawn from a top-left [at] (used inside a rotated HUD).
  static void _drawLeftText(Canvas canvas, String text, Offset at, Color color,
      double fontSize, double maxWidth) {
    if (fontSize <= 1) return;
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, at);
  }

  /// Right-aligned label whose right edge sits at [at] (the score readout).
  static void _drawRightText(Canvas canvas, String text, Offset at, Color color,
      double fontSize, double maxWidth) {
    if (fontSize <= 1) return;
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.right,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, Offset(at.dx - maxWidth, at.dy));
  }

  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }
}
