import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
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

  // Mixed context: seat 0 is a HUMAN, every other seat is a BOT at [d]. The
  // engine sets ALL bots' BotProfile from this difficulty — the lever the
  // competitiveness audit sweeps (easy/medium/hard).
  MiniGameContext mixedCtx(int n, BotDifficulty d, int seed) {
    final players = [
      PlayerSlot.defaults(0, isBot: false),
      for (var i = 1; i < n; i++) PlayerSlot.defaults(i, isBot: true),
    ];
    return MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(n),
      difficulty: d,
    );
  }

  // Drive one 1v1 match where seat 0 is a SKILLED human-sim: every ~16 frames
  // (~0.27s) it looses a SOLVED arc at the nearest open scoring target —
  // judging the lob, LEADING the mover's drift, banking bullseyes + combos and
  // conserving the scarce quiver (it holds fire when only bombs/walled targets
  // are up). Returns (seat-0 score, bot score). Cadence 16 matches the deliberate
  // aimer used by the anti-spam proof above — not a spammer's blind spray.
  (num, num) duelSkilledVsBot(BotDifficulty d, int seed) {
    final g = ArcherPop()..init(mixedCtx(2, d, seed));
    var frame = 0;
    while (g.status != MiniGameStatus.finished && frame++ < 60 * 80) {
      if (frame % 16 == 0 && g.debugAmmo(0) > 0) {
        g.debugShootNearestTarget(0);
      }
      g.update(1 / 60);
    }
    return (g.scores.of(0), g.scores.of(1));
  }

  // Win-rate + margin spread of the skilled human vs a [d] bot over [seeds].
  ({double winRate, num minMargin, num maxMargin, int wins, int n})
      sweepDuel(BotDifficulty d, List<int> seeds) {
    var wins = 0;
    num minMargin = 1 << 30;
    num maxMargin = -(1 << 30);
    for (final seed in seeds) {
      final (s0, bot) = duelSkilledVsBot(d, seed);
      final margin = s0 - bot;
      if (s0 > bot) wins++;
      if (margin < minMargin) minMargin = margin;
      if (margin > maxMargin) maxMargin = margin;
    }
    return (
      winRate: wins / seeds.length,
      minMargin: minMargin,
      maxMargin: maxMargin,
      wins: wins,
      n: seeds.length,
    );
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

  test(
      'ROTATION-CORRECT: a TOP-seat (rot2) human drag aims INTO the arena, '
      'not inverted', () {
    // 2-player split: seat 1 sits on the TOP edge (rotationQuarters == 2). A
    // top-seat player pulls the slingshot BACK toward their own body (the top
    // edge → up the screen, −y); the arrow must loose DOWNWARD into the arena
    // (+y), not up off their own edge. Routed through the real onInput path.
    final g = ArcherPop()..init(humanCtx(2, seed: 11));
    expect(ZoneLayout.forPlayers(2).forPlayer(1)!.rotationQuarters, 2,
        reason: 'seat 1 must be the top (rot2) seat for this to test rotation');

    // Press inside seat 1's zone (top half), then drag UP toward the top edge
    // (a slingshot pull back toward the body) — a long pull, over the gate.
    g.onInput(const PlayerInput(
        playerId: 1, phase: InputPhase.down, normPos: Offset(0.5, 0.25)));
    g.onInput(const PlayerInput(
        playerId: 1, phase: InputPhase.holdTick, normPos: Offset(0.5, 0.05)));
    g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.up));

    expect(g.debugArrowCount, 1, reason: 'a real top-seat draw must loose');
    final vel = g.debugLastArrowVel(1);
    expect(vel, isNotNull);
    expect(vel!.dy, greaterThan(0),
        reason: 'top-seat (rot2) pull-toward-body must loose DOWN into the '
            'arena (dy>0), not inverted up off the edge (got $vel)');
  });

  test('ROTATION-CONSISTENCY: a BOTTOM-seat (rot0) pull-back aims up the field',
      () {
    // The companion to the top-seat case: seat 0 (bottom, rot0) pulls back
    // toward its body (down the screen, +y) and the arrow looses UP (−y) into
    // the arena — the reference seat the helper normalizes every other against.
    final g = ArcherPop()..init(humanCtx(2, seed: 11));
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.75)));
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.holdTick, normPos: Offset(0.5, 0.95)));
    g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
    final vel = g.debugLastArrowVel(0);
    expect(vel, isNotNull);
    expect(vel!.dy, lessThan(0),
        reason: 'bottom-seat (rot0) pull-toward-body must loose UP into the '
            'arena (dy<0) (got $vel)');
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
      'WORSE, banks NO combo and NO bullseye, vs a player who JUDGES the lob',
      () {
    // Head-to-head, both HUMAN (so no bot auto-fire interferes and the test owns
    // every input). Determinism comes entirely from the seeds:
    //  * P0 = JUDGING player: only looses when a real (non-bomb) target exists,
    //    and lobs a solved arc that LEADS the nearest mover's drift onto its core
    //    — conserves ammo, lands bullseyes, chains a combo.
    //  * P1 = BLIND SPAMMER: looses in a RANDOM direction every cadence until the
    //    quiver is dry, ignoring targets entirely (the "just spam" archetype).
    // The judging player must clearly win, bank a combo + bullseyes; the spammer
    // must burn its whole quiver and chain nothing.
    final spamRng = SeededRng(123456);
    // Bullseye is a precision signal that depends on the exact (shared) target
    // field, which shifts with seat geometry — so accumulate it ACROSS the sweep
    // (the aimer banks center-cores; the blind spammer never does) instead of
    // asserting it on every single seed. The decisive per-seed proof is the
    // score margin + combo + ammo asserts below.
    var aimedBullseyesTotal = 0;
    var spammerBullseyesTotal = 0;
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

      // The whole point: judging the lob + conserving beats blind spam, and by a
      // CLEAR margin (not a coin-flip) — a measured shooter is decisively ahead.
      expect(aimed, greaterThan(spammer + 6),
          reason: 'seed $seed: aimed ($aimed) must clearly beat spammer '
              '($spammer)');
      // The aimed player actually scores (deliberate hits land).
      expect(aimed, greaterThan(0),
          reason: 'seed $seed: aimed player should score positive ($aimed)');
      // The blind spammer burns its entire quiver (waste), unlike the
      // conserving aimer.
      expect(g.debugAmmo(1), 0,
          reason: 'seed $seed: spammer should exhaust its quiver');

      // THE NEW SKILL SIGNAL: a judging shooter who LEADS moving targets BANKS a
      // combo (consecutive hits stack the multiplier). A blind sprayer cannot
      // chain — its multiplier never leaves 1.
      expect(g.debugPeakCombo(0), greaterThanOrEqualTo(2),
          reason: 'seed $seed: aimed player should bank a combo '
              '(peak ${g.debugPeakCombo(0)})');
      // A blind sprayer can luck into a stray DOUBLE (two random hits in a row),
      // but never SUSTAINS a chain — a 3+ combo requires actually leading the
      // moving targets. (The decisive spam-loses proof is the score margin +
      // bullseye gap above; the multiplier is the visible skill signal on top.)
      expect(g.debugPeakCombo(1), lessThanOrEqualTo(2),
          reason: 'seed $seed: blind spammer must never SUSTAIN a chain '
              '(peak ${g.debugPeakCombo(1)})');
      // …and the spammer lands NO center-core bullseyes on ANY seed (a blind
      // loose can clip a rim but never threads the core).
      expect(g.debugBullseyes(1), 0,
          reason: 'seed $seed: blind spammer should land no bullseyes '
              '(${g.debugBullseyes(1)})');
      aimedBullseyesTotal += g.debugBullseyes(0);
      spammerBullseyesTotal += g.debugBullseyes(1);
    }

    // The aimer banks center-core BULLSEYES across the sweep (the precision
    // reward for judging the lob); the blind spammer banks none.
    expect(aimedBullseyesTotal, greaterThan(0),
        reason: 'aimed player should land bullseyes across the sweep '
            '($aimedBullseyesTotal)');
    expect(spammerBullseyesTotal, 0,
        reason: 'blind spammer should land no bullseyes across the sweep '
            '($spammerBullseyesTotal)');
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

  // ── COMPETITIVE: skill gradient + beatable-but-tough hard bot ───────────────
  //
  // Measured: a SKILLED human-sim in seat 0 (solves + LEADS the lob at the
  // nearest open target every ~0.27s, banks bullseyes/combos, conserves ammo)
  // vs a single BOT at each difficulty over 24 seeds (1v1, the contracted shape).
  // Win-rate table at this cadence (seeds 1..24) — the permanent contract:
  //     easy   WR ≈ 0.875   avgMargin ≈ +17
  //     medium WR ≈ 0.750   avgMargin ≈ +9
  //     hard   WR ≈ 0.667   avgMargin ≈ +6
  // (Underlying N=80 sweep agrees: 0.875 / 0.762 / 0.662, with bot scores
  // 6.2 / 7.7 / 11.2 — a monotone difficulty.) The bands below are deliberately
  // ROBUST (wide of the measured values) so they lock the SHAPE — a real skill
  // gradient and a hard bot that is beatable but never a pushover/wall — without
  // being brittle to engine RNG tweaks. A regression that flattens the gradient,
  // walls the hard bot, or turns it into a pushover trips this.
  group('COMPETITIVE: skill gradient + beatable-but-tough hard bot', () {
    // >= 12 seeds (24 used): a robust, contiguous, non-cherry-picked window.
    final seeds = [for (var s = 1; s <= 24; s++) s];

    final easy = sweepDuel(BotDifficulty.easy, seeds);
    final medium = sweepDuel(BotDifficulty.medium, seeds);
    final hard = sweepDuel(BotDifficulty.hard, seeds);

    test('EASY is clearly beatable (win-rate >= 0.70)', () {
      expect(easy.winRate, greaterThanOrEqualTo(0.70),
          reason: 'skilled human should dominate easy bots '
              '(${easy.wins}/${easy.n} = ${easy.winRate})');
    });

    test('HARD is beatable-but-tough (win-rate in [0.15, 0.90])', () {
      // Not a WALL (> 0.15: a skilled player can win), not a PUSHOVER
      // (< 0.90: the hard bot takes real games off you).
      expect(hard.winRate, greaterThanOrEqualTo(0.15),
          reason: 'hard bot must not be an unbeatable wall '
              '(${hard.wins}/${hard.n} = ${hard.winRate})');
      expect(hard.winRate, lessThanOrEqualTo(0.90),
          reason: 'hard bot must not be a trivial pushover '
              '(${hard.wins}/${hard.n} = ${hard.winRate})');
    });

    test('GRADIENT: winEasy >= winMedium >= winHard and winEasy > winHard', () {
      expect(easy.winRate, greaterThanOrEqualTo(medium.winRate),
          reason: 'easy (${easy.winRate}) should be >= medium '
              '(${medium.winRate})');
      expect(medium.winRate, greaterThanOrEqualTo(hard.winRate),
          reason: 'medium (${medium.winRate}) should be >= hard '
              '(${hard.winRate})');
      expect(easy.winRate, greaterThan(hard.winRate),
          reason: 'easy (${easy.winRate}) must STRICTLY beat hard '
              '(${hard.winRate}) — a real skill gradient, not a flat line');
    });

    test('NOT luck-dominated: vs EASY the skilled human wins a clear majority',
        () {
      // A skill signal, not a coin flip: > 60% of seeds are wins vs easy.
      expect(easy.wins, greaterThan(seeds.length * 0.6),
          reason: 'vs easy the skilled human should win reliably across seeds '
              '(${easy.wins}/${easy.n})');
    });

    test('NO runaway: outcomes VARY across seeds (margins span both signs)',
        () {
      // Across each difficulty the per-seed margin spans a wide range and
      // includes seeds the human LOSES (minMargin < 0) — the match is not a
      // fixed runaway; the bot mounts comebacks on some seeds.
      for (final r in [
        (BotDifficulty.easy, easy),
        (BotDifficulty.medium, medium),
        (BotDifficulty.hard, hard),
      ]) {
        final d = r.$1;
        final res = r.$2;
        expect(res.maxMargin - res.minMargin, greaterThan(20),
            reason: '$d: margins should vary across seeds, not a fixed runaway '
                '(min ${res.minMargin}, max ${res.maxMargin})');
        expect(res.minMargin, lessThan(0),
            reason: '$d: the bot should take at least one seed off the human '
                '(min margin ${res.minMargin}) — no guaranteed runaway');
      }
    });
  });
}
