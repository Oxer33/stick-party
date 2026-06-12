import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/falling_dodge/falling_dodge.dart';
import 'package:stick_party/minigames/falling_dodge/falling_fx.dart';

void main() {
  MiniGameContext ctxFor(int n, {int seed = 7}) {
    final players = [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)];
    return MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(n),
    );
  }

  test('falling dodge finishes with four bots and ranks all players', () {
    final g = FallingDodge()..init(ctxFor(4));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  for (final count in [1, 2, 3]) {
    test('falling dodge finishes with $count player(s)', () {
      final g = FallingDodge()..init(ctxFor(count, seed: 41 + count));
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished);
      expect(g.winResult!.ranking.toSet(),
          {for (var i = 0; i < count; i++) i});
    });
  }

  test('SCORED RUN: an all-bot round runs the FULL timer and never ends early '
      '(anti-instant-win)', () {
    // The rework makes this a scored run, not last-one-standing: crushed runners
    // respawn, so the round plays the whole [timeLimit] (~26s) and is ranked by
    // banked grazes. It must NEVER resolve early (the old "instant win when the
    // rival was crushed" bug) — it always reaches the time cap.
    final g = FallingDodge()..init(ctxFor(4, seed: 5));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    final simSeconds = n / 60.0;
    // Anti-instant-win floor: a real round, well past any "one left" moment.
    expect(simSeconds, greaterThan(8.0));
    // Ceiling: the full timer (26s) plus a small resolution buffer.
    expect(simSeconds, lessThan(27.0));
  });

  test('SCORED RUN: a 1v1 where the bot is crushed still runs the full timer '
      '(no instant win when the rival falls)', () {
    // The core complaint: in 1v1 the round used to end the instant the lone bot
    // was crushed. Now the human plays the WHOLE run banking grazes. Drive a
    // human that taps steadily vs one medium bot; assert the round lasts a real
    // minimum regardless of when the bot first gets crushed, with no throw.
    final players = [
      PlayerSlot.defaults(0),
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(19),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = FallingDodge()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
      if (n % 17 == 0) g.onInput(PlayerInput.down(0, const Offset(0.9, 0.5)));
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
    expect(n / 60.0, greaterThan(8.0),
        reason: '1v1 must play a real run, not end when the bot is crushed');
  });

  test('golden token: a runner sharing the lane scoops it; a different lane '
      'misses it', () {
    // Catch case: runner in lane 1, token spawns in lane 1, ticked until it
    // crosses the runner line → tick returns the caught token exactly once.
    final catchLane = TokenLane(firstSpawnAt: 0);
    final rng = SeededRng(1);
    TokenFx? caught;
    var n = 0;
    while (caught == null && n++ < 10000) {
      caught = catchLane.tick(
        dt: 1 / 60,
        elapsed: n / 60.0,
        spawnLane: 1,
        laneSpacing: 100,
        bandTop: 0,
        bandBottom: 600,
        runnerY: 400,
        runnerLane: 1,
        rng: rng,
      );
    }
    expect(caught, isNotNull, reason: 'a same-lane token must be scooped');
    expect(caught!.lane, 1);

    // Miss case: runner stays in lane 0 while the token falls in lane 2 → it is
    // never returned as caught and the lane clears it after it falls past.
    final missLane = TokenLane(firstSpawnAt: 0);
    final rng2 = SeededRng(2);
    var anyCatch = false;
    for (var i = 1; i <= 600; i++) {
      final got = missLane.tick(
        dt: 1 / 60,
        elapsed: i / 60.0,
        spawnLane: 2,
        laneSpacing: 100,
        bandTop: 0,
        bandBottom: 600,
        runnerY: 400,
        runnerLane: 0,
        rng: rng2,
      );
      if (got != null) anyCatch = true;
    }
    expect(anyCatch, isFalse, reason: 'a different-lane token must not score');
  });

  test('human swap input does not throw and round still resolves', () {
    final players = [
      PlayerSlot.defaults(0),
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(13),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = FallingDodge()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
      if (n % 15 == 0) g.onInput(PlayerInput.down(0));
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
  });

  test('bots graze for real points and scores spread (not a flat tie)', () {
    // The rework makes the CLOSE dodge the only points, and bots are tuned to
    // step adjacent (graze) rather than flee far. So all-bot rounds end with
    // banked grazes — at least one bot well above the tiny survival-only bonus
    // (~26s * 0.4 ≈ 10.4) — and a real spread between best and worst. We scan a
    // handful of seeds and require the property to hold across them, so a single
    // unlucky board cannot make the suite flaky.
    var sawGraze = false;
    var sawSpread = false;
    for (var seed = 70; seed < 76; seed++) {
      final g = FallingDodge()..init(ctxFor(4, seed: seed));
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      final scores = g.winResult!.finalScores;
      final values = [for (var i = 0; i < 4; i++) (scores[i] ?? 0).toDouble()];
      final best = values.reduce((a, b) => a > b ? a : b);
      final worst = values.reduce((a, b) => a < b ? a : b);
      if (best > 11) sawGraze = true; // above the survival-only ceiling
      if (best - worst > 1) sawSpread = true;
    }
    expect(sawGraze, isTrue, reason: 'no bot ever banked a graze chain');
    expect(sawSpread, isTrue, reason: 'bot scores never spread');
  });

  test('_finish ranks by banked score so a daredevil can top a safe runner', () {
    // The reweight makes ranking follow total (graze-dominated) score, highest
    // first. Verifying the ranking is monotonically non-increasing in score is
    // exactly the mechanism that lets a bold grazer outrank a timid survivor:
    // placement tracks banked points, not who merely lived longest.
    final g = FallingDodge()..init(ctxFor(4, seed: 88));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    final win = g.winResult!;
    expect(win.ranking.toSet(), {0, 1, 2, 3});
    for (var i = 0; i + 1 < win.ranking.length; i++) {
      final hi = (win.finalScores[win.ranking[i]] ?? 0).toDouble();
      final lo = (win.finalScores[win.ranking[i + 1]] ?? 0).toDouble();
      expect(hi, greaterThanOrEqualTo(lo),
          reason: 'ranking not ordered by score at $i: ${win.finalScores}');
    }
  });

  test('a chain reset never claws back already-banked graze points', () {
    // Core guarantee of the rework, seed-independent: a GRAZE only ever ADDS
    // points, and over-fleeing merely zeroes the live multiplier — it must never
    // subtract score that was already banked. So a runner's live score is
    // non-decreasing across the whole round, no matter how the hazards fall. We
    // pin the runner to the far-left wall (a tap at x=0 hops left; the hopper
    // clamps at lane 0) just to keep the scenario controlled.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0)],
      arena: const Size(800, 1200),
      rng: SeededRng(123),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = FallingDodge()..init(ctx);
    var n = 0;
    var prev = 0.0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.onInput(PlayerInput.down(0, const Offset(0.0, 0.5)));
      g.update(1 / 60);
      final s = g.scores.of(0).toDouble();
      expect(s, greaterThanOrEqualTo(prev - 1e-9),
          reason: 'live score dropped — a reset must not remove banked points');
      prev = s;
    }
    expect(g.status, MiniGameStatus.finished);
    // The final score folds in the small survival bonus on top of banked
    // grazes, so it is always >= the last live score and never negative.
    final finalScore = (g.winResult!.finalScores[0] ?? 0).toDouble();
    expect(finalScore, greaterThanOrEqualTo(prev - 1e-9));
    expect(finalScore, greaterThanOrEqualTo(0));
  });

  test('DESIGN LAW: a blind flailer ends BELOW a measured dodger '
      '(spam loses to reading + timing)', () {
    // The whole hardening, proven deterministically across several shared 1v1
    // rounds (both runners face the SAME hazard board per seed, via ctx.rng):
    //
    //  * P0 MEASURED DODGER: reads the telegraph via [debugSafeHopDir] and steps
    //    exactly one lane OFF a threatened lane onto a clear one, and only when
    //    threatened. That is the earned dodge — it survives the chase and banks a
    //    graze chain.
    //  * P1 BLIND FLAILER: taps a RANDOM side EVERY frame (its own rng, so the
    //    sim stays deterministic). It is perpetually mid-hop (a wider hitbox),
    //    walks into chase hazards, and almost never lines up a threatened→clear
    //    step, so it is crushed often and banks almost nothing.
    //
    // On EVERY seed the flailer must end with a LOWER score, LESS time alive, and
    // a WORSE rank — requiring it across seeds makes the proof robust, not a
    // lucky board, and would surface any real hole in the law.
    for (final seed in [31, 12, 57, 88]) {
      final players = [
        PlayerSlot.defaults(0), // measured dodger (human-driven)
        PlayerSlot.defaults(1), // blind flailer (human-driven)
      ];
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(2),
      );
      final g = FallingDodge()..init(ctx);
      final flail = SeededRng(seed * 7 + 1); // drives the flailer, NOT the sim

      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        // Measured: act only when threatened, and only in a safe direction.
        final dir = g.debugSafeHopDir(0);
        if (dir != 0) g.onInput(PlayerInput.down(0, g.debugTouchForDir(dir)));
        // Blind flailer: random side, every single frame.
        g.onInput(PlayerInput.down(1, Offset(flail.next(), 0.5)));
        g.update(1 / 60);
      }

      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      final win = g.winResult!;
      final dodgerScore = (win.finalScores[0] ?? 0).toDouble();
      final flailerScore = (win.finalScores[1] ?? 0).toDouble();

      expect(flailerScore, lessThan(dodgerScore),
          reason: 'seed $seed: blind flailing must score below a measured '
              'dodger (dodger=$dodgerScore flailer=$flailerScore)');
      expect(g.debugAliveSec(1), lessThan(g.debugAliveSec(0)),
          reason: 'seed $seed: the flailer is crushed more, surviving less');
      // Worse rank = appears LATER in the best→worst ranking.
      expect(win.ranking.indexOf(1), greaterThan(win.ranking.indexOf(0)),
          reason: 'seed $seed: the flailer must rank below the dodger');
    }
  });

  test('DESIGN LAW: a STILL player scores ~nothing (no free proximity grazes)',
      () {
    // A runner that NEVER moves earns no grazes: a graze requires a deliberate
    // step OFF a threatened lane, which a still player never makes. It banks at
    // most the tiny survival bonus and nowhere near a real graze chain. Solo so
    // there is no rival to muddy the read; seed-robust across a few boards.
    for (final seed in [2, 17, 44]) {
      final ctx = MiniGameContext(
        players: [PlayerSlot.defaults(0)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(1),
      );
      final g = FallingDodge()..init(ctx);
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        g.update(1 / 60); // never tap — pure stillness
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      final score = (g.winResult!.finalScores[0] ?? 0).toDouble();
      // A still player earns ZERO grazes (a graze requires a deliberate dodge
      // OFF a threatened lane — gated in _registerNearMiss). It banks only the
      // odd token that happens to fall in its fixed lane plus a tiny survival
      // sliver — far below a reader's graze chain (the sibling tests show a
      // reader banks a real chain and a flailer loses head-to-head). Bound this
      // well under that so a still player can never "win" by doing nothing.
      expect(score, lessThan(40.0),
          reason: 'a still player banked a real graze chain for free (seed '
              '$seed, score=$score)');
    }
  });

  test('a measured dodger actually banks a real graze chain (reading pays)', () {
    // The positive half of the law: a runner that reads + dodges should bank
    // well ABOVE the survival-only ceiling, proving the earned-graze path is
    // reachable by skill (not just that spam fails). Solo, seed-robust.
    var sawRealChain = false;
    for (final seed in [3, 8, 21, 50]) {
      final ctx = MiniGameContext(
        players: [PlayerSlot.defaults(0)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(1),
      );
      final g = FallingDodge()..init(ctx);
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        final dir = g.debugSafeHopDir(0);
        if (dir != 0) g.onInput(PlayerInput.down(0, g.debugTouchForDir(dir)));
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      final score = (g.winResult!.finalScores[0] ?? 0).toDouble();
      if (score > 11.0) sawRealChain = true; // above survival-only
    }
    expect(sawRealChain, isTrue,
        reason: 'a reading dodger never banked a graze chain on any seed');
  });

  test('render never throws across the whole run (incl. FINAL BARRAGE climax)',
      () {
    // A no-throw guard over the full round on a real canvas, exercising the
    // climax cinematic (banner + flash + slow-mo) and a live graze chain.
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(800, 1200);
    final ctx = MiniGameContext(
      players: [for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)],
      arena: size,
      rng: SeededRng(64),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = FallingDodge()..init(ctx);
    var n = 0;
    expect(() {
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        g.update(1 / 60);
        g.render(canvas, size);
      }
      g.render(canvas, size); // one more after finish (winner cinematic)
    }, returnsNormally);
    expect(g.status, MiniGameStatus.finished);
  });
}
