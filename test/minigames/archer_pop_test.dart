import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/archer_pop/archer_pop.dart';

void main() {
  // All-bot context (drives the finish / ranking / pacing invariants).
  MiniGameContext botCtx(int n, {int seed = 7}) {
    final players = [
      for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    return MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(n),
    );
  }

  // Human context (no bots) so a test can drive every input itself.
  MiniGameContext humanCtx(int n, {int seed = 7}) {
    final players = [
      for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: false)
    ];
    return MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(n),
    );
  }

  void runToFinish(ArcherPop g, {int maxFrames = 60 * 80}) {
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < maxFrames) {
      g.update(1 / 60);
    }
  }

  // ── Finish / ranking invariants ─────────────────────────────────────────────

  test('target range finishes with four bots and ranks all players', () {
    final g = ArcherPop()..init(botCtx(4));
    runToFinish(g);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  for (final count in [1, 2, 3]) {
    test('target range finishes with $count player(s)', () {
      final g = ArcherPop()..init(botCtx(count, seed: 21 + count));
      runToFinish(g);
      expect(g.status, MiniGameStatus.finished);
      expect(g.winResult!.ranking.toSet(), {for (var i = 0; i < count; i++) i});
    });
  }

  test('target range always ends within the time-limit ceiling', () {
    // The round ends either when every quiver is dry or at the 40s limit
    // (~2400 frames; allow hit-stop slack). It must always resolve well before
    // the runaway guard.
    for (final seed in const [1, 7, 13, 21, 99]) {
      final g = ArcherPop()..init(botCtx(2, seed: seed));
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      expect(n, lessThan(60 * 50), reason: 'seed $seed overran');
    }
  });

  test('PACING: all-bot 4p round lasts > 1.5s and finishes within the limit',
      () {
    for (final seed in const [1, 7, 13, 21, 99]) {
      final g = ArcherPop()..init(botCtx(4, seed: seed));
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(frames, greaterThan(90),
          reason: 'seed $seed ended too fast (${frames / 60}s)');
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      expect(frames, lessThan(60 * 50),
          reason: 'seed $seed overran (${frames / 60}s)');
    }
  });

  // ── No-throw render invariants ──────────────────────────────────────────────

  test('renders without throwing at the start, mid-round and at finish', () {
    final g = ArcherPop()..init(botCtx(4, seed: 4));
    final rec = ui.PictureRecorder();
    const size = Size(900, 1400);
    final canvas = ui.Canvas(rec, Offset.zero & size);
    // Start frame.
    expect(() => g.render(canvas, size), returnsNormally);
    // Mid-round (some arrows in flight, targets moving).
    for (var i = 0; i < 60 * 6 && g.status != MiniGameStatus.finished; i++) {
      g.update(1 / 60);
    }
    expect(() => g.render(canvas, size), returnsNormally);
    // Run to finish, render there too.
    runToFinish(g);
    expect(() => g.render(canvas, size), returnsNormally);
  });

  test('the LAST ARROWS climax banner renders without throwing', () {
    // Burn most of an all-bot match's quiver to enter the climax window.
    final g = ArcherPop()..init(botCtx(3, seed: 4));
    for (var i = 0; i < 60 * 30 && g.status != MiniGameStatus.finished; i++) {
      g.update(1 / 60);
    }
    final rec = ui.PictureRecorder();
    const size = Size(900, 1400);
    final canvas = ui.Canvas(rec, Offset.zero & size);
    expect(() => g.render(canvas, size), returnsNormally);
  });

  // ── Behavior: ammo + aim mechanics ──────────────────────────────────────────

  test('every loosed arrow consumes one quiver arrow', () {
    final g = ArcherPop()..init(humanCtx(1, seed: 5));
    expect(g.debugAmmo(0), ArcherPop.debugQuiver);
    // Three deliberate aimed shots: ammo drops by exactly three.
    final fallback = const Offset(400, 300);
    var fired = 0;
    for (var i = 0; i < 3; i++) {
      final t = g.debugNearestTargetTo(0) ?? fallback;
      if (g.debugAimShotAt(0, t)) fired++;
      g.update(1 / 60);
    }
    expect(fired, 3, reason: 'each aimed draw should loose');
    expect(g.debugAmmo(0), ArcherPop.debugQuiver - 3);
  });

  test('ANTI-INCIDENTAL-CLEAR: a bare tap (no drag) looses no arrow', () {
    // A press-release with (near) zero drag is below the power gate: no arrow is
    // spent and nothing can be hit by an incidental tap.
    final g = ArcherPop()..init(humanCtx(1, seed: 8));
    final before = g.debugAmmo(0);
    // Down then up at the SAME point (zero pull) — a pure tap.
    const at = Offset(0.5, 0.9);
    g.onInput(
        const PlayerInput(playerId: 0, phase: InputPhase.down, normPos: at));
    g.onInput(
        const PlayerInput(playerId: 0, phase: InputPhase.holdTick, normPos: at));
    g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
    expect(g.debugArrowCount, 0, reason: 'a tap must not loose an arrow');
    expect(g.debugAmmo(0), before, reason: 'a tap must not spend ammo');

    // A micro-drag (a few px, still under the gate) is likewise not a shot.
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.9)));
    g.onInput(const PlayerInput(
        playerId: 0,
        phase: InputPhase.holdTick,
        normPos: Offset(0.502, 0.898)));
    g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
    expect(g.debugArrowCount, 0, reason: 'a micro-drag must not loose');
    expect(g.debugAmmo(0), before);
  });

  test('a deliberate drag DOES loose an arrow', () {
    final g = ArcherPop()..init(humanCtx(1, seed: 8));
    final before = g.debugAmmo(0);
    // A long pull from low on the field, well over the power gate.
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.95)));
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.holdTick, normPos: Offset(0.5, 0.55)));
    g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
    expect(g.debugArrowCount, 1, reason: 'a real draw must loose exactly one');
    expect(g.debugAmmo(0), before - 1);
  });

  test('a lone archer can still score over a round', () {
    final g = ArcherPop()..init(botCtx(1, seed: 3));
    runToFinish(g);
    expect(g.status, MiniGameStatus.finished);
    // A solo bot aims at targets and finishes near/above zero (it may clip a
    // bomb, but never crashes / never goes wildly negative across a round).
    expect(g.scores.of(0), greaterThanOrEqualTo(-9));
  });

  // ── THE ANTI-SPAM PROOF (deterministic via ctx.rng) ─────────────────────────

  test(
      'a BLIND SPAMMER (random-direction looses, quiver exhausted) scores '
      'WORSE than a player who AIMS at targets', () {
    // Head-to-head, both HUMAN (so no bot auto-fire interferes and the test owns
    // every input). Determinism comes entirely from the seeds:
    //  * P0 = AIMED player: only looses when a real (non-bomb) target exists, and
    //    aims a solved arc straight at the nearest one — conserves ammo, hits.
    //  * P1 = BLIND SPAMMER: looses in a RANDOM direction every cadence until the
    //    quiver is dry, ignoring targets entirely (the "just spam" archetype).
    // The aimed player must win — and the spammer must burn its whole quiver.
    final spamRng = SeededRng(123456);
    for (final seed in const [1, 7, 13, 42, 99]) {
      final g = ArcherPop()..init(humanCtx(2, seed: seed));

      var frame = 0;
      while (g.status != MiniGameStatus.finished && frame++ < 60 * 80) {
        // P0 AIMS: every ~0.25s, shoot the nearest clean target if one is up;
        // otherwise hold fire (conserve the scarce quiver). Still far more
        // deliberate than the spammer's ~0.12s blind spray.
        if (frame % 15 == 0 && g.debugAmmo(0) > 0) {
          g.debugShootNearestTarget(0);
        }
        // P1 SPAMS: every ~0.12s loose a full-power arrow in a uniformly RANDOM
        // direction (true blind spam), regardless of where targets are, until
        // the quiver runs out.
        if (frame % 7 == 0 && g.debugAmmo(1) > 0) {
          final ang = spamRng.range(-math.pi, math.pi);
          // P1 sits on the top edge; a far point along that heading → a long
          // pull (over the gate) routed through the real input path.
          const from = Offset(0.5, 0.25);
          final to = Offset(
            (from.dx + math.cos(ang) * 0.5).clamp(0.02, 0.98),
            (from.dy + math.sin(ang) * 0.5).clamp(0.02, 0.98),
          );
          g.onInput(
              PlayerInput(playerId: 1, phase: InputPhase.down, normPos: from));
          g.onInput(PlayerInput(
              playerId: 1, phase: InputPhase.holdTick, normPos: to));
          g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.up));
        }
        g.update(1 / 60);
      }

      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      final aimed = g.scores.of(0);
      final spammer = g.scores.of(1);

      // The whole point: aiming + conserving beats blind spam.
      expect(aimed, greaterThan(spammer),
          reason: 'seed $seed: aimed ($aimed) must beat spammer ($spammer)');
      // The aimed player actually scores (deliberate hits land).
      expect(aimed, greaterThan(0),
          reason: 'seed $seed: aimed player should score positive ($aimed)');
      // The blind spammer burns its entire quiver (waste), unlike the
      // conserving aimer.
      expect(g.debugAmmo(1), 0,
          reason: 'seed $seed: spammer should exhaust its quiver');
    }
  });

  test('blind spam cannot rack up an aimed-level score', () {
    // A sharper statement on one seed: a blind spammer that empties its quiver
    // in random directions ends LOW — proving an unaimed loose does not clear
    // targets for you.
    final g = ArcherPop()..init(humanCtx(1, seed: 7));
    final spamRng = SeededRng(987654);
    var frame = 0;
    while (g.status != MiniGameStatus.finished && frame++ < 60 * 80) {
      if (frame % 7 == 0 && g.debugAmmo(0) > 0) {
        final ang = spamRng.range(-math.pi, math.pi);
        const from = Offset(0.5, 0.95);
        final to = Offset(
          (from.dx + math.cos(ang) * 0.5).clamp(0.02, 0.98),
          (from.dy + math.sin(ang) * 0.5).clamp(0.02, 0.98),
        );
        g.onInput(
            PlayerInput(playerId: 0, phase: InputPhase.down, normPos: from));
        g.onInput(PlayerInput(
            playerId: 0, phase: InputPhase.holdTick, normPos: to));
        g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.debugAmmo(0), 0, reason: 'the spammer empties the quiver');
    expect(g.scores.of(0), lessThan(ArcherPop.debugQuiver * 2),
        reason: 'blind spam must not reach a strong (aimed-level) score');
  });

  test('an AIMED solo player racks up a clearly positive score', () {
    // The flip side: a player who aims every shot at a live target finishes well
    // positive — the contrast that makes the anti-spam comparison meaningful.
    final g = ArcherPop()..init(humanCtx(1, seed: 7));
    var frame = 0;
    while (g.status != MiniGameStatus.finished && frame++ < 60 * 80) {
      if (frame % 18 == 0 && g.debugAmmo(0) > 0) {
        g.debugShootNearestTarget(0);
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.scores.of(0), greaterThan(2),
        reason: 'aiming at real targets should score clearly positive');
  });
}
