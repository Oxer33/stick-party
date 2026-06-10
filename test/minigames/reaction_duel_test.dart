import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/helpers/reaction_gate.dart';
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

  test('reaction duel: a human who false-starts every round is ranked last', () {
    // HARD bots (low errorRate) reliably win their rounds rather than fluffing
    // every feint, so a human who jumps the gun in BOTH rounds banks zero points
    // and lands behind them. Tapping every frame while WAITING re-false-starts
    // on each fresh round; once penalized, extra taps are ignored by the gate.
    final ctx = MiniGameContext(
      players: [
        PlayerSlot.defaults(0), // human jumps the gun
        PlayerSlot.defaults(1, isBot: true),
      ],
      arena: const Size(800, 1200),
      rng: SeededRng(4),
      zones: ZoneLayout.forPlayers(2),
      difficulty: BotDifficulty.hard,
    );
    final g = ReactionDuel()..init(ctx);

    // Tap immediately (still in the waiting phase) -> false start, and keep
    // tapping so the next round's wait also catches an early tap.
    g.onInput(PlayerInput.down(0));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    final ranking = g.winResult!.ranking;
    expect(ranking.toSet(), {0, 1});
    // The serial false-starter must rank last behind a reliable bot.
    expect(ranking.last, 0);
  });

  test('feint: tapping a fake-GO flash locks the player out (early false start)',
      () {
    // Build a gate with a long wait so a feint comfortably fits before GO, and
    // force a feint to exist (feints: 1). Advance to the lit flash, tap, and
    // confirm the tap is an early false start that penalizes — even though the
    // phase is still WAITING (a feint is NOT the GO).
    final gate = ReactionGate(SeededRng(4),
        minDelay: 3.0, maxDelay: 3.0, feints: 1, feintFlashSec: 0.25);
    expect(gate.fakeGoTimes, isNotEmpty,
        reason: 'a long wait must schedule at least one feint');

    // Step in small ticks until the (first) fake flash lights up.
    final flashAt = gate.fakeGoTimes.first;
    var t = 0.0;
    while (!gate.feintActive && t < flashAt + 0.5) {
      gate.update(1 / 120);
      t += 1 / 120;
    }
    expect(gate.feintActive, isTrue, reason: 'the feint flash must light');
    expect(gate.phase, ReactionPhase.waiting,
        reason: 'a feint must not advance to GO');

    // Tapping the fake is an early false start and locks the player out.
    expect(gate.onTap(0), ReactionTap.early);
    expect(gate.penalized, contains(0));

    // Later, the REAL GO still fires and the locked-out player cannot win it.
    while (gate.phase == ReactionPhase.waiting && t < 4.0) {
      gate.update(1 / 120);
      t += 1 / 120;
    }
    expect(gate.phase, ReactionPhase.go);
    expect(gate.onTap(0), ReactionTap.ignored);
    expect(gate.winner, isNull);
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
