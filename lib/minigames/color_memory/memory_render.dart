import 'dart:math' as math;
import 'dart:ui';

/// Pure-Canvas rendering for `ColorMemory` — a glowing arcade Simon stage.
///
/// Holds NO game state and never mutates the simulation: callers pass plain
/// value snapshots (rects, 0..1 strengths, booleans). Kept in its own file so
/// the gameplay module stays lean and the drawing stays cohesive (mirrors the
/// sumo_smash / reaction_duel split).
///
/// Every method is side-effect free beyond the supplied [Canvas], guards its
/// own inputs, and never throws (so it is safe to call from `render`).
class MemoryRenderer {
  MemoryRenderer._();

  // ── Palette (no magic colors inline elsewhere) ─────────────────────────────
  static const Color _bgTop = Color(0xFF161226); // deep arcade violet
  static const Color _bgMid = Color(0xFF0E1C33); // mid console blue
  static const Color _bgBottom = Color(0xFF05070E); // near-black floor
  static const Color _vignette = Color(0xCC04060C);
  static const Color _gridLine = Color(0x14A9C7FF);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _black = Color(0xFF000000);
  static const Color _consoleFill = Color(0xFF0B1120);
  static const Color _consoleEdge = Color(0x3389B4FF);
  static const Color _watchBanner = Color(0xFF6FA8FF); // calm "WATCH" blue
  static const Color _turnBanner = Color(0xFF54E08A); // active "YOUR TURN" green
  static const Color _pipDim = Color(0x33FFFFFF);

  /// The four Simon pad colors. Index 0..3 maps to a pad slot. Exposed so the
  /// game module references one source of truth for both logic and drawing.
  static const List<Color> palette = <Color>[
    Color(0xFFE5484D), // red
    Color(0xFF3E8BFF), // blue
    Color(0xFF46C46A), // green
    Color(0xFFF2C037), // yellow
  ];

  // ── Tuning (fractions / factors; no inline magic numbers) ──────────────────
  static const double _vignInnerFrac = 0.40;
  static const double _vignOuterFrac = 0.82;
  static const int _gridCols = 7;
  static const int _gridRows = 11;
  static const double _padGapFactor = 0.06; // gap between quadrants / half
  static const double _padCornerFactor = 0.16; // pad corner radius / half
  static const double _clusterCornerFactor = 0.10; // cluster plate corner / side
  static const double _clusterPadFactor = 0.10; // inset of pads inside plate
  static const double _baseAlpha = 0.34; // resting pad fill alpha
  static const double _hubGapFactor = 0.30; // hub hole / half (cluster center)
  static const double _seqDiscFactor = 0.085; // center disc radius / minSide
  static const double _pipRadiusFactor = 0.010; // progress pip radius / blockW
  static const double _bannerFontFrac = 0.052; // phase banner font / width
  static const double _roundFontFrac = 0.030; // round counter font / width

  // ── Background: console gradient + faint grid + vignette ────────────────────
  static void drawBackground(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = Gradient.linear(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        const [_bgTop, _bgMid, _bgBottom],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawRect(Offset.zero & size, bg);

    final line = Paint()
      ..color = _gridLine
      ..strokeWidth = 1.0;
    for (var c = 1; c < _gridCols; c++) {
      final x = size.width * (c / _gridCols);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var r = 1; r < _gridRows; r++) {
      final y = size.height * (r / _gridRows);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  /// Crowd-dark vignette so the pads pop (drawn over the grid, under the pads).
  static void drawVignette(Canvas canvas, Size size) {
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final outer = diag * _vignOuterFrac;
    final inner = diag * _vignInnerFrac;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = Gradient.radial(
          Offset(size.width / 2, size.height * 0.5),
          outer,
          const [Color(0x00000000), _vignette],
          [(inner / outer).clamp(0.0, 0.99), 1.0],
        ),
    );
  }

  /// A player's Simon cluster: a dark rounded console plate carrying four
  /// glowing colored quadrants the player TAPS directly. [blooms] holds a 0..1
  /// brightness per slot (red, blue, green, yellow) so flashing-in-sequence and
  /// just-tapped pads bloom brightly with an afterglow halo. [alive] dims a whole
  /// cluster on death. [turnPulse] (0..1) gently breathes a "your turn — tap the
  /// colors" rim during the input phase (no per-pad cursor); [oops] (0..1)
  /// flashes the plate when a forgiven wrong tap happened.
  static void drawCluster(
    Canvas canvas,
    Rect block, {
    required List<double> blooms,
    required bool alive,
    required bool done,
    required Color accent,
    double turnPulse = 0,
    double oops = 0,
    bool appendInvite = false,
  }) {
    if (block.width <= 2) return;
    final side = math.min(block.width, block.height);
    final plate =
        Rect.fromCenter(center: block.center, width: side, height: side);
    _drawPlate(canvas, plate, accent, alive: alive, done: done);

    final half = side / 2;
    final gap = half * _padGapFactor;
    final inset = side * _clusterPadFactor;
    final quadW = half - inset - gap;

    for (var slot = 0; slot < palette.length; slot++) {
      final left = plate.left + inset + (slot % 2) * (half - inset + gap);
      final top = plate.top + inset + (slot ~/ 2) * (half - inset + gap);
      final cell = Rect.fromLTWH(left, top, quadW, quadW);
      final bloom = slot < blooms.length ? blooms[slot].clamp(0.0, 1.0) : 0.0;
      _drawPad(canvas, cell, palette[slot], bloom: bloom, alive: alive);
    }

    // Center hub hole punched through the cluster for the classic Simon look.
    canvas.drawCircle(
      plate.center,
      half * _hubGapFactor,
      Paint()..color = _black.withValues(alpha: alive ? 0.85 : 0.5),
    );
    canvas.drawCircle(
      plate.center,
      half * _hubGapFactor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, half * 0.02)
        ..color = accent.withValues(alpha: alive ? 0.6 : 0.2),
    );

    // "Your turn" rim: a soft pulsing accent frame around the whole plate so the
    // child knows it is time to tap the colors (replaces the old cursor ring).
    // [appendInvite] forces it on for the round winner during the append beat
    // (they are `done`, but should still be invited to tap a color), drawn a
    // touch brighter/thicker so "pick a color to add" reads as the active call.
    final tp = turnPulse.clamp(0.0, 1.0);
    if (alive && (appendInvite || !done) && tp > 0.0) {
      final rr = RRect.fromRectAndRadius(
          plate, Radius.circular(plate.width * _clusterCornerFactor));
      final widen = appendInvite ? 0.03 : 0.02;
      final baseA = appendInvite ? 0.45 : 0.30;
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, plate.width * (0.02 + widen * tp))
          ..color = _blend(accent, _white, appendInvite ? 0.6 : 0.4)
              .withValues(alpha: (baseA + 0.4 * tp).clamp(0.0, 1.0)),
      );
    }

    // Forgiven-miss flash: a soft yellow plate wash + rim so a kid sees "oops,
    // try again" without it reading as elimination.
    final op = oops.clamp(0.0, 1.0);
    if (alive && op > 0.02) {
      final rr = RRect.fromRectAndRadius(
          plate, Radius.circular(plate.width * _clusterCornerFactor));
      canvas.drawRRect(
        rr,
        Paint()..color = palette[3].withValues(alpha: 0.18 * op),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, plate.width * 0.04)
          ..color = palette[3].withValues(alpha: 0.7 * op),
      );
    }
  }

  static void _drawPlate(
    Canvas canvas,
    Rect plate,
    Color accent, {
    required bool alive,
    required bool done,
  }) {
    final rr = RRect.fromRectAndRadius(
        plate, Radius.circular(plate.width * _clusterCornerFactor));
    // Drop shadow for depth: a plain offset fill (no per-frame blur).
    canvas.drawRRect(
      rr.shift(Offset(0, plate.width * 0.035)),
      Paint()..color = _black.withValues(alpha: 0.35),
    );
    canvas.drawRRect(
      rr,
      Paint()..color = _consoleFill.withValues(alpha: alive ? 1.0 : 0.6),
    );
    // Accent edge — brightens to a victory glow once the player has cleared
    // the round (done), reads as a calm rim otherwise.
    final edgeColor = done
        ? _blend(accent, _white, 0.4)
        : (alive ? _consoleEdge : const Color(0x22557799));
    if (done && alive) {
      // Wide faint solid stroke as a cheap victory bloom (no per-frame blur).
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(4.0, plate.width * 0.07)
          ..color = accent.withValues(alpha: 0.28),
      );
    }
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, plate.width * 0.012)
        ..color = edgeColor,
    );
  }

  static void _drawPad(
    Canvas canvas,
    Rect cell,
    Color color, {
    required double bloom,
    required bool alive,
  }) {
    final radius = Radius.circular(cell.width * _padCornerFactor);
    final rr = RRect.fromRectAndRadius(cell, radius);
    final baseA = alive ? _baseAlpha : 0.10;
    final fillA = (baseA + (1.0 - baseA) * bloom).clamp(0.0, 1.0);

    // Soft outer bloom halo when lit: two stacked translucent inflated plates
    // (wider+fainter, then tighter+brighter) fake a glow without a per-pad blur.
    if (bloom > 0.02 && alive) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell.inflate(cell.width * 0.16), radius),
        Paint()..color = color.withValues(alpha: 0.16 * bloom),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell.inflate(cell.width * 0.07), radius),
        Paint()..color = color.withValues(alpha: 0.28 * bloom),
      );
    }

    // Pad body with a top-down gradient so it reads as a glossy button.
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = Gradient.linear(
          cell.topCenter,
          cell.bottomCenter,
          [
            _blend(color, _white, 0.18 + 0.4 * bloom).withValues(alpha: fillA),
            _blend(color, _black, 0.18).withValues(alpha: fillA),
          ],
        ),
    );

    // Glossy top sheen.
    final sheen = Rect.fromLTWH(
        cell.left + cell.width * 0.12,
        cell.top + cell.height * 0.10,
        cell.width * 0.76,
        cell.height * 0.30);
    canvas.drawRRect(
      RRect.fromRectAndRadius(sheen, Radius.circular(sheen.height * 0.5)),
      Paint()
        ..color = _white.withValues(
            alpha: (0.12 + 0.5 * bloom).clamp(0.0, 1.0) * (alive ? 1.0 : 0.3)),
    );

    // Crisp rim that lights up with the bloom.
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, cell.width * 0.04)
        ..color = _blend(color, _white, 0.5)
            .withValues(alpha: (0.25 + 0.7 * bloom).clamp(0.0, 1.0)),
    );
  }

  /// Per-player progress pips beneath a cluster: one per sequence color, filled
  /// in the player's [accent] for entries already reproduced this round.
  static void drawProgress(
    Canvas canvas,
    Rect block,
    int sequenceLength,
    int progress,
    Color accent, {
    required bool alive,
  }) {
    if (sequenceLength <= 0 || block.width <= 2) return;
    final side = math.min(block.width, block.height);
    final r = math.max(2.0, block.width * _pipRadiusFactor);
    final y = block.center.dy + side / 2 + r * 2.4;
    final span = side * 0.92;
    final startX = block.center.dx - span / 2;
    final fill = Paint()..color = accent.withValues(alpha: alive ? 1.0 : 0.3);
    final dim = Paint()..color = _pipDim;
    for (var i = 0; i < sequenceLength; i++) {
      final x = sequenceLength == 1
          ? block.center.dx
          : startX + span * (i / (sequenceLength - 1));
      final done = i < progress;
      if (done && alive) {
        // Wide faint solid disc under the bright pip fakes the glow cheaply.
        canvas.drawCircle(Offset(x, y), r * 2.4,
            Paint()..color = accent.withValues(alpha: 0.18));
        canvas.drawCircle(Offset(x, y), r * 1.5, fill);
      } else {
        canvas.drawCircle(Offset(x, y), r, done ? fill : dim);
      }
    }
  }

  /// A small numbered tab over a cluster so each player reads at a glance.
  static void drawPlayerTab(
    Canvas canvas,
    Rect block,
    Color accent,
    int displayNumber, {
    required bool alive,
  }) {
    final side = math.min(block.width, block.height);
    final r = math.max(8.0, side * 0.075);
    final c = Offset(block.center.dx, block.center.dy - side / 2 - r * 1.2);
    canvas.drawCircle(
        c, r, Paint()..color = accent.withValues(alpha: alive ? 1.0 : 0.3));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.16)
        ..color = _white.withValues(alpha: alive ? 0.85 : 0.3),
    );
    _drawText(canvas, '$displayNumber', c, r * 1.25, _readableText(accent),
        weight: FontWeight.w900);
  }

  /// An "X" stamp + soft dark wash over an eliminated cluster.
  static void drawEliminated(Canvas canvas, Rect block, double strength) {
    final s = strength.clamp(0.0, 1.0);
    if (s <= 0.02) return;
    final side = math.min(block.width, block.height);
    final plate =
        Rect.fromCenter(center: block.center, width: side, height: side);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          plate, Radius.circular(side * _clusterCornerFactor)),
      Paint()..color = _black.withValues(alpha: 0.42 * s),
    );
    final half = side * 0.26;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(3.0, side * 0.05)
      ..color = palette[0].withValues(alpha: 0.9 * s);
    final c = plate.center;
    canvas.drawLine(c.translate(-half, -half), c.translate(half, half), paint);
    canvas.drawLine(c.translate(half, -half), c.translate(-half, half), paint);
  }

  /// The big central state cue: a calm blue "WATCH" while the sequence flashes,
  /// a bright green "YOUR TURN" while players reproduce. [pulse] 0..1 throbs it.
  static void drawPhaseBanner(
    Canvas canvas,
    Size size, {
    required bool watching,
    required double pulse,
    double topFrac = 0.06,
  }) {
    final p = pulse.clamp(0.0, 1.0);
    final color = watching ? _watchBanner : _turnBanner;
    final text = watching ? 'WATCH' : 'YOUR TURN';
    final center = Offset(size.width / 2, size.height * topFrac);
    final font = size.width * _bannerFontFrac * (0.96 + 0.06 * p);
    // Soft badge behind the word.
    canvas.drawCircle(
      center,
      font * 1.7,
      Paint()
        ..shader = Gradient.radial(
          center,
          font * 1.7,
          [color.withValues(alpha: 0.22 + 0.12 * p), const Color(0x00000000)],
        ),
    );
    _drawText(canvas, text, center, font, color.withValues(alpha: 0.95),
        weight: FontWeight.w900, glow: true, glowColor: color);
  }

  /// The call-and-response cue: during the append beat, announce that the round
  /// winner ([appenderNumber], 1-based) is adding a color for the table. Drawn
  /// in the winner's [accent] in the same badge style as [drawPhaseBanner] so it
  /// reads from across the room. [pulse] 0..1 throbs it.
  static void drawAppendBanner(
    Canvas canvas,
    Size size, {
    required int appenderNumber,
    required Color accent,
    required double pulse,
    double topFrac = 0.06,
  }) {
    final p = pulse.clamp(0.0, 1.0);
    final color = _blend(accent, _white, 0.25);
    final text = 'P$appenderNumber ADDS A COLOR';
    final center = Offset(size.width / 2, size.height * topFrac);
    final font = size.width * _bannerFontFrac * (0.78 + 0.06 * p);
    canvas.drawCircle(
      center,
      font * 2.4,
      Paint()
        ..shader = Gradient.radial(
          center,
          font * 2.4,
          [color.withValues(alpha: 0.22 + 0.12 * p), const Color(0x00000000)],
        ),
    );
    _drawText(canvas, text, center, font, color.withValues(alpha: 0.95),
        weight: FontWeight.w900, glow: true, glowColor: color);
  }

  /// The shared sequence shown as a row of pips near the top: lit in the
  /// flashing color while WATCHING (up to [shownCount]); calm dots otherwise so
  /// players can gauge how long the pattern is.
  static void drawSharedSequence(
    Canvas canvas,
    Size size,
    List<int> sequence, {
    required int shownCount,
    required bool watching,
    double topFrac = 0.135,
  }) {
    if (sequence.isEmpty) return;
    final r = math.max(3.0, size.width * 0.011);
    final gap = r * 3.0;
    // The sequence cap keeps this within one comfortable row.
    final totalW = gap * (sequence.length - 1);
    final startX = size.width / 2 - totalW / 2;
    final y = size.height * topFrac;
    for (var i = 0; i < sequence.length; i++) {
      final x = sequence.length == 1 ? size.width / 2 : startX + gap * i;
      final color = palette[sequence[i].clamp(0, palette.length - 1)];
      final lit = watching && i < shownCount;
      if (lit) {
        // Wide faint solid disc under the bright dot fakes the glow cheaply.
        canvas.drawCircle(Offset(x, y), r * 3.0,
            Paint()..color = color.withValues(alpha: 0.18));
        canvas.drawCircle(Offset(x, y), r * 1.5, Paint()..color = color);
      } else {
        canvas.drawCircle(
          Offset(x, y),
          r,
          Paint()..color = color.withValues(alpha: watching ? 0.28 : 0.5),
        );
      }
    }
  }

  /// The central "now flashing" disc shown during WATCH — a big glowing orb in
  /// the active color so the light show reads even from across the room.
  /// [color] null hides it (between flashes / during input).
  static void drawFlashCore(
    Canvas canvas,
    Size size,
    Color? color,
    double strength,
  ) {
    final s = strength.clamp(0.0, 1.0);
    if (color == null || s <= 0.02) return;
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * _seqDiscFactor;
    // Wide soft halo.
    canvas.drawCircle(
      center,
      r * 3.0 * (0.7 + 0.3 * s),
      Paint()
        ..shader = Gradient.radial(
          center,
          r * 3.0 * (0.7 + 0.3 * s),
          [color.withValues(alpha: 0.5 * s), const Color(0x00000000)],
        ),
    );
    // Bright core.
    canvas.drawCircle(
      center,
      r * (0.8 + 0.25 * s),
      Paint()
        ..shader = Gradient.radial(
          center.translate(0, -r * 0.2),
          r * (0.8 + 0.25 * s),
          [_blend(color, _white, 0.5), color],
        ),
    );
    canvas.drawCircle(
      center,
      r * (0.8 + 0.25 * s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, r * 0.08)
        ..color = _white.withValues(alpha: 0.6 * s),
    );
  }

  /// Round counter line in the title zone.
  static void drawRoundCounter(Canvas canvas, Size size, int round) {
    final font = size.width * _roundFontFrac;
    final center = Offset(size.width / 2, size.height * 0.195);
    _drawText(canvas, 'ROUND $round', center, font,
        _white.withValues(alpha: 0.7),
        weight: FontWeight.w700);
  }

  // ── Small private helpers ──────────────────────────────────────────────────

  static Color _blend(Color a, Color b, double t) =>
      Color.lerp(a, b, t.clamp(0.0, 1.0)) ?? a;

  /// Pick black or white text for legibility against [bg].
  static Color _readableText(Color bg) {
    final luma = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luma > 0.6 ? _black : _white;
  }

  /// Centered text with an optional cheap glow halo (offset copies). Never
  /// throws; degenerate sizes are ignored.
  static void _drawText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color, {
    FontWeight weight = FontWeight.w800,
    bool glow = false,
    Color? glowColor,
  }) {
    if (fontSize <= 0 || text.isEmpty) return;
    final width = fontSize * (text.length + 2);
    if (glow) {
      final gb = ParagraphBuilder(ParagraphStyle(
        textAlign: TextAlign.center,
        fontSize: fontSize,
        fontWeight: weight,
      ))
        ..pushStyle(
            TextStyle(color: (glowColor ?? color).withValues(alpha: 0.5)))
        ..addText(text);
      final gp = gb.build()..layout(ParagraphConstraints(width: width));
      for (final o in const [
        Offset(0, 2.5),
        Offset(2.5, 0),
        Offset(-2.5, 0),
        Offset(0, -2.5),
      ]) {
        canvas.drawParagraph(gp,
            Offset(center.dx - width / 2 + o.dx, center.dy - fontSize + o.dy));
      }
    }
    final builder = ParagraphBuilder(ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
      fontWeight: weight,
    ))
      ..pushStyle(TextStyle(color: color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: width));
    canvas.drawParagraph(
        paragraph, Offset(center.dx - width / 2, center.dy - fontSize));
  }
}
