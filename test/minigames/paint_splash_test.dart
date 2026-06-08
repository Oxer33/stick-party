import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
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

  test('bots steer + spray on their own, covering ground over the round', () {
    final g = PaintSplash()..init(ctxFor(4, 7));
    runToEnd(g);
    // Each self-driving bot should paint a meaningful chunk of its own zone.
    for (var id = 0; id < 4; id++) {
      expect(g.scores.of(id), greaterThan(0), reason: 'bot $id painted nothing');
    }
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
