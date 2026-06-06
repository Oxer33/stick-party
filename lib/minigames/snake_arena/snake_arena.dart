import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'snake_render.dart';

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
/// Mutable round-scoped state (allowed for the duration of one round).
class _Snake {
  final int playerId;
  final Color color;
  final List<_Cell> body; // index 0 == head
  _Heading heading;
  bool alive = true;
  int pendingGrowth = 0; // segments still to grow (skips tail removal)
  int score = 0; // pellets eaten (HUD readout)

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

/// Snake Arena — every player drives a glowing TRON snake on one shared neon
/// grid.
///
/// Rules (one clear scheme):
///  * Each snake advances exactly one cell every logical tick (dt is
///    accumulated, so the sim is deterministic regardless of frame rate). The
///    tick interval starts at [_stepSecStart] and ramps toward [_stepSecMin]
///    over the round so matches converge.
///  * **TAP rotates that snake's heading CLOCKWISE** (up→right→down→left→up).
///    One control, and reversing into your own neck is impossible by design.
///  * Eat a glowing food pellet to grow by [_growPerFood] segments and +1 score;
///    a fresh pellet then respawns on a free cell.
///  * A snake dies when its next head cell hits a wall, its own body, or any
///    other snake's body (head-on swaps kill both). Death = explosion burst +
///    heavy shake + hit-stop, and the snake is eliminated.
///  * Last snake alive wins. If [_timeLimit] elapses first, the longest snake
///    wins. Final ranking ([finishByOrder]) is survivors (by length) then the
///    reverse death order, so every player id appears exactly once.
///
/// Bots look one cell ahead and steer to a safe neighbor, lightly biasing
/// toward the nearest pellet; [BotProfile.errorRate] makes them occasionally
/// take a worse turn so they feel human, not perfect.
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

  // ── Grid / sim tuning (no magic numbers inline) ─────────────────────────────
  static const int _cols = 23;
  static const int _rows = 30;
  static const double _stepSecStart = 0.13; // initial tick interval
  static const double _stepSecMin = 0.075; // floor as the round heats up
  static const double _stepRampSec = 38.0; // time to reach the floor
  static const double _timeLimit = 45;
  static const int _startLength = 3;
  static const int _growPerFood = 2;
  static const int _foodCount = 3; // simultaneous pellets on the board

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botFoodBias = 0.55; // chance to chase food when safe

  // ── Layout tuning (pixels / fractions) ──────────────────────────────────────
  static const double _marginFactor = 0.04; // arena margin / min(w,h)
  static const double _hudHeightFactor = 0.11; // HUD column height / arena height
  static const double _hudGap = 10.0; // gap between field and HUD

  // ── Juice tuning ────────────────────────────────────────────────────────────
  static const int _eatSparks = 10;
  static const double _wallFlareDecay = 2.4; // per-second flare falloff

  late Juice _juice;
  final List<_Snake> _snakes = [];
  final List<_Cell> _food = [];

  // Death order, worst→best as snakes die (used to build the final ranking).
  final List<int> _deathOrder = [];

  double _elapsed = 0;
  double _stepAcc = 0;
  double _animClock = 0; // real-time clock for pulses (never time-scaled)
  double _wallFlare = 0; // 0..1 neon wall flare, decays over time
  Size _lastSize = const Size(1, 1);

  @override
  void init(MiniGameContext ctx) {
    prepare(ctx);
    _juice = Juice(rng: ctx.rng);
    _spawnSnakes();
    _seedFood();
    begin();
  }

  /// Place each snake on its own row band, headed toward open space, with a
  /// short trailing body so it reads as a snake from frame one.
  void _spawnSnakes() {
    final count = ctx.players.length;
    for (var i = 0; i < count; i++) {
      final p = ctx.players[i];
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

  void _seedFood() {
    for (var i = 0; i < _foodCount; i++) {
      _spawnOneFood();
    }
  }

  /// Spawn one pellet on a free cell (not on a body, not on another pellet).
  /// Tries random cells; falls back to a deterministic scan so it never hangs.
  void _spawnOneFood() {
    const maxTries = 40;
    for (var t = 0; t < maxTries; t++) {
      final c = _Cell(ctx.rng.intRange(0, _cols), ctx.rng.intRange(0, _rows));
      if (_isFree(c)) {
        _food.add(c);
        return;
      }
    }
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final cell = _Cell(c, r);
        if (_isFree(cell)) {
          _food.add(cell);
          return;
        }
      }
    }
  }

  bool _isFree(_Cell c) {
    if (_food.contains(c)) return false;
    for (final s in _snakes) {
      if (s.body.contains(c)) return false;
    }
    return true;
  }

  @override
  void onInput(PlayerInput input) {
    if (status != MiniGameStatus.running || input.phase != InputPhase.down) {
      return;
    }
    _turn(input.playerId);
  }

  /// Rotate a snake's heading CLOCKWISE (up→right→down→left→up).
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
    if (!dt.isFinite || dt <= 0) return;
    _elapsed += dt;
    _animClock += dt;
    _wallFlare = math.max(0, _wallFlare - _wallFlareDecay * dt);

    final sdt = dt * _juice.hitStop.timeScale;
    _juice.update(dt);

    _driveBots(sdt);

    final step = _currentStepSec();
    _stepAcc += sdt;
    while (_stepAcc >= step) {
      _stepAcc -= step;
      _advanceAll();
      if (status == MiniGameStatus.finished) return;
    }

    if (_elapsed >= _timeLimit) _finishByLength();
  }

  /// Tick interval shrinks linearly from [_stepSecStart] to [_stepSecMin] over
  /// [_stepRampSec] so snakes speed up and rounds converge.
  double _currentStepSec() {
    final t = (_elapsed / _stepRampSec).clamp(0.0, 1.0);
    return _stepSecStart + (_stepSecMin - _stepSecStart) * t;
  }

  /// How "hot" the round is (0..1) — drives the speed-up screen tint.
  double _speedHeat() => (_elapsed / _stepRampSec).clamp(0.0, 1.0);

  // ── Bots ────────────────────────────────────────────────────────────────────

  /// Bots look one cell ahead. If their current heading is blocked they steer to
  /// the safest free neighbor (preferring one toward the nearest pellet); when
  /// safe they lightly chase food. [BotProfile.errorRate] injects an occasional
  /// worse turn so they read as fallible players.
  void _driveBots(double dt) {
    for (final s in _snakes) {
      if (!s.alive || s.clock == null) continue;
      if (!s.clock!.tick(dt)) continue;
      s.clock!.arm(ctx.botProfile, ctx.rng);

      if (_isBlocked(s, s.heading)) {
        _steerToSafe(s);
      } else if (ctx.rng.chance(ctx.botProfile.errorRate)) {
        // Deliberate mistake: a clockwise turn that may or may not be safe.
        s.heading = _Heading.values[(s.heading.index + 1) % 4];
      } else if (ctx.rng.chance(_botFoodBias)) {
        _seekFood(s);
      }
    }
  }

  /// Pick a free heading that steps closest to the nearest pellet (preferring a
  /// safe turn); fall back to the first safe clockwise heading. Leaves the
  /// heading unchanged if boxed in (it will crash, which is correct).
  void _steerToSafe(_Snake s) {
    final target = _nearestFood(s.head);
    _Heading? best;
    var bestDist = 1 << 30;
    for (var i = 1; i <= 3; i++) {
      final h = _Heading.values[(s.heading.index + i) % 4];
      if (_isBlocked(s, h)) continue;
      if (target == null) {
        s.heading = h; // first safe option when there is no food to chase
        return;
      }
      final d = _manhattan(s.head.plus(_kStep[h]!), target);
      if (d < bestDist) {
        bestDist = d;
        best = h;
      }
    }
    if (best != null) s.heading = best;
  }

  /// While already safe ahead, optionally turn toward the nearest pellet if that
  /// turn is also safe (light, opportunistic food-seeking).
  void _seekFood(_Snake s) {
    final target = _nearestFood(s.head);
    if (target == null) return;
    var bestDist = _manhattan(s.head.plus(_kStep[s.heading]!), target);
    _Heading? turn;
    for (final i in const [1, 3]) {
      // clockwise + counter-clockwise (2 = reverse, impossible anyway).
      final h = _Heading.values[(s.heading.index + i) % 4];
      if (_isBlocked(s, h)) continue;
      final d = _manhattan(s.head.plus(_kStep[h]!), target);
      if (d < bestDist) {
        bestDist = d;
        turn = h;
      }
    }
    if (turn != null) s.heading = turn;
  }

  _Cell? _nearestFood(_Cell from) {
    _Cell? best;
    var bestDist = 1 << 30;
    for (final f in _food) {
      final d = _manhattan(from, f);
      if (d < bestDist) {
        bestDist = d;
        best = f;
      }
    }
    return best;
  }

  static int _manhattan(_Cell a, _Cell b) =>
      (a.col - b.col).abs() + (a.row - b.row).abs();

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

  // ── Step resolution ──────────────────────────────────────────────────────────

  /// Advance all living snakes one cell, resolving deaths and eating, then check
  /// for a winner. Deaths are computed against pre-move positions so head-on
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

    // Phase 2: move survivors (advance head; eat grows, otherwise trim tail).
    for (final s in living) {
      if (dying.contains(s)) continue;
      final nh = nextHeads[s]!;
      s.body.insert(0, nh);
      final ate = _food.remove(nh);
      if (ate) {
        s.pendingGrowth += _growPerFood;
        s.score += 1;
        setScore(s.playerId, s.score);
        _onEat(nh, s.color);
        _spawnOneFood();
      }
      if (s.pendingGrowth > 0) {
        s.pendingGrowth -= 1;
      } else {
        s.body.removeLast();
      }
    }

    // Phase 3: kill flagged snakes (after moves so the burst lands at the head).
    for (final s in dying) {
      _kill(s);
    }

    // End on the last survivor (multi-player) OR when no snake is left alive
    // (covers a solo snake crashing — otherwise the round would idle on an
    // empty grid until the time limit).
    if (_aliveCount() == 0 || (_aliveCount() <= 1 && _snakes.length > 1)) {
      _finishByLength();
    }
  }

  /// Eat feedback: pop sparks at the pellet + a small score popup + a light wall
  /// flare — snappy, but quieter than a death.
  void _onEat(_Cell at, Color color) {
    final p = _cellCenter(at, _lastSize);
    _juice.particles.burst(
      at: p,
      count: _eatSparks,
      color: color,
      speed: 220,
      size: 5,
      gravity: 120,
      life: 0.45,
    );
    _juice.popup(p.translate(0, -_cell() * 0.8), '+1', color, size: 22);
    _juice.shake.light();
    _wallFlare = math.max(_wallFlare, 0.4);
  }

  void _kill(_Snake s) {
    if (!s.alive) return;
    s.alive = false;
    _deathOrder.add(s.playerId);
    final at = _cellCenter(s.head, _lastSize);
    // Explosion: scatter the body into sparks along its length, then a big KO.
    for (var i = 0; i < s.body.length; i += 2) {
      _juice.particles.burst(
        at: _cellCenter(s.body[i], _lastSize),
        count: 4,
        color: s.color,
        speed: 200,
        size: 5,
        life: 0.6,
      );
    }
    _juice.ko(at, s.color);
    _wallFlare = 1.0;
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

  // ── Rendering ──────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas, Size size) {
    _lastSize = size;
    final field = _fieldRect(size);

    SnakeRenderer.drawBackground(canvas, size);

    canvas.save();
    final o = _juice.shake.offset;
    canvas.translate(o.dx, o.dy);

    SnakeRenderer.drawGrid(canvas, field, _cols, _rows, _gridPulse());
    SnakeRenderer.drawWalls(canvas, field, _wallFlare);

    for (final f in _food) {
      SnakeRenderer.drawFood(
        canvas,
        _cellCenter(f, size),
        _cell(),
        _animClock + f.col * 0.6 + f.row * 0.4, // per-pellet phase offset
      );
    }

    // Dead snakes first (husks under the living), then the living on top.
    for (final s in _snakes.where((s) => !s.alive)) {
      _drawSnake(canvas, s, size);
    }
    for (final s in _snakes.where((s) => s.alive)) {
      _drawSnake(canvas, s, size);
    }

    _juice.render(canvas);
    canvas.restore();

    _drawHud(canvas, size, field);

    // Speed-up tint sits above everything (including shake) as an ambient wash.
    SnakeRenderer.drawSpeedTint(canvas, size, _speedHeat());
  }

  void _drawSnake(Canvas canvas, _Snake s, Size size) {
    final pixels = [for (final c in s.body) _cellCenter(c, size)];
    SnakeRenderer.drawSnake(
      canvas,
      pixels,
      _headingPixelDir(s.heading),
      _cell(),
      s.color,
      alive: s.alive,
    );
  }

  void _drawHud(Canvas canvas, Size size, Rect field) {
    final top = field.bottom + _hudGap;
    final margin = _margin(size);
    final h = size.height * _hudHeightFactor - _hudGap;
    if (h <= 1) return;
    final bar = Rect.fromLTWH(margin, top, size.width - margin * 2,
        math.min(h, size.height - top - margin));
    if (bar.height <= 1) return;
    SnakeRenderer.drawHudBacking(canvas, bar);
    final total = _snakes.length;
    for (var i = 0; i < total; i++) {
      final s = _snakes[i];
      SnakeRenderer.drawPlayerStat(
          canvas, bar, i, total, s.color, s.length, s.alive);
    }
  }

  /// Grid breathing 0..1, gentle sine.
  double _gridPulse() => 0.5 + 0.5 * math.sin(_animClock * 1.4);

  Offset _headingPixelDir(_Heading h) {
    final step = _kStep[h]!;
    return Offset(step.col.toDouble(), step.row.toDouble());
  }

  // ── Layout helpers ────────────────────────────────────────────────────────

  double _margin(Size size) => math.min(size.width, size.height) * _marginFactor;

  /// The playfield rectangle: margins all round + a reserved HUD strip beneath.
  /// Cells are kept square by fitting the grid aspect into the available box.
  Rect _fieldRect(Size size) {
    final m = _margin(size);
    final hud = size.height * _hudHeightFactor;
    final availW = size.width - m * 2;
    final availH = size.height - m * 2 - hud;
    if (availW <= 1 || availH <= 1) {
      return Rect.fromLTWH(0, 0, size.width, size.height);
    }
    final cell = math.min(availW / _cols, availH / _rows);
    final w = cell * _cols;
    final fh = cell * _rows;
    final left = m + (availW - w) / 2;
    return Rect.fromLTWH(left, m, w, fh);
  }

  /// Side length of one grid cell in pixels (square).
  double _cell() => _fieldRect(_lastSize).width / _cols;

  Offset _cellCenter(_Cell c, Size size) {
    final f = _fieldRect(size);
    final cw = f.width / _cols;
    final ch = f.height / _rows;
    return Offset(f.left + (c.col + 0.5) * cw, f.top + (c.row + 0.5) * ch);
  }
}
