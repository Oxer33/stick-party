import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/tap_sprint/tap_sprint.dart';

/// Hurdle Dash (legacy id `tap_sprint`): rhythmic TAPS build run speed (a
/// cadence, not a mash); telegraphed HURDLES must be VAULTED on cue (a controlled
/// press inside the jump window, or a hold) or the runner TRIPS. First across the
/// finish wins; farthest at the buzzer wins if nobody finishes.
void main() {
  const dt = 1 / 60;
  const strideFrames = 9; // 9/60 = 0.15s — inside the stride window 0.085..0.26

  /// A measured solo runner driven to the finish: it taps a steady stride beat
  /// for speed, and vaults a hurdle ONLY when [TapSprint.shouldVaultNow] says a
  /// vault would clear (reading the telegraph). Every press is ≥ a stride-gap
  /// apart, so each registers cleanly. Deterministic (fixed dt + ctx.rng).
  TapSprint runMeasuredSolo(int seed) {
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0)],
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = TapSprint()..init(ctx);
    var sincePress = strideFrames; // allowed to press on frame 0
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      if (sincePress >= strideFrames) {
        if (g.hasHurdleInWindow(0)) {
          // A hurdle is telegraphed: wait for the exact clear moment, then vault.
          if (g.shouldVaultNow(0)) {
            g.onInput(PlayerInput.down(0));
            sincePress = 0;
          }
        } else {
          g.onInput(PlayerInput.down(0)); // stride on the beat
          sincePress = 0;
        }
      }
      g.update(dt);
      sincePress++;
    }
    return g;
  }

  test('finishes with a full ranking inside the pacing bounds (4 bots)', () {
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = TapSprint()..init(ctx);

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
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(3),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = TapSprint()..init(ctx);

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
      final ctx = MiniGameContext(
        players: [PlayerSlot.defaults(0)],
        arena: const Size(800, 1200),
        rng: SeededRng(9),
        zones: ZoneLayout.forPlayers(1),
      );
      final g = TapSprint()..init(ctx);
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
    // A runner that strides on the beat but NEVER vaults must, at some point,
    // dead-stop at a hurdle: its meters advance, then hold flat across the trip
    // stop. (A clean run would never stall.) Proves hurdles physically interpose.
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0)],
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = TapSprint()..init(ctx);

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

  test('a measured runner who HOLDS to vault beats a blind spammer head-to-head',
      () {
    // THE WHOLE DESIGN, proven deterministically in one shared 1v1 race (both
    // face the SAME hurdle course):
    //
    //  * P0 MEASURED: strides on cadence between hurdles (high rhythm → fast) and
    //    HOLDS as each hurdle enters its window — the hold auto-leaps at the clear
    //    moment, so it vaults the gauntlet cleanly and runs the tape down.
    //  * P1 BLIND SPAMMER: taps EVERY frame. Over-mash crushes its rhythm (crawls)
    //    AND a tap never vaults — so it clips every hurdle, tripping over and over,
    //    and is left far behind.
    final players = [
      PlayerSlot.defaults(0), // measured (strides + holds to vault)
      PlayerSlot.defaults(1), // blind spammer
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = TapSprint()..init(ctx);

    var holding = false;
    var sinceStride = strideFrames;
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 90) {
      // Measured P0: hold through a hurdle's window (auto-vaults at the clear
      // moment), stride on cadence otherwise.
      if (g.hasHurdleInWindow(0)) {
        if (!holding) {
          g.onInput(PlayerInput.down(0));
          holding = true;
        }
        g.onInput(PlayerInput(playerId: 0, phase: InputPhase.holdTick, dt: dt));
      } else {
        if (holding) {
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
          holding = false;
        }
        if (sinceStride >= strideFrames) {
          g.onInput(PlayerInput.down(0));
          sinceStride = 0;
        }
      }
      g.onInput(PlayerInput.down(1)); // blind spam every frame
      g.update(dt);
      sinceStride++;
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.metersOf(0), greaterThan(g.metersOf(1)),
        reason: 'reading + holding to vault must beat a blind mash');
    // The spammer trips every hurdle and never finishes — left well short.
    expect(g.metersOf(1), lessThan(g.metersOf(0) * 0.8),
        reason: 'the blind spammer should be stalled well short');
    expect(g.winResult!.winner, 0);
  });

  test('hold-to-vault also clears a hurdle (the second one-touch mapping)', () {
    // A runner that strides on the beat AND holds a press the whole time auto-
    // vaults each hurdle at the right moment, so HOLD is a valid clearing input.
    // It should out-distance an identical runner that strides but never vaults.
    TapSprint runHold(bool hold) {
      final ctx = MiniGameContext(
        players: [PlayerSlot.defaults(0)],
        arena: const Size(800, 1200),
        rng: SeededRng(5),
        zones: ZoneLayout.forPlayers(1),
      );
      final g = TapSprint()..init(ctx);
      for (var f = 0; f < 60 * 14 && g.status != MiniGameStatus.finished; f++) {
        if (f % strideFrames == 0) g.onInput(PlayerInput.down(0)); // stride beat
        if (hold) {
          g.onInput(PlayerInput(playerId: 0, phase: InputPhase.holdTick, dt: dt));
        }
        g.update(dt);
      }
      return g;
    }

    final holder = runHold(true);
    final noVault = runHold(false);
    expect(holder.metersOf(0), greaterThan(noVault.metersOf(0)),
        reason: 'holding to auto-vault must clear hurdles the no-vault run trips on');
  });

  test('render does not throw across the round', () {
    final players = [
      for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(11),
      zones: ZoneLayout.forPlayers(4),
    );
    final g = TapSprint()..init(ctx);
    final canvas = Canvas(PictureRecorder());

    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
    for (var i = 0; i < 400 && g.status != MiniGameStatus.finished; i++) {
      g.update(dt);
      g.onInput(PlayerInput.down(0));
    }
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });

  test('measured solo run reaches the finish', () {
    final g = runMeasuredSolo(5);
    expect(g.status, MiniGameStatus.finished);
    expect(g.metersOf(0), greaterThan(0));
  });
}
