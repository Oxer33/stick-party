import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
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
    // one that never resolves. 60s of frames comfortably exceeds the 45s cap.
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

  test('tapping the colored pads directly does not throw and round resolves',
      () {
    // New control: players tap the real colored quadrants in their cluster via
    // input.normPos (no auto-cycling cursor). Player 0's cluster in a 2p layout
    // sits in the bottom band; these four points land in its four quadrants.
    // Cycling taps across them exercises the pad hit-testing (correct → advance,
    // wrong → forgiven on round 1 then out) and the round must always resolve.
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
    final g = ColorMemory()..init(ctxFor(2, 3));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % 9 == 0) g.onInput(PlayerInput.down(0));
    }
    expect(g.status, MiniGameStatus.finished);
  });

  test('render does not throw in either phase', () {
    final g = ColorMemory()..init(ctxFor(4, 11));
    final canvas = Canvas(PictureRecorder());
    // Showing phase (just started).
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    // Advance into the input phase and render again.
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60);
    }
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    runToEnd(g);
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });
}
