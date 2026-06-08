/// Wordless, kid-friendly per-player START CUE shown during the countdown.
///
/// For each player zone it paints — rotated to face the seated player — a big
/// pulsing tap target in the player's color, an action glyph + one short word
/// derived from the game's `inputHint`, and the player's name. It also tints
/// each zone faintly with the player's color for the first moment of the
/// countdown (an identity flash) so a child instantly finds their character.
///
/// Pure presentation: it reads the live countdown and repaints off the runner's
/// existing `hudTick` notifier. No BackdropFilter / MaskFilter.blur — everything
/// is drawn with cheap, allocation-light Canvas calls.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/input_zones.dart';
import '../../engine/player_manager.dart';

/// The four cue archetypes a player can be shown. Each maps to a glyph the
/// painter knows how to draw and a single uppercase word a pre-reader learns by
/// shape, not by reading.
enum CueKind {
  /// Single tap — expanding ripple. Word: "TAP!".
  tap,

  /// Press and hold — a ring that fills. Word: "HOLD".
  hold,

  /// Rapid repeated taps — a burst of small ripples. Word: "MASH!".
  mash,

  /// Move / drag — a joystick nub with four arrows. Word: "DRAG".
  drag,
}

/// Tuning for the start cue (kept here so the painter has no magic numbers).
class StartCueTune {
  StartCueTune._();

  /// Seconds the per-zone color identity flash stays before fully fading.
  static const double identityFlashSec = 0.6;

  /// Peak opacity of the identity flash tint.
  static const double identityFlashAlpha = 0.22;

  /// One full pulse of the tap target, in seconds.
  static const double pulsePeriodSec = 0.9;

  /// Tap-target radius as a fraction of the zone's shorter side.
  static const double targetRadiusFactor = 0.16;

  /// Largest the tap target is allowed to get, in logical px (small zones).
  static const double targetRadiusMax = 84;

  /// Opacity applied to a bot's whole cue (dimmer than a human's).
  static const double botDim = 0.4;

  /// Gap between the tap target and the word below it, in px.
  static const double wordGap = 14;

  /// Word font size, in px.
  static const double wordSize = 22;

  /// Player-name font size, in px (sits above the target).
  static const double nameSize = 26;
}

/// Maps a game's `inputHint` string to a [CueKind]. Unknown / empty hints fall
/// back to [CueKind.tap] (the simplest, safest "just touch" cue).
CueKind cueKindFor(String inputHint) {
  final String h = inputHint.trim().toUpperCase();
  if (h.contains('MASH')) return CueKind.mash;
  if (h.contains('HOLD')) return CueKind.hold; // covers "TAP / HOLD" too
  if (h.contains('MOVE') || h.contains('DRAG')) return CueKind.drag;
  return CueKind.tap; // "TAP" and anything unrecognised
}

/// The single short word shown under the glyph for a [CueKind].
String cueWordFor(CueKind kind) {
  switch (kind) {
    case CueKind.tap:
      return 'TAP!';
    case CueKind.hold:
      return 'HOLD';
    case CueKind.mash:
      return 'MASH!';
    case CueKind.drag:
      return 'DRAG';
  }
}

/// Overlay that draws one start cue per player zone while [showNow] is true.
///
/// Repaints off [hudTick] (already bumped every countdown frame by the runner)
/// and reads [remaining]/[total] to drive the pulse + identity-flash phases.
class StartCueOverlay extends StatelessWidget {
  const StartCueOverlay({
    super.key,
    required this.hudTick,
    required this.zones,
    required this.players,
    required this.inputHint,
    required this.remaining,
    required this.total,
    required this.showNow,
  });

  /// Repaint signal bumped each frame by the runner.
  final ValueNotifier<int> hudTick;

  /// Per-player screen slices.
  final ZoneLayout zones;

  /// Roster (for color + name + bot flag).
  final PlayerManager players;

  /// The running game's input hint (e.g. "TAP", "HOLD", "MASH", "MOVE").
  final String inputHint;

  /// Seconds left on the countdown (drops to 0 as play starts).
  final double Function() remaining;

  /// Total countdown length, for deriving elapsed time.
  final double total;

  /// Whether the cue should be shown at all (false once countdown is done).
  final bool Function() showNow;

  @override
  Widget build(BuildContext context) {
    final CueKind kind = cueKindFor(inputHint);
    final String word = cueWordFor(kind);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _StartCuePainter(
            repaint: hudTick,
            zones: zones,
            players: players,
            kind: kind,
            word: word,
            remaining: remaining,
            total: total,
            showNow: showNow,
          ),
        ),
      ),
    );
  }
}

class _StartCuePainter extends CustomPainter {
  _StartCuePainter({
    required Listenable repaint,
    required this.zones,
    required this.players,
    required this.kind,
    required this.word,
    required this.remaining,
    required this.total,
    required this.showNow,
  }) : super(repaint: repaint);

  final ZoneLayout zones;
  final PlayerManager players;
  final CueKind kind;
  final String word;
  final double Function() remaining;
  final double total;
  final bool Function() showNow;

  /// Caches laid-out paragraphs (the word + each player's name) so we don't
  /// rebuild a [ui.Paragraph] per zone every countdown frame (4 zones × 2 texts
  /// × 60fps). Keyed by the text + its (constant-per-slot) color; the painter
  /// instance is stable across the whole countdown, so this fills once.
  final Map<String, ui.Paragraph> _paragraphCache = <String, ui.Paragraph>{};

  @override
  void paint(Canvas canvas, Size size) {
    if (!showNow()) return;
    final double elapsed = (total - remaining()).clamp(0.0, total);
    final double pulse = _pulse01(elapsed);
    final double flash = _flash01(elapsed);

    for (final PlayerZone zone in zones.zones) {
      final PlayerSlot? slot = _slotFor(zone.playerId);
      if (slot == null) continue;
      _paintZone(canvas, size, zone, slot, pulse, flash);
    }
  }

  /// 0→1→0 triangle over one pulse period (used for ring radius/alpha).
  double _pulse01(double elapsed) {
    final double t = (elapsed % StartCueTune.pulsePeriodSec) /
        StartCueTune.pulsePeriodSec;
    return t < 0.5 ? t * 2 : (1 - t) * 2;
  }

  /// 1→0 over the identity-flash window, then stays 0.
  double _flash01(double elapsed) {
    if (elapsed >= StartCueTune.identityFlashSec) return 0;
    return 1 - (elapsed / StartCueTune.identityFlashSec);
  }

  PlayerSlot? _slotFor(int playerId) {
    for (final PlayerSlot s in players.slots) {
      if (s.id == playerId) return s;
    }
    return null;
  }

  void _paintZone(
    Canvas canvas,
    Size size,
    PlayerZone zone,
    PlayerSlot slot,
    double pulse,
    double flash,
  ) {
    final Rect r = Rect.fromLTRB(
      zone.normRect.left * size.width,
      zone.normRect.top * size.height,
      zone.normRect.right * size.width,
      zone.normRect.bottom * size.height,
    );
    final Color color = Color(slot.colorArgb);
    final double dim = slot.isBot ? StartCueTune.botDim : 1.0;

    // Identity flash: faint full-zone tint that fades over the first moment.
    if (flash > 0) {
      final Paint tint = Paint()
        ..color = color.withValues(
            alpha: StartCueTune.identityFlashAlpha * flash * dim);
      canvas.drawRect(r, tint);
    }

    final double base = math.min(r.width, r.height);
    final double targetR = math.min(
      base * StartCueTune.targetRadiusFactor,
      StartCueTune.targetRadiusMax,
    );

    canvas.save();
    canvas.translate(r.center.dx, r.center.dy);
    canvas.rotate(zone.rotationQuarters * math.pi / 2);

    _drawTarget(canvas, color, dim, targetR, pulse);
    _drawGlyph(canvas, color, dim, targetR, pulse);
    _drawWord(canvas, color, dim, targetR);
    _drawName(canvas, color, dim, targetR, slot.name);

    canvas.restore();
  }

  // ----- tap target (concentric pulsing rings) -----------------------------

  void _drawTarget(
      Canvas canvas, Color color, double dim, double targetR, double pulse) {
    // Soft filled core so the "press here" spot reads even at a glance.
    final Paint core = Paint()
      ..color = color.withValues(alpha: 0.16 * dim)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, targetR * 0.72, core);

    // Steady inner ring.
    final Paint inner = Paint()
      ..color = color.withValues(alpha: 0.9 * dim)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(Offset.zero, targetR * 0.72, inner);

    // Expanding ripple ring — radius and fade ride the pulse.
    final double rippleR = targetR * (0.72 + 0.7 * pulse);
    final Paint ripple = Paint()
      ..color = color.withValues(alpha: (1 - pulse) * 0.75 * dim)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset.zero, rippleR, ripple);
  }

  // ----- per-kind action glyph (centred in the target) ---------------------

  void _drawGlyph(
      Canvas canvas, Color color, double dim, double targetR, double pulse) {
    final Paint p = Paint()
      ..color = color.withValues(alpha: 0.95 * dim)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final double g = targetR * 0.42; // glyph half-extent

    switch (kind) {
      case CueKind.tap:
        _glyphTap(canvas, g, dim, color);
        break;
      case CueKind.hold:
        _glyphHold(canvas, p, g, pulse, dim, color);
        break;
      case CueKind.mash:
        _glyphMash(canvas, g, dim, color);
        break;
      case CueKind.drag:
        _glyphDrag(canvas, p, g);
        break;
    }
  }

  /// A single dot — the universal "tap right here".
  void _glyphTap(Canvas canvas, double g, double dim, Color color) {
    final Paint dot = Paint()
      ..color = color.withValues(alpha: 0.95 * dim)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, g * 0.55, dot);
  }

  /// A near-full arc that "fills" with the pulse — press and keep holding.
  void _glyphHold(Canvas canvas, Paint p, double g, double pulse, double dim,
      Color color) {
    final Paint dot = Paint()
      ..color = color.withValues(alpha: 0.95 * dim)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, g * 0.42, dot);

    // Sweep from the top, growing with the pulse (a charging ring).
    final double sweep = (0.2 + 0.8 * pulse) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: g * 0.95),
      -math.pi / 2,
      sweep,
      false,
      p,
    );
  }

  /// Two stacked dots — tap again and again, fast.
  void _glyphMash(Canvas canvas, double g, double dim, Color color) {
    final Paint dot = Paint()
      ..color = color.withValues(alpha: 0.95 * dim)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(0, -g * 0.45), g * 0.4, dot);
    canvas.drawCircle(Offset(0, g * 0.45), g * 0.4, dot);
  }

  /// Four arrows from the centre — move / drag in any direction.
  void _glyphDrag(Canvas canvas, Paint p, double g) {
    const List<double> dirs = <double>[
      -math.pi / 2, // up
      math.pi / 2, // down
      math.pi, // left
      0, // right
    ];
    final double len = g * 0.95;
    final double head = g * 0.32;
    for (final double a in dirs) {
      final Offset tip = Offset(math.cos(a) * len, math.sin(a) * len);
      canvas.drawLine(Offset.zero, tip, p);
      // Two short barbs forming the arrowhead.
      for (final double off in <double>[2.4, -2.4]) {
        final double ba = a + math.pi + off;
        canvas.drawLine(
          tip,
          tip + Offset(math.cos(ba) * head, math.sin(ba) * head),
          p,
        );
      }
    }
  }

  // ----- text: the action word (below target) and name (above) -------------

  void _drawWord(Canvas canvas, Color color, double dim, double targetR) {
    _drawCenteredText(
      canvas,
      word,
      Offset(0, targetR + StartCueTune.wordGap),
      color.withValues(alpha: 0.98 * dim),
      StartCueTune.wordSize,
      letterSpacing: 1.5,
    );
  }

  void _drawName(
      Canvas canvas, Color color, double dim, double targetR, String name) {
    _drawCenteredText(
      canvas,
      name,
      Offset(0, -(targetR + StartCueTune.wordGap + StartCueTune.nameSize)),
      color.withValues(alpha: 1.0 * dim),
      StartCueTune.nameSize,
      letterSpacing: 0.5,
    );
  }

  /// Paints [text] horizontally centred at [topCenter] (the *top* of the text
  /// box, so callers position by edge). The laid-out paragraph is cached and
  /// reused across frames (see [_paragraphCache]).
  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset topCenter,
    Color color,
    double fontSize, {
    double letterSpacing = 0,
  }) {
    final ui.Paragraph paragraph = _paragraph(text, color, fontSize, letterSpacing);
    canvas.drawParagraph(paragraph, Offset(topCenter.dx - 120, topCenter.dy));
  }

  /// Builds (and caches) a laid-out paragraph for [text]/[color]/[fontSize].
  ui.Paragraph _paragraph(
    String text,
    Color color,
    double fontSize,
    double letterSpacing,
  ) {
    final String key =
        '$text|${color.toARGB32()}|$fontSize|$letterSpacing';
    final ui.Paragraph? cached = _paragraphCache[key];
    if (cached != null) return cached;

    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.center,
        fontWeight: FontWeight.w900,
        fontSize: fontSize,
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: color,
        letterSpacing: letterSpacing,
        shadows: const <ui.Shadow>[
          ui.Shadow(color: Color(0xCC000000), blurRadius: 4),
        ],
      ))
      ..addText(text);
    final ui.Paragraph paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 240));
    _paragraphCache[key] = paragraph;
    return paragraph;
  }

  @override
  bool shouldRepaint(covariant _StartCuePainter oldDelegate) =>
      oldDelegate.zones != zones ||
      oldDelegate.kind != kind ||
      oldDelegate.word != word ||
      oldDelegate.total != total;
}
