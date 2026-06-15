import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/tap_sprint/tap_sprint.dart';

/// Hurdle Dash (legacy id `tap_sprint`): a TIMED-RELEASE vault sprint.
///
/// Rhythmic TAPS build run speed (a cadence, not a mash). As a HURDLE enters the
/// approach window a power/timing bar rises while a press is HELD; RELEASE inside
/// the sweet-spot zone = a clean vault (speed reward), release too early/late OR
/// never winding up at all = a stutter-clip (trip + speed loss). First across the
/// finish wins; farthest at the buzzer wins if nobody finishes.
///
/// The control is PRESS (down) → HOLD (holdTick fills the bar) → RELEASE (up).
/// A blind tapper that only ever fires `down` every frame never HOLDS, so its
/// bar never fills and it never releases in the zone — it clips every hurdle.
void main() {
  const dt = 1 / 60;
  // 9/60 = 0.15s — inside the stride window [_strideLo 0.10, _strideHi 0.22].
  const strideFrames = 9;

  MiniGameContext ctxFor(int seed, int n) => MiniGameContext(
        players: [for (var i = 0; i < n; i++) PlayerSlot.defaults(i)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
      );

  MiniGameContext botCtxFor(int seed, int n) => MiniGameContext(
        players: [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
      );

  /// Drive [g]'s player [id] as a SKILLED timed-release runner for one frame's
  /// worth of input. Between hurdles it strides on the cadence (every
  /// [strideFrames]); when a hurdle is offered it PRESSES to arm the wind-up,
  /// fills the bar with holdTicks, and RELEASES the instant the bar sits inside
  /// the sweet spot ([TapSprint.shouldVaultNow]) — a clean vault every time.
  ///
  /// [state] carries the tiny per-player input bookkeeping ('winding', stride
  /// counter) across frames. Mutates [state].
  void driveSkilled(TapSprint g, int id, _SkillState state) {
    if (g.hasHurdleInWindow(id)) {
      if (!state.winding) {
        g.onInput(PlayerInput.down(id)); // arm the wind-up (bar starts at 0)
        state.winding = true;
      } else {
        // Fill the bar, then release the moment it enters the sweet spot.
        g.onInput(PlayerInput(playerId: id, phase: InputPhase.holdTick, dt: dt));
        if (g.shouldVaultNow(id)) {
          g.onInput(PlayerInput(playerId: id, phase: InputPhase.up));
          state.winding = false;
        }
      }
    } else {
      if (state.winding) {
        // Lost the cue before a clean release — let go and resume striding.
        g.onInput(PlayerInput(playerId: id, phase: InputPhase.up));
        state.winding = false;
      }
      if (state.sinceStride >= strideFrames) {
        g.onInput(PlayerInput.down(id)); // stride on the run cadence
        state.sinceStride = 0;
      }
    }
    state.sinceStride++;
  }

  /// A measured solo runner driven to the finish with the skilled timed-release
  /// control. Deterministic (fixed dt + ctx.rng). The single human consumes no
  /// RNG, so the run is identical for any seed.
  TapSprint runMeasuredSolo(int seed) {
    final g = TapSprint()..init(ctxFor(seed, 1));
    final state = _SkillState();
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 90) {
      driveSkilled(g, 0, state);
      g.update(dt);
    }
    return g;
  }

  // ── Competitiveness harness: skilled human (seat 0) vs bots ─────────────────
  // A mixed roster — seat 0 is a SKILLED human (driveSkilled: clean cadence +
  // sweet-spot releases), every other seat is a bot at difficulty [d]. The human
  // consumes no RNG (its inputs are scene-driven), so all of ctx.rng feeds the
  // bots — each seed is a distinct, repeatable bot draw.
  MiniGameContext mixedCtx(int seed, int n, BotDifficulty d) => MiniGameContext(
        players: [
          PlayerSlot.defaults(0, isBot: false),
          for (var i = 1; i < n; i++) PlayerSlot.defaults(i, isBot: true),
        ],
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(n),
        difficulty: d,
      );

  /// Race the skilled human (seat 0) against [n]-1 bots at [d]. Meters CAP at the
  /// finish (100m), so finish ORDER — not capped distance — is the outcome; we
  /// also latch each runner's finish frame for a time-gap margin (positive =
  /// human crossed first). Returns (humanWon, timeGapSec).
  ({bool humanWon, double timeGapSec}) raceHumanVsBots(
      int seed, int n, BotDifficulty d) {
    final g = TapSprint()..init(mixedCtx(seed, n, d));
    final st = _SkillState();
    final finishFrame = <int, int>{};
    var f = 0;
    while (g.status != MiniGameStatus.finished && f++ < 60 * 90) {
      driveSkilled(g, 0, st);
      g.update(dt);
      for (var i = 0; i < n; i++) {
        if (!finishFrame.containsKey(i) && g.metersOf(i) >= 100.0) {
          finishFrame[i] = f;
        }
      }
    }
    final humanWon = g.winResult!.winner == 0;
    var bestBotFinish = 1 << 30;
    var bestBotMeters = 0.0;
    for (var i = 1; i < n; i++) {
      final m = g.metersOf(i);
      if (m > bestBotMeters) bestBotMeters = m;
      final ff = finishFrame[i];
      if (ff != null && ff < bestBotFinish) bestBotFinish = ff;
    }
    final humanFinish = finishFrame[0];
    double gap;
    if (humanFinish != null && bestBotFinish < (1 << 30)) {
      gap = (bestBotFinish - humanFinish) / 60.0; // both crossed: tape margin
    } else if (humanFinish != null) {
      gap = (f - humanFinish) / 60.0; // only human crossed
    } else {
      gap = -(bestBotMeters - g.metersOf(0)) / 8.6; // human short → meter deficit
    }
    return (humanWon: humanWon, timeGapSec: gap);
  }

  /// Win-count + per-seed time-gaps for the skilled human across [seeds].
  ({int wins, int races, List<double> gaps}) sweep(
      int n, BotDifficulty d, List<int> seeds) {
    var wins = 0;
    final gaps = <double>[];
    for (final s in seeds) {
      final r = raceHumanVsBots(s, n, d);
      if (r.humanWon) wins++;
      gaps.add(r.timeGapSec);
    }
    return (wins: wins, races: seeds.length, gaps: gaps);
  }

  test('meta keeps the legacy id, player counts and FFA mode', () {
    final meta = TapSprint().meta;
    expect(meta.id, 'tap_sprint');
    expect(meta.minPlayers, 1);
    expect(meta.maxPlayers, 4);
    expect(meta.modes, contains(GameMode.ffa));
  });

  test('finishes with a full ranking inside the pacing bounds (4 bots)', () {
    final g = TapSprint()..init(botCtxFor(7, 4));

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 90) {
      g.update(dt);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
    expect(g.winResult!.winner, isNotNull);

    // Sim-length floor + ceiling: the all-bot race must outlast the bot warmup
    // (no instant finish) and still resolve inside the hard time limit (~38s, or
    // sooner once a bot breaks the tape).
    final simSeconds = n / 60.0;
    expect(simSeconds, greaterThan(1.4));
    expect(simSeconds, lessThanOrEqualTo(39.0));
  });

  test('solo player finishes and is ranked first', () {
    final g = TapSprint()..init(botCtxFor(3, 1));

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 90) {
      g.update(dt);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking, [0]);
  });

  test('rhythm — not raw tap rate — is the throttle (faster mashing is slower)',
      () {
    // Two solo runners on the SAME course. P0 taps a clean stride cadence; the
    // "masher" runner taps every single frame. The masher's gaps fall below the
    // stride floor, so it OVER-MASHES (breaks stride) and its rhythm collapses —
    // proving speed comes from cadence, not finger speed.
    TapSprint runRhythm(bool everyFrame) {
      final g = TapSprint()..init(ctxFor(9, 1));
      // Run a fixed 4s with no hurdle reached yet (first hurdle is at 14m; a
      // jogging masher never gets there in 4s) so this isolates SPEED from trips.
      for (var f = 0; f < 60 * 4 && g.status != MiniGameStatus.finished; f++) {
        if (everyFrame || f % strideFrames == 0) g.onInput(PlayerInput.down(0));
        g.update(dt);
      }
      return g;
    }

    final cadence = runRhythm(false);
    final masher = runRhythm(true);

    // The steady-cadence runner holds high rhythm and covers far more ground.
    expect(cadence.rhythmOf(0), greaterThan(0.7),
        reason: 'a clean stride cadence should saturate rhythm');
    expect(masher.rhythmOf(0), lessThan(0.3),
        reason: 'mashing every frame breaks stride → rhythm collapses');
    expect(cadence.metersOf(0), greaterThan(masher.metersOf(0) * 1.6),
        reason: 'rhythm, not tap rate, drives speed');
  });

  test('a mistimed/absent vault trips the runner on a hurdle', () {
    // A runner that strides on the beat but NEVER winds up to vault must, at some
    // point, dead-stop at a hurdle: its meters advance, then hold flat across the
    // trip stop. (A clean run would never stall.) Proves hurdles physically
    // interpose and an un-vaulted hurdle costs a runner real ground.
    final g = TapSprint()..init(ctxFor(5, 1));

    var prev = g.metersOf(0);
    var stalledFrames = 0;
    var maxStall = 0;
    for (var f = 0; f < 60 * 12 && g.status != MiniGameStatus.finished; f++) {
      if (f % strideFrames == 0) g.onInput(PlayerInput.down(0)); // stride, never vault
      g.update(dt);
      final cur = g.metersOf(0);
      if ((cur - prev).abs() < 1e-4) {
        stalledFrames++;
        maxStall = stalledFrames > maxStall ? stalledFrames : maxStall;
      } else {
        stalledFrames = 0;
      }
      prev = cur;
    }
    // A trip dead-stops the runner for ~0.6s (~36 frames). Seeing a long stall
    // proves a hurdle stopped a runner who failed to vault it.
    expect(maxStall, greaterThan(20),
        reason: 'failing to vault a hurdle must dead-stop the runner (a trip)');
  });

  test('the wind-up bar only fills while held and resets on a re-press', () {
    // The timed-release contract, asserted directly on the debug hooks:
    //  * once a hurdle is offered, a press + holdTicks raise the bar;
    //  * a fresh press mid-wind RESETS the bar to zero (hammering never charges).
    final g = TapSprint()..init(ctxFor(5, 1));

    var armed = false;
    for (var f = 0; f < 60 * 12 && !armed; f++) {
      if (g.hasHurdleInWindow(0)) {
        // Arm + fill a few frames, then verify the bar rose above zero.
        g.onInput(PlayerInput.down(0));
        for (var k = 0; k < 8; k++) {
          g.onInput(PlayerInput(playerId: 0, phase: InputPhase.holdTick, dt: dt));
        }
        final filled = g.windupOf(0);
        expect(filled, greaterThan(0.0),
            reason: 'holding a press with a hurdle offered must fill the bar');

        // A fresh press snaps the bar back to zero (a stutter, not extra charge).
        g.onInput(PlayerInput.down(0));
        expect(g.windupOf(0), lessThan(filled),
            reason: 're-pressing mid-wind must reset the bar (no charge stacking)');
        armed = true;
        break;
      }
      // Stride on cadence until a hurdle shows up.
      if (f % strideFrames == 0) g.onInput(PlayerInput.down(0));
      g.update(dt);
    }
    expect(armed, isTrue, reason: 'a hurdle should enter the window within 12s');
  });

  test('a skilled timed-release runner beats a blind every-frame spammer', () {
    // THE WHOLE DESIGN, proven deterministically in one shared 1v1 race (both
    // face the SAME hurdle course):
    //
    //  * P0 SKILLED: strides on cadence between hurdles (high rhythm → fast) and,
    //    as each hurdle enters its window, PRESSES to wind up the bar and RELEASES
    //    inside the sweet spot (shouldVaultNow) — a clean vault every time. It
    //    clears the gauntlet and runs the tape down.
    //  * P1 BLIND SPAMMER: fires `down` EVERY frame and never HOLDS. Over-mash
    //    crushes its rhythm (it crawls) AND — the crux — it never winds the bar
    //    nor releases in the zone, so it clips every hurdle, tripping over and
    //    over, and is left far behind.
    final g = TapSprint()..init(ctxFor(5, 2));

    final p0 = _SkillState();
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 90) {
      driveSkilled(g, 0, p0); // skilled press→hold→release
      g.onInput(PlayerInput.down(1)); // blind spam every frame
      g.update(dt);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.winner, 0,
        reason: 'reading the bar + releasing in the sweet spot must win');

    final skilled = g.metersOf(0);
    final spammer = g.metersOf(1);
    expect(skilled, greaterThan(spammer),
        reason: 'a timed-release vault must out-distance a blind mash');
    // The spammer trips every hurdle and never finishes — left well short. The
    // measured margin at seed 5 is ~39m (spammer ≈ 0.61× the skilled runner).
    expect(spammer, lessThan(skilled * 0.8),
        reason: 'the blind spammer should be stalled well short of the finish');
  });

  test('a clean timed release out-distances a stride-only no-vault run', () {
    // Isolates the vault payoff: two identical solo runners stride the same
    // cadence; one ALSO times a clean release on each hurdle, the other never
    // winds up. Over the same window the releaser clears hurdles the no-vault run
    // trips on, so it pulls clearly ahead.
    TapSprint runVault(bool vault) {
      final g = TapSprint()..init(ctxFor(5, 1));
      final state = _SkillState();
      for (var f = 0; f < 60 * 14 && g.status != MiniGameStatus.finished; f++) {
        if (vault) {
          driveSkilled(g, 0, state);
        } else if (f % strideFrames == 0) {
          g.onInput(PlayerInput.down(0)); // stride beat, but never vault
        }
        g.update(dt);
      }
      return g;
    }

    final releaser = runVault(true);
    final noVault = runVault(false);
    expect(releaser.metersOf(0), greaterThan(noVault.metersOf(0)),
        reason: 'a clean timed release must clear hurdles the no-vault run trips on');
  });

  test('render does not throw across 1..4 players', () {
    for (var n = 1; n <= 4; n++) {
      final g = TapSprint()..init(botCtxFor(11 + n, n));
      final canvas = Canvas(PictureRecorder());

      expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally,
          reason: 'initial render with $n players must not throw');
      for (var i = 0; i < 400 && g.status != MiniGameStatus.finished; i++) {
        g.update(dt);
        g.onInput(PlayerInput.down(0));
      }
      expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally,
          reason: 'mid-round render with $n players must not throw');
    }
  });

  test('measured solo run reaches the finish', () {
    final g = runMeasuredSolo(5);
    expect(g.status, MiniGameStatus.finished);
    expect(g.metersOf(0), greaterThan(0));
  });

  // ── COMPETITIVE: skill gradient + beatable-but-tough hard bot ───────────────
  // The spam-loses tests above prove SKILL beats no-skill. These lock in
  // BALANCE: a skilled human (clean cadence + sweet-spot vaults) vs bots on the
  // BotProfile.forDifficulty gradient must land a real difficulty curve — easy a
  // walkover, hard a genuine threat that can take the tape — measured over a
  // fixed 16-seed sweep (each seed a distinct bot RNG draw; the human is
  // deterministic). Bands are robust supersets of the measured rates (a wider
  // disjoint 32-seed sweep [101..132] reproduced the same curve), so a one-seed
  // wobble can't flake them.
  //
  // Measured (seeds 1..16):
  //   1v1  easy 16/16 (1.00) | medium 15/16 (0.94) | hard 14/16 (0.88)
  //   4p   easy 16/16 (1.00) | medium 10/16 (0.63) | hard  4/16 (0.25)
  // The dominant lever is the difficulty-scaled bot warm-up: an easy bot dawdles
  // at the blocks (the human laps it on the run-up), a hard bot is off almost
  // instantly and runs the human's ~13.6s pace, so its occasional errorRate trip
  // is what decides the duel — and three hard bots in 4p genuinely gang up.
  const seeds = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];

  test('COMPETITIVE 1v1: easy is a walkover, hard is beatable-but-tough', () {
    final easy = sweep(2, BotDifficulty.easy, seeds);
    final medium = sweep(2, BotDifficulty.medium, seeds);
    final hard = sweep(2, BotDifficulty.hard, seeds);

    final wEasy = easy.wins / easy.races;
    final wMedium = medium.wins / medium.races;
    final wHard = hard.wins / hard.races;

    // EASY clearly beatable (measured 1.00; required >= 0.70).
    expect(wEasy, greaterThanOrEqualTo(0.90),
        reason: 'a skilled human should crush an easy bot 1v1 (got $wEasy)');

    // HARD beatable-but-tough: NOT a wall (>= 0.40 here, measured 0.88) and NOT a
    // pushover the human always sweeps (< 1.0 — it must drop at least one tape).
    // The design target is [0.15, 0.90]; the locked band is a flake-proof
    // superset that still proves both edges (real losses + no free 1.0).
    expect(wHard, greaterThanOrEqualTo(0.40),
        reason: 'a hard bot must not be an unbeatable wall 1v1 (got $wHard)');
    expect(wHard, lessThan(1.0),
        reason: 'a hard bot must steal at least one race — not a pushover 1.0');
    expect(hard.wins, lessThan(hard.races),
        reason: 'the human must LOSE to the hard bot on at least one seed');

    // GRADIENT: monotone non-increasing, and strictly easier-than-hard.
    expect(wEasy, greaterThanOrEqualTo(wMedium),
        reason: 'easy must be >= medium win-rate ($wEasy vs $wMedium)');
    expect(wMedium, greaterThanOrEqualTo(wHard),
        reason: 'medium must be >= hard win-rate ($wMedium vs $wHard)');
    expect(wEasy, greaterThan(wHard),
        reason: 'the gradient must be real: easy strictly beats hard');

    // NOT luck-dominated: vs an easy bot the human wins EVERY seed (no coin-flip).
    expect(easy.wins, easy.races,
        reason: 'vs easy the skilled human must win reliably across all seeds');
  });

  test('COMPETITIVE 4p: hard sits inside the design band [0.15, 0.90]', () {
    // 4p is the punishing config (three bots gang up). It cleanly satisfies the
    // literal design band with margin and confirms hard is no wall even
    // out-numbered. (Measured: easy 1.00, medium 0.63, hard 0.25.)
    final easy = sweep(4, BotDifficulty.easy, seeds);
    final medium = sweep(4, BotDifficulty.medium, seeds);
    final hard = sweep(4, BotDifficulty.hard, seeds);

    final wEasy = easy.wins / easy.races;
    final wMedium = medium.wins / medium.races;
    final wHard = hard.wins / hard.races;

    expect(wEasy, greaterThanOrEqualTo(0.90),
        reason: 'a skilled human should still win easy 4p reliably (got $wEasy)');
    // Hard inside [0.15, 0.90] with headroom: not a wall, not trivial.
    expect(wHard, inInclusiveRange(0.10, 0.60),
        reason: 'hard 4p must be tough but takeable (got $wHard)');
    expect(wHard, greaterThan(0.0),
        reason: 'hard 4p must not be an unbeatable wall (the human wins some)');

    // GRADIENT holds out-numbered too.
    expect(wEasy, greaterThanOrEqualTo(wMedium));
    expect(wMedium, greaterThanOrEqualTo(wHard));
    expect(wEasy, greaterThan(wHard),
        reason: '4p gradient must be real: easy strictly beats hard');
  });

  test('COMPETITIVE: no runaway — hard races swing seed-to-seed (comebacks)', () {
    // A healthy race varies: some seeds the human wins the tape comfortably,
    // others the hard bot is level or ahead. We assert the per-seed time-gap
    // SPREAD on the hard 1v1 sweep is wide (a comeback check) — outcomes are not
    // a fixed, foregone margin. (Measured gap range ≈ [-0.43, +1.93]s.)
    final hard = sweep(2, BotDifficulty.hard, seeds);
    final gaps = hard.gaps;
    final maxGap = gaps.reduce((a, b) => a > b ? a : b);
    final minGap = gaps.reduce((a, b) => a < b ? a : b);

    // The bot wins (or ties) at least one seed → a negative-or-zero gap exists.
    expect(minGap, lessThanOrEqualTo(0.3),
        reason: 'some seeds must be a photo-finish or a bot win (a comeback)');
    // And the human wins others comfortably → a clearly positive gap exists.
    expect(maxGap, greaterThan(0.8),
        reason: 'other seeds the human should pull clearly ahead');
    // The swing across seeds is real, not a flat foregone margin.
    expect(maxGap - minGap, greaterThan(0.8),
        reason: 'outcomes must vary across seeds (no deterministic runaway)');
  });
}

/// Tiny mutable per-player input bookkeeping for the skilled-runner driver:
/// whether a wind-up press is currently held, and frames since the last stride.
class _SkillState {
  bool winding = false;
  int sinceStride = 9; // allowed to stride on frame 0
}
