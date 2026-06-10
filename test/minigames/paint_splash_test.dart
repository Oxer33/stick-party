import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/helpers/area_fill_grid.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/paint_splash/paint_splash.dart';

void main() {
  MiniGameContext ctxFor(int n, int seed) => MiniGameContext(
        players: [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
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
    // Deterministic: fixed seed, fixed inputs, no bots, no other touches.
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
      // brush spraying continuously (mirrors a finger held on the screen).
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

  test('a human holding still keeps spraying past the idle timeout', () {
    // Regression: a stationary held finger emits only per-frame holdTicks with
    // no position (normPos == Offset.zero). Those ticks must keep the brush
    // spraying for the whole hold. Previously the idle-touch timeout in update()
    // flipped spraying off ~0.18s after the finger stopped moving, so a held
    // brush that wasn't being wiggled died and stopped covering ground.
    //
    // The dwell bonus makes "still spraying" observable at one spot: lingering
    // ramps the splat radius up, so a brush that keeps firing paints a steadily
    // fatter circle (more owned cells). We compare a full-round hold against a
    // hold cut short right at the idle window: pre-fix both stopped spraying at
    // ~0.18s and covered the same; with the fix the long hold keeps spraying and
    // covers strictly more. Solo human so the score is exactly this coverage.
    int coverageForHoldFrames(int holdFrames) {
      final ctx = MiniGameContext(
        players: [PlayerSlot.defaults(0)], // lone human
        arena: const Size(800, 1200),
        rng: SeededRng(9),
        zones: ZoneLayout.forPlayers(1),
      );
      final g = PaintSplash()..init(ctx);
      g.onInput(const PlayerInput(
          playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.5)));
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 120) {
        g.update(1 / 60);
        if (n <= holdFrames) {
          // Hold still: positionless per-frame ticks, the exact event a still
          // finger produces every frame.
          g.onInput(const PlayerInput(
              playerId: 0, phase: InputPhase.holdTick, dt: 1 / 60));
        }
      }
      expect(g.status, MiniGameStatus.finished);
      return g.scores.of(0).toInt();
    }

    // ~0.18s touchIdleTimeout ≈ 11 frames at 60fps; 16 frames is just past it.
    final shortHold = coverageForHoldFrames(16);
    final longHold = coverageForHoldFrames(60 * 5); // 5s of continuous holding
    expect(longHold, greaterThan(shortHold),
        reason: 'holding still must keep spraying past the idle timeout '
            '(short=$shortHold long=$longHold)');
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

  test('render does not throw', () {
    final g = PaintSplash()..init(ctxFor(4, 3));
    final canvas = Canvas(PictureRecorder());
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    g.update(1 / 60);
    g.onInput(const PlayerInput(
        playerId: 1, phase: InputPhase.down, normPos: Offset(0.75, 0.75)));
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });
}
