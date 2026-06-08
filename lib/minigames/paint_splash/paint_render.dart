import 'dart:math' as math;
import 'dart:ui';

/// Pure-Canvas rendering for [PaintSplash]. Holds NO game state and never
/// mutates the simulation — callers pass plain value snapshots. Kept in its own
/// file so the gameplay module stays lean and the drawing stays cohesive.
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
///
/// The look is a splatter-paint turf war: a textured studio wall/canvas, an
/// underlying coverage tint baked from the grid, vibrant irregular paint blobs
/// (lumpy outlines + drips + flung droplets) stamped on top, each player's
/// reticle drawn as a spray-can / roller marker in their color, and a live
/// coverage-percent bar stack.
class PaintRenderer {
  PaintRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _wallTop = Color(0xFF20242E);
  static const Color _wallBottom = Color(0xFF0E1016);
  static const Color _canvasTint = Color(0xFFF3ECE0); // primed canvas paper
  static const Color _canvasShade = Color(0xFFD9CFBE);
  static const Color _weave = Color(0x0E000000); // canvas weave threads
  static const Color _vignette = Color(0x55000000);
  static const Color _frame = Color(0xFF3A3326);
  static const Color _frameHi = Color(0xFF6E5F44);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _steel = Color(0xFFB8C0CC);
  static const Color _steelDark = Color(0xFF6C7480);

  // ── Tuning (visual only) ───────────────────────────────────────────────────
  static const double _frameWidthFactor = 0.018; // frame stroke / min side
  static const int _weaveStep = 26; // px spacing of canvas weave lines
  static const int _blobLobes = 11; // outline points of a splat body
  static const double _blobWobble = 0.26; // outline radius variation
  static const double _dripMax = 0.9; // max drip length / blob radius
  static const int _dropletRing = 7; // flung droplets around a fresh splat
  static const double _highlightInset = 0.34; // wet sheen radius / blob radius
  static const double _reticleRingFactor = 0.052; // marker reach / min side
  static const double _barHeightFactor = 0.018; // coverage bar height / height
  static const double _barInsetFactor = 0.03; // bar inset from edges / width

  // ── Background: studio wall + primed canvas + woven texture + frame ─────────

  /// The arena backdrop. Draws a dark studio wall, a primed-canvas panel with a
  /// faint diagonal weave, a soft vignette and a chunky wooden frame so the
  /// playfield reads as a real canvas you are splattering.
  static void drawBackground(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1) return;
    final rect = Offset.zero & size;

    // Studio wall behind the canvas.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height),
          const [_wallTop, _wallBottom],
        ),
    );

    // Primed canvas panel (subtle vertical shade for a lit-from-top feel).
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height),
          const [_canvasTint, _canvasShade],
        ),
    );

    _drawWeave(canvas, size);
    _drawVignette(canvas, size);
    _drawFrame(canvas, size);
  }

  /// Faint diagonal cross-hatch evoking canvas weave threads.
  static void _drawWeave(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1
      ..color = _weave;
    final extent = (size.width + size.height).toInt();
    for (var x = -size.height.toInt(); x < extent; x += _weaveStep) {
      final fx = x.toDouble();
      canvas.drawLine(
          Offset(fx, 0), Offset(fx + size.height, size.height), paint);
      canvas.drawLine(
          Offset(fx + size.height, 0), Offset(fx, size.height), paint);
    }
  }

  /// Soft darkening toward the edges to focus the eye on the action.
  static void _drawVignette(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(size.width, size.height) * 0.72;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          center,
          radius,
          const [Color(0x00000000), _vignette],
          const [0.62, 1.0],
        ),
    );
  }

  /// Chunky wooden frame hugging the canvas edge with a lit inner lip.
  static void _drawFrame(Canvas canvas, Size size) {
    final w =
        math.max(4.0, math.min(size.width, size.height) * _frameWidthFactor);
    final outer = Offset.zero & size;
    canvas.drawRect(
      outer.deflate(w * 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = _frame,
    );
    canvas.drawRect(
      outer.deflate(w * 1.15),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.18)
        ..color = _frameHi.withValues(alpha: 0.5),
    );
  }

  // ── Coverage base tint (baked from the grid) ───────────────────────────────

  /// A soft tinted under-layer painted from the grid ownership: each owned cell
  /// contributes a faint translucent, slightly-overdrawn block of its owner
  /// color. This fills the gaps between the crisp blobs so coverage reads at a
  /// glance without looking like flat tiles. [cellOwnerColor] returns the owner
  /// color for a cell or null when unpainted.
  static void drawCoverageTint(
    Canvas canvas,
    Size size,
    int cols,
    int rows,
    Color? Function(int col, int row) cellOwnerColor,
  ) {
    if (cols < 1 || rows < 1 || size.width <= 1 || size.height <= 1) return;
    final cw = size.width / cols;
    final ch = size.height / rows;
    // Translucent overdrawn cells (no blur) — this loop runs for up to cols×rows
    // cells every frame, so a per-cell MaskFilter.blur was the heaviest cost in
    // the game. Overlapping faint rects still read as soft coverage under the
    // crisp hero blobs drawn on top.
    final overlap = math.max(cw, ch) * 0.5;
    final paint = Paint();
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final color = cellOwnerColor(col, row);
        if (color == null) continue;
        paint.color = color.withValues(alpha: 0.28);
        // Overdraw past the cell edges softens the block boundaries.
        canvas.drawRect(
          Rect.fromLTWH(col * cw - overlap * 0.5, row * ch - overlap * 0.5,
              cw + overlap, ch + overlap),
          paint,
        );
      }
    }
  }

  // ── Paint blobs (the hero visual) ──────────────────────────────────────────

  /// Stamp a single irregular paint splat centered at [center] (pixels) with
  /// pixel [radius] in [color]. [seed] makes the lumpy outline, drips and
  /// droplets deterministic per stamp; [wet] in 0..1 fades a glossy sheen in for
  /// fresh splats and out as they dry. [age01] in 0..1 (0 = freshest) softens
  /// the flung droplet ring for older stamps so only recent splats sparkle.
  static void drawSplat(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    required int seed,
    double wet = 1,
    double age01 = 0,
  }) {
    if (radius <= 0.5 || !center.dx.isFinite || !center.dy.isFinite) return;
    final r = radius;
    final shade = _blend(color, _black, 0.30);
    final tint = _blend(color, _white, 0.30);

    // Soft contact shadow so blobs feel like wet paint sitting on the canvas:
    // two stacked translucent circles (wide+faint, tight+darker) — no per-splat
    // blur.
    canvas.drawCircle(
      center.translate(r * 0.06, r * 0.08),
      r * 1.12,
      Paint()..color = _black.withValues(alpha: 0.07),
    );
    canvas.drawCircle(
      center.translate(r * 0.06, r * 0.08),
      r * 0.96,
      Paint()..color = _black.withValues(alpha: 0.11),
    );

    // Drips first (under the body) so they read as paint running off the blob.
    _drawDrips(canvas, center, r, color, seed);

    // The lumpy body.
    final body = _blobPath(center, r, seed);
    canvas.drawPath(
      body,
      Paint()
        ..shader = Gradient.radial(
          center.translate(-r * 0.28, -r * 0.32),
          r * 1.25,
          [tint, color, shade],
          const [0.0, 0.55, 1.0],
        ),
    );
    // Dark rim for a crisp edge.
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.06)
        ..color = shade.withValues(alpha: 0.8),
    );

    // A couple of inner blobs/eyes for texture variety.
    final blobRng = _Lcg(seed * 2654435761 + 3);
    final spots = 2 + (blobRng.next() * 2).floor();
    final spotPaint = Paint()..color = shade.withValues(alpha: 0.35);
    for (var i = 0; i < spots; i++) {
      final a = blobRng.next() * math.pi * 2;
      final d = r * (0.15 + blobRng.next() * 0.4);
      final sr = r * (0.08 + blobRng.next() * 0.12);
      canvas.drawCircle(
        center + Offset(math.cos(a) * d, math.sin(a) * d),
        sr,
        spotPaint,
      );
    }

    // Wet glossy sheen highlight (fades as the splat dries).
    final w = wet.clamp(0.0, 1.0);
    if (w > 0.02) {
      // Two stacked translucent white blots (wide+faint, tight+stronger) plus a
      // crisp glint fake the wet sheen without a per-splat blur.
      canvas.drawCircle(
        center.translate(-r * 0.26, -r * 0.30),
        r * (_highlightInset + 0.12),
        Paint()..color = _white.withValues(alpha: 0.2 * w),
      );
      canvas.drawCircle(
        center.translate(-r * 0.26, -r * 0.30),
        r * _highlightInset,
        Paint()..color = _white.withValues(alpha: 0.34 * w),
      );
      canvas.drawCircle(
        center.translate(-r * 0.30, -r * 0.34),
        r * 0.10,
        Paint()..color = _white.withValues(alpha: 0.7 * w),
      );
    }

    // Flung droplet ring (strong on fresh splats, faint on old ones).
    final freshness = (1.0 - age01).clamp(0.0, 1.0);
    if (freshness > 0.05) {
      _drawDroplets(canvas, center, r, color, seed, freshness);
    }
  }

  /// Build a closed lumpy outline for a splat body using smooth quadratics.
  static Path _blobPath(Offset center, double r, int seed) {
    final rng = _Lcg(seed * 40503 + 17);
    final radii = <double>[];
    for (var i = 0; i < _blobLobes; i++) {
      // Occasional spikier lobe makes the silhouette read as splattered.
      final spike = rng.next() < 0.25 ? rng.next() * 0.5 : 0.0;
      radii.add(
          r * (1.0 - _blobWobble * 0.5 + rng.next() * _blobWobble + spike));
    }
    Offset pt(int i) {
      final ang = (i / _blobLobes) * math.pi * 2;
      final rr = radii[i % _blobLobes];
      return center + Offset(math.cos(ang) * rr, math.sin(ang) * rr);
    }

    final path = Path();
    // Start at the midpoint between the last and first lobe for a smooth loop.
    final start = Offset.lerp(pt(_blobLobes - 1), pt(0), 0.5)!;
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < _blobLobes; i++) {
      final curr = pt(i);
      final nextMid = Offset.lerp(curr, pt(i + 1), 0.5)!;
      path.quadraticBezierTo(curr.dx, curr.dy, nextMid.dx, nextMid.dy);
    }
    path.close();
    return path;
  }

  /// A few teardrop drips running downward off the blob (gravity feel).
  static void _drawDrips(
    Canvas canvas,
    Offset center,
    double r,
    Color color,
    int seed,
  ) {
    final rng = _Lcg(seed * 22695477 + 1);
    final count = 1 + rng.next().round() + (rng.next() < 0.4 ? 1 : 0);
    final paint = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final spread = (rng.next() - 0.5) * 1.4; // around straight-down
      final ang = math.pi / 2 + spread;
      final len = r * (0.3 + rng.next() * _dripMax);
      final wTop = r * (0.16 + rng.next() * 0.12);
      final start =
          center + Offset(math.cos(ang) * r * 0.7, math.sin(ang) * r * 0.7);
      final end = start + Offset(math.cos(ang) * len, math.sin(ang) * len);
      // Tapered teardrop: a quad on each side meeting at a rounded tip bulb.
      final perp = Offset(-math.sin(ang), math.cos(ang));
      final path = Path()
        ..moveTo(start.dx + perp.dx * wTop, start.dy + perp.dy * wTop)
        ..quadraticBezierTo(
          end.dx + perp.dx * wTop * 0.3,
          end.dy + perp.dy * wTop * 0.3,
          end.dx,
          end.dy,
        )
        ..quadraticBezierTo(
          end.dx - perp.dx * wTop * 0.3,
          end.dy - perp.dy * wTop * 0.3,
          start.dx - perp.dx * wTop,
          start.dy - perp.dy * wTop,
        )
        ..close();
      canvas.drawPath(path, paint);
      // Drip tip bulb.
      canvas.drawCircle(end, wTop * 0.55, paint);
    }
  }

  /// Small flung droplets ringing a splat — the satisfying "splat!" scatter.
  static void _drawDroplets(
    Canvas canvas,
    Offset center,
    double r,
    Color color,
    int seed,
    double freshness,
  ) {
    final rng = _Lcg(seed * 19349663 + 7);
    final paint = Paint()..color = color.withValues(alpha: 0.92 * freshness);
    for (var i = 0; i < _dropletRing; i++) {
      final a = (i / _dropletRing) * math.pi * 2 + rng.next() * 0.8;
      final d = r * (1.05 + rng.next() * 0.7);
      final dr = r * (0.05 + rng.next() * 0.13);
      final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
      canvas.drawCircle(p, dr, paint);
    }
  }

  // ── Reticle marker: spray-can / roller in the player's color ───────────────

  /// Draw a player's steering brush marker. [charge] in 0..1 (the dwell bonus —
  /// how big the next splat will be) grows a target ring so a "loaded" lingering
  /// brush reads clearly. [isRoller] swaps the spray-can silhouette for a
  /// roller, so up to four players are instantly distinguishable by tool +
  /// color. [pulse] in 0..1 animates a recent-splat flash. [spraying] true draws
  /// an active paint burst at the nozzle so a held brush visibly lays paint.
  static void drawReticle(
    Canvas canvas,
    Size size,
    Offset center,
    Color color, {
    required double charge,
    required bool isRoller,
    double pulse = 0,
    bool spraying = false,
  }) {
    if (!center.dx.isFinite || !center.dy.isFinite) return;
    final unit = math.min(size.width, size.height) * _reticleRingFactor;
    if (unit <= 0) return;
    final c = charge.clamp(0.0, 1.0);

    _drawTargetRing(canvas, center, unit, color, c, pulse.clamp(0.0, 1.0));
    if (spraying) _drawSprayBurst(canvas, center, unit, color, c);
    if (isRoller) {
      _drawRoller(canvas, center, unit, color);
    } else {
      _drawSprayCan(canvas, center, unit, color);
    }
  }

  /// A soft puff of colored mist at the brush centre while it is actively
  /// spraying, so a held/steering brush clearly reads as laying down paint.
  static void _drawSprayBurst(
      Canvas canvas, Offset center, double unit, Color color, double charge) {
    final r = unit * (1.1 + 0.8 * charge);
    // Two stacked translucent puffs (wide+faint, tight+stronger) read as colored
    // mist without a per-cursor blur.
    canvas.drawCircle(
        center, r, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawCircle(
        center, r * 0.7, Paint()..color = color.withValues(alpha: 0.24));
    canvas.drawCircle(
      center,
      r * 0.5,
      Paint()..color = color.withValues(alpha: 0.5),
    );
  }

  /// Pulsing target ring sized to the pending splat radius.
  static void _drawTargetRing(Canvas canvas, Offset center, double unit,
      Color color, double charge, double pulse) {
    final ringR = unit * (1.6 + 1.4 * charge) + unit * 0.5 * pulse;
    // Soft halo: a wide, faint stroke (no blur) under the crisp dashed ring.
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.8
        ..color = color.withValues(alpha: 0.12 + 0.14 * pulse),
    );
    // Dashed-look ring via short arcs.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, unit * 0.18)
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.85);
    final rect = Rect.fromCircle(center: center, radius: ringR);
    const segs = 8;
    for (var i = 0; i < segs; i++) {
      final a0 = (i / segs) * math.pi * 2;
      canvas.drawArc(rect, a0, math.pi * 2 / segs * 0.55, false, ringPaint);
    }
    // Crosshair ticks.
    final tick = Paint()
      ..strokeWidth = math.max(1.0, unit * 0.12)
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.7);
    for (final d in const [
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1)
    ]) {
      canvas.drawLine(
        center + Offset(d.dx, d.dy) * ringR * 0.78,
        center + Offset(d.dx, d.dy) * ringR * 1.05,
        tick,
      );
    }
  }

  /// A small spray-can icon: body, nozzle, color band and a puff of mist.
  static void _drawSprayCan(
      Canvas canvas, Offset center, double unit, Color color) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final bodyW = unit * 0.9;
    final bodyH = unit * 1.7;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(0, unit * 0.2), width: bodyW, height: bodyH),
      Radius.circular(unit * 0.22),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = Gradient.linear(
          Offset(-bodyW / 2, 0),
          Offset(bodyW / 2, 0),
          const [_steel, _steelDark],
        ),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, unit * 0.1)
        ..color = _black.withValues(alpha: 0.4),
    );
    // Color band shows which player owns this can.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(0, unit * 0.2), width: bodyW, height: unit * 0.5),
        Radius.circular(unit * 0.1),
      ),
      Paint()..color = color,
    );
    // Nozzle + cap.
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(0, -unit * 0.75),
          width: bodyW * 0.5,
          height: unit * 0.4),
      Paint()..color = _steelDark,
    );
    canvas.drawCircle(
        Offset(0, -unit * 1.0), unit * 0.18, Paint()..color = color);
    // Mist puff toward the target above the can.
    final mist = Paint()..color = color.withValues(alpha: 0.5);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
          Offset((i - 1) * unit * 0.18, -unit * 1.35), unit * 0.1, mist);
    }
    canvas.restore();
  }

  /// A small paint-roller icon: handle, frame and a color-loaded sleeve.
  static void _drawRoller(
      Canvas canvas, Offset center, double unit, Color color) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    // Sleeve (the rolling part) loaded with the player color.
    final sleeve = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(0, -unit * 0.6), width: unit * 1.8, height: unit * 0.7),
      Radius.circular(unit * 0.35),
    );
    canvas.drawRRect(sleeve, Paint()..color = color);
    canvas.drawRRect(
      sleeve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, unit * 0.08)
        ..color = _blend(color, _black, 0.4),
    );
    // Sleeve sheen.
    canvas.drawLine(
      Offset(-unit * 0.7, -unit * 0.75),
      Offset(unit * 0.7, -unit * 0.75),
      Paint()
        ..strokeWidth = math.max(0.8, unit * 0.1)
        ..strokeCap = StrokeCap.round
        ..color = _white.withValues(alpha: 0.4),
    );
    // Metal frame from sleeve down to the handle.
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, unit * 0.12)
      ..strokeCap = StrokeCap.round
      ..color = _steel;
    canvas.drawLine(Offset(0, -unit * 0.25), Offset(0, unit * 0.2), wire);
    canvas.drawLine(Offset(0, unit * 0.2), Offset(unit * 0.2, unit * 0.2), wire);
    // Handle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(0, unit * 0.85), width: unit * 0.4, height: unit),
        Radius.circular(unit * 0.18),
      ),
      Paint()..color = _steelDark,
    );
    canvas.restore();
  }

  // ── Zone borders (whose canvas is whose) ───────────────────────────────────

  /// Faint player-tinted borders around each player's paintable zone so the
  /// split of the canvas reads instantly. [zones] pairs each normalized rect
  /// with that player's color. A single full-screen zone (solo play) is skipped
  /// since there is nothing to divide.
  static void drawZoneBorders(
    Canvas canvas,
    Size size,
    List<({Rect rect, Color color})> zones,
  ) {
    if (size.width <= 1 || size.height <= 1 || zones.length < 2) return;
    for (final z in zones) {
      final r = Rect.fromLTRB(
        z.rect.left * size.width,
        z.rect.top * size.height,
        z.rect.right * size.width,
        z.rect.bottom * size.height,
      ).deflate(2);
      // Soft tinted halo just inside the seam: a wide, faint stroke (no blur)
      // under the crisp thin border below.
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(3.0, math.min(size.width, size.height) * 0.018)
          ..color = z.color.withValues(alpha: 0.1),
      );
      // Crisp thin border.
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, math.min(size.width, size.height) * 0.003)
          ..color = z.color.withValues(alpha: 0.5),
      );
    }
  }

  // ── Coverage bars (live HUD) ───────────────────────────────────────────────

  /// A live stacked bar showing each player's coverage fraction. [entries] is a
  /// list of (color, fraction0to1, isLeader) ordered as the players appear. The
  /// leader's bar gets a bright glow. Drawn at the top inside the frame.
  static void drawCoverageBars(
    Canvas canvas,
    Size size,
    List<({Color color, double fraction, bool isLeader})> entries,
  ) {
    if (entries.isEmpty || size.width <= 1 || size.height <= 1) return;
    final inset = size.width * _barInsetFactor;
    final barH = math.max(6.0, size.height * _barHeightFactor);
    final gap = barH * 0.55;
    final fullW = size.width - inset * 2;
    var y = inset + size.height * 0.012;

    for (final e in entries) {
      final frac = e.fraction.clamp(0.0, 1.0);
      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, y, fullW, barH),
        Radius.circular(barH * 0.5),
      );
      // Track.
      canvas.drawRRect(track, Paint()..color = _black.withValues(alpha: 0.32));
      // Fill.
      final fillW = math.max(barH, fullW * frac);
      final fill = RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, y, fillW, barH),
        Radius.circular(barH * 0.5),
      );
      if (e.isLeader) {
        // A slightly inflated translucent fill under the solid bar fakes the
        // leader glow without a blur.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(inset, y, fillW, barH).inflate(barH * 0.28),
            Radius.circular(barH),
          ),
          Paint()..color = e.color.withValues(alpha: 0.28),
        );
      }
      canvas.drawRRect(fill, Paint()..color = e.color);
      // Top sheen on the fill.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, y, fillW, barH * 0.42),
          Radius.circular(barH * 0.4),
        ),
        Paint()..color = _white.withValues(alpha: 0.22),
      );
      // Percent label at the bar end.
      final pct = (frac * 100).round();
      _drawLabel(
        canvas,
        '$pct%',
        Offset(inset + fillW + barH * 0.4, y + barH * 0.5),
        barH * 0.95,
        e.color,
      );
      y += barH + gap;
    }
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  static void _drawLabel(
    Canvas canvas,
    String text,
    Offset anchor,
    double fontSize,
    Color color,
  ) {
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
    ))
      ..pushStyle(TextStyle(
        color: color,
        shadows: const [
          Shadow(color: _black, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: fontSize * 6));
    canvas.drawParagraph(
      paragraph,
      Offset(anchor.dx, anchor.dy - fontSize * 0.62),
    );
  }
}

/// Tiny deterministic linear-congruential generator for stable per-stamp
/// visual variation (lumps, drips, droplets) without touching the sim RNG.
/// Pure value type; never throws.
class _Lcg {
  int _state;
  _Lcg(int seed) : _state = (seed & 0x7fffffff) | 1;

  /// Next double in [0, 1).
  double next() {
    // Numerical Recipes LCG constants, masked to 31 bits.
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }
}
