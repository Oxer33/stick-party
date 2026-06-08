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

  test('FRENZY climax: late taps count double for a solo player', () {
    // Solo player → no leader gap, so the comeback assist is zero and we isolate
    // the frenzy double-count cleanly.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0)],
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = ButtonMasher()..init(ctx);

    // Batch A: 10 taps ~1s in (well before the 75% frenzy gate of the 10s round).
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60);
    }
    final beforeA = g.scores.of(0);
    for (var i = 0; i < 10; i++) {
      g.onInput(PlayerInput.down(0));
    }
    g.update(1 / 60);
    final normalGain = g.scores.of(0) - beforeA;

    // Step to ~8s (inside the frenzy window) without tapping.
    for (var i = 0; i < 60 * 7 && g.status != MiniGameStatus.finished; i++) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.running,
        reason: 'must still be running inside the frenzy window (~8s of 10s)');

    // Batch B: 10 taps during frenzy.
    final beforeB = g.scores.of(0);
    for (var i = 0; i < 10; i++) {
      g.onInput(PlayerInput.down(0));
    }
    g.update(1 / 60);
    final frenzyGain = g.scores.of(0) - beforeB;

    // 10 taps in frenzy must out-score 10 normal taps (double-count).
    expect(frenzyGain, greaterThan(normalGain),
        reason: 'frenzy taps must out-score normal taps');
    expect(frenzyGain, greaterThanOrEqualTo(18), reason: '~2x of 10 taps');
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
