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
  // Stadium crowd-glow tiers (stacked translucent radials, NOT MaskFilter).
  static const Color _crowdGlowWarm = Color(0x14FBBF24); // amber haze, far side
  static const Color _crowdGlowCool = Color(0x1222D3EE); // cyan rim, near side
  static const Color _floodCool = Color(0x2238E0FF); // cool floodlight wash
  static const Color _floodWarm = Color(0x1AFFE6A8); // warm floodlight wash
  // Moving sun-reflection shimmer sweeping the grass.
  static const Color _grassShimmer = Color(0x26FFFFFF);
  // Vivid scoring-shot ball trail (fast strike streak).
  static const Color _ballFlame = Color(0xFFFFE08A);
  static const Color _ballHotCore = Color(0xFFFFFFFF);

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

  static const double _goalZoneGlowFactor = 0.18; // end-zone glow depth / height
  static const double _shimmerWidthFactor = 0.34; // moving grass shimmer band w
  static const double _shimmerSweepPerFrame = 0.0042; // shimmer phase / frame
  static const double _goalFlashFactor = 0.5; // goal-mouth flash reach / depth
  static const double _ballSpinLineFactor = 0.62; // spin streak length / radius

  // Soft-edge faking: how many concentric layers approximate a blur. Cheap vs
  // MaskFilter.
  static const int _softLayers = 3;

  // Monotonic frame phase, advanced once per [drawBackground] (the first draw
  // each frame). Drives the slow sun-reflection shimmer across the grass without
  // a new Ticker or any non-deterministic clock (no DateTime.now / random). The
  // host repaints every frame, so this reads as smooth continuous motion.
  static double _framePhase = 0;

  // Joystick geometry (the on-screen virtual stick).
  static const double _joyBaseAlpha = 0.16; // base disc fill
  static const double _joyRingAlpha = 0.5; // base ring stroke
  static const double _joyThumbFactor = 0.42; // thumb radius / base radius

  // ── Background: stadium gradient + dark crowd haze ─────────────────────────
  // This is the first draw call each frame, so it also advances the shared
  // monotonic [_framePhase] that animates the grass shimmer — keeping every
  // moving effect on one cheap, deterministic clock (no new Ticker).
  static void drawBackground(Canvas canvas, Size size) {
    _framePhase += _shimmerSweepPerFrame;
    final full = Offset.zero & size;
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_stadiumTop, _stadiumBottom],
      );
    canvas.drawRect(full, bg);

    // Floodlight washes spilling in from the top corners (cool left, warm
    // right) — stacked translucent radials for stadium-lighting depth.
    canvas.drawRect(
      full,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width * 0.16, -size.height * 0.04),
          size.width * 0.8,
          const [_floodCool, Color(0x00000000)],
        ),
    );
    canvas.drawRect(
      full,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width * 0.86, -size.height * 0.05),
          size.width * 0.78,
          const [_floodWarm, Color(0x00000000)],
        ),
    );

    // Richer crowd glow band near the top edge: a bright white core with a
    // warm amber halo and a cool cyan rim, so the stands read as a lit crowd
    // rather than a flat haze.
    canvas.drawRect(
      full,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.04),
          size.width * 0.95,
          const [_crowdGlowWarm, Color(0x00000000)],
        ),
    );
    canvas.drawRect(
      full,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.07),
          size.width * 0.7,
          const [_crowdGlow, Color(0x00000000)],
        ),
    );
    // Thin cool rim hugging the very top so the upper crowd has a neon edge.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.22),
      Paint()
        ..shader = Gradient.linear(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height * 0.22),
          const [_crowdGlowCool, Color(0x00000000)],
        ),
    );
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

    // Goal-zone glow: a soft colored swell at each end so the danger areas in
    // front of the nets read hotter than midfield. Static (no clock).
    _drawGoalZoneGlow(canvas, pitch);

    // Moving sun-reflection shimmer: a soft vertical light band sweeping left↔
    // right across the turf, eased so it dwells at the edges. Driven by the
    // shared frame phase — pure sin(phase), deterministic.
    _drawGrassShimmer(canvas, pitch);

    canvas.restore();

    _drawMarkings(canvas, pitch, lineW);
  }

  /// Soft end-zone glow in front of each goal (top + bottom). Drawn inside the
  /// pitch clip so it never spills onto the border. Color-neutral white so it
  /// reads as turf sheen, not a team tint (goals own the colored accents).
  static void _drawGoalZoneGlow(Canvas canvas, Rect pitch) {
    final depth = pitch.height * _goalZoneGlowFactor;
    final reach = math.max(pitch.width * 0.5, depth * 2.2);
    const hot = Color(0x1FFFFFFF);
    canvas.drawRect(
      pitch,
      Paint()
        ..shader = Gradient.radial(
          Offset(pitch.center.dx, pitch.top - depth * 0.2),
          reach,
          const [hot, Color(0x00000000)],
        ),
    );
    canvas.drawRect(
      pitch,
      Paint()
        ..shader = Gradient.radial(
          Offset(pitch.center.dx, pitch.bottom + depth * 0.2),
          reach,
          const [hot, Color(0x00000000)],
        ),
    );
  }

  /// A slow sun-reflection shimmer band that sweeps horizontally across the
  /// grass. Position is `sin(_framePhase)` eased to a 0..1 sweep so the band
  /// lingers at each touchline before gliding back — a living-pitch sparkle.
  static void _drawGrassShimmer(Canvas canvas, Rect pitch) {
    final t = 0.5 + 0.5 * math.sin(_framePhase);
    final bandW = pitch.width * _shimmerWidthFactor;
    final cx = pitch.left + bandW * 0.5 + (pitch.width - bandW) * t;
    final left = cx - bandW * 0.5;
    final right = cx + bandW * 0.5;
    canvas.drawRect(
      pitch,
      Paint()
        ..shader = Gradient.linear(
          Offset(left, pitch.top),
          Offset(right, pitch.bottom),
          const [Color(0x00000000), _grassShimmer, Color(0x00000000)],
          const [0.0, 0.5, 1.0],
        ),
    );
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
    // Net SHAKE: as the swell fades the mesh quivers. Amplitude rides the bulge
    // and a fast ripple wave runs across the mouth (deterministic sin, no clock).
    final shakeAmp = cell * 0.55 * b;
    final shakePhase = _framePhase * 9.0;
    for (var gy = 0.0; gy <= depth; gy += cell) {
      final sy = y - inward * gy;
      // Horizontal strands ripple vertically more toward the back of the net.
      final depthT = (gy / depth).clamp(0.0, 1.0);
      final wob = shakeAmp * depthT * math.sin(shakePhase + gy * 0.18);
      canvas.drawLine(
          Offset(mouth.left, sy + wob), Offset(mouth.right, sy + wob), mesh);
    }
    for (var gx = mouth.left; gx <= mouth.right; gx += cell) {
      // Mid strands sag toward the back when the net bulges.
      final t = ((gx - mouth.left) / mouthW - 0.5).abs() * 2; // 0 mid → 1 edge
      final sag = push * (1 - t);
      // Lateral quiver, strongest in the middle of the mouth and at the back.
      final quiver = shakeAmp * (1 - t) * math.sin(shakePhase + gx * 0.07);
      canvas.drawLine(
        Offset(gx, y),
        Offset(gx + quiver, backY + sag),
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

    // GOAL FLASH: when a goal just scored ([bulge] > 0) the whole mouth pulses
    // — a fat halo behind the goal line plus a stack of bright over-strokes on
    // the bar in the side accent. Throbs on the shared frame phase. Sits on the
    // top/bottom wall, well clear of the ball-centered aim/power overlay.
    if (b > 0.01) {
      final throb = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(_framePhase * 11.0));
      final hot = Color.lerp(color, _white, 0.45) ?? color;
      // Halo bloom centered on the mouth, reaching toward the back of the net.
      canvas.drawRect(
        Rect.fromLTRB(mouth.left - postW * 2, math.min(y, backY) - postW,
            mouth.right + postW * 2, math.max(y, backY) + postW),
        Paint()
          ..shader = Gradient.radial(
            Offset(mouth.center.dx, y),
            mouthW * (_goalFlashFactor + 0.45),
            [hot.withValues(alpha: 0.55 * b * throb), const Color(0x00000000)],
          ),
      );
      // Stacked glow on the front bar (cheap fake-bloom, no MaskFilter).
      for (var i = _softLayers; i >= 1; i--) {
        final f = i / _softLayers;
        canvas.drawLine(
          Offset(mouth.left, y),
          Offset(mouth.right, y),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = postW * (1.0 + 2.2 * f)
            ..color = hot.withValues(alpha: 0.5 * b * throb * (1.2 - f)),
        );
      }
    }
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
  /// When [armed] the thumb wears a bright halo ring — the "tap will SHOOT the
  /// next touch" cue — versus a plain thumb while it would only trap/dribble.
  static void drawJoystick(
    Canvas canvas, {
    required Offset origin,
    required Offset thumb,
    required double maxRadius,
    required Color color,
    bool armed = false,
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
    // Armed-to-shoot halo: a bright ring just outside the thumb so a kid can see
    // their next touch will SHOOT (a plain thumb = the touch will trap/dribble).
    if (armed) {
      canvas.drawCircle(
        clamped,
        thumbR * 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, thumbR * 0.3)
          ..color = _white.withValues(alpha: 0.7),
      );
    }
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

    // Speed read straight from the trail's node spacing (the data already says
    // how fast the ball travels — no extra param, no clock). 0 at rest → 1 on a
    // hard, fast strike. Used to escalate the trail into a scoring-shot streak.
    final heat = _trailHeat(trail, radius);

    // Motion trail. On a fast shot ([heat] high) it ignites into a vivid flame
    // streak: a wide amber underlay topped by a hot white core, then the usual
    // fading white discs ride on top. At rest it stays the soft white tail.
    if (trail.length > 1) {
      if (heat > 0.05) {
        final tip = trail.last;
        final tail = trail.first;
        // Amber bloom underlay (cheap stacked strokes, no MaskFilter).
        for (var i = _softLayers; i >= 1; i--) {
          final f = i / _softLayers;
          canvas.drawLine(
            tail,
            tip,
            Paint()
              ..strokeCap = StrokeCap.round
              ..strokeWidth = radius * (0.9 + 1.6 * f) * heat
              ..color = _ballFlame.withValues(alpha: 0.30 * heat * (1.2 - f)),
          );
        }
        // Hot white core down the center of the streak.
        canvas.drawLine(
          tail,
          tip,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = radius * (0.45 + 0.5 * heat)
            ..color = _ballHotCore.withValues(alpha: 0.5 * heat),
        );
      }
      final paint = Paint();
      for (var i = trail.length - 1; i >= 0; i--) {
        final f = (i + 1) / trail.length; // 1 newest → ~0 oldest
        // The discs brighten on a fast shot so the streak reads as molten.
        paint.color = Color.lerp(_white, _ballFlame, 0.5 * heat)!
            .withValues(alpha: (0.18 + 0.22 * heat) * f * _ballTrailStep);
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

    // Rolling SPIN LINES: two short rim arcs on opposite sides that orbit with
    // [spin], so a rolling ball visibly rotates (not just a static seam). Drawn
    // as faint dark strokes near the edge — they read as the ball turning over.
    final spinLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, radius * 0.12)
      ..color = _ballSeam.withValues(alpha: 0.42);
    final spinRect = Rect.fromCircle(
        center: Offset.zero, radius: radius * _ballSpinLineFactor);
    const arcSpan = math.pi * 0.5;
    canvas.drawArc(spinRect, spin, arcSpan, false, spinLine);
    canvas.drawArc(spinRect, spin + math.pi, arcSpan, false, spinLine);

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

  /// A vignette darkening the screen corners for stadium focus. Two stacked
  /// radials: a deep neutral darken plus a faint cool tint in the far corners,
  /// so the frame feels like a lit arena at night. Drawn before the HUD, so the
  /// scoreboard always stays crisp on top.
  static void drawVignette(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.longestSide * _vignetteFactor;
    // Cool tint blooming in from the corners (subtle, under the darken).
    canvas.drawRect(
      full,
      Paint()
        ..shader = Gradient.radial(
          center,
          r * 1.05,
          const [Color(0x00000000), Color(0x141A2A4D)],
          const [0.55, 1.0],
        ),
    );
    // Primary corner darken for focus.
    canvas.drawRect(
      full,
      Paint()
        ..shader = Gradient.radial(
          center,
          r,
          const [Color(0x00000000), Color(0x70000000)],
          const [0.6, 1.0],
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

  /// Ball "heat" in 0..1 derived purely from how far apart the latest trail
  /// nodes sit (the trail is sampled once per frame, so wide gaps = fast ball =
  /// a scoring strike). Deterministic from the passed data — no clock, no speed
  /// param needed. Below a knee it stays 0 so a slow dribble keeps a calm tail.
  static double _trailHeat(List<Offset> trail, double radius) {
    final n = trail.length;
    if (n < 3 || radius <= 0) return 0;
    // Average spacing over the last few segments (newest end = fastest motion).
    final span = math.min(4, n - 1);
    var sum = 0.0;
    for (var i = n - span; i < n; i++) {
      sum += (trail[i] - trail[i - 1]).distance;
    }
    final avgGap = sum / span;
    // A gap near the radius is a brisk roll; ~3× radius/frame is a hard shot.
    const knee = 0.9; // gap/radius below this → no streak
    final norm = (avgGap / radius - knee) / 2.2;
    return norm.clamp(0.0, 1.0);
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
