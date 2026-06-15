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

  // ── CONFIDENCE REWARD: the fast-recall STREAK ────────────────────────────────
  //
  // Winning a round (first to reproduce the whole pattern) builds a streak that
  // adds a SUB-INTEGER flair to the final score. It must (a) actually reward a
  // repeat front-runner with a fraction on top of recall depth, (b) be bounded
  // well under 0.5 so it can NEVER round a score up across a depth threshold
  // (otherwise blind spam could ride a streak into the climax range), and (c)
  // leave the integer recall depth — what every depth/spam assertion reads via
  // .round() — completely unchanged.

  test('a surviving round-winner earns a sub-integer streak bonus on top of '
      'depth (and the flair never rounds the depth up)', () {
    // In an all-bot match the LAST player standing is a repeat round-winner who
    // never got KO'd, so its streak survives to the finish and adds a fractional
    // flair on top of its recall depth. A KO snaps a streak (so a knocked-out
    // player shows none) — hence we scan the field and require the bonus to show
    // for at least one finisher across the seed sweep. Every score's integer part
    // (what the depth/spam tests read via .round()) must be left untouched.
    var sawBonus = false;
    for (final seed in [1, 2, 3, 7, 13, 42]) {
      final g = ColorMemory()..init(ctxFor(4, seed));
      runToEnd(g);
      expect(g.status, MiniGameStatus.finished);
      for (final id in g.winResult!.ranking) {
        final raw = g.scores.of(id).toDouble();
        final frac = raw - raw.floor();
        // The bonus is bounded under 0.5 (it can never tip .round() up a depth).
        expect(frac, lessThan(0.5),
            reason: 'seed=$seed p$id streak flair $frac must stay below 0.5');
        // The integer recall depth (what spam/depth tests read) is unaffected.
        expect(raw.round(), raw.floor(),
            reason: 'seed=$seed p$id flair must not round the depth up');
        if (frac > 0) sawBonus = true;
      }
    }
    expect(sawBonus, isTrue,
        reason: 'a surviving repeat round-winner should carry a streak bonus');
  });

  test('STREAK SAFETY: the bonus never lifts a shallow run across the climax',
      () {
    // The spam-safety guarantee for the NEW scoring: even with the streak flair
    // folded in, a blind spammer's RAW score (not just its .round()) can never
    // reach the climax depth. A growing pattern cannot be guessed, and the
    // bounded sub-integer streak bonus cannot bridge the gap.
    const climaxLen = 5; // mirrors ColorMemory._climaxSeqLen
    var deepestRawSpam = 0.0;
    for (final seed in [1, 2, 3, 4, 5, 7, 11, 13, 42, 99, 123, 777]) {
      final g = ColorMemory()..init(soloCtx(seed));
      final tapRng = SeededRng(seed * 131 + 17);
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
        g.update(1 / 60);
        if (n % 3 == 0) {
          g.onInput(PlayerInput.down(0, soloQuads[tapRng.intRange(0, 4)]));
        }
      }
      expect(g.status, MiniGameStatus.finished);
      final raw = g.scores.of(0).toDouble();
      if (raw > deepestRawSpam) deepestRawSpam = raw;
    }
    expect(deepestRawSpam, lessThan(climaxLen.toDouble()),
        reason: 'a blind spammer reached raw depth $deepestRawSpam — even with '
            'the streak bonus it must stay short of the climax ($climaxLen)');
  });

  test('the streak crowns ONE player: a head-to-head winner out-scores the '
      'spammer by more than a lone streak flair', () {
    // The streak is competitive, not a participation trophy: a KO snaps it, and
    // only the round-winner keeps it. Head-to-head (blind spammer P0 vs HARD bot
    // P1), the bot both out-recalls the spammer AND banks the streak — so its
    // margin is wider than any sub-integer flair alone, proving recall (not the
    // bonus) decides the match while the streak is a real edge on top.
    const p0Quads = <Offset>[
      // 2p layout, player 0 plate (no render → _lastSize 1x1) center (0.5,0.74).
      Offset(0.40, 0.64), // red
      Offset(0.60, 0.64), // blue
      Offset(0.40, 0.84), // green
      Offset(0.60, 0.84), // yellow
    ];
    var botAheadEverywhere = true;
    for (final seed in [1, 2, 3, 5, 7, 13, 42]) {
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
      expect(g.status, MiniGameStatus.finished);
      final spam = g.scores.of(0).toDouble();
      final bot = g.scores.of(1).toDouble();
      // The margin exceeds 1 full point — i.e. it is a recall-depth gap, not a
      // mere fractional streak flair edging the result.
      if (bot - spam <= 1.0) botAheadEverywhere = false;
    }
    expect(botAheadEverywhere, isTrue,
        reason: 'the memoriser must lead by a full recall point, not a flair');
  });

  // ══ COMPETITIVE: skill gradient + beatable-but-tough hard bot ════════════════
  //
  // The blind-spam laws above prove memory skill beats NO skill. This block
  // proves the harder claim: against a REALISTIC SKILLED HUMAN the bots form a
  // real difficulty gradient — easy is clearly beatable, hard is tough but never
  // a wall or a pushover. Color Memory is last-player-standing, so the contest is
  // "who's recall lapses first": the human must out-survive the bot's per-round
  // slip plan ([ColorMemory._rollBotMistakeStep], scaled by BotProfile.errorRate).
  //
  // ── The realistic skilled-human model (seat 0) ──────────────────────────────
  // A perfect-recall human would trivially outlast every bot (≈100% at all
  // difficulties = a degenerate flat gradient — confirmed in measurement at
  // pRecall=1.0). So seat 0 is modelled as a HIGH-but-IMPERFECT memoriser:
  //   * it WATCHED the light show, so it knows the sequence (via debugSequence) —
  //     exactly the information a human at the table has;
  //   * it recalls each color independently with probability [_pRecall] = 0.95
  //     (< 1): the chance it clears a length-L pattern is 0.95^(L-1), decaying
  //     with depth, so depth genuinely contests the bots instead of trivialising
  //     them;
  //   * round 1 (length 1) is cleared reliably (the game's forgiving retry);
  //   * it reproduces FAST — a tap every 3 frames during the input phase — so it
  //     generally answers before the bots (which hold the first answer a beat),
  //     the skilled-human reaction edge the game already assumes;
  //   * when it wins a round it taps a color in the append beat to keep building.
  // Fully deterministic (its recall / wrong-pad / append choices run off their own
  // seeded RNGs), so this whole gradient is reproducible frame-for-frame.
  //
  // ── Why 1v1 ─────────────────────────────────────────────────────────────────
  // The duel isolates the human-vs-ONE-bot contest with the clearest read (no
  // third-party KO order muddying the survival race) and is the canonical PvP
  // shape. Measured win-rates @ pRecall=0.95 over three disjoint 12-seed windows:
  //   easy   0.75 / 0.83 / 0.75
  //   medium 0.75 / 0.83 / 0.58
  //   hard   0.50 / 0.50 / 0.50
  // The bands below are robust supersets of those values, asserted on the two
  // disjoint windows used here (the third window was a measurement cross-check).
  const pRecall = 0.95;

  // Seat-0 plate quadrants in a 2p layout (player 0 sits in the bottom band;
  // with no render() _lastSize stays 1x1, so normPos doubles as the plate coord).
  // slot 0=red(TL) 1=blue(TR) 2=green(BL) 3=yellow(BR).
  const duelQuads = <Offset>[
    Offset(0.40, 0.64),
    Offset(0.60, 0.64),
    Offset(0.40, 0.84),
    Offset(0.60, 0.84),
  ];

  // One 1v1 match: realistic skilled human (seat 0) vs one bot of [diff].
  // Returns true iff the human finishes first in the ranking (wins the match).
  bool skilledHumanWins(int seed, BotDifficulty diff) {
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(2),
      difficulty: diff,
    );
    final g = ColorMemory()..init(ctx);
    final recallRng = SeededRng(seed * 7919 + 13);
    final wrongRng = SeededRng(seed * 104729 + 7);
    final appendRng = SeededRng(seed * 1299709 + 5);

    var n = 0;
    var lastTapStep = -1; // commit at most one tap per step (wait for it to land)
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % 3 != 0) continue;
      if (g.debugInputPhase && g.debugAlive0) {
        final seq = g.debugSequence;
        final step = g.debugProgress0;
        if (step >= seq.length) continue; // already cleared this round
        if (step == lastTapStep) continue; // our last tap hasn't resolved yet
        lastTapStep = step;
        // Round 1 is cleared reliably; deeper rounds recall each color with
        // probability pRecall (an imperfect memoriser).
        final correct = seq.length <= 1 || recallRng.next() < pRecall;
        final want = seq[step];
        final slot = correct ? want : (want + 1 + wrongRng.intRange(0, 3)) % 4;
        g.onInput(PlayerInput.down(0, duelQuads[slot]));
      } else if (g.debugAppendPhase && g.debugAppenderId == 0) {
        // Won the round → append any color (cosmetic for balance; grows either way).
        g.onInput(PlayerInput.down(0, duelQuads[appendRng.intRange(0, 4)]));
        lastTapStep = -1;
      } else {
        lastTapStep = -1;
      }
    }
    expect(g.status, MiniGameStatus.finished,
        reason: 'seed=$seed diff=${diff.name} must finish');
    return g.winResult!.ranking.first == 0;
  }

  // Win-rate of the realistic skilled human vs [diff] over a seed [window].
  double winRate(List<int> window, BotDifficulty diff) {
    var wins = 0;
    for (final seed in window) {
      if (skilledHumanWins(seed, diff)) wins++;
    }
    return wins / window.length;
  }

  // Two DISJOINT 12-seed windows (≥12 each). Every assertion runs on both, so a
  // band only passes if it holds on independent seed sets (robust, not cherry-
  // picked). 12 ≥ the required floor.
  const windowA = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  const windowB = [13, 14, 15, 42, 99, 123, 256, 777, 2024, 31, 57, 88];

  test('COMPETITIVE: EASY is clearly beatable (win-rate ≥ 0.70, both windows)',
      () {
    for (final window in [windowA, windowB]) {
      final wr = winRate(window, BotDifficulty.easy);
      expect(wr, greaterThanOrEqualTo(0.70),
          reason: 'a skilled human must clearly beat the EASY bot '
              '(got ${wr.toStringAsFixed(2)} on window starting ${window.first})');
    }
  });

  test('COMPETITIVE: HARD is beatable-but-tough (win-rate in [0.15, 0.90], both '
      'windows — not a wall, not a pushover)', () {
    for (final window in [windowA, windowB]) {
      final wr = winRate(window, BotDifficulty.hard);
      expect(wr, greaterThanOrEqualTo(0.15),
          reason: 'the HARD bot must not be an unbeatable wall '
              '(got ${wr.toStringAsFixed(2)} on window starting ${window.first})');
      expect(wr, lessThanOrEqualTo(0.90),
          reason: 'the HARD bot must not be a trivial pushover '
              '(got ${wr.toStringAsFixed(2)} on window starting ${window.first})');
    }
  });

  test('COMPETITIVE: a clean difficulty GRADIENT (winEasy ≥ winMedium ≥ winHard '
      'and winEasy > winHard)', () {
    for (final window in [windowA, windowB]) {
      final e = winRate(window, BotDifficulty.easy);
      final m = winRate(window, BotDifficulty.medium);
      final h = winRate(window, BotDifficulty.hard);
      // Monotone non-increasing across difficulty. A one-seed tolerance (≈0.083)
      // on the adjacent easy≥medium / medium≥hard steps absorbs single-seed noise
      // where two tiers measure equal, without admitting an inverted gradient.
      const slack = 1.0 / 12 + 1e-9;
      expect(e, greaterThanOrEqualTo(m - slack),
          reason: 'easy ($e) must not rank below medium ($m) — window '
              '${window.first}');
      expect(m, greaterThanOrEqualTo(h - slack),
          reason: 'medium ($m) must not rank below hard ($h) — window '
              '${window.first}');
      // The end-to-end gradient is decisive (no tolerance): easy clearly tops hard.
      expect(e, greaterThan(h),
          reason: 'easy ($e) must beat the field more often than hard ($h) — '
              'window ${window.first}');
    }
  });

  test('COMPETITIVE: not luck-dominated — the skilled human beats EASY reliably, '
      'yet outcomes still VARY (no runaway)', () {
    // Reliability: a clear majority of EASY matches go to the human on BOTH
    // windows (already enforced ≥0.70 above; restated as the "skill, not luck"
    // claim). Variety: across the full 24-seed sweep the human neither always
    // wins nor always loses to the HARD bot — the result is genuinely contested,
    // so the gradient is a real spread of outcomes, not a fixed coin.
    var easyWinsAll = 0, easyN = 0;
    var hardWins = 0, hardN = 0;
    for (final window in [windowA, windowB]) {
      for (final seed in window) {
        easyN++;
        if (skilledHumanWins(seed, BotDifficulty.easy)) easyWinsAll++;
        hardN++;
        if (skilledHumanWins(seed, BotDifficulty.hard)) hardWins++;
      }
    }
    expect(easyWinsAll / easyN, greaterThan(0.5),
        reason: 'vs EASY the skilled human wins the clear majority '
            '($easyWinsAll/$easyN) — skill, not luck');
    // No runaway in either direction vs HARD: some wins, some losses.
    expect(hardWins, greaterThan(0),
        reason: 'the human must take at least some HARD matches (not a wall)');
    expect(hardWins, lessThan(hardN),
        reason: 'the human must NOT sweep every HARD match (not a pushover)');
  });
}
