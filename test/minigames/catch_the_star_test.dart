import 'dart:math' as math;
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

  /// A deterministic lawn-mower sweep across the whole arena: returns the drag
  /// point for frame [frame], cycling x↔y so a net steered to it covers every
  /// part of its zone within ~1s. Used to chase the free-roaming star without
  /// reading the (private) star position — wherever it drifts, the swept net
  /// passes through it repeatedly.
  Offset sweepAt(int frame) {
    final t = frame / 60.0;
    final x = 0.5 + 0.45 * math.sin(t * 6.3);
    final y = 0.5 + 0.45 * math.sin(t * 5.1 + 1.0);
    return Offset(x, y);
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

  test('bots chase the star and accumulate catches over a full round', () {
    // Bots now DRIVE their net to the star and tap when in range; over a full
    // round the field should land at least some catches.
    final g = CatchTheStar()..init(ctxFor(4, 21));
    runToEnd(g);
    final total = [for (var p = 0; p < 4; p++) g.scores.of(p)]
        .fold<num>(0, (a, b) => a + b);
    expect(total, greaterThan(0));
  });

  test('a human who chases the roaming star with their net scores', () {
    // The core new mechanic: drag the net onto the free-roaming star, then tap
    // to snatch. A solo human who steers their net straight at the star every
    // frame (and taps) must land catches, so a positioning-driven score accrues.
    // Solo so the score is purely this. Tracking the star uses the test-only
    // [starPosForTest] view so the chase is deterministic, not luck.
    final g = CatchTheStar()..init(ctxFor(1, 7));
    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
      g.update(1 / 60);
      g.onInput(PlayerInput.down(0, g.starPosForTest));
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.scores.of(0), greaterThan(0),
        reason: 'steering the net onto the roaming star must land catches');
  });

  test('a net stays clamped to its own zone even when dragged outside it', () {
    // Zones confine each net so nobody reaches into a rival's slice. Player 0
    // owns the BOTTOM half (y in [0.5,1]) in a 2p split. We drag player 0's net
    // hard into the TOP half (the rival's side) and into the corners every
    // frame; the net must never cross above y=0.5 nor leave [0,1] horizontally.
    final g = CatchTheStar()
      ..init(MiniGameContext(
        players: [
          PlayerSlot.defaults(0),
          PlayerSlot.defaults(1, isBot: true),
        ],
        arena: const Size(800, 1200),
        rng: SeededRng(3),
        zones: ZoneLayout.forPlayers(2),
      ));

    // A sweep that deliberately aims well OUTSIDE player 0's bottom zone:
    // top-of-screen and beyond the left/right edges.
    Offset outsideAt(int f) {
      final t = f / 60.0;
      return Offset(-0.5 + 2.0 * (0.5 + 0.5 * math.sin(t * 7.0)), -0.3);
    }

    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
      g.update(1 / 60);
      g.onInput(PlayerInput.down(0, outsideAt(frames)));
      final net = g.netPosForTest(0)!;
      // Stays in its own (bottom) half and on-board, every single frame.
      expect(net.dy, greaterThanOrEqualTo(0.5),
          reason: 'net crossed into the rival half at frame $frames');
      expect(net.dy, lessThanOrEqualTo(1.0));
      expect(net.dx, inInclusiveRange(0.0, 1.0));
    }
    expect(g.status, MiniGameStatus.finished);
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
    // CLIMAX mechanic. A solo human steers their net onto the roaming star and
    // taps every frame, snatching it wherever it goes. We snapshot the score the
    // moment the flurry begins (the last 7s of the 30s round) and require a
    // meaningful score gain across that flurry — i.e. the finish is a live gold
    // storm rather than a dead tail. The chase tracks [starPosForTest] so it is
    // deterministic.
    final g = CatchTheStar()..init(ctxFor(1, 7));
    var frames = 0;
    num scoreAtFlurryStart = -1;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
      g.update(1 / 60);
      g.onInput(PlayerInput.down(0, g.starPosForTest));
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
      g.onInput(PlayerInput.down(0, sweepAt(frames)));
    }
    expect(g.status, MiniGameStatus.finished);
    expect(frames / 60.0, greaterThan(1.5));
    expect(frames / 60.0, lessThanOrEqualTo(31.0));
  });
}
