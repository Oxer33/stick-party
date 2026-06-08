import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/catch_the_star/catch_the_star.dart';

void main() {
  MiniGameContext ctxFor(int n, int seed) => MiniGameContext(
        players: [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
      );

  void runToEnd(CatchTheStar g) {
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
    }
  }

  test('four bots finish with a full ranking', () {
    final g = CatchTheStar()..init(ctxFor(4, 7));
    runToEnd(g);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('all-bot 4p round lasts >1.5s and finishes within the time limit', () {
    // Guards a regression that would end the round early or never. The round is
    // a fixed 30s sprint, so we assert it spans (1.5s, 31s].
    const dt = 1 / 60;
    for (final seed in [1, 2, 3, 7, 21]) {
      final g = CatchTheStar()..init(ctxFor(4, seed));
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
        g.update(dt);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      expect(frames * dt, greaterThan(1.5), reason: 'seed=$seed ended too fast');
      expect(frames * dt, lessThanOrEqualTo(31.0),
          reason: 'seed=$seed exceeded the time limit');
    }
  });

  test('finishes for 1..3 players', () {
    for (final n in [1, 2, 3]) {
      final g = CatchTheStar()..init(ctxFor(n, 13 + n));
      runToEnd(g);
      expect(g.status, MiniGameStatus.finished, reason: 'n=$n');
      expect(g.winResult!.ranking.toSet(), {for (var p = 0; p < n; p++) p});
    }
  });

  test('bots accumulate at least some catches over a full round', () {
    final g = CatchTheStar()..init(ctxFor(4, 21));
    runToEnd(g);
    final total = [for (var p = 0; p < 4; p++) g.scores.of(p)]
        .fold<num>(0, (a, b) => a + b);
    expect(total, greaterThan(0));
  });

  test('render does not throw', () {
    final g = CatchTheStar()..init(ctxFor(3, 4));
    final canvas = Canvas(PictureRecorder());
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    g.update(1 / 60);
    g.onInput(PlayerInput.down(0, const Offset(0.25, 0.75)));
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });

  test('GOLD RUSH flurry: the final window still scores hard (climax)', () {
    // CLIMAX mechanic. A solo human parked on the 1p catcher anchor (the zone
    // center) taps every frame, so it snatches whatever spawns. We snapshot the
    // score the moment the flurry begins (the last 7s of the 30s round) and
    // require a meaningful score gain across that flurry — i.e. the finish is a
    // live gold storm rather than a dead tail.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0)], // lone human; catcher at (0.5, 0.5)
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = CatchTheStar()..init(ctx);
    const tapAt = Offset(0.5, 0.5);

    var frames = 0;
    num scoreAtFlurryStart = -1;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
      g.update(1 / 60);
      g.onInput(PlayerInput.down(0, tapAt));
      // The flurry is the last 7s of the 30s round → starts at ~23s.
      if (scoreAtFlurryStart < 0 && frames / 60.0 >= 23.0) {
        scoreAtFlurryStart = g.scores.of(0);
      }
    }
    expect(g.status, MiniGameStatus.finished);
    expect(scoreAtFlurryStart, greaterThanOrEqualTo(0));
    expect(g.scores.of(0) - scoreAtFlurryStart, greaterThan(0),
        reason: 'the GOLD RUSH flurry must keep scoring to the very end');
  });

  test('finishes within the limit with constant tapping (flurry on)', () {
    // The end flurry must not break termination: still a fixed ~30s sprint.
    final g = CatchTheStar()..init(ctxFor(4, 21));
    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
      g.update(1 / 60);
      g.onInput(PlayerInput.down(0, const Offset(0.25, 0.75)));
    }
    expect(g.status, MiniGameStatus.finished);
    expect(frames / 60.0, greaterThan(1.5));
    expect(frames / 60.0, lessThanOrEqualTo(31.0));
  });
}
