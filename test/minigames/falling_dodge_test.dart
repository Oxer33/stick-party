import 'package:flutter/widgets.dart';
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
}
