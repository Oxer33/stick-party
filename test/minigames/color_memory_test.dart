import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/color_memory/color_memory.dart';

void main() {
  MiniGameContext ctxFor(int n, int seed) => MiniGameContext(
        players: [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
      );

  void runToEnd(ColorMemory g) {
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
    }
  }

  test('four bots finish with a full ranking', () {
    final g = ColorMemory()..init(ctxFor(4, 7));
    runToEnd(g);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
    expect(g.winResult!.ranking.length, 4);
  });

  test('all-bot 4p round lasts >1.5s and finishes within the time limit', () {
    // Guards both failure modes: a bug that ends the round instantly (<1.5s) and
    // one that never resolves. The call-and-response append beats live inside the
    // rounds, so everything is still bounded by the 45s cap (+1 frame slack).
    const dt = 1 / 60;
    for (final seed in [1, 2, 3, 7, 13, 42, 99]) {
      final g = ColorMemory()..init(ctxFor(4, seed));
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
        g.update(dt);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      expect(frames * dt, greaterThan(1.5),
          reason: 'seed=$seed ended in ${(frames * dt).toStringAsFixed(2)}s '
              '(too fast — a sub-1.5s finish reads as a bug)');
      expect(frames * dt, lessThanOrEqualTo(46.0),
          reason: 'seed=$seed exceeded the time limit');
    }
  });

  test('always terminates across player counts and seeds', () {
    for (final n in [1, 2, 3, 4]) {
      for (final seed in [1, 2, 5, 42, 99]) {
        final g = ColorMemory()..init(ctxFor(n, seed));
        runToEnd(g);
        expect(g.status, MiniGameStatus.finished,
            reason: 'n=$n seed=$seed must finish');
        expect(
            g.winResult!.ranking.toSet(), {for (var p = 0; p < n; p++) p});
      }
    }
  });

  test('call-and-response grows the shared pattern past its start length', () {
    // The whole structural change: after a round is won, the WINNER appends the
    // next color (no rng auto-grow). Growth must therefore still happen — across
    // these seeds at least one all-bot match builds the pattern well beyond the
    // single starting color (a survivor's score == cleared sequence length, an
    // eliminated player's score == entries cleared, both > the start of 1).
    var bestScore = 0;
    for (final seed in [1, 2, 3, 7, 13, 42]) {
      final g = ColorMemory()..init(ctxFor(4, seed));
      runToEnd(g);
      expect(g.status, MiniGameStatus.finished);
      for (final id in g.winResult!.ranking) {
        final s = g.scores.of(id).round();
        if (s > bestScore) bestScore = s;
      }
    }
    // Start length is 1; the winner-appended growth must push the pattern up.
    expect(bestScore, greaterThan(1),
        reason: 'the winner-appended sequence must grow beyond the start');
  });

  test('solo hard bot drives the pattern into the climax (drumroll) range', () {
    // CLIMAX / progression. A lone HARD bot wins each round and appends a color
    // (deterministic via ctx.rng), so the shared pattern climbs round by round
    // into the climax length (where the show speeds up + a drumroll fires).
    // Across seeds the deepest run must reach at least the climax threshold, and
    // every run must still terminate cleanly inside the time limit.
    const climaxLen = 5; // mirrors ColorMemory._climaxSeqLen
    var deepest = 0;
    for (final seed in [0, 5, 7, 13, 42]) {
      final ctx = MiniGameContext(
        players: [PlayerSlot.defaults(0, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(1),
        difficulty: BotDifficulty.hard,
      );
      final g = ColorMemory()..init(ctx);
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      expect(frames / 60.0, greaterThan(1.5));
      expect(frames / 60.0, lessThanOrEqualTo(46.0));
      final s = g.scores.of(0).round();
      if (s > deepest) deepest = s;
    }
    expect(deepest, greaterThanOrEqualTo(climaxLen),
        reason: 'the appended pattern should reach the climax (drumroll) range');
  });

  test('tapping the colored pads directly does not throw and round resolves',
      () {
    // Players tap the real colored quadrants in their cluster via input.normPos.
    // Player 0's cluster in a 2p layout sits in the bottom band; these points
    // land in its four quadrants. Blindly cycling taps exercises pad hit-testing
    // (correct → advance, wrong → forgiven on round 1 then out) AND, if player 0
    // happens to win, the append-tap routing — the round must always resolve.
    const quadrants = <Offset>[
      Offset(0.365, 0.65), // red   (top-left)
      Offset(0.635, 0.65), // blue  (top-right)
      Offset(0.365, 0.83), // green (bottom-left)
      Offset(0.635, 0.83), // yellow(bottom-right)
    ];
    final g = ColorMemory()..init(ctxFor(2, 3));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % 9 == 0) g.onInput(PlayerInput.down(0, quadrants[(n ~/ 9) % 4]));
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
  });

  test('a positionless tap is ignored (never eliminates) and round resolves',
      () {
    // A tap with no position (origin) misses every pad, so it must be ignored
    // rather than counting as a wrong color — a fumbled touch never KO's a kid.
    // It must also be ignored during the append beat (no stray color appended).
    final g = ColorMemory()..init(ctxFor(2, 3));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % 9 == 0) g.onInput(PlayerInput.down(0));
    }
    expect(g.status, MiniGameStatus.finished);
  });

  test('render does not throw in any phase (including the append beat)', () {
    final g = ColorMemory()..init(ctxFor(4, 11));
    final canvas = Canvas(PictureRecorder());
    // Showing phase (just started).
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    // Advance into the input phase and render again.
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60);
    }
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    // Run to the end (covers the append beat + finish) rendering throughout.
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    }
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });

  // ── THE DESIGN LAW: blind pad-spam must LOSE to memory skill ─────────────────
  //
  // You cannot guess a GROWING sequence. After round 1 there is no forgiving
  // retry, so a single wrong pad ends your run — random tapping therefore dies
  // shallow, while a player/bot that actually reproduces the pattern climbs into
  // the climax depths. These tests prove that ordering deterministically (every
  // tap is driven by a seeded rng; bots act off ctx.rng), with no peeking at the
  // hidden sequence.

  // Solo (1p) plate quadrant tap points. With no render() the game's _lastSize
  // stays (1,1), so a 0..1 normPos doubles as the plate coordinate (same trick
  // the pad-tap test above relies on). The 1p region is (0.18,0.36,0.82,0.82);
  // squared + centered that plate spans (0.27,0.36)-(0.73,0.82) with center
  // (0.5,0.59), so these four points land cleanly in the four colored quadrants.
  const soloQuads = <Offset>[
    Offset(0.40, 0.47), // red    (top-left)
    Offset(0.60, 0.47), // blue   (top-right)
    Offset(0.40, 0.71), // green  (bottom-left)
    Offset(0.60, 0.71), // yellow (bottom-right)
  ];

  MiniGameContext soloCtx(int seed, {bool bot = false, BotDifficulty? diff}) =>
      MiniGameContext(
        players: [PlayerSlot.defaults(0, isBot: bot)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(1),
        difficulty: diff ?? BotDifficulty.medium,
      );

  // Run a solo BLIND SPAMMER: a human who taps a RANDOM colored quadrant every
  // [everyFrames] frames (driven by its own seeded rng so it's deterministic),
  // never watching the light show. Returns the recall depth reached (score =
  // entries cleared).
  int runBlindSpammer(int seed, {int everyFrames = 3}) {
    final g = ColorMemory()..init(soloCtx(seed));
    final tapRng = SeededRng(seed * 131 + 17);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % everyFrames == 0) {
        g.onInput(PlayerInput.down(0, soloQuads[tapRng.intRange(0, 4)]));
      }
    }
    expect(g.status, MiniGameStatus.finished, reason: 'spammer run must finish');
    return g.scores.of(0).round();
  }

  // Run a solo HARD bot (a competent reference player that reproduces patterns
  // and appends colors, climbing round by round). Returns its recall depth.
  int runSkilledBot(int seed) {
    final g =
        ColorMemory()..init(soloCtx(seed, bot: true, diff: BotDifficulty.hard));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished, reason: 'bot run must finish');
    return g.scores.of(0).round();
  }

  test('a blind pad-spammer dies SHALLOW — never near the climax depth', () {
    // Across a seed sweep the deepest a random tapper ever reaches must stay well
    // short of the climax length: with no post-round-1 retry, random taps cannot
    // survive a growing pattern. This is the "spam cannot luck into a deep run".
    const climaxLen = 5; // mirrors ColorMemory._climaxSeqLen
    var deepestSpam = 0;
    for (final seed in [1, 2, 3, 4, 5, 7, 11, 13, 42, 99, 123, 777]) {
      final d = runBlindSpammer(seed);
      if (d > deepestSpam) deepestSpam = d;
    }
    // Sanity: spamming is allowed to clear the forgiving round 1 sometimes, so a
    // shallow depth is expected — but it must never approach the climax depth a
    // real memoriser reaches.
    expect(deepestSpam, lessThan(climaxLen),
        reason: 'random tapping reached depth $deepestSpam — it must stay short '
            'of the climax ($climaxLen); a growing pattern cannot be guessed');
  });

  test('DESIGN LAW: memory skill DOMINATES blind spam in recall depth', () {
    // The core ordering, proven in aggregate over a seed sweep so a rare bot
    // early-slip can never flip the result: a competent reproducer (HARD bot)
    // reaches FAR deeper total recall than a blind spammer. Solo runs, fully
    // deterministic (bot acts off ctx.rng; spammer off its own seeded rng).
    const seeds = [1, 2, 3, 5, 7, 13, 42, 99, 256];
    var spamSum = 0;
    var skilledSum = 0;
    var deepestSkilled = 0;
    for (final seed in seeds) {
      spamSum += runBlindSpammer(seed);
      final s = runSkilledBot(seed);
      skilledSum += s;
      if (s > deepestSkilled) deepestSkilled = s;
    }
    // The memoriser reaches the climax depths; the spammer never gets close.
    expect(deepestSkilled, greaterThanOrEqualTo(5),
        reason: 'the reproducing bot should climb into the climax depth');
    // Total recall is not a near thing — skill should multiply spam, not edge it.
    expect(skilledSum, greaterThan(spamSum * 2),
        reason: 'pattern-reproducing recall ($skilledSum) must dominate blind '
            'spam recall ($spamSum), not merely beat it');
  });

  test('DESIGN LAW: a blind spammer loses head-to-head to a real player '
      '(memoriser wins the field, spammer never takes a deep lead)', () {
    // Head-to-head, 2 players: P0 is a blind human spammer (random pad every few
    // frames, own seeded rng), P1 is a HARD bot that reproduces the pattern. The
    // spammer acts immediately while the bot waits a reaction beat, so the spammer
    // reaches its fatal wrong pad first and is knocked out early almost every
    // round. Proven in aggregate (robust to a rare single-seed bot slip):
    //  * the bot's recall depth dominates the spammer's by a wide margin;
    //  * the bot wins the overwhelming majority of matches (not a coin flip);
    //  * the spammer never finishes with a CLIMAX-deep score — it cannot ride a
    //    growing pattern by luck even when it happens to take a round.
    const p0Quads = <Offset>[
      // 2p layout, player index 0 sits in the bottom band; plate (with no render)
      // spans (0.32,0.56)-(0.68,0.92), center (0.5,0.74).
      Offset(0.40, 0.64), // red
      Offset(0.60, 0.64), // blue
      Offset(0.40, 0.84), // green
      Offset(0.60, 0.84), // yellow
    ];
    var botWins = 0;
    var spamSum = 0;
    var botSum = 0;
    var deepestSpam = 0;
    const seeds = [1, 2, 3, 4, 5, 7, 11, 13, 42, 99, 123, 777, 2024];
    for (final seed in seeds) {
      final ctx = MiniGameContext(
        players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(2),
        difficulty: BotDifficulty.hard,
      );
      final g = ColorMemory()..init(ctx);
      final tapRng = SeededRng(seed * 977 + 3);
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
        g.update(1 / 60);
        if (n % 3 == 0) {
          g.onInput(PlayerInput.down(0, p0Quads[tapRng.intRange(0, 4)]));
        }
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      if (g.winResult!.ranking.first == 1) botWins++;
      final spam = g.scores.of(0).round();
      spamSum += spam;
      botSum += g.scores.of(1).round();
      if (spam > deepestSpam) deepestSpam = spam;
    }
    // The spammer can never luck into a deep run, even across a full sweep.
    expect(deepestSpam, lessThan(5),
        reason: 'a blind spammer reached depth $deepestSpam — it must never ride '
            'a growing pattern into the climax range by luck');
    // Aggregate dominance (robust to a rare single-seed bot slip).
    expect(botSum, greaterThan(spamSum * 2),
        reason: 'the memoriser ($botSum) must out-recall the spammer ($spamSum) '
            'by a wide margin');
    expect(botWins, greaterThanOrEqualTo((seeds.length * 0.8).ceil()),
        reason: 'the reproducing bot should win the overwhelming majority '
            '($botWins/${seeds.length})');
  });
}
