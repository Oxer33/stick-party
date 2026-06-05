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
}
