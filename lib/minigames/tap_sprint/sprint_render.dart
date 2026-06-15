import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Pure-Canvas rendering for [TapSprint]. Holds NO game state and never mutates
/// the simulation — callers pass plain value snapshots. Kept in its own file so
/// the gameplay module stays lean and the drawing stays cohesive (mirrors the
/// sumo_smash / tug_of_war split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class SprintRenderer {
  SprintRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _skyTop = Color(0xFF152138);
  static const Color _skyMid = Color(0xFF0E1626);
  static const Color _skyBottom = Color(0xFF080C16);
  static const Color _standBack = Color(0xFF1C2740);
  static const Color _standFront = Color(0xFF11192B);
  static const Color _railColor = Color(0xFF2C3A57);
  static const Color _trackTop = Color(0xFFD2622F);
  static const Color _trackBottom = Color(0xFF9C3F1C);
  static const Color _trackBottomDark = Color(0x55000000); // bottom darken
  static const Color _trackSheen = Color(0x18FFFFFF);
  static const Color _trackSheenStrong = Color(0x33FFFFFF); // glossier top sheen
  static const Color _trackHighlight = Color(0x26FFFFFF); // travelling sheen sweep
  static const Color _heatShimmer = Color(0x14FFE9C8); // warm heat-haze tint
  static const Color _cheerFlare = Color(0x33FFC93C); // crowd cheer flare near finish
  static const Color _laneLine = Color(0xFFF2ECDD);
  static const Color _laneShadow = Color(0x33000000);
  static const Color _startLine = Color(0xFFF2ECDD);
  static const Color _markerColor = Color(0x66FFFFFF);
  static const Color _checkerLight = Color(0xFFF4EFE4);
  static const Color _checkerDark = Color(0xFF181C24);
  static const Color _tapeColor = Color(0xFFFF4D6A);
  static const Color _tapeGlow = Color(0xFFFF8FA6);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _bannerPole = Color(0xFFB9C2D6);
  static const Color _sweatColor = Color(0xFF9FE6FF); // sweat-fleck cyan tint

  // ── Hurdle palette (the interposing obstacle) ───────────────────────────────
  /// The trip/knock color — the burst the gameplay fires on a clipped hurdle.
  static const Color hurdleHit = Color(0xFFFF4438);
  /// The clean-vault color — the bright pop the gameplay fires on a clean
  /// timed release (a successful sweet-spot vault).
  static const Color cleanVault = Color(0xFF5BE6B0);
  static const Color _hurdleBar = Color(0xFFF4EFE4); // crossbar (idle, approaching)
  static const Color _hurdleLeg = Color(0xFF2C3A57); // upright legs
  static const Color _hurdleWarn = Color(0xFFFFC93C); // approach telegraph color
  static const Color _hurdlePassed = Color(0xFF54E08A); // cleared/behind tint
  static const Color _hudTrack = Color(0xCC0B1220); // distance-HUD pill bg

  // ── Wind-up timing bar palette (the SKILL read) ─────────────────────────────
  static const Color _barTrack = Color(0xCC0A1018); // bar trough (neon-glass bg)
  static const Color _barFill = Color(0xFF7CF2FF); // rising power fill (cyan)
  static const Color _barFillHot = Color(0xFFFFE36B); // fill tip near full (warm)
  static const Color _sweetZone = Color(0xFF5BE6B0); // sweet-spot band (green)
  static const Color _sweetEdge = Color(0xFFEFFFF6); // sweet-spot edge ticks
  static const Color _barNeedle = Color(0xFFFFFFFF); // release needle at the fill

  // ── Tuning (fractions / px; no inline magic numbers) ───────────────────────
  static const double _standTopFrac = 0.0; // stands start at the very top
  static const int _crowdRows = 4; // rows of crowd dots
  static const double _railThickness = 6;
  static const int _distanceMarkers = 9; // 10m..90m gridlines
  static const double _laneLineWidth = 2.4;
  static const double _laneSheenWidth = 1.2;
  static const double _startBandWidth = 10;
  static const double _bannerHeightFrac = 0.052; // checker banner height / arenaH
  static const int _checkerCols = 14;
  static const double _tapeWidth = 4;
  static const double _spotlightWFactor = 2.2; // spotlight width / laneHeight
  static const double _spotlightHFactor = 1.35; // spotlight height / laneHeight
  static const int _dustMoteCount = 5;
  static const int _speedLineCount = 6;
  // Hurdle geometry, as fractions of the lane height it stands in.
  static const double _hurdleHeightFrac = 0.46; // crossbar height / laneHeight
  static const double _hurdleHalfWidthFrac = 0.16; // half foot-spread / laneHeight
  static const double _hudHeightFrac = 0.055; // distance-HUD pill height / arenaH
  // Wind-up timing bar geometry, as fractions of the lane height it floats over.
  static const double _barWidthFrac = 1.55; // bar width / laneHeight
  static const double _barHeightFrac = 0.16; // bar height / laneHeight
  static const double _barLiftFrac = 0.96; // bar centre lift above the bar / laneH

  // ── Background: night-stadium sky + tiered stands with a crowd ──────────────
  static void drawBackground(
    Canvas canvas,
    Size size,
    double trackTop,
    double t,
  ) {
    final sky = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, trackTop),
        const [_skyTop, _skyMid, _skyBottom],
        const [0.0, 0.6, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, trackTop), sky);

    _drawStands(canvas, size, trackTop, t);
  }

  /// Raked grandstand slab with twinkling crowd dots + a front guard rail.
  static void _drawStands(Canvas canvas, Size size, double trackTop, double t) {
    final standTop = size.height * _standTopFrac;
    final standH = trackTop - standTop;
    if (standH <= 1) return;

    final back = Paint()
      ..shader = Gradient.linear(
        Offset(0, standTop),
        Offset(0, trackTop),
        const [_standBack, _standFront],
      );
    canvas.drawRect(Rect.fromLTWH(0, standTop, size.width, standH), back);

    // Crowd: deterministic grid of small dots that twinkle with the clock.
    final dot = Paint();
    final cols = (size.width / (standH / _crowdRows)).clamp(18, 80).toInt();
    final rows = _crowdRows;
    final cellW = size.width / cols;
    final cellH = standH / (rows + 1);
    for (var r = 0; r < rows; r++) {
      final y = standTop + cellH * (r + 0.7);
      // Rows nearer the field are larger + brighter (perspective).
      final depth = r / rows;
      final radius = (1.2 + depth * 2.2) * (cellH / 14).clamp(0.6, 2.4);
      // Gentle crowd sway: a slow horizontal wave + small vertical bob, varied
      // per column so the stand reads as a living, swaying crowd (deterministic).
      final swayAmp = cellW * 0.18;
      final bobAmp = radius * 0.6;
      for (var c = 0; c < cols; c++) {
        final seed = r * 131 + c * 17;
        final base = _crowdHue(seed % 5);
        final stagger = c.isEven ? 0.0 : cellW * 0.5;
        final twinkle =
            0.45 + 0.4 * (0.5 + 0.5 * math.sin(t * 1.6 + seed.toDouble()));
        dot.color = base.withValues(
            alpha: (twinkle * (0.4 + depth * 0.5)).clamp(0.0, 1.0));
        final sway = math.sin(t * 1.1 + c * 0.5 + r) * swayAmp;
        final bob = math.cos(t * 1.8 + seed.toDouble()) * bobAmp;
        final x = cellW * (c + 0.5) + stagger + sway;
        canvas.drawCircle(Offset(x % size.width, y + bob), radius, dot);
      }
    }

    // Cheer flare: a soft warm glow over the stands toward the finish (right
    // side) that pulses on the clock, as if that block is roaring loudest.
    final flarePulse = 0.5 + 0.5 * math.sin(t * 2.4);
    final flareCx = size.width * 0.82;
    final flareR = standH * 1.4;
    canvas.drawCircle(
      Offset(flareCx, standTop + standH * 0.5),
      flareR,
      Paint()
        ..shader = Gradient.radial(
          Offset(flareCx, standTop + standH * 0.5),
          flareR,
          [
            _cheerFlare.withValues(alpha: 0.10 + 0.16 * flarePulse),
            const Color(0x00000000),
          ],
        ),
    );

    // Front guard rail separating crowd from the track.
    final rail = Paint()
      ..color = _railColor
      ..strokeWidth = _railThickness;
    canvas.drawLine(Offset(0, trackTop - _railThickness * 0.5),
        Offset(size.width, trackTop - _railThickness * 0.5), rail);
    canvas.drawLine(
      Offset(0, trackTop - _railThickness),
      Offset(size.width, trackTop - _railThickness),
      Paint()
        ..color = _white.withValues(alpha: 0.12)
        ..strokeWidth = 1.4,
    );
  }

  static Color _crowdHue(int i) {
    switch (i) {
      case 0:
        return const Color(0xFFFF6B6B);
      case 1:
        return const Color(0xFF4D9BFF);
      case 2:
        return const Color(0xFF54E08A);
      case 3:
        return const Color(0xFFFFC93C);
      default:
        return const Color(0xFFEFEFEF);
    }
  }

  /// The running track surface: warm gradient slab + a subtle top sheen.
  static void drawTrack(Canvas canvas, Size size, double trackTop) {
    final h = math.max(0.0, size.height - trackTop);
    if (h <= 0) return;
    final rect = Rect.fromLTWH(0, trackTop, size.width, h);
    final track = Paint()
      ..shader = Gradient.linear(
        Offset(0, trackTop),
        Offset(0, size.height),
        const [_trackTop, _trackBottom],
      );
    canvas.drawRect(rect, track);

    // Top sheen so the surface reads as a lit synthetic track (now stronger,
    // a two-stop fall-off for a glossier, more lit synthetic surface).
    final sheenH = h * 0.32;
    final sheen = Paint()
      ..shader = Gradient.linear(
        Offset(0, trackTop),
        Offset(0, trackTop + sheenH),
        const [_trackSheenStrong, _trackSheen, Color(0x00000000)],
        const [0.0, 0.35, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, trackTop, size.width, sheenH), sheen);

    // Bottom darken — grounds the track and gives it depth (Visual Bible:
    // top sheen + bottom darken). Cheap single linear fill, no blur.
    final darkH = h * 0.30;
    final darken = Paint()
      ..shader = Gradient.linear(
        Offset(0, size.height - darkH),
        Offset(0, size.height),
        const [Color(0x00000000), _trackBottomDark],
      );
    canvas.drawRect(
        Rect.fromLTWH(0, size.height - darkH, size.width, darkH), darken);

    // A faint crisp lip right under the rail so the track edge catches light.
    canvas.drawRect(
      Rect.fromLTWH(0, trackTop, size.width, 1.5),
      Paint()..color = _white.withValues(alpha: 0.10),
    );
  }

  /// Scrolling distance gridlines (10m..90m). [scroll] in 0..1 is the fraction
  /// of one cell the markers have drifted (parallax with the leader).
  static void drawDistanceMarkers(
    Canvas canvas,
    Size size,
    double startX,
    double finishX,
    double scroll,
  ) {
    final span = finishX - startX;
    if (span <= 1) return;
    final paint = Paint()
      ..color = _markerColor
      ..strokeWidth = 1.6;
    final step = span / (_distanceMarkers + 1);
    final s01 = scroll.clamp(0.0, 1.0);
    final shift = s01 * step;
    for (var i = 1; i <= _distanceMarkers; i++) {
      final x = startX + step * i - shift;
      if (x <= startX || x >= finishX) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    _drawSpeedTexture(canvas, size, startX, finishX, step, shift);
    _drawTravellingHighlight(canvas, size, s01);
    _drawHeatShimmer(canvas, size, s01);
  }

  /// Fine scrolling dash-texture between the metre gridlines — gives the track
  /// a sense of rushing speed as the leader advances. Deterministic; reuses the
  /// same [shift] the markers drift by (a sub-cell scroll), no clock needed.
  static void _drawSpeedTexture(
    Canvas canvas,
    Size size,
    double startX,
    double finishX,
    double step,
    double shift,
  ) {
    final paint = Paint()
      ..color = _white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    final half = step / 2;
    for (var i = 0; i <= _distanceMarkers; i++) {
      final x = startX + step * i + half - shift;
      if (x <= startX || x >= finishX) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  /// A single soft vertical sheen band that sweeps left→right across the track
  /// in lockstep with the marker scroll, faking a moving stadium light. Wide
  /// translucent fill (no blur) so it stays a per-frame cheap pass.
  static void _drawTravellingHighlight(Canvas canvas, Size size, double s01) {
    // Loop the sweep over the full width twice per scroll cycle for liveliness.
    final cx = ((s01 * 2.0) % 1.0) * size.width;
    final bandW = size.width * 0.22;
    final left = cx - bandW / 2;
    final paint = Paint()
      ..shader = Gradient.linear(
        Offset(left, 0),
        Offset(left + bandW, 0),
        const [Color(0x00000000), _trackHighlight, Color(0x00000000)],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(left, 0, bandW, size.height), paint);
  }

  /// Subtle heat-haze shimmer drifting up off the warm track — two faint warm
  /// horizontal bands whose vertical position eases with the scroll phase.
  static void _drawHeatShimmer(Canvas canvas, Size size, double s01) {
    final paint = Paint();
    for (var i = 0; i < 2; i++) {
      final phase = (s01 + i * 0.5) % 1.0;
      final wave = math.sin(phase * math.pi * 2 + i);
      final bandH = size.height * 0.08;
      final y = size.height * (0.5 + i * 0.22) + wave * size.height * 0.03;
      paint.shader = Gradient.linear(
        Offset(0, y - bandH / 2),
        Offset(0, y + bandH / 2),
        const [Color(0x00000000), _heatShimmer, Color(0x00000000)],
        const [0.0, 0.5, 1.0],
      );
      canvas.drawRect(Rect.fromLTWH(0, y - bandH / 2, size.width, bandH), paint);
    }
  }

  /// Lane dividers + a numbered pip at the start of each lane. [laneYs] are the
  /// foot-line y of each lane top→bottom; lanes are filled between midpoints.
  static void drawLanes(
    Canvas canvas,
    Size size,
    double startX,
    double finishX,
    List<double> laneYs,
    List<Color> laneColors,
  ) {
    if (laneYs.isEmpty) return;
    final n = laneYs.length;

    // Alternating faint lane tint bands + a colored foot-line accent per lane.
    for (var i = 0; i < n; i++) {
      final top = _laneTop(laneYs, i);
      final bot = _laneBottom(laneYs, i, size.height);
      if (i.isOdd) {
        canvas.drawRect(
          Rect.fromLTRB(0, top, size.width, bot),
          Paint()..color = _white.withValues(alpha: 0.03),
        );
      }
      final accent = Paint()
        ..color = laneColors[i].withValues(alpha: 0.16)
        ..strokeWidth = 3;
      canvas.drawLine(
          Offset(startX, laneYs[i]), Offset(finishX, laneYs[i]), accent);
    }

    // White lane divider lines between lanes (with a soft drop).
    final line = Paint()
      ..color = _laneLine
      ..strokeWidth = _laneLineWidth;
    final shadow = Paint()
      ..color = _laneShadow
      ..strokeWidth = _laneLineWidth + 1.5;
    for (var i = 0; i <= n; i++) {
      final y = i == 0
          ? _laneTop(laneYs, 0)
          : (i == n
              ? _laneBottom(laneYs, n - 1, size.height)
              : (laneYs[i - 1] + laneYs[i]) / 2);
      canvas.drawLine(Offset(0, y + 1.5), Offset(size.width, y + 1.5), shadow);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    // A center sheen on each interior divider for the synthetic-track look.
    final sheen = Paint()
      ..color = _white.withValues(alpha: 0.22)
      ..strokeWidth = _laneSheenWidth;
    for (var i = 1; i < n; i++) {
      final y = (laneYs[i - 1] + laneYs[i]) / 2;
      canvas.drawLine(Offset(0, y - 0.8), Offset(size.width, y - 0.8), sheen);
    }

    // Numbered start pips per lane.
    for (var i = 0; i < n; i++) {
      _drawLanePip(canvas, Offset(startX * 0.5, laneYs[i]), laneColors[i],
          i + 1, _laneHeight(laneYs, i, size.height));
    }
  }

  static double _laneTop(List<double> laneYs, int i) {
    if (i == 0) {
      final next = laneYs.length > 1 ? laneYs[1] : laneYs[0] + 80;
      return laneYs[0] - (next - laneYs[0]) / 2;
    }
    return (laneYs[i - 1] + laneYs[i]) / 2;
  }

  static double _laneBottom(List<double> laneYs, int i, double height) {
    if (i == laneYs.length - 1) {
      final prev = laneYs.length > 1 ? laneYs[i - 1] : laneYs[i] - 80;
      return math.min(height, laneYs[i] + (laneYs[i] - prev) / 2);
    }
    return (laneYs[i] + laneYs[i + 1]) / 2;
  }

  static double _laneHeight(List<double> laneYs, int i, double height) =>
      _laneBottom(laneYs, i, height) - _laneTop(laneYs, i);

  static void _drawLanePip(
    Canvas canvas,
    Offset center,
    Color color,
    int number,
    double laneH,
  ) {
    final r = (laneH * 0.16).clamp(10.0, 26.0);
    // Plain offset disc as the pip shadow (no per-pip blur).
    canvas.drawCircle(center.translate(0, r * 0.12), r,
        Paint()..color = _black.withValues(alpha: 0.35));
    canvas.drawCircle(center, r, Paint()..color = color);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, r * 0.16)
        ..color = _white.withValues(alpha: 0.85),
    );
    _drawText(canvas, '$number', center, r * 1.2, _readableText(color),
        weight: FontWeight.w900);
  }

  /// A clean start stripe behind the blocks.
  static void drawStartLine(Canvas canvas, Size size, double startX) {
    canvas.drawRect(
      Rect.fromLTWH(
          startX - _startBandWidth / 2, 0, _startBandWidth, size.height),
      Paint()..color = _startLine.withValues(alpha: 0.85),
    );
  }

  /// The finish: a vertical checkered band on the track + a glowing tape across
  /// it + a checkered banner arch overhead with two poles.
  static void drawFinish(Canvas canvas, Size size, double finishX, double t) {
    // Checkered ground band (two columns wide).
    final bandW = (size.width * 0.03).clamp(16.0, 44.0);
    final cell = bandW / 2;
    final rows = (size.height / cell).ceil();
    final left = finishX - bandW / 2;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < 2; c++) {
        final isLight = (r + c).isEven;
        canvas.drawRect(
          Rect.fromLTWH(left + c * cell, r * cell, cell, cell),
          Paint()
            ..color = (isLight ? _checkerLight : _checkerDark)
                .withValues(alpha: 0.92),
        );
      }
    }

    _drawBanner(canvas, size, finishX, bandW);
    _drawTape(canvas, size, finishX, t);
  }

  static void _drawBanner(
      Canvas canvas, Size size, double finishX, double bandW) {
    final h = size.height * _bannerHeightFrac;
    final w = bandW * 3.4;
    // Center over the finish, but keep the whole banner (+poles) on-screen.
    final left =
        (finishX - w / 2).clamp(2.0, math.max(2.0, size.width - w - 2)).toDouble();
    final rect = Rect.fromLTWH(left, 2, w, h);

    // Poles either side, dropping a little below the banner.
    final pole = Paint()
      ..color = _bannerPole
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, 0), Offset(left, h + size.height * 0.1), pole);
    canvas.drawLine(
        Offset(left + w, 0), Offset(left + w, h + size.height * 0.1), pole);

    // Checker fill.
    final cw = w / _checkerCols;
    final ch = h / 2;
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < _checkerCols; c++) {
        final isLight = (r + c).isEven;
        canvas.drawRect(
          Rect.fromLTWH(left + c * cw, 2 + r * ch, cw, ch),
          Paint()..color = isLight ? _checkerLight : _checkerDark,
        );
      }
    }
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _black.withValues(alpha: 0.35),
    );

    // "FINISH" wordmark centered on the banner.
    _drawText(canvas, 'FINISH', Offset(left + w / 2, 2 + h / 2), h * 0.46,
        _tapeColor,
        weight: FontWeight.w900, maxWidth: w);
  }

  static void _drawTape(Canvas canvas, Size size, double finishX, double t) {
    final flutter = math.sin(t * 7.0) * 3;
    final p1 = Offset(finishX - 6, size.height * 0.04);
    final p2 = Offset(finishX + 6 + flutter, size.height);
    // Wide faint solid stroke under the crisp tape fakes the glow (no blur).
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..strokeWidth = _tapeWidth * 3.4
        ..strokeCap = StrokeCap.round
        ..color = _tapeGlow.withValues(alpha: 0.2),
    );
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..strokeWidth = _tapeWidth
        ..strokeCap = StrokeCap.round
        ..color = _tapeColor,
    );
  }

  // ── Hurdle (the interposing obstacle; telegraphed) ──────────────────────────
  /// One hurdle standing on the track at [base] (the lane foot line), sized to
  /// [laneHeight]. A crossbar on two angled legs with a small ground shadow.
  ///
  /// [live] is the telegraph: when this is the next hurdle inside the runner's
  /// jump window it lights up in the warn color with a pulsing "JUMP!" arc + tag
  /// ([warnPulse] 0..1 throbs it), so a reading player always gets the tell.
  /// [passed] draws a hurdle the runner has already cleared in a faint green,
  /// receding behind. Side-effect free; never throws.
  static void drawHurdle(
    Canvas canvas,
    Offset base,
    double laneHeight, {
    required bool live,
    required bool passed,
    double warnPulse = 0,
  }) {
    if (laneHeight <= 1) return;
    final h = (laneHeight * _hurdleHeightFrac).clamp(8.0, laneHeight);
    final halfW = (laneHeight * _hurdleHalfWidthFrac).clamp(4.0, laneHeight);
    final top = base.dy - h;
    final barColor = passed
        ? _hurdlePassed.withValues(alpha: 0.45)
        : (live ? _hurdleWarn : _hurdleBar);
    final legColor = passed
        ? _hurdlePassed.withValues(alpha: 0.4)
        : (live ? _blend(_hurdleWarn, _hurdleLeg, 0.35) : _hurdleLeg);

    // Ground contact shadow.
    canvas.drawOval(
      Rect.fromCenter(
          center: base, width: halfW * 2.4, height: h * 0.16),
      Paint()..color = _black.withValues(alpha: 0.28),
    );

    // Two angled legs splaying down to the track.
    final leg = Paint()
      ..color = legColor
      ..strokeWidth = math.max(2.0, halfW * 0.32)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(base.dx, top), base.translate(-halfW, 0), leg);
    canvas.drawLine(Offset(base.dx, top), base.translate(halfW, 0), leg);

    // Live telegraph glow behind the bar (cheap stacked disc, no blur).
    if (live) {
      final p = warnPulse.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(base.dx, top),
        halfW * (1.4 + 0.4 * p),
        Paint()..color = _hurdleWarn.withValues(alpha: 0.18 + 0.16 * p),
      );
    }

    // Clear-flash: a clean green halo behind a freshly-cleared bar — a little
    // "nice vault!" sparkle that confirms the clear. Stacked discs, no blur.
    if (passed) {
      final f = 0.5 + 0.5 * warnPulse.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(base.dx, top),
        halfW * (1.2 + 0.5 * f),
        Paint()..color = _hurdlePassed.withValues(alpha: 0.10 + 0.10 * f),
      );
      canvas.drawCircle(
        Offset(base.dx, top),
        halfW * (0.6 + 0.3 * f),
        Paint()..color = _hurdlePassed.withValues(alpha: 0.16 * f),
      );
    }

    // Crossbar with a thin striped underline so it reads as a barrier.
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
          base.dx - halfW * 1.15, top - h * 0.12, base.dx + halfW * 1.15, top + h * 0.12),
      Radius.circular(h * 0.12),
    );
    canvas.drawRRect(barRect, Paint()..color = barColor);
    canvas.drawRRect(
      barRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, h * 0.05)
        ..color = (passed ? _hurdlePassed : _black).withValues(alpha: 0.35),
    );

    // Wind-ripple: as the runner nears (live), a bright highlight skims back and
    // forth along the crossbar like wind catching it — a subtle "it's reactive"
    // tell. A clipped travelling band over the bar; deterministic on warnPulse.
    if (live) {
      final p = warnPulse.clamp(0.0, 1.0);
      final barLeft = base.dx - halfW * 1.15;
      final barRight = base.dx + halfW * 1.15;
      final barW = barRight - barLeft;
      // Ping-pong the highlight centre across the bar.
      final tri = 1.0 - (2.0 * p - 1.0).abs(); // 0→1→0
      final cx = barLeft + barW * (0.15 + 0.7 * tri);
      final bandW = barW * 0.42;
      canvas.save();
      canvas.clipRRect(barRect);
      canvas.drawRect(
        Rect.fromLTRB(cx - bandW / 2, top - h * 0.12, cx + bandW / 2, top + h * 0.12),
        Paint()
          ..shader = Gradient.linear(
            Offset(cx - bandW / 2, top),
            Offset(cx + bandW / 2, top),
            const [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
            const [0.0, 0.5, 1.0],
          ),
      );
      canvas.restore();
    }

    if (live) _drawJumpCue(canvas, Offset(base.dx, top - h * 0.55), halfW, warnPulse);
  }

  /// A small pulsing up-chevron just above a live hurdle — the "vault here" tell.
  /// The full read (PRESS to wind up, RELEASE in the sweet spot) is carried by
  /// the power/timing bar drawn above it ([drawWindupBar]), so this stays a
  /// compact, uncluttered arrow.
  static void _drawJumpCue(
      Canvas canvas, Offset at, double scale, double pulse) {
    final p = pulse.clamp(0.0, 1.0);
    final lift = scale * 0.4 * p;
    final c = at.translate(0, -lift);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, scale * 0.22)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _hurdleWarn.withValues(alpha: 0.7 + 0.3 * p);
    final s = scale * 0.6;
    // Up-chevron (vault arrow).
    canvas.drawLine(c.translate(-s, s * 0.6), c.translate(0, -s * 0.2), paint);
    canvas.drawLine(c.translate(0, -s * 0.2), c.translate(s, s * 0.6), paint);
  }

  // ── Wind-up timing bar (the SKILL: PRESS to charge, RELEASE in the zone) ─────
  /// The POWER/TIMING bar that floats above a live hurdle — the visible skill.
  /// A horizontal neon-glass trough with a bright SWEET-SPOT zone band; while a
  /// press is held the [fill] rises 0→1 and a needle rides its tip. RELEASE with
  /// the needle inside the zone = a clean vault. Always shows the zone (the read
  /// is legible before you commit); the fill + needle + label appear while
  /// [winding]. Side-effect free; never throws; deterministic off [pulse].
  ///
  /// [base] is the hurdle foot point; the bar floats [_barLiftFrac] of a
  /// [laneHeight] above it. [sweetLo]/[sweetHi] are the zone edges on 0..1.
  static void drawWindupBar(
    Canvas canvas,
    Offset base,
    double laneHeight, {
    required double fill,
    required bool winding,
    required double sweetLo,
    required double sweetHi,
    double pulse = 0,
  }) {
    if (laneHeight <= 1) return;
    final w = (laneHeight * _barWidthFrac).clamp(40.0, laneHeight * 3.2);
    final h = (laneHeight * _barHeightFrac).clamp(8.0, laneHeight);
    final cy = base.dy - laneHeight * _hurdleHeightFrac - laneHeight * _barLiftFrac;
    final left = base.dx - w / 2;
    final f = fill.clamp(0.0, 1.0);
    final lo = sweetLo.clamp(0.0, 1.0);
    final hi = sweetHi.clamp(0.0, 1.0).clamp(lo, 1.0);
    final p = pulse.clamp(0.0, 1.0);
    final r = Radius.circular(h * 0.5);

    final trough = Rect.fromLTWH(left, cy - h / 2, w, h);
    final troughRR = RRect.fromRectAndRadius(trough, r);

    // Soft outer glow halo (stacked translucent rRect, no blur) so it reads as a
    // lit neon-glass element floating over the track.
    canvas.drawRRect(
      RRect.fromRectAndRadius(trough.inflate(h * 0.35), Radius.circular(h)),
      Paint()..color = _barFill.withValues(alpha: 0.10 + 0.06 * p),
    );
    // Trough.
    canvas.drawRRect(troughRR, Paint()..color = _barTrack);

    // Sweet-spot zone band (clip to the trough so the rounded ends stay clean).
    canvas.save();
    canvas.clipRRect(troughRR);
    final zoneL = left + w * lo;
    final zoneR = left + w * hi;
    canvas.drawRect(
      Rect.fromLTRB(zoneL, cy - h / 2, zoneR, cy + h / 2),
      Paint()..color = _sweetZone.withValues(alpha: 0.34 + 0.18 * p),
    );

    // The rising power fill up to the current value (cyan → warm near the top).
    if (winding && f > 0) {
      final fillR = left + w * f;
      canvas.drawRect(
        Rect.fromLTRB(left, cy - h / 2, fillR, cy + h / 2),
        Paint()
          ..shader = Gradient.linear(
            Offset(left, cy),
            Offset(fillR, cy),
            [_barFill.withValues(alpha: 0.85), _barFillHot.withValues(alpha: 0.95)],
          ),
      );
    }
    canvas.restore();

    // Sweet-spot edge ticks (bright verticals marking the zone boundaries).
    final tick = Paint()
      ..color = _sweetEdge.withValues(alpha: 0.85)
      ..strokeWidth = math.max(1.4, h * 0.14)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(zoneL, cy - h * 0.6), Offset(zoneL, cy + h * 0.6), tick);
    canvas.drawLine(Offset(zoneR, cy - h * 0.6), Offset(zoneR, cy + h * 0.6), tick);

    // Trough rim.
    canvas.drawRRect(
      troughRR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, h * 0.12)
        ..color = _white.withValues(alpha: 0.22),
    );

    // Release needle riding the fill tip while winding (the live read point).
    if (winding) {
      final nx = left + w * f;
      final inZone = f >= lo && f <= hi;
      final needle = Paint()
        ..color = (inZone ? _sweetZone : _barNeedle)
            .withValues(alpha: 0.92)
        ..strokeWidth = math.max(2.0, h * 0.22)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(nx, cy - h * 0.95), Offset(nx, cy + h * 0.95), needle);
      // A small diamond cap so the needle reads as a release marker.
      final cap = h * 0.42;
      final path = Path()
        ..moveTo(nx, cy - h * 0.95 - cap)
        ..lineTo(nx + cap * 0.7, cy - h * 0.95)
        ..lineTo(nx, cy - h * 0.95 + cap * 0.5)
        ..lineTo(nx - cap * 0.7, cy - h * 0.95)
        ..close();
      canvas.drawPath(
          path,
          Paint()
            ..color = (inZone ? _sweetZone : _barNeedle).withValues(alpha: 0.95));
    }

    // A compact label above the bar: prompt to PRESS when idle, RELEASE while
    // winding — the action is always unmistakable.
    _drawText(
      canvas,
      winding ? 'RELEASE!' : 'HOLD!',
      Offset(base.dx, cy - h * 1.5),
      h * 0.92,
      winding ? _sweetZone : _hurdleWarn,
      weight: FontWeight.w900,
      maxWidth: w,
    );
  }

  // ── Distance HUD (the objective: progress toward the finish) ────────────────
  /// A top-center pill reading the leader's distance toward the finish, e.g.
  /// "63 / 100 m", with a thin progress bar — so the objective + how close it is
  /// are always on screen. Side-effect free; never throws.
  static void drawDistanceHud(
    Canvas canvas,
    Size size,
    double leaderMeters,
    double raceMeters,
    Color accent,
  ) {
    if (raceMeters <= 0 || size.width <= 1) return;
    final frac = (leaderMeters / raceMeters).clamp(0.0, 1.0);
    final h = (size.height * _hudHeightFrac).clamp(22.0, 60.0);
    final w = (size.width * 0.42).clamp(120.0, size.width - 16);
    final center = Offset(size.width / 2, h * 0.85);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.5),
    );
    canvas.drawRRect(rect, Paint()..color = _hudTrack);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: 0.5),
    );

    // Progress fill bar tucked along the bottom of the pill.
    final barH = h * 0.18;
    final barTop = center.dy + h * 0.5 - barH - 2;
    final barLeft = center.dx - w / 2 + 6;
    final barW = w - 12;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, barTop, barW, barH), Radius.circular(barH * 0.5)),
      Paint()..color = _white.withValues(alpha: 0.12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, barTop, barW * frac, barH),
        Radius.circular(barH * 0.5)),
      Paint()..color = accent,
    );

    final meters = leaderMeters.clamp(0, raceMeters).round();
    _drawText(
      canvas,
      '$meters / ${raceMeters.round()} m',
      center.translate(0, -h * 0.08),
      h * 0.42,
      _white,
      weight: FontWeight.w900,
      maxWidth: w,
    );
  }

  /// A soft moving spotlight tracking the race leader on the track.
  static void drawLeaderSpotlight(
      Canvas canvas, Offset feet, double laneHeight, Color color) {
    final w = laneHeight * _spotlightWFactor;
    final h = laneHeight * _spotlightHFactor;
    if (w <= 0 || h <= 0) return;
    final center = feet.translate(0, -h * 0.18);
    final glow = Paint()
      ..shader = Gradient.radial(
        center,
        w * 0.5,
        [color.withValues(alpha: 0.22), const Color(0x00000000)],
      );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, h / w);
    canvas.drawCircle(Offset.zero, w * 0.5, glow);
    canvas.restore();
  }

  /// Soft contact shadow ellipse beneath a sprinter at ground level. [squash]
  /// stretches it with the gait so the runner feels grounded.
  static void drawContactShadow(
      Canvas canvas, Offset feet, double bodyW, double squash) {
    final s = squash.clamp(0.3, 1.4);
    // A plain translucent oval grounds the runner without a per-frame blur.
    final paint = Paint()..color = _black.withValues(alpha: 0.26 * s);
    canvas.drawOval(
      Rect.fromCenter(
          center: feet, width: bodyW * 2.4 * s, height: bodyW * 0.6),
      paint,
    );
  }

  /// Footstep dust kicked up behind a fast runner. [speed] 0..1 scales the puff;
  /// [stride] is a phase clock so puffs pulse with the gait.
  static void drawFootDust(
    Canvas canvas,
    Offset feet,
    double bodyW,
    double speed,
    double stride,
  ) {
    final s = speed.clamp(0.0, 1.0);
    if (s <= 0.03) return;
    // Translucent solid puffs (no per-mote blur) read as soft kicked-up dust.
    final paint = Paint();

    // Low, wide ground-hugging spray fan behind the heel — the bulk of the kick.
    for (var i = 0; i < _dustMoteCount; i++) {
      final phase = stride * 1.7 + i * 0.9;
      final spread = 0.5 + 0.5 * math.sin(phase);
      final px = -bodyW * (0.35 + i * 0.5);
      final py = bodyW * 0.04 * spread; // hug the ground, fan downward a touch
      paint.color = _trackBottom.withValues(alpha: (0.05 + 0.12 * spread) * s);
      canvas.drawCircle(feet.translate(px, py),
          bodyW * (0.34 + 0.30 * spread) * (0.7 + s), paint);
    }

    // The lighter rising puffs (original look, kept on top of the low spray).
    for (var i = 0; i < _dustMoteCount; i++) {
      final phase = stride * 2.0 + i * 1.3;
      final puff = 0.5 + 0.5 * math.sin(phase);
      // Dust trails BEHIND the runner (runners face +x, so dust goes -x).
      final px = -bodyW * (0.5 + i * 0.55);
      final py = -bodyW * 0.08 * puff;
      paint.color = _trackTop.withValues(alpha: (0.10 + 0.20 * puff) * s);
      canvas.drawCircle(feet.translate(px, py),
          bodyW * (0.28 + 0.22 * puff) * (0.6 + s), paint);
    }

    // A few sharp grit specks flung back on a faster stride — adds energy.
    if (s > 0.4) {
      final grit = Paint()..color = _white.withValues(alpha: 0.18 * s);
      for (var i = 0; i < 3; i++) {
        final phase = stride * 2.6 + i * 2.0;
        final fly = 0.5 + 0.5 * math.sin(phase);
        final gx = -bodyW * (0.4 + i * 0.7) * (0.6 + fly);
        final gy = -bodyW * (0.1 + 0.4 * fly);
        canvas.drawCircle(feet.translate(gx, gy), bodyW * 0.07 * (0.6 + s), grit);
      }
    }
  }

  /// Horizontal speed lines streaking back from a fast sprinter. [speed] 0..1
  /// scales their length + opacity; [phase] animates the streak offset.
  static void drawSpeedLines(
    Canvas canvas,
    Offset chest,
    double bodyW,
    double speed,
    double phase,
    Color color,
  ) {
    final s = speed.clamp(0.0, 1.0);
    if (s <= 0.25) return;
    final amount = (s - 0.25) / 0.75; // ramp in above the threshold
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < _speedLineCount; i++) {
      final spread = (i / (_speedLineCount - 1) - 0.5) * bodyW * 2.6;
      final jitter = math.sin(phase * 3.0 + i * 2.1) * bodyW * 0.2;
      final len = bodyW * (1.6 + 2.4 * amount) * (0.7 + (i % 3) * 0.18);
      final y = chest.dy + spread + jitter;
      final x1 = chest.dx - bodyW * 0.9;
      final x0 = x1 - len;
      paint
        ..strokeWidth = (1.0 + 1.6 * amount) * (i.isEven ? 1.0 : 0.6)
        ..shader = Gradient.linear(
          Offset(x0, y),
          Offset(x1, y),
          [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.5 * amount),
          ],
        );
      canvas.drawLine(Offset(x0, y), Offset(x1, y), paint);
    }

    _drawEffortTells(canvas, chest, bodyW, s, phase);
  }

  /// Hard-effort tells on a flat-out sprinter: rhythmic breath puffs drifting
  /// off the mouth and a light sweat streak flicking back off the brow. Both
  /// ramp in only near top speed so a jogging runner stays clean. Deterministic
  /// off the supplied [phase]; translucent solids, no blur.
  static void _drawEffortTells(
      Canvas canvas, Offset chest, double bodyW, double s, double phase) {
    if (s <= 0.55) return;
    final effort = ((s - 0.55) / 0.45).clamp(0.0, 1.0);
    // Head sits a little above the chest; runner faces +x.
    final head = chest.translate(bodyW * 0.15, -bodyW * 1.05);

    // Breath puff: a soft expanding mote ahead of the mouth, exhaled in pulses.
    final breath = (math.sin(phase * 2.0) * 0.5 + 0.5);
    final puffR = bodyW * (0.16 + 0.20 * breath);
    final puffX = bodyW * (0.35 + 0.45 * breath);
    canvas.drawCircle(
      head.translate(puffX, -bodyW * 0.05),
      puffR,
      Paint()
        ..color = _white.withValues(alpha: (0.06 + 0.14 * (1 - breath)) * effort),
    );

    // Sweat streak: a short bright dash flicked back off the brow on the beat.
    final fling = math.sin(phase * 3.0);
    if (fling > 0.2) {
      final bx = head.translate(-bodyW * 0.25, -bodyW * 0.15);
      final ex = bx.translate(-bodyW * (0.4 + 0.5 * fling), -bodyW * 0.3 * fling);
      canvas.drawLine(
        bx,
        ex,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = bodyW * 0.07
          ..shader = Gradient.linear(
            bx,
            ex,
            [
              _sweatColor.withValues(alpha: 0.55 * effort * fling),
              _sweatColor.withValues(alpha: 0.0),
            ],
          ),
      );
    }
  }

  /// A small ring flourish when the leader lunges for the tape.
  static void drawLungeFlash(
      Canvas canvas, Offset chest, double bodyW, double strength, Color color) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    canvas.drawCircle(
      chest,
      bodyW * (0.8 + 1.8 * (1 - s)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * s + 1
        ..color = Color.lerp(color, _white, 0.4)!.withValues(alpha: 0.55 * s),
    );
  }

  /// Render the stick sprinter itself. Kept here so the painter call lives with
  /// the rest of the visuals; [figure] owns its own pose/ragdoll state.
  static void drawSprinter(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w800,
    double maxWidth = 240,
  }) {
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: weight,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - maxWidth / 2, center.dy - fontSize * 0.62),
    );
  }
}
