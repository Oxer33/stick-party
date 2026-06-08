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

  // Rope palette.
  static const Color _ropeCore = Color(0xFFE8C98C);
  static const Color _ropeDark = Color(0xFF9C6F3A);
  static const Color _ropeShade = Color(0xFF5E3F1F);

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
  static const double _ropeBraidW = 4;
  static const double _ropeGripW = 11;

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
  static void drawCrowdBands(Canvas canvas, Size size, double bandFrac) {
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
  }

  /// Crowd-dark vignette so the action pops (drawn over the field, under the
  /// popups). [pulse] in 0..1 reddens/tightens the frame as the marker nears an
  /// edge — selling the rising tension.
  static void drawVignette(Canvas canvas, Size size, double pulse) {
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final outer = diag * _vignetteOuterFrac;
    final inner = diag * _vignetteInnerFrac;
    final p = pulse.clamp(0.0, 1.0);
    final edge = Color.lerp(_vignette, const Color(0xFF260202), p) ?? _vignette;
    final paint = Paint()
      ..shader = Gradient.radial(
        Offset(size.width / 2, size.height * 0.5),
        outer,
        [const Color(0x00000000), edge],
        [(inner / outer).clamp(0.0, 0.99), 1.0],
      );
    canvas.drawRect(Offset.zero & size, paint);
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

    // Bubbling hot spots — a few drifting glowing blobs (deterministic from t).
    // Plain translucent discs (no per-blob blur).
    final blob = Paint();
    for (var i = 0; i < 5; i++) {
      final phase = t * (0.7 + i * 0.13) + i * 1.7;
      final bx = math.sin(phase) * rx * 0.5;
      final by = math.cos(phase * 0.9 + i) * ry * 0.45;
      final pulse = 0.5 + 0.5 * math.sin(phase * 1.6);
      final r = ry * (0.18 + 0.12 * pulse);
      blob.color = Color.lerp(_pitMud1, _pitLava, pulse)!
          .withValues(alpha: 0.45 * pulse + 0.18);
      canvas.drawCircle(center.translate(bx, by), r, blob);
    }

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

  /// Dashed horizontal center line + two horizontal goal lines (the win
  /// thresholds, north + south). [centerY] is the pit center row; [topGoalY] /
  /// [bottomGoalY] are the goal horizontals.
  static void drawFieldLines(
    Canvas canvas,
    Size size,
    double midX,
    double centerY,
    double topGoalY,
    double bottomGoalY,
  ) {
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
    _goalLine(canvas, topGoalY, midX, goalHalf, -1);
    _goalLine(canvas, bottomGoalY, midX, goalHalf, 1);
  }

  static void _goalLine(
      Canvas canvas, double y, double midX, double half, double dir) {
    final paint = Paint()
      ..color = _white.withValues(alpha: 0.5)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(midX - half, y), Offset(midX + half, y), paint);
    // Chevron flags pointing inward (toward the pit).
    final flag = Paint()
      ..color = _white.withValues(alpha: 0.28)
      ..strokeWidth = 2;
    canvas.drawLine(
        Offset(midX - half, y), Offset(midX - half + 8, y + dir * 12), flag);
    canvas.drawLine(
        Offset(midX + half, y), Offset(midX + half - 8, y + dir * 12), flag);
  }

  /// The rope as a near-vertical curve bowing through the [knot], drawn from
  /// [topHand] to [bottomHand], with a braided sheen. [bow] is the sideways
  /// wobble depth (px). Tinted grip wraps mark each team's grip.
  static void drawRope(
    Canvas canvas,
    Offset topHand,
    Offset bottomHand,
    Offset knot,
    double bow,
    Color topTint,
    Color bottomTint,
  ) {
    final span = bottomHand.dy - topHand.dy;
    if (span.abs() < 1) return;

    // Two control legs so the apex of the bow sits at the knot (sideways wobble).
    final topCtrl = Offset(
        knot.dx + bow * 0.6, topHand.dy + (knot.dy - topHand.dy) * 0.5);
    final bottomCtrl = Offset(
        knot.dx + bow * 0.6, knot.dy + (bottomHand.dy - knot.dy) * 0.5);

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

    // Dark underside → body → bright braid (stacked for a round 3-D rope).
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
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ropeBraidW
        ..strokeCap = StrokeCap.round
        ..color = _ropeCore,
    );

    // Tinted grip wraps near each team's hands.
    _gripWrap(canvas, topHand, topCtrl, topTint);
    _gripWrap(canvas, bottomHand, bottomCtrl, bottomTint);
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
    final tint = l <= 0
        ? Color.lerp(_white, topTint, (-l).clamp(0.0, 1.0))!
        : Color.lerp(_white, bottomTint, l.clamp(0.0, 1.0))!;

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
