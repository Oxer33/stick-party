import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/button_masher/button_masher.dart';

void main() {
  test('button masher finishes with full ranking (4 bots)', () {
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = ButtonMasher()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});

    // Sim-length floor + ceiling: the all-bot round must outlast the bot warmup
    // and still resolve inside the (~10s) hard time limit.
    final simSeconds = n / 60.0;
    expect(simSeconds, greaterThan(1.5));
    expect(simSeconds, lessThanOrEqualTo(11.0));
  });

  test('button masher scores reflect tap counts and a human tap registers', () {
    final players = [
      PlayerSlot.defaults(0), // human
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ButtonMasher()..init(ctx);

    // Human mashes a handful of times in the first frame.
    for (var i = 0; i < 5; i++) {
      g.onInput(PlayerInput.down(0));
    }
    g.update(1 / 60);
    expect(g.scores.of(0), greaterThanOrEqualTo(5));

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    // Bot mashes the whole round, so total taps must exceed the human's 5.
    expect(g.scores.of(1), greaterThan(5));
  });
}
