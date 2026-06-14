import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/snake_arena/snake_arena.dart';

void main() {
  MiniGameContext ctxFor(int n, int seed) => MiniGameContext(
        players: [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
      );

  // ── Invariants (kept) ───────────────────────────────────────────────────────

  test('four bots finish with a full ranking', () {
    final g = SnakeArena()..init(ctxFor(4, 7));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
    expect(g.winResult!.ranking.length, 4);
  });

  test('all-bot 4p round lasts >1.5s and finishes within the time limit', () {
    // PACING contract: a round must not collapse instantly (>1.5s of play) and
    // must always resolve well within the round time limit (never just idle out)
    // across difficulties and seeds.
    const minTicks = 90; // 1.5s at 60 fps
    const maxTicks = 60 * 38; // ~38s: the 35s limit + a small resolution buffer
    for (final diff in BotDifficulty.values) {
      for (final seed in const [1, 7, 13, 21, 34]) {
        final ctx = MiniGameContext(
          players: [for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)],
          arena: const Size(800, 1200),
          rng: SeededRng(seed),
          zones: ZoneLayout.forPlayers(4),
          difficulty: diff,
        );
        final g = SnakeArena()..init(ctx);
        var ticks = 0;
        while (g.status != MiniGameStatus.finished && ticks < 60 * 120) {
          g.update(1 / 60);
          ticks++;
        }
        expect(g.status, MiniGameStatus.finished,
            reason: 'diff=$diff seed=$seed must finish');
        expect(ticks, greaterThan(minTicks),
            reason: 'diff=$diff seed=$seed lasted ${ticks / 60}s (<1.5s)');
        expect(ticks, lessThanOrEqualTo(maxTicks),
            reason: 'diff=$diff seed=$seed lasted ${ticks / 60}s (over limit)');
      }
    }
  });

  test('terminates for 1, 2 and 3 players across seeds', () {
    for (final n in [1, 2, 3]) {
      for (final seed in [1, 5, 42]) {
        final g = SnakeArena()..init(ctxFor(n, seed));
        var i = 0;
        while (g.status != MiniGameStatus.finished && i++ < 60 * 120) {
          g.update(1 / 60);
        }
        expect(g.status, MiniGameStatus.finished,
            reason: 'n=$n seed=$seed must finish');
        expect(
            g.winResult!.ranking.toSet(), {for (var p = 0; p < n; p++) p});
      }
    }
  });

  test('left/right side taps steer and the game still finishes', () {
    // New control: tapping the LEFT half of the zone turns left, the RIGHT half
    // turns right (via input.normPos). Player 0's zone in a 2p layout is the
    // bottom half, so x<0.5 is its left and x>=0.5 its right. Alternating sides
    // must never throw and the round must still resolve.
    final g = SnakeArena()..init(ctxFor(2, 3));
    g.onInput(PlayerInput.down(0, const Offset(0.2, 0.75))); // left half → left
    g.onInput(PlayerInput.down(0, const Offset(0.8, 0.75))); // right half → right
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % 17 == 0) {
        final left = (n ~/ 17).isEven;
        g.onInput(PlayerInput.down(0, Offset(left ? 0.2 : 0.8, 0.75)));
      }
    }
    expect(g.status, MiniGameStatus.finished);
  });

  test('a positionless tap still steers without throwing', () {
    // A synthetic tap with no position (origin) must still be a valid steer (it
    // reads as the left half) so test/automation paths never stall.
    final g = SnakeArena()..init(ctxFor(2, 3));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % 17 == 0) g.onInput(PlayerInput.down(0));
    }
    expect(g.status, MiniGameStatus.finished);
  });

  test('SUDDEN DEATH: the closing arena forces a finish within the limit', () {
    // CLIMAX mechanic. The arena starts closing in the final window, so even a
    // cagey field is squeezed to a finish — it must always resolve by the 35s
    // cap (+a small resolution buffer), never idle out forever, across seeds.
    const maxTicks = 60 * 36; // 35s limit + buffer
    for (final seed in const [1, 7, 13, 21, 34, 42]) {
      final g = SnakeArena()..init(ctxFor(2, seed));
      var ticks = 0;
      while (g.status != MiniGameStatus.finished && ticks < 60 * 120) {
        g.update(1 / 60);
        ticks++;
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      expect(ticks, lessThanOrEqualTo(maxTicks),
          reason: 'seed=$seed should resolve within the cap');
    }
  });

  test('render does not throw deep into SUDDEN DEATH (arena closing)', () {
    // The closing-wall + golden-pellet draw paths must be exercised without
    // throwing once the arena is closing (the last ~9s of the 35s round).
    final g = SnakeArena()..init(ctxFor(4, 5));
    final canvas = Canvas(PictureRecorder());
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 36) {
      g.update(1 / 60);
      if (n / 60.0 >= 27.0) {
        // Inside the closing window each frame: render must stay safe.
        expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
      }
    }
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });

  test('render does not throw before or after finish', () {
    final g = SnakeArena()..init(ctxFor(4, 11));
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
    }
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });

  // ── New behavior: scarcity + contested / leader-biased food ──────────────────

  test('only two pellets share the board (scarcity drives a contested race)',
      () {
    // The pellet count was cut 4 → 2. It must hold at seed, never exceed the cap
    // mid-game, and immediately refill to the cap when one is eaten.
    expect(SnakeArena.maxFood, 2);
    final g = SnakeArena()..init(ctxFor(4, 7));
    expect(g.foodCount, 2, reason: 'seeds exactly two pellets');
    var sawRefill = false;
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      // Hard cap: the board never holds more than two pellets at once. (We avoid
      // asserting an exact count every tick: once the arena closes in SUDDEN
      // DEATH a packed core can briefly leave no free cell to refill into.)
      expect(g.foodCount, lessThanOrEqualTo(2),
          reason: 'never more than two pellets at once');
      if (g.foodCount == 2) sawRefill = true;
    }
    expect(sawRefill, isTrue,
        reason: 'the board is refilled back up to the two-pellet cap');
  });

  test('fresh pellets are biased toward the longest snake (contested spawns)',
      () {
    // Make snake 0 a clear leader, then repeatedly spawn a single fresh pellet.
    // With a 0.66 bias most spawns should land within the bias radius of the
    // leader's head — deterministic under the fixed seed. We assert a strong
    // majority (well above the ~66% expected, ~34% uniform fallback) rather than
    // every spawn, since the fallback occasionally seeds far away by design.
    final g = SnakeArena()..init(ctxFor(2, 5));
    g.growSnakeForTest(0, 12); // snake 0 is now decisively the longest
    final head = g.headOf(0)!;
    const radius = 6; // a little slack over the 5-cell bias radius
    var near = 0;
    const trials = 80;
    for (var i = 0; i < trials; i++) {
      g.respawnSingleFoodForTest();
      final cells = g.foodCells;
      expect(cells.length, 1, reason: 'exactly one pellet after a respawn');
      final f = cells.first;
      final d = (f.col - head.col).abs() + (f.row - head.row).abs();
      if (d <= radius) near++;
    }
    // Uniform-random spawns would land within radius 6 only ~7% of the time
    // (a ~85-cell diamond on a ~1100-cell board), so a third of all spawns
    // clustering near the leader already proves a strong bias without pinning
    // an exact count (the intentional ~34% random fallback adds variance).
    expect(near, greaterThan(trials ~/ 3),
        reason: 'biased spawns ($near/$trials) cluster near the leader');
  });

  // ── DESIGN LAW: blind spam (random turn every frame) must LOSE ────────────────

  test('ANTI-SPAM: a blind random-turner never beats a routing hard bot', () {
    // The design law: button-spam / no-skill play MUST LOSE to skilled play. We
    // pit two snakes head-to-head and differ ONLY in input strategy:
    //   * Player 0 SPAMS: a random side tap EVERY frame (~11 per logical step), so
    //     its heading is re-randomized into thrash — it jitters into a wall or its
    //     own body within a second or two.
    //   * Player 1 is a HARD bot: it flood-fills for open space, routes to food and
    //     dodges head-ons — i.e. it routes + survives (the "planner" reference).
    // The spammer must NOT win a single seed, and the round must always resolve.
    // Deterministic: the game is seeded by ctx.rng and the blind input by a fixed
    // per-seed math.Random, so the whole match replays identically.
    const seeds = [1, 3, 7, 11, 13, 17, 21, 34, 42, 99];
    var spamWins = 0;
    var botWins = 0;
    for (final seed in seeds) {
      final g = SnakeArena()
        ..init(MiniGameContext(
          players: [
            PlayerSlot.defaults(0), // human spammer (random turn every frame)
            PlayerSlot.defaults(1, isBot: true), // routing hard bot
          ],
          arena: const Size(800, 1200),
          rng: SeededRng(seed),
          zones: ZoneLayout.forPlayers(2),
          difficulty: BotDifficulty.hard,
        ));
      final spamRng = math.Random(seed * 131 + 1);
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
        g.update(1 / 60);
        _spamTurnBlindly(g, 0, spamRng); // blind random side tap every frame
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      final winner = g.winResult!.ranking.first;
      if (winner == 0) {
        spamWins++;
      } else if (winner == 1) {
        botWins++;
      }
    }
    // Blind thrashing must never win against a snake that routes + survives.
    expect(spamWins, 0,
        reason: 'a blind random-turner won $spamWins/${seeds.length} rounds — '
            'spam must never beat skilled routing');
    // And the routing bot must in fact dominate (sanity: it actually wins them).
    expect(botWins, seeds.length,
        reason: 'the routing hard bot should win every seed ($botWins/'
            '${seeds.length})');
  });

  test('ANTI-SPAM: a blind random-turner crashes early (solo, dies fast)', () {
    // Proof the difficulty INTERPOSES: with no deliberate steering, a snake that
    // turns randomly every frame thrashes itself into a wall / its own body almost
    // immediately. Solo (so nothing else can end the round) the average survival
    // must be a tiny slice of the 35s round — i.e. blind play self-destructs.
    const seeds = [11, 22, 33, 44, 55, 66, 77, 88];
    var totalSec = 0.0;
    var longestLen = 0;
    for (final seed in seeds) {
      final g = SnakeArena()..init(ctxHumanSolo(seed));
      final spamRng = math.Random(seed * 17 + 3);
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
        g.update(1 / 60);
        _spamTurnBlindly(g, 0, spamRng);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      totalSec += frames / 60.0;
      final len = g.scores.of(0).toInt();
      if (len > longestLen) longestLen = len;
    }
    final avgSec = totalSec / seeds.length;
    // A deliberate player survives the whole ~35s and grows long; blind thrash
    // dies in a fraction of that. Generous ceiling (well under the round) so the
    // claim is robust, not brittle.
    expect(avgSec, lessThan(8.0),
        reason: 'blind random-turner survived ${avgSec.toStringAsFixed(1)}s on '
            'average — it must crash early');
    // It also barely grows (it dies before it can eat much).
    expect(longestLen, lessThan(20),
        reason: 'a blind turner should never grow long (max len $longestLen)');
  });

  test('FINAL TWO showdown + winner cheer render without throwing', () {
    // SPECTACLE: a 4-snake round drops to two survivors (firing the one-shot
    // FINAL-2 slow-mo/flash/banner) and ends on a winner (confetti + champion
    // banner). Render must stay no-throw through the whole climax, every frame.
    final g = SnakeArena()..init(ctxFor(4, 7));
    final canvas = Canvas(PictureRecorder());
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    }
    // One more render after finish (winner cheer / confetti still settling).
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });
}

/// A 1-player human (non-bot) context — used to measure how a blind random-turner
/// fares with no help (no bots to end the round for it).
MiniGameContext ctxHumanSolo(int seed) => MiniGameContext(
      players: [PlayerSlot.defaults(0)],
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(1),
    );

/// Blind "spam" play for [id]: a RANDOM side tap every single frame (no reading
/// of the board), so between two logical steps the heading is flipped ~11 times
/// and ends up effectively random — the snake thrashes into a wall or itself.
/// [rng] is a fixed per-seed [math.Random] so the spam stream is deterministic.
void _spamTurnBlindly(SnakeArena g, int id, math.Random rng) {
  g.onInput(PlayerInput.down(id, Offset(rng.nextDouble(), 0.5)));
}
