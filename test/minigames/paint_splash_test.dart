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

  test('bots roam + spray on their own, covering ground over the round', () {
    final g = PaintSplash()..init(ctxFor(4, 7));
    runToEnd(g);
    // Each self-driving bot should own a meaningful chunk of the shared board.
    for (var id = 0; id < 4; id++) {
      expect(g.scores.of(id), greaterThan(0), reason: 'bot $id painted nothing');
    }
  });

  // ── Grid economy (the lever that makes blind spraying lose) ─────────────────

  test('overpaint flips a cell to the new owner (grid steal mechanic)', () {
    // The structural heart of the redesign: the canvas is shared and paint is
    // last-writer-wins, so painting over a rival's cell STEALS it. Verified
    // directly on the grid: player 1 owns a spot, then player 0 paints the same
    // spot and the cell's owner flips to 0, while player 1's coverage drops.
    final grid = AreaFillGrid(cols: 30, rows: 38);
    const at = Offset(0.5, 0.5);
    const r = 0.06;

    grid.paintCircle(1, at, r);
    final ownedByOneBefore = grid.coverageOf(1);
    expect(ownedByOneBefore, greaterThan(0));
    // The exact center cell belongs to player 1.
    expect(grid.ownerAt(15, 19), 1);

    grid.paintCircle(0, at, r);
    // The overlapping cells flipped from 1 to 0.
    expect(grid.ownerAt(15, 19), 0,
        reason: 'painting over a rival cell must transfer ownership');
    expect(grid.coverageOf(0), greaterThan(0));
    expect(grid.coverageOf(1), lessThan(ownedByOneBefore),
        reason: 'the rival should lose the stolen cells');
  });

  test('paintCircleDelta reports gained / stolen / wasted correctly', () {
    // The ink economy is charged from this accounting, so it must be exact:
    //  * First stroke on empty canvas: every cell is GAINED, none stolen/wasted.
    //  * Re-coating the SAME spot: nothing gained, every cell WASTED (this is
    //    what drains a parked brush's ink for no new ground).
    //  * A rival painting over it: those cells are gained AND counted as stolen.
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
        reason: 'parking on owned cells is pure waste');

    final raid = grid.paintCircleDelta(1, at, r);
    expect(raid.gained, greaterThan(0));
    expect(raid.stolen, raid.gained,
        reason: 'every gained cell here was taken from a rival');
  });

  test('overpaint via paintCircle still works (back-compat delegation)', () {
    // paintCircle now delegates to paintCircleDelta; its observable behavior
    // (last-writer-wins ownership) must be unchanged.
    final grid = AreaFillGrid(cols: 8, rows: 8);
    grid.paintCircle(2, const Offset(0.5, 0.5), 1.0); // cover all
    expect(grid.coverageOf(2), grid.totalCells);
    grid.paintCircle(3, const Offset(0.5, 0.5), 1.0); // steal all
    expect(grid.coverageOf(3), grid.totalCells);
    expect(grid.coverageOf(2), 0);
  });

  test('a player paints over a rival on the shared canvas and steals turf', () {
    // Game-level proof of the steal on ONE shared canvas. Two humans, identical
    // setup. Final scores are each player's owned-cell count at the buzzer.
    //
    //  * Control: player 1 holds the centre for ~1s and nobody contests it →
    //    player 1 ends owning that whole patch (its uncontested coverage).
    //  * Raided: player 1 holds the centre for ~1s, THEN player 0 holds the SAME
    //    centre for ~1s, painting over it → player 0 ends owning the overlap and
    //    player 1 ends owning strictly LESS than in the control run.
    //
    // Deterministic: fixed seed, fixed inputs, no bots, no other touches. Both
    // ~1s holds stay above the ink sputter floor, so the steal is clean.
    const center = Offset(0.5, 0.5);
    const phaseA = 60; // ~1s: player 1 paints the centre
    const phaseB = 120; // then ~1s: (optionally) player 0 overpaints it

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
        if (frames <= phaseA) {
          g.onInput(frames == 1
              ? const PlayerInput(
                  playerId: 1, phase: InputPhase.down, normPos: center)
              : const PlayerInput(
                  playerId: 1, phase: InputPhase.holdTick, dt: 1 / 60));
        } else if (rivalRaids && frames <= phaseB) {
          g.onInput(frames == phaseA + 1
              ? const PlayerInput(
                  playerId: 0, phase: InputPhase.down, normPos: center)
              : const PlayerInput(
                  playerId: 0, phase: InputPhase.holdTick, dt: 1 / 60));
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

  test('held spray accumulates coverage into the score', () {
    final g = PaintSplash()..init(ctxFor(2, 9));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      // Hold a touch for player 0: a down then per-frame held ticks keep the
      // brush spraying (mirrors a finger held on the screen).
      if (n == 1) {
        g.onInput(const PlayerInput(
            playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.75)));
      } else {
        g.onInput(const PlayerInput(
            playerId: 0, phase: InputPhase.holdTick, dt: 1 / 60));
      }
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.scores.of(0), greaterThan(0));
  });

  // ── THE LAW: blind hold-spray must LOSE to deliberate play ──────────────────

  // A solo human (no bots → the final score is exactly this player's coverage,
  // fully deterministic). [stopFrame], when set, lifts the finger at that frame
  // so a comparison can be cut off before the free-flow finale.
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
      if (stopFrame != null && n > stopFrame) {
        g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
        continue;
      }
      drive(g, n);
    }
    expect(g.status, MiniGameStatus.finished);
    return g.scores.of(0).toInt();
  }

  // BLIND: press down once at the centre and HOLD forever, never moving. The can
  // drains and then SPUTTERS (dud splats that paint nothing), and every real
  // splat re-coats cells it already owns (full waste surcharge) — so it stalls
  // at one small patch.
  void driveBlindHold(PaintSplash g, int frame) {
    g.onInput(frame == 1
        ? const PlayerInput(
            playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.5))
        : const PlayerInput(playerId: 0, phase: InputPhase.holdTick, dt: 1 / 60));
  }

  // MANAGED: deliberate play. Real held BURSTS (down, then holdTicks so paint
  // flows on the natural ~0.085s cadence) separated by long RELEASES so the can
  // stays full and NEVER sputters, AND the brush hops to a FRESH grid cell on
  // every burst (a serpentine sweep). 12 held + 24 released frames keeps ink
  // net-positive (release ≫ the 1.54:1 ratio the recharge needs), so every
  // splat lands ink-cheap on new ground. This is "manage ink + target fresh
  // turf" by the book.
  void driveManagedSweep(PaintSplash g, int frame) {
    const burst = 12;
    const rest = 24;
    const cols = 6;
    const rows = 6;
    final phase = frame % (burst + rest);
    if (phase >= burst) {
      g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
      return;
    }
    final cell = frame ~/ (burst + rest);
    final gx = 0.1 + 0.8 * ((cell % cols) / (cols - 1));
    final gy = 0.1 + 0.8 * (((cell ~/ cols) % rows) / (rows - 1));
    final at = Offset(gx, gy);
    // First frame of each burst: a fresh DOWN at the new cell (lays one splat
    // immediately + steers there). Following burst frames: holdTicks keep it
    // flowing at the spray cadence without re-snapping the splat timer.
    g.onInput(phase == 0
        ? PlayerInput(playerId: 0, phase: InputPhase.down, normPos: at)
        : const PlayerInput(playerId: 0, phase: InputPhase.holdTick, dt: 1 / 60));
  }

  test('a blind hold-sprayer ends with LESS coverage than a managed player', () {
    // The headline invariant: no-skill holding cannot match deliberate ink + aim.
    // Same seed for both so the only difference is the input policy.
    final blind = runSolo(11, drive: driveBlindHold);
    final managed = runSolo(11, drive: driveManagedSweep);

    expect(blind, greaterThan(0), reason: 'sanity: the blind brush paints SOME');
    expect(managed, greaterThan(blind),
        reason: 'managed ink + fresh-turf aim must beat blind holding '
            '(blind=$blind managed=$managed)');
    // And the gap must be decisive, not a coin-flip: a sweeper covers many times
    // the footprint a single parked, sputtering brush can.
    expect(managed, greaterThan(blind * 3),
        reason: 'deliberate play should dominate, not edge out, blind holding '
            '(blind=$blind managed=$managed)');
  });

  test('the ink economy alone (no finale) already punishes blind holding', () {
    // Tighter version of the law that EXCLUDES the DOUBLE INK finale, proving
    // the ink economy ALONE — not the free-flow climax — is what defeats blind
    // holding. Both runs lift the finger at 22s (before the 24s..30s free-flow
    // window) and stay idle after, so the finale paints nothing for EITHER run;
    // the whole difference comes from the first 22s of input policy.
    const cutoffFrame = 22 * 60;
    final blind = runSolo(21, drive: driveBlindHold, stopFrame: cutoffFrame);
    final managed =
        runSolo(21, drive: driveManagedSweep, stopFrame: cutoffFrame);
    expect(managed, greaterThan(blind),
        reason: 'paced ink + fresh-turf sweep beats blind holding pre-finale '
            '(blind=$blind managed=$managed)');
  });

  test('DOUBLE INK: a single splat covers more in the finale than early', () {
    // CLIMAX mechanic. One quick tap (a single splat) at the same spot covers
    // strictly MORE cells during the DOUBLE INK finale than the same tap early
    // in the round, because the finale fattens the splat radius. Solo human so
    // the score is exactly that one player's coverage.
    int coverageForSingleTapAt(double warmupSeconds) {
      final ctx = MiniGameContext(
        players: [PlayerSlot.defaults(0)], // lone human
        arena: const Size(800, 1200),
        rng: SeededRng(9),
        zones: ZoneLayout.forPlayers(1),
      );
      final g = PaintSplash()..init(ctx);
      var n = 0;
      var tapped = false;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
        g.update(1 / 60);
        if (!tapped && n / 60.0 >= warmupSeconds) {
          // A single down splat at the zone center; do not hold (no follow-up
          // ticks) so exactly one splat lands and we measure its footprint.
          g.onInput(const PlayerInput(
              playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.5)));
          tapped = true;
        }
      }
      expect(g.status, MiniGameStatus.finished);
      return g.scores.of(0).toInt();
    }

    // Early single tap (~1s in, normal radius) vs a tap inside the last ~6s
    // DOUBLE INK window of the 30s round (~27s in, fattened radius).
    final early = coverageForSingleTapAt(1.0);
    final finale = coverageForSingleTapAt(27.0);
    expect(finale, greaterThan(early),
        reason: 'a DOUBLE INK splat must paint a bigger footprint '
            '(early=$early finale=$finale)');
  });

  test('finale ink is free: a hold through DOUBLE INK out-covers a dry early '
      'hold', () {
    // During the last 6s the can is topped off every frame, so a held brush in
    // the finale keeps laying full (fattened) splats with no dud sputter. A 5s
    // hold spanning the finale must out-cover a 5s early hold that runs the can
    // dry — the free-flow finale lifts the ink ceiling for the climax.
    int coverageForHoldStartingAt(double startSeconds) {
      final g = PaintSplash()
        ..init(MiniGameContext(
          players: [PlayerSlot.defaults(0)],
          arena: const Size(800, 1200),
          rng: SeededRng(33),
          zones: ZoneLayout.forPlayers(1),
        ));
      var n = 0;
      var started = false;
      final startFrame = (startSeconds * 60).round();
      while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
        g.update(1 / 60);
        if (n >= startFrame && n < startFrame + 60 * 5) {
          g.onInput(!started
              ? const PlayerInput(
                  playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.5))
              : const PlayerInput(
                  playerId: 0, phase: InputPhase.holdTick, dt: 1 / 60));
          started = true;
        } else if (started) {
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
        }
      }
      expect(g.status, MiniGameStatus.finished);
      return g.scores.of(0).toInt();
    }

    // A 5s hold at one spot early (~2s, runs dry → sputters) vs a 5s hold that
    // runs through the finale (~25s.. → free flow, fattened, no sputter).
    final earlyHold = coverageForHoldStartingAt(2.0);
    final finaleHold = coverageForHoldStartingAt(25.0);
    expect(finaleHold, greaterThan(earlyHold),
        reason: 'the free-flow + fattened finale must out-cover an early dry '
            'hold (early=$earlyHold finale=$finaleHold)');
  });

  // ── Bots scale with difficulty (managed bots beat sloppy ones) ──────────────

  test('paint bots fill the board and resolve at both difficulties', () {
    // The skilled-vs-spam ordering (the design law) is proven by the human
    // managed-vs-blind ink-economy tests above. Difficulty is session-wide (one
    // BotProfile per game), so a head-to-head hard-vs-easy bot can't be staged
    // inside one game; here we just sanity-check that an all-bot board fills up
    // and the round resolves at both ends of the dial. (Bot ink-discipline feel
    // is a tuning pass, not a correctness invariant.)
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

  test('render does not throw', () {
    final g = PaintSplash()..init(ctxFor(4, 3));
    final canvas = Canvas(PictureRecorder());
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    g.update(1 / 60);
    g.onInput(const PlayerInput(
        playerId: 1, phase: InputPhase.down, normPos: Offset(0.75, 0.75)));
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });

  test('render does not throw across the whole round (incl. finale cues)', () {
    // Drives a full round with a held human so the DOUBLE INK banner, lead-flip
    // slow-mo and final WINNER bigMoment all fire, rendering each frame.
    final g = PaintSplash()..init(ctxFor(3, 8));
    final canvas = Canvas(PictureRecorder());
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
      g.update(1 / 60);
      g.onInput(n == 1
          ? const PlayerInput(
              playerId: 0, phase: InputPhase.down, normPos: Offset(0.4, 0.4))
          : const PlayerInput(
              playerId: 0, phase: InputPhase.holdTick, dt: 1 / 60));
      expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    }
    // One more render on the finished frame (winner banner + confetti).
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    expect(g.status, MiniGameStatus.finished);
  });
}
