import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/tug_of_war/tug_of_war.dart';

void main() {
  test('tug of war finishes with full ranking (4 bots, FFA)', () {
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = TugOfWar()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});

    // Sim-length floor + ceiling: back-and-forth pulling must outlast the bot
    // warmup, and the round must still resolve inside the (~20s) hard limit.
    final simSeconds = n / 60.0;
    expect(simSeconds, greaterThan(1.5));
    expect(simSeconds, lessThanOrEqualTo(21.0));
  });

  test('tug of war 2v2 by team finishes; one full team ranks ahead', () {
    final players = [
      PlayerSlot.defaults(0, isBot: true).copyWith(team: Team.a),
      PlayerSlot.defaults(1, isBot: true).copyWith(team: Team.b),
      PlayerSlot.defaults(2, isBot: true).copyWith(team: Team.a),
      PlayerSlot.defaults(3, isBot: true).copyWith(team: Team.b),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(9),
      zones: ZoneLayout.forPlayers(4, mode: GameMode.team2v2),
      mode: GameMode.team2v2,
    );
    final g = TugOfWar()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    final ranking = g.winResult!.ranking;
    expect(ranking.toSet(), {0, 1, 2, 3});

    // Top two must be one whole team (A = ids {0,2}, B = ids {1,3}).
    final topTeam = {ranking[0], ranking[1]};
    final teamA = {0, 2};
    final teamB = {1, 3};
    expect(setEquals(topTeam, teamA) || setEquals(topTeam, teamB), isTrue);
  });

  test('all-bot round outlasts warmup and resolves within the cap across seeds '
      '(climax surge + comeback never break resolution)', () {
    for (final seed in [1, 12, 99, 250]) {
      final players = [
        for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
      ];
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(4),
      );
      final g = TugOfWar()..init(ctx);
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3}, reason: 'seed $seed');
      final simSeconds = n / 60.0;
      expect(simSeconds, greaterThan(1.5), reason: 'seed $seed floor');
      expect(simSeconds, lessThanOrEqualTo(21.0), reason: 'seed $seed cap');
    }
  });

  test('tug of war duel 1v1 finishes', () {
    final players = [
      PlayerSlot.defaults(0, isBot: true),
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(2),
      zones: ZoneLayout.forPlayers(2, mode: GameMode.duel1v1),
      mode: GameMode.duel1v1,
    );
    final g = TugOfWar()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
  });
}
