import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';
import 'striker.dart';

/// One side's accent + score, packaged so the renderer never reaches into game
/// state. Immutable value type.
class SoccerSide {
  /// Accent color for this side's goal net, scoreboard chip and ground rings.
  final Color color;

  /// Current score shown on the scoreboard.
  final int score;

  /// Short label (e.g. "TOP"/"BOT" or a team letter) for the scoreboard chip.
  final String label;

  const SoccerSide({
    required this.color,
    required this.score,
    required this.label,
  });
}

/// A drawable snapshot of one player for the renderer. Immutable value type so
/// the renderer stays a pure function of its inputs.
class SoccerActor {
  final StickFigure figure;

  /// Pelvis/render anchor for the figure (feet planted on the ground line).
  final Offset root;

  /// Ground-contact center (feet) used for the shadow + ground ring.
  final Offset feet;

  /// Footprint radius used to size the shadow / ground ring.
  final double radius;

  /// Side accent color (also the ground-ring color).
  final Color color;

  /// 1-based number drawn in the ground ring.
  final int number;

  /// 0..1 kick flash used to brighten/scale the ground ring on a kick.
  final double kickFlash;

  /// Origin of the active kick trail (null when none). Drawn behind the figure.
  final Offset? trailFrom;

  /// Unit direction of the active kick trail (zero when none).
  final Offset trailDir;

  /// 0..1 remaining strength of the kick trail (0 when none).
  final double trailStrength;

  const SoccerActor({
    required this.figure,
    required this.root,
    required this.feet,
    required this.radius,
    required this.color,
    required this.number,
    this.kickFlash = 0,
    this.trailFrom,
    this.trailDir = Offset.zero,
    this.trailStrength = 0,
  });

  /// Build an actor for the player at [feet] (figure planted on its disc), 1-based
  /// [number], with the optional kick [trail] supplying the streak + flash.
  factory SoccerActor.fromParts({
    required int playerId,
    required Offset feet,
    required double radius,
    required StickFigure figure,
    required Color color,
    DashTrail? trail,
  }) =>
      SoccerActor(
        figure: figure,
        root: feet, // pelvis anchors at feet so the stick stands on its disc
        feet: feet,
        radius: radius,
        color: color,
        number: playerId + 1,
        kickFlash: trail?.strength ?? 0,
        trailFrom: trail?.from,
        trailDir: trail?.dir ?? Offset.zero,
        trailStrength: trail?.strength ?? 0,
      );
}

/// Pure-Canvas rendering for One-Touch Soccer. Holds NO game state and never
/// mutates the simulation — callers pass plain value snapshots. Kept in its own
/// file so the gameplay module stays lean and the drawing stays cohesive.
///
/// The pitch is NORTH/SOUTH: goals sit on the TOP and BOTTOM walls, the turf is
/// mowed in horizontal bands and the penalty boxes hug the top and bottom.
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`). For
/// performance there are NO per-entity blur mask filters — soft edges are faked
/// with cheap layered solid strokes/fills so the game stays smooth.
class SoccerRenderer {
  SoccerRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _stadiumTop = Color(0xFF0A1A12);
  static const Color _stadiumBottom = Color(0xFF03070A);
  static const Color _turfLight = Color(0xFF2BA85A);
  static const Color _turfDark = Color(0xFF1F8E49);
  static const Color _turfShadeLeft = Color(0x33A8FFC8);
  static const Color _turfShadeRight = Color(0x33000000);
  static const Color _border = Color(0xFF05130B);
  static const Color _line = Color(0xFFF2FFF6);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _ballSeam = Color(0xFF12202B);
  static const Color _crowdGlow = Color(0x1AFFFFFF);

  // ── Tuning (no magic numbers inline) ───────────────────────────────────────
  static const int _stripeCount = 12;
  static const double _lineWidthFactor = 0.006; // line stroke / pitch shortSide
  static const double _centerCircleFactor = 0.13; // radius / shortSide
  static const double _penaltyDepthFactor = 0.16; // box depth / pitch height
  static const double _penaltyWidthFactor = 0.52; // box width / pitch width
  static const double _netCellFactor = 0.16; // net cell / mouth width
  static const double _postWidthFactor = 0.018; // post stroke / pitch shortSide
  static const double _goalDepthFactor = 0.05; // net depth / pitch height
  static const double _vignetteFactor = 0.62; // vignette inset
  static const double _ballTrailStep = 0.55; // trail node spacing fade
  static const double _shadowDropFactor = 1.1; // ball shadow drop / radius
  static const double _scoreboardHeightFactor = 0.052; // of pitch height
  static const double _twoPi = math.pi * 2;

  // Soft-edge faking: how many concentric layers approximate a blur. Cheap vs
  // MaskFilter.
  static const int _softLayers = 3;

  // Joystick geometry (the on-screen virtual stick).
  static const double _joyBaseAlpha = 0.16; // base disc fill
  static const double _joyRingAlpha = 0.5; // base ring stroke
  static const double _joyThumbFactor = 0.42; // thumb radius / base radius

  // ── Background: stadium gradient + dark crowd haze ─────────────────────────
  static void drawBackground(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_stadiumTop, _stadiumBottom],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // Soft crowd glow band near the top edge for stadium depth.
    final glow = Paint()
      ..shader = Gradient.radial(
        Offset(size.width / 2, size.height * 0.06),
        size.width * 0.7,
        const [_crowdGlow, Color(0x00000000)],
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  /// The pitch: dark stadium border, alternating mowed HORIZONTAL bands (with a
  /// subtle left-light / right-shade overlay), perimeter line, center line +
  /// circle and both penalty boxes (top + bottom).
  static void drawPitch(Canvas canvas, Rect pitch) {
    if (pitch.width <= 2 || pitch.height <= 2) return;
    final shortSide = pitch.shortestSide;
    final lineW = math.max(1.5, shortSide * _lineWidthFactor);

    // Stadium-dark border ring just outside the pitch.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        pitch.inflate(shortSide * 0.02),
        Radius.circular(shortSide * 0.03),
      ),
      Paint()..color = _border,
    );

    // Mowed horizontal bands.
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
      pitch,
      Radius.circular(shortSide * 0.02),
    ));
    final bandH = pitch.height / _stripeCount;
    final bandPaint = Paint();
    for (var i = 0; i < _stripeCount; i++) {
      bandPaint.color = i.isEven ? _turfLight : _turfDark;
      canvas.drawRect(
        Rect.fromLTWH(
          pitch.left,
          pitch.top + i * bandH,
          pitch.width,
          bandH + 1,
        ),
        bandPaint,
      );
    }
    // Horizontal light → shade gradient overlay for grassy depth.
    canvas.drawRect(
      pitch,
      Paint()
        ..shader = Gradient.linear(
          pitch.centerLeft,
          pitch.centerRight,
          const [_turfShadeLeft, Color(0x00000000), _turfShadeRight],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.restore();

    _drawMarkings(canvas, pitch, lineW);
  }

  static void _drawMarkings(Canvas canvas, Rect pitch, double lineW) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineW
      ..color = _line.withValues(alpha: 0.82);

    // Perimeter.
    canvas.drawRect(pitch.deflate(lineW), line);

    // Halfway line (horizontal) + center circle + spot.
    canvas.drawLine(
      Offset(pitch.left + lineW, pitch.center.dy),
      Offset(pitch.right - lineW, pitch.center.dy),
      line,
    );
    final circleR = pitch.shortestSide * _centerCircleFactor;
    canvas.drawCircle(pitch.center, circleR, line);
    canvas.drawCircle(
        pitch.center, math.max(2.0, lineW * 1.4), Paint()..color = _line);

    // Penalty boxes on the top + bottom, centered horizontally.
    final boxDepth = pitch.height * _penaltyDepthFactor;
    final boxWidth = pitch.width * _penaltyWidthFactor;
    final boxLeft = pitch.center.dx - boxWidth / 2;
    canvas.drawRect(
      Rect.fromLTWH(boxLeft, pitch.top + lineW, boxWidth, boxDepth),
      line,
    );
    canvas.drawRect(
      Rect.fromLTWH(
          boxLeft, pitch.bottom - lineW - boxDepth, boxWidth, boxDepth),
      line,
    );
  }

  /// A goal: a netted mouth on the top or bottom wall. [onBottom] selects the
  /// bottom wall (else the top). [bulge] in 0..1 flashes a net ripple after a
  /// recent goal.
  static void drawGoal(
    Canvas canvas,
    Rect pitch,
    Rect mouth, {
    required bool onBottom,
    required Color color,
    required double bulge,
  }) {
    if (mouth.width <= 2) return;
    final shortSide = pitch.shortestSide;
    final depth = pitch.height * _goalDepthFactor;
    final y = onBottom ? pitch.bottom : pitch.top;
    final inward = onBottom ? -1.0 : 1.0;
    final backY = y - inward * depth;
    final mouthW = mouth.width;
    final cell = math.max(6.0, mouthW * _netCellFactor);

    // Net recess background (dim) so the mesh reads against the turf.
    final recess = Rect.fromLTRB(
      mouth.left,
      math.min(y, backY),
      mouth.right,
      math.max(y, backY),
    );
    canvas.drawRect(recess, Paint()..color = _black.withValues(alpha: 0.30));

    // Net bulge ripple after a goal: a soft colored swell pushed into the net.
    final b = bulge.clamp(0.0, 1.0);
    if (b > 0.01) {
      final swell = Paint()
        ..shader = Gradient.radial(
          Offset(mouth.center.dx, backY),
          depth * 1.6,
          [color.withValues(alpha: 0.5 * b), const Color(0x00000000)],
        );
      canvas.drawRect(recess, swell);
    }

    // Net mesh: horizontal + vertical strands, slightly displaced by the bulge.
    final mesh = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, shortSide * 0.0025)
      ..color = _white.withValues(alpha: 0.34 + 0.30 * b);
    final push = inward * depth * 0.4 * b;
    for (var gy = 0.0; gy <= depth; gy += cell) {
      final sy = y - inward * gy;
      canvas.drawLine(
          Offset(mouth.left, sy), Offset(mouth.right, sy), mesh);
    }
    for (var gx = mouth.left; gx <= mouth.right; gx += cell) {
      // Mid strands sag toward the back when the net bulges.
      final t = ((gx - mouth.left) / mouthW - 0.5).abs() * 2; // 0 mid → 1 edge
      final sag = push * (1 - t);
      canvas.drawLine(
        Offset(gx, y),
        Offset(gx, backY + sag),
        mesh,
      );
    }

    // Posts + crossbars in the side accent.
    final postW = math.max(2.5, shortSide * _postWidthFactor);
    final post = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = postW
      ..strokeCap = StrokeCap.round
      ..color = color;
    // Front goal line (the mouth) gets a cheap layered glow + a crisp bar.
    _strokeSoftLine(canvas, Offset(mouth.left, y), Offset(mouth.right, y),
        color, postW);
    canvas.drawLine(Offset(mouth.left, y), Offset(mouth.right, y), post);
    // Side bars receding to the back of the net.
    canvas.drawLine(Offset(mouth.left, y), Offset(mouth.left, backY), post);
    canvas.drawLine(Offset(mouth.right, y), Offset(mouth.right, backY), post);
    canvas.drawLine(
        Offset(mouth.left, backY), Offset(mouth.right, backY), post);
  }

  /// Solid contact shadow ellipse + a colored ground ring with a number, drawn
  /// beneath one player. [kickFlash] in 0..1 brightens the ring on a kick. No
  /// blur — the shadow is a single soft-tinted oval.
  static void drawActorGround(Canvas canvas, SoccerActor a) {
    final r = a.radius;
    // Shadow (flat tint, no mask filter).
    canvas.drawOval(
      Rect.fromCenter(center: a.feet, width: r * 2.6, height: r * 0.8),
      Paint()..color = _black.withValues(alpha: 0.30),
    );
    // Ground ring (brightens with kick flash).
    final flash = a.kickFlash.clamp(0.0, 1.0);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, r * (0.12 + 0.10 * flash))
      ..color = Color.lerp(a.color.withValues(alpha: 0.9), _white, 0.5 * flash) ??
          a.color;
    canvas.drawOval(
      Rect.fromCenter(center: a.feet, width: r * 3.0, height: r * 1.05),
      ring,
    );
    // Number pip.
    final pip = a.feet.translate(0, r * 0.04);
    final pr = r * 0.42;
    canvas.drawCircle(pip, pr, Paint()..color = a.color);
    canvas.drawCircle(
      pip,
      pr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, pr * 0.2)
        ..color = _white.withValues(alpha: 0.85),
    );
    _drawText(canvas, '${a.number}', pip, pr * 1.3, _readableText(a.color),
        FontWeight.w900);
  }

  /// Render the stick player itself (figure owns its own pose state).
  static void drawActor(Canvas canvas, SoccerActor a) {
    a.figure.render(canvas, a.root);
  }

  /// A short directional motion streak behind a kicking striker, drawn from
  /// [SoccerActor.trailFrom] along [SoccerActor.trailDir]. No-op when there is
  /// no active trail. Uses layered solid strokes (no blur) for a soft look.
  static void drawDashTrail(Canvas canvas, SoccerActor a) {
    final from = a.trailFrom;
    final s = a.trailStrength.clamp(0.0, 1.0);
    if (from == null || s <= 0.01 || a.trailDir == Offset.zero) return;
    final r = a.radius;
    final to = from + a.trailDir * (r * 2.4);
    final baseW = r * (0.55 + 0.8 * s);
    // Outer-to-inner layered strokes fake a glow without a mask filter.
    for (var i = _softLayers; i >= 1; i--) {
      final f = i / _softLayers; // 1 outer → ~0.33 inner
      canvas.drawLine(
        from,
        to,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = baseW * (0.5 + f)
          ..color = a.color.withValues(alpha: 0.12 * s * (1.2 - f)),
      );
    }
  }

  /// The on-screen virtual joystick for one human player: a translucent base
  /// disc + ring at [origin] and a brighter thumb at [thumb], clamped to
  /// [maxRadius]. Drawn in the player's [color] so each stick is identifiable.
  static void drawJoystick(
    Canvas canvas, {
    required Offset origin,
    required Offset thumb,
    required double maxRadius,
    required Color color,
  }) {
    if (maxRadius <= 1) return;
    // Clamp the thumb inside the base radius.
    final v = thumb - origin;
    final d = v.distance;
    final clamped =
        d > maxRadius && d > 0 ? origin + (v / d) * maxRadius : thumb;

    // Base disc + ring.
    canvas.drawCircle(origin, maxRadius,
        Paint()..color = color.withValues(alpha: _joyBaseAlpha));
    canvas.drawCircle(
      origin,
      maxRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, maxRadius * 0.06)
        ..color = color.withValues(alpha: _joyRingAlpha),
    );

    // A faint line from base center to the thumb shows the steer direction.
    canvas.drawLine(
      origin,
      clamped,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(2.0, maxRadius * 0.05)
        ..color = color.withValues(alpha: 0.45),
    );

    // Thumb: solid color core + white rim.
    final thumbR = maxRadius * _joyThumbFactor;
    canvas.drawCircle(
        clamped, thumbR, Paint()..color = color.withValues(alpha: 0.92));
    canvas.drawCircle(
      clamped,
      thumbR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, thumbR * 0.18)
        ..color = _white.withValues(alpha: 0.9),
    );
  }

  /// The ball: motion trail → contact shadow → white body with a faint
  /// pentagon/seam hint and a directional highlight. [squash] in 0..1 flattens
  /// it along [velDir] after a hard hit; [trail] is newest→oldest centers. The
  /// shadow is a flat tinted oval (no mask filter).
  static void drawBall(
    Canvas canvas,
    Offset pos,
    double radius, {
    required List<Offset> trail,
    required Offset velDir,
    required double spin,
    required double squash,
  }) {
    if (radius <= 0) return;

    // Motion trail: fading discs behind the ball.
    if (trail.length > 1) {
      final paint = Paint();
      for (var i = trail.length - 1; i >= 0; i--) {
        final f = (i + 1) / trail.length; // 1 newest → ~0 oldest
        paint.color = _white.withValues(alpha: 0.18 * f * _ballTrailStep);
        canvas.drawCircle(trail[i], radius * (0.5 + 0.5 * f), paint);
      }
    }

    // Contact shadow on the turf (flat tint).
    canvas.drawOval(
      Rect.fromCenter(
        center: pos.translate(0, radius * _shadowDropFactor),
        width: radius * 2.0,
        height: radius * 0.7,
      ),
      Paint()..color = _black.withValues(alpha: 0.28),
    );

    // Squash transform: flatten along travel direction, stretch across it.
    final s = squash.clamp(0.0, 1.0);
    final ang = velDir == Offset.zero ? 0.0 : math.atan2(velDir.dy, velDir.dx);
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(ang);
    canvas.scale(1.0 - 0.30 * s, 1.0 + 0.22 * s);
    canvas.rotate(-ang);

    // Body with a soft top-left sheen.
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = Gradient.radial(
          Offset(-radius * 0.3, -radius * 0.35),
          radius * 1.5,
          const [_white, Color(0xFFD7E2EC)],
        ),
    );

    // Faint pentagon seam hint, rotated by spin.
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, radius * 0.10)
      ..strokeJoin = StrokeJoin.round
      ..color = _ballSeam.withValues(alpha: 0.55);
    final penta = Path();
    for (var i = 0; i < 5; i++) {
      final a = spin + i * _twoPi / 5 - math.pi / 2;
      final p = Offset(math.cos(a), math.sin(a)) * radius * 0.5;
      if (i == 0) {
        penta.moveTo(p.dx, p.dy);
      } else {
        penta.lineTo(p.dx, p.dy);
      }
    }
    penta.close();
    canvas.drawPath(penta, seam);
    // Short spokes from the pentagon corners to the rim.
    for (var i = 0; i < 5; i++) {
      final a = spin + i * _twoPi / 5 - math.pi / 2;
      final inner = Offset(math.cos(a), math.sin(a)) * radius * 0.5;
      final outer = Offset(math.cos(a), math.sin(a)) * radius * 0.92;
      canvas.drawLine(inner, outer, seam);
    }

    // Crisp outline.
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, radius * 0.12)
        ..color = _ballSeam,
    );
    canvas.restore();
  }

  /// A vignette darkening the screen corners for stadium focus.
  static void drawVignette(Canvas canvas, Size size) {
    final r = size.longestSide * _vignetteFactor;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height / 2),
          r,
          const [Color(0x00000000), Color(0x66000000)],
          const [0.62, 1.0],
        ),
    );
  }

  /// A scoreboard at the top: two color chips with each side's score and a
  /// countdown clock in the middle. [secondsLeft] is clamped to ≥ 0.
  static void drawScoreboard(
    Canvas canvas,
    Rect pitch,
    SoccerSide top,
    SoccerSide bottom,
    double secondsLeft,
  ) {
    final h = math.max(22.0, pitch.height * _scoreboardHeightFactor);
    final w = math.min(pitch.width * 0.62, h * 7.5);
    final center = Offset(pitch.center.dx, pitch.top + h * 0.9);
    final bar = Rect.fromCenter(center: center, width: w, height: h);
    final rrect = RRect.fromRectAndRadius(bar, Radius.circular(h * 0.32));

    // Backing panel.
    canvas.drawRRect(
        rrect, Paint()..color = _black.withValues(alpha: 0.55));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, h * 0.06)
        ..color = _white.withValues(alpha: 0.16),
    );

    // Top-side chip (left of the bar).
    final chipW = h * 1.5;
    _drawScoreChip(
      canvas,
      Rect.fromLTWH(bar.left, bar.top, chipW, h),
      top.color,
      '${top.score}',
      top.label,
    );
    // Bottom-side chip (right of the bar).
    _drawScoreChip(
      canvas,
      Rect.fromLTWH(bar.right - chipW, bar.top, chipW, h),
      bottom.color,
      '${bottom.score}',
      bottom.label,
    );

    // Clock in the middle.
    final secs = secondsLeft.clamp(0.0, 5999.0);
    final mm = (secs ~/ 60).toString();
    final ss = (secs % 60).floor().toString().padLeft(2, '0');
    _drawText(canvas, '$mm:$ss', center.translate(0, -h * 0.02), h * 0.5,
        _white, FontWeight.w800);
  }

  static void _drawScoreChip(
    Canvas canvas,
    Rect rect,
    Color color,
    String score,
    String label,
  ) {
    final rr = RRect.fromRectAndRadius(
        rect.deflate(rect.height * 0.12), Radius.circular(rect.height * 0.26));
    canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: 0.9));
    _drawText(canvas, score, rect.center.translate(0, -rect.height * 0.02),
        rect.height * 0.5, _readableText(color), FontWeight.w900);
    // Tiny side label above the number.
    _drawText(
        canvas,
        label,
        rect.center.translate(0, -rect.height * 0.42),
        rect.height * 0.20,
        _readableText(color).withValues(alpha: 0.85),
        FontWeight.w700);
  }

  /// A centered kickoff banner during the brief pause before the next kickoff.
  /// [alpha] fades it in/out.
  static void drawKickoffBanner(
    Canvas canvas,
    Rect pitch,
    String text,
    double alpha,
  ) {
    final a = alpha.clamp(0.0, 1.0);
    if (a <= 0.01) return;
    final fontSize = pitch.shortestSide * 0.085;
    _drawText(canvas, text, pitch.center, fontSize,
        _white.withValues(alpha: a), FontWeight.w900);
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  /// Fake a soft glow on a line with a few translucent over-strokes (cheaper
  /// than [MaskFilter.blur] and good enough at gameplay scale).
  static void _strokeSoftLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color,
    double baseW,
  ) {
    for (var i = _softLayers; i >= 1; i--) {
      final f = i / _softLayers; // 1 outer → inner
      canvas.drawLine(
        a,
        b,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = baseW * (1.0 + 1.4 * f)
          ..color = color.withValues(alpha: 0.18 * (1.2 - f)),
      );
    }
  }

  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color,
    FontWeight weight,
  ) {
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: weight,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: fontSize * 8));
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - fontSize * 4, center.dy - fontSize * 0.62),
    );
  }
}
