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

/// Immutable snapshot of one archer handed to the renderer. Carries only what
/// is needed to draw — no gameplay coupling, no mutation.
class ArcherView {
  final Offset base; // pelvis/render anchor in arena px
  final Color color;
  final ArcherSide side;
  final double facing; // -1 / +1
  final double aimAngle; // bow aim in radians (screen space)
  final double draw; // 0..1 bow draw amount (1 = fully nocked, about to loose)
  final int combo; // current pop streak (0 = none)
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

/// Immutable snapshot of one balloon target.
class BalloonView {
  final Offset pos;
  final Color color;
  final double radius;
  final double bobPhase; // for the gentle squash/sway
  final double popT; // 0 = whole, >0 = popping (1 → 0 as it bursts)
  final bool golden; // bonus balloon (worth more) → metallic shine + sparkle
  final double sparklePhase; // animates the golden glint

  const BalloonView({
    required this.pos,
    required this.color,
    required this.radius,
    required this.bobPhase,
    this.popT = 0,
    this.golden = false,
    this.sparklePhase = 0,
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

/// Pure-Canvas rendering for ArcherPop. Holds NO game state and never mutates
/// the simulation — callers pass plain value snapshots. Every method guards its
/// own inputs and never throws, so it is safe to call from `render`.
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

  // ── Tuning (fractions / px) ────────────────────────────────────────────────
  static const double _bowRadius = 30; // bow limb radius at scale 1
  static const double _bowSpan = 1.5; // limb arc half-angle (radians)
  static const double _drawDepth = 12; // px the string pulls back at full draw
  static const double _arrowLen = 26; // drawn arrow shaft length
  static const double _aimGuideLen = 150; // px reticle reach
  static const int _hillBands = 3;
  static const double _looseKick = 6; // px the riser snaps forward on a loose
  static const double _windRef = 70; // wind speed mapped to full streak strength

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
    // Puffy clouds from a few overlapping translucent ovals — soft + cheap, no
    // per-cloud blur. The faint alpha keeps the cluster reading as one cloud.
    final paint = Paint()..color = _cloud;
    for (var i = 0; i < clouds.length; i++) {
      final c = clouds[i];
      // Slow horizontal drift that wraps across the width.
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

  /// Layered rolling hills receding to the horizon (far → near, darker + taller).
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

  /// Grass band from the horizon to the bottom with a subtle gradient + texture.
  static void _drawGrass(Canvas canvas, Size size, double horizonY) {
    final ground = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, horizonY),
        Offset(size.width / 2, size.height),
        const [_grassTop, _grassLow],
      );
    canvas.drawRect(Rect.fromLTRB(0, horizonY, size.width, size.height), ground);

    // Soft scan-line texture (cheap, no blur) for a turf feel.
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

  /// Faint diagonal speed-streaks blowing in the wind direction. [windX] (px/s)
  /// sets direction + strength; a calm field is nearly clear and a strong gust
  /// visibly rushes. Streaks are supplied as deterministic anchors so they
  /// animate with the sim clock without per-frame allocation churn.
  static void drawWindStreaks(
    Canvas canvas,
    Size size,
    List<Offset> anchors,
    double windX,
    double t,
  ) {
    final strength = (windX.abs() / _windRef).clamp(0.0, 1.0);
    if (anchors.isEmpty || strength <= 0.02) return;
    final dirSign = windX >= 0 ? 1.0 : -1.0;
    final len = 26.0 + 40.0 * strength;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6;
    final span = size.width + len * 2;
    for (var i = 0; i < anchors.length; i++) {
      final a = anchors[i];
      // Drift with the wind, wrapping across the width.
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

  /// A small top banner showing wind heading + strength: an arrow that grows
  /// and brightens with the gust so players can read the drift before loosing.
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

    // A wind arrow whose length tracks strength, pointing with the gust.
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
    // Arrowhead.
    final back = to - Offset(dirSign * h * 0.34, 0);
    final head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(back.dx, back.dy - h * 0.24)
      ..lineTo(back.dx, back.dy + h * 0.24)
      ..close();
    canvas.drawPath(head, Paint()..color = col);
  }

  // ── Balloon target ──────────────────────────────────────────────────────────

  /// A bobbing balloon with a teardrop bulb, glossy highlight, knot and a wavy
  /// string. When [b.popT] > 0 it renders a quick rubber-burst flash instead.
  /// Golden balloons add a metallic gradient, a glow halo and a rotating glint.
  static void drawBalloon(Canvas canvas, BalloonView b) {
    final r = b.radius;
    if (r <= 0) return;

    if (b.popT > 0) {
      _drawPopFlash(canvas, b.pos, r, b.golden ? _gold : b.color, b.popT);
      return;
    }

    // Gentle squash + sway from the bob phase.
    final squash = 1.0 + math.sin(b.bobPhase) * 0.05;
    final sway = math.sin(b.bobPhase * 0.7) * r * 0.12;
    final center = b.pos.translate(sway, 0);

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // Golden balloons get a soft outer glow (two stacked translucent rings,
    // wide+faint under tight+stronger) so the bonus reads without a per-balloon
    // blur.
    if (b.golden) {
      canvas.drawCircle(Offset.zero, r * 1.7,
          Paint()..color = _gold.withValues(alpha: 0.12));
      canvas.drawCircle(Offset.zero, r * 1.34,
          Paint()..color = _gold.withValues(alpha: 0.2));
    }

    // String: a wavy tail with a small knot.
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

    // Teardrop bulb: a circle pinched to a knot at the bottom.
    final bulb = Path()
      ..addOval(Rect.fromCenter(
          center: Offset.zero, width: r * 2 / squash, height: r * 2 * squash))
      ..moveTo(-r * 0.22, r * 0.86 * squash)
      ..lineTo(0, r * 1.04 * squash)
      ..lineTo(r * 0.22, r * 0.86 * squash)
      ..close();

    final baseColor = b.golden ? _gold : b.color;
    final body = Paint()
      ..shader = Gradient.radial(
        Offset(-r * 0.32, -r * 0.38),
        r * 1.5,
        [
          _blend(baseColor, _white, b.golden ? 0.55 : 0.4),
          baseColor,
          _blend(baseColor, _black, b.golden ? 0.3 : 0.4),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawPath(bulb, body);

    // Rim outline.
    canvas.drawPath(
      bulb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.07)
        ..color = _blend(baseColor, _black, 0.35).withValues(alpha: 0.8),
    );

    // Glossy vertical highlight + specular dot.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(-r * 0.3, -r * 0.2), width: r * 0.42, height: r * 0.9),
      Paint()..color = _balloonShine.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
        Offset(-r * 0.38, -r * 0.42), r * 0.14, Paint()..color = _white);

    // Golden rotating glint (a tiny 4-point sparkle).
    if (b.golden) {
      _drawSparkle(canvas, Offset(r * 0.2, -r * 0.1), r * 0.4, b.sparklePhase);
    }

    // Knot pip.
    canvas.drawCircle(Offset(0, r * 0.96 * squash), r * 0.16,
        Paint()..color = _blend(baseColor, _black, 0.25));

    canvas.restore();
  }

  /// A short-lived rubber-pop: an expanding torn ring + a bright inner flash.
  static void _drawPopFlash(
      Canvas canvas, Offset at, double r, Color color, double popT) {
    final p = popT.clamp(0.0, 1.0);
    final grow = 1.0 + (1 - p) * 1.4;
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

  /// A four-point sparkle glint that rotates with [phase].
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

  // ── Archer (stick figure + drawn bow + aim guide) ───────────────────────────

  /// Faint dashed aim guide along the bow heading, fading out, with a small
  /// reticle ring — drawn under the archers so it never hides a body. The guide
  /// brightens with [a.draw] so a fully-nocked shot reads as "ready to loose".
  static void drawAimGuide(Canvas canvas, ArcherView a) {
    final dir = Offset(math.cos(a.aimAngle), math.sin(a.aimAngle));
    final origin = _bowAnchor(a);
    final end = origin + dir * (_aimGuideLen * a.scale);
    const steps = 12;
    final ready = a.draw.clamp(0.0, 1.0);
    final seg = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < steps; i++) {
      if (i.isOdd) continue;
      final f0 = i / steps, f1 = (i + 1) / steps;
      final base = (1 - f0) * (0.28 + 0.34 * ready);
      seg.color = a.color.withValues(alpha: base.clamp(0.0, 1.0));
      canvas.drawLine(
          Offset.lerp(origin, end, f0)!, Offset.lerp(origin, end, f1)!, seg);
    }
    canvas.drawCircle(
      end,
      6 * a.scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = a.color.withValues(alpha: (0.3 + 0.4 * ready).clamp(0.0, 1.0)),
    );
  }

  /// Render the stick archer body. The bow + nocked arrow are drawn separately
  /// (on top) so the string sits in front of the bow hand.
  static void drawArcherBody(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }

  /// The recurve bow: two glowing wooden limbs forming an arc, a taut string
  /// that pulls back with [a.draw], and a nocked arrow that slides back as the
  /// draw deepens. Anchored at the bow hand so it tracks the aim. A recent
  /// [a.loose] snaps the riser forward + flashes the string for release punch.
  static void drawBow(Canvas canvas, ArcherView a) {
    final dir = Offset(math.cos(a.aimAngle), math.sin(a.aimAngle));
    final perp = Offset(-dir.dy, dir.dx);
    // The loose kick shoves the whole bow forward briefly on release.
    final kick = a.loose.clamp(0.0, 1.0) * _looseKick * a.scale;
    final hand = _bowAnchor(a) + dir * kick;
    final r = _bowRadius * a.scale;
    final draw = a.draw.clamp(0.0, 1.0);

    // Limb tips: arc opening toward the aim direction.
    final tipTop = hand + perp * (math.sin(_bowSpan) * r) + dir * _bowCurve(r);
    final tipBot = hand - perp * (math.sin(_bowSpan) * r) + dir * _bowCurve(r);
    // Control point bows the limbs back behind the hand (away from aim).
    final ctrl = hand - dir * (r * 0.5);

    // Soft colored aura under the wood: a wide, faint stroke (no blur) beneath
    // the crisp limbs fakes the glow far cheaper per archer.
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

    // Wooden limbs (dark base + bright inner riser line).
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

    // Nock point: string pulled back behind the hand proportional to draw. On a
    // fresh loose the string snaps forward past the hand (overshoot) + flashes.
    final loose = a.loose.clamp(0.0, 1.0);
    final nockBack = draw * _drawDepth * a.scale - loose * _drawDepth * a.scale;
    final nock = hand - dir * nockBack;

    // String from tip → nock → tip.
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

    // Motion trail (only while flying).
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

  /// Shared arrow art: shaft, two fletching vanes at the tail, metallic head.
  static void _drawArrowShaft(Canvas canvas, Offset tail, Offset tip,
      Offset dir, Offset perp, Color color, double scale,
      {double alpha = 1.0}) {
    final w = math.max(1.4, 2.2 * scale);
    // Shaft (dark under + light core for a round look).
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

    // Fletching: two angled vanes near the tail in the owner color.
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
    // Owner-color band so arrows read at a glance.
    canvas.drawCircle(
        vaneBase, w * 0.9, Paint()..color = color.withValues(alpha: alpha));

    // Metallic broadhead.
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
    final up = -a.side.outward; // toward the field
    final at = a.base + up * (66 * a.scale);
    final pulse = 1.0 + 0.12 * math.sin(a.combo.toDouble());
    _drawBadgeText(canvas, at, 'x${a.combo}', 22 * a.scale * pulse, a.color);
  }

  // ── Geometry shared with gameplay (so visuals + the loosed arrow agree) ─────

  /// The bow-hand anchor: lifted off the pelvis toward the chest, then nudged
  /// along the aim so the riser sits where the figure's front hand reaches.
  static Offset bowAnchor(ArcherView a) => _bowAnchor(a);
  static Offset _bowAnchor(ArcherView a) {
    final dir = Offset(math.cos(a.aimAngle), math.sin(a.aimAngle));
    // Chest is ~30px up the spine from the pelvis root at scale 1.
    final shoulder = a.base.translate(0, -34 * a.scale);
    return shoulder + dir * (18 * a.scale);
  }

  static double _bowCurve(double r) => r * 0.28; // how far limbs bow forward

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

    // Rounded pill backing in the player color.
    final w = paragraph.maxIntrinsicWidth + fontSize * 0.8;
    final h = fontSize * 1.5;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.5),
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

  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }
}
