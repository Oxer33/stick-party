import 'dart:math' as math;
import 'dart:ui';

import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../art/fx/juice.dart';

/// Four cardinal headings on the grid, ordered clockwise so a tap can rotate
/// to the next one with `(index + 1) % 4`.
enum _Heading { up, right, down, left }

const Map<_Heading, _Cell> _kStep = {
  _Heading.up: _Cell(0, -1),
  _Heading.right: _Cell(1, 0),
  _Heading.down: _Cell(0, 1),
  _Heading.left: _Cell(-1, 0),
};

/// Immutable integer grid coordinate.
class _Cell {
  final int col;
  final int row;
  const _Cell(this.col, this.row);

  _Cell plus(_Cell o) => _Cell(col + o.col, row + o.row);

  @override
  bool operator ==(Object other) =>
      other is _Cell && other.col == col && other.row == row;

  @override
  int get hashCode => col * 31337 + row;
}

/// One player's snake: an ordered body (head first) on the shared grid.
class _Snake {
  final int playerId;
  final Color color;
  final List<_Cell> body; // index 0 == head
  _Heading heading;
  bool alive = true;
  int pendingGrowth = 0; // segments still to grow (skips tail removal)

  // Bot steering only.
  final ReactionClock? clock;

  _Snake({
    required this.playerId,
    required this.color,
    required _Cell head,
    required this.heading,
    this.clock,
  }) : body = [head];

  _Cell get head => body.first;
  int get length => body.length;
}

/// Snake Arena — every player drives a snake on one shared grid.
///
/// Rules (one clear scheme):
/// - Each snake advances exactly one cell every [_stepSec] (logical tick,
///   independent of frame dt). Tap rotates that snake's heading **clockwise**.
/// - A snake dies when its next head cell hits a wall, its own body, or any
///   other snake's body. Death triggers [Juice.ko] at the head.
/// - Snakes grow by one segment every [_growEverySec].
/// - Last snake alive wins; if [_timeLimit] elapses, the longest snake wins.
///   Final ranking is survivors (by length) then the reverse death order.
class SnakeArena extends MiniGameBase {
  @override
  MiniGameMeta get meta => const MiniGameMeta(
        id: 'snake_arena',
        name: 'Snake Arena',
        minPlayers: 1,
        maxPlayers: 4,
        modes: [GameMode.ffa],
        inputHint: 'TAP',
      );

  static const int _cols = 24;
  static const int _rows = 32;
  static const double _stepSec = 0.12; // one grid advance per tick
  static const double _growEverySec = 3.0;
  static const double _timeLimit = 45;
  static const int _startLength = 3;

  late Juice _juice;
  final List<_Snake> _snakes = [];

  // Death order, worst→best as snakes die (used to build the final ranking).
  final List<int> _deathOrder = [];

  double _elapsed = 0;
  double _stepAcc = 0;
  double _growAcc = 0;
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _spawnSnakes();
    begin();
  }

  /// Place each snake on its own row band, headed toward open space.
  void _spawnSnakes() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
      // Spread start rows evenly; alternate facing so they grow apart.
      final row = ((i + 1) * _rows) ~/ (count + 1);
      final fromLeft = i.isEven;
      final col = fromLeft ? _startLength : _cols - 1 - _startLength;
      final heading = fromLeft ? _Heading.right : _Heading.left;
      final snake = _Snake(
        playerId: p.id,
        color: Color(p.colorArgb),
        head: _Cell(col, row),
        heading: heading,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      );
      // Seed an initial body trailing behind the head.
      final back = _kStep[heading]!;
      for (var s = 1; s < _startLength; s++) {
        snake.body.add(_Cell(col - back.col * s, row - back.row * s));
      }
      _snakes.add(snake);
    }
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _turn(input.playerId);
  }

  /// Rotate a snake's heading clockwise (up→right→down→left→up).
  void _turn(int id) {
    for (final s in _snakes) {
      if (s.playerId == id && s.alive) {
        s.heading = _Heading.values[(s.heading.index + 1) % 4];
        return;
      }
    }
  }

  @override
  void update(double dt) {
    if (status != MiniGameStatus.running) return;
    _elapsed += dt;
    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _driveBots(sdt);

    _stepAcc += sdt;
    while (_stepAcc >= _stepSec) {
      _stepAcc -= _stepSec;
      _advanceAll();
      if (status == MiniGameStatus.finished) return;
    }

    _growAcc += sdt;
    while (_growAcc >= _growEverySec) {
      _growAcc -= _growEverySec;
      for (final s in _snakes) {
        if (s.alive) s.pendingGrowth += 1;
      }
    }

    if (_elapsed >= _timeLimit) _finishByLength();
  }

  /// Bots look one cell ahead; if blocked they turn (clockwise) to seek a free
  /// cell. They also turn occasionally by mistake via [BotProfile.errorRate].
  void _driveBots(double dt) {
    for (final s in _snakes) {
      if (!s.alive || s.clock == null) continue;
      if (!s.clock!.tick(dt)) continue;
      s.clock!.arm(ctx.botProfile, ctx.rng);

      if (_isBlocked(s, s.heading)) {
        _steerToSafe(s);
      } else if (ctx.rng.chance(ctx.botProfile.errorRate)) {
        // Deliberate mistake: a turn that may or may not be safe.
        s.heading = _Heading.values[(s.heading.index + 1) % 4];
      }
    }
  }

  /// Pick the first clockwise heading whose next cell is free; leave unchanged
  /// if the snake is boxed in (it will crash, which is correct).
  void _steerToSafe(_Snake s) {
    for (var i = 1; i <= 3; i++) {
      final h = _Heading.values[(s.heading.index + i) % 4];
      if (!_isBlocked(s, h)) {
        s.heading = h;
        return;
      }
    }
  }

  bool _isBlocked(_Snake s, _Heading h) {
    final next = s.head.plus(_kStep[h]!);
    return _hitsWall(next) || _hitsAnyBody(next, ignoreTailOf: s);
  }

  bool _hitsWall(_Cell c) =>
      c.col < 0 || c.col >= _cols || c.row < 0 || c.row >= _rows;

  /// True if [c] overlaps any living snake's body. The moving snake's own tail
  /// is ignored when it is about to vacate that cell (no pending growth).
  bool _hitsAnyBody(_Cell c, {required _Snake ignoreTailOf}) {
    for (final s in _snakes) {
      if (!s.alive) continue;
      for (var i = 0; i < s.body.length; i++) {
        final isMovingTail = identical(s, ignoreTailOf) &&
            i == s.body.length - 1 &&
            ignoreTailOf.pendingGrowth == 0;
        if (isMovingTail) continue;
        if (s.body[i] == c) return true;
      }
    }
    return false;
  }

  /// Advance all living snakes one cell, resolving deaths, then check for a
  /// winner. Deaths are computed against pre-move positions so head-on
  /// collisions kill both snakes fairly.
  void _advanceAll() {
    final living = _snakes.where((s) => s.alive).toList();
    if (living.isEmpty) return;

    final nextHeads = <_Snake, _Cell>{
      for (final s in living) s: s.head.plus(_kStep[s.heading]!),
    };

    // Phase 1: flag deaths (wall, body, head-on swap, shared target cell).
    final dying = <_Snake>{};
    for (final s in living) {
      final nh = nextHeads[s]!;
      if (_hitsWall(nh) || _hitsAnyBody(nh, ignoreTailOf: s)) {
        dying.add(s);
        continue;
      }
      for (final o in living) {
        if (identical(o, s)) continue;
        final sameTarget = nextHeads[o] == nh;
        final swap = nextHeads[o] == s.head && nh == o.head;
        if (sameTarget || swap) {
          dying.add(s);
          break;
        }
      }
    }

    // Phase 2: move survivors (advance head, trim tail unless growing).
    for (final s in living) {
      if (dying.contains(s)) continue;
      s.body.insert(0, nextHeads[s]!);
      if (s.pendingGrowth > 0) {
        s.pendingGrowth -= 1;
      } else {
        s.body.removeLast();
      }
    }

    // Phase 3: kill flagged snakes (after moves so KO lands at the head cell).
    for (final s in dying) {
      _kill(s);
    }

    if (_aliveCount() <= 1 && _snakes.length > 1) _finishByLength();
  }

  void _kill(_Snake s) {
    if (!s.alive) return;
    s.alive = false;
    _deathOrder.add(s.playerId);
    _juice.ko(_cellCenter(s.head, _lastSize), s.color);
    setScore(s.playerId, s.length);
  }

  int _aliveCount() => _snakes.where((s) => s.alive).length;

  /// Build best→worst ranking: living snakes first (longest wins), then the
  /// dead in reverse death order (latest death ranks higher). Every player id
  /// appears exactly once.
  void _finishByLength() {
    if (status == MiniGameStatus.finished) return;
    final living = _snakes.where((s) => s.alive).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final s in living) {
      setScore(s.playerId, s.length);
    }
    final ordered = <int>[
      ...living.map((s) => s.playerId),
      ..._deathOrder.reversed,
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
    for (final s in _snakes) {
      _drawSnake(canvas, s);
    }

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

  void _drawSnake(Canvas canvas, _Snake s) {
    final cw = _lastSize.width / _cols;
    final ch = _lastSize.height / _rows;
    final cell = math.min(cw, ch);
    final inset = cell * 0.12;
    final paint = Paint()
      ..color = s.alive ? s.color : s.color.withValues(alpha: 0.25);
    for (var i = 0; i < s.body.length; i++) {
      final c = s.body[i];
      final left = c.col * cw + inset;
      final top = c.row * ch + inset;
      final rect = Rect.fromLTWH(left, top, cw - inset * 2, ch - inset * 2);
      // Head a touch rounder than the body.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(i == 0 ? cell * 0.4 : cell * 0.2),
        ),
        paint,
      );
    }
  }

  Offset _cellCenter(_Cell c, Size size) {
    final cw = size.width / _cols;
    final ch = size.height / _rows;
    return Offset((c.col + 0.5) * cw, (c.row + 0.5) * ch);
  }
}
