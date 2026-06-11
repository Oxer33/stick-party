import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../art/fx/juice.dart';
import '../../engine/bots.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import 'snake_arena_bot.dart';
import 'snake_arena_types.dart';
import 'snake_render.dart';

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
///    a fresh pellet then respawns on a free cell. Only [_foodCount] pellets
///    exist at once and a fresh one is biased to spawn near the LONGEST snake,
///    so eating is a CONTESTED race (snakes converge on the same food) rather
///    than parallel grazing.
///  * Force a rival to crash into your body and you bank a [_takedownScore] +
///    [_takedownGrow]-segment TAKEDOWN bonus — blocking is worth playing for, so
///    snakes actively cut each other off, not just chase food.
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
  // Only TWO pellets on the board at once (was 4): scarcity turns eating into a
  // contested RACE instead of parallel grazing — snakes converge on the same
  // food and steal/block each other.
  static const int _foodCount = 2; // simultaneous pellets on the board

  // ── Contested spawns: bias fresh food toward the LEADER ─────────────────────
  // A fresh pellet has a [_leaderBiasChance] chance to spawn within
  // [_leaderBiasRadius] cells of the CURRENT LONGEST snake's head, dragging the
  // pack into the leader's space so the lead is contestable (rubber-band without
  // nerfing anyone's score). Falls back to a free uniform cell if the biased
  // pick is occupied/walled.
  static const double _leaderBiasChance = 0.66; // odds a pellet targets the lead
  static const int _leaderBiasRadius = 5; // cells around the leader head

  // ── Reward for forcing a rival crash ────────────────────────────────────────
  // When a snake dies by running INTO another living snake's body, the snake it
  // hit is credited a [_takedownScore] bonus — blocking a rival is now worth
  // playing for, adding direct interaction on top of the food race. (Wall, self
  // and mutual head-on deaths credit no one — only a clean body-block pays.)
  static const int _takedownScore = 2; // score for causing a rival's crash
  static const int _takedownGrow = 2; // bonus segments for a takedown (feeds length)
  static const int _takedownSparks = 12; // celebratory burst on a takedown

  // ── Climax: SUDDEN DEATH (the arena closes in) ──────────────────────────────
  // In the final [_suddenDeathSec] the walls march inward one ring at a time
  // (every [_shrinkRingSec]), squeezing the snakes together so the round can
  // never drag — a snake caught in a freshly closed ring dies. A one-shot cue
  // (banner + heavy shake) announces it. Capped so a sliver of arena always
  // remains for the survivors to fight over.
  static const double _suddenDeathSec = 9.0; // length of the closing finale
  static const double _shrinkRingSec = 1.4; // seconds per closed border ring
  static const int _shrinkRingsMax = 6; // hard cap on closed rings per side

  // ── Chaos: the GOLDEN pellet (a swingy bonus any snake can grab) ─────────────
  static const double _goldenChance = 0.16; // odds a fresh pellet is golden
  static const int _goldenGrow = 4; // extra segments a golden pellet grants
  static const int _goldenScore = 3; // score a golden pellet is worth
  static const int _goldenEatSparks = 18; // bigger burst on a golden eat
  static const Color _goldFx = Color(0xFFFFD24A); // golden pellet / cue accent

  // ── Bot tuning ──────────────────────────────────────────────────────────────
  // With only two pellets, a stronger food pull makes bots converge on the same
  // scarce food and actively contest it (the leader-biased spawns put that food
  // in crowded space), so the race reads as competitive rather than aimless.
  static const double _botFoodBias = 0.7; // chance to chase food when safe
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
  final List<Snake> _snakes = [];
  final List<Cell> _food = [];
  final Set<Cell> _golden = <Cell>{}; // which active pellets are golden
  bool _suddenDeathAnnounced = false; // the closing-arena cue fired once

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
      final heading = fromLeft ? Heading.right : Heading.left;
      final snake = Snake(
        playerId: p.id,
        color: Color(p.colorArgb),
        head: Cell(col, row),
        heading: heading,
        clock: p.isBot ? ReactionClock(ctx.botProfile, ctx.rng) : null,
      );
      // Seed an initial body trailing behind the head.
      final back = kStep[heading]!;
      for (var s = 1; s < _startLength; s++) {
        snake.body.add(Cell(col - back.col * s, row - back.row * s));
      }
      _snakes.add(snake);
    }
  }

  void _seedFood() {
    for (var i = 0; i < _foodCount; i++) {
      _spawnOneFood();
    }
  }

  /// Spawn one pellet on a free cell (not on a body, not on another pellet, not
  /// in a closed SUDDEN-DEATH ring). With [_leaderBiasChance] it first targets a
  /// cell near the LONGEST snake's head (contested spawn — drags the pack toward
  /// the leader); otherwise (and as a fallback) it tries uniform-random cells,
  /// then a deterministic scan so it never hangs. A fresh pellet may be GOLDEN.
  void _spawnOneFood() {
    if (ctx.rng.chance(_leaderBiasChance) && _trySpawnNearLeader()) return;
    const maxTries = 40;
    for (var t = 0; t < maxTries; t++) {
      final c = Cell(ctx.rng.intRange(0, _cols), ctx.rng.intRange(0, _rows));
      if (_isFree(c) && !_hitsWall(c)) {
        _addFood(c);
        return;
      }
    }
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final cell = Cell(c, r);
        if (_isFree(cell) && !_hitsWall(cell)) {
          _addFood(cell);
          return;
        }
      }
    }
  }

  /// Try to place a pellet within [_leaderBiasRadius] cells of the current
  /// longest living snake's head, so fresh food keeps appearing in contested
  /// space around the leader. Returns false (no spawn) if there is no leader or
  /// no free biased cell was found in a bounded number of tries — the caller
  /// then falls back to a uniform spawn.
  bool _trySpawnNearLeader() {
    final leader = _longestLivingSnake();
    if (leader == null) return false;
    final head = leader.head;
    const maxTries = 24;
    for (var t = 0; t < maxTries; t++) {
      final r = _leaderBiasRadius;
      final c = Cell(
        head.col + ctx.rng.intRange(-r, r + 1),
        head.row + ctx.rng.intRange(-r, r + 1),
      );
      if (c.col < 0 || c.col >= _cols || c.row < 0 || c.row >= _rows) continue;
      if (_isFree(c) && !_hitsWall(c)) {
        _addFood(c);
        return true;
      }
    }
    return false;
  }

  /// The longest living snake (ties broken by first found), or null if none are
  /// alive — drives the contested-spawn bias toward the current leader.
  Snake? _longestLivingSnake() {
    Snake? best;
    for (final s in _snakes) {
      if (!s.alive) continue;
      if (best == null || s.length > best.length) best = s;
    }
    return best;
  }

  /// Place a pellet and roll whether it is golden (tracked in [_golden]).
  void _addFood(Cell c) {
    _food.add(c);
    if (ctx.rng.chance(_goldenChance)) _golden.add(c);
  }

  bool _isFree(Cell c) {
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
        s.heading = Heading.values[(s.heading.index + delta) % 4];
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

    _maybeAnnounceSuddenDeath();
    _cullClosedRing();
    if (status == MiniGameStatus.finished) return;
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

  /// Drive every bot's reaction clock; when one fires, steer it via [SnakeBot]
  /// (a several-cells-ahead flood-fill + food pull + head-on dodge), which reads
  /// as competent without being psychic. [BotProfile.errorRate] makes it fumble.
  /// The AI is fed the game's own wall/body tests so it respects SUDDEN DEATH.
  void _driveBots(double dt) {
    final bot = SnakeBot(
      snakes: _snakes,
      food: _food,
      cols: _cols,
      rows: _rows,
      profile: ctx.botProfile,
      rng: ctx.rng,
      hitsWall: _hitsWall,
      hitsBody: (c, mover) => _hitsAnyBody(c, ignoreTailOf: mover),
      foodBias: _botFoodBias,
      lookahead: _botLookahead,
      floodCap: _botFloodCap,
      spaceWeight: _botSpaceWeight,
      headOnPenalty: _botHeadOnPenalty,
    );
    for (final s in _snakes) {
      if (!s.alive || s.clock == null) continue;
      if (!s.clock!.tick(dt)) continue;
      s.clock!.arm(ctx.botProfile, ctx.rng);
      bot.steer(s);
    }
  }

  /// In SUDDEN DEATH the playable box shrinks: [_shrinkRings] border rings on
  /// every side are closed off and count as wall. Zero until the finale opens,
  /// then it ramps one ring at a time (capped so a core arena always remains).
  int _shrinkRings() {
    final intoSd = _elapsed - (_timeLimit - _suddenDeathSec);
    if (intoSd <= 0) return 0;
    final rings = (intoSd / _shrinkRingSec).floor() + 1;
    // Never close so far that no interior is left (keep at least a 3-wide core).
    final maxByGrid = ((math.min(_cols, _rows) - 3) / 2).floor();
    return rings.clamp(0, math.min(_shrinkRingsMax, math.max(0, maxByGrid)));
  }

  /// True if [c] is outside the (possibly shrunk) playable box. Routing the
  /// closing arena through the one wall test makes the whole sim — deaths, food
  /// spawns and bot pathing — respect SUDDEN DEATH automatically.
  bool _hitsWall(Cell c) {
    final m = _shrinkRings();
    return c.col < m ||
        c.col >= _cols - m ||
        c.row < m ||
        c.row >= _rows - m;
  }

  /// True if [c] overlaps any living snake's body. The moving snake's own tail
  /// is ignored when it is about to vacate that cell (no pending growth).
  bool _hitsAnyBody(Cell c, {required Snake ignoreTailOf}) {
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

  /// The living snake (other than [exclude]) whose body occupies [c], or null if
  /// none — used to attribute a takedown to the snake that blocked a rival. The
  /// mover's own about-to-vacate tail is ignored so a self-trim is not a body.
  Snake? _bodyOwnerAt(Cell c, {required Snake exclude}) {
    for (final s in _snakes) {
      if (!s.alive || identical(s, exclude)) continue;
      for (var i = 0; i < s.body.length; i++) {
        if (s.body[i] == c) return s;
      }
    }
    return null;
  }

  /// Credit [blocker] a takedown: bump its score + growth, then fire the
  /// signature cinematic beat at [crashCell] — where the rival ran into the
  /// blocker's body. One `bigMoment` per crash (burst + shake + slow-mo + zoom +
  /// flash + "TAKEDOWN!" banner + haptic) so forcing a rival crash reads as a
  /// deliberate, celebrated win.
  void _awardTakedown(Snake blocker, Cell crashCell) {
    blocker.score += _takedownScore;
    // Bonus growth feeds the length-based ranking too, so a takedown is a real
    // edge (longer snake) rather than a cosmetic counter.
    blocker.pendingGrowth += _takedownGrow;
    setScore(blocker.playerId, blocker.score);
    final at = _cellCenter(crashCell, _lastSize);
    _juice.bigMoment(at, blocker.color, banner: 'TAKEDOWN!',
        sparks: _takedownSparks);
  }

  // ── Step resolution ──────────────────────────────────────────────────────────

  /// Advance all living snakes one cell, resolving deaths and eating, then check
  /// for a winner. Deaths are computed against pre-move positions so head-on
  /// collisions kill both snakes fairly.
  void _advanceAll() {
    final living = _snakes.where((s) => s.alive).toList();
    if (living.isEmpty) return;

    final nextHeads = <Snake, Cell>{
      for (final s in living) s: s.head.plus(kStep[s.heading]!),
    };

    // Phase 1: flag deaths (wall, body, head-on swap, shared target cell). When
    // the death is a clean block — running into ANOTHER snake's body — remember
    // who owns that body so it can be credited a takedown (interaction reward).
    final dying = <Snake>{};
    final killer = <Snake, Snake>{}; // victim → the rival whose body blocked it
    for (final s in living) {
      final nh = nextHeads[s]!;
      if (_hitsWall(nh)) {
        dying.add(s);
        continue;
      }
      if (_hitsAnyBody(nh, ignoreTailOf: s)) {
        dying.add(s);
        final blocker = _bodyOwnerAt(nh, exclude: s);
        if (blocker != null) killer[s] = blocker; // crashed into a rival
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
        final wasGolden = _golden.remove(nh);
        s.pendingGrowth += wasGolden ? _goldenGrow : _growPerFood;
        s.score += wasGolden ? _goldenScore : 1;
        setScore(s.playerId, s.score);
        _onEat(nh, s.color, golden: wasGolden);
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

    // Phase 3b: pay out takedowns — a snake that blocked a rival (and survived
    // the step itself) banks the bonus, so cutting another snake off is worth
    // playing for, not just incidental.
    for (final entry in killer.entries) {
      final victim = entry.key;
      final blocker = entry.value;
      // The crash cell is where the victim tried to move — i.e. into the
      // blocker's body. Aim the cinematic beat there.
      if (blocker.alive) _awardTakedown(blocker, nextHeads[victim]!);
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
  void _maybeNearMiss(Snake s) {
    if (_nearMissCd > 0) return;
    final ahead = s.head.plus(kStep[s.heading]!); // the cell it's about to enter
    var hazard = false;
    Offset? toward;
    for (final step in kStep.values) {
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
  bool _isHazardBody(Cell c, Snake self) {
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

  /// Eat feedback: pop sparks at the pellet + a score popup + a light wall flare
  /// — snappy, but quieter than a death. A GOLDEN pellet pops a bigger gold
  /// burst, a "+N" with a louder shake, so a swingy grab reads as a big deal.
  void _onEat(Cell at, Color color, {bool golden = false}) {
    final p = _cellCenter(at, _lastSize);
    final burstColor = golden ? _goldFx : color;
    _juice.particles.burst(
      at: p,
      count: golden ? _goldenEatSparks : _eatSparks,
      color: burstColor,
      speed: golden ? 300 : 220,
      size: golden ? 7 : 5,
      gravity: 120,
      life: golden ? 0.6 : 0.45,
    );
    _juice.popup(p.translate(0, -_cell() * 0.8),
        golden ? '+$_goldenScore' : '+1', burstColor,
        size: golden ? 30 : 22);
    if (golden) {
      _juice.shake.medium();
    } else {
      _juice.shake.light();
    }
    _wallFlare = math.max(_wallFlare, golden ? 0.7 : 0.4);
  }

  /// Fire the one-shot SUDDEN DEATH cue the instant the arena starts closing: a
  /// banner, a heavy shake and a full wall flare so the closing walls read.
  void _maybeAnnounceSuddenDeath() {
    if (_suddenDeathAnnounced || _shrinkRings() <= 0) return;
    _suddenDeathAnnounced = true;
    final center = Offset(_lastSize.width / 2, _lastSize.height * 0.42);
    _juice.popup(center, 'SUDDEN DEATH!', _goldFx, size: 44);
    _juice.shake.heavy();
    _wallFlare = 1.0;
  }

  /// Kill any living snake whose head is caught inside a freshly closed SUDDEN
  /// DEATH ring (the wall closed on it), then resolve the round if that leaves
  /// one (or zero) snakes — so the closing arena always forces a finish.
  void _cullClosedRing() {
    if (_shrinkRings() <= 0) return;
    var killedAny = false;
    for (final s in _snakes) {
      if (s.alive && _hitsWall(s.head)) {
        _kill(s);
        killedAny = true;
      }
    }
    if (!killedAny) return;
    if (_aliveCount() == 0 || (_aliveCount() <= 1 && _snakes.length > 1)) {
      _finishByLength();
    }
  }

  void _kill(Snake s) {
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
    _juice.applyWorldTransform(canvas);

    SnakeRenderer.drawGrid(canvas, field, _cols, _rows, _gridPulse());
    SnakeRenderer.drawWalls(canvas, field, _wallFlare);

    // SUDDEN DEATH: draw the closing inner walls as a bright, throbbing border
    // around the still-playable box so the squeeze is unmistakable.
    final rings = _shrinkRings();
    if (rings > 0) {
      SnakeRenderer.drawClosingWalls(
          canvas, _shrunkFieldRect(size, rings), 0.6 + 0.4 * _gridPulse());
    }

    for (final f in _food) {
      SnakeRenderer.drawFood(
        canvas,
        _cellCenter(f, size),
        _cell(),
        _animClock + f.col * 0.6 + f.row * 0.4, // per-pellet phase offset
        golden: _golden.contains(f),
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

    _juice.renderOverlay(canvas, size);
  }

  void _drawSnake(Canvas canvas, Snake s, Size size) {
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
  void _drawTurnHint(Canvas canvas, Snake s, Size size) {
    final isHuman = s.clock == null;
    final fadeIn = (1.0 - _elapsed / _hintFadeSec).clamp(0.0, 1.0);
    final emphasis = isHuman
        ? _hintIdleLevel + (1.0 - _hintIdleLevel) * fadeIn
        : _hintIdleLevel * 0.5;
    final leftHeading = Heading.values[(s.heading.index + 3) % 4];
    final rightHeading = Heading.values[(s.heading.index + 1) % 4];
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

  Offset _headingPixelDir(Heading h) {
    final step = kStep[h]!;
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

  /// Pixel rect of the still-playable box once [rings] border rings are closed
  /// (the SUDDEN DEATH inner wall), inset from the full field by whole cells.
  Rect _shrunkFieldRect(Size size, int rings) {
    final f = _fieldRect(size);
    final cw = f.width / _cols;
    final ch = f.height / _rows;
    return Rect.fromLTRB(
      f.left + rings * cw,
      f.top + rings * ch,
      f.right - rings * cw,
      f.bottom - rings * ch,
    );
  }

  Offset _cellCenter(Cell c, Size size) {
    final f = _fieldRect(size);
    final cw = f.width / _cols;
    final ch = f.height / _rows;
    return Offset(f.left + (c.col + 0.5) * cw, f.top + (c.row + 0.5) * ch);
  }

  // ── Test seams (read-only / setup) ──────────────────────────────────────────

  /// Number of pellets currently on the board (should never exceed [_foodCount]).
  @visibleForTesting
  int get foodCount => _food.length;

  /// The simultaneous-pellet cap, exposed so a test reads the tuned value.
  @visibleForTesting
  static int get maxFood => _foodCount;

  /// Snapshot of the live pellet cells (copy — mutating it cannot affect state).
  @visibleForTesting
  List<Cell> get foodCells => List.unmodifiable(_food);

  /// Head cell of [id]'s snake, or null if there is no such snake.
  @visibleForTesting
  Cell? headOf(int id) {
    for (final s in _snakes) {
      if (s.playerId == id) return s.head;
    }
    return null;
  }

  /// Append [n] trailing segments to [id]'s snake (a deterministic way to make a
  /// clear leader in tests). The extra cells are stacked behind the tail; they
  /// only need to make [Snake.length] larger for the leader-bias spawn logic.
  @visibleForTesting
  void growSnakeForTest(int id, int n) {
    for (final s in _snakes) {
      if (s.playerId != id) continue;
      final tail = s.body.last;
      for (var i = 0; i < n; i++) {
        s.body.add(tail); // duplicate-tail padding; length is all the bias reads
      }
      return;
    }
  }

  /// Clear all pellets, then spawn one fresh pellet — lets a test exercise the
  /// (leader-biased) spawn path in isolation and inspect where it lands.
  @visibleForTesting
  void respawnSingleFoodForTest() {
    _food.clear();
    _golden.clear();
    _spawnOneFood();
  }
}
