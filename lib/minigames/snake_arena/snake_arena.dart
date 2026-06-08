import 'dart:math' as math;
import 'dart:ui';

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'snake_render.dart';

/// Four cardinal headings on the grid, ordered clockwise so a right turn is
/// `(index + 1) % 4` and a left turn is `(index + 3) % 4`.
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
///  * **TAP a SIDE of your zone to steer**: tapping the LEFT half of your
///    zone turns the snake LEFT (counter-clockwise), the RIGHT half turns it
///    RIGHT (clockwise) — "tap the side you want to turn toward". This is the
///    most intuitive control for young children (steer like a wheel), and
///    reversing into your own neck is impossible by design. Turns are relative
///    to the snake's current heading; the zone's own rotation (top-edge players
///    are flipped 180°) is accounted for so left/right always match what that
///    player sees. A tap with no position (e.g. a synthetic/test tap) defaults
///    to a right turn so the old one-tap behavior still works.
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
  static const double _stepSecStart = 0.18; // initial tick interval (calm start)
  static const double _stepSecMin = 0.09; // floor as the round heats up
  static const double _warmupSec = 4.0; // calm spell before the speed ramp
  static const double _stepRampSec = 20.0; // time (after warmup) to reach floor
  static const double _timeLimit = 35;
  static const int _startLength = 3;
  static const int _growPerFood = 2;
  static const int _foodCount = 4; // simultaneous pellets on the board

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  static const double _botFoodBias = 0.55; // chance to chase food when safe
  static const int _botLookahead = 5; // cells of free space a bot wants ahead
  static const int _botFloodCap = 24; // max cells counted by the safety flood
  static const double _botSpaceWeight = 1.6; // free-space vs food-distance weight
  static const double _botHeadOnPenalty = 40.0; // dodge cells a rival can enter

  // ── Layout tuning (pixels / fractions) ──────────────────────────────────────
  static const double _marginFactor = 0.04; // arena margin / min(w,h)
  static const double _hudHeightFactor = 0.11; // HUD column height / arena height
  static const double _hudGap = 10.0; // gap between field and HUD

  // ── Juice tuning ────────────────────────────────────────────────────────────
  static const int _eatSparks = 10;
  static const int _nearMissSparks = 5;
  static const double _wallFlareDecay = 2.4; // per-second flare falloff
  static const double _nearMissCooldownSec = 0.18; // throttle near-miss sparks
  static const double _hintFadeSec = 1.6; // turn-hint settle time at round start
  static const double _hintIdleLevel = 0.55; // resting turn-hint brightness

  late Juice _juice;
  final List<_Snake> _snakes = [];
  final List<_Cell> _food = [];

  // Death order, worst→best as snakes die (used to build the final ranking).
  final List<int> _deathOrder = [];

  double _elapsed = 0;
  double _stepAcc = 0;
  double _animClock = 0; // real-time clock for pulses (never time-scaled)
  double _wallFlare = 0; // 0..1 neon wall flare, decays over time
  double _nearMissCd = 0; // near-miss spark throttle (real-time)
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
    _turn(input.playerId, _tapTurnsRight(input.playerId, input.normPos));
  }

  /// Which half of the player's zone the tap landed in. Returns true for a RIGHT
  /// turn (right half), false for a LEFT turn (left half). The tap [pos] is in
  /// full-screen 0..1 space; it is mapped into the player's [PlayerZone] and the
  /// zone's own 180° rotation (top-edge seats) is undone so "right" always means
  /// the player's own right. A degenerate/zero tap defaults to a right turn so a
  /// positionless synthetic tap still steers (and never stalls).
  bool _tapTurnsRight(int id, Offset pos) {
    final zone = ctx.zones.forPlayer(id);
    if (zone == null) return true;
    final rect = zone.normRect;
    if (rect.width <= 0) return true;
    // Fraction across the zone, 0 at its left edge → 1 at its right edge.
    var fx = ((pos.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    // A 180°-rotated seat sees its zone upside-down, so its left/right are
    // mirrored relative to screen space.
    if (zone.rotationQuarters % 4 == 2) fx = 1.0 - fx;
    return fx >= 0.5;
  }

  /// Turn a snake: RIGHT = clockwise (`+1`), LEFT = counter-clockwise (`+3`).
  /// Reversing straight back is impossible because a single ±90° turn can never
  /// flip the heading 180°.
  void _turn(int id, bool right) {
    for (final s in _snakes) {
      if (s.playerId == id && s.alive) {
        final delta = right ? 1 : 3;
        s.heading = _Heading.values[(s.heading.index + delta) % 4];
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
    _nearMissCd = math.max(0, _nearMissCd - dt);

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

  /// Tick interval holds at [_stepSecStart] through [_warmupSec] (a calm spell
  /// to read the board), then shrinks linearly to [_stepSecMin] over
  /// [_stepRampSec] so snakes speed up and rounds converge.
  double _currentStepSec() =>
      _stepSecStart + (_stepSecMin - _stepSecStart) * _speedHeat();

  /// How "hot" the round is (0..1): zero during warmup, then ramps to 1.
  double _speedHeat() =>
      ((_elapsed - _warmupSec) / _stepRampSec).clamp(0.0, 1.0);

  // ── Bots ────────────────────────────────────────────────────────────────────

  /// Bots look SEVERAL cells ahead, not one. On each reaction tick a bot scores
  /// every non-reverse heading by how much open space it opens up (a capped
  /// flood-fill so it won't drive into a pocket it can't escape) plus a pull
  /// toward the nearest pellet, and steers to the best one. This makes them read
  /// as competent — they hug walls, weave through trails and grab food — without
  /// being psychic. [BotProfile.errorRate] makes them occasionally take a worse
  /// (but still legal) turn, so easy bots fumble and a human can win.
  void _driveBots(double dt) {
    for (final s in _snakes) {
      if (!s.alive || s.clock == null) continue;
      if (!s.clock!.tick(dt)) continue;
      s.clock!.arm(ctx.botProfile, ctx.rng);
      _steerBot(s);
    }
  }

  /// Choose this bot's heading. Considers straight + both turns (reverse is
  /// illegal by design). Picks the highest-scoring legal heading; on an error
  /// roll it instead picks a random *legal* heading (a misjudgment, not instant
  /// suicide). Leaves the heading unchanged only when fully boxed in.
  void _steerBot(_Snake s) {
    final options = <_Heading>[];
    var best = s.heading;
    var bestScore = -double.infinity;
    final target = _nearestFood(s.head);

    for (final i in const [0, 1, 3]) {
      // 0 = straight, 1 = clockwise, 3 = counter-clockwise (2 = reverse, skip).
      final h = _Heading.values[(s.heading.index + i) % 4];
      if (_isBlocked(s, h)) continue;
      options.add(h);
      final score = _headingScore(s, h, target);
      if (score > bestScore) {
        bestScore = score;
        best = h;
      }
    }

    if (options.isEmpty) return; // boxed in — it will crash (correct).
    if (options.length > 1 && ctx.rng.chance(ctx.botProfile.errorRate)) {
      s.heading = ctx.rng.pick(options); // believable misjudgment
      return;
    }
    s.heading = best;
  }

  /// Higher is better. Reward open space reachable after the step (so the bot
  /// avoids trapping itself) and, when food bias fires, reward getting closer to
  /// the nearest pellet. Penalise stepping into a cell a rival head could also
  /// enter next tick (a likely fatal head-on). Space dominates so survival beats
  /// greed, and dodging beats both.
  double _headingScore(_Snake s, _Heading h, _Cell? target) {
    final next = s.head.plus(_kStep[h]!);
    var score = _reachableSpace(next, s).toDouble() * _botSpaceWeight;
    if (target != null && ctx.rng.chance(_botFoodBias)) {
      // Closer pellet → higher score (negative distance), modestly weighted.
      score += (_cols + _rows) - _manhattan(next, target);
    }
    if (_rivalCanEnter(next, s)) score -= _botHeadOnPenalty;
    return score;
  }

  /// True if some OTHER living snake's head is one cell away from [cell] — i.e.
  /// it could move into [cell] on the same tick, killing both. Lets bots steer
  /// out of head-on standoffs instead of trading kills (smarter, fairer, and it
  /// keeps rounds from collapsing in the first seconds).
  bool _rivalCanEnter(_Cell cell, _Snake self) {
    for (final o in _snakes) {
      if (!o.alive || identical(o, self)) continue;
      if (_manhattan(o.head, cell) == 1) return true;
    }
    return false;
  }

  /// Capped flood-fill: how many free cells are reachable starting from [from],
  /// treating living snake bodies (except [mover]'s about-to-move tail) and the
  /// walls as solid. Counts at most [_botFloodCap] cells and explores at most
  /// [_botLookahead] rings deep — cheap, deterministic, enough to tell "roomy"
  /// from "dead end". Returns 0 if [from] itself is solid.
  int _reachableSpace(_Cell from, _Snake mover) {
    if (_hitsWall(from) || _hitsAnyBody(from, ignoreTailOf: mover)) return 0;
    final seen = <_Cell>{from};
    var frontier = <_Cell>[from];
    var count = 1;
    for (var depth = 0; depth < _botLookahead && count < _botFloodCap; depth++) {
      final next = <_Cell>[];
      for (final cell in frontier) {
        for (final step in _kStep.values) {
          final n = cell.plus(step);
          if (seen.contains(n)) continue;
          if (_hitsWall(n) || _hitsAnyBody(n, ignoreTailOf: mover)) continue;
          seen.add(n);
          next.add(n);
          if (++count >= _botFloodCap) break;
        }
        if (count >= _botFloodCap) break;
      }
      if (next.isEmpty) break;
      frontier = next;
    }
    return count;
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

    // Phase 4: near-miss feedback — a survivor whose head is now one cell from a
    // wall or another body just had a close shave; spark it (throttled).
    for (final s in living) {
      if (!s.alive) continue;
      _maybeNearMiss(s);
    }

    // End on the last survivor (multi-player) OR when no snake is left alive
    // (covers a solo snake crashing — otherwise the round would idle on an
    // empty grid until the time limit).
    if (_aliveCount() == 0 || (_aliveCount() <= 1 && _snakes.length > 1)) {
      _finishByLength();
    }
  }

  /// Spark + tiny shake when [s]'s head sits adjacent to a hazard it did not hit
  /// (a wall, another snake, or its own deeper body) — a "phew" beat that makes
  /// dodging feel earned. Throttled by [_nearMissCooldownSec] so a snake gliding
  /// along a wall doesn't fizz every tick.
  void _maybeNearMiss(_Snake s) {
    if (_nearMissCd > 0) return;
    final ahead = s.head.plus(_kStep[s.heading]!); // the cell it's about to enter
    var hazard = false;
    Offset? toward;
    for (final step in _kStep.values) {
      final n = s.head.plus(step);
      if (n == ahead) continue; // that's its path, not a near miss
      if (_hitsWall(n) || _isHazardBody(n, s)) {
        hazard = true;
        toward = Offset(step.col.toDouble(), step.row.toDouble());
        break;
      }
    }
    if (!hazard) return;
    _nearMissCd = _nearMissCooldownSec;
    final at = _cellCenter(s.head, _lastSize);
    final dir = toward ?? const Offset(0, -1);
    _juice.particles.burst(
      at: at + dir * (_cell() * 0.4),
      count: _nearMissSparks,
      color: Color.lerp(s.color, const Color(0xFFFFFFFF), 0.4) ?? s.color,
      speed: 150,
      baseAngle: math.atan2(dir.dy, dir.dx),
      spread: math.pi * 0.5,
      size: 3.5,
      gravity: 60,
      life: 0.3,
    );
    _juice.shake.light();
  }

  /// True if cell [c] holds a body segment that is a real hazard to [self] — any
  /// other snake's body, or [self]'s own body beyond the neck (ignores the head
  /// and the segment right behind it, which can never be a "near miss").
  bool _isHazardBody(_Cell c, _Snake self) {
    for (final o in _snakes) {
      if (!o.alive) continue;
      if (identical(o, self)) {
        for (var i = 2; i < o.body.length; i++) {
          if (o.body[i] == c) return true;
        }
      } else if (o.body.contains(c)) {
        return true;
      }
    }
    return false;
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

    // The "tap left / tap right to steer" hint, on top of the snakes so it
    // always reads.
    for (final s in _snakes.where((s) => s.alive)) {
      _drawTurnHint(canvas, s, size);
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

  /// Draw the "tap left = turn left, tap right = turn right" affordance over
  /// [s]'s head: a left-pointing and a right-pointing arrow flanking the head,
  /// each showing where that tap would send the snake. Humans (no bot clock) get
  /// a bold hint that fades from full to a calm idle level over [_hintFadeSec] so
  /// the rule lands at the start without nagging forever; bots show a faint
  /// version so every snake visibly obeys the same rule.
  void _drawTurnHint(Canvas canvas, _Snake s, Size size) {
    final isHuman = s.clock == null;
    final fadeIn = (1.0 - _elapsed / _hintFadeSec).clamp(0.0, 1.0);
    final emphasis = isHuman
        ? _hintIdleLevel + (1.0 - _hintIdleLevel) * fadeIn
        : _hintIdleLevel * 0.5;
    final leftHeading = _Heading.values[(s.heading.index + 3) % 4];
    final rightHeading = _Heading.values[(s.heading.index + 1) % 4];
    SnakeRenderer.drawTurnHint(
      canvas,
      _cellCenter(s.head, size),
      _headingPixelDir(s.heading),
      _headingPixelDir(leftHeading),
      _headingPixelDir(rightHeading),
      _cell(),
      s.color,
      pulse: _gridPulse(),
      emphasis: emphasis,
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
