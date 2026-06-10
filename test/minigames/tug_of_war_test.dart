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

  // ── Hold-and-release dig-in behavior ──────────────────────────────────────
  //
  // These drive a SINGLE top-side human (id 0, even → top). With no opponent the
  // marker only swings on this player's digs: a dig toward the top reads as
  // score (max(0, -marker)). [beatWindowOpenForTest] lets each run press exactly
  // when the dig-in window is open, so the only variable is the hold behavior.

  /// Advance [g] one frame at a time until the dig-in window opens (bounded).
  void advanceToWindow(TugOfWar g) {
    var guard = 0;
    while (!g.beatWindowOpenForTest && guard++ < 600) {
      g.update(1 / 60);
    }
  }

  /// Advance until the dig-in window CLOSES (bounded), so the next dig re-arms
  /// (the heave latch re-arms only once the beat leaves the sweet-spot).
  void advancePastWindow(TugOfWar g) {
    var guard = 0;
    while (g.beatWindowOpenForTest && guard++ < 600) {
      g.update(1 / 60);
    }
  }

  /// Run a 1p top-side tug for [digs] on-beat digs: each dig waits for the
  /// window, presses, holds [holdFr] frames, then releases. Returns the final
  /// advantage score (how far the player dug toward their goal).
  double runHoldPattern({required int holdFr, int digs = 6}) {
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0)], // single human, top side
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = TugOfWar()..init(ctx);
    for (var d = 0; d < digs && g.status != MiniGameStatus.finished; d++) {
      advanceToWindow(g);
      g.onInput(PlayerInput.down(0)); // press inside the window → starts a dig
      for (var f = 0; f < holdFr && g.status != MiniGameStatus.finished; f++) {
        g.update(1 / 60);
      }
      g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up)); // release
      // Step out of the window so the next dig re-arms (the heave latch re-arms
      // only once the beat leaves the sweet-spot).
      advancePastWindow(g);
    }
    return g.scores.of(0).toDouble();
  }

  test('dig-in: a longer (in-window) hold pulls harder than an instant release',
      () {
    // Same seed + same on-beat presses; only the hold length differs. A ~8-frame
    // hold (≈0.13s, safely inside the window + grace) charges the dig, so it must
    // out-pull a zero-hold instant release over the same number of digs.
    final instant = runHoldPattern(holdFr: 0);
    final held = runHoldPattern(holdFr: 8);
    expect(held, greaterThan(instant),
        reason: 'a charged hold must pull the marker further than an instant tap');
    expect(held, greaterThan(0),
        reason: 'a charged dig should clearly move the marker');
  });

  test('dig-in: over-holding past the window SLIPS and loses the gained ground',
      () {
    // A safe hold drags the marker toward the player's goal (positive score). An
    // over-long hold (40 frames — well past window close + grace) trips the SLIP
    // path on release/auto-release, recoiling the marker the WRONG way, so the
    // greedy pattern ends up far behind the disciplined one.
    final disciplined = runHoldPattern(holdFr: 8);
    final greedy = runHoldPattern(holdFr: 40);
    expect(disciplined, greaterThan(greedy),
        reason: 'over-holding must slip and forfeit ground vs a clean release');
  });
}
