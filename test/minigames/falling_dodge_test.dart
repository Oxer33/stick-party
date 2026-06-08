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
}
