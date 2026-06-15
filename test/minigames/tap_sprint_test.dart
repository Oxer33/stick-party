import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
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
}

/// Tiny mutable per-player input bookkeeping for the skilled-runner driver:
/// whether a wind-up press is currently held, and frames since the last stride.
class _SkillState {
  bool winding = false;
  int sinceStride = 9; // allowed to stride on frame 0
}
