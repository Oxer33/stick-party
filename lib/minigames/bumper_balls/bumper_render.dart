import 'dart:math' as math;
import 'dart:ui';

/// A ball's facial expression, driven by its current situation so the knockout
/// reads with character: [neutral] is the determined default; [scared] (raised
/// brows + shrunken pupils) shows when it is near the deadly edge; [happy] (a big
/// arc smile) shows while buffed by a star; [dizzy] (X eyes + a wobbly mouth) is
/// worn by a ball that has just been knocked off as it spins away.
enum BallFace { neutral, scared, happy, dizzy }

/// Pure-Canvas rendering for [BumperBalls]. Holds NO game state and never
/// mutates the simulation — callers pass plain value snapshots. Kept in its own
/// file so the gameplay module stays lean and the drawing stays cohesive.
///
/// Theme: a neon knockout floor. A dark void backdrop, a glowing hex/grid disc
/// platform with a bright energized rim and a pulsing red danger band, and
/// glossy player-colored bumper balls with eyes, a motion trail, squash &
/// stretch on impact and impact spark rings. There is no idle aim arrow; while
/// a player charges, a player-colored telegraph follows their drag (where the
/// bump will fire), and a launched ball wears a hot rocket-dash aura. A numbered
/// ground id ring keeps each ball identifiable.
///
/// Perf: per-entity glows (ball bloom, motion trail, impact ring, aim
/// telegraph) and the ambient motes use cheap layered solid strokes — no
/// per-frame [MaskFilter.blur]. Blur is reserved for the handful of
/// once-per-frame backdrop pieces (platform drop-shadow, danger-band halo, rim
/// glow) plus the single soft contact shadow under each ball.
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class BumperRenderer {
  BumperRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _bgTop = Color(0xFF0A0E1A);
  static const Color _bgBottom = Color(0xFF05070E);
  static const Color _voidGlow = Color(0x223A6BFF);
  static const Color _floorCore = Color(0xFF16243F);
  static const Color _floorEdge = Color(0xFF0B1322);
  static const Color _hexLine = Color(0x2A5FA8FF);
  static const Color _gridGlow = Color(0x14A9D8FF);
  static const Color _ringShadow = Color(0x77000000);
  static const Color _dangerBand = Color(0xFFFF4060);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF050810);
  static const Color _pupil = Color(0xFF0A0E1A);

  // ── Tuning ─────────────────────────────────────────────────────────────────
  static const double _voidGlowFactor = 1.7; // backdrop glow radius / ring R
  static const double _rimWidthFactor = 0.045; // rim stroke / ring radius
  static const double _shadowDrop = 0.07; // platform drop-shadow / radius
  static const double _dangerBandFactor = 0.11; // band depth / ring radius
  static const double _hexRadiusFactor = 0.13; // hex cell radius / ring radius
  static const double _ballGlowFactor = 1.55; // ball glow radius / ball radius
  static const double _eyeOffsetFactor = 0.34; // eye spread / ball radius
  static const double _eyeRadiusFactor = 0.20; // white radius / ball radius
  static const double _trailMaxFactor = 2.6; // trail length / ball radius
  static const int _concentricRings = 5;
  static const double _idRingWidthFactor =
      0.12; // id stroke width / ball radius
  static const double _idRingWFactor = 2.4; // id ellipse width / ball radius
  static const double _idRingHFactor = 0.78; // id ellipse height / ball radius
  static const double _idPipFactor = 0.42; // id number pip radius / ball radius
  static const double _launchAuraFactor = 1.85; // rocket aura radius / ball R
  static const Color _launchHot = Color(0xFFFFF1C2); // rocket comet hot core

  // ── Background: void gradient + soft central glow ───────────────────────────
  static void drawBackground(
    Canvas canvas,
    Size size,
    Offset center,
    double ringRadius,
  ) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgBottom],
      );
    canvas.drawRect(Offset.zero & size, bg);

    final glowR = ringRadius * _voidGlowFactor;
    if (glowR > 0) {
      final glow = Paint()
        ..shader = Gradient.radial(center, glowR, const [
          _voidGlow,
          Color(0x00000000),
        ]);
      canvas.drawCircle(center, glowR, glow);
    }
  }

  /// Sparse drifting energy motes for depth (positions supplied by the caller so
  /// they stay deterministic and animate with the sim clock).
  static void drawAmbientMotes(Canvas canvas, List<Offset> motes, double t) {
    if (motes.isEmpty) return;
    final paint = Paint(); // solid dots (no per-mote blur)
    for (var i = 0; i < motes.length; i++) {
      final m = motes[i];
      final drift = Offset(0, math.sin(t * 0.6 + i) * 6);
      final twinkle = 0.16 + 0.18 * (0.5 + 0.5 * math.sin(t * 1.9 + i * 1.3));
      paint.color = _gridGlow.withValues(alpha: twinkle.clamp(0.0, 1.0));
      canvas.drawCircle(m + drift, 1.6 + (i % 3) * 0.7, paint);
    }
  }

  /// The platform: drop shadow → energized floor gradient → hex lattice + faint
  /// concentric grid → glowing danger band → bright neon rim + inner lip.
  /// [accent] tints the rim; [dangerPulse] in 0..1 brightens the danger band.
  static void drawPlatform(
    Canvas canvas,
    Offset center,
    double ringRadius, {
    required Color accent,
    required double dangerPulse,
    required double t,
  }) {
    if (ringRadius <= 1) return;

    // Soft drop shadow so the disc floats above the void.
    final shadow = Paint()
      ..color = _ringShadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(
      center + Offset(0, ringRadius * _shadowDrop),
      ringRadius * 1.03,
      shadow,
    );

    // Energized floor body.
    final floor = Paint()
      ..shader = Gradient.radial(
        center.translate(-ringRadius * 0.12, -ringRadius * 0.16),
        ringRadius * 1.18,
        const [_floorCore, _floorEdge],
        const [0.0, 1.0],
      );
    canvas.drawCircle(center, ringRadius, floor);

    // Clip the lattice to the disc so lines never spill past the rim.
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: ringRadius)),
    );
    _drawHexLattice(canvas, center, ringRadius);
    _drawConcentricGrid(canvas, center, ringRadius, t);
    canvas.restore();

    _drawDangerBand(canvas, center, ringRadius, dangerPulse, t);
    _drawRim(canvas, center, ringRadius, accent);
  }

  /// A hexagonal grid filling the disc, drawn as glowing strokes.
  static void _drawHexLattice(Canvas canvas, Offset center, double ringRadius) {
    final cell = ringRadius * _hexRadiusFactor;
    if (cell <= 2) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, cell * 0.05)
      ..color = _hexLine;

    // Axial hex layout: column step 1.5*r, row step sqrt(3)*r (offset cols).
    final colStep = cell * 1.5;
    final rowStep = cell * math.sqrt(3.0);
    final cols = (ringRadius / colStep).ceil() + 1;
    final rows = (ringRadius / rowStep).ceil() + 1;
    for (var q = -cols; q <= cols; q++) {
      for (var r = -rows; r <= rows; r++) {
        final cx = center.dx + q * colStep;
        final cy = center.dy + r * rowStep + (q.isEven ? 0 : rowStep / 2);
        final c = Offset(cx, cy);
        if ((c - center).distance > ringRadius + cell) continue;
        canvas.drawPath(_hexPath(c, cell * 0.96), paint);
      }
    }
  }

  static Path _hexPath(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i; // pointy-right orientation
      final p = center + Offset(math.cos(a) * radius, math.sin(a) * radius);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  /// A few slowly breathing concentric rings for a "scanline" energy feel.
  static void _drawConcentricGrid(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double t,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, ringRadius * 0.005);
    for (var i = 1; i <= _concentricRings; i++) {
      final base = i / (_concentricRings + 1);
      final breathe = 0.5 + 0.5 * math.sin(t * 1.2 + i);
      paint.color = _gridGlow.withValues(alpha: (0.08 + 0.07 * breathe));
      canvas.drawCircle(center, ringRadius * base, paint);
    }
  }

  /// Glowing red danger band just inside the rim: a soft halo + a crisp core
  /// line so it clearly reads as "the edge will knock you out".
  static void _drawDangerBand(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double pulse,
    double t,
  ) {
    final p = pulse.clamp(0.0, 1.0);
    final bandDepth = ringRadius * _dangerBandFactor;
    final bandR = ringRadius - bandDepth * 0.7;
    final alpha = (0.28 + 0.5 * p);
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bandDepth * 1.15
      ..color = _dangerBand.withValues(alpha: (alpha * 0.5).clamp(0.0, 1.0))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, bandDepth * 0.6);
    canvas.drawCircle(center, bandR, halo);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, bandDepth * 0.4)
      ..color = _dangerBand.withValues(alpha: alpha.clamp(0.0, 1.0));
    canvas.drawCircle(center, bandR, core);

    // A bright crest that travels around the band — it sweeps faster and reads
    // sharper as [pulse] climbs (the band brightens as the floor shrinks and a
    // ball is pinned near the deadly edge), so the rim feels alive and urgent.
    // A short bright arc swept along the existing core circle: no blur, no new
    // geometry beyond one arc.
    if (p > 0.01) {
      final sweepW = _blend(_dangerBand, _white, 0.6 + 0.3 * p);
      final crestSpan = math.pi * (0.5 - 0.32 * p); // tighter = sharper crest
      final speed = 1.4 + 2.6 * p; // faster travel under pressure
      final headAngle = (t * speed) % (math.pi * 2);
      final crestRect = Rect.fromCircle(center: center, radius: bandR);
      canvas.drawArc(
        crestRect,
        headAngle - crestSpan,
        crestSpan,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(2.0, bandDepth * 0.5)
          ..color = sweepW.withValues(alpha: (0.32 + 0.5 * p).clamp(0.0, 1.0)),
      );
      // A tight white tip at the leading head so the crest reads as a runner.
      canvas.drawArc(
        crestRect,
        headAngle - crestSpan * 0.32,
        crestSpan * 0.32,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.2, bandDepth * 0.22)
          ..color = _white.withValues(alpha: (0.3 + 0.45 * p).clamp(0.0, 1.0)),
      );
    }
  }

  /// Bright neon rim: a controlled outer glow, a vertical gradient core stroke,
  /// and an inner highlight lip for a thick 3-D energized edge.
  static void _drawRim(
    Canvas canvas,
    Offset center,
    double ringRadius,
    Color accent,
  ) {
    final rimW = math.max(3.0, ringRadius * _rimWidthFactor);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimW * 1.5
      ..color = accent.withValues(alpha: 0.42)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, rimW * 0.8);
    canvas.drawCircle(center, ringRadius, glow);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimW
      ..shader = Gradient.linear(
        center.translate(0, -ringRadius),
        center.translate(0, ringRadius),
        [_blend(accent, _white, 0.55), accent],
      );
    canvas.drawCircle(center, ringRadius, rim);

    final lip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, rimW * 0.35)
      ..color = _white.withValues(alpha: 0.2);
    canvas.drawCircle(center, ringRadius - rimW * 0.55, lip);
  }

  /// Soft contact shadow ellipse beneath a ball at ground level.
  static void drawContactShadow(Canvas canvas, Offset ground, double ballR) {
    final paint = Paint()
      ..color = _black.withValues(alpha: 0.36)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, ballR * 0.3);
    canvas.drawOval(
      Rect.fromCenter(center: ground, width: ballR * 2.1, height: ballR * 0.55),
      paint,
    );
  }

  /// A short directional motion trail behind a moving ball. [strength] 0..1 and
  /// [speedFrac] 0..1 (share of max speed) scale length and opacity.
  static void drawTrail(
    Canvas canvas,
    Offset pos,
    Offset dir,
    double ballR,
    Color color,
    double strength,
    double speedFrac,
  ) {
    final s = strength.clamp(0.0, 1.0) * speedFrac.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    final len = ballR * _trailMaxFactor * s;
    final tail = pos - dir * len;
    // Two cheap layered solid strokes (no blur): a wider faint base + a tighter
    // brighter core fake a soft motion blur at a fraction of the cost.
    canvas.drawLine(
      tail,
      pos,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = ballR * (1.0 + 1.2 * s)
        ..color = color.withValues(alpha: 0.16 * s),
    );
    canvas.drawLine(
      tail,
      pos,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = ballR * (0.6 + 0.8 * s)
        ..color = color.withValues(alpha: 0.34 * s),
    );
  }

  /// A hot comet aura behind a ROCKET-DASHING ball: a forward-biased glow plus
  /// a couple of trailing embers so a launched ball reads as a dangerous streak
  /// caroming off rivals. [heading] is the unit travel direction, [speedFrac]
  /// 0..1 its share of max speed. Layered solids only (no blur) — cheap.
  static void drawLaunchAura(
    Canvas canvas,
    Offset pos,
    Offset heading,
    double ballR,
    Color color,
    double speedFrac,
  ) {
    if (ballR <= 0) return;
    final s = speedFrac.clamp(0.0, 1.0);
    final hot = _blend(color, _launchHot, 0.5 + 0.4 * s);
    // Wide soft halo around the ball.
    canvas.drawCircle(
      pos,
      ballR * (_launchAuraFactor + 0.3 * s),
      Paint()..color = hot.withValues(alpha: 0.18 + 0.16 * s),
    );
    // Two trailing embers behind the ball along its heading.
    final back = _normalize(heading);
    for (var i = 1; i <= 2; i++) {
      final at = pos - back * (ballR * (0.9 * i + 0.6 * s));
      canvas.drawCircle(
        at,
        ballR * (0.7 - 0.18 * i),
        Paint()
          ..color = hot.withValues(alpha: (0.32 - 0.1 * i) * (0.5 + 0.5 * s)),
      );
    }
  }

  /// A glossy energized bumper ball with squash & stretch.
  ///
  /// [squash] in roughly [-0.5, 0.5]: positive stretches along [stretchDir]
  /// (and thins across it); negative flattens. [lookDir] aims the pupils.
  /// [ready] adds a bright charge ring telegraphing a dash is available.
  static void drawBall(
    Canvas canvas,
    Offset pos,
    double ballR,
    Color color, {
    required double squash,
    required Offset stretchDir,
    required Offset lookDir,
    required bool ready,
    required int displayNumber,
    BallFace face = BallFace.neutral,
  }) {
    if (ballR <= 0) return;

    // Outer glow as two cheap layered solid rings (no per-frame blur): a wide
    // faint halo and a tighter brighter one read as a soft neon bloom.
    canvas.drawCircle(
      pos,
      ballR * _ballGlowFactor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ballR * 0.5
        ..color = color.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      pos,
      ballR * (1.0 + (_ballGlowFactor - 1.0) * 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ballR * 0.34
        ..color = color.withValues(alpha: 0.24),
    );

    final sq = squash.clamp(-0.5, 0.5);
    final along = 1.0 + sq;
    final across = 1.0 - sq * 0.6;
    final ang = math.atan2(stretchDir.dy, stretchDir.dx);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(ang);
    canvas.scale(along, across);
    canvas.rotate(-ang);
    canvas.translate(-pos.dx, -pos.dy);

    // Body with a top-lit radial gradient (glossy sphere shading).
    final body = Paint()
      ..shader = Gradient.radial(
        pos.translate(-ballR * 0.3, -ballR * 0.36),
        ballR * 1.35,
        [_blend(color, _white, 0.45), color, _blend(color, _black, 0.42)],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawCircle(pos, ballR, body);

    // Rim light along the edge for a glassy bead.
    canvas.drawCircle(
      pos,
      ballR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, ballR * 0.1)
        ..color = _white.withValues(alpha: 0.28),
    );

    // Charge ring when a dash is ready.
    if (ready) {
      canvas.drawCircle(
        pos,
        ballR * 1.12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, ballR * 0.08)
          ..color = _blend(color, _white, 0.5).withValues(alpha: 0.6),
      );
    }

    _drawFace(canvas, pos, ballR, lookDir, displayNumber, face);

    // Specular highlight blob, last so it sits on top.
    canvas.drawCircle(
      pos + Offset(-ballR * 0.32, -ballR * 0.38),
      ballR * 0.22,
      Paint()..color = _white.withValues(alpha: 0.7),
    );

    canvas.restore();
  }

  /// The ball's face, switched by [face] so its mood reads at a glance. The
  /// number badge is always drawn; the eyes + mouth vary with the expression.
  static void _drawFace(
    Canvas canvas,
    Offset pos,
    double ballR,
    Offset lookDir,
    int number,
    BallFace face,
  ) {
    final eyeOffset = ballR * _eyeOffsetFactor;
    final eyeR = ballR * _eyeRadiusFactor;

    if (face == BallFace.dizzy) {
      _drawXEyes(canvas, pos, ballR, eyeOffset, eyeR);
      _drawWobblyMouth(canvas, pos, ballR);
    } else {
      _drawLiveEyes(canvas, pos, ballR, lookDir, eyeOffset, eyeR, face);
      _drawMoodMouth(canvas, pos, ballR, face);
    }

    // Player number badge tucked at the top of the ball (every expression).
    _drawNumber(
      canvas,
      pos.translate(0, -ballR * 0.46),
      '$number',
      ballR * 0.4,
      _white.withValues(alpha: 0.85),
    );
  }

  /// White eyes that track [lookDir]. [face] tweaks them: SCARED shrinks the
  /// pupils + adds raised brows, HAPPY keeps round pupils, NEUTRAL is the
  /// determined default. Always draws a catchlight for life.
  static void _drawLiveEyes(
    Canvas canvas,
    Offset pos,
    double ballR,
    Offset lookDir,
    double eyeOffset,
    double eyeR,
    BallFace face,
  ) {
    final lean = _normalize(lookDir) * (ballR * 0.16);
    final scared = face == BallFace.scared;
    final pupilScale = scared ? 0.34 : 0.55; // small pupils read as alarmed
    final white = Paint()..color = _white;
    final pupilPaint = Paint()..color = _pupil;

    for (final sign in const [-1.0, 1.0]) {
      final eye = pos + Offset(sign * eyeOffset, -ballR * 0.08);
      canvas.drawCircle(eye, eyeR, white);
      canvas.drawCircle(eye + lean, eyeR * pupilScale, pupilPaint);
      // Tiny catchlight for life.
      canvas.drawCircle(
        eye + Offset(-eyeR * 0.3, -eyeR * 0.3),
        eyeR * 0.22,
        Paint()..color = _white.withValues(alpha: 0.9),
      );
      // Raised worried brow above each eye when scared.
      if (scared) {
        final brow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, ballR * 0.06)
          ..strokeCap = StrokeCap.round
          ..color = _pupil;
        final by = eye.dy - eyeR * 1.7;
        canvas.drawLine(
          Offset(eye.dx - eyeR * 0.9, by + eyeR * 0.5),
          Offset(eye.dx + eyeR * 0.9, by),
          brow,
        );
      }
    }
  }

  /// Cross (X) eyes for a knocked-out ball — the classic "seeing stars" read.
  static void _drawXEyes(
    Canvas canvas,
    Offset pos,
    double ballR,
    double eyeOffset,
    double eyeR,
  ) {
    final x = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, ballR * 0.08)
      ..strokeCap = StrokeCap.round
      ..color = _pupil;
    for (final sign in const [-1.0, 1.0]) {
      final eye = pos + Offset(sign * eyeOffset, -ballR * 0.08);
      final r = eyeR * 0.9;
      canvas.drawLine(eye + Offset(-r, -r), eye + Offset(r, r), x);
      canvas.drawLine(eye + Offset(-r, r), eye + Offset(r, -r), x);
    }
  }

  /// Mouth for a live ball: HAPPY is a wide upward smile, SCARED a small worried
  /// O, NEUTRAL the determined arc (unchanged from the original face).
  static void _drawMoodMouth(
    Canvas canvas,
    Offset pos,
    double ballR,
    BallFace face,
  ) {
    if (face == BallFace.scared) {
      // A small open "oh no" mouth.
      canvas.drawCircle(
        pos + Offset(0, ballR * 0.34),
        ballR * 0.13,
        Paint()..color = _pupil,
      );
      return;
    }
    final mouth = Rect.fromCenter(
      center: pos + Offset(0, ballR * (face == BallFace.happy ? 0.24 : 0.3)),
      width: ballR * (face == BallFace.happy ? 0.78 : 0.62),
      height: ballR * (face == BallFace.happy ? 0.6 : 0.42),
    );
    canvas.drawArc(
      mouth,
      0.12 * math.pi,
      0.76 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, ballR * 0.09)
        ..strokeCap = StrokeCap.round
        ..color = _pupil,
    );
  }

  /// A small wavy mouth for the dizzy/KO'd ball.
  static void _drawWobblyMouth(Canvas canvas, Offset pos, double ballR) {
    final w = ballR * 0.5;
    final y = pos.dy + ballR * 0.32;
    final path = Path()..moveTo(pos.dx - w, y);
    path.cubicTo(
      pos.dx - w * 0.33, y - ballR * 0.14,
      pos.dx + w * 0.33, y + ballR * 0.14,
      pos.dx + w, y,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, ballR * 0.08)
        ..strokeCap = StrokeCap.round
        ..color = _pupil,
    );
  }

  /// A crisp impact spark ring at a collision point — an expanding ring + a star
  /// flash. [progress] in 0..1 drives radius/fade.
  static void drawImpactRing(
    Canvas canvas,
    Offset at,
    double maxRadius,
    Color color,
    double progress,
  ) {
    final p = progress.clamp(0.0, 1.0);
    if (p >= 1.0) return;
    final r = maxRadius * _easeOut(p);
    final fade = 1.0 - p;

    // Platform shockwave: a wider, flatter concentric ring that radiates out
    // along the disc and outruns the spark, so a big hit visibly thumps the
    // floor. Drawn FIRST (under the crisp spark) as a single thinning stroke —
    // no blur, no extra geometry — and it reaches ~1.7x the spark radius.
    final waveR = maxRadius * 1.7 * _easeOut(p);
    canvas.drawCircle(
      at,
      waveR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, maxRadius * 0.16 * fade * fade)
        ..color = _blend(color, _white, 0.25).withValues(alpha: 0.34 * fade),
    );

    // Two concentric solid strokes (no blur) read as a crisp expanding spark.
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, maxRadius * 0.12 * fade)
        ..color = _blend(color, _white, 0.4).withValues(alpha: 0.7 * fade),
    );
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, maxRadius * 0.05 * fade)
        ..color = _white.withValues(alpha: 0.5 * fade),
    );

    // Quick cross-flash early in the impact.
    if (p < 0.5) {
      final flashAlpha = (1.0 - p * 2).clamp(0.0, 1.0);
      final arm = maxRadius * 0.7 * _easeOut(p * 2);
      final flash = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.5, maxRadius * 0.08)
        ..color = _white.withValues(alpha: 0.8 * flashAlpha);
      canvas.drawLine(at - Offset(arm, 0), at + Offset(arm, 0), flash);
      canvas.drawLine(at - Offset(0, arm), at + Offset(0, arm), flash);
    }
  }

  /// A player-colored ground id ring + small numbered pip beneath a ball, so
  /// every ball is identifiable at a glance even when bunched together.
  static void drawIdRing(
    Canvas canvas,
    Offset ground,
    double ballR,
    Color color,
    int displayNumber,
  ) {
    if (ballR <= 0) return;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, ballR * _idRingWidthFactor)
      ..color = color.withValues(alpha: 0.9);
    canvas.drawOval(
      Rect.fromCenter(
        center: ground,
        width: ballR * _idRingWFactor,
        height: ballR * _idRingHFactor,
      ),
      ring,
    );

    // Number pip sits at the front (bottom) of the ground ring.
    final pipCenter = ground.translate(0, ballR * 0.05);
    final r = ballR * _idPipFactor;
    canvas.drawCircle(pipCenter, r, Paint()..color = color);
    canvas.drawCircle(
      pipCenter,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.18)
        ..color = _white.withValues(alpha: 0.85),
    );
    _drawNumber(
      canvas,
      pipCenter,
      '$displayNumber',
      r * 1.25,
      _readableText(color),
    );
  }

  /// The player's control made visible while CHARGING only (there is no idle
  /// arrow): a player-colored telegraph pointing the way the player is dragging
  /// — where the bump will fire — that grows with [charge], plus a charge
  /// ground-arc that fills as the hold deepens. [aim] is the heading in radians
  /// (set by the drag), [charge] 0..1. Cheap layered solid strokes (no blur).
  static void drawAim(
    Canvas canvas,
    Offset center,
    double ballR,
    Color color, {
    required double aim,
    required double charge,
  }) {
    if (ballR <= 0) return;
    final c = charge.clamp(0.0, 1.0);
    final dir = Offset(math.cos(aim), math.sin(aim));
    final base = ballR * 1.0;
    // A faint short stub at rest (the idle "you'll fire THIS way" preview) that
    // grows long + bright as the charge fills — so the bump direction is always
    // on screen and a tap never fires in a surprise direction.
    final len = ballR * (1.2 + 2.7 * c);
    final a = 0.4 + 0.55 * c; // overall opacity: dim idle → bold charged
    final start = center + dir * base;
    final end = center + dir * (base + len);
    final w = ballR * (0.22 + 0.26 * c);

    // Layered solid shaft: a wide soft-tinted base, a crisp colored core, then a
    // white inner line so it pops over the neon floor — all blur-free.
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color.withValues(alpha: 0.45 * a)
        ..strokeWidth = w * 1.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color.withValues(alpha: 0.95 * a)
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = _white.withValues(alpha: 0.6 * a)
        ..strokeWidth = w * 0.4
        ..strokeCap = StrokeCap.round,
    );

    // Arrowhead (color fill + white outline).
    final perp = Offset(-dir.dy, dir.dx);
    final head = ballR * (0.6 + 0.34 * c);
    final tip = end + dir * head;
    final left = end + perp * head * 0.66;
    final right = end - perp * head * 0.66;
    final headPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(headPath, Paint()..color = color.withValues(alpha: 0.95 * a));
    canvas.drawPath(
      headPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, ballR * 0.08)
        ..color = _white.withValues(alpha: 0.7 * a),
    );

    // Charge ground-arc beneath the ball — only once a hold is building.
    if (c > 0.01) {
      final groundCenter = center.translate(0, ballR);
      canvas.drawArc(
        Rect.fromCircle(center: groundCenter, radius: ballR * 1.25),
        -math.pi / 2,
        math.pi * 2 * c,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ballR * 0.18
          ..strokeCap = StrokeCap.round
          ..color = _blend(color, _white, c).withValues(alpha: 0.9),
      );
    }
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  static double _easeOut(double t) {
    final x = t.clamp(0.0, 1.0);
    return 1 - (1 - x) * (1 - x);
  }

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  /// Pick black or white text for legibility against [bg].
  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }

  static Offset _normalize(Offset v) {
    final d = v.distance;
    if (d < 1e-6) return Offset.zero;
    return v / d;
  }

  static void _drawNumber(
    Canvas canvas,
    Offset center,
    String text,
    double fontSize,
    Color color,
  ) {
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
      ..layout(ParagraphConstraints(width: fontSize * 3));
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - fontSize * 1.5, center.dy - fontSize * 0.62),
    );
  }
}
