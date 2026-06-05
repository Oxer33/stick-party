import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
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

  test('a tap does not throw and game still finishes', () {
    final g = SnakeArena()..init(ctxFor(2, 3));
    g.onInput(PlayerInput.down(0, const Offset(0.5, 0.5)));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % 17 == 0) g.onInput(PlayerInput.down(0));
    }
    expect(g.status, MiniGameStatus.finished);
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
