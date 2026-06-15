import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Pure-Canvas rendering for [TugOfWar] — a VERTICAL (north/south) rope pull on
/// the tall portrait screen: a top team and a bottom team haul a vertical rope,
/// the marker rides up/down between two goal lines, and the losing team is
/// yanked off the top/bottom edge into a central pit.
///
/// Holds NO game state and never mutates the simulation — callers pass plain
/// value snapshots. Kept in its own file so the gameplay module stays lean and
/// the drawing stays cohesive (mirrors the sumo_smash split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
///
/// Performance: this file draws every entity each frame, so it avoids
/// `MaskFilter.blur` in per-entity/per-loop paint. Soft glows are faked with
/// stacked translucent solid strokes/fills (a wide faint layer under a crisp
/// one), which reads similarly at a fraction of the cost.
class TugRenderer {
  TugRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _bgTop = Color(0xFF1A1322);
  static const Color _bgMid = Color(0xFF120C1A);
  static const Color _bgBottom = Color(0xFF070409);
  static const Color _vignette = Color(0x99000000);
  static const Color _spotlight = Color(0x18FFE6B0);
  static const Color _groundLine = Color(0x33FFFFFF);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  // Pit (mud/lava) palette.
  static const Color _pitOuter = Color(0xFF120A06);
  static const Color _pitMud0 = Color(0xFF6E2E0E);
  static const Color _pitMud1 = Color(0xFFB8500F);
  static const Color _pitLava = Color(0xFFFFC23A);
  static const Color _pitRim = Color(0xFFFF7A1A);
  static const Color _pitRimGlow = Color(0xFFFFB54D);
  // Atmosphere accents (neon-glass identity).
  static const Color _flame = Color(0xFFFB7234);
  static const Color _ember = Color(0xFFFFD27A);
  static const Color _steam = Color(0xFFB9A8C8);

  // Rope palette.
  static const Color _ropeCore = Color(0xFFE8C98C);
  static const Color _ropeDark = Color(0xFF9C6F3A);
  static const Color _ropeShade = Color(0xFF5E3F1F);
  static const Color _ropeShimmer = Color(0xFFFFF4D8);

  // ── Tuning (fractions of arena; no inline magic numbers) ────────────────────
  static const double _spotlightFactor = 0.9; // spotlight radius / height
  static const double _vignetteInnerFrac = 0.5; // clear-zone radius / diag
  static const double _vignetteOuterFrac = 0.72; // vignette radius / diag
  static const double _centerDashLen = 14;
  static const double _centerDashGap = 12;
  static const double _goalLineHalfFrac = 0.16; // goal line half-WIDTH / width

  // Pit rim stroke width relative to pit x-radius.
  static const double _pitRimWidthFrac = 0.024;

  // Rope layer widths (px).
  static const double _ropeShadowW = 14;
  static const double _ropeUnderW = 12;
  static const double _ropeBodyW = 9;
  static const double _ropeStrandW = 3.2; // each woven strand
  static const double _ropeGripW = 11;

  // Braid/shimmer tuning (visual-only, deterministic).
  static const int _ropeSamples = 28; // path samples for the woven strands
  static const double _braidTwists = 8.0; // helix turns down the rope
  static const double _braidAmpFrac = 0.34; // strand offset / body width

  // ── Background: gradient sky + soft stage spotlight ─────────────────────────
  static void drawBackground(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgMid, _bgBottom],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // Soft warm stage spotlight centered on the pit.
    final spotR = size.height * _spotlightFactor;
    if (spotR > 0) {
      final spotCenter = Offset(size.width / 2, size.height / 2);
      final spot = Paint()
        ..shader = Gradient.radial(
          spotCenter,
          spotR,
          const [_spotlight, Color(0x00000000)],
        );
      canvas.drawCircle(spotCenter, spotR, spot);
    }
  }

  /// Two dark "crowd" bands behind each team (top + bottom) so the standing rows
  /// read with depth. [bandFrac] is each band's height as a fraction of height.
  ///
  /// [lead] in -1..1 (-1 = top winning) makes the FAVOURED crowd bob/cheer —
  /// faint warm dot-rows ripple toward the marker's side. [t] is the animation
  /// clock. Both default to 0 so existing callers stay valid (additive). The
  /// dark depth bands underneath are unchanged.
  static void drawCrowdBands(
    Canvas canvas,
    Size size,
    double bandFrac, {
    double lead = 0,
    double t = 0,
  }) {
    final bandH = size.height * bandFrac.clamp(0.0, 0.4);
    if (bandH <= 0) return;
    // Top band (fades downward into the field).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, bandH),
      Paint()
        ..shader = Gradient.linear(
          const Offset(0, 0),
          Offset(0, bandH),
          const [Color(0x88000000), Color(0x00000000)],
        ),
    );
    // Bottom band (fades upward into the field).
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - bandH, size.width, bandH),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, size.height - bandH),
          Offset(0, size.height),
          const [Color(0x00000000), Color(0x88000000)],
        ),
    );

    // Cheering spectators: faint bobbing dot-rows. The side the marker swings
    // toward bobs harder + glows warmer (deterministic from index + t).
    final l = lead.clamp(-1.0, 1.0);
    _drawCheerRow(canvas, size, bandH, t, dir: -1, hype: (-l).clamp(0.0, 1.0));
    _drawCheerRow(canvas, size, bandH, t, dir: 1, hype: l.clamp(0.0, 1.0));
  }

  static void _drawCheerRow(
    Canvas canvas,
    Size size,
    double bandH,
    double t, {
    required double dir, // -1 top, +1 bottom
    required double hype, // 0..1 how much this side is favoured
  }) {
    const cols = 11;
    final baseY = dir < 0 ? bandH * 0.55 : size.height - bandH * 0.55;
    final headR = bandH * 0.07;
    if (headR <= 0.5) return;
    // Idle ambient bob even when neutral, stronger toward the favoured side.
    final amp = bandH * (0.05 + 0.16 * hype);
    final speed = 5.0 + 3.5 * hype;
    final dot = Paint();
    final headColor = Color.lerp(_white, _ember, hype)!;
    for (var i = 0; i < cols; i++) {
      final fx = (i + 0.5) / cols;
      // Skip the central column so the rope/marker stay clean.
      if ((fx - 0.5).abs() < 0.06) continue;
      final phase = t * speed + i * 0.9;
      // Bob INTO the field (toward the rope), away from the screen edge.
      final bob = (0.5 + 0.5 * math.sin(phase)) * amp * -dir;
      final cx = size.width * fx;
      final cy = baseY + bob;
      final glow = (0.10 + 0.30 * hype) * (0.55 + 0.45 * math.sin(phase));
      dot.color = headColor.withValues(alpha: glow.clamp(0.0, 0.5));
      canvas.drawCircle(Offset(cx, cy), headR, dot);
    }
  }

  /// Crowd-dark vignette so the action pops (drawn over the field, under the
  /// popups). [pulse] in 0..1 reddens/tightens the frame as the marker nears an
  /// edge — selling the rising tension. Near match point the punch lands harder
  /// (a thin breathing warm rim), but the center stays clear so the beat cue is
  /// never obscured. [t] is the animation clock (defaults to 0 — additive).
  static void drawVignette(
    Canvas canvas,
    Size size,
    double pulse, {
    double t = 0,
  }) {
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final p = pulse.clamp(0.0, 1.0);
    // Heartbeat-style breath so the punch feels alive at match point.
    final breath = 0.5 + 0.5 * math.sin(t * 5.0);
    final tighten = 1.0 - 0.06 * p * breath; // pull the frame in on big pulses
    final outer = diag * _vignetteOuterFrac;
    final inner = diag * _vignetteInnerFrac * tighten;
    final edge = Color.lerp(_vignette, const Color(0xFF260202), p) ?? _vignette;
    final paint = Paint()
      ..shader = Gradient.radial(
        Offset(size.width / 2, size.height * 0.5),
        outer,
        [const Color(0x00000000), edge],
        [(inner / outer).clamp(0.0, 0.99), 1.0],
      );
    canvas.drawRect(Offset.zero & size, paint);

    // Match-point flare: a faint warm rim that breathes only when pulse is high.
    // Kept well outside the central beat-cue zone (large radius, thin stroke).
    if (p > 0.45) {
      final flare = ((p - 0.45) / 0.55).clamp(0.0, 1.0);
      final ringR = outer * (0.94 - 0.02 * breath);
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 + 10 * flare
          ..color =
              _flame.withValues(alpha: 0.10 * flare * (0.6 + 0.4 * breath)),
      );
    }
  }

  /// The central mud/lava pit: dark socket → radial mud→lava core → bubbling
  /// hot spots → glowing rim. [t] is an animation clock (seconds) for shimmer.
  static void drawPit(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double t,
  ) {
    if (rx <= 1 || ry <= 1) return;

    // Recessed socket shadow around the pit — stacked translucent ovals fake the
    // soft edge without a per-frame blur.
    final socketRect =
        Rect.fromCenter(center: center, width: rx * 2.4, height: ry * 2.4);
    canvas.drawOval(
        socketRect, Paint()..color = _pitOuter.withValues(alpha: 0.5));
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2.15, height: ry * 2.15),
      Paint()..color = _pitOuter.withValues(alpha: 0.8),
    );

    // Mud → lava radial body (slightly offset highlight for volume).
    final body = Paint()
      ..shader = Gradient.radial(
        center.translate(-rx * 0.12, -ry * 0.18),
        rx * 1.15,
        const [_pitLava, _pitMud1, _pitMud0, _pitOuter],
        const [0.0, 0.4, 0.75, 1.0],
      );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
      body,
    );

    // Bubbling hot spots — more aggressive now: 8 drifting glowing blobs that
    // swell and "pop" (deterministic from t). Plain translucent discs (no blur).
    final blob = Paint();
    for (var i = 0; i < 8; i++) {
      final phase = t * (0.9 + i * 0.11) + i * 1.7;
      final bx = math.sin(phase) * rx * 0.55;
      final by = math.cos(phase * 0.9 + i) * ry * 0.5;
      // Sharper swell so bubbles read as actively boiling.
      final pulse = 0.5 + 0.5 * math.sin(phase * 1.9);
      final pop = math.pow(pulse, 2.2).toDouble(); // mostly small, occasional big
      final r = ry * (0.12 + 0.16 * pop);
      blob.color = Color.lerp(_pitMud1, _pitLava, pop)!
          .withValues(alpha: 0.5 * pop + 0.16);
      canvas.drawCircle(center.translate(bx, by), r, blob);
    }

    // Rising heat: steam wisps + ember flecks lifting off the surface, fading as
    // they climb (deterministic from t). Stacked translucent discs, no blur.
    _drawPitHeat(canvas, center, rx, ry, t);

    // Inner heat highlight.
    final heat = Paint()
      ..shader = Gradient.radial(
        center.translate(-rx * 0.1, -ry * 0.2),
        rx * 0.55,
        [
          _pitLava.withValues(alpha: 0.5),
          const Color(0x00000000),
        ],
      );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 1.1, height: ry * 1.1),
      heat,
    );

    // Glowing rim: a wide faint solid stroke under a crisp hot core line.
    final rimW = math.max(2.0, rx * _pitRimWidthFrac);
    final rimRect =
        Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    final glowPulse = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(t * 3.0));
    canvas.drawOval(
      rimRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW * 3.2
        ..color = _pitRimGlow.withValues(alpha: 0.18 * glowPulse),
    );
    canvas.drawOval(
      rimRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimW
        ..color = _pitRim.withValues(alpha: 0.9),
    );
  }

  /// Rising steam wisps + ember flecks lifting off the pit. Deterministic from
  /// [t]; each particle loops on its own phase and fades as it climbs.
  static void _drawPitHeat(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double t,
  ) {
    final unit = (ry / 60).clamp(0.6, 2.0); // scale sparks to pit size
    // Steam wisps (cool translucent grey-violet) drifting up from the surface.
    final wisp = Paint();
    for (var i = 0; i < 6; i++) {
      final seed = i * 1.37;
      final climb = (t * (0.18 + i * 0.015) + seed) % 1.0; // 0..1 loop
      final sx = math.sin(seed * 3.1) * rx * 0.6;
      final px = sx + math.sin(t * 0.8 + seed) * rx * 0.08; // gentle sway
      final py = -ry * 0.2 - climb * ry * 1.5; // rise above the rim
      final fade = (1.0 - climb) * climb * 4.0; // fade in then out
      final r = ry * (0.16 + climb * 0.34);
      wisp.color = _steam.withValues(alpha: (0.10 * fade).clamp(0.0, 0.16));
      canvas.drawCircle(center.translate(px, py), r, wisp);
    }
    // Ember flecks: tiny hot sparks rising + winking out.
    final fleck = Paint();
    for (var i = 0; i < 9; i++) {
      final seed = i * 0.71 + 0.3;
      final climb = (t * (0.32 + i * 0.02) + seed) % 1.0;
      final fx = math.sin(seed * 5.7) * rx * 0.7;
      final px = fx + math.sin(t * 1.6 + seed) * rx * 0.06;
      final py = -ry * 0.1 - climb * ry * 1.7;
      final twinkle = 0.5 + 0.5 * math.sin(t * 9.0 + seed * 4);
      final fade = (1.0 - climb) * twinkle;
      final r = (1.3 + 1.1 * (1.0 - climb)) * unit;
      fleck.color = Color.lerp(_ember, _flame, climb)!
          .withValues(alpha: (0.5 * fade).clamp(0.0, 0.7));
      canvas.drawCircle(center.translate(px, py), r, fleck);
    }
  }

  /// Dashed horizontal center line + two horizontal goal lines (the win
  /// thresholds, north + south). [centerY] is the pit center row; [topGoalY] /
  /// [bottomGoalY] are the goal horizontals.
  ///
  /// [lead] in -1..1 (-1 = top) lights the goal line the marker is pushing
  /// toward with a danger glow so the pull direction reads at a glance. [t] is
  /// the animation clock. Both default to 0 (additive — existing callers valid).
  static void drawFieldLines(
    Canvas canvas,
    Size size,
    double midX,
    double centerY,
    double topGoalY,
    double bottomGoalY, {
    double lead = 0,
    double t = 0,
  }) {
    final goalHalf = size.width * _goalLineHalfFrac;

    // Dashed horizontal center line through the pit.
    final dash = Paint()
      ..color = _groundLine
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    var x = midX - goalHalf * 1.4;
    final xEnd = midX + goalHalf * 1.4;
    while (x < xEnd) {
      canvas.drawLine(Offset(x, centerY),
          Offset(math.min(x + _centerDashLen, xEnd), centerY), dash);
      x += _centerDashLen + _centerDashGap;
    }

    // Top + bottom goal lines with small chevrons so they read as "the line".
    // The line nearer to losing (marker pushing toward it) gets a danger glow.
    final l = lead.clamp(-1.0, 1.0);
    final pulse = 0.5 + 0.5 * math.sin(t * 6.0);
    _goalLine(canvas, topGoalY, midX, goalHalf, -1,
        danger: (-l).clamp(0.0, 1.0), pulse: pulse);
    _goalLine(canvas, bottomGoalY, midX, goalHalf, 1,
        danger: l.clamp(0.0, 1.0), pulse: pulse);
  }

  static void _goalLine(
    Canvas canvas,
    double y,
    double midX,
    double half,
    double dir, {
    double danger = 0,
    double pulse = 0,
  }) {
    // Danger underglow: wide faint warm stroke beneath the line (no blur).
    if (danger > 0.04) {
      canvas.drawLine(
        Offset(midX - half, y),
        Offset(midX + half, y),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9 + 6 * danger
          ..strokeCap = StrokeCap.round
          ..color = _flame.withValues(
              alpha: (0.22 * danger * (0.6 + 0.4 * pulse)).clamp(0.0, 0.6)),
      );
    }
    final lineColor = Color.lerp(_white, _ember, danger * 0.8)!;
    final paint = Paint()
      ..color = lineColor.withValues(alpha: 0.5 + 0.45 * danger)
      ..strokeWidth = 3 + 1.2 * danger
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(midX - half, y), Offset(midX + half, y), paint);
    // Chevron flags pointing inward (toward the pit).
    final flag = Paint()
      ..color = lineColor.withValues(alpha: 0.28 + 0.4 * danger)
      ..strokeWidth = 2;
    canvas.drawLine(
        Offset(midX - half, y), Offset(midX - half + 8, y + dir * 12), flag);
    canvas.drawLine(
        Offset(midX + half, y), Offset(midX + half - 8, y + dir * 12), flag);
  }

  /// The rope as a near-vertical curve bowing through the [knot], drawn from
  /// [topHand] to [bottomHand], with a real braided weave. [bow] is the sideways
  /// wobble depth (px). Tinted grip wraps mark each team's grip.
  ///
  /// Optional [t] (animation seconds) drives a tension-shimmer highlight that
  /// travels along the rope, and [taut] in 0..1 (rises near a win) flattens the
  /// bow, tightens the weave, and adds a fine vibration. Both default to 0 so
  /// existing callers and tests are unaffected (additive, visual-only). The
  /// woven twin strands themselves are always drawn (pure geometry).
  static void drawRope(
    Canvas canvas,
    Offset topHand,
    Offset bottomHand,
    Offset knot,
    double bow,
    Color topTint,
    Color bottomTint, {
    double t = 0,
    double taut = 0,
  }) {
    final span = bottomHand.dy - topHand.dy;
    if (span.abs() < 1) return;

    final tt = taut.clamp(0.0, 1.0);
    // Near a win the bow flattens (rope pulls straight + tight).
    final bowEff = bow * (1.0 - 0.45 * tt);
    // Fine high-frequency vibration when the rope is straining toward a win.
    final shake = tt > 0.01 ? math.sin(t * 48.0) * (2.2 * tt) : 0.0;

    // Two control legs so the apex of the bow sits at the knot (sideways wobble).
    final topCtrl = Offset(knot.dx + bowEff * 0.6 + shake,
        topHand.dy + (knot.dy - topHand.dy) * 0.5);
    final bottomCtrl = Offset(knot.dx + bowEff * 0.6 + shake,
        knot.dy + (bottomHand.dy - knot.dy) * 0.5);

    final path = Path()
      ..moveTo(topHand.dx, topHand.dy)
      ..quadraticBezierTo(topCtrl.dx, topCtrl.dy, knot.dx, knot.dy)
      ..quadraticBezierTo(
          bottomCtrl.dx, bottomCtrl.dy, bottomHand.dx, bottomHand.dy);

    // Soft drop shadow of the rope: a wide faint solid stroke (no blur).
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeShadowW * 1.6
        ..strokeCap = StrokeCap.round
        ..color = _black.withValues(alpha: 0.16),
    );

    // Dark underside → body (stacked for a round 3-D rope). The flat highlight
    // line is replaced by twin helical strands below for a real woven look.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeUnderW
        ..strokeCap = StrokeCap.round
        ..color = _ropeShade,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeBodyW
        ..strokeCap = StrokeCap.round
        ..color = _ropeDark,
    );

    // Braided weave + travelling tension shimmer (sampled along the bezier).
    _drawBraid(canvas, topHand, topCtrl, knot, bottomCtrl, bottomHand, tt, t);

    // Tinted grip wraps near each team's hands.
    _gripWrap(canvas, topHand, topCtrl, topTint);
    _gripWrap(canvas, bottomHand, bottomCtrl, bottomTint);
  }

  /// Evaluate the two-segment quadratic-bezier rope at [u] in 0..1, returning
  /// the point and the unit tangent. First half = top→knot, second = knot→bottom.
  static (Offset, Offset) _ropeSample(
    Offset p0,
    Offset c0,
    Offset mid,
    Offset c1,
    Offset p1,
    double u,
  ) {
    final Offset a, b, c;
    final double s;
    if (u <= 0.5) {
      a = p0;
      b = c0;
      c = mid;
      s = u / 0.5;
    } else {
      a = mid;
      b = c1;
      c = p1;
      s = (u - 0.5) / 0.5;
    }
    final mt = 1 - s;
    final pos = a * (mt * mt) + b * (2 * mt * s) + c * (s * s);
    var tan = (b - a) * (2 * mt) + (c - b) * (2 * s);
    final d = tan.distance;
    if (d > 0.0001) tan = tan / d;
    return (pos, tan);
  }

  /// Twin helical strands woven down the rope + a bright shimmer ripple that
  /// travels along it. The strands are two sine offsets in phase opposition,
  /// laid perpendicular to the rope tangent so the weave wraps the body.
  static void _drawBraid(
    Canvas canvas,
    Offset p0,
    Offset c0,
    Offset mid,
    Offset c1,
    Offset p1,
    double taut,
    double t,
  ) {
    final amp = _ropeBodyW * _braidAmpFrac;
    // Taut rope = more twists packed in + a touch brighter strands.
    final twists = _braidTwists * (1.0 + 0.25 * taut);
    final strandBright = (0.75 + 0.2 * taut).clamp(0.0, 1.0);

    // Shimmer head sweeps top→bottom on a loop; brighter when taut.
    final shimmerU = (t * 0.45) % 1.0;
    final shimmerBright = (0.35 + 0.5 * taut).clamp(0.0, 1.0);
    const shimmerHalf = 0.10; // half-width of the highlight band in u-space

    final strandA = <Offset>[];
    final strandB = <Offset>[];
    final shimmerPts = <Offset>[];
    final shimmerCore = <Offset>[];

    for (var i = 0; i <= _ropeSamples; i++) {
      final u = i / _ropeSamples;
      final (pos, tan) = _ropeSample(p0, c0, mid, c1, p1, u);
      // Perpendicular to the tangent (rotate 90°).
      final nrm = Offset(-tan.dy, tan.dx);
      final ang = u * twists * math.pi * 2;
      final off = math.sin(ang) * amp;
      strandA.add(pos + nrm * off);
      strandB.add(pos - nrm * off); // opposite phase = interlocked weave

      // Shimmer: collect the points within the travelling band.
      final dist = (u - shimmerU).abs();
      if (dist < shimmerHalf) {
        shimmerPts.add(pos);
        // The crisp core rides the very center of the band.
        if (dist < shimmerHalf * 0.4) shimmerCore.add(pos);
      }
    }

    // Strand shading: a darker wide pass under a bright crisp pass (fake round).
    final strandShade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ropeStrandW + 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _ropeShade.withValues(alpha: 0.55);
    final strandLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ropeStrandW
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _ropeCore.withValues(alpha: strandBright);

    final pathA = _polyline(strandA);
    final pathB = _polyline(strandB);
    canvas.drawPath(pathA, strandShade);
    canvas.drawPath(pathB, strandShade);
    canvas.drawPath(pathA, strandLine);
    canvas.drawPath(pathB, strandLine);

    // Travelling tension shimmer: wide faint halo under a crisp hot line, both
    // following the rope centerline within the moving band (no blur).
    if (shimmerPts.length >= 2) {
      canvas.drawPath(
        _polyline(shimmerPts),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ropeBodyW + 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _ropeShimmer.withValues(alpha: 0.10 + 0.16 * shimmerBright),
      );
    }
    if (shimmerCore.length >= 2) {
      canvas.drawPath(
        _polyline(shimmerCore),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _white.withValues(alpha: 0.5 + 0.4 * shimmerBright),
      );
    }
  }

  static Path _polyline(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    return path;
  }

  static void _gripWrap(Canvas canvas, Offset hand, Offset ctrl, Color tint) {
    final dir = ctrl - hand;
    final len = dir.distance;
    if (len < 1) return;
    final n = dir / len;
    final end = hand + n * (len * 0.32);
    canvas.drawLine(
      hand,
      end,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeGripW
        ..strokeCap = StrokeCap.round
        ..color = tint.withValues(alpha: 0.85),
    );
  }

  /// The center marker: a fabric pennant hanging off the rope knot, tinted
  /// toward whichever side is currently winning ([lead] in -1..1, -1 = top).
  static void drawMarkerFlag(
    Canvas canvas,
    Offset knot,
    double lead,
    Color topTint,
    Color bottomTint,
    double t,
  ) {
    final l = lead.clamp(-1.0, 1.0);
    final mag = l.abs();
    final winTint = l <= 0 ? topTint : bottomTint;
    final tint = l <= 0
        ? Color.lerp(_white, topTint, mag)!
        : Color.lerp(_white, bottomTint, mag)!;

    // Pull-direction glow: a soft halo on the knot biased toward the winning
    // end, growing with the lead, so the direction of force reads instantly.
    // Stacked translucent discs (no blur), offset up/down toward that side.
    if (mag > 0.03) {
      final glowPulse = 0.6 + 0.4 * math.sin(t * 5.0);
      final glowAt = knot.translate(0, l * 16);
      canvas.drawCircle(
        glowAt,
        16 + 14 * mag,
        Paint()
          ..color = winTint.withValues(alpha: (0.10 + 0.18 * mag) * glowPulse),
      );
      canvas.drawCircle(
        glowAt,
        9 + 8 * mag,
        Paint()
          ..color = winTint.withValues(alpha: (0.18 + 0.26 * mag) * glowPulse),
      );
      // A short directional arrow streak pointing the way the marker is sliding.
      final dir = l <= 0 ? -1.0 : 1.0;
      canvas.drawLine(
        knot,
        knot.translate(0, dir * (14 + 18 * mag)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = winTint.withValues(alpha: (0.4 * mag).clamp(0.0, 0.6)),
      );
    }

    // Pole binding knot on the rope.
    canvas.drawCircle(knot, 9, Paint()..color = _ropeDark);
    canvas.drawCircle(
        knot,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _ropeCore);

    // Triangular pennant flapping to the SIDE of the knot (wave from t + lead
    // bias up/down so the flag leans toward the winning end).
    final wave = math.sin(t * 6.0) * 6;
    final tip = knot + Offset(34, wave + l * 14);
    final flag = Path()
      ..moveTo(knot.dx + 4, knot.dy - 3)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(knot.dx + 4, knot.dy + 3)
      ..close();
    canvas.drawPath(flag, Paint()..color = tint);
    // Subtle inner sheen on the pennant for a glassy fabric feel.
    canvas.drawLine(
      Offset(knot.dx + 6, knot.dy - 1),
      Offset(tip.dx * 0.7 + knot.dx * 0.3, tip.dy * 0.7 + knot.dy * 0.3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _white.withValues(alpha: 0.35),
    );
    canvas.drawPath(
      flag,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _black.withValues(alpha: 0.3),
    );
    // Bright eye on the knot.
    canvas.drawCircle(knot, 3.2, Paint()..color = _white);
  }

  /// Dug-in feet dust puff for a straining puller. [strain] 0..1 scales it.
  /// [dir] is the horizontal spray direction (kept for figure spread).
  static void drawFootDust(
      Canvas canvas, Offset feet, double bodyW, double strain, double t,
      {required double dir}) {
    final s = strain.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    // Plain translucent puffs (no per-mote blur).
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      final phase = t * 3.0 + i * 2.1;
      final puff = 0.5 + 0.5 * math.sin(phase);
      final px = dir * bodyW * (0.5 + i * 0.5);
      final py = -bodyW * 0.1 * puff;
      paint.color = _pitMud1.withValues(alpha: (0.14 + 0.18 * puff) * s);
      canvas.drawCircle(feet.translate(px, py),
          bodyW * (0.3 + 0.25 * puff) * (0.6 + s), paint);
    }
  }

  /// Soft contact shadow ellipse beneath a puller at ground level.
  static void drawContactShadow(Canvas canvas, Offset groundCenter, double w) {
    // A plain translucent oval grounds the figure without a per-frame blur.
    canvas.drawOval(
      Rect.fromCenter(center: groundCenter, width: w * 2.4, height: w * 0.7),
      Paint()..color = _black.withValues(alpha: 0.25),
    );
  }

  /// A team effort bar showing how hard a team is pulling. [effort] 0..1 fills
  /// it from the left edge inward; [heave] 0..1 brightens + adds a surge glow
  /// tip when the rhythm bonus is hot. [dir] -1 = top team, +1 = bottom (used to
  /// tag which team the bar labels; the bar itself is horizontal for both).
  static void drawEffortBar(
    Canvas canvas,
    Offset anchor,
    double width,
    double effort,
    double heave,
    Color color, {
    required double dir,
  }) {
    final e = effort.clamp(0.0, 1.0);
    const h = 8.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromCenter(center: anchor, width: width, height: h),
      const Radius.circular(h / 2),
    );
    canvas.drawRRect(track, Paint()..color = _black.withValues(alpha: 0.35));

    final fillW = width * e;
    if (fillW > 1) {
      final left = anchor.dx - width / 2;
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, anchor.dy - h / 2, fillW, h),
        const Radius.circular(h / 2),
      );
      final hot = Color.lerp(color, _white, 0.3 * heave.clamp(0.0, 1.0))!;
      canvas.drawRRect(fillRect, Paint()..color = hot);
    }

    // Heave surge glow tip at the leading edge of the fill: stacked translucent
    // discs instead of a per-frame blur.
    if (heave > 0.05) {
      final tipX = anchor.dx - width / 2 + fillW;
      final hv = heave.clamp(0.0, 1.0);
      canvas.drawCircle(Offset(tipX, anchor.dy), h * (1.2 + heave),
          Paint()..color = _white.withValues(alpha: 0.18 * hv));
      canvas.drawCircle(Offset(tipX, anchor.dy), h * (0.8 + heave),
          Paint()..color = _white.withValues(alpha: 0.4 * hv));
    }
  }

  /// Expanding ring shockwave near a team when their HEAVE surge fires.
  static void drawHeaveCue(
      Canvas canvas, Offset at, double strength, Color color) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    canvas.drawCircle(
      at,
      18 + 34 * (1 - s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s + 1
        ..color = Color.lerp(color, _white, 0.4)!.withValues(alpha: 0.6 * s),
    );
  }

  /// The shared HEAVE beat track: a rounded rail with a highlighted centered
  /// sweet-spot band and a sweeping marker at [pos] (0..1 across the rail).
  /// [windowHalf] is the sweet-spot half-width in the same 0..1 space.
  /// [inWindow] flips the whole cue bright + tags it "HEAVE!" so the player sees
  /// the exact instant to tap. Self-contained and side-effect free.
  static void drawBeatTrack(
    Canvas canvas,
    Offset center,
    double width,
    double pos,
    double windowHalf, {
    required bool inWindow,
    required Color accent,
    required double t,
  }) {
    if (width <= 4) return;
    final p = pos.clamp(0.0, 1.0);
    final half = windowHalf.clamp(0.02, 0.5);
    final left = center.dx - width / 2;
    const railH = 14.0;

    // Rail track.
    final track = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: railH),
      const Radius.circular(railH / 2),
    );
    canvas.drawRRect(track, Paint()..color = _black.withValues(alpha: 0.42));
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _white.withValues(alpha: 0.12),
    );

    // Centered sweet-spot band (brightens while the marker is inside it). Faked
    // glow via a wide faint solid plate under the crisp band edge (no blur).
    final bandW = width * (half * 2);
    final bandGlow = inWindow ? 0.9 : 0.45;
    final pulse = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(t * 6.0));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: bandW + 12, height: railH + 16),
        const Radius.circular(10),
      ),
      Paint()
        ..color =
            accent.withValues(alpha: (0.14 * bandGlow * pulse).clamp(0.0, 1.0)),
    );
    final band = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: bandW, height: railH + 8),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = inWindow ? 3.0 : 1.8
        ..color = accent.withValues(alpha: inWindow ? 0.95 : 0.5),
    );

    // Sweeping marker (a bright vertical paddle riding the rail). Faked glow via
    // a wider faint paddle behind the crisp one when in-window (no blur).
    final mx = left + width * p;
    final markColor = inWindow ? _white : accent;
    final markH = railH + 14;
    if (inWindow) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(mx, center.dy), width: 13, height: markH + 6),
          const Radius.circular(6.5),
        ),
        Paint()..color = markColor.withValues(alpha: 0.35),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(mx, center.dy), width: 7, height: markH),
        const Radius.circular(3.5),
      ),
      Paint()..color = markColor,
    );

    // "HEAVE!" tag floating over the band only at the moment it lines up.
    if (inWindow) {
      _drawBeatLabel(canvas, center.translate(0, -railH - 16), accent);
    }
  }

  static void _drawBeatLabel(Canvas canvas, Offset at, Color color) {
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: 16,
      fontWeight: FontWeight.w900,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText('HEAVE!');
    final para = builder.build()
      ..layout(const ParagraphConstraints(width: 160));
    canvas.drawParagraph(para, Offset(at.dx - 80, at.dy - 8));
  }

  /// Render the stick puller itself. Kept here so the painter call lives with
  /// the rest of the visuals; [figure] owns its own pose/ragdoll state.
  static void drawPuller(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }
}
