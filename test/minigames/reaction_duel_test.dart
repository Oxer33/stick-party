import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/reaction_duel/reaction_duel.dart';
import 'package:stick_party/minigames/reaction_duel/reaction_duel_rounds.dart';

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
    // The quick-draw is now a best-of-2 (a normal round + a LIGHTNING final
    // worth double), so it must comfortably outlast 1.5s yet never blow past its
    // 20s cap (+1 frame of resolution slack).
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
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 40) {
        g.update(dt);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed=$seed must finish');
      expect(frames * dt, greaterThan(1.5), reason: 'seed=$seed ended too fast');
      expect(frames * dt, lessThanOrEqualTo(21.0),
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

  test('LIGHTNING double points: finale win outranks a normal-round win', () {
    // CLIMAX mechanic, proven on the scoring core ([buildDuelRanking]). Player 1
    // won the normal round (+1). Player 0 won the LIGHTNING final (+2). Despite
    // player 1 banking points first, the double-weighted finale must put player
    // 0 on top — so the last round genuinely swings the match.
    final ranking = buildDuelRanking(
      [0, 1],
      {0: 2, 1: 1}, // cumulative points after both rounds
      {0: 0.30}, // last (lightning) round reaction time for the finale winner
    );
    expect(ranking, [0, 1], reason: 'the lightning win (2 pts) must rank first');
  });

  test('buildDuelRanking breaks point ties by the faster last reaction', () {
    // A drawn match on points falls back to who reacted faster in the final
    // round; a player who reacted outranks one who did not.
    expect(buildDuelRanking([0, 1], {0: 1, 1: 1}, {0: 0.40, 1: 0.20}), [1, 0]);
    expect(buildDuelRanking([0, 1], {0: 1, 1: 1}, {1: 0.25}), [1, 0]);
  });

  test('plays a full best-of-2 (spans more than a single round)', () {
    // The match is now two rounds; an all-bot 4p game must therefore take longer
    // than one round's worst-case (well past the single ~3.6s max GO delay +
    // linger) yet still finish within the 20s cap.
    const dt = 1 / 60;
    final ctx = MiniGameContext(
      players: [for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = ReactionDuel()..init(ctx);
    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 40) {
      g.update(dt);
    }
    expect(g.status, MiniGameStatus.finished);
    // Two rounds (each: a wait + reaction + ~1s linger) plus the inter-round
    // beat comfortably exceed ~5s; a single-round game could not.
    expect(frames * dt, greaterThan(5.0),
        reason: 'a best-of-2 must outlast a single round');
    expect(frames * dt, lessThanOrEqualTo(21.0));
  });
}
