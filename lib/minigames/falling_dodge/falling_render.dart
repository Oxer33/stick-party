import 'dart:math' as math;
import 'dart:ui';

import '../../art/stick/stick_figure.dart';

/// Kind of falling hazard. Each draws a distinct silhouette and carries its own
/// size / fall-speed feel (chosen by the gameplay module).
enum HazardKind { boulder, anvil, crate }

/// Pure-Canvas rendering for [FallingDodge]. Holds NO game state and never
/// mutates the simulation — callers pass plain value snapshots. Kept in its own
/// file so the gameplay module stays lean and the drawing stays cohesive.
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class FallingRenderer {
  FallingRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _bgTop = Color(0xFF141B2E);
  static const Color _bgBottom = Color(0xFF080B14);
  static const Color _bgSheen = Color(0xFF8B5CF6); // overhead cool-violet wash
  static const Color _bgHeatDeep = Color(0xFFFB7234); // deep molten floor glow
  static const Color _bandFloorBlend = Color(0xFF0B0F18);
  static const Color _divider = Color(0xFF1E2940);
  static const Color _laneLine = Color(0x14FFFFFF);
  static const Color _laneLineLit = Color(0x33FFFFFF);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _scrollTex = Color(0x0EFFFFFF);
  static const Color _scrollTexFar = Color(0x07FFFFFF); // distant parallax layer
  static const Color _telegraph = Color(0xFFFF5A4D);
  // Late-dodge window: AMBER while warming (get ready) → hot RED in the scoring
  // late window (dodge NOW). The split color is the whole readability of the
  // mechanic, so the two states never blur into one.
  static const Color _telegraphWarm = Color(0xFFFFA02A); // warm: building danger
  static const Color _telegraphHot = Color(0xFFFF3A2A); // hot: the scoring window
  static const Color _nearMissTint = Color(0x3325E0FF);

  // Hazard body colors.
  static const Color _boulderHi = Color(0xFF8C8478);
  static const Color _boulderLo = Color(0xFF4A453D);
  static const Color _boulderEdge = Color(0xFF2C2925);
  static const Color _anvilHi = Color(0xFF5C6373);
  static const Color _anvilLo = Color(0xFF2A2E38);
  static const Color _anvilEdge = Color(0xFF15171D);
  static const Color _crateHi = Color(0xFFB07B43);
  static const Color _crateLo = Color(0xFF6E4A24);
  static const Color _crateEdge = Color(0xFF3A2613);
  static const Color _spike = Color(0xFFCBD2DE);

  // ── Tuning (visual only) ───────────────────────────────────────────────────
  static const double _dividerH = 2.0;
  static const double _floorFade = 0.34; // floor tint strength at band bottom
  static const int _scrollRows = 5; // scrolling texture chevrons per band
  static const double _contactShadowW = 2.0;
  static const double _contactShadowH = 0.42;
  static const double _telegraphMaxH = 0.55; // marker height / hazard size
  static const double _dropShadowMax = 0.9; // hazard shadow width / size at land

  // Directional hop-hint chevrons flanking the runner.
  static const double _hintReachFactor = 0.46; // gap from runner / lane spacing
  static const double _hintSizeFactor = 0.18; // chevron arm length / lane spacing
  static const double _hintLiftFactor = 0.55; // lift above ground / lane spacing
  static const double _hintGlideFactor = 0.06; // outward breathe travel / spacing

  // ── Background ──────────────────────────────────────────────────────────────

  /// Full-arena vertical gradient backdrop. Drawn once under every band. Layers
  /// (bottom → top): base gradient, an overhead cool-violet sheen, a bottom heat
  /// wash that swells with [intensity], and a soft vignette that frames the play
  /// and deepens with the escalation so the finale reads hottest + most focused.
  static void drawBackground(Canvas canvas, Size size, double intensity) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgBottom],
      );
    canvas.drawRect(rect, bg);

    final heat = intensity.clamp(0.0, 1.0);

    // Overhead sheen: a faint cool wash from the top sells "deep arcade night"
    // and gives the backdrop a top-lit read under the bands.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height * 0.5),
          [
            _bgSheen.withValues(alpha: 0.10),
            const Color(0x00000000),
          ],
        ),
    );

    // Escalation heat: a layered red wash from the bottom as the game ramps —
    // a wide deep glow under a tighter brighter core so the floor feels molten.
    if (heat > 0.01) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.linear(
            Offset(size.width / 2, size.height),
            Offset(size.width / 2, size.height * 0.40),
            [
              _bgHeatDeep.withValues(alpha: 0.12 * heat),
              const Color(0x00000000),
            ],
          ),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = Gradient.linear(
            Offset(size.width / 2, size.height),
            Offset(size.width / 2, size.height * 0.62),
            [
              _telegraph.withValues(alpha: 0.10 * heat),
              const Color(0x00000000),
            ],
          ),
      );
    }

    // Vignette: a soft radial darken from the edges keeps the eye on the lanes
    // and tightens (deepens) with the escalation. Single radial — no per-entity
    // blur — so it stays cheap.
    final vig = (0.26 + 0.18 * heat).clamp(0.0, 1.0);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.46),
          size.longestSide * 0.62,
          [
            const Color(0x00000000),
            _black.withValues(alpha: vig),
          ],
          const [0.55, 1.0],
        ),
    );
  }

  // ── One player band ─────────────────────────────────────────────────────────

  /// The band backdrop: a player-tinted floor that darkens toward the bottom, a
  /// scrolling downward chevron texture for motion, neon lane dividers and a
  /// glowing frame. [scroll] is an ever-increasing phase (px) driving the
  /// texture; [danger] in 0..1 brightens the frame when a hazard is close.
  static void drawBand(
    Canvas canvas,
    Rect band,
    Color color, {
    required double scroll,
    required double danger,
    required bool alive,
  }) {
    if (band.width <= 1 || band.height <= 1) return;
    final a = alive ? 1.0 : 0.4;

    // Tinted floor: dark base → faint player color toward the bottom.
    final floor = Paint()
      ..shader = Gradient.linear(
        Offset(band.center.dx, band.top),
        Offset(band.center.dx, band.bottom),
        [
          _bandFloorBlend,
          _blend(_bandFloorBlend, color, _floorFade * a),
        ],
      );
    canvas.drawRect(band, floor);

    _drawScrollTexture(canvas, band, scroll, a);
    _drawTopDivider(canvas, band, a);
    _drawBandFrame(canvas, band, color, danger, a);
  }

  /// Downward-scrolling chevrons sell the sense of falling motion. Two parallax
  /// layers: a faint, slower, larger "far" layer set behind a brighter, faster,
  /// tighter "near" layer — the speed/scale split reads as depth so the whole
  /// band feels like it is rushing upward past the runner.
  static void _drawScrollTexture(
      Canvas canvas, Rect band, double scroll, double a) {
    if (band.height / _scrollRows <= 2) return;
    // Far layer first (slower, larger, dimmer), then the near layer over it.
    _drawChevronLayer(canvas, band, scroll * 0.55, a,
        rows: _scrollRows - 1, widthFactor: 0.085, color: _scrollTexFar,
        offset: band.width * 0.5);
    _drawChevronLayer(canvas, band, scroll, a,
        rows: _scrollRows, widthFactor: 0.06, color: _scrollTex);
  }

  /// One downward-chevron layer at a given [scroll] phase / density. [offset]
  /// staggers a layer's horizontal phase so the two layers never line up.
  static void _drawChevronLayer(
    Canvas canvas,
    Rect band,
    double scroll,
    double a, {
    required int rows,
    required double widthFactor,
    required Color color,
    double offset = 0.0,
  }) {
    final rowGap = band.height / rows;
    if (rowGap <= 2) return;
    final phase = scroll % rowGap;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, band.height * 0.012 * (widthFactor / 0.06))
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: color.a * a);
    final w = band.width * widthFactor;
    final step = w * 3.4;
    for (var r = -1; r <= rows; r++) {
      final y = band.top + phase + r * rowGap;
      if (y < band.top - rowGap || y > band.bottom + rowGap) continue;
      // A sparse row of small downward chevrons across the width.
      final start = band.left + w + (offset % step);
      for (var x = start; x < band.right - w; x += step) {
        final path = Path()
          ..moveTo(x - w * 0.5, y - w * 0.28)
          ..lineTo(x, y + w * 0.28)
          ..lineTo(x + w * 0.5, y - w * 0.28);
        canvas.drawPath(path, paint);
      }
    }
  }

  /// Faint top divider line between stacked player bands.
  static void _drawTopDivider(Canvas canvas, Rect band, double a) {
    canvas.drawRect(
      Rect.fromLTWH(band.left, band.top, band.width, _dividerH),
      Paint()..color = _divider.withValues(alpha: _divider.a * a),
    );
  }

  /// Soft neon frame around the band; brightens with [danger].
  static void _drawBandFrame(
      Canvas canvas, Rect band, Color color, double danger, double a) {
    final d = danger.clamp(0.0, 1.0);
    final inset = band.deflate(math.max(2.0, band.height * 0.02));
    final rrect = RRect.fromRectAndRadius(
        inset, Radius.circular(math.max(6.0, band.height * 0.05)));

    // Soft outer aura: a wide, faint stroke (no blur) under the crisp core line.
    // Widens with danger instead of blurring more — cheap per band.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3.0, band.height * 0.035 + 6 * d)
      ..color = color.withValues(alpha: (0.10 + 0.2 * d) * a);
    canvas.drawRRect(rrect, glow);

    // Crisp core line.
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, band.height * 0.008)
      ..color = color.withValues(alpha: (0.45 + 0.4 * d) * a);
    canvas.drawRRect(rrect, core);
  }

  // ── Lane dividers (vertical) ──────────────────────────────────────────────

  /// Vertical lane guide lines inside a band. The runner's current lane is lit
  /// brighter so it reads clearly, and (when [color]/[phase] are supplied) gets a
  /// soft player-color wash column; a faint shimmer sweeps the safe lanes so the
  /// playfield feels alive. All additive + readability-preserving.
  static void drawLanes(
    Canvas canvas,
    Rect band,
    List<double> laneX,
    double runnerVisualLane,
    bool alive, {
    Color? color,
    double phase = 0.0,
  }) {
    final a = alive ? 1.0 : 0.4;
    final top = band.top + band.height * 0.06;
    final bottom = band.bottom - band.height * 0.06;

    // Soft player-color wash under the current lane: a gentle vertical column so
    // "you are here" reads instantly even before the eye finds the runner.
    if (color != null && laneX.length > 1 && alive) {
      final litIdx = runnerVisualLane.round().clamp(0, laneX.length - 1);
      final span = (laneX.length > 1)
          ? (laneX[1] - laneX[0]).abs()
          : band.width * 0.5;
      final lx = laneX[litIdx];
      final breathe = 0.5 + 0.5 * math.sin(phase * 2.2);
      final washW = span * 0.86;
      canvas.drawRect(
        Rect.fromLTRB(lx - washW * 0.5, top, lx + washW * 0.5, bottom),
        Paint()
          ..shader = Gradient.linear(
            Offset(lx, top),
            Offset(lx, bottom),
            [
              color.withValues(alpha: (0.05 + 0.05 * breathe) * a),
              color.withValues(alpha: (0.12 + 0.06 * breathe) * a),
            ],
          ),
      );
    }

    for (var i = 0; i < laneX.length; i++) {
      final x = laneX[i];
      final lit = (i - runnerVisualLane).abs() < 0.5;
      // Safe-zone shimmer: a slow per-lane brightness ripple (deterministic via
      // index + phase) that travels across the non-current lanes.
      final shimmer = lit
          ? 0.0
          : (0.5 + 0.5 * math.sin(phase * 1.6 - i * 0.9)).clamp(0.0, 1.0);
      final baseA = (lit ? _laneLineLit.a : _laneLine.a) * a;
      final paint = Paint()
        ..strokeWidth = lit ? 2.4 : 1.6
        ..strokeCap = StrokeCap.round
        ..color = (lit ? _laneLineLit : _laneLine)
            .withValues(alpha: baseA * (1.0 + 0.6 * shimmer));
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  // ── Telegraph: ground marker in a hazard's target lane ────────────────────

  /// The VISIBLE late-dodge window: a ground marker under a hazard's target lane
  /// that telegraphs WHEN to dodge, not just where. It has two readable states:
  ///
  ///  * WARM ([hotFrac] == 0): an AMBER ring that CONTRACTS from wide toward a
  ///    tight core as [warmFrac] (0→1) grows — "danger building, get ready". A
  ///    hop now is safe but scores nothing.
  ///  * HOT ([hotFrac] > 0): the ring SNAPS to RED, locks tight, throbs faster,
  ///    and a closing bracket cinches in as [hotFrac] (0→1) climbs to impact —
  ///    the unmistakable "NOW". Stepping off a HOT lane is the ONLY scoring dodge.
  ///
  /// [progress] (overall closeness, 1 = about to hit) still drives the down-caret
  /// stack. [phase] (seconds) breathes the glow. All additive, no blur, pure
  /// Canvas — safe to call from render and never throws.
  static void drawTelegraph(
    Canvas canvas,
    double laneX,
    double groundY,
    double hazardSize,
    double progress, {
    double phase = 0.0,
    double warmFrac = 0.0,
    double hotFrac = 0.0,
  }) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.02) return;
    final warm = warmFrac.clamp(0.0, 1.0);
    final hot = hotFrac.clamp(0.0, 1.0);
    final isHot = hot > 0.0;

    // Color flips amber → red the instant the window goes hot; intensity ramps
    // with how late we are inside it.
    final color = isHot ? _telegraphHot : _telegraphWarm;

    // The marker CONTRACTS as the hazard nears: wide while early-warm, cinching
    // to a tight locked ring through the hot window. (reach: 1.5 → ~0.5.)
    final reach =
        isHot ? (0.78 - 0.30 * hot) : (1.5 - 0.72 * warm).clamp(0.78, 1.5);
    final w = hazardSize * reach;
    final h = hazardSize * _telegraphMaxH * (isHot ? 0.92 : 1.0);

    // Faster throb + stronger core once hot, so it reads as "armed".
    final pulse = 0.5 + 0.5 * math.sin(phase * (isHot ? 9.0 : 5.0));
    final intensity = isHot ? (0.55 + 0.45 * hot) : (0.18 + 0.30 * warm);

    // Pulsing glow halo (behind everything).
    final haloScale = (isHot ? 1.5 : 1.9) + 0.5 * pulse;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(laneX, groundY),
        width: w * haloScale,
        height: h * (haloScale * 0.92),
      ),
      Paint()
        ..color = color.withValues(
            alpha: (0.05 + 0.16 * intensity) * (0.55 + 0.45 * pulse)),
    );

    // Soft halo: two stacked translucent ovals fake the blur cheaply.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(laneX, groundY), width: w * 1.3, height: h * 1.5),
      Paint()..color = color.withValues(alpha: 0.06 + 0.22 * intensity),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(laneX, groundY), width: w, height: h),
      Paint()..color = color.withValues(alpha: 0.10 + 0.30 * intensity),
    );

    // Crisp ring (thickens + brightens when hot).
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, hazardSize * (isHot ? 0.075 : 0.05))
      ..color = color.withValues(alpha: 0.40 + 0.55 * intensity);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(laneX, groundY), width: w * 0.78, height: h * 0.78),
      ring,
    );

    // HOT-only: a hard bright inner core + a closing "lock bracket" that cinches
    // toward the center as impact nears — the felt "it's locked on, dodge NOW".
    if (isHot) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(laneX, groundY),
            width: w * 0.34,
            height: h * 0.34),
        Paint()
          ..color = _white.withValues(
              alpha: (0.30 + 0.5 * hot) * (0.6 + 0.4 * pulse)),
      );
      _drawHotBracket(canvas, laneX, groundY, hazardSize, hot, color);
    }

    // Down-pointing caret stack: more carets as the hazard nears.
    final carets = 1 + (p * 2).round();
    final caret = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, hazardSize * (isHot ? 0.06 : 0.045))
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.5 + 0.45 * intensity);
    final cw = hazardSize * 0.22;
    for (var i = 0; i < carets; i++) {
      final cy = groundY - h * 0.9 - i * cw * 0.85;
      final path = Path()
        ..moveTo(laneX - cw * 0.5, cy - cw * 0.35)
        ..lineTo(laneX, cy + cw * 0.35)
        ..lineTo(laneX + cw * 0.5, cy - cw * 0.35);
      canvas.drawPath(path, caret);
    }
  }

  /// A pair of opposing corner ticks that cinch INWARD toward the lane center as
  /// [hot] (0→1) climbs — a targeting-lock "brackets closing" read on the HOT
  /// window. Pure additive strokes; deterministic off [hot].
  static void _drawHotBracket(Canvas canvas, double laneX, double groundY,
      double hazardSize, double hot, Color color) {
    // Bracket span shrinks from wide to tight as the hazard locks on.
    final span = hazardSize * (0.62 - 0.30 * hot);
    final arm = hazardSize * 0.16;
    final yh = hazardSize * _telegraphMaxH * 0.5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, hazardSize * 0.05)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.55 + 0.4 * hot);
    // Left + right vertical ticks bracketing the lane, just above the line.
    for (final s in const [-1.0, 1.0]) {
      final x = laneX + s * span;
      canvas.drawLine(Offset(x, groundY - yh), Offset(x, groundY + yh), paint);
      // Small inward foot so it reads as a corner bracket, not a plain bar.
      canvas.drawLine(
          Offset(x, groundY + yh), Offset(x - s * arm, groundY + yh), paint);
      canvas.drawLine(
          Offset(x, groundY - yh), Offset(x - s * arm, groundY - yh), paint);
    }
  }

  // ── Hazard ────────────────────────────────────────────────────────────────

  /// Draw a falling hazard centered at [center]. [groundY] is the runner line;
  /// the drop-shadow grows + tightens as the hazard approaches it (extra
  /// telegraph). [spin] rotates the boulder/crate for tumbling feel.
  static void drawHazard(
    Canvas canvas,
    Offset center,
    double size,
    HazardKind kind,
    double groundY,
    double spin,
  ) {
    _drawHazardShadow(canvas, center, size, groundY);
    // Impact dust: a deterministic burst of grit kicked up as the body reaches
    // the runner line, fading out just below it so a landing/hit reads with a
    // punch. Drawn under the body so the silhouette stays clean.
    _drawImpactDust(canvas, center, size, groundY, kind);
    switch (kind) {
      case HazardKind.boulder:
        _drawBoulder(canvas, center, size, spin);
      case HazardKind.anvil:
        _drawAnvil(canvas, center, size, spin);
      case HazardKind.crate:
        _drawCrate(canvas, center, size, spin);
    }
  }

  /// A short-lived grit burst at the ground line as a hazard lands/hits. The
  /// strength ramps in over a small window straddling [groundY] and fades just
  /// past it, so it fires exactly once per fall with no extra state. Particle
  /// fan-out is deterministic (index trig), never rng — render stays pure.
  static void _drawImpactDust(Canvas canvas, Offset center, double size,
      double groundY, HazardKind kind) {
    final dist = center.dy - groundY; // <0 above the line, >0 below
    // Active window: from just above the line to a body-height below it.
    final window = size * 0.9;
    if (dist < -size * 0.25 || dist > window) return;
    // Strength: 0 at the top edge, peaks at the line, fades to 0 below.
    final t = dist <= 0
        ? (1.0 + dist / (size * 0.25)).clamp(0.0, 1.0)
        : (1.0 - dist / window).clamp(0.0, 1.0);
    if (t <= 0.02) return;

    final dust = _dustColorFor(kind);
    const motes = 7;
    final spread = size * (0.55 + 0.7 * t);
    final lift = size * 0.22 * t;
    final fill = Paint()..color = dust.withValues(alpha: 0.16 + 0.20 * t);
    for (var i = 0; i < motes; i++) {
      // Symmetric fan kicked outward from the contact point.
      final dir = (i.isEven ? 1 : -1);
      final frac = (i + 1) / (motes + 1);
      final dx = dir * spread * frac;
      // Higher motes nearer the center, lower ones farther out (a low plume).
      final dy = -lift * (1.0 - frac) - size * 0.04;
      final r = size * (0.10 + 0.06 * (1.0 - frac)) * (0.6 + 0.4 * t);
      canvas.drawCircle(Offset(center.dx + dx, groundY + dy), r, fill);
    }
    // A faint flat scuff right on the line ties the plume to the ground.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, groundY),
        width: spread * 2.0,
        height: size * 0.16 * t,
      ),
      Paint()..color = dust.withValues(alpha: 0.10 + 0.12 * t),
    );
  }

  /// Grit tint per hazard so dust reads as "from that thing" (stone/iron/wood).
  static Color _dustColorFor(HazardKind kind) {
    switch (kind) {
      case HazardKind.boulder:
        return _boulderHi;
      case HazardKind.anvil:
        return _anvilHi;
      case HazardKind.crate:
        return _crateHi;
    }
  }

  /// Soft drop-shadow that grows and darkens as the hazard nears the ground.
  static void _drawHazardShadow(
      Canvas canvas, Offset center, double size, double groundY) {
    final dist = groundY - center.dy;
    // Near = small dist; map a window above the ground onto 0..1 closeness.
    final near = (1.0 - (dist / (size * 6)).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    final w = size * (0.5 + _dropShadowMax * near);
    final h = size * (0.18 + 0.18 * near);
    // Two stacked translucent ovals (wide+faint under tight+darker) fake the soft
    // shadow without a per-hazard blur.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(center.dx, groundY), width: w * 1.3, height: h * 1.5),
      Paint()..color = _black.withValues(alpha: 0.10 + 0.16 * near),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx, groundY), width: w, height: h),
      Paint()..color = _black.withValues(alpha: 0.16 + 0.26 * near),
    );
  }

  static void _drawBoulder(
      Canvas canvas, Offset center, double size, double spin) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(spin);
    final r = size * 0.5;

    // Rough circular silhouette built from a slightly irregular polygon.
    final path = Path();
    const points = 9;
    for (var i = 0; i <= points; i++) {
      final ang = (i / points) * math.pi * 2;
      // Deterministic lumpiness from a cheap trig sum (no rng needed).
      final lump = 1.0 + 0.10 * math.sin(ang * 3) + 0.06 * math.sin(ang * 7);
      final pr = r * lump;
      final x = math.cos(ang) * pr;
      final y = math.sin(ang) * pr;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Body gradient (top-lit).
    final body = Paint()
      ..shader = Gradient.radial(
        Offset(-r * 0.3, -r * 0.4),
        r * 1.6,
        const [_boulderHi, _boulderLo],
      );
    canvas.drawPath(path, body);

    // Dark rim.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size * 0.045)
        ..color = _boulderEdge,
    );

    // A couple of cracks for texture.
    final crack = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size * 0.03)
      ..strokeCap = StrokeCap.round
      ..color = _boulderEdge.withValues(alpha: 0.7);
    canvas.drawLine(
        Offset(-r * 0.2, -r * 0.3), Offset(r * 0.1, r * 0.2), crack);
    canvas.drawLine(Offset(r * 0.1, r * 0.2), Offset(r * 0.45, r * 0.1), crack);

    // Specular highlight.
    canvas.drawCircle(
      Offset(-r * 0.32, -r * 0.4),
      r * 0.2,
      Paint()..color = _white.withValues(alpha: 0.18),
    );
    canvas.restore();
  }

  static void _drawAnvil(
      Canvas canvas, Offset center, double size, double spin) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    // Heavy iron rocks rather than tumbles: a small bounded sway off the spin
    // clock keeps it weighty while still feeling like it is falling free.
    canvas.rotate(math.sin(spin) * 0.16);
    final w = size * 0.92;
    final h = size * 0.82;

    // Anvil silhouette: top flat with horn, narrow waist, splayed base.
    final path = Path()
      ..moveTo(-w * 0.5, -h * 0.5)
      ..lineTo(w * 0.42, -h * 0.5)
      ..lineTo(w * 0.5, -h * 0.28) // horn
      ..lineTo(w * 0.18, -h * 0.22)
      ..lineTo(w * 0.16, h * 0.04) // waist right
      ..lineTo(w * 0.4, h * 0.22)
      ..lineTo(w * 0.4, h * 0.5) // base right
      ..lineTo(-w * 0.4, h * 0.5)
      ..lineTo(-w * 0.4, h * 0.22)
      ..lineTo(-w * 0.16, h * 0.04) // waist left
      ..lineTo(-w * 0.18, -h * 0.22)
      ..lineTo(-w * 0.5, -h * 0.28)
      ..close();

    final body = Paint()
      ..shader = Gradient.linear(
        Offset(0, -h * 0.5),
        Offset(0, h * 0.5),
        const [_anvilHi, _anvilLo],
      );
    canvas.drawPath(path, body);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size * 0.04)
        ..color = _anvilEdge,
    );

    // Top face sheen.
    canvas.drawLine(
      Offset(-w * 0.46, -h * 0.46),
      Offset(w * 0.36, -h * 0.46),
      Paint()
        ..strokeWidth = math.max(1.0, size * 0.04)
        ..strokeCap = StrokeCap.round
        ..color = _white.withValues(alpha: 0.22),
    );
    canvas.restore();
  }

  static void _drawCrate(
      Canvas canvas, Offset center, double size, double spin) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(spin * 0.4); // crates tumble gently
    final s = size * 0.84;
    final rect = Rect.fromCenter(center: Offset.zero, width: s, height: s);

    // Spikes poking out of every side.
    final spikePaint = Paint()..color = _spike;
    final spikeEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size * 0.02)
      ..color = _anvilEdge;
    const spikesPerSide = 3;
    for (var side = 0; side < 4; side++) {
      for (var i = 0; i < spikesPerSide; i++) {
        final t = (i + 1) / (spikesPerSide + 1);
        final along = (t - 0.5) * s;
        final out = size * 0.16;
        final half = size * 0.07;
        late Offset base1, base2, tip;
        switch (side) {
          case 0: // top
            base1 = Offset(along - half, -s * 0.5);
            base2 = Offset(along + half, -s * 0.5);
            tip = Offset(along, -s * 0.5 - out);
          case 1: // right
            base1 = Offset(s * 0.5, along - half);
            base2 = Offset(s * 0.5, along + half);
            tip = Offset(s * 0.5 + out, along);
          case 2: // bottom
            base1 = Offset(along - half, s * 0.5);
            base2 = Offset(along + half, s * 0.5);
            tip = Offset(along, s * 0.5 + out);
          default: // left
            base1 = Offset(-s * 0.5, along - half);
            base2 = Offset(-s * 0.5, along + half);
            tip = Offset(-s * 0.5 - out, along);
        }
        final spike = Path()
          ..moveTo(base1.dx, base1.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(base2.dx, base2.dy)
          ..close();
        canvas.drawPath(spike, spikePaint);
        canvas.drawPath(spike, spikeEdge);
      }
    }

    // Wooden box body.
    final body = Paint()
      ..shader = Gradient.linear(
        Offset(-s * 0.5, -s * 0.5),
        Offset(s * 0.5, s * 0.5),
        const [_crateHi, _crateLo],
      );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size * 0.06));
    canvas.drawRRect(rrect, body);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, size * 0.05)
        ..color = _crateEdge,
    );

    // Plank cross-braces.
    final brace = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size * 0.04)
      ..color = _crateEdge.withValues(alpha: 0.8);
    canvas.drawLine(
        Offset(-s * 0.5, -s * 0.5), Offset(s * 0.5, s * 0.5), brace);
    canvas.drawLine(
        Offset(s * 0.5, -s * 0.5), Offset(-s * 0.5, s * 0.5), brace);
    canvas.restore();
  }

  // ── Runner contact shadow ─────────────────────────────────────────────────

  /// Soft contact shadow ellipse beneath the runner at the ground line.
  static void drawContactShadow(
      Canvas canvas, Offset groundCenter, double width, bool alive) {
    if (!alive) return;
    // Two stacked translucent ovals (wide+faint under tight+darker) fake the
    // soft edge without a per-runner blur.
    canvas.drawOval(
      Rect.fromCenter(
        center: groundCenter,
        width: width * (_contactShadowW + 0.5),
        height: width * (_contactShadowH + 0.18),
      ),
      Paint()..color = _black.withValues(alpha: 0.14),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: groundCenter,
        width: width * _contactShadowW,
        height: width * _contactShadowH,
      ),
      Paint()..color = _black.withValues(alpha: 0.26),
    );
  }

  // ── Directional hop hints (the control affordance) ─────────────────────────

  /// Draw the player's directional control cue: a small chevron on each side of
  /// the runner pointing the way a tap on that side will hop. [laneSpacing] sizes
  /// them to the lane gap; [pulse] in 0..1 gently breathes them; a side fades when
  /// its [canLeft]/[canRight] is false (the runner is against that wall).
  static void drawHopHints(
    Canvas canvas,
    Offset runnerGround,
    double laneSpacing,
    Color color,
    double pulse, {
    required bool canLeft,
    required bool canRight,
  }) {
    final reach = laneSpacing * _hintReachFactor;
    final s = laneSpacing * _hintSizeFactor;
    final y = runnerGround.dy - laneSpacing * _hintLiftFactor;
    final p = pulse.clamp(0.0, 1.0);
    final glide = laneSpacing * _hintGlideFactor * p;

    if (canLeft) {
      _drawChevron(
          canvas, Offset(runnerGround.dx - reach - glide, y), s, color, -1, p);
    }
    if (canRight) {
      _drawChevron(
          canvas, Offset(runnerGround.dx + reach + glide, y), s, color, 1, p);
    }
  }

  /// One double-stroke chevron pointing toward [dir] (-1 left / +1 right).
  static void _drawChevron(
      Canvas canvas, Offset tip, double size, Color color, int dir, double p) {
    final back = -dir.toDouble();
    // Two arms meeting at the tip, opening away from the travel direction.
    final path = Path()
      ..moveTo(tip.dx + back * size, tip.dy - size * 0.62)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + back * size, tip.dy + size * 0.62);
    // Soft aura underlay: a wide, faint stroke (no blur) beneath the crisp
    // chevron + white core — the layered widths fake the glow cheaply.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(2.4, size * 0.62)
        ..color = color.withValues(alpha: 0.12 + 0.16 * p),
    );
    // Crisp color stroke so it reads over the dark band.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.6, size * 0.28)
        ..color = color.withValues(alpha: (0.6 + 0.35 * p).clamp(0.0, 1.0)),
    );
    // White core highlight.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.8, size * 0.1)
        ..color = _white.withValues(alpha: (0.45 + 0.3 * p).clamp(0.0, 1.0)),
    );
  }

  // ── Graze-chain streak badge ───────────────────────────────────────────────

  static const Color _chainCool = Color(0xFF35E0FF); // low streak
  static const Color _chainHot = Color(0xFFFFC23C); // high streak

  /// A floating streak badge above the runner showing the live graze chain: a
  /// stack of pips (one per link, capped) plus an "xN" once it is worth bragging
  /// about. Cool at a short streak, hot as it grows — the at-a-glance "how big
  /// is my combo" read that makes hugging danger feel rewarding to kids. Drawn
  /// only while a chain is live ([chain] >= 1).
  static void drawGrazeChain(
    Canvas canvas,
    Offset above,
    double figureScale,
    int chain,
    int maxPips,
    double pulse, {
    double flash = 0.0,
  }) {
    if (chain < 1) return;
    final shown = chain < maxPips ? chain : maxPips;
    final heat =
        (maxPips <= 1 ? 0.0 : (shown - 1) / (maxPips - 1)).clamp(0.0, 1.0);
    final color = _blend(_chainCool, _chainHot, heat);
    final p = pulse.clamp(0.0, 1.0);
    final f = flash.clamp(0.0, 1.0); // one-shot flare on the freshest link

    // The flare scales the whole badge up briefly so a NEW link visibly pops.
    final r = math.max(2.0, 3.0 * figureScale) * (1.0 + 0.12 * p + 0.5 * f);
    final gap = r * 2.6;
    final totalW = (shown - 1) * gap;
    final y = above.dy;
    final startX = above.dx - totalW / 2;

    // Expanding burst ring on a fresh graze — a felt "level up" pop behind the
    // pips (fades as [flash] decays).
    if (f > 0.02) {
      canvas.drawCircle(
        Offset(above.dx, y),
        r * (3.0 + 5.0 * (1.0 - f)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, r * 0.5 * f)
          ..color = color.withValues(alpha: 0.5 * f),
      );
    }

    for (var i = 0; i < shown; i++) {
      final c = Offset(startX + i * gap, y);
      // The freshest pip glows hottest on a flare.
      final isNewest = i == shown - 1;
      final glowA = 0.18 + (isNewest ? 0.5 * f : 0.0);
      canvas.drawCircle(
          c, r * (1.7 + 0.6 * (isNewest ? f : 0.0)),
          Paint()..color = color.withValues(alpha: glowA));
      canvas.drawCircle(c, r, Paint()..color = color);
      canvas.drawCircle(
        c.translate(-r * 0.28, -r * 0.28),
        r * 0.4,
        Paint()..color = _white.withValues(alpha: 0.6 + 0.4 * (isNewest ? f : 0.0)),
      );
    }
    // "xN" label once the streak is genuinely stacking.
    if (chain >= 2) {
      _drawChainLabel(canvas, Offset(above.dx, y - r * 3.4), 'x$chain', color,
          math.max(11.0, 9.0 * figureScale) * (1.0 + 0.08 * p + 0.25 * f));
    }
  }

  static void _drawChainLabel(Canvas canvas, Offset center, String text,
      Color color, double fontSize) {
    if (fontSize <= 1) return;
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    const w = 120.0;
    final paragraph = builder.build()
      ..layout(const ParagraphConstraints(width: w));
    canvas.drawParagraph(
        paragraph, Offset(center.dx - w / 2, center.dy - fontSize * 0.6));
  }

  // ── Near-miss flash on a lane ──────────────────────────────────────────────

  /// A brief cyan column flash in the lane where a near-miss just happened.
  static void drawNearMissFlash(
    Canvas canvas,
    Rect band,
    double laneX,
    double strength,
  ) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    final w = band.width * 0.16 * (0.6 + 0.6 * s);
    final paint = Paint()
      ..shader = Gradient.linear(
        Offset(laneX, band.top),
        Offset(laneX, band.bottom),
        [
          _nearMissTint.withValues(alpha: _nearMissTint.a * s),
          const Color(0x00000000),
        ],
      );
    canvas.drawRect(
      Rect.fromLTRB(laneX - w * 0.5, band.top, laneX + w * 0.5, band.bottom),
      paint,
    );
  }

  // ── Golden token (chaos pickup) ────────────────────────────────────────────

  static const Color _tokenGold = Color(0xFFFFB31E);
  static const Color _tokenGoldHi = Color(0xFFFFE99A);

  /// A glowing golden coin to scoop for bonus points. Stacked translucent halos
  /// (no blur), a filled disc with a rim, and a twinkle that pulses with [t].
  static void drawToken(Canvas canvas, Offset center, double size, double t) {
    final r = size * 0.5;
    final pulse = 0.5 + 0.5 * math.sin(t * 6.0);
    // Soft halos.
    canvas.drawCircle(center, r * (2.4 + 0.5 * pulse),
        Paint()..color = _tokenGold.withValues(alpha: 0.14));
    canvas.drawCircle(center, r * (1.7 + 0.3 * pulse),
        Paint()..color = _tokenGold.withValues(alpha: 0.26));
    // Coin body with a soft top→bottom gradient.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = Gradient.linear(
          center.translate(0, -r),
          center.translate(0, r),
          [_tokenGoldHi, _tokenGold],
        ),
    );
    // Rim.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.16)
        ..color = _tokenGoldHi.withValues(alpha: 0.9),
    );
    // Twinkle.
    canvas.drawCircle(
      center.translate(-r * 0.28, -r * 0.28),
      r * 0.26,
      Paint()..color = _white.withValues(alpha: 0.5 + 0.4 * pulse),
    );
  }

  // ── Runner figure passthrough ─────────────────────────────────────────────

  /// Render the stick runner. Kept here so the painter call lives with the rest
  /// of the visuals; [figure] owns its own pose/ragdoll state.
  static void drawRunner(Canvas canvas, StickFigure figure, Offset root) {
    figure.render(canvas, root);
  }

  // ── Per-band player label ──────────────────────────────────────────────────

  /// A small player identity marker in the band corner: a glowing colored pip
  /// inside a soft ring. Purely a color cue (no glyphs) so it reads instantly
  /// and stays font-independent.
  static void drawBandLabel(Canvas canvas, Rect band, Color color, bool alive) {
    final a = alive ? 0.95 : 0.4;
    final pad = math.max(8.0, band.height * 0.05);
    final pip = math.max(4.0, band.height * 0.02);
    final c = Offset(band.left + pad + pip, band.top + pad + pip);

    // Soft glow: two stacked translucent halos (wide+faint, tight+stronger)
    // instead of a per-band blur.
    canvas.drawCircle(
        c, pip * 2.6, Paint()..color = color.withValues(alpha: 0.14 * a));
    canvas.drawCircle(
        c, pip * 2.0, Paint()..color = color.withValues(alpha: 0.26 * a));
    // Outer ring.
    canvas.drawCircle(
      c,
      pip * 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, pip * 0.35)
        ..color = color.withValues(alpha: 0.7 * a),
    );
    // Core pip with a bright center.
    canvas.drawCircle(c, pip, Paint()..color = color.withValues(alpha: a));
    canvas.drawCircle(
      c.translate(-pip * 0.25, -pip * 0.25),
      pip * 0.4,
      Paint()..color = _white.withValues(alpha: 0.6 * a),
    );
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;
}
