import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/chicken_jump/chicken_jump.dart';

void main() {
  MiniGameContext ctxFor(int n, {int seed = 7}) {
    final players = [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)];
    return MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(n),
    );
  }

  // ── Invariants (kept) ───────────────────────────────────────────────────────

  test('chicken jump finishes with four bots and ranks all players', () {
    final g = ChickenJump()..init(ctxFor(4));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  for (final count in [1, 2, 3]) {
    test('chicken jump finishes with $count player(s)', () {
      final g = ChickenJump()..init(ctxFor(count, seed: 31 + count));
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished);
      expect(g.winResult!.ranking.toSet(),
          {for (var i = 0; i < count; i++) i});
    });
  }

  test('SCORED RUN: an all-bot round runs the FULL timer and never ends early '
      '(anti-instant-win)', () {
    // The rework makes this a scored run, not last-one-standing: caught climbers
    // respawn, so the round plays the whole [timeLimit] and is ranked by peak
    // height. It must NEVER resolve in the first couple of seconds (the old
    // "instant win when the rival fell" bug) — it always reaches the time cap.
    final g = ChickenJump()..init(ctxFor(4, seed: 5));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    final simSeconds = n / 60.0;
    // Anti-instant-win floor: a real round, well past any "one left" moment.
    expect(simSeconds, greaterThan(8.0));
    // Ceiling: the full timer (30s) plus a small resolution buffer.
    expect(simSeconds, lessThan(31.0));
  });

  test('SCORED RUN: a 1v1 where the bot is caught still runs the full timer '
      '(no instant win when the rival falls)', () {
    // The core complaint: in 1v1 the round used to end the instant the lone bot
    // died. Now the human plays the WHOLE run for height. Drive a human that
    // taps steadily vs one medium bot; assert the round lasts a real minimum
    // regardless of when the bot first gets caught.
    final players = [
      PlayerSlot.defaults(0),
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(17),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ChickenJump()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
      if (n % 22 == 0) {
        g.onInput(PlayerInput.down(0));
        g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
      }
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
    expect(n / 60.0, greaterThan(8.0),
        reason: '1v1 must play a real run, not end when the bot is caught');
  });

  test('all-bot rounds finish across difficulties and seeds within the cap', () {
    // The DOUBLE-LEAP gamble (bots risk it when the lava is close, and can
    // crumble on the cracked landing) must never break convergence: every
    // all-bot field still resolves with a full ranking by the 30s time cap
    // (+ a small resolution buffer; the round may run right up to the limit).
    const maxTicks = 60 * 31; // 30s cap + a 1s resolution buffer
    for (final diff in BotDifficulty.values) {
      for (final seed in const [1, 7, 13, 21]) {
        final ctx = MiniGameContext(
          players: [for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)],
          arena: const Size(800, 1200),
          rng: SeededRng(seed),
          zones: ZoneLayout.forPlayers(4),
          difficulty: diff,
        );
        final g = ChickenJump()..init(ctx);
        var ticks = 0;
        while (g.status != MiniGameStatus.finished && ticks < 60 * 80) {
          g.update(1 / 60);
          ticks++;
        }
        expect(g.status, MiniGameStatus.finished,
            reason: 'diff=$diff seed=$seed must finish');
        expect(ticks, lessThanOrEqualTo(maxTicks),
            reason: 'diff=$diff seed=$seed must resolve within the cap');
        expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3},
            reason: 'diff=$diff seed=$seed full ranking');
      }
    }
  });

  test('a steady stream of safe single TAPS keeps a player alive and finishes',
      () {
    // BACK-COMPAT: the old behavior — a positionless down tap every ~20 frames
    // is a safe single hop — must still keep the human in the round and resolve.
    final players = [
      PlayerSlot.defaults(0),
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(9),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ChickenJump()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
      if (n % 20 == 0) {
        // A discrete tap = down immediately followed by up (no sustained hold),
        // so it stays a SAFE single rung — never a double leap.
        g.onInput(PlayerInput.down(0));
        g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
      }
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
  });

  // ── New behavior: the GAMBLE (double leap + cracked rung) ────────────────────

  test('holding past the leap threshold climbs higher than the same number of '
      'single taps (the double-leap gamble)', () {
    // A single human vs no pressure: compare two identical players, one tapping
    // safely, one holding each press. Over the same number of presses the holder
    // should reach a strictly greater height — the bonus rung is real. Driven
    // entirely off the deterministic context clock (no rng in the assert path
    // beyond the seeded miss roll, which a low miss chance keeps reliable here).
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1)],
      arena: const Size(800, 1200),
      rng: SeededRng(3),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ChickenJump()..init(ctx);

    // Settle the warmup so hops register cleanly.
    for (var i = 0; i < 130; i++) {
      g.update(1 / 60);
    }

    // Player 0 taps safely; player 1 holds each press long enough to leap.
    // 6 presses each, spaced so the hopper settles and (for the holder) the hold
    // clears the leap threshold (~0.16s) but the cracked rung is vacated before
    // it crumbles (crack hold ~0.62s).
    for (var press = 0; press < 6; press++) {
      g.onInput(PlayerInput.down(0));
      g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));

      g.onInput(PlayerInput.down(1)); // begin a hold (also commits a safe hop)
      for (var f = 0; f < 16; f++) {
        // ~0.27s held → springs the bonus rung, then release before crumble.
        g.update(1 / 60);
      }
      g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.up));
      for (var f = 0; f < 12; f++) {
        g.update(1 / 60);
      }
    }

    expect(g.heightLaneOf(1), greaterThan(g.heightLaneOf(0)),
        reason: 'the holder should out-climb the safe tapper via double leaps');
  });

  test('lingering on a cracked rung crumbles the climber back down a rung', () {
    // Hold to leap onto a cracked rung, then DO NOTHING — the rung must give way
    // and drop the climber one rung below where the leap landed. The leap can
    // miss (a seeded ~16% fizzle), so retry presses until a crack actually forms
    // before testing the crumble — the assertion is on the crumble, not the roll.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(2),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ChickenJump()..init(ctx);
    for (var i = 0; i < 130; i++) {
      g.update(1 / 60);
    }

    // Press-and-hold until a cracked rung is underfoot (bounded retries so a
    // missed leap never wedges the test). Release between attempts.
    var formed = false;
    for (var attempt = 0; attempt < 8 && !formed; attempt++) {
      g.onInput(PlayerInput.down(0));
      for (var f = 0; f < 14 && !formed; f++) {
        g.update(1 / 60); // hold past the leap threshold
        if (g.crackedRungOf(0) >= 0) formed = true;
      }
      if (!formed) {
        g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
        for (var f = 0; f < 8; f++) {
          g.update(1 / 60);
        }
      }
    }
    expect(formed, isTrue,
        reason: 'a held press should eventually spring a cracked rung');
    final peak = g.heightLaneOf(0);

    // Keep lingering past the crumble window (~0.62s) without hopping off.
    for (var f = 0; f < 60; f++) {
      g.update(1 / 60);
    }
    expect(g.heightLaneOf(0), lessThan(peak),
        reason: 'a lingered cracked rung must crumble and drop the climber');
  });

  test('SCORED RUN: the double-leap holder out-SCORES the safe masher over a '
      'full run (skill beats spam)', () {
    // Anti-spam guarantee against the final score model: two identical humans,
    // one mashing safe single hops, one holding each press to gamble the double
    // leap. Both press the same number of times, then the round plays out to the
    // finish. Ranked by peak height, the holder must finish with a score >= the
    // masher (and the holder must lead the ranking) — so safe single-hop mashing
    // can never out-score the risky leap. Deterministic via the seeded context.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1)],
      arena: const Size(800, 1200),
      rng: SeededRng(3),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ChickenJump()..init(ctx);
    for (var i = 0; i < 130; i++) {
      g.update(1 / 60);
    }
    // Player 0 mashes safe single taps; player 1 holds each press to leap.
    for (var press = 0; press < 6; press++) {
      g.onInput(PlayerInput.down(0));
      g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
      g.onInput(PlayerInput.down(1));
      for (var f = 0; f < 16; f++) {
        g.update(1 / 60);
      }
      g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.up));
      for (var f = 0; f < 12; f++) {
        g.update(1 / 60);
      }
    }
    // Run the rest of the round out to the finish (no further input).
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    final scores = g.winResult!.finalScores;
    final holder = (scores[1] ?? 0).toDouble();
    final masher = (scores[0] ?? 0).toDouble();
    expect(holder, greaterThanOrEqualTo(masher),
        reason: 'the bold leaper must not score below the safe masher');
    expect(g.winResult!.ranking.first, 1,
        reason: 'the higher-climbing leaper should top the ranking');
  });
}
