import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/reaction_duel/reaction_duel.dart';

void main() {
  test('reaction duel finishes with full ranking (4 bots)', () {
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = ReactionDuel()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('all-bot 4p round lasts >1.5s and finishes within the time limit', () {
    // The quick-draw must never end in a sub-1.5s flicker (the min GO delay plus
    // the post-win linger keeps it dramatic) nor blow past its 12s cap.
    const dt = 1 / 60;
    for (final seed in [1, 2, 3, 7, 13, 42, 99]) {
      final ctx = MiniGameContext(
        players: [for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(4),
      );
      final g = ReactionDuel()..init(ctx);
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 30) {
        g.update(dt);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      expect(frames * dt, greaterThan(1.5), reason: 'seed=$seed ended too fast');
      expect(frames * dt, lessThanOrEqualTo(13.0),
          reason: 'seed=$seed exceeded the time limit');
    }
  });

  test('reaction duel: early human tap is penalized and ranked last', () {
    final ctx = MiniGameContext(
      players: [
        PlayerSlot.defaults(0), // human jumps the gun
        PlayerSlot.defaults(1, isBot: true),
      ],
      arena: const Size(800, 1200),
      rng: SeededRng(4),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ReactionDuel()..init(ctx);

    // Tap immediately (still in the waiting phase) -> false start.
    g.onInput(PlayerInput.down(0));

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    final ranking = g.winResult!.ranking;
    expect(ranking.toSet(), {0, 1});
    // Penalized player must be last.
    expect(ranking.last, 0);
  });

  test('reaction duel solo player finishes within the time limit', () {
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(1),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = ReactionDuel()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking, [0]);
  });
}
