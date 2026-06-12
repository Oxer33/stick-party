import 'dart:ui' show PictureRecorder;

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

  /// Tap once as a discrete press (down immediately followed by up), so it is a
  /// SAFE single hop — never held into a double leap.
  void tap(ChickenJump g, int id) {
    g.onInput(PlayerInput.down(id));
    g.onInput(PlayerInput(playerId: id, phase: InputPhase.up));
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
      if (n % 22 == 0) tap(g, 0);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
    expect(n / 60.0, greaterThan(8.0),
        reason: '1v1 must play a real run, not end when the bot is caught');
  });

  test('all-bot rounds finish across difficulties and seeds within the cap', () {
    // The DOUBLE-LEAP gamble and the SPIKE gauntlet (bots can be knocked down
    // and stunned) must never break convergence: every all-bot field still
    // resolves with a full ranking by the 30s time cap (+ a small resolution
    // buffer; the round may run right up to the limit).
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
    // (Blind taps may now bump the spike gauntlet, but a hit only knocks back +
    // stuns; the player survives via respawn and the round still finishes.)
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
      if (n % 20 == 0) tap(g, 0);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1});
  });

  test('render never throws across a full run (incl. spikes + gamble + climax)',
      () {
    // Render-no-throw invariant: drive a 4-bot round and paint every few frames
    // through the warmup, the live spike gauntlet, the climax surge and the
    // finish. Spikes, cracks, lava and popups must all render safely.
    final g = ChickenJump()..init(ctxFor(4, seed: 11));
    final rec = PictureRecorder();
    final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, 800, 1200));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
      if (n % 5 == 0) {
        expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
      }
    }
    expect(g.status, MiniGameStatus.finished);
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });

  // ── The interposing obstacle: SPIKE gates ────────────────────────────────────

  test('tapping UP onto an armed spike rung does NOT gain height (the gate '
      'interposes)', () {
    // Climb (only on safe windows) to the rung just below the first gate, then
    // wait until the gate above is UNSAFE (armed/warning) and tap into it. The
    // hop must be rejected (no gain / knocked back), not a free climb — proof the
    // spike actually blocks a blind tap.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(4),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ChickenJump()..init(ctx);
    for (var i = 0; i < 130; i++) {
      g.update(1 / 60); // clear the warmup so spikes go live
    }
    final below = g.spikeStartRung - 1;
    var guard = 0;
    while (g.heightLaneOf(0) < below && guard++ < 4000) {
      if (g.nextRungSafeOf(0) && g.stunOf(0) <= 0) tap(g, 0);
      g.update(1 / 60);
    }
    expect(g.heightLaneOf(0), below,
        reason: 'should reach the rung just below the gauntlet');

    // Wait until the gate above is specifically DEADLY (spikes fully out) — not
    // merely the harmless WARN beat, which is still safe to land on.
    guard = 0;
    while (!g.nextRungDeadlyOf(0) && guard++ < 4000) {
      g.update(1 / 60);
    }
    expect(g.nextRungDeadlyOf(0), isTrue,
        reason: 'the gate above should eventually arm (spikes out)');
    final laneBefore = g.heightLaneOf(0);
    tap(g, 0); // tap straight into the armed spike
    g.update(1 / 60);
    expect(g.heightLaneOf(0), lessThanOrEqualTo(laneBefore),
        reason: 'a tap into an armed spike must never gain height');
  });

  test('ANTI-SPAM: a blind frame-spammer SCORES LOWER than a measured climber '
      'who reads the spikes (skill beats mash)', () {
    // The DESIGN-LAW proof. Two identical humans climb the same shared gauntlet:
    //  * Player 0 MASHES — taps EVERY frame, blind to the spikes.
    //  * Player 1 is MEASURED — taps only when the rung above is SAFE.
    // The score is ALTITUDE HELD over the run (∫ rung·dt). The masher, climbing
    // in cadence straight into rotating spikes, is knocked DOWN repeatedly and
    // spends its time LOW (banking little); the reader threads the safe windows,
    // climbs clean and HOLDS high (banking far more). Deterministic via the
    // seeded context.
    //
    // On the OLD design (no spike gate / no cadence cap) the masher front-ran
    // straight to the top and this assertion FAILS; with the gauntlet it PASSES.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1)],
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ChickenJump()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      // Player 0: blind mash — a discrete tap every single frame.
      tap(g, 0);
      // Player 1: measured — tap only into a safe rung, and never while stunned.
      if (g.nextRungSafeOf(1) && g.stunOf(1) <= 0) tap(g, 1);
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);

    // Altitude held: the reader must out-bank the masher by a clear margin.
    final masherHeld = g.heldScoreOf(0);
    final readerHeld = g.heldScoreOf(1);
    expect(readerHeld, greaterThan(masherHeld),
        reason: 'a spike-reading climber must hold more altitude than a masher');

    // The same ordering must hold in the final score / ranking.
    final scores = g.winResult!.finalScores;
    expect((scores[1] ?? 0).toDouble(),
        greaterThan((scores[0] ?? 0).toDouble()),
        reason: 'the reader must out-score the masher');
    expect(g.winResult!.ranking.first, 1,
        reason: 'the measured climber should top the ranking');
  });

  test('SPIKED climber is briefly stunned (taps ignored) then recovers', () {
    // After a spike hit the climber is locked out for a beat: taps during the
    // stun do nothing, and once it clears taps work again. Drive a masher into
    // the gauntlet until it gets spiked, then assert the stun lockout.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ChickenJump()..init(ctx);
    for (var i = 0; i < 130; i++) {
      g.update(1 / 60);
    }
    // Blind-mash until a spike hit lands (a stun appears). Bounded.
    var guard = 0;
    while (g.stunOf(0) <= 0 && guard++ < 6000) {
      tap(g, 0);
      g.update(1 / 60);
    }
    expect(g.stunOf(0), greaterThan(0),
        reason: 'a blind masher should eventually be spiked');
    // While stunned, a tap is ignored — height cannot increase this frame.
    final laneStunned = g.heightLaneOf(0);
    tap(g, 0);
    expect(g.heightLaneOf(0), laneStunned,
        reason: 'taps must be ignored while stunned');
    // Let the stun clear; the climber must be able to act again.
    guard = 0;
    while (g.stunOf(0) > 0 && guard++ < 600) {
      g.update(1 / 60);
    }
    expect(g.stunOf(0), 0, reason: 'the stun should clear');
  });

  // ── The GAMBLE (double leap + cracked rung), now atop the gauntlet ────────────

  test('holding past the leap threshold climbs higher than the same number of '
      'safe single taps (the double-leap gamble)', () {
    // Two identical players climb the SAME gauntlet on safe windows only, so the
    // spike gate is neutral between them; the ONLY difference is that player 1
    // HOLDS each press to spring the bonus rung. Over the same number of presses
    // the holder reaches a strictly greater peak height — the bonus rung is real.
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

    // 8 presses each. Each press waits until the tapper's next rung AND the
    // holder's next TWO rungs (its leap crosses two) are all safe, so the spike
    // gate is neutral between them; the holder holds ~0.27s to clear the leap
    // threshold, then releases before the cracked rung can crumble. (A press
    // during the hop cooldown is a no-op, so the loop waits out the cadence too.)
    for (var press = 0; press < 8; press++) {
      var guard = 0;
      while ((!g.nextRungSafeOf(0) ||
              !g.nextNRungsSafeOf(1, 2) ||
              g.stunOf(0) > 0 ||
              g.stunOf(1) > 0) &&
          guard++ < 6000) {
        g.update(1 / 60);
      }
      tap(g, 0); // safe single hop

      g.onInput(PlayerInput.down(1)); // begin a hold (also commits a safe hop)
      for (var f = 0; f < 16; f++) {
        g.update(1 / 60); // ~0.27s held → springs the bonus rung
      }
      g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.up));
      for (var f = 0; f < 18; f++) {
        g.update(1 / 60); // release; wait out the cooldown before crumble
      }
    }

    expect(g.peakLaneOf(1), greaterThan(g.peakLaneOf(0)),
        reason: 'the holder should out-climb the safe tapper via double leaps');
  });

  test('lingering on a cracked rung crumbles the climber back down a rung', () {
    // Hold to leap onto a cracked rung, then DO NOTHING — the rung must give way
    // and drop the climber one rung below where the leap landed. The leap can
    // miss (a seeded ~16% fizzle) or hit a spike, so retry presses (only into
    // safe windows) until a crack actually forms before testing the crumble —
    // the assertion is on the crumble, not the roll.
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

    // Press-and-hold (into safe windows for both the step and the leap's bonus
    // rung) until a cracked rung is underfoot.
    var formed = false;
    for (var attempt = 0; attempt < 24 && !formed; attempt++) {
      var guard = 0;
      while ((!g.nextNRungsSafeOf(0, 2) || g.stunOf(0) > 0) && guard++ < 2000) {
        g.update(1 / 60);
      }
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

  test('SCORED RUN: the measured leaper out-SCORES the blind masher over a full '
      'run (skill beats spam, via the final score model)', () {
    // Anti-spam guarantee against the FINAL score model (altitude held over the
    // run). Player 0 blind-mashes every frame; player 1 is a measured leaper — it
    // holds each press to gamble the double leap, but only when both rungs ahead
    // are safe. Run the round to the finish; the leaper, climbing clean and
    // holding high, must out-score the masher (battered low by the spikes) and
    // top the ranking — so blind mashing can never out-score skilled play.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1)],
      arena: const Size(800, 1200),
      rng: SeededRng(3),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ChickenJump()..init(ctx);
    var n = 0;
    var holding = false;
    var holdFrames = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      tap(g, 0); // player 0: blind mash every frame
      // Player 1: a simple safe-window leap loop (hold ~10 frames, release). The
      // leap crosses two rungs, so it only commits when both are safe.
      if (!holding) {
        if (g.nextNRungsSafeOf(1, 2) && g.stunOf(1) <= 0) {
          g.onInput(PlayerInput.down(1));
          holding = true;
          holdFrames = 0;
        }
      } else {
        holdFrames++;
        if (holdFrames >= 10) {
          g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.up));
          holding = false;
        }
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    final scores = g.winResult!.finalScores;
    final leaper = (scores[1] ?? 0).toDouble();
    final masher = (scores[0] ?? 0).toDouble();
    expect(leaper, greaterThan(masher),
        reason: 'the measured leaper must out-score the blind masher');
    expect(g.winResult!.ranking.first, 1,
        reason: 'the higher-climbing leaper should top the ranking');
  });
}
