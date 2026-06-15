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

  test('SHARP READ REWARDED: a duelist who taps only on the real GO banks a '
      'reaction time + builds a READ streak and beats a masher', () {
    // The heart of the rework: the read is now VISIBLE and REWARDED. Player 0 is
    // a "sharp reader" — it taps ONLY while the genuine GO is open (g.isGoOpen),
    // which stays false through every feint, so it never false-starts and wins
    // every draw it can reach. Player 1 is a blind MASHER — it taps every frame,
    // so it false-starts on the wait/feints and wins nothing. Deterministic via
    // ctx.rng(seed); easy bot would otherwise be irrelevant — both seats here are
    // driven by the test, not bot AI.
    final ctx = MiniGameContext(
      players: [
        PlayerSlot.defaults(0), // sharp reader (human)
        PlayerSlot.defaults(1), // blind masher (human)
      ],
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = ReactionDuel()..init(ctx);

    var frames = 0;
    var sawReward = false;
    var maxStreak = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
      // The masher spams blindly every frame (false-starts on wait + feints).
      g.onInput(PlayerInput.down(1));
      // The sharp reader fires ONLY when the real GO is open — never on a feint.
      if (g.isGoOpen) g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
      // The reward is visible the instant a clean tap lands: a reaction time and
      // (on a run) a streak. Capture the peak streak seen across the match.
      if (g.lastReadMs > 0) sawReward = true;
      if (g.readStreak > maxStreak) maxStreak = g.readStreak;
    }

    expect(g.status, MiniGameStatus.finished);
    final ranking = g.winResult!.ranking;
    expect(ranking.toSet(), {0, 1});
    // The sharp reader wins the match; the masher is dead last.
    expect(ranking.first, 0, reason: 'the duelist who reads the GO wins');
    expect(ranking.last, 1, reason: 'the blind masher loses');
    // The read is REWARDED visibly: a real reaction time was banked...
    expect(sawReward, isTrue,
        reason: 'a clean tap must surface a reaction time (ms)');
    expect(g.lastReadMs, greaterThan(0));
    // ...and the sharp reader strung wins into a READ streak (first-to-3 means a
    // clean sweep reaches at least a 2-streak before the match ends).
    expect(maxStreak, greaterThanOrEqualTo(2),
        reason: 'consecutive clean reads build a streak ▲');
    // The masher never banked a single won draw (live score stays under 1.0).
    expect(g.scores.of(1), lessThan(1.0),
        reason: 'a masher can never reach even one won draw');
  });

  test('LEARNABLE READ: the GO window is open ONLY on the real signal, never on '
      'a feint — so the read is a skill, not a guess', () {
    // The cue must be learnable: g.isGoOpen (the "tap now and win" window) has to
    // be FALSE through every feint and TRUE only once the genuine GO fires. We
    // drive a long-wait gate with a guaranteed feint and watch the window.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(4),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = ReactionDuel()..init(ctx);

    var sawGoOpen = false;
    var frames = 0;
    // Watch the first draw only: step until the GO opens (or we time out). Any
    // frame the window is open must be the REAL GO (the gate proof below shows a
    // feint can never flip phase==go, which is what isGoOpen is gated on).
    while (!g.isGoOpen && frames++ < 60 * 10) {
      // A solo bot resolves the draw itself; we only sample the window here.
      g.update(1 / 60);
      if (g.isGoOpen) sawGoOpen = true;
    }
    sawGoOpen = sawGoOpen || g.isGoOpen;
    expect(sawGoOpen, isTrue, reason: 'the real GO must eventually open');

    // Structural proof on the shared gate the duel reads: a lit feint keeps the
    // phase WAITING (so isGoOpen, gated on phase==go, can never be true on it).
    final gate = ReactionGate(SeededRng(4),
        minDelay: 3.0, maxDelay: 3.0, feints: 1, feintFlashSec: 0.25);
    var t = 0.0;
    while (!gate.feintActive && t < 3.0) {
      gate.update(1 / 120);
      t += 1 / 120;
    }
    expect(gate.feintActive, isTrue, reason: 'a feint must light');
    expect(gate.phase, ReactionPhase.waiting,
        reason: 'a feint is NOT the GO — the read stays a skill');
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

  // ── COMPETITIVE: skill gradient + beatable-but-tough hard bot ────────────────
  // The ANTI-SPAM / SHARP-READ tests above prove SKILL beats no-skill. This locks
  // in BALANCE. A SKILLED human-sim (seat 0) plays a clean 1v1 against ONE bot on
  // the BotProfile.forDifficulty gradient: it taps ONLY while the genuine GO is
  // open (g.isGoOpen — false through every feint, so it NEVER false-starts) and
  // only after a FIXED, fast-but-human reaction latency of [_humanLatencySec]
  // (0.22s) measured from the GO edge. So the duel comes down to reaction speed:
  // the hard bot (BotProfile reaction 0.16s) genuinely out-draws a 0.22s human on
  // its faster rolls, but its bounded skill-scaled draw-lag means it sometimes
  // draws a touch late and the sharp human banks the draw — beatable-but-tough.
  //
  // 1v1 is the clean head-to-head (a 4p win-rate measures "beat the FASTEST of
  // three independent bots", which is a different, much harder test and muddies
  // the gradient — see the separate 4p gradient check below).
  //
  // Measured over a fixed 12-seed sweep [1..12], reproduced on a DISJOINT window
  // [101..112] so a one-seed wobble can't flake the bands:
  //   1v1  easy 12/12 (1.00) | medium 12/12 (1.00) | hard 7/12 A, 6/12 B (.58/.50)
  // The locked bands are robust supersets of BOTH windows.
  const competitiveSeeds = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

  test(
      'COMPETITIVE: skill gradient + beatable-but-tough hard bot — a sharp '
      'human (fixed 0.22s reaction, never false-starts) crushes easy, and hard '
      'is a genuine contest', () {
    final easy = _skilledVsBot1v1(BotDifficulty.easy, competitiveSeeds);
    final medium = _skilledVsBot1v1(BotDifficulty.medium, competitiveSeeds);
    final hard = _skilledVsBot1v1(BotDifficulty.hard, competitiveSeeds);

    final n = competitiveSeeds.length;
    final winEasy = easy.wins / n;
    final winMedium = medium.wins / n;
    final winHard = hard.wins / n;

    // EASY clearly beatable: the sharp human wins the large majority (measured
    // 1.00; required >= 0.70).
    expect(winEasy, greaterThanOrEqualTo(0.70),
        reason: 'easy bot must be clearly beatable (win-rate $winEasy)');

    // HARD beatable-but-tough: inside the design band [0.15, 0.90] — NOT a wall
    // (the human wins some) and NOT a trivial pushover (the human loses some).
    // Measured 0.58 (A) / 0.50 (B); the band is a flake-proof superset.
    expect(winHard, greaterThanOrEqualTo(0.15),
        reason: 'hard bot must not be an unwinnable wall (win-rate $winHard)');
    expect(winHard, lessThanOrEqualTo(0.90),
        reason: 'hard bot must not be a trivial pushover (win-rate $winHard)');
    // Concretely: the human must WIN at least one seed AND LOSE at least one.
    expect(hard.wins, greaterThan(0),
        reason: 'a sharp human must steal at least one hard duel');
    expect(hard.wins, lessThan(n),
        reason: 'the hard bot must take at least one duel (not a pushover)');

    // GRADIENT: difficulty must matter, monotonically, with a real spread.
    expect(winEasy, greaterThanOrEqualTo(winMedium),
        reason: 'easy ($winEasy) must be >= medium ($winMedium)');
    expect(winMedium, greaterThanOrEqualTo(winHard),
        reason: 'medium ($winMedium) must be >= hard ($winHard)');
    expect(winEasy, greaterThan(winHard),
        reason: 'difficulty must matter: easy ($winEasy) > hard ($winHard)');

    // NOT luck-dominated: vs easy the sharp human wins EVERY seed (the
    // false-start discipline + reaction edge are decisive, not a coin-flip).
    expect(easy.wins, n,
        reason: 'vs easy the sharp human must win reliably across all seeds '
            '(${easy.wins}/$n)');

    // NO runaway: HARD outcomes must SWING seed-to-seed — best-of-3 draws can go
    // either way, so there must exist BOTH a seed the human sweeps and a seed the
    // bot sweeps. (Margin = human draws won − bot draws won; +3 = a 3–0 human
    // sweep, −3 = a 3–0 bot sweep.) Measured margins span [-3, +3].
    expect(hard.margins.any((m) => m >= 2), isTrue,
        reason: 'some hard seed must be a clear human win (margin >= +2)');
    expect(hard.margins.any((m) => m <= -2), isTrue,
        reason: 'some hard seed must be a clear human loss (margin <= -2)');
  });

  test('COMPETITIVE 4p: the gradient holds even out-numbered (3 bots gang up)',
      () {
    // 4p is the punishing config: the human must out-draw the FASTEST of three
    // independent bots every draw, so the win-rate is naturally far lower than
    // the 1v1 band — we assert the GRADIENT (easy still a walkover, hard strictly
    // harder), not the [0.15, 0.90] duel band. (Measured: easy 1.00, hard 0.00.)
    final easy = _skilledVsBot1v1(BotDifficulty.easy, competitiveSeeds, players: 4);
    final hard = _skilledVsBot1v1(BotDifficulty.hard, competitiveSeeds, players: 4);

    final n = competitiveSeeds.length;
    expect(easy.wins / n, greaterThanOrEqualTo(0.70),
        reason: 'a sharp human should still beat three easy bots reliably');
    expect(hard.wins, lessThan(easy.wins),
        reason: '4p gradient must hold: hard is strictly harder than easy');
  });
}

/// Skilled human-sim for the COMPETITIVE sweep: taps ONLY on the real GO
/// (g.isGoOpen — never on a feint, so it never false-starts) and only after a
/// FIXED, fast-but-human reaction latency measured from the GO edge. Models a
/// sharp duelist whose reaction speed (not luck) decides the contest.
const double _humanLatencySec = 0.22;

class _SkilledHuman {
  double _goOpenFor = -1; // seconds the GO has been open this draw (-1 = closed)
  bool _tappedThisGo = false;

  /// Advance one frame; returns true if the human should tap now.
  bool step(ReactionDuel g, double dt) {
    if (!g.isGoOpen) {
      _goOpenFor = -1;
      _tappedThisGo = false;
      return false;
    }
    _goOpenFor = _goOpenFor < 0 ? dt : _goOpenFor + dt;
    if (!_tappedThisGo && _goOpenFor >= _humanLatencySec) {
      _tappedThisGo = true;
      return true;
    }
    return false;
  }
}

/// Outcome of one difficulty sweep: matches the skilled human (seat 0) won, and
/// the per-seed draw margin (human draws won − best bot draws won).
class _SweepResult {
  final int wins;
  final List<int> margins;
  const _SweepResult(this.wins, this.margins);
}

/// Run the skilled human (seat 0) against [players]-1 bots at [diff] over
/// [seeds], one match per seed. Deterministic: the human is fixed-latency and
/// every bot draw is seeded via ctx.rng(seed).
_SweepResult _skilledVsBot1v1(
  BotDifficulty diff,
  List<int> seeds, {
  int players = 2,
}) {
  var wins = 0;
  final margins = <int>[];
  for (final seed in seeds) {
    final ctx = MiniGameContext(
      players: [
        PlayerSlot.defaults(0), // skilled human
        for (var i = 1; i < players; i++) PlayerSlot.defaults(i, isBot: true),
      ],
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(players),
      difficulty: diff,
    );
    final g = ReactionDuel()..init(ctx);
    final human = _SkilledHuman();

    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < 60 * 60) {
      if (human.step(g, 1 / 60)) g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
    }
    if (g.winResult!.ranking.first == 0) wins++;
    final s0 = g.scores.of(0).floor();
    var bestBot = 0;
    for (var i = 1; i < players; i++) {
      final si = g.scores.of(i).floor();
      if (si > bestBot) bestBot = si;
    }
    margins.add(s0 - bestBot);
  }
  return _SweepResult(wins, margins);
}
