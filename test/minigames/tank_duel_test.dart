import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/tank_duel/manual_aim.dart';
import 'package:stick_party/minigames/tank_duel/tank_duel.dart';
import 'package:stick_party/minigames/tank_duel/tank_fx.dart';

void main() {
  MiniGameContext ctxFor(int n,
      {int seed = 7,
      BotDifficulty difficulty = BotDifficulty.medium,
      GameMode mode = GameMode.ffa}) {
    final players = [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)];
    return MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(n),
      difficulty: difficulty,
      mode: mode,
    );
  }

  /// Advance an all-bot game to its finish (or a hard cap) at a fixed 60 fps,
  /// returning the frame count it took.
  int runToFinish(TankDuel g, {int maxFrames = 60 * 80}) {
    var frames = 0;
    while (g.status != MiniGameStatus.finished && frames++ < maxFrames) {
      g.update(1 / 60);
    }
    return frames;
  }

  /// Render one frame into a throwaway canvas so render-path asserts can prove
  /// "never throws" (the manual reticle + predicted arc + strafe dust + gunner
  /// mascot + team tints all draw here).
  void renderOnce(TankDuel g, {ui.Size size = const ui.Size(800, 1200)}) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Offset.zero & size);
    g.render(canvas, size);
    recorder.endRecording().dispose();
  }

  test('tank duel finishes with four bots and ranks all players', () {
    final g = TankDuel()..init(ctxFor(4));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('all-bot 4p round lasts > 1.5s and finishes within the time limit', () {
    // Across several seeds: a round must never end in a sub-1.5s flash (the
    // min-duration floor + bot warm-up guarantee it plays out), yet must always
    // resolve by the 40s limit. 40s ≈ 2400 frames; allow slack for hit-stop.
    for (var seed = 0; seed < 8; seed++) {
      final g = TankDuel()..init(ctxFor(4, seed: 100 + seed));
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      expect(frames, greaterThan(90),
          reason: 'seed $seed ended too fast (${frames / 60}s)');
      expect(frames, lessThan(60 * 50),
          reason: 'seed $seed overran the limit (${frames / 60}s)');
    }
  });

  for (final count in [1, 2, 3]) {
    test('tank duel finishes with $count player(s)', () {
      final g = TankDuel()..init(ctxFor(count, seed: 11 + count));
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished);
      expect(g.winResult!.ranking.toSet(),
          {for (var i = 0; i < count; i++) i});
    });
  }

  test('human drag-fire (down, drag, up) fires without throwing', () {
    final players = [
      PlayerSlot.defaults(0),
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(3),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = TankDuel()..init(ctx);
    // A drag aims the barrel up-field, then a release fires.
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.6)));
    g.onInput(const PlayerInput(
        playerId: 0, phase: InputPhase.up, normPos: Offset(0.5, 0.55)));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
      if (n % 30 == 0) {
        g.onInput(const PlayerInput(
            playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.6)));
        g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
      }
    }
    expect(g.status, MiniGameStatus.finished);
  });

  test('a pure tap (down then immediate up, no drag) still fires; round resolves',
      () {
    // Tap-to-fire must survive the manual-aim rework: a down+up with no position
    // is a snap shot down the CURRENT (sticky) aim — release always looses, and
    // the zero-position sentinel leaves the aim untouched.
    final players = [
      PlayerSlot.defaults(0),
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(8),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = TankDuel()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      if (n % 25 == 0) {
        expect(() {
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.down));
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
        }, returnsNormally);
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
  });

  test('a full charge (down, long hold, release) fires a charged shell; '
      'round resolves', () {
    // A long hold (well past the ~0.9s full-charge time) must accrue power and
    // still loose a shell on release without throwing — exercising the charge
    // ramp + the charged-speed launch path. ~70 frames ≈ 1.17s hold.
    final players = [
      PlayerSlot.defaults(0),
      PlayerSlot.defaults(1, isBot: true),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(9),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = TankDuel()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      if (n % 120 == 0) {
        expect(() => g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.down)),
            returnsNormally);
      }
      if (n % 120 == 70) {
        expect(() => g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up)),
            returnsNormally);
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
  });

  test('charging bots fire, land hits, and resolve (arc solved at charge speed)',
      () {
    // Hard bots wind up a charged shot a good share of the time. A charged shell
    // is solved at the SAME (faster) speed it launches at, so it must still
    // connect rather than sail away. Across several hard-bot rounds the games
    // resolve and hits land in aggregate — and crucially nothing throws while
    // charged shells are in flight or while bots steer their manual aim.
    var totalHits = 0.0;
    for (var seed = 0; seed < 6; seed++) {
      final g = TankDuel()
        ..init(ctxFor(2, seed: 200 + seed, difficulty: BotDifficulty.hard));
      var n = 0;
      expect(() {
        while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
          g.update(1 / 60);
        }
      }, returnsNormally, reason: 'seed $seed threw mid-flight');
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      for (final v in g.winResult!.finalScores.values) {
        totalHits += v.toDouble();
      }
    }
    // Led shells (tap + charged) reach their moving targets, so hits accumulate.
    expect(totalHits, greaterThan(0));
  });

  // ── ManualAim helper (the drag-aim primitive) ──────────────────────────────

  group('ManualAim (drag-aim, clamped to the firing band)', () {
    test('aimToward clamps a heading past the band edge onto the limit', () {
      // A band centered straight up-screen (-pi/2) ±0.5 rad.
      const center = -math.pi / 2;
      final aim = ManualAim(minAngle: center - 0.5, maxAngle: center + 0.5);
      // Drag far to the right of the pivot → wants to point right (~0 rad), but
      // that's outside the band, so it must rest on the nearest edge.
      aim.aimToward(const Offset(0, 0), const Offset(1000, -1));
      expect(aim.angle, closeTo(center + 0.5, 1e-6));
      expect(aim.angle, greaterThanOrEqualTo(aim.minAngle));
      expect(aim.angle, lessThanOrEqualTo(aim.maxAngle));
    });

    test('setAngle is sticky + clamped; a target behind folds to an edge', () {
      const center = math.pi / 2; // straight down-screen
      final aim = ManualAim(minAngle: center - 0.4, maxAngle: center + 0.4);
      aim.setAngle(center + 0.2);
      expect(aim.angle, closeTo(center + 0.2, 1e-6)); // holds where set
      // An angle well outside (pointing up, behind a down-facing tank) clamps to
      // the nearest band edge instead of wrapping to the far side.
      aim.setAngle(-math.pi / 2);
      expect(aim.angle,
          anyOf(closeTo(aim.minAngle, 1e-6), closeTo(aim.maxAngle, 1e-6)));
    });

    test('nudge steers within the band and saturates at the near edge', () {
      final aim = ManualAim(minAngle: -0.5, maxAngle: 0.5, angle: 0);
      aim.nudge(0.2);
      expect(aim.angle, closeTo(0.2, 1e-6));
      // Several small steps (as a bot's bounded turn would take) walk it to the
      // near edge and saturate there — the manual aim never leaves the band.
      for (var i = 0; i < 10; i++) {
        aim.nudge(0.2);
      }
      expect(aim.angle, closeTo(0.5, 1e-6));
      for (var i = 0; i < 20; i++) {
        aim.nudge(-0.2);
      }
      expect(aim.angle, closeTo(-0.5, 1e-6));
    });

    test('rejects a non-finite or inverted band', () {
      expect(() => ManualAim(minAngle: double.nan, maxAngle: 1),
          throwsArgumentError);
      expect(() => ManualAim(minAngle: 1, maxAngle: 0), throwsArgumentError);
    });
  });

  // ── TEAM 2v2 + FFA fairness ────────────────────────────────────────────────

  test('team2v2 4p finishes and ranks all four players', () {
    final g = TankDuel()..init(ctxFor(4, seed: 40, mode: GameMode.team2v2));
    runToFinish(g);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('team2v2 resolves by TEAM: the winning squad takes the top two ranks',
      () {
    // Squads split by id parity ({0,2} vs {1,3}). However a round resolves —
    // a team wiped early or most aggregate hits at the bell — the two members
    // of the winning team must occupy ranks 0 & 1 (never interleaved with the
    // losers), proving scoring/ranking aggregate per TEAM rather than per loner.
    for (var seed = 0; seed < 8; seed++) {
      final g =
          TankDuel()..init(ctxFor(4, seed: 300 + seed, mode: GameMode.team2v2));
      runToFinish(g);
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      final rank = g.winResult!.ranking;
      // Top two are teammates (same parity); bottom two are the other squad.
      expect(rank[0].isEven, rank[1].isEven,
          reason: 'seed $seed: top two should be one squad ($rank)');
      expect(rank[2].isEven, rank[3].isEven,
          reason: 'seed $seed: bottom two should be the other squad ($rank)');
      expect(rank[0].isEven, isNot(rank[2].isEven),
          reason: 'seed $seed: the two squads must not interleave ($rank)');
    }
  });

  test('friendly fire is OFF: a team is never wiped faster than free-for-all',
      () {
    // With friendly fire off, teammates cannot damage each other, so a 2v2
    // takes (on aggregate, across seeds) AT LEAST as long to resolve as the same
    // four tanks in a free-for-all where every shell can hurt every other tank.
    // A shorter team round would betray teammates dealing damage. Deterministic
    // via ctx.rng (same seeds compared head-to-head).
    var ffaTotal = 0, teamTotal = 0;
    for (var seed = 0; seed < 8; seed++) {
      final ffa = TankDuel()..init(ctxFor(4, seed: 500 + seed));
      final team = TankDuel()
        ..init(ctxFor(4, seed: 500 + seed, mode: GameMode.team2v2));
      ffaTotal += runToFinish(ffa);
      teamTotal += runToFinish(team);
    }
    expect(teamTotal, greaterThanOrEqualTo(ffaTotal),
        reason: 'team rounds resolved faster than FFA — friendly fire leaked');
  });

  test('team2v2 paces correctly: past the floor, within the limit', () {
    for (var seed = 0; seed < 6; seed++) {
      final g =
          TankDuel()..init(ctxFor(4, seed: 700 + seed, mode: GameMode.team2v2));
      final frames = runToFinish(g);
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      expect(frames, greaterThan(90),
          reason: 'seed $seed ended too fast (${frames / 60}s)');
      expect(frames, lessThan(60 * 50),
          reason: 'seed $seed overran the limit (${frames / 60}s)');
    }
  });

  test('odd 3p stays free-for-all (no lone-ganged team) even in team2v2 mode',
      () {
    // An odd seat count can't split into fair squads, so requesting team2v2 with
    // 3 players must fall back to FFA: each tank scores for itself and all three
    // are ranked individually. (The 1-vs-2 unfairness is the thing we avoid.)
    final g = TankDuel()..init(ctxFor(3, seed: 21, mode: GameMode.team2v2));
    runToFinish(g);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2});
  });

  test('render never throws across modes (reticle + arc + strafe + gunner + wreck)',
      () {
    // Drive each mode to a finish (so wrecks, the winner pulse, the strafing
    // tanks, the predicted-arc reticle and the cheering gunner are all on
    // screen) and render at several points — none may throw.
    for (final mode in [GameMode.ffa, GameMode.team2v2]) {
      final g = TankDuel()..init(ctxFor(4, seed: 33, mode: mode));
      expect(() {
        for (var i = 0; i < 60 * 80 && g.status != MiniGameStatus.finished; i++) {
          g.update(1 / 60);
          if (i % 40 == 0) renderOnce(g);
        }
        renderOnce(g); // final frame: winner celebration + any wrecks
      }, returnsNormally, reason: 'mode $mode threw while rendering');
      expect(g.status, MiniGameStatus.finished);
    }
  });

  test('render never throws for 1..4 players while a human drags + charges', () {
    // A human dragging onto the field and holding a charge populates the live
    // predicted arc + reticle + charge gauge; rendering that with 1..4 seats and
    // a strafing board must never throw.
    for (final count in [1, 2, 3, 4]) {
      final players = [
        PlayerSlot.defaults(0),
        for (var i = 1; i < count; i++) PlayerSlot.defaults(i, isBot: true),
      ];
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(800, 1200),
        rng: SeededRng(60 + count),
        zones: ZoneLayout.forPlayers(count),
      );
      final g = TankDuel()..init(ctx);
      expect(() {
        for (var i = 0; i < 60 * 80 && g.status != MiniGameStatus.finished; i++) {
          // Hold a drag-charge on P0 so the arc preview + gauge are live.
          if (i % 90 == 0) {
            g.onInput(const PlayerInput(
                playerId: 0, phase: InputPhase.down, normPos: Offset(0.5, 0.5)));
          }
          if (i % 90 == 40) {
            g.onInput(const PlayerInput(
                playerId: 0, phase: InputPhase.holdTick, normPos: Offset(0.4, 0.5)));
          }
          if (i % 90 == 60) {
            g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
          }
          g.update(1 / 60);
          if (i % 25 == 0) renderOnce(g);
        }
      }, returnsNormally, reason: '$count-player render threw');
    }
  });

  group('AirdropController (chaos pickup)', () {
    final field = const Rect.fromLTRB(60, 60, 740, 1140);
    AirdropController make() => AirdropController(
          half: 18,
          firstDropSec: 3.0,
          respawnSec: 5.0,
          lifeSec: 6.0,
          appearPerSec: 3.0,
          bobPerSec: 2.0,
        );

    test('drops inside the central band after its delay and eases in', () {
      final c = make();
      final rng = SeededRng(4);
      // Before the delay: nothing.
      for (var i = 0; i < 60; i++) {
        c.tick(1 / 60, rng, field);
      }
      expect(c.crate, isNull);
      // Past the delay + ease-in: a ready crate in the central band.
      for (var i = 0; i < 60 * 3; i++) {
        c.tick(1 / 60, rng, field);
      }
      final crate = c.crate;
      expect(crate, isNotNull);
      expect(crate!.ready, isTrue);
      expect(crate.pos.dy, greaterThan(field.top + field.height * 0.31));
      expect(crate.pos.dy, lessThan(field.bottom - field.height * 0.31));
    });

    test('contains() is true only at a ready crate; consume clears it', () {
      final c = make();
      final rng = SeededRng(5);
      for (var i = 0; i < 60 * 4; i++) {
        c.tick(1 / 60, rng, field);
      }
      final crate = c.crate!;
      expect(c.contains(crate.pos), isTrue);
      expect(c.contains(crate.pos + const Offset(500, 0)), isFalse);
      c.consume();
      expect(c.crate, isNull);
      expect(c.contains(crate.pos), isFalse);
    });
  });

  // ── THE DESIGN LAW: a blind trigger-masher must LOSE to LED, aimed fire ─────

  /// Build a 2p human-vs-human duel (P0 bottom, P1 top) on a shared seed so both
  /// shooters face the SAME strafe phases, crate board and airdrops — any score
  /// gap is the SKILL gap, not luck. No bots: both tanks are human-driven by the
  /// test so [ctx.rng] alone drives the world deterministically.
  ///
  /// A SQUARE arena is used on purpose: it makes the two facing tanks symmetric
  /// (neither gravity-favored the way a top tank firing DOWN would be on a tall
  /// board), so the round isolates the one variable under test — LED, timed aim
  /// vs blind mashing — instead of confounding it with edge geometry. A snap shot
  /// comfortably reaches across this span, so the proof is purely about WHERE you
  /// point the scarce shell (the moving foe's lead) and WHEN you loose it.
  MiniGameContext duelCtx(int seed) => MiniGameContext(
        players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1)],
        arena: const Size(800, 800),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(2),
      );

  /// Drive one shared duel: P0 SKILLED (each frame DRAGS its manual aim onto the
  /// solved lead onto the strafing foe via the debug seams, and fires the instant
  /// the breech is loaded AND the barrel is on the lead), P1 BLIND SPAMMER
  /// (down+up every single frame, never aiming — its sticky barrel just sits at
  /// its rest angle while shells fly at a foe that has strafed away). Returns the
  /// game at finish.
  TankDuel runDuel(int seed) {
    final g = TankDuel()..init(duelCtx(seed));
    // Aim tolerance for the skilled release: tight, so P0 only looses when its
    // manual barrel is genuinely on the solved lead.
    const aimTol = 0.06;
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      // P0 SKILLED: solve the lead onto the MOVING foe, DRIVE the manual aim onto
      // it (the player's drag), then fire only when loaded + lined up.
      final want = g.debugBestAimAngle(0);
      if (want != null) {
        g.debugSetAim(0, want); // drag the barrel onto the lead
        if (g.debugIsLoaded(0) && (g.debugAimAngle(0) - want).abs() <= aimTol) {
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.down));
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
        }
      }
      // P1 BLIND SPAMMER: mash the trigger every frame, no aim. The reload economy
      // holds it to the same scarce shell budget, and every shell it looses flies
      // down its STALE rest aim at a foe that keeps strafing out of the way.
      g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.down));
      g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.up));
      g.update(1 / 60);
    }
    return g;
  }

  test('DESIGN LAW (per-seed): a blind trigger-masher NEVER wins the duel', () {
    // On EVERY seed the blind spammer must not finish 1st against a shooter who
    // leads the moving foe and times the scarce shot. Requiring it across several
    // shared boards makes the proof robust (not one lucky strafe) and would
    // surface any real hole in the manual-aim + reload-gated "each shot must
    // count" law.
    for (final seed in [1, 7, 19, 23, 42, 88]) {
      final g = runDuel(seed);
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      final rank = g.winResult!.ranking;
      expect(rank.first, isNot(1),
          reason: 'seed $seed: blind masher must NOT win ($rank, scores '
              '${g.winResult!.finalScores})');
    }
  });

  test('DESIGN LAW (aggregate): led, timed aim strictly OUT-HITS blind mashing',
      () {
    // Across the shared seeds, the skilled shooter's TOTAL landed hits must
    // strictly DOMINATE the spammer's. (A single chaotic duel can swing on a
    // lucky spray, so the strict dominance is asserted in aggregate.) Also proves
    // the spammer banks SOME hits (the board isn't degenerate) yet still loses
    // the volume war on AIM (leading a moving target), not on a lower fire-rate.
    var skilledHits = 0.0, spamHits = 0.0;
    var skilledShots = 0, spamShots = 0;
    for (final seed in [1, 7, 19, 23, 42, 88]) {
      final g = runDuel(seed);
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      skilledHits += (g.winResult!.finalScores[0] ?? 0).toDouble();
      spamHits += (g.winResult!.finalScores[1] ?? 0).toDouble();
      skilledShots += g.debugShotsFired(0);
      spamShots += g.debugShotsFired(1);
    }
    expect(skilledHits, greaterThan(spamHits),
        reason: 'led aim must out-hit blind mashing in aggregate '
            '(skilled=$skilledHits spam=$spamHits)');
    // Dominance, not a coin-flip edge: aim should clearly beat spray.
    expect(skilledHits, greaterThan(spamHits * 1.5),
        reason: 'led fire should DOMINATE, not edge out, blind mashing '
            '(skilled=$skilledHits spam=$spamHits)');
    // The win is accuracy, NOT volume: the masher gets at least as many shells
    // off as the skilled shooter (it pulls the trigger far more often), yet
    // lands fewer — proving the reload economy denies a fire-rate win.
    expect(spamShots, greaterThanOrEqualTo(skilledShots),
        reason: 'the masher should loose at least as many shells '
            '(spam=$spamShots skilled=$skilledShots) — it loses on AIM');
    expect(spamHits, greaterThan(0),
        reason: 'sanity: a blind spray still lands the odd lucky shell');
  });

  test('reload caps fire-rate: a frame-perfect masher fires only a few shells '
      'per second (no spray)', () {
    // The lever itself: even pressing down+up EVERY frame for one second, the
    // breech reload lets only a handful of shells out — not 60. This is what
    // converts "mash faster" into "each shot must count".
    final g = TankDuel()..init(duelCtx(5));
    for (var i = 0; i < 60; i++) {
      g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.down));
      g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
      g.update(1 / 60);
    }
    final shots = g.debugShotsFired(0);
    expect(shots, greaterThan(0), reason: 'a masher still fires SOME');
    // ~1 shell per reload (≈0.62s) → about 2 in a second, never a 60-shot spray.
    expect(shots, lessThanOrEqualTo(4),
        reason: 'reload must cap a frame-perfect mash to a few shells/s, got '
            '$shots');
  });

  test('manual aim is STICKY: a tap never moves the barrel from where it was set',
      () {
    // Manual aim holds between shots. Set it via the debug seam, then a
    // zero-position tap (snap fire) must leave the angle exactly where it was —
    // the barrel does not re-center or sweep on its own.
    final g = TankDuel()..init(duelCtx(13));
    // Bottom tank: inward normal is up (-pi/2); aim toward one band edge.
    g.debugSetAim(0, -math.pi / 2 - 0.5);
    final set = g.debugAimAngle(0);
    // A pure tap (no position) fires but must NOT change the aim.
    g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.down));
    g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
    g.update(1 / 60);
    expect(g.debugAimAngle(0), closeTo(set, 1e-9),
        reason: 'a tap must keep the sticky manual aim, not move it');
  });

  test('rot2 TOP-SEAT human drag aims INTO the arena (not inverted), via onInput',
      () {
    // The zone-aim rotation correctness fix: P1 sits on the TOP edge (rot2). Its
    // inward normal points DOWN-screen (+y, sin > 0). A top-seat player drags
    // "away from my body" — downward, into the field — within its own top zone.
    // The real onInput path (down at the press point, then a holdTick drag deeper
    // into the field) must resolve the barrel to point INTO the arena (sin > 0),
    // NOT flip it back up toward the top rim. Avatar world position must not
    // affect this — the aim is measured purely from the gesture within the zone.
    final players = [
      PlayerSlot.defaults(0),
      PlayerSlot.defaults(1), // human top seat (rot2)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(31),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = TankDuel()..init(ctx);
    // Top zone is the upper half (y in [0, 0.5]); press near the top edge, then
    // drag DOWN toward the arena center — the player's "into the field" gesture.
    g.onInput(const PlayerInput(
        playerId: 1, phase: InputPhase.down, normPos: Offset(0.5, 0.12)));
    g.onInput(const PlayerInput(
        playerId: 1, phase: InputPhase.holdTick, normPos: Offset(0.5, 0.40)));
    final angle = g.debugAimAngle(1);
    // Into the arena for a top tank = downward = sin(angle) > 0. An inverted
    // (un-rotation-corrected) result would point up the screen (sin < 0).
    expect(math.sin(angle), greaterThan(0),
        reason: 'top-seat drag into the field must aim DOWN into the arena, '
            'got angle=$angle (sin=${math.sin(angle)})');
  });

  test('tanks STRAFE: the solved lead angle tracks the moving foe over time', () {
    // The moving-target mechanic: the solved lead angle onto the enemy must shift
    // as that enemy strafes (a static foe would never move the lead). Read the
    // lead at two well-separated times; it must differ.
    final g = TankDuel()..init(duelCtx(17));
    final a0 = g.debugBestAimAngle(0);
    for (var i = 0; i < 90; i++) {
      g.update(1 / 60); // ~1.5s — comfortably more than half a strafe pass
    }
    final a1 = g.debugBestAimAngle(0);
    expect(a0, isNotNull);
    expect(a1, isNotNull);
    expect((a1! - a0!).abs(), greaterThan(1e-3),
        reason: 'the lead onto a strafing foe should move as it slides '
            '(a0=$a0 a1=$a1)');
  });

  // ── COMPETITIVE: skill gradient + beatable-but-tough hard bot ────────────────
  //
  // The spam-loses laws above prove the MECHANIC rewards aim over mashing. These
  // prove the BOTS are tuned for a fair fight: a SKILLED human in seat 0 (drags
  // its manual aim onto the solved moving-target lead via the debug seams and
  // fires the instant the breech is loaded AND the barrel is lined up) must
  // CLEARLY beat an easy bot, hold a real edge over medium, and find HARD a
  // beatable-but-tough wall — never a 0% brick nor a 100% pushover. A clean
  // EASY ≥ MEDIUM ≥ HARD gradient is the headline.
  //
  // 1v1 (GameMode.duel1v1) on a SQUARE arena is the clean read: one human vs one
  // bot, symmetric edges, FFA scoring (first to 3 hits or most at the bell), so
  // the only variable is the bot's skill tier — not seat geometry or a teammate.
  //
  // Bands are robust SUPERSETS of measured win-rates (≥16 seeds), validated on a
  // DISJOINT seed window so they aren't fit to one lucky board. Measured (16
  // seeds/diff) across four windows {0..15, 500..515, 1000..1015, 2000..2023}:
  //   easy   0.875 – 0.938   (band ≥ 0.70)
  //   medium 0.500 – 0.625
  //   hard   0.250 – 0.458   (band [0.15, 0.90])

  /// A 1v1 duel context: SKILLED human in seat 0 vs ONE bot of [difficulty] in
  /// seat 1, [GameMode.duel1v1] (FFA scoring) on a square, symmetric arena.
  MiniGameContext skillVsBotCtx(int seed, BotDifficulty difficulty) =>
      MiniGameContext(
        players: [
          PlayerSlot.defaults(0), // skilled human (driven by the test)
          PlayerSlot.defaults(1, isBot: true), // bot foe
        ],
        arena: const Size(800, 800),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(2),
        difficulty: difficulty,
        mode: GameMode.duel1v1,
      );

  /// One skilled-human (seat 0) vs bot (seat 1) duel. Seat 0 each frame DRAGS its
  /// manual aim onto the solved lead of the strafing bot and fires only when the
  /// breech is loaded AND the barrel is on that lead; the engine drives the bot.
  /// Returns (seat-0 won, hit margin seat0−seat1) at finish.
  ({bool won, int margin}) runSkillVsBot(int seed, BotDifficulty difficulty) {
    final g = TankDuel()..init(skillVsBotCtx(seed, difficulty));
    const aimTol = 0.06;
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      final want = g.debugBestAimAngle(0);
      if (want != null) {
        g.debugSetAim(0, want); // drag the barrel onto the moving foe's lead
        if (g.debugIsLoaded(0) && (g.debugAimAngle(0) - want).abs() <= aimTol) {
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.down));
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
        }
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished,
        reason: 'seed $seed did not resolve');
    final r = g.winResult!;
    final a = (r.finalScores[0] ?? 0).toInt();
    final b = (r.finalScores[1] ?? 0).toInt();
    return (won: r.ranking.first == 0, margin: a - b);
  }

  /// Win-rate of the skilled human over [seeds] vs a bot of [difficulty].
  double skillWinRate(BotDifficulty difficulty, List<int> seeds) {
    var wins = 0;
    for (final seed in seeds) {
      if (runSkillVsBot(seed, difficulty).won) wins++;
    }
    return wins / seeds.length;
  }

  // The primary measurement window the bands were tuned against.
  final primarySeeds = [for (var s = 0; s < 16; s++) s];
  // A DISJOINT window the bands are re-validated on (proves they aren't overfit).
  final disjointSeeds = [for (var s = 1000; s < 1016; s++) s];

  test('COMPETITIVE: EASY bot is clearly beatable by a skilled aimer (>=0.70)',
      () {
    // A skilled human should win the clear majority vs an easy bot — it under-
    // leads the strafe and commits wide shots, so timed, led fire dominates it.
    for (final seeds in [primarySeeds, disjointSeeds]) {
      final wr = skillWinRate(BotDifficulty.easy, seeds);
      expect(wr, greaterThanOrEqualTo(0.70),
          reason: 'easy must be clearly beatable, got $wr on $seeds');
    }
  });

  test('COMPETITIVE: HARD bot is beatable-but-tough (win-rate in [0.15, 0.90])',
      () {
    // Hard tracks the lead tightly and lands most of its scarce shells, so the
    // skilled human wins only sometimes — but it is NEVER a 0% wall (the hard bot
    // keeps a floored aim spread, so it sprays the odd wide shell and a sharp
    // human can steal the race) nor a trivial 100% pushover.
    for (final seeds in [primarySeeds, disjointSeeds]) {
      final wr = skillWinRate(BotDifficulty.hard, seeds);
      expect(wr, inInclusiveRange(0.15, 0.90),
          reason: 'hard must be tough but beatable, got $wr on $seeds');
    }
  });

  test('COMPETITIVE: a clean skill gradient — winEasy >= winMedium >= winHard '
      'AND winEasy > winHard', () {
    // The headline: harder bots win more, monotonically, on BOTH windows. The
    // strict easy>hard gap proves the difficulty knob actually moves the duel.
    for (final seeds in [primarySeeds, disjointSeeds]) {
      final easy = skillWinRate(BotDifficulty.easy, seeds);
      final medium = skillWinRate(BotDifficulty.medium, seeds);
      final hard = skillWinRate(BotDifficulty.hard, seeds);
      expect(easy, greaterThanOrEqualTo(medium),
          reason: 'easy ($easy) should be at least as beatable as medium '
              '($medium) on $seeds');
      expect(medium, greaterThanOrEqualTo(hard),
          reason: 'medium ($medium) should be at least as beatable as hard '
              '($hard) on $seeds');
      expect(easy, greaterThan(hard),
          reason: 'the gradient must be real: easy ($easy) > hard ($hard) '
              'on $seeds');
    }
  });

  test('COMPETITIVE: not luck-dominated — vs EASY the skilled aimer wins most '
      'individual seeds', () {
    // Beating easy must be reliable, not a coin flip: across the primary window
    // the skilled human wins the large majority of INDIVIDUAL boards (so the
    // aggregate win-rate isn't carried by a couple of lucky strafes).
    var wins = 0;
    for (final seed in primarySeeds) {
      if (runSkillVsBot(seed, BotDifficulty.easy).won) wins++;
    }
    expect(wins, greaterThanOrEqualTo(11),
        reason: 'skilled aim should reliably beat easy across seeds, '
            'won $wins/${primarySeeds.length}');
  });

  test('COMPETITIVE: NO runaway — duels are decided by close, varied margins '
      'with comebacks both ways', () {
    // A healthy duel swings: across the primary window vs medium the per-seed
    // margins must VARY (not a fixed blowout) and BOTH sides must take seeds —
    // the human wins some and the bot wins some, so no single outcome runs away.
    final margins = <int>{};
    var humanWins = 0, botWins = 0;
    for (final seed in primarySeeds) {
      final r = runSkillVsBot(seed, BotDifficulty.medium);
      margins.add(r.margin);
      if (r.won) {
        humanWins++;
      } else {
        botWins++;
      }
    }
    expect(margins.length, greaterThan(1),
        reason: 'margins should vary across seeds, got $margins');
    expect(humanWins, greaterThan(0), reason: 'the human must win some seeds');
    expect(botWins, greaterThan(0),
        reason: 'the bot must win some seeds (a comeback exists), not a sweep');
    // Close fights: every duel is decided within a couple of hits, never a rout.
    for (final m in margins) {
      expect(m.abs(), lessThanOrEqualTo(3),
          reason: 'a duel margin should stay close (<=3), got $m');
    }
  });
}
