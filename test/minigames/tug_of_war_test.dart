import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
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

  test('render does not throw before, during, or after resolution', () {
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(3),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = TugOfWar()..init(ctx);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    // Render at start, then periodically through the whole round (covers the
    // heave/slip cues + the win cinematic) — none of it may throw.
    expect(() => g.render(canvas, ctx.arena), returnsNormally);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
      if (n % 30 == 0) {
        expect(() => g.render(canvas, ctx.arena), returnsNormally);
      }
    }
    expect(() => g.render(canvas, ctx.arena), returnsNormally);
  });

  // ── On-beat HEAVE behavior (one-touch, rhythm + nerve) ─────────────────────
  //
  // These drive a SINGLE top-side human (id 0, even → top). With no opponent the
  // marker only swings on this player's taps: a heave toward the top reads as
  // score (max(0, -marker)). [beatWindowOpenForTest] lets each run tap exactly
  // when the sweet-spot is open, so the only variable is HOW it is tapped.

  /// Advance [g] one frame at a time until the beat sweet-spot opens (bounded).
  void advanceToWindow(TugOfWar g) {
    var guard = 0;
    while (!g.beatWindowOpenForTest && guard++ < 600) {
      g.update(1 / 60);
    }
  }

  /// Advance until the sweet-spot CLOSES (bounded), so the next tap re-arms (the
  /// heave latch re-arms only once the beat leaves the sweet-spot).
  void advancePastWindow(TugOfWar g) {
    var guard = 0;
    while (g.beatWindowOpenForTest && guard++ < 600) {
      g.update(1 / 60);
    }
  }

  /// A fresh 1p top-side game (single human, no bots).
  TugOfWar solo1p() {
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0)], // single human, top side
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(1),
    );
    return TugOfWar()..init(ctx);
  }

  test('heave: one on-beat tap drags the marker toward the goal (positive score)',
      () {
    final g = solo1p();
    advanceToWindow(g);
    g.onInput(PlayerInput.down(0)); // a single tap inside the sweet-spot
    g.update(1 / 60); // let the heave settle into the marker
    expect(g.scores.of(0).toDouble(), greaterThan(0),
        reason: 'a clean on-beat tap must move the rope toward the goal');
  });

  test('heave: an OFF-BEAT tap does not pull — it slips (zero advantage)', () {
    final g = solo1p();
    advancePastWindow(g); // make sure the sweet-spot is CLOSED
    expect(g.beatWindowOpenForTest, isFalse);
    g.onInput(PlayerInput.down(0)); // tap with the window shut → a MISS/slip
    g.update(1 / 60);
    // A miss recoils the marker toward the opponent (down/+), so top advantage
    // (max(0, -marker)) stays pinned at zero — off-beat taps never pull.
    expect(g.scores.of(0).toDouble(), 0,
        reason: 'an off-beat tap must not drag the rope toward the goal');
  });

  test('heave: a SECOND tap inside the same window misses (one heave per beat)',
      () {
    // One clean heave, then immediately a second tap in the SAME open window.
    final g = solo1p();
    advanceToWindow(g);
    g.onInput(PlayerInput.down(0)); // heave (consumes the armed beat)
    g.update(1 / 60);
    final afterFirst = g.scores.of(0).toDouble();
    g.onInput(PlayerInput.down(0)); // repeat tap, same window → MISS/slip
    g.update(1 / 60);
    final afterSecond = g.scores.of(0).toDouble();
    expect(afterFirst, greaterThan(0));
    expect(afterSecond, lessThan(afterFirst),
        reason: 'a double-tap in one window must slip back the gained ground');
  });

  // ── THE VISIBLE SKILL: ROPE TENSION → POWER HEAVE ──────────────────────────
  //
  // The rework makes the skill VISIBLE: clean centered heaves wind a per-side
  // ROPE TENSION meter; once it is TAUT a heave is a POWER HEAVE (2–3× pull),
  // while a SLACK heave is a dud. These drive the meter directly via the
  // @visibleForTesting hooks so the payoff curve is asserted with no reliance on
  // exact beat timing.

  test('tension: a chain of clean centered heaves winds the rope TAUT', () {
    // A single human, no opponent. Tap once, dead-center, on each beat window.
    // Tension must start SLACK (0) and climb past the POWER-HEAVE threshold as the
    // chain lands — the meter is the visible, learnable cue.
    final g = solo1p();
    expect(g.tensionForTest(0), 0, reason: 'tension starts slack');

    var reachedTaut = false;
    for (var beat = 0; beat < 8 && !reachedTaut; beat++) {
      advanceToWindow(g);
      // Tap only at/near dead-center so each heave winds maximum tension.
      var guard = 0;
      while (g.beatPrecisionForTest < 0.95 && guard++ < 60) {
        g.update(1 / 60);
      }
      g.onInput(PlayerInput.down(0));
      g.update(1 / 60);
      if (g.tensionForTest(0) >= TugOfWar.tautThresholdForTest) {
        reachedTaut = true;
      }
      advancePastWindow(g); // re-arm for the next beat
    }
    expect(reachedTaut, isTrue,
        reason: 'steady centered heaves must wind the rope into the TAUT band');
  });

  test('power heave: a TAUT heave hauls multiples of a SLACK one', () {
    // Drive the same dead-center heave at two tensions and compare how far each
    // dragged the marker. The TAUT (fully wound) heave must out-haul the SLACK one
    // by at least ~2× — the whole risk/reward of reading the meter.
    final slack = solo1p();
    final slackPull = slack.driveHeaveAtTensionForTest(0, 0.0);
    final taut = solo1p();
    final tautPull = taut.driveHeaveAtTensionForTest(0, 1.0);
    expect(slackPull, greaterThan(0), reason: 'even a slack heave nudges the rope');
    expect(tautPull, greaterThan(slackPull * 2.0),
        reason: 'a TAUT power heave must haul at least twice a slack dud');
  });

  // ── THE ANTI-MASH PROOF: a blind spammer LOSES the rope to an on-beat tapper ─
  //
  // Two HUMANS, head-to-head, no bots (id 0 even → top, id 1 odd → bottom). Both
  // see the same shared beat. The SPAMMER (top) taps EVERY frame, ignoring the
  // beat; the RHYTHM player (bottom) taps EXACTLY ONCE each time the sweet-spot
  // opens. Everything is deterministic (ctx.rng only drives bots/juice, and there
  // are no bots here), so this is a stable proof: the masher lands one weak
  // edge-heave per beat and then SLIPS on every other tap, netting BACKWARD,
  // while the clean tapper hauls the rope home. The rhythm player must win.
  test('BLIND SPAMMER loses the rope to an ON-BEAT tapper (deterministic)', () {
    final players = [
      PlayerSlot.defaults(0), // human, top  → the blind SPAMMER
      PlayerSlot.defaults(1), // human, bottom → the RHYTHM player
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(2, mode: GameMode.duel1v1),
      mode: GameMode.duel1v1,
    );
    final g = TugOfWar()..init(ctx);

    var rhythmArmed = true; // the rhythm player taps once per window open
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      // SPAMMER: mash every single frame, blind to the beat.
      g.onInput(PlayerInput.down(0));

      // RHYTHM: a single deliberate tap on the leading edge of each open window.
      final open = g.beatWindowOpenForTest;
      if (open && rhythmArmed) {
        g.onInput(PlayerInput.down(1));
        rhythmArmed = false;
      } else if (!open) {
        rhythmArmed = true; // re-arm once the window has closed
      }

      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished,
        reason: 'the contest must resolve');
    // The rhythm player (bottom, id 1) must take the rope outright.
    expect(g.winResult!.winner, 1,
        reason: 'an on-beat tapper must beat a blind masher');
    // And the masher must be driven the WRONG way: with the marker resolved on
    // the bottom half, the top spammer never gained ground (score pinned at 0).
    expect(g.scores.of(0).toDouble(), 0,
        reason: 'blind mashing slips itself backward — it never pulls home');
    expect(g.scores.of(1).toDouble(), greaterThan(0),
        reason: 'the rhythm player dragged the rope to its goal');
  });

  test('skill gap: an on-beat tapper out-pulls a blind masher head-to-head '
      '(score margin is decisive)', () {
    // Same setup as the proof, but measured as a SCORE MARGIN at a fixed horizon
    // (no reliance on who crosses the line first) — the on-beat side must lead by
    // a wide, unambiguous margin, so spam can't merely tie.
    final players = [
      PlayerSlot.defaults(0), // SPAMMER, top
      PlayerSlot.defaults(1), // RHYTHM, bottom
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(21),
      zones: ZoneLayout.forPlayers(2, mode: GameMode.duel1v1),
      mode: GameMode.duel1v1,
    );
    final g = TugOfWar()..init(ctx);

    var rhythmArmed = true;
    var n = 0;
    // Stop short of a forced finish to read the live margin mid-contest.
    while (g.status != MiniGameStatus.finished && n++ < 60 * 6) {
      g.onInput(PlayerInput.down(0)); // blind mash
      final open = g.beatWindowOpenForTest;
      if (open && rhythmArmed) {
        g.onInput(PlayerInput.down(1));
        rhythmArmed = false;
      } else if (!open) {
        rhythmArmed = true;
      }
      g.update(1 / 60);
    }

    final spammer = g.scores.of(0).toDouble();
    final rhythm = g.scores.of(1).toDouble();
    expect(rhythm, greaterThan(0),
        reason: 'the on-beat tapper is hauling the rope home');
    expect(rhythm, greaterThan(spammer + 0.2),
        reason: 'the on-beat side must lead by a decisive margin, not a tie');
  });

  // ── THE POWER-HEAVE PROOF: a TENSION READER buries a SLACK MASHER ───────────
  //
  // The rework's headline claim, made deterministic. Two HUMANS, no bots (id 0
  // top, id 1 bottom). The MASHER (top) taps EVERY frame: it lands one SLACK dud
  // per window then SLIPS on every other tap, so its ROPE TENSION is dumped to
  // ~zero and pinned SLACK — it can NEVER power heave. The READER (bottom) taps
  // once per window, near dead-center, building tension into the TAUT band and
  // POWER-HEAVING. The reader must take the rope outright AND by a wide margin —
  // proving the visible tension read, not raw tap rate, is what wins.
  test('TENSION READER buries a SLACK MASHER outright (deterministic)', () {
    final players = [
      PlayerSlot.defaults(0), // human, top → SLACK MASHER (taps every frame)
      PlayerSlot.defaults(1), // human, bottom → TENSION READER (one centered tap)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(13),
      zones: ZoneLayout.forPlayers(2, mode: GameMode.duel1v1),
      mode: GameMode.duel1v1,
    );
    final g = TugOfWar()..init(ctx);

    var readerArmed = true;
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      // MASHER: blind frame-by-frame spam.
      g.onInput(PlayerInput.down(0));
      // READER: a single deliberate tap once the beat is near dead-center, so each
      // heave winds maximum tension toward a POWER HEAVE.
      final open = g.beatWindowOpenForTest;
      if (open && readerArmed && g.beatPrecisionForTest >= 0.85) {
        g.onInput(PlayerInput.down(1));
        readerArmed = false;
      } else if (!open) {
        readerArmed = true;
      }
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished, reason: 'the contest must resolve');
    expect(g.winResult!.winner, 1,
        reason: 'the tension reader (power heaves) must beat the slack masher');
    // The masher never gets the marker to its half — its tension stays slack and
    // its slips drive it backward, so its advantage is pinned at zero.
    expect(g.scores.of(0).toDouble(), 0,
        reason: 'a slack masher slips itself backward — it never pulls home');
    // The reader's POWER HEAVES haul the rope decisively home.
    expect(g.scores.of(1).toDouble(), greaterThan(0.5),
        reason: 'reading the tension and power-heaving wins by a wide margin');
  });

  // ── Uneven-teams fairness (a lone puller vs two) ──────────────────────────
  //
  // A single top-side human (id 0, even → top) does ONE on-beat heave, measured
  // before the bot warmup ends (so the bots never pull and the marker moves only
  // on the human's heave). With two bottom-side opponents (3p ⇒ 1-vs-2) the lone
  // puller's HEAVE is multiplied (~1.9x), so its single tap drags the marker
  // markedly FURTHER than the same tap with no opponents (an even 1-side roster).

  /// One on-beat heave for top-side id 0 with [players], returning its advantage
  /// (how far the marker was dragged toward the top goal). The whole heave lands
  /// inside the 1.0s bot warmup, so any bot opponents stay idle and only the
  /// human moves the rope — isolating the underdog pull multiplier.
  double oneHeaveAdvantage(List<PlayerSlot> players) {
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(players.length),
    );
    final g = TugOfWar()..init(ctx);
    advanceToWindow(g); // reach the sweet-spot (well within warmup)
    g.onInput(PlayerInput.down(0)); // a single on-beat tap → one heave
    g.update(1 / 60); // let the fired heave settle into the marker
    return g.scores.of(0).toDouble();
  }

  test('fairness: a lone puller (1-vs-2) out-pulls the same heave with no opponent',
      () {
    // Even roster: a single top-side puller with no opponent ⇒ multiplier 1.0.
    final solo = oneHeaveAdvantage([PlayerSlot.defaults(0)]);
    // Short-handed roster: id 0 (top) vs two bottom bots (ids 1, 3) ⇒ deficit 1,
    // so the lone puller's heave is boosted ~1.9x.
    final underdog = oneHeaveAdvantage([
      PlayerSlot.defaults(0), // human, top
      PlayerSlot.defaults(1, isBot: true), // bot, bottom
      PlayerSlot.defaults(3, isBot: true), // bot, bottom
    ]);
    expect(solo, greaterThan(0), reason: 'a clean heave must move the marker');
    expect(underdog, greaterThan(solo * 1.5),
        reason: 'the short-handed side must pull markedly harder per heave');
  });

  test('fairness: even teams (1v1) keep the neutral pull multiplier', () {
    // A balanced split (id 0 top vs id 1 bottom) has zero deficit, so the lone
    // heave pulls exactly as far as the no-opponent baseline — even modes
    // untouched.
    final solo = oneHeaveAdvantage([PlayerSlot.defaults(0)]);
    final even = oneHeaveAdvantage([
      PlayerSlot.defaults(0), // human, top
      PlayerSlot.defaults(1, isBot: true), // bot, bottom (idle during warmup)
    ]);
    expect(even, closeTo(solo, 1e-9),
        reason: 'an even split must not change the pull multiplier');
  });

  // ── COMPETITIVE: skill gradient + beatable-but-tough hard bot ────────────────
  //
  // The permanent competitiveness contract for Tug of War, measured head-to-head:
  // a SKILLED human (one tap per beat, at dead-CENTER for max pull — the optimal
  // play) on top (id 0) vs ONE bot on the bottom (id 1), across all three tiers.
  // 1v1 is the clean read: the all-bot harness can't show a curve (equal-skill
  // bots tug to a draw), and team modes blur it; head-to-head exposes the slope.
  //
  // Measured (this build, deterministic), skilled human win-rate over the bot:
  //   window A seeds 1..12  → easy 12/12, medium 12/12, hard 5/12
  //   window B seeds 13..24 → easy 12/12, medium 12/12, hard 5/12  (disjoint)
  //   combined 24 seeds     → easy 24/24, medium 24/24, hard 10/24 (~0.417)
  // hard avg margin hovers near zero (±0.07) with W/L flipping seed to seed — a
  // genuine coin-flip wall, not a 0-win brick and not a 1.0 pushover. The bands
  // below are robust SUPERSETS of those values (easy ≥ 0.70, hard within
  // ~[0.15, 0.90]), and the whole 24-seed window is asserted so the proof spans
  // the seeds the bands were validated on (A ∪ B). No retune was needed.

  /// Skilled-human (seat 0, top) wins over a single [diff] bot across [seeds]
  /// 1v1 rounds, indexing seeds from [seedFrom] so disjoint windows can be swept.
  /// Models the OPTIMAL play: exactly one tap per beat window, fired only at/near
  /// dead-center (precision ≥ 0.9) so every heave winds maximum tension toward a
  /// POWER HEAVE — never an off-beat slip, never a double-tap.
  int skilledHumanWins(BotDifficulty diff, {int seeds = 12, int seedFrom = 1}) {
    var wins = 0;
    for (var s = seedFrom; s < seedFrom + seeds; s++) {
      final g = TugOfWar()
        ..init(MiniGameContext(
          players: [
            PlayerSlot.defaults(0), // skilled human, top
            PlayerSlot.defaults(1, isBot: true), // bot, bottom
          ],
          arena: const Size(800, 1200),
          rng: SeededRng(s * 7 + 1),
          zones: ZoneLayout.forPlayers(2, mode: GameMode.duel1v1),
          mode: GameMode.duel1v1,
          difficulty: diff,
        ));
      var tappedThisWindow = false;
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 40) {
        final open = g.beatWindowOpenForTest;
        if (!open) tappedThisWindow = false;
        if (open && !tappedThisWindow && g.beatPrecisionForTest >= 0.9) {
          g.onInput(PlayerInput.down(0)); // one centered tap per window
          tappedThisWindow = true;
        }
        g.update(1 / 60);
      }
      if (g.winResult!.winner == 0) wins++;
    }
    return wins;
  }

  test('COMPETITIVE: skill gradient + beatable-but-tough hard bot', () {
    // 24 seeds = window A (1..12) ∪ window B (13..24); the bands are robust
    // supersets of the measured win-rates and were validated on both windows.
    const seeds = 24;
    final easy = skilledHumanWins(BotDifficulty.easy, seeds: seeds);
    final medium = skilledHumanWins(BotDifficulty.medium, seeds: seeds);
    final hard = skilledHumanWins(BotDifficulty.hard, seeds: seeds);
    final easyRate = easy / seeds;
    final hardRate = hard / seeds;

    // EASY clearly beatable (win-rate ≥ 0.70). Measured 1.000; floor is a wide
    // superset so a sloppy CPU never becomes a coin-flip.
    expect(easyRate, greaterThanOrEqualTo(0.70),
        reason: 'a clean on-beat human must clearly beat the easy CPU '
            '(got $easy/$seeds = ${easyRate.toStringAsFixed(3)})');

    // HARD beatable-but-tough: inside ~[0.15, 0.90] — NOT a wall (0, impossible)
    // and NOT a trivial pushover (1.0). Measured 0.417 on both windows.
    expect(hardRate, greaterThanOrEqualTo(0.15),
        reason: 'the hard CPU must stay beatable by perfect timing, not a wall '
            '(got $hard/$seeds = ${hardRate.toStringAsFixed(3)})');
    expect(hardRate, lessThanOrEqualTo(0.90),
        reason: 'the hard CPU must remain a real challenge, not a pushover '
            '(got $hard/$seeds = ${hardRate.toStringAsFixed(3)})');

    // GRADIENT: winEasy ≥ winMedium ≥ winHard AND winEasy > winHard, so the
    // difficulty dial monotonically tightens and easy is strictly easier than
    // hard (the setting genuinely means something).
    expect(easy, greaterThanOrEqualTo(medium),
        reason: 'easy must be at least as winnable as medium '
            '(easy $easy vs medium $medium)');
    expect(medium, greaterThanOrEqualTo(hard),
        reason: 'medium must be at least as winnable as hard '
            '(medium $medium vs hard $hard)');
    expect(easy, greaterThan(hard),
        reason: 'easy must be strictly more winnable than hard '
            '(easy $easy vs hard $hard)');

    // NOT luck-dominated: against the easy CPU a skilled human wins reliably
    // (re-stated as a count floor so a single lucky seed can't carry it).
    expect(easy, greaterThanOrEqualTo((seeds * 0.70).ceil()),
        reason: 'skill must beat the easy CPU across seeds, not by luck '
            '(got $easy/$seeds)');

    // NO runaway: hard outcomes VARY across seeds (neither a 0-win brick nor a
    // 24-win sweep), proving comebacks happen and no side runs away unbeatably.
    expect(hard, greaterThan(0),
        reason: 'hard must be winnable on some seeds (comeback exists)');
    expect(hard, lessThan(seeds),
        reason: 'hard must take some seeds off the human (no human runaway)');
  });
}
