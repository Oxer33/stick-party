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
  static const Color _bandFloorBlend = Color(0xFF0B0F18);
  static const Color _divider = Color(0xFF1E2940);
  static const Color _laneLine = Color(0x14FFFFFF);
  static const Color _laneLineLit = Color(0x33FFFFFF);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _scrollTex = Color(0x0EFFFFFF);
  static const Color _telegraph = Color(0xFFFF5A4D);
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

  /// Full-arena vertical gradient backdrop. Drawn once under every band.
  static void drawBackground(Canvas canvas, Size size, double intensity) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgBottom],
      );
    canvas.drawRect(Offset.zero & size, bg);

    // Escalation heat: a faint red wash from the bottom as the game ramps.
    final heat = intensity.clamp(0.0, 1.0);
    if (heat > 0.01) {
      final wash = Paint()
        ..shader = Gradient.linear(
          Offset(size.width / 2, size.height),
          Offset(size.width / 2, size.height * 0.45),
          [
            _telegraph.withValues(alpha: 0.10 * heat),
            const Color(0x00000000),
          ],
        );
      canvas.drawRect(Offset.zero & size, wash);
    }
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

  /// Downward-scrolling chevrons sell the sense of falling motion.
  static void _drawScrollTexture(
      Canvas canvas, Rect band, double scroll, double a) {
    final rowGap = band.height / _scrollRows;
    if (rowGap <= 2) return;
    final phase = scroll % rowGap;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, band.height * 0.012)
      ..strokeCap = StrokeCap.round
      ..color = _scrollTex.withValues(alpha: _scrollTex.a * a);
    final w = band.width * 0.06;
    for (var r = -1; r <= _scrollRows; r++) {
      final y = band.top + phase + r * rowGap;
      if (y < band.top - rowGap || y > band.bottom + rowGap) continue;
      // A sparse row of small downward chevrons across the width.
      for (var x = band.left + w; x < band.right - w; x += w * 3.4) {
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

    // Outer glow (single soft pass), stronger when a hazard is near.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, band.height * 0.02)
      ..color = color.withValues(alpha: (0.16 + 0.34 * d) * a)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 6 * d);
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
  /// brighter so it reads clearly.
  static void drawLanes(
    Canvas canvas,
    Rect band,
    List<double> laneX,
    double runnerVisualLane,
    bool alive,
  ) {
    final a = alive ? 1.0 : 0.4;
    final top = band.top + band.height * 0.06;
    final bottom = band.bottom - band.height * 0.06;
    for (var i = 0; i < laneX.length; i++) {
      final x = laneX[i];
      final lit = (i - runnerVisualLane).abs() < 0.5;
      final paint = Paint()
        ..strokeWidth = lit ? 2.4 : 1.6
        ..strokeCap = StrokeCap.round
        ..color = (lit ? _laneLineLit : _laneLine)
            .withValues(alpha: (lit ? _laneLineLit.a : _laneLine.a) * a);
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  // ── Telegraph: ground marker in a hazard's target lane ────────────────────

  /// A pulsing ground marker under a hazard's target lane so the player can
  /// react before it lands. [progress] in 0..1 is how close the hazard is to
  /// the runner line (1 = about to hit) and drives the marker's intensity.
  static void drawTelegraph(
    Canvas canvas,
    double laneX,
    double groundY,
    double hazardSize,
    double progress,
  ) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0.02) return;
    final w = hazardSize * (1.0 + 0.4 * p);
    final h = hazardSize * _telegraphMaxH;

    // Soft halo.
    final halo = Paint()
      ..color = _telegraph.withValues(alpha: 0.10 + 0.28 * p)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, hazardSize * 0.22);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(laneX, groundY), width: w, height: h),
      halo,
    );

    // Crisp ring.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, hazardSize * 0.05)
      ..color = _telegraph.withValues(alpha: 0.45 + 0.5 * p);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(laneX, groundY), width: w * 0.78, height: h * 0.78),
      ring,
    );

    // Down-pointing caret stack: more carets as the hazard nears.
    final carets = 1 + (p * 2).round();
    final caret = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, hazardSize * 0.045)
      ..strokeCap = StrokeCap.round
      ..color = _telegraph.withValues(alpha: 0.5 + 0.4 * p);
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
    switch (kind) {
      case HazardKind.boulder:
        _drawBoulder(canvas, center, size, spin);
      case HazardKind.anvil:
        _drawAnvil(canvas, center, size);
      case HazardKind.crate:
        _drawCrate(canvas, center, size, spin);
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
    final shadow = Paint()
      ..color = _black.withValues(alpha: 0.18 + 0.32 * near)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.18);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx, groundY), width: w, height: h),
      shadow,
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

  static void _drawAnvil(Canvas canvas, Offset center, double size) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
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
    canvas.drawOval(
      Rect.fromCenter(
        center: groundCenter,
        width: width * _contactShadowW,
        height: width * _contactShadowH,
      ),
      Paint()
        ..color = _black.withValues(alpha: 0.34)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.18),
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
    // Soft glow underlay.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(2.0, size * 0.5)
        ..color = color.withValues(alpha: 0.18 + 0.22 * p)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.4),
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

    // Soft glow.
    canvas.drawCircle(
      c,
      pip * 2.0,
      Paint()
        ..color = color.withValues(alpha: 0.35 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, pip),
    );
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
