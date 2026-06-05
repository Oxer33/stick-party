import 'dart:math' as math;
import 'dart:ui';

import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../art/fx/juice.dart';

/// The four pad colors players reproduce. Index 0..3 maps to a pad slot.
const List<Color> _kPalette = [
  Color(0xFFE5484D), // red
  Color(0xFF3E8BFF), // blue
  Color(0xFF46C46A), // green
  Color(0xFFF2C037), // yellow
];

/// Round phase. [showing] flashes the sequence; [input] takes reproduction.
enum _Phase { showing, input }

/// Per-player reproduction state for the current round.
class _Pad {
  final int playerId;
  final Color accent;
  bool alive = true;
  bool done = false; // finished this round's reproduction correctly
  int progress = 0; // correct entries so far this round
  int highlight = 0; // currently highlighted pad (one-touch cursor)
  final ReactionClock? clock;

  _Pad({required this.playerId, required this.accent, this.clock});
}

/// Color Memory — a Simon-style game on a shared, growing color sequence.
///
/// One-touch rule (documented): during the [_Phase.input] phase each player has
/// a highlight that auto-cycles through their four pads every [_cycleSec]. A tap
/// **locks the currently-highlighted color** as that player's next entry:
/// - correct → progress advances; once progress == sequence length the player
///   has cleared the round and waits;
/// - wrong → that player is eliminated ([Juice.ko]).
///
/// Each round the sequence first flashes (showing), then everyone reproduces.
/// When the round resolves, the sequence grows by one. Last player standing
/// wins via [finishByOrder].
///
/// Termination is guaranteed several ways: a per-round input deadline
/// ([_roundDeadlineSec]) eliminates anyone who hasn't finished, a sequence
/// length cap ([_maxSeqLen]), last-player-standing, and the overall
/// [_timeLimit].
class ColorMemory extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'color_memory',
        name: 'Color Memory',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  static const int _palette = 4;
  static const double _timeLimit = 45;
  static const double _showStepSec = 0.45; // per-color flash during showing
  static const double _cycleSec = 0.4; // per-pad highlight dwell during input
  static const double _roundDeadlineSec = 6.0; // hard cap on one input phase
  static const int _maxSeqLen = 24; // absolute cap so it always terminates
  static const int _startSeqLen = 1;

  late Juice _juice;
  final List<int> _sequence = [];
  final List<_Pad> _pads = [];

  // Elimination order (worst→best) used to build the final ranking.
  final List<int> _outOrder = [];

  _Phase _phase = _Phase.showing;
  double _elapsed = 0;
  double _phaseTimer = 0; // time spent in the current phase
  double _cycleAcc = 0; // drives the input-highlight cursor
  int _showIndex = 0; // which sequence color is flashing
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    for (final p in ctx.players) {
      _pads.add(_Pad(
        playerId: p.id,
        accent: Color(p.colorArgb),
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      ));
    }
    for (var i = 0; i < _startSeqLen; i++) {
      _sequence.add(ctx.rng.intRange(0, _palette));
    }
    _enterShowing();
    begin();
  }

  // ---- Phase transitions ----------------------------------------------------

  void _enterShowing() {
    _phase = _Phase.showing;
    _phaseTimer = 0;
    _showIndex = 0;
  }

  void _enterInput() {
    _phase = _Phase.input;
    _phaseTimer = 0;
    _cycleAcc = 0;
    for (final pad in _pads) {
      if (!pad.alive) continue;
      pad.progress = 0;
      pad.done = false;
      pad.highlight = 0;
      pad.clock?.arm(ctx.botProfile, ctx.rng);
    }
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running ||
        _phase != _Phase.input ||
        input.phase != InputPhase.down) {
      return;
    }
    final pad = _padOf(input.playerId);
    if (pad == null || !pad.alive || pad.done) return;
    // One-touch rule: lock whatever color is currently highlighted.
    _commit(pad, pad.highlight);
  }

  _Pad? _padOf(int id) {
    for (final p in _pads) {
      if (p.playerId == id) return p;
    }
    return null;
  }

  /// Apply a chosen color for [pad]: advance on a match, eliminate on a miss.
  void _commit(_Pad pad, int color) {
    final expected = _sequence[pad.progress];
    if (color == expected) {
      pad.progress += 1;
      if (pad.progress >= _sequence.length) {
        pad.done = true;
      }
    } else {
      _eliminate(pad);
    }
  }

  void _eliminate(_Pad pad) {
    if (!pad.alive) return;
    pad.alive = false;
    _outOrder.add(pad.playerId);
    _juice.ko(_padCenter(pad.playerId), pad.accent);
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);
    _phaseTimer += sdt;

    if (_phase == _Phase.showing) {
      _updateShowing();
    } else {
      _updateInput(sdt);
    }

    if (_elapsed >= _timeLimit) _finishNow();
  }

  /// Flash through the sequence; advance to input once all colors have shown.
  void _updateShowing() {
    _showIndex = (_phaseTimer ~/ _showStepSec).clamp(0, _sequence.length);
    if (_phaseTimer >= _sequence.length * _showStepSec) {
      _enterInput();
    }
  }

  /// Drive the highlight cursor + bots, then resolve the round when everyone
  /// alive is done or the input deadline passes.
  void _updateInput(double dt) {
    _cycleAcc += dt;
    while (_cycleAcc >= _cycleSec) {
      _cycleAcc -= _cycleSec;
      for (final pad in _pads) {
        if (pad.alive && !pad.done) {
          pad.highlight = (pad.highlight + 1) % _palette;
        }
      }
    }

    _driveBots(dt);

    final deadlineHit = _phaseTimer >= _roundDeadlineSec;
    if (deadlineHit) {
      // Anyone who hasn't finished reproducing in time is out.
      for (final pad in _pads) {
        if (pad.alive && !pad.done) _eliminate(pad);
      }
    }

    if (_roundResolved()) _resolveRound();
  }

  /// Bots commit on their reaction cadence: the correct color with probability
  /// (1 - errorRate), otherwise a deliberately wrong one (→ elimination).
  void _driveBots(double dt) {
    for (final pad in _pads) {
      if (pad.clock == null || !pad.alive || pad.done) continue;
      if (!pad.clock!.tick(dt)) continue;
      pad.clock!.arm(ctx.botProfile, ctx.rng);

      final expected = _sequence[pad.progress];
      final correct = !ctx.rng.chance(ctx.botProfile.errorRate);
      final color = correct ? expected : _wrongColor(expected);
      _commit(pad, color);
    }
  }

  int _wrongColor(int expected) {
    final offset = ctx.rng.intRange(1, _palette);
    return (expected + offset) % _palette;
  }

  bool _roundResolved() {
    for (final pad in _pads) {
      if (pad.alive && !pad.done) return false;
    }
    return true;
  }

  /// Round over: check terminal conditions, else grow the sequence and replay.
  void _resolveRound() {
    final alive = _pads.where((p) => p.alive).length;

    // Last player standing (multi-player) ends the match.
    if (_pads.length > 1 && alive <= 1) {
      _finishNow();
      return;
    }
    // Everyone wiped simultaneously (e.g. single-player miss / mass deadline).
    if (alive == 0) {
      _finishNow();
      return;
    }
    // Sequence cap reached → stop here and rank survivors.
    if (_sequence.length >= _maxSeqLen) {
      _finishNow();
      return;
    }

    _sequence.add(ctx.rng.intRange(0, _palette));
    _enterShowing();
  }

  /// Build best→worst ranking: survivors first (more progress / longer-lived),
  /// then eliminated players in reverse knock-out order. Every id appears once.
  void _finishNow() {
    if (status == MiniGameStatus.finished) return;
    final survivors = _pads.where((p) => p.alive).toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    for (final pad in _pads) {
      // Score = entries cleared; survivors get full sequence-length credit.
      setScore(pad.playerId, pad.alive ? _sequence.length : pad.progress);
    }
    final ordered = <int>[
      ...survivors.map((p) => p.playerId),
      ..._outOrder.reversed,
    ];
    final seen = <int>{};
    final full = [
      for (final id in ordered)
        if (seen.add(id)) id,
    ];
    for (final p in ctx.players) {
      if (seen.add(p.id)) full.add(p.id);
    }
    finishByOrder(full);
  }

  // ---- Rendering ------------------------------------------------------------

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    _drawBorder(canvas, size);
    for (var i = 0; i < _pads.length; i++) {
      _drawPlayerPads(canvas, _pads[i], i);
    }
    _drawSharedSequence(canvas, size);

    _juice.render(canvas);
    canvas.restore();
  }

  void _drawBorder(Canvas canvas, Size size) {
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x33FFFFFF);
    canvas.drawRect(Offset.zero & size, border);
  }

  /// Draw one player's 2x2 pad block within their region of the screen.
  void _drawPlayerPads(Canvas canvas, _Pad pad, int index) {
    final region = _playerRegion(index, _pads.length);
    final block = _padBlockRect(region);
    final half = block.width / 2;
    final gap = half * 0.08;

    for (var slot = 0; slot < _palette; slot++) {
      final cx = block.left + (slot % 2) * half;
      final cy = block.top + (slot ~/ 2) * half;
      final cell =
          Rect.fromLTWH(cx + gap, cy + gap, half - gap * 2, half - gap * 2);
      final lit = _phase == _Phase.input &&
          pad.alive &&
          !pad.done &&
          pad.highlight == slot;
      final base = _kPalette[slot];
      final color = pad.alive
          ? base.withValues(alpha: lit ? 1.0 : 0.45)
          : base.withValues(alpha: 0.12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell, Radius.circular(half * 0.14)),
        Paint()..color = color,
      );
    }

    // Progress pips under the block in the player's accent.
    _drawProgress(canvas, pad, block);
  }

  void _drawProgress(Canvas canvas, _Pad pad, Rect block) {
    if (_sequence.isEmpty) return;
    final pipR = block.width * 0.018;
    final y = block.bottom + pipR * 2;
    final paint = Paint()..color = pad.accent;
    final dim = Paint()..color = pad.accent.withValues(alpha: 0.25);
    final span = block.width;
    for (var i = 0; i < _sequence.length; i++) {
      final x = block.left + span * ((i + 0.5) / _sequence.length);
      canvas.drawCircle(Offset(x, y), pipR, i < pad.progress ? paint : dim);
    }
  }

  /// Shared sequence preview: flashes the active color while showing.
  void _drawSharedSequence(Canvas canvas, Size size) {
    if (_phase != _Phase.showing || _sequence.isEmpty) return;
    final idx = _showIndex.clamp(0, _sequence.length - 1);
    final color = _kPalette[_sequence[idx]];
    final r = math.min(size.width, size.height) * 0.08;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, r, Paint()..color = color);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x66FFFFFF),
    );
  }

  // ---- Layout helpers -------------------------------------------------------

  /// Normalized region for a player's HUD (mirrors ZoneLayout sensibilities).
  Rect _playerRegion(int index, int count) {
    switch (count) {
      case 1:
        return const Rect.fromLTRB(0.15, 0.35, 0.85, 0.8);
      case 2:
        return index == 0
            ? const Rect.fromLTRB(0.15, 0.55, 0.85, 0.9)
            : const Rect.fromLTRB(0.15, 0.1, 0.85, 0.45);
      case 3:
        if (index == 0) return const Rect.fromLTRB(0.3, 0.6, 0.7, 0.92);
        return index == 1
            ? const Rect.fromLTRB(0.06, 0.1, 0.46, 0.42)
            : const Rect.fromLTRB(0.54, 0.1, 0.94, 0.42);
      default:
        final left = index.isEven;
        final bottom = index < 2;
        final l = left ? 0.06 : 0.54;
        final t = bottom ? 0.58 : 0.1;
        return Rect.fromLTRB(l, t, l + 0.4, t + 0.32);
    }
  }

  Rect _padBlockRect(Rect region) {
    final px = Rect.fromLTRB(
      region.left * _lastSize.width,
      region.top * _lastSize.height,
      region.right * _lastSize.width,
      region.bottom * _lastSize.height,
    );
    final side = math.min(px.width, px.height);
    return Rect.fromCenter(center: px.center, width: side, height: side);
  }

  Offset _padCenter(int playerId) {
    final index = _pads.indexWhere((p) => p.playerId == playerId);
    if (index < 0) return Offset(_lastSize.width / 2, _lastSize.height / 2);
    return _padBlockRect(_playerRegion(index, _pads.length)).center;
  }
}
