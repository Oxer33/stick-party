import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/tap_sprint/tap_sprint.dart';

void main() {
  test('tap sprint finishes with full ranking (4 bots)', () {
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = TapSprint()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
    expect(g.winResult!.winner, isNotNull);

    // Sim-length floor + ceiling: the all-bot race must outlast the bot warmup
    // (no instant finish) and still resolve inside the hard time limit (~30s).
    final simSeconds = n / 60.0;
    expect(simSeconds, greaterThan(1.5));
    expect(simSeconds, lessThanOrEqualTo(31.0));
  });

  test('tap sprint solo player finishes', () {
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(3),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = TapSprint()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking, [0]);
  });

  test('tap sprint render does not throw mid-round', () {
    final ctx = MiniGameContext(
      players: [for (var i = 0; i < 3; i++) PlayerSlot.defaults(i, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(11),
      zones: ZoneLayout.forPlayers(3),
    );
    final g = TapSprint()..init(ctx);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    g.update(1 / 60);
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });
}
