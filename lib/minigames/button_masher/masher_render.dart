import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Geometry of one climbing tower in render space. Pure value — the sim builds
/// it and both the sim and [MasherRenderer] read its anchors so they agree on
/// where each rung and the flag sit.
class TowerSpec {
  final double center; // x of the tower center
  final double width; // base width (drives every other size)
  final double railTop; // y of the top rung (just under the flag)
  final double railBottom; // y of the ground rung (rung 0)
  final int rungs; // rung count from ground to flag

  const TowerSpec({
    required this.center,
    required this.width,
    required this.railTop,
    required this.railBottom,
    required this.rungs,
  });

  double get railSpan => railBottom - railTop;

  /// World position of a 0..1 height (0 = ground rung, 1 = flag).
  Offset rungAt(double frac) =>
      Offset(center, railBottom - railSpan * frac.clamp(0.0, 1.0));

  /// World position of integer [rung] (0.._rungs).
  Offset rungPos(int rung) => rungAt(rungs <= 0 ? 0 : rung / rungs);

  Offset get flag => Offset(center, railTop - width * 0.55);
}

/// Pure-Canvas rendering for [ButtonMasher]'s "Tower Climb". Holds NO game
/// state and never mutates the simulation — callers pass plain value snapshots.
/// Kept in its own file so the gameplay module stays lean (mirrors the
/// sumo_smash / tug_of_war split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class MasherRenderer {
  MasherRenderer._();

  // ── Shared palette (no magic colors inline elsewhere) ───────────────────────
  static const Color flagGold = Color(0xFFFFD23C);
  // Hazard danger color — the sweeping bars + knockback puff.
  static const Color hazardRed = Color(0xFFFF4438);
  static const Color hazardWarn = Color(0xFFFFC93C); // telegraph flash color

  static const Color _bgTop = Color(0xFF173A4F);
  static const Color _bgMid = Color(0xFF0E2436);
  static const Color _bgBottom = Color(0xFF070F1A);
  static const Color _stageGlow = Color(0x2238D0FF);
  static const Color _ground = Color(0xFF15212E);
  static const Color _groundLine = Color(0x22FFFFFF);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);

  // Tower hardware palette.
  static const Color _railDark = Color(0xFF0C1622);
  static const Color _railSteel = Color(0xFF566578);
  static const Color _railSteelHi = Color(0xFFAEB9C6);
  static const Color _rungSteel = Color(0xFF8A93A2);
  static const Color _hazardDark = Color(0xFF7A140E);
  static const Color _hazardHi = Color(0xFFFF8A80);

  // Cloud band colors strung behind the towers.
  static const List<Color> _clouds = <Color>[
    Color(0x14FFFFFF),
    Color(0x10BFE8FF),
  ];

  // Atmosphere extras (depth/parallax/summit light).
  static const Color _rayTint = Color(0xFF8BD4FF); // cool summit light shafts
  static const Color _vignette = Color(0x4A05070C); // edge-gutter darkening
  static const Color _railSheen = Color(0xFFE8F2FF); // top-of-rail highlight
  static const Color _scuffTint = Color(0xFFFFE7B0); // climbed-rung foothold

  // ── Tuning (fractions of tower width / arena; no inline magic numbers) ──────
  static const double _railWidthFrac = 0.5; // distance between the two rails
  static const double _railThickFrac = 0.09; // each rail's thickness / width
  static const double _rungThickFrac = 0.1; // ladder rung thickness / width
  static const double _flagPoleFrac = 1.0; // flag pole height / width
  static const int _groundLines = 4;
  static const int _cloudBands = 5;
  static const int _summitRays = 5; // volumetric light shafts from the top
  static const double _barThickFrac = 0.34; // min band height / width (floor)
  static const double _barBandMaxFrac = 1.1; // max band height / width (clamp)
  static const double _barFullWidthFrac = 1.18; // slab spans this * tower width
  static const double _barSpikeFrac = 0.16; // spike teeth size / width

  // ── Background: cool tower-climb sky + glow + drifting clouds + ground ──────
  /// [beatPulse] (0..1) is the shared metronome danger glow — 0 deep in the safe
  /// gap, 1 on the live strike. It tints the whole scene toward danger so the
  /// rhythm reads at a glance even in peripheral vision: cool sky breathes a red
  /// wash on the beat, then clears for the climb window.
  static void drawBackground(Canvas canvas, Size size, double t,
      {double beatPulse = 0}) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgMid, _bgBottom],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // Soft cool glow pooling near the top (toward the summit), gently breathing.
    final glowR = size.width * (0.86 + 0.05 * math.sin(t * 0.6));
    if (glowR > 0) {
      final center = Offset(size.width / 2, size.height * 0.18);
      canvas.drawCircle(
        center,
        glowR,
        Paint()
          ..shader = Gradient.radial(
            center,
            glowR,
            const [_stageGlow, Color(0x00000000)],
          ),
      );
    }

    _drawSummitRays(canvas, size, t);
    _drawClouds(canvas, size, t);
    _drawGround(canvas, size);
    _drawDepthVignette(canvas, size);
    _drawBeatWash(canvas, size, beatPulse);
  }

  /// Tower-wide danger wash on the beat — a top band + side-gutter rim that swell
  /// with [beatPulse]. Cheap (gradient rects, additive) and drawn over the
  /// backdrop but under the towers, so the live beat is unmistakable without
  /// hiding the climbers.
  static void _drawBeatWash(Canvas canvas, Size size, double pulse) {
    final p = pulse.clamp(0.0, 1.0);
    if (p <= 0.01) return;
    final a = 0.05 + 0.20 * p; // gentle in the gap, hot on the strike
    // Top band glow (danger rolling down from the bars overhead).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.5),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height * 0.5),
          [hazardRed.withValues(alpha: a), const Color(0x00000000)],
        ),
    );
    // A pulse rim along the left/right gutters too, so the flash reads even
    // where the towers fill the middle.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = Gradient.linear(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          [
            hazardRed.withValues(alpha: a * 0.7),
            const Color(0x00000000),
            const Color(0x00000000),
            hazardRed.withValues(alpha: a * 0.7),
          ],
          const [0.0, 0.12, 0.88, 1.0],
        ),
    );
  }

  /// Faint volumetric light shafts fanning down from the summit — sells "tall"
  /// and gives the upper sky some slow drift without obscuring the towers.
  static void _drawSummitRays(Canvas canvas, Size size, double t) {
    final apex = Offset(size.width / 2, -size.height * 0.05);
    final reach = size.height * 0.72;
    final paint = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < _summitRays; i++) {
      final u = (i + 0.5) / _summitRays - 0.5; // −0.5..0.5
      final sway = math.sin(t * 0.18 + i * 1.7) * 0.05;
      final spread = size.width * (0.16 + 0.06 * (i % 2));
      final dx = (u + sway) * size.width * 1.1;
      final foot = Offset(apex.dx + dx, apex.dy + reach);
      final ray = Path()
        ..moveTo(apex.dx - spread * 0.18, apex.dy)
        ..lineTo(apex.dx + spread * 0.18, apex.dy)
        ..lineTo(foot.dx + spread, foot.dy)
        ..lineTo(foot.dx - spread, foot.dy)
        ..close();
      final a = (0.05 + 0.03 * math.sin(t * 0.5 + i)).clamp(0.0, 1.0);
      canvas.drawPath(
        ray,
        Paint()
          ..blendMode = paint.blendMode
          ..shader = Gradient.linear(
            apex,
            foot,
            [_rayTint.withValues(alpha: a), const Color(0x00000000)],
          ),
      );
    }
  }

  /// Vertical edge vignette — darkens the left/right gutters so the playfield
  /// feels deep and the towers pop forward. Drawn after clouds, before actors.
  static void _drawDepthVignette(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.linear(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          const [_vignette, Color(0x00000000), Color(0x00000000), _vignette],
          const [0.0, 0.16, 0.84, 1.0],
        ),
    );
  }

  /// Slow drifting cloud bands for height + parallax.
  static void _drawClouds(Canvas canvas, Size size, double t) {
    for (var i = 0; i < _cloudBands; i++) {
      final u = (i + 0.5) / _cloudBands;
      final y = size.height * (0.1 + 0.6 * u);
      final drift = math.sin(t * 0.2 + i) * size.width * 0.06;
      final w = size.width * (0.5 + 0.3 * (i % 2));
      final h = size.height * 0.05;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * u + drift, y),
          width: w,
          height: h,
        ),
        Paint()..color = _clouds[i % _clouds.length],
      );
    }
  }

  static void _drawGround(Canvas canvas, Size size) {
    final top = size.height * 0.88;
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, size.height - top),
      Paint()
        ..shader = Gradient.linear(
          Offset(0, top),
          Offset(0, size.height),
          const [_ground, _bgBottom],
        ),
    );
    final line = Paint()
      ..color = _groundLine
      ..strokeWidth = 1.5;
    final span = size.height - top;
    for (var i = 1; i <= _groundLines; i++) {
      final f = i / (_groundLines + 1);
      final y = top + span * f * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  // ── Tower: twin rails + numbered ladder rungs + a reached-glow ──────────────
  static void drawTower(
    Canvas canvas,
    TowerSpec t, {
    required Color color,
    required int rungs,
    required double reachedFraction,
    required int number,
    required double glowPulse,
  }) {
    if (t.railSpan <= 1 || t.width <= 1 || rungs <= 0) return;
    final railGap = t.width * _railWidthFrac;
    final railThick = math.max(2.0, t.width * _railThickFrac);
    final lx = t.center - railGap / 2;
    final rx = t.center + railGap / 2;

    // Drop shadow of the whole tower.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(lx - railThick / 2 + 4, t.railTop + 6,
            rx + railThick / 2 + 4, t.railBottom),
        Radius.circular(railThick * 0.5),
      ),
      Paint()..color = _black.withValues(alpha: 0.25),
    );

    // Twin steel rails.
    for (final x in [lx, rx]) {
      final railRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
            x - railThick / 2, t.railTop, x + railThick / 2, t.railBottom),
        Radius.circular(railThick * 0.5),
      );
      canvas.drawRRect(railRect, Paint()..color = _railDark);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - railThick * 0.28, t.railTop, x + railThick * 0.1,
              t.railBottom),
          Radius.circular(railThick * 0.4),
        ),
        Paint()
          ..shader = Gradient.linear(
            Offset(x - railThick * 0.28, 0),
            Offset(x + railThick * 0.1, 0),
            const [_railSteelHi, _railSteel],
          ),
      );
      // Top sheen cap — a bright glint where each rail catches the summit light,
      // fading down so the tower reads as polished metal rising into depth.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - railThick * 0.24, t.railTop,
              x + railThick * 0.06, t.railTop + t.railSpan * 0.22),
          Radius.circular(railThick * 0.3),
        ),
        Paint()
          ..shader = Gradient.linear(
            Offset(0, t.railTop),
            Offset(0, t.railTop + t.railSpan * 0.22),
            [_railSheen.withValues(alpha: 0.55), const Color(0x00000000)],
          ),
      );
    }

    _drawRungs(canvas, t, color, rungs, reachedFraction, glowPulse, lx, rx);
    _drawBasePlaque(canvas, t, color, number);
  }

  /// The ladder rungs between the rails. Rungs at or below the climber's best
  /// height light up in the player color; the rest are dim steel.
  static void _drawRungs(
    Canvas canvas,
    TowerSpec t,
    Color color,
    int rungs,
    double reachedFraction,
    double glowPulse,
    double lx,
    double rx,
  ) {
    final rungThick = math.max(2.0, t.width * _rungThickFrac);
    final reachedRung = (reachedFraction.clamp(0.0, 1.0) * rungs).round();
    final scuffPaint = Paint(); // reused across climbed rungs (no per-rung alloc)
    for (var i = 1; i <= rungs; i++) {
      final pos = t.rungPos(i);
      final lit = i <= reachedRung;
      final col = lit ? color : _rungSteel;
      final a = lit ? 1.0 : 0.5;

      if (lit) {
        // Cheap glow plate under a lit rung (no per-rung blur).
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(lx, pos.dy - rungThick, rx, pos.dy + rungThick),
            Radius.circular(rungThick),
          ),
          Paint()
            ..color = color
                .withValues(alpha: (0.12 + 0.1 * glowPulse).clamp(0.0, 1.0)),
        );
        // Foothold "scuff": a faint warm smudge worn into a rung already
        // climbed past, so the trail of conquered rungs reads as progress.
        // Only on rungs strictly below the current best (i < reachedRung).
        if (i < reachedRung) {
          // Deterministic side + size variation by index — looks worn, not
          // stamped, with zero randomness in render.
          final side = (i.isEven ? 1.0 : -1.0);
          final jitter = math.sin(i * 1.7);
          final sx = t.center + side * t.width * (0.07 + 0.05 * jitter.abs());
          final scuffR = rungThick * (0.7 + 0.2 * jitter.abs());
          scuffPaint.color =
              _scuffTint.withValues(alpha: 0.10 + 0.05 * jitter.abs());
          canvas.drawCircle(Offset(sx, pos.dy), scuffR, scuffPaint);
        }
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
              lx, pos.dy - rungThick / 2, rx, pos.dy + rungThick / 2),
          Radius.circular(rungThick * 0.5),
        ),
        Paint()..color = col.withValues(alpha: a),
      );
    }
  }

  /// A slim colored ground nameplate carrying the player number, set just under
  /// the ground rung so it labels the tower without covering the climber.
  static void _drawBasePlaque(
      Canvas canvas, TowerSpec t, Color color, int number) {
    final w = t.width * 0.9;
    final h = t.width * 0.32;
    final center = Offset(t.center, t.railBottom + t.width * 0.32);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.32),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, h * 0.12)
        ..color = _blend(color, _white, 0.45),
    );
    _drawText(canvas, 'P$number', center, h * 0.6, _readableText(color),
        bold: true);
  }

  // ── Hazard bar (full-width slab on the shared beat; telegraphed) ─────────────
  /// A FULL-WIDTH hazard bar centered on band height [bandRung], spanning the
  /// whole lane (no horizontal pocket — timing on the beat is the only out). The
  /// band's vertical thickness comes from [halfRungs] (the lethal half-height in
  /// rungs), so what you see is exactly what kills: a climber inside this slab's
  /// rung band during the LIVE window eats it.
  ///
  /// State reads the shared beat directly:
  ///  * [warn] true  → a flashing telegraph slab (harmless lead-in).
  ///  * [live] true  → a solid spiked danger slab; [sweep] (0..1) is how far the
  ///    leading wipe-edge has crossed the lane and [sweepDir] (+1 / -1) the wipe
  ///    direction, so the slam reads as a fast pass across the band.
  ///  * neither      → the SAFE gap: a dim parked slab so the band stays legible
  ///    (you can see WHERE the danger will be while it's harmless).
  ///
  /// [beatPhase] (0..1 through this bar's beat) drives the live shimmer/sparks
  /// deterministically (no clock); [warnPulse] (0..1) throbs the telegraph.
  /// Side-effect free; never throws.
  static void drawHazardBar(
    Canvas canvas,
    TowerSpec t, {
    required double bandRung,
    required double halfRungs,
    required int rungs,
    required bool live,
    required bool warn,
    required double sweep,
    required int sweepDir,
    required double beatPhase,
    double warnPulse = 0,
  }) {
    if (t.width <= 2 || rungs <= 0) return;
    final y = t.rungAt((bandRung / rungs).clamp(0.0, 1.0)).dy;
    // Band height follows the lethal half-height in rungs, clamped so a thin
    // band still reads and a wide one never swallows the lane. Falls back to the
    // legacy slab thickness when the band would be sub-pixel.
    final rungPx = t.railSpan / rungs;
    final bandH = (2 * halfRungs.abs() * rungPx)
        .clamp(t.width * _barThickFrac, t.width * _barBandMaxFrac);
    // Full-width: the slab spans a touch beyond the rails so its edges read as
    // entering/leaving the lane rather than floating inside it.
    final w = t.width * _barFullWidthFrac;
    final center = Offset(t.center, y);

    if (warn) {
      _drawWarnBar(canvas, center, w, bandH, warnPulse);
      return;
    }
    if (live) {
      _drawLiveBar(canvas, center, w, bandH, sweep, sweepDir, beatPhase);
    } else {
      _drawSafeBar(canvas, center, w, bandH);
    }
  }

  /// The SAFE-gap slab: a dim, full-width parked band so the player always sees
  /// WHERE the hazard lives even while it is harmless — the climb window reads as
  /// "step now, the band is asleep". Just a faint fill + hairline edge.
  static void _drawSafeBar(Canvas canvas, Offset center, double w, double h) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.3),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset(0, center.dy - h / 2),
          Offset(0, center.dy + h / 2),
          [
            _hazardDark.withValues(alpha: 0.18),
            hazardRed.withValues(alpha: 0.14),
            _hazardDark.withValues(alpha: 0.18),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawLine(
      Offset(center.dx - w / 2, center.dy),
      Offset(center.dx + w / 2, center.dy),
      Paint()
        ..strokeWidth = math.max(1.0, h * 0.05)
        ..color = hazardRed.withValues(alpha: 0.22),
    );
  }

  /// The LIVE full-width slab: a solid spiked danger band with a bright wipe-edge
  /// crossing the lane in [sweepDir] at [sweep] (0..1). The whole band is lethal;
  /// the wipe is pure spectacle (reads as a fast pass), the spikes sell "do not
  /// touch", and [phase] jitters the speed fx deterministically.
  static void _drawLiveBar(Canvas canvas, Offset center, double w, double h,
      double sweep, int sweepDir, double phase) {
    final s = sweep.clamp(0.0, 1.0);
    final dir = sweepDir >= 0 ? 1.0 : -1.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.3),
    );
    // Danger glow halo behind the slab (cheap stacked rrect, no blur).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: w * 1.04, height: h * 1.6),
        Radius.circular(h),
      ),
      Paint()..color = hazardRed.withValues(alpha: 0.22),
    );
    // Solid slab body.
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset(0, center.dy - h / 2),
          Offset(0, center.dy + h / 2),
          const [_hazardHi, hazardRed, _hazardDark],
          const [0.0, 0.5, 1.0],
        ),
    );
    _drawSweepEdge(canvas, rect, center, w, h, s, dir);
    _drawShimmer(canvas, rect, center, w, h, phase);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, h * 0.1)
        ..color = _white.withValues(alpha: 0.5),
    );
    _drawSpikes(canvas, center, w, h);
  }

  /// The bright leading wipe-edge crossing a live slab: a hot vertical bar (the
  /// front of the pass) with a short trailing gradient behind it, clipped to the
  /// slab. Travels left→right for [dir] +1, right→left for −1, at [sweep] 0..1.
  static void _drawSweepEdge(Canvas canvas, RRect rect, Offset center, double w,
      double h, double sweep, double dir) {
    canvas.save();
    canvas.clipRRect(rect);
    final left = center.dx - w / 2;
    // Position the leading edge by sweep; flip travel direction by dir.
    final frac = dir > 0 ? sweep : 1.0 - sweep;
    final ex = left + frac * w;
    final edgeW = math.max(2.0, w * 0.05);
    // Trailing wash behind the edge so the pass has a comet head.
    final tailLen = w * 0.28;
    final tailStart = ex - dir * tailLen;
    canvas.drawRect(
      Rect.fromLTRB(math.min(ex, tailStart), center.dy - h / 2,
          math.max(ex, tailStart), center.dy + h / 2),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = Gradient.linear(
          Offset(tailStart, center.dy),
          Offset(ex, center.dy),
          [const Color(0x00000000), _hazardHi.withValues(alpha: 0.5)],
        ),
    );
    // The hot leading edge itself.
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(ex, center.dy), width: edgeW, height: h),
      Paint()..color = _blend(_hazardHi, _white, 0.5).withValues(alpha: 0.9),
    );
    canvas.restore();
  }

  /// A single bright diagonal sweep crossing the slab face for a metallic
  /// speed-glint. Clipped to [rect] so it stays inside the bar.
  static void _drawShimmer(Canvas canvas, RRect rect, Offset center, double w,
      double h, double phase) {
    if (w <= 1) return;
    canvas.save();
    canvas.clipRRect(rect);
    // Glint travels across the bar, looping with the beat phase.
    final p = (phase * 2.0) % 1.0;
    final gx = center.dx - w / 2 + p * (w + h);
    final band = h * 0.5;
    final glint = Path()
      ..moveTo(gx, center.dy - h)
      ..lineTo(gx + band, center.dy - h)
      ..lineTo(gx + band - h, center.dy + h)
      ..lineTo(gx - h, center.dy + h)
      ..close();
    canvas.drawPath(
      glint,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = _white.withValues(alpha: 0.16),
    );
    canvas.restore();
  }

  /// Hazard-stripe spike teeth along the top + bottom edge so the bar reads as
  /// "do not touch" even at a glance.
  static void _drawSpikes(Canvas canvas, Offset center, double w, double h) {
    final spike = (w * _barSpikeFrac).clamp(3.0, h);
    final n = math.max(2, (w / (spike * 1.6)).floor());
    final paint = Paint()..color = _hazardHi.withValues(alpha: 0.8);
    for (var i = 0; i < n; i++) {
      final x = center.dx - w / 2 + (i + 0.5) * (w / n);
      // top tooth
      final top = Path()
        ..moveTo(x - spike / 2, center.dy - h / 2)
        ..lineTo(x + spike / 2, center.dy - h / 2)
        ..lineTo(x, center.dy - h / 2 - spike * 0.7)
        ..close();
      canvas.drawPath(top, paint);
      // bottom tooth
      final bot = Path()
        ..moveTo(x - spike / 2, center.dy + h / 2)
        ..lineTo(x + spike / 2, center.dy + h / 2)
        ..lineTo(x, center.dy + h / 2 + spike * 0.7)
        ..close();
      canvas.drawPath(bot, paint);
    }
  }

  /// The telegraph: a flashing full-width ghost of the slab pulsing in the warn
  /// color so the player knows a live pass is imminent — freeze NOW.
  static void _drawWarnBar(
      Canvas canvas, Offset center, double w, double h, double pulse) {
    final p = pulse.clamp(0.0, 1.0);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: w, height: h),
      Radius.circular(h * 0.3),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = hazardWarn.withValues(alpha: 0.12 + 0.18 * p),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, h * 0.16)
        ..color = hazardWarn.withValues(alpha: 0.55 + 0.4 * p),
    );
    // A row of warning chevrons across the band so the full-width telegraph
    // reads at a glance (more than one, since the slab now spans the lane).
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, h * 0.14)
      ..strokeCap = StrokeCap.round
      ..color = hazardWarn.withValues(alpha: 0.7 + 0.3 * p);
    final s = h * 0.3;
    for (final f in const [-0.3, -0.1, 0.1, 0.3]) {
      final x = center.dx + f * w;
      canvas.drawLine(Offset(x - s, center.dy - s),
          Offset(x, center.dy), paint);
      canvas.drawLine(Offset(x, center.dy),
          Offset(x - s, center.dy + s), paint);
    }
  }

  // ── Flag at the top (the goal) ──────────────────────────────────────────────
  static void drawFlag(
    Canvas canvas,
    TowerSpec t, {
    required Color color,
    required bool planted,
    required double wave,
  }) {
    final base = t.rungAt(1.0); // top rung — pole rises from here
    final poleH = t.width * _flagPoleFrac;
    final poleTop = Offset(base.dx, base.dy - poleH);

    // Pole.
    canvas.drawLine(
      base,
      poleTop,
      Paint()
        ..color = _railSteelHi
        ..strokeWidth = math.max(2.0, t.width * 0.07)
        ..strokeCap = StrokeCap.round,
    );

    // Planted glow.
    if (planted) {
      canvas.drawCircle(
        poleTop,
        t.width * 0.7,
        Paint()..color = flagGold.withValues(alpha: 0.22),
      );
    }

    // Waving pennant — a triangle flapping off the pole top.
    final w = t.width * 0.7;
    final hh = t.width * 0.34;
    final flutter = math.sin(wave) * w * 0.18;
    final flag = Path()
      ..moveTo(poleTop.dx, poleTop.dy)
      ..lineTo(poleTop.dx, poleTop.dy + hh)
      ..quadraticBezierTo(
        poleTop.dx + w * 0.6 + flutter,
        poleTop.dy + hh * 0.5,
        poleTop.dx + w,
        poleTop.dy + hh * 0.2 + flutter,
      )
      ..close();
    canvas.drawPath(
      flag,
      Paint()..color = planted ? color : flagGold.withValues(alpha: 0.92),
    );
    canvas.drawPath(
      flag,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, t.width * 0.04)
        ..color = _blend(planted ? color : flagGold, _white, 0.5),
    );
    // Finial knob.
    canvas.drawCircle(poleTop, t.width * 0.08,
        Paint()..color = _blend(flagGold, _white, 0.3));
  }

  // ── Climber stickman ────────────────────────────────────────────────────────
  /// The climber clinging to the rail at [root]. [reach] 0..1 lifts a reaching
  /// arm on a step; [stunned] draws it knocked-loose (leaning + dimmed) after a
  /// bar hit. The figure carries its own state clips (attack/hurt/victory).
  static void drawClimber(
    Canvas canvas,
    StickFigure figure,
    Offset root, {
    required double reach,
    required bool stunned,
    required Color color,
    required double scale,
  }) {
    if (stunned) {
      _drawKnockbackWash(canvas, root, scale);
      // Knocked-loose tell: a slight lean (kept) on top of the red wash.
      canvas.save();
      canvas.translate(root.dx, root.dy);
      canvas.rotate(0.12);
      canvas.translate(-root.dx, -root.dy);
      figure.render(canvas, root);
      canvas.restore();
      return;
    }
    final r = reach.clamp(0.0, 1.0);
    // Strain shake: while a step is lunging hard the body trembles. Derived from
    // [reach] only (no clock needed) — reach ramps 0→1→0 across a step, so
    // hashing it through sin() yields a deterministic sub-pixel tremor that lives
    // exactly during the fast part of a climb and dies when clinging.
    final shake = _strainShake(r, scale);
    if (shake != Offset.zero) {
      canvas.save();
      canvas.translate(shake.dx, shake.dy);
      figure.render(canvas, root);
      canvas.restore();
      // Faint effort glow at the hips when straining hardest.
      _softGlow(canvas, root.translate(0, -scale * 0.7), scale * 0.34, color,
          0.12 * r);
    } else {
      figure.render(canvas, root);
    }
    // A drawn reaching hand-hold cue when stepping up.
    if (r > 0.02) {
      final hand = root.translate(
          scale * 0.08 + shake.dx, -scale * (1.5 + 0.5 * r) + shake.dy);
      canvas.drawCircle(
          hand, scale * 0.1 * r, Paint()..color = _blend(color, _white, 0.5));
    }
  }

  /// Deterministic strain tremor for the climbing body. Amplitude ramps with the
  /// step intensity [r]; the offset is a function of [r] alone (two detuned sines)
  /// so it shivers frame-to-frame as [r] sweeps, with no clock and no randomness.
  static Offset _strainShake(double r, double scale) {
    if (r < 0.18) return Offset.zero; // only the hard, fast part of a step
    final amp = scale * 0.05 * r;
    final dx = math.sin(r * 47.0) * amp;
    final dy = math.sin(r * 61.0 + 1.3) * amp * 0.6;
    return Offset(dx, dy);
  }

  /// Red knockback flash behind a bar-struck climber: a layered hot wash plus a
  /// few outward impact streaks. Brighter + punchier than a flat disc so the hit
  /// reads instantly, while staying behind the (leaning) figure.
  static void _drawKnockbackWash(Canvas canvas, Offset root, double scale) {
    final c = root.translate(0, -scale * 0.7);
    // Layered wash (stacked translucent discs, no blur).
    canvas.drawCircle(
        c, scale * 1.05, Paint()..color = hazardRed.withValues(alpha: 0.12));
    canvas.drawCircle(
        c, scale * 0.72, Paint()..color = hazardRed.withValues(alpha: 0.22));
    canvas.drawCircle(c, scale * 0.4,
        Paint()..color = _blend(hazardRed, _white, 0.3).withValues(alpha: 0.3));
    // Impact streaks radiating out — deterministic angles, no per-frame alloc.
    final streak = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.5, scale * 0.06)
      ..color = _hazardHi.withValues(alpha: 0.45);
    for (var i = 0; i < 6; i++) {
      final ang = i * (math.pi * 2 / 6) + 0.4;
      final inner = c + Offset(math.cos(ang), math.sin(ang)) * scale * 0.5;
      final outer = c + Offset(math.cos(ang), math.sin(ang)) * scale * 0.95;
      canvas.drawLine(inner, outer, streak);
    }
  }

  // ── Tap / step flash ring ───────────────────────────────────────────────────
  /// An expanding ring + soft fill on a grabbed rung. [t] is the remaining-life
  /// fraction (1 = fresh, 0 = gone).
  static void drawTapFlash(
      Canvas canvas, Offset at, double t, Color color, double scale) {
    final k = t.clamp(0.0, 1.0);
    if (k <= 0.01) return;
    final grow = 1 - k;
    final r = scale * (0.3 + 0.8 * grow);
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, scale * 0.1 * k)
        ..color = _blend(color, _white, 0.4).withValues(alpha: 0.7 * k),
    );
    _softGlow(canvas, at, r * 0.5, color, 0.24 * k);
  }

  // ── Small private helpers ───────────────────────────────────────────────────
  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  /// Cheap soft glow: a wide faint disc under a tighter brighter one — fakes a
  /// blurred halo without a per-frame [MaskFilter.blur].
  static void _softGlow(Canvas canvas, Offset c, double r, Color color,
      double alpha) {
    final a = alpha.clamp(0.0, 1.0);
    canvas.drawCircle(
        c, r * 1.4, Paint()..color = color.withValues(alpha: a * 0.5));
    canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: a));
  }

  /// Pick black or white text for legibility against [bg].
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
    bool bold = false,
  }) {
    if (fontSize <= 0) return;
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: fontSize * 4));
    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - fontSize * 2, center.dy - fontSize * 0.62),
    );
  }
}
