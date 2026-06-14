import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/bots.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
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
  /// "never throws" (the gunner mascot + team tints draw here).
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

  test('human tap fires without throwing', () {
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
    g.onInput(PlayerInput.down(0, const Offset(0.5, 0.9)));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
      if (n % 30 == 0) g.onInput(PlayerInput.down(0));
    }
    expect(g.status, MiniGameStatus.finished);
  });

  test('a pure tap (down then immediate up) still fires; round resolves', () {
    // Tap-to-fire must survive the hold-to-slow-aim addition: a down+up in the
    // same frame is a snap shot (release always looses).
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
    // still loose a shell on release without throwing — exercising the new
    // charge ramp + the charged-speed launch path. ~70 frames ≈ 1.17s hold.
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
    // resolve and hits land in aggregate (score accrues from landed shells) —
    // and crucially nothing throws while charged shells are in flight.
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
    // Shells (tap + charged) reach their targets, so hits accumulate overall.
    expect(totalHits, greaterThan(0));
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

  test('render never throws across modes (gunner mascot + team tints + wreck)',
      () {
    // Drive each mode to a finish (so wrecks, the winner pulse and the cheering
    // gunner are all on screen) and render at several points — none may throw.
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

  // ── THE DESIGN LAW: a blind trigger-masher must LOSE to timed, aimed fire ────

  /// Build a 2p human-vs-human duel (P0 bottom, P1 top) on a shared seed so both
  /// shooters face the SAME sweep phases, crate board and airdrops — any score
  /// gap is the SKILL gap, not luck. No bots: both tanks are human-driven by the
  /// test so [ctx.rng] alone drives the world deterministically.
  ///
  /// A SQUARE arena is used on purpose: it makes the two facing tanks symmetric
  /// (neither gravity-favored the way a top tank firing DOWN would be on a tall
  /// board), so the round isolates the one variable under test — timed aim vs
  /// blind mashing — instead of confounding it with edge geometry. A snap shot
  /// comfortably reaches across this span, so the proof is purely about WHEN you
  /// loose the scarce shell, not whether it can reach.
  MiniGameContext duelCtx(int seed) => MiniGameContext(
        players: [PlayerSlot.defaults(0), PlayerSlot.defaults(1)],
        arena: const Size(800, 800),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(2),
      );

  /// Drive one shared duel: P0 SKILLED (fires only when the breech is loaded AND
  /// the sweep is lined up on the solved lead onto the foe), P1 BLIND SPAMMER
  /// (down+up every single frame, never aiming/charging). The spammer's own rng
  /// is separate from [ctx.rng] so the sim stays deterministic. Returns the game
  /// at finish.
  TankDuel runDuel(int seed) {
    final g = TankDuel()..init(duelCtx(seed));
    // Aim tolerance for the skilled release: a tight cone, so P0 only looses a
    // scarce shell when the sweep actually crosses the firing line (timing it on
    // the sweep — exactly what the design rewards).
    const aimTol = 0.06;
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      // P0 SKILLED: wait for a loaded breech, then fire the instant the sweep is
      // within the cone of the lead angle onto the enemy (a snap, well-aimed).
      if (g.debugIsLoaded(0)) {
        final want = g.debugBestAimAngle(0);
        if (want != null && (g.debugAimAngle(0) - want).abs() <= aimTol) {
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.down));
          g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
        }
      }
      // P1 BLIND SPAMMER: mash the trigger every frame, no aim, no charge. The
      // reload economy holds it to the same scarce shell budget, and every shell
      // it does loose flies at whatever angle the sweep happens to sit on.
      g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.down));
      g.onInput(const PlayerInput(playerId: 1, phase: InputPhase.up));
      g.update(1 / 60);
    }
    return g;
  }

  test('DESIGN LAW (per-seed): a blind trigger-masher NEVER wins the duel', () {
    // On EVERY seed the blind spammer must not finish 1st against a shooter who
    // times the scarce shot on the sweep. Requiring it across several shared
    // boards makes the proof robust (not one lucky sweep) and would surface any
    // real hole in the reload-gated "each shot must count" law.
    for (final seed in [1, 7, 19, 23, 42, 88]) {
      final g = runDuel(seed);
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      final rank = g.winResult!.ranking;
      expect(rank.first, isNot(1),
          reason: 'seed $seed: blind masher must NOT win ($rank, scores '
              '${g.winResult!.finalScores})');
    }
  });

  test('DESIGN LAW (aggregate): timed aim strictly OUT-HITS blind mashing', () {
    // Across the shared seeds, the skilled shooter's TOTAL landed hits must
    // strictly dominate the spammer's. (A single chaotic duel can swing on a
    // lucky spray, so the strict dominance is asserted in aggregate — the same
    // shape the sibling chaotic games use.) Also proves the spammer banks SOME
    // hits (the board isn't degenerate) yet still loses the volume war on
    // accuracy, not on a lower fire-rate.
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
        reason: 'timed aim must out-hit blind mashing in aggregate '
            '(skilled=$skilledHits spam=$spamHits)');
    // Dominance, not a coin-flip edge: aim should clearly beat spray.
    expect(skilledHits, greaterThan(spamHits * 1.5),
        reason: 'aimed fire should DOMINATE, not edge out, blind mashing '
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
}
