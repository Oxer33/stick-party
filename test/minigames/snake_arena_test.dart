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
}
