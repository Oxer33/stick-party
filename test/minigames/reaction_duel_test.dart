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
import 'package:stick_party/minigames/reaction_duel/reaction_render.dart';

void main() {
  test('quick-draw duel finishes with full ranking (4 bots)', () {
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

  test('all-bot 4p match lasts >1.5s and finishes within the time limit', () {
    // The duel is a race to a target number of won draws (with a hard draw cap +
    // overall time cap as safety nets), so it must comfortably outlast 1.5s yet
    // never blow past its 40s cap (+1 frame of resolution slack).
    const dt = 1 / 60;
    for (final seed in [1, 2, 3, 7, 13, 42, 99]) {
      final ctx = MiniGameContext(
        players: [
          for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
        ],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(4),
      );
      final g = ReactionDuel()..init(ctx);
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
        g.update(dt);
      }
      expect(g.status, MiniGameStatus.finished,
          reason: 'seed=$seed must finish');
      expect(frames * dt, greaterThan(1.5),
          reason: 'seed=$seed ended too fast');
      expect(frames * dt, lessThanOrEqualTo(41.0),
          reason: 'seed=$seed exceeded the time limit');
    }
  });

  test('ANTI-SPAM: a blind spammer false-starts every draw and LOSES the match '
      'to a duelist who waits for the GO', () {
    // The spine of the rework. Player 0 is a human who SPAMS — it taps every
    // single frame from the very start, so on every draw its first tap lands
    // during WAIT (or on a feint) and is a FALSE START; once penalized, the
    // gate ignores its extra taps. Player 1 is a HARD bot — "a duelist who waits
    // for the GO": it holds nerve through WAIT (low errorRate) and draws on its
    // reaction delay after the real signal. Deterministic via ctx.rng(seed).
    //
    // A blind early tap can NEVER win a draw (anti-incidental: the gate only
    // ever sets a winner from a GO-phase tap), so the spammer wins ZERO draws
    // and is ranked LAST behind the disciplined opponent.
    final ctx = MiniGameContext(
      players: [
        PlayerSlot.defaults(0), // human blind spammer
        PlayerSlot.defaults(1, isBot: true), // disciplined opponent
      ],
      arena: const Size(800, 1200),
      rng: SeededRng(4),
      zones: ZoneLayout.forPlayers(2),
      difficulty: BotDifficulty.hard,
    );
    final g = ReactionDuel()..init(ctx);

    // SPAM from frame zero and keep spamming every frame for the whole match.
    g.onInput(PlayerInput.down(0));
    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
      g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    final ranking = g.winResult!.ranking;
    expect(ranking.toSet(), {0, 1});
    // The disciplined opponent wins the match; the blind spammer is dead last.
    expect(ranking.first, 1, reason: 'the duelist who waits for the GO wins');
    expect(ranking.last, 0, reason: 'the blind spammer loses the match');
    // Strongest anti-spam evidence: spamming banked NO won draws at all (a draw
    // tally of 0 keeps the live score below 1.0; the opponent banked the match).
    expect(g.scores.of(0), lessThan(g.scores.of(1)),
        reason: 'the spammer never out-scores the disciplined opponent');
    expect(g.scores.of(0), lessThan(1.0),
        reason: 'a spammer can never reach even one won draw');
  });

  test('ANTI-INCIDENTAL: a tap before the real GO can never win a draw', () {
    // The safeguard, proven on the gate that the duel is built on. An early tap
    // (during WAIT) and a tap landing on a FEINT are both false starts that lock
    // the player out; neither can ever become the winner. Only a deliberate tap
    // in the GO window wins. So no lucky/incidental early input backs into a win.
    final gate = ReactionGate(SeededRng(4),
        minDelay: 3.0, maxDelay: 3.0, feints: 1, feintFlashSec: 0.25);
    expect(gate.fakeGoTimes, isNotEmpty,
        reason: 'a long wait must schedule at least one feint');

    // A plain early tap during WAIT is a false start, not a win.
    expect(gate.phase, ReactionPhase.waiting);
    expect(gate.onTap(0), ReactionTap.early);
    expect(gate.winner, isNull);

    // Advance to the lit feint; a tap there is also an early false start (the
    // phase is still WAITING — a feint is NOT the GO), and still no winner.
    final flashAt = gate.fakeGoTimes.first;
    var t = 0.0;
    while (!gate.feintActive && t < flashAt + 0.5) {
      gate.update(1 / 120);
      t += 1 / 120;
    }
    expect(gate.feintActive, isTrue, reason: 'the feint flash must light');
    expect(gate.phase, ReactionPhase.waiting,
        reason: 'a feint must not advance to GO');
    expect(gate.onTap(1), ReactionTap.early);
    expect(gate.winner, isNull, reason: 'tapping a feint can never win');

    // The REAL GO then fires; both locked-out players are ignored and there is
    // still no winner from their earlier (early) taps. Only a fresh GO-phase tap
    // by a clean player wins.
    while (gate.phase == ReactionPhase.waiting && t < 4.0) {
      gate.update(1 / 120);
      t += 1 / 120;
    }
    expect(gate.phase, ReactionPhase.go);
    expect(gate.onTap(0), ReactionTap.ignored);
    expect(gate.onTap(1), ReactionTap.ignored);
    expect(gate.winner, isNull);
    expect(gate.onTap(2), ReactionTap.valid,
        reason: 'a deliberate GO-phase tap by a clean player wins');
    expect(gate.winner, 2);
  });

  test('quick-draw solo player finishes within the time limit', () {
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

  test('render never throws across WAIT / feint / GO / KO and the tally HUD',
      () {
    // The render path must be no-throw at every phase (it runs every frame). We
    // drive a 4p match, rendering into a recording canvas each frame so feints,
    // the GO flash, KO ragdolls, the draw tally and (if reached) MATCH POINT all
    // paint at least once.
    final ctx = MiniGameContext(
      players: [
        for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
      ],
      arena: const Size(800, 1200),
      rng: SeededRng(13),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = ReactionDuel()..init(ctx);

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    var frames = 0;
    expect(() {
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
        g.update(1 / 60);
        g.render(canvas, const Size(800, 1200));
      }
      g.render(canvas, const Size(800, 1200)); // one more after finish
    }, returnsNormally);
    expect(g.status, MiniGameStatus.finished);
  });

  group('drawAward (winner takes the draw)', () {
    test('awards exactly one draw to the winner and zero to everyone else', () {
      // Quick-Draw is winner-takes-the-draw: only the single fastest valid tap
      // wins; slower tappers, silent players and false-starters get nothing.
      final award = drawAward([0, 1, 2, 3], 2);
      expect(award[2], 1, reason: 'the winner banks the draw');
      expect(award[0], 0);
      expect(award[1], 0);
      expect(award[3], 0);
    });

    test('a washed draw (no winner) awards nothing', () {
      // A draw where nobody made a valid tap (a timed-out GO, or all false
      // starts) gives no one a draw, yet every id still gets an entry.
      final award = drawAward([0, 1], null);
      expect(award[0], 0);
      expect(award[1], 0);
    });
  });

  group('matchWon (first to N)', () {
    test('true once any duelist reaches the target', () {
      expect(matchWon({0: 2, 1: 1}, 3), isFalse);
      expect(matchWon({0: 3, 1: 1}, 3), isTrue);
      expect(matchWon({0: 4, 1: 1}, 3), isTrue, reason: 'overshoot still wins');
    });

    test('a target below 1 is clamped to 1', () {
      expect(matchWon({0: 1}, 0), isTrue);
      expect(matchWon({0: 0}, 0), isFalse);
    });
  });

  group('buildDuelRanking (draws won, then snappier total reaction)', () {
    test('ranks by draws won first', () {
      // More draws won is the champion, regardless of reaction totals.
      final ranking = buildDuelRanking(
        [0, 1],
        {0: 3, 1: 2},
        {0: 1.20, 1: 0.40}, // 1 was snappier but won fewer draws
      );
      expect(ranking, [0, 1], reason: 'the duelist with more draws wins');
    });

    test('breaks draw ties by the smaller cumulative reaction total', () {
      // Level on draws → the snappier duelist (lower total reaction) ranks
      // higher; a duelist who reacted at least once outranks one who never did.
      expect(
          buildDuelRanking([0, 1], {0: 1, 1: 1}, {0: 0.90, 1: 0.50}), [1, 0]);
      expect(buildDuelRanking([0, 1], {0: 1, 1: 1}, {1: 0.25}), [1, 0],
          reason: 'a duelist who reacted outranks one who never did');
    });

    test('every id appears exactly once', () {
      final ranking = buildDuelRanking([0, 1, 2, 3], {2: 1}, {2: 0.3});
      expect(ranking.toSet(), {0, 1, 2, 3});
      expect(ranking.length, 4);
    });
  });

  test('DrawTallyRow render helper never throws (empty / normal / overshoot)',
      () {
    // The HUD value type + drawer must be no-throw for any snapshot the game can
    // hand it, including an empty roster and a won-count above the target.
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    expect(() {
      ReactionRenderer.drawDrawTally(canvas, const Size(800, 1200),
          rows: const [], target: 3);
      ReactionRenderer.drawDrawTally(
        canvas,
        const Size(800, 1200),
        rows: const [
          DrawTallyRow(color: Color(0xFFE53935), won: 0),
          DrawTallyRow(color: Color(0xFF24D16A), won: 5), // overshoot
        ],
        target: 3,
      );
    }, returnsNormally);
  });

  test('plays multiple draws (spans more than a single draw)', () {
    // First-to-N means an all-bot 4p match must take more than one draw's
    // worst-case (well past a single ~4.2s max GO delay + linger) yet still
    // finish within the 40s cap.
    const dt = 1 / 60;
    final ctx = MiniGameContext(
      players: [for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = ReactionDuel()..init(ctx);
    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
      g.update(dt);
    }
    expect(g.status, MiniGameStatus.finished);
    // A first-to-3 race over several draws (each: a wait + reaction + ~1s linger
    // + the inter-draw beat) comfortably exceeds ~5s.
    expect(frames * dt, greaterThan(5.0),
        reason: 'a first-to-N race must outlast a single draw');
    expect(frames * dt, lessThanOrEqualTo(41.0));
  });
}
