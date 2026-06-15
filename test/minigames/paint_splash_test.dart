import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/helpers/area_fill_grid.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/paint_splash/paint_splash.dart';

void main() {
  MiniGameContext ctxFor(int n, int seed,
          {BotDifficulty difficulty = BotDifficulty.medium}) =>
      MiniGameContext(
        players: [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
        difficulty: difficulty,
      );

  /// Run to completion, returning the number of simulated frames (at 1/60 s).
  int runToEnd(PaintSplash g) {
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
    }
    return n;
  }

  // ── Invariants: finish / ranking / pacing for 1..4 players ──────────────────

  test('four bots finish with a full ranking', () {
    final g = PaintSplash()..init(ctxFor(4, 7));
    runToEnd(g);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('all-bot 4p round lasts well over the warmup but finishes in time', () {
    final g = PaintSplash()..init(ctxFor(4, 7));
    final frames = runToEnd(g);
    final simSeconds = frames / 60.0;
    // Never a blink-and-miss round: must outlast the ~1.5s bot warmup.
    expect(simSeconds, greaterThan(1.5));
    // And it must always resolve within the round's hard time limit (+1 frame).
    expect(g.status, MiniGameStatus.finished);
    expect(simSeconds, lessThanOrEqualTo(31.0));
  });

  test('finishes for 1..3 players', () {
    for (final n in [1, 2, 3]) {
      final g = PaintSplash()..init(ctxFor(n, 5 + n));
      runToEnd(g);
      expect(g.status, MiniGameStatus.finished, reason: 'n=$n');
      expect(g.winResult!.ranking.toSet(), {for (var p = 0; p < n; p++) p});
    }
  });

  test('bots roam + tap on their own, covering ground over the round', () {
    final g = PaintSplash()..init(ctxFor(4, 7));
    runToEnd(g);
    // Each self-driving bot should own a meaningful chunk of the shared board.
    for (var id = 0; id < 4; id++) {
      expect(g.scores.of(id), greaterThan(0), reason: 'bot $id painted nothing');
    }
  });

  // ── Grid economy (the substrate the chain rides on) ─────────────────────────

  test('overpaint flips a cell to the new owner (grid steal mechanic)', () {
    // The structural heart: the canvas is shared and paint is last-writer-wins,
    // so a splat over a rival's cell STEALS it. Verified directly on the grid.
    final grid = AreaFillGrid(cols: 30, rows: 38);
    const at = Offset(0.5, 0.5);
    const r = 0.06;

    grid.paintCircle(1, at, r);
    final ownedByOneBefore = grid.coverageOf(1);
    expect(ownedByOneBefore, greaterThan(0));
    expect(grid.ownerAt(15, 19), 1);

    grid.paintCircle(0, at, r);
    expect(grid.ownerAt(15, 19), 0,
        reason: 'painting over a rival cell must transfer ownership');
    expect(grid.coverageOf(0), greaterThan(0));
    expect(grid.coverageOf(1), lessThan(ownedByOneBefore),
        reason: 'the rival should lose the stolen cells');
  });

  test('paintCircleDelta reports gained / stolen / wasted correctly', () {
    // The chain extension test (gained/touched) and the dud-on-waste behavior
    // are charged from this accounting, so it must be exact.
    final grid = AreaFillGrid(cols: 30, rows: 38);
    const at = Offset(0.5, 0.5);
    const r = 0.06;

    final first = grid.paintCircleDelta(0, at, r);
    expect(first.gained, greaterThan(0));
    expect(first.stolen, 0, reason: 'empty canvas has nothing to steal');
    expect(first.wasted, 0, reason: 'fresh paint wastes nothing');

    final recoat = grid.paintCircleDelta(0, at, r);
    expect(recoat.gained, 0, reason: 're-coating my own cells gains nothing');
    expect(recoat.wasted, greaterThan(0),
        reason: 'mashing owned cells is pure waste (breaks the chain)');

    final raid = grid.paintCircleDelta(1, at, r);
    expect(raid.gained, greaterThan(0));
    expect(raid.stolen, raid.gained,
        reason: 'every gained cell here was taken from a rival');
  });

  test('a player taps over a rival on the shared canvas and steals turf', () {
    // Game-level proof of the steal on ONE shared canvas. Two humans, identical
    // setup. Final scores are each player's owned-cell count at the buzzer.
    //
    //  * Control: player 1 chain-taps the centre cluster; nobody contests it.
    //  * Raided: player 1 does the same, THEN player 0 taps the SAME cluster,
    //    painting over it → player 1 ends owning strictly LESS than in control.
    //
    // Deterministic: fixed seed, fixed inputs, no bots. Taps are spaced so the
    // can never sputters, so the steal is clean.
    const cluster = [
      Offset(0.48, 0.48),
      Offset(0.52, 0.50),
      Offset(0.50, 0.53),
      Offset(0.47, 0.52),
    ];
    const tapEvery = 20; // frames between taps (above the ink floor)
    const phaseATaps = 6; // player 1 lays this many taps first
    const phaseBStart = phaseATaps * tapEvery + 30;

    ({int p0, int p1}) runSteal({required bool rivalRaids}) {
      final g = PaintSplash()
        ..init(MiniGameContext(
          players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1)],
          arena: const Size(800, 1200),
          rng: SeededRng(4),
          zones: ZoneLayout.forPlayers(2),
        ));
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 45) {
        g.update(1 / 60);
        // Player 1 taps the cluster in phase A.
        if (frames <= phaseATaps * tapEvery && frames % tapEvery == 0) {
          final at = cluster[(frames ~/ tapEvery) % cluster.length];
          g.onInput(
              PlayerInput(playerId: 1, phase: InputPhase.down, normPos: at));
        }
        // Player 0 (optionally) raids the same cluster in phase B.
        if (rivalRaids &&
            frames > phaseBStart &&
            frames <= phaseBStart + phaseATaps * tapEvery &&
            frames % tapEvery == 0) {
          final at = cluster[(frames ~/ tapEvery) % cluster.length];
          g.onInput(
              PlayerInput(playerId: 0, phase: InputPhase.down, normPos: at));
        }
      }
      expect(g.status, MiniGameStatus.finished);
      return (p0: g.scores.of(0).toInt(), p1: g.scores.of(1).toInt());
    }

    final control = runSteal(rivalRaids: false);
    final raided = runSteal(rivalRaids: true);

    expect(control.p1, greaterThan(0), reason: 'player 1 must paint something');
    expect(raided.p0, greaterThan(0),
        reason: 'player 0 must own the cells it painted over');
    expect(raided.p1, lessThan(control.p1),
        reason: 'painting over player 1 must steal cells from it '
            '(control=${control.p1} raided=${raided.p1})');
  });

  test('a tap accumulates coverage into the score', () {
    // A solo human taps a few fresh spots; their score must reflect the paint.
    final g = PaintSplash()
      ..init(MiniGameContext(
        players: [PlayerSlot.defaults(0)],
        arena: const Size(800, 1200),
        rng: SeededRng(9),
        zones: ZoneLayout.forPlayers(1),
      ));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % 20 == 0 && n < 60 * 10) {
        final i = n ~/ 20;
        final at = Offset(0.2 + 0.1 * (i % 6), 0.2 + 0.1 * ((i ~/ 6) % 6));
        g.onInput(PlayerInput(playerId: 0, phase: InputPhase.down, normPos: at));
      }
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.scores.of(0), greaterThan(0));
  });

  // ── THE LAW: a one-spot masher / random tapper LOSES to a measured chainer ──

  // A solo human (no bots → the final score is exactly this player's coverage,
  // fully deterministic). [stopFrame], when set, stops all input at that frame
  // so a comparison can be cut off before the free-flow GOLD RUSH finale.
  int runSolo(
    int seed, {
    required void Function(PaintSplash g, int frame) drive,
    int? stopFrame,
  }) {
    final g = PaintSplash()
      ..init(MiniGameContext(
        players: [PlayerSlot.defaults(0)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(1),
      ));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (stopFrame != null && n > stopFrame) continue; // idle after cutoff
      drive(g, n);
    }
    expect(g.status, MiniGameStatus.finished);
    return g.scores.of(0).toInt();
  }

  // MASHER: tap the SAME spot as fast as possible (every frame). Each tap lands
  // on the same grid cell → the chain BREAKS every time (never grows past 0),
  // and the rapid tapping drains the ink can so most taps SPUTTER (dud radius,
  // no grid paint). The board barely grows beyond one small patch.
  void driveOneSpotMasher(PaintSplash g, int frame) {
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.5)));
  }

  // CHAINER: deliberate play. Tap a FRESH grid cell on a steady ~0.33s cadence
  // (20 frames) — slow enough that the ink can never empties, fast enough to
  // stay inside the chain window — walking a serpentine sweep so every tap is on
  // new ground. This BUILDS and sustains a long chain, so the splats swell and
  // each lands ink-cheap on fresh turf. "Read where the fresh turf is + keep the
  // combo alive" by the book.
  void driveMeasuredChainer(PaintSplash g, int frame) {
    const tapEvery = 20; // frames between taps (≈0.33s)
    if (frame % tapEvery != 0) return;
    const cols = 8;
    const rows = 8;
    final cell = frame ~/ tapEvery;
    // Serpentine so consecutive cells are always adjacent-but-different (a real
    // moving sweep), never re-tapping the same spot.
    final r = (cell ~/ cols) % rows;
    var cx = cell % cols;
    if (r.isOdd) cx = cols - 1 - cx; // reverse every other row
    final gx = 0.1 + 0.8 * (cx / (cols - 1));
    final gy = 0.1 + 0.8 * (r / (rows - 1));
    g.onInput(
        PlayerInput(playerId: 0, phase: InputPhase.down, normPos: Offset(gx, gy)));
  }

  // RANDOM TAPPER: taps every frame at a pseudo-random spot. It moves around (so
  // it isn't the masher) but has no cadence discipline — it drains the can and
  // sputters, and its erratic hops frequently miss the chain window / re-hit
  // owned turf, so it never builds a sustained chain.
  void driveRandomTapper(PaintSplash g, int frame) {
    // Cheap deterministic hash → a spot in [0.08, 0.92]^2.
    final h = (frame * 2654435761) & 0x7fffffff;
    final gx = 0.08 + 0.84 * ((h % 1000) / 1000.0);
    final gy = 0.08 + 0.84 * (((h ~/ 1000) % 1000) / 1000.0);
    g.onInput(
        PlayerInput(playerId: 0, phase: InputPhase.down, normPos: Offset(gx, gy)));
  }

  test('a one-spot masher ends with FAR less coverage than a measured chainer',
      () {
    // The headline invariant: mashing one spot cannot match deliberate chaining.
    // Same seed for both so the only difference is the input policy.
    final masher = runSolo(11, drive: driveOneSpotMasher);
    final chainer = runSolo(11, drive: driveMeasuredChainer);

    expect(masher, greaterThan(0), reason: 'sanity: the masher paints SOME');
    expect(chainer, greaterThan(masher),
        reason: 'a chainer must beat a one-spot masher '
            '(masher=$masher chainer=$chainer)');
    // And the gap must be decisive, not a coin-flip: chaining fresh turf covers
    // many times the footprint a single mashed, sputtering spot can.
    expect(chainer, greaterThan(masher * 3),
        reason: 'deliberate chaining should dominate, not edge out, mashing '
            '(masher=$masher chainer=$chainer)');
  });

  test('a random tapper also loses decisively to a measured chainer', () {
    // Even an input that moves around the board (so it isn't trivially the
    // one-spot masher) loses badly without cadence + chain discipline: frantic
    // tapping drains the can so it self-throttles to a few COLD dots. Cut at 22s
    // (pre-finale) so the deliberately spam-friendly free-flow GOLD RUSH climax
    // — designed to let a trailing kid mash back into it — isn't what's measured.
    const cutoffFrame = 22 * 60;
    final random = runSolo(15, drive: driveRandomTapper, stopFrame: cutoffFrame);
    final chainer =
        runSolo(15, drive: driveMeasuredChainer, stopFrame: cutoffFrame);
    expect(random, greaterThan(0),
        reason: 'sanity: the random tapper paints SOME');
    expect(chainer, greaterThan(random * 2),
        reason: 'a measured chainer must clearly out-cover a spam tapper '
            '(random=$random chainer=$chainer)');
  });

  test('the chain economy alone (no finale) already punishes mashing', () {
    // Tighter version that EXCLUDES the GOLD RUSH finale, proving the chain +
    // ink economy ALONE — not the free-flow climax — is what defeats mashing.
    // Both runs stop input at 22s (before the 24s..30s free-flow window) and
    // stay idle, so the finale paints nothing for EITHER run.
    const cutoffFrame = 22 * 60;
    final masher =
        runSolo(21, drive: driveOneSpotMasher, stopFrame: cutoffFrame);
    final chainer =
        runSolo(21, drive: driveMeasuredChainer, stopFrame: cutoffFrame);
    expect(chainer, greaterThan(masher),
        reason: 'chaining fresh turf beats mashing pre-finale '
            '(masher=$masher chainer=$chainer)');
    expect(chainer, greaterThan(masher * 3),
        reason: 'the pre-finale gap must be decisive '
            '(masher=$masher chainer=$chainer)');
  });

  test('chaining a sweep covers far more than tapping one spot the same number '
      'of times', () {
    // Direct mechanic proof, finale excluded. Both lay the SAME number of taps
    // on the SAME cadence (so ink + tap-count are equal); the ONLY difference is
    // WHERE: a fresh-cell sweep (builds a chain → fat splats) vs re-tapping a
    // single cell (chain stays 0 → base/dud splats). Solo human, one seed.
    const tapEvery = 20;
    const taps = 24; // ends ~8s in, well before the 24s finale
    const cutoff = taps * tapEvery + 5;

    int coverageFor({required bool sweep}) {
      final g = PaintSplash()
        ..init(MiniGameContext(
          players: [PlayerSlot.defaults(0)],
          arena: const Size(800, 1200),
          rng: SeededRng(30),
          zones: ZoneLayout.forPlayers(1),
        ));
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
        g.update(1 / 60);
        if (n > cutoff || n % tapEvery != 0) continue;
        final i = n ~/ tapEvery;
        if (i >= taps) continue;
        late Offset at;
        if (sweep) {
          const cols = 6;
          final r = (i ~/ cols) % cols;
          var cx = i % cols;
          if (r.isOdd) cx = cols - 1 - cx;
          at = Offset(0.12 + 0.76 * (cx / (cols - 1)),
              0.12 + 0.76 * (r / (cols - 1)));
        } else {
          at = const Offset(0.5, 0.5); // always the same cell
        }
        g.onInput(PlayerInput(playerId: 0, phase: InputPhase.down, normPos: at));
      }
      expect(g.status, MiniGameStatus.finished);
      return g.scores.of(0).toInt();
    }

    final oneSpot = coverageFor(sweep: false);
    final swept = coverageFor(sweep: true);
    expect(swept, greaterThan(oneSpot * 3),
        reason: 'same taps, same cadence: a fresh-cell chain must dwarf '
            're-tapping one spot (oneSpot=$oneSpot swept=$swept)');
  });

  test('GOLD RUSH: a single tap covers more in the finale than early', () {
    // CLIMAX mechanic. One quick tap at the same spot covers strictly MORE cells
    // during the GOLD RUSH finale than the same tap early in the round, because
    // the finale fattens the splat radius. Solo human so the score is exactly
    // that one player's coverage.
    int coverageForSingleTapAt(double warmupSeconds) {
      final g = PaintSplash()
        ..init(MiniGameContext(
          players: [PlayerSlot.defaults(0)],
          arena: const Size(800, 1200),
          rng: SeededRng(9),
          zones: ZoneLayout.forPlayers(1),
        ));
      var n = 0;
      var tapped = false;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
        g.update(1 / 60);
        if (!tapped && n / 60.0 >= warmupSeconds) {
          g.onInput(const PlayerInput(
              playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.5)));
          tapped = true;
        }
      }
      expect(g.status, MiniGameStatus.finished);
      return g.scores.of(0).toInt();
    }

    // Early single tap (~1s in, base radius) vs a tap inside the last ~6s GOLD
    // RUSH window of the 30s round (~27s in, fattened radius).
    final early = coverageForSingleTapAt(1.0);
    final finale = coverageForSingleTapAt(27.0);
    expect(finale, greaterThan(early),
        reason: 'a GOLD RUSH tap must paint a bigger footprint '
            '(early=$early finale=$finale)');
  });

  // ── Bots scale with difficulty (managed bots beat sloppy ones) ──────────────

  test('paint bots fill the board and resolve at both difficulties', () {
    // The skilled-vs-spam ordering (the design law) is proven by the human
    // chainer-vs-masher tests above, and the skilled-human-vs-bot gradient by the
    // COMPETITIVE test below. Difficulty is session-wide (one BotProfile per
    // game), so a head-to-head hard-vs-easy BOT pairing can't be staged inside a
    // single game; here we just sanity-check that an all-bot board fills up and
    // the round resolves at both ends of the dial.
    for (final d in <BotDifficulty>[BotDifficulty.easy, BotDifficulty.hard]) {
      for (final s in <int>[1, 3, 5]) {
        final g = PaintSplash()..init(ctxFor(4, s, difficulty: d));
        runToEnd(g);
        expect(g.status, MiniGameStatus.finished, reason: 'd=$d seed=$s');
        var total = 0.0;
        for (var id = 0; id < 4; id++) {
          total += g.scores.of(id).toDouble();
        }
        expect(total, greaterThan(0.0),
            reason: 'bots painted something (d=$d seed=$s)');
      }
    }
  });

  // ── COMPETITIVE: skill gradient + beatable-but-tough hard bot ───────────────
  //
  // A SKILLED human-sim in seat 0 (the serpentine fresh-cell chainer from the
  // spam-loses tests — steady ~0.33s cadence, always new ground, never breaks its
  // own chain) faces BOTS in the other seats. We measure seat-0 win-rate per
  // difficulty over a seed sweep. Territory is a multi-player contest, so the
  // CLEANEST skilled-vs-bot read is 2 players (one human, one bot); 4p is recorded
  // as a note (the human faces three ganging bots, so its win-rate is naturally
  // lower — still gradient-ordered).
  //
  // Bands are robust supersets of the measured values (12-seed window 1..12,
  // re-validated on the disjoint window 101..116 during tuning):
  //     2p   easy ~0.94   medium ~0.31   hard ~0.25–0.31
  // Tuned via the bot TAP-CADENCE dial (botTapIntervalMin/Max) + chain discipline;
  // the core tap-to-splat chain mechanic is untouched, so the spam-loses / finish
  // / no-throw invariants above all still hold.

  /// SKILLED chainer for seat 0 — identical policy to [driveMeasuredChainer]
  /// above (serpentine fresh-cell sweep over the whole shared board on a ~0.33s
  /// cadence), just over a 9x9 lattice so it roams the full canvas to claim/steal.
  void driveSkilledSeat0(PaintSplash g, int frame) {
    const tapEvery = 20; // ~0.33s — above the ink floor, inside the chain window
    if (frame % tapEvery != 0) return;
    const cols = 9, rows = 9;
    final cell = frame ~/ tapEvery;
    final r = (cell ~/ cols) % rows;
    var cx = cell % cols;
    if (r.isOdd) cx = cols - 1 - cx; // serpentine → always adjacent-but-fresh
    final gx = 0.06 + 0.88 * (cx / (cols - 1));
    final gy = 0.06 + 0.88 * (r / (rows - 1));
    g.onInput(
        PlayerInput(playerId: 0, phase: InputPhase.down, normPos: Offset(gx, gy)));
  }

  /// One contest: skilled human in seat 0 vs bots elsewhere. Returns whether
  /// seat 0 won (strictly the most cells) and its coverage margin over the best
  /// bot (signed fraction of the whole board).
  ({bool win, double margin}) runSkilledVsBots(
      int n, int seed, BotDifficulty d) {
    final g = PaintSplash()
      ..init(MiniGameContext(
        players: [
          PlayerSlot.defaults(0),
          for (var i = 1; i < n; i++) PlayerSlot.defaults(i, isBot: true),
        ],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
        difficulty: d,
      ));
    var f = 0;
    while (g.status != MiniGameStatus.finished && f++ < 60 * 120) {
      g.update(1 / 60);
      driveSkilledSeat0(g, f);
    }
    expect(g.status, MiniGameStatus.finished);
    final total = g.scores.byPlayer.values.fold<num>(0, (a, b) => a + b);
    final s0 = g.scores.of(0).toInt();
    var top = 0;
    for (var i = 1; i < n; i++) {
      final v = g.scores.of(i).toInt();
      if (v > top) top = v;
    }
    final margin = total == 0 ? 0.0 : (s0 - top) / total;
    return (win: s0 > top, margin: margin);
  }

  ({double winRate, double avgMargin, double minMargin, double maxMargin})
      sweepSkilled(int n, List<int> seeds, BotDifficulty d) {
    var wins = 0;
    var marginSum = 0.0, lo = 1e9, hi = -1e9;
    for (final s in seeds) {
      final r = runSkilledVsBots(n, s, d);
      if (r.win) wins++;
      marginSum += r.margin;
      if (r.margin < lo) lo = r.margin;
      if (r.margin > hi) hi = r.margin;
    }
    return (
      winRate: wins / seeds.length,
      avgMargin: marginSum / seeds.length,
      minMargin: lo,
      maxMargin: hi,
    );
  }

  test('COMPETITIVE: skill gradient + beatable-but-tough hard bot (2p, 12 seeds)',
      () {
    final seeds = [for (var s = 1; s <= 12; s++) s];
    final easy = sweepSkilled(2, seeds, BotDifficulty.easy);
    final medium = sweepSkilled(2, seeds, BotDifficulty.medium);
    final hard = sweepSkilled(2, seeds, BotDifficulty.hard);

    final dbg = 'easy=${easy.winRate.toStringAsFixed(2)} '
        'medium=${medium.winRate.toStringAsFixed(2)} '
        'hard=${hard.winRate.toStringAsFixed(2)} '
        '(easyMargin=${easy.avgMargin.toStringAsFixed(2)} '
        'hardMargin=${hard.avgMargin.toStringAsFixed(2)})';

    // EASY clearly beatable: a skilled human wins the large majority.
    expect(easy.winRate, greaterThanOrEqualTo(0.70),
        reason: 'easy bot should be clearly beatable — $dbg');

    // HARD beatable-but-tough: a real wall would be 0 (human never wins); a
    // pushover would be 1.0. It must sit strictly inside a tough-but-winnable
    // band.
    expect(hard.winRate, greaterThanOrEqualTo(0.15),
        reason: 'hard bot must not be an unbeatable WALL — $dbg');
    expect(hard.winRate, lessThanOrEqualTo(0.90),
        reason: 'hard bot must not be a trivial PUSHOVER — $dbg');

    // GRADIENT: harder bots win more (the human wins less). Monotone, with a
    // tiny epsilon so cadence jitter on a 12-seed window can't flip an equal
    // pair, plus a strict easy-beats-hard separation.
    const eps = 0.001;
    expect(easy.winRate, greaterThanOrEqualTo(medium.winRate - eps),
        reason: 'winEasy >= winMedium — $dbg');
    expect(medium.winRate, greaterThanOrEqualTo(hard.winRate - eps),
        reason: 'winMedium >= winHard — $dbg');
    expect(easy.winRate, greaterThan(hard.winRate),
        reason: 'winEasy must strictly exceed winHard — $dbg');

    // NOT luck-dominated: against the easy bot the skilled human wins reliably
    // across the whole seed window (not a coin-flip).
    expect(easy.winRate, greaterThanOrEqualTo(0.70),
        reason: 'skilled play must beat easy reliably, not by luck — $dbg');

    // NO runaway: territory can snowball, so prove outcomes VARY rather than one
    // side always burying the other. Across the difficulty dial both the human
    // and the bots take some rounds (a clean win AND a clean loss both occur),
    // and the per-seed margins span a real spread (a comeback range exists), not
    // a single pinned blowout.
    final someHumanWins = easy.winRate > 0.0; // human wins somewhere
    final someBotWins = hard.winRate < 1.0; // bot wins somewhere
    expect(someHumanWins && someBotWins, isTrue,
        reason: 'outcomes must vary across the dial (no universal blowout) — '
            '$dbg');
    expect(hard.maxMargin - hard.minMargin, greaterThan(0.10),
        reason: 'vs-hard margins must vary across seeds (comeback range '
            'exists), not a pinned runaway — '
            'hard[min=${hard.minMargin.toStringAsFixed(2)} '
            'max=${hard.maxMargin.toStringAsFixed(2)}]');
  });

  // ── Render never throws ─────────────────────────────────────────────────────

  test('render does not throw', () {
    final g = PaintSplash()..init(ctxFor(4, 3));
    final canvas = Canvas(PictureRecorder());
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    g.update(1 / 60);
    g.onInput(const PlayerInput(
        playerId: 1, phase: InputPhase.down, normPos: Offset(0.75, 0.75)));
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });

  test('render does not throw across the whole round (incl. finale cues + chain '
      'badge + break dud)', () {
    // Drives a full round with a human who BOTH chains (fresh taps) and breaks
    // (re-tapping one spot) so the chain badge, the ▼ BREAK dud, the GOLD RUSH
    // banner, the lead-flip slow-mo and the final WINNER bigMoment all render.
    final g = PaintSplash()..init(ctxFor(3, 8));
    final canvas = Canvas(PictureRecorder());
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      if (n % 14 == 0) {
        // Alternate: chain to a fresh cell, then mash the centre to break it.
        final isChain = (n ~/ 14).isEven;
        final at = isChain
            ? Offset(0.15 + 0.7 * (((n ~/ 14) % 6) / 5.0),
                0.15 + 0.7 * (((n ~/ 14) % 4) / 3.0))
            : const Offset(0.5, 0.5);
        g.onInput(PlayerInput(playerId: 0, phase: InputPhase.down, normPos: at));
      }
      expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    }
    // One more render on the finished frame (winner banner + confetti).
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    expect(g.status, MiniGameStatus.finished);
  });
}
