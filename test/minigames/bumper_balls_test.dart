import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/bumper_balls/bumper_balls.dart';
import 'package:stick_party/minigames/bumper_balls/bumper_fx.dart';

/// Frames-per-second the headless sim is stepped at.
const int _fps = 60;

/// Hard floor: an all-bot round must never end this fast (guards against an
/// instant-end regression where a single launch ejects an idle ball at once).
const double _minRoundSec = 1.5;

/// Generous upper bound for the headless loop (well past the in-game limit).
const int _maxFrames = 60 * 80;

BumperBalls _build(int count, int seed) {
  final players = [
    for (var i = 0; i < count; i++) PlayerSlot.defaults(i, isBot: true),
  ];
  final ctx = MiniGameContext(
    players: players,
    arena: const Size(800, 1200),
    rng: SeededRng(seed),
    zones: ZoneLayout.forPlayers(count),
  );
  return BumperBalls()..init(ctx);
}

/// Run [g] to completion, returning the number of simulated frames it took.
int _runToFinish(BumperBalls g) {
  var n = 0;
  while (g.status != MiniGameStatus.finished && n < _maxFrames) {
    g.update(1 / _fps);
    n++;
  }
  return n;
}

/// Cadence + self-safety of the MEASURED slingshotter, shared by the duel and
/// mixed runners so both score the same "skilled" behaviour:
///  * on a paced cadence (clears the ~0.22s launch cooldown) it AIMS at the
///    nearest rival and pulls a STRONG (full-power) slingshot, but
///  * only when it is NOT hugging its OWN edge — so it banks rivals toward the
///    rim without rocketing ITSELF off.
/// That single self-preservation read (don't fire when you would sail off) is
/// the judgement a blind every-frame tapper never makes.
const int _skilledPeriod = 14; // a judged launch roughly every 0.23s when ready
const double _skilledSelfSafeFrac = 0.72; // fire only when below this edge-frac

void _driveSpammer(BumperBalls g, int blindId) {
  // SPAMMER: a power-0 launch every single frame (a blind instant tap). Power is
  // the VISIBLE pull distance, so a tap = power 0 = a feeble dud nudge: no rocket
  // window, commit-gated knockback that cannot eject — it drifts/self-rings.
  g.debugLaunch(blindId, 0, 0);
}

void _driveSlingshotter(BumperBalls g, int skilledId, int frame) {
  if (frame % _skilledPeriod != 0) return;
  final aim = g.debugAimAtNearest(skilledId);
  final selfFrac = g.debugSelfEdgeFrac(skilledId) ?? 1.0;
  if (aim != null && selfFrac < _skilledSelfSafeFrac) {
    g.debugLaunch(skilledId, aim, 1.0);
  }
}

/// The DECISIVE head-to-head: a 2-player duel (both HUMAN-driven, no bots) so
/// the only variable is the play STYLE. The slingshotter can reliably target the
/// near-stationary spammer; the spammer's feeble dribbles drift off the shrinking
/// edge. Returns the finished game so the caller can compare KO scores / ranks.
BumperBalls _runDuel(int seed, {required int blindId, required int skilledId}) {
  final players = [
    for (var i = 0; i < 2; i++) PlayerSlot.defaults(i, isBot: false),
  ];
  final ctx = MiniGameContext(
    players: players,
    arena: const Size(800, 1200),
    rng: SeededRng(seed),
    zones: ZoneLayout.forPlayers(2),
  );
  final g = BumperBalls()..init(ctx);
  var n = 0;
  while (g.status != MiniGameStatus.finished && n++ < _maxFrames) {
    _driveSpammer(g, blindId);
    _driveSlingshotter(g, skilledId, n);
    g.update(1 / _fps);
  }
  return g;
}

/// The ROBUST corollary: a 4-player round where slots 0 and 1 are HUMAN-driven
/// (one spammer, one slingshotter) and slots 2..3 are bots. Proves spam cannot
/// take the round even in a chaotic mixed field. Returns the finished game.
BumperBalls _runMixed(int seed, {required int blindId, required int skilledId}) {
  final players = [
    for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: i >= 2),
  ];
  final ctx = MiniGameContext(
    players: players,
    arena: const Size(800, 1200),
    rng: SeededRng(seed),
    zones: ZoneLayout.forPlayers(4),
  );
  final g = BumperBalls()..init(ctx);
  var n = 0;
  while (g.status != MiniGameStatus.finished && n++ < _maxFrames) {
    _driveSpammer(g, blindId);
    _driveSlingshotter(g, skilledId, n);
    g.update(1 / _fps);
  }
  return g;
}

void main() {
  test('bumper balls finishes with all bots and ranks everyone', () {
    final g = _build(4, 7);
    _runToFinish(g);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('all-bot round does not end instantly but still terminates', () {
    // Several seeds so the pacing/bot-fairness guard is not luck of one RNG.
    for (final seed in const [1, 2, 3, 7, 11]) {
      final g = _build(4, seed);
      final frames = _runToFinish(g);
      final seconds = frames / _fps;

      // Lower floor: a strong launch must not eject an idle ball immediately —
      // there is a ~2s bot warmup, so the round always lasts a real beat.
      expect(
        seconds,
        greaterThan(_minRoundSec),
        reason: 'seed $seed ended in ${seconds.toStringAsFixed(2)}s (too fast)',
      );
      // Upper bound: it must converge within the loop budget (time limit + grace).
      expect(
        g.status,
        MiniGameStatus.finished,
        reason: 'seed $seed did not finish within $_maxFrames frames',
      );
      expect(frames, lessThan(_maxFrames), reason: 'seed $seed hit the cap');
    }
  });

  test('finishes for 1..3 players with a full ranking', () {
    for (final count in const [1, 2, 3]) {
      final g = _build(count, 11 + count);
      _runToFinish(g);
      expect(g.status, MiniGameStatus.finished, reason: '$count players');
      expect(g.winResult, isNotNull, reason: '$count players');
      expect(g.winResult!.ranking.toSet(), {
        for (var i = 0; i < count; i++) i,
      }, reason: '$count players');
    }
  });

  // ── PEG LAYOUT: deterministic, clear of spawns, drives bank shots ────────────

  test('pegs: a deterministic 2..4 set, identical per run, clear of spawns', () {
    for (final count in const [1, 2, 3, 4]) {
      final a = _build(count, 42);
      final b = _build(count, 99); // seed must NOT change the static layout
      // 2..4 pegs (count + 1, clamped). Always at least the centre bank anchor.
      expect(a.debugPegCount, inInclusiveRange(2, 4), reason: '$count players');
      expect(a.debugPegCount, greaterThanOrEqualTo(1), reason: '$count players');
      // Layout is fixed by arena size + count, so two builds match exactly.
      expect(
        b.debugPegPositions,
        equals(a.debugPegPositions),
        reason: '$count players: peg layout is not deterministic',
      );
      // No peg sits on top of a spawn point (a respawn would wedge into it).
      for (var i = 0; i < count; i++) {
        final spawn = a.debugSpawnOf(i)!;
        for (final peg in a.debugPegPositions) {
          expect(
            (peg - spawn).distance,
            greaterThan(40), // comfortably clear of any spawn ball
            reason: '$count players: a peg sits on player $i\'s spawn',
          );
        }
      }
    }
  });

  test('peg bank: a ball launched dead-on into a peg never passes through it '
      '(the local elastic carom deflects momentum)', () {
    // The bank-shot identity: a ball fired straight at a peg is deflected/
    // reversed by the local peg collision rather than tunneling through it. We
    // aim at the nearest peg to the ball and assert the ball never ends up on the
    // FAR side of that peg's centre along the launch axis.
    final g = _build(2, 5);
    g.update(1 / _fps); // step so the sim is running
    final ballPos = g.debugBallPos(0)!;
    // Pick the peg nearest the ball as the bank target.
    final pegs = g.debugPegPositions;
    var peg = pegs.first;
    var best = double.infinity;
    for (final p in pegs) {
      final d = (p - ballPos).distance;
      if (d < best) {
        best = d;
        peg = p;
      }
    }
    final toPeg = peg - ballPos;
    final aim = math.atan2(toPeg.dy, toPeg.dx);
    final launchDir = Offset(math.cos(aim), math.sin(aim));
    g.debugLaunch(0, aim, 1.0);
    // Track the ball's projection onto the launch axis, measured from the peg.
    // It should approach (negative→0) but never go clearly POSITIVE (past the
    // peg) — a clean bounce keeps it on the near side.
    var maxPastPeg = double.negativeInfinity;
    for (var i = 0; i < 40; i++) {
      g.update(1 / _fps);
      final pos = g.debugBallPos(0);
      if (pos == null) break; // ringed out on the carom-back — also fine
      final rel = pos - peg;
      final along = rel.dx * launchDir.dx + rel.dy * launchDir.dy;
      if (along > maxPastPeg) maxPastPeg = along;
    }
    // A small tolerance for the contact-resolution step; a tunneling ball would
    // shoot far past (hundreds of px) the peg centre.
    expect(
      maxPastPeg,
      lessThan(g.debugBodyRadius),
      reason: 'ball passed through the peg ($maxPastPeg px past centre) instead '
          'of banking off it',
    );
  });

  // ── SLINGSHOT: pull-back power map, taps go nowhere, no throw ─────────────────

  test('slingshot power map: a full pull travels far more than a tap', () {
    final g = _build(2, 5);
    g.update(1 / _fps);
    final startTap = g.debugBallPos(0)!;
    // A power-0 "tap" launch barely moves the ball (a feeble dud nudge).
    g.debugLaunch(0, 0, 0);
    for (var i = 0; i < 12; i++) {
      g.update(1 / _fps);
    }
    final tapTravel = (g.debugBallPos(0)! - startTap).distance;

    // A full-power slingshot launches the ball a long way.
    final g2 = _build(2, 5);
    g2.update(1 / _fps);
    final startPull = g2.debugBallPos(0)!;
    g2.debugLaunch(0, 0, 1.0); // strong pull, fire along +x
    for (var i = 0; i < 12; i++) {
      g2.update(1 / _fps);
    }
    final pullTravel = (g2.debugBallPos(0)! - startPull).distance;

    // The judged pull must travel far more than the tap — power is the pull.
    expect(
      pullTravel,
      greaterThan(tapTravel * 4),
      reason: 'a full pull ($pullTravel) was not far stronger than a tap '
          '($tapTravel) — the slingshot power map is broken',
    );
  });

  test(
    'tap, pull-back drag and full launch inputs never throw and resolve',
    () {
      final players = [
        for (var i = 0; i < 3; i++) PlayerSlot.defaults(i, isBot: i != 0),
      ];
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(800, 1200),
        rng: SeededRng(5),
        zones: ZoneLayout.forPlayers(3),
      );
      final g = BumperBalls()..init(ctx);
      var n = 0;
      while (g.status != MiniGameStatus.finished && n < _maxFrames) {
        // Tap (down+up same frame, in place) → a dud nudge, never throws.
        if (n % 30 == 0) {
          expect(
            () => g.onInput(PlayerInput.down(0, const Offset(0.5, 0.7))),
            returnsNormally,
          );
          expect(
            () => g.onInput(const PlayerInput(
              playerId: 0,
              phase: InputPhase.up,
              normPos: Offset(0.5, 0.7),
            )),
            returnsNormally,
          );
        }
        // Pull-back slingshot: press at the ball, drag the finger BACK, release.
        if (n % 47 == 0) {
          expect(
            () => g.onInput(PlayerInput.down(0, const Offset(0.5, 0.7))),
            returnsNormally,
          );
        }
        if (n % 47 == 6) {
          expect(
            () => g.onInput(const PlayerInput(
              playerId: 0,
              phase: InputPhase.holdTick,
              normPos: Offset(0.7, 0.9), // pull back/down → fire up/left
            )),
            returnsNormally,
          );
        }
        if (n % 47 == 12) {
          expect(
            () => g.onInput(const PlayerInput(
              playerId: 0,
              phase: InputPhase.up,
              normPos: Offset(0.7, 0.9),
            )),
            returnsNormally,
          );
        }
        g.update(1 / _fps);
        n++;
      }
      expect(g.status, MiniGameStatus.finished);
      expect(g.winResult!.ranking.toSet(), {0, 1, 2});
    },
  );

  test('ROCKET window: repeated full launches keep the round resolving across '
      'seeds (momentum-keep + peg banks must not stall or crash the sim)', () {
    // The rocket window counteracts ring-friction for ~1.1s and banks off pegs;
    // this guards that a human spamming full launches never softlocks the sim,
    // never throws, and still converges to a full ranking. Several seeds.
    for (final seed in const [2, 8, 14, 23]) {
      final players = [
        for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: i != 0),
      ];
      final ctx = MiniGameContext(
        players: players,
        arena: const Size(800, 1200),
        rng: SeededRng(seed),
        zones: ZoneLayout.forPlayers(4),
      );
      final g = BumperBalls()..init(ctx);
      var n = 0;
      while (g.status != MiniGameStatus.finished && n < _maxFrames) {
        if (n % 20 == 0) {
          final aim = g.debugAimAtNearest(0) ?? 0;
          g.debugLaunch(0, aim, 1.0);
        }
        g.update(1 / _fps);
        n++;
      }
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      expect(g.winResult, isNotNull, reason: 'seed $seed');
      expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3}, reason: 'seed $seed');
      expect(n, lessThan(_maxFrames), reason: 'seed $seed hit the cap');
    }
  });

  test('render does not throw before or after finish', () {
    final g = _build(4, 3);
    final rec = PictureRecorder();
    const size = Size(900, 1400);
    final canvas = Canvas(rec, Offset.zero & size);
    // Draw a few frames in so pegs / trails / launch auras are exercised.
    for (var i = 0; i < 120; i++) {
      g.update(1 / _fps);
    }
    expect(() => g.render(canvas, size), returnsNormally);
    _runToFinish(g);
    expect(() => g.render(canvas, size), returnsNormally);
  });

  test('render does not throw WHILE a human is mid-pull (slingshot telegraph)',
      () {
    // Exercise the slingshot band + dotted trajectory + power-gauge draw path.
    final players = [
      for (var i = 0; i < 2; i++) PlayerSlot.defaults(i, isBot: i != 0),
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(4),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = BumperBalls()..init(ctx);
    g.update(1 / _fps);
    // Press + drag back so the telegraph is live, but do NOT release.
    g.onInput(PlayerInput.down(0, const Offset(0.5, 0.7)));
    g.onInput(const PlayerInput(
      playerId: 0,
      phase: InputPhase.holdTick,
      normPos: Offset(0.75, 0.92),
    ));
    final rec = PictureRecorder();
    const size = Size(800, 1200);
    final canvas = Canvas(rec, Offset.zero & size);
    expect(() => g.render(canvas, size), returnsNormally);
  });

  // ── DESIGN LAW: button-spam must LOSE to a measured, aimed slingshot ─────────

  test('SPAM LOSES: in a head-to-head duel a blind every-frame tapper (power 0, '
      'no aim) loses EVERY trial to a measured slingshotter — fewer ring-outs '
      'and never first, across seeds and regardless of spawn slot', () {
    // The headline guarantee of the rework, proven in the cleanest setting: a
    // 2-player duel (both HUMAN-driven, no bots) so the ONLY variable is the
    // play STYLE.
    //   * blind  = power-0 launch every frame: a feeble dud that cannot eject
    //              (commit-gated), arms no rocket, and drifts/self-rings on the
    //              closing edge (a NEGATIVE score is expected).
    //   * skilled = aim at the rival + a full-power pull, paced, and never fired
    //              while hugging its own edge: real banked ring-outs.
    // For EVERY trial the slingshotter must STRICTLY out-score the spammer AND
    // the spammer must never finish first. Both slot orderings prove the win is
    // the BEHAVIOR (aim + judged pull + self-preservation), not the spawn slot.
    var skilledScoreTotal = 0.0;
    var blindScoreTotal = 0.0;
    for (final seed in const [1, 5, 7, 13, 21, 42, 99, 123, 256]) {
      for (final swap in const [false, true]) {
        final blindId = swap ? 1 : 0;
        final skilledId = swap ? 0 : 1;
        final g = _runDuel(seed, blindId: blindId, skilledId: skilledId);
        expect(g.status, MiniGameStatus.finished);

        final scores = g.winResult!.finalScores;
        final blindScore = (scores[blindId] ?? 0).toDouble();
        final skilledScore = (scores[skilledId] ?? 0).toDouble();

        // Per trial the LAW: the measured slingshotter STRICTLY out-banks spam.
        expect(
          skilledScore,
          greaterThan(blindScore),
          reason: 'seed $seed swap=$swap: spammer ($blindScore) was not beaten '
              'by the slingshotter ($skilledScore)',
        );
        // …and the spammer never takes the round.
        expect(
          g.winResult!.ranking.first,
          isNot(blindId),
          reason: 'seed $seed swap=$swap: a blind tapper WON the duel',
        );

        skilledScoreTotal += skilledScore;
        blindScoreTotal += blindScore;
      }
    }
    // And the aggregate margin is decisive, not a hair.
    expect(
      skilledScoreTotal,
      greaterThan(blindScoreTotal),
      reason: 'slingshotter total ($skilledScoreTotal) did not beat the spammer '
          'total ($blindScoreTotal)',
    );
  });

  test('SPAM NEVER WINS: a blind tapper never finishes 1st in a mixed 4-player '
      'round (against a slingshotter + bots), across seeds and spawn slots', () {
    // The robust corollary: whatever the seed, in a chaotic 4-ball field
    // button-mashing cannot take the round. A blind tapper (power 0, no aim,
    // commit-gated knockback) must never end up [ranking.first]. A flake-proof
    // claim — the guarantee that matters for the table: skill, not flailing.
    for (final seed in const [1, 7, 13, 21, 99, 123, 256]) {
      for (final swap in const [false, true]) {
        final blindId = swap ? 1 : 0;
        final skilledId = swap ? 0 : 1;
        final g = _runMixed(seed, blindId: blindId, skilledId: skilledId);
        expect(
          g.winResult!.ranking.first,
          isNot(blindId),
          reason: 'seed $seed swap=$swap: a blind tapper WON the round',
        );
      }
    }
  });

  test('SPAM SELF-DESTRUCTS: in the duel a blind tapper ends with a NEGATIVE '
      'score (it banks no KOs and self-rings on the shrinking edge)', () {
    // Direct evidence the spam path is feeble: a power-0 every-frame tapper
    // cannot bank ring-outs, so its score is non-positive every trial and the
    // aggregate is firmly underwater (self-ring penalties dominate).
    var total = 0.0;
    for (final seed in const [1, 5, 7, 13, 21, 42, 99, 123, 256]) {
      for (final swap in const [false, true]) {
        final blindId = swap ? 1 : 0;
        final skilledId = swap ? 0 : 1;
        final g = _runDuel(seed, blindId: blindId, skilledId: skilledId);
        final blindScore = (g.winResult!.finalScores[blindId] ?? 0).toDouble();
        // Per trial: a blind tapper never finishes with a POSITIVE KO score.
        expect(
          blindScore,
          lessThanOrEqualTo(0),
          reason: 'seed $seed swap=$swap: a blind tapper scored $blindScore (>0)',
        );
        total += blindScore;
      }
    }
    expect(
      total,
      lessThan(0),
      reason: 'blind tapper aggregate score ($total) was not negative',
    );
  });

  group('StarController (chaos pickup)', () {
    StarController make() => StarController(
      radius: 14,
      firstSpawnSec: 2.0,
      respawnSec: 5.0,
      lifeSec: 4.0,
      appearPerSec: 3.0,
      spinPerSec: 3.0,
      spawnSpreadFactor: 0.4,
    );

    test('never spawns with a single ball alive', () {
      final c = make();
      final rng = SeededRng(1);
      for (var i = 0; i < 60 * 5; i++) {
        c.tick(1 / 60, 1, rng, const Offset(400, 600), 300);
      }
      expect(c.star, isNull);
    });

    test('spawns inside the platform after the delay with >= 2 alive', () {
      final c = make();
      final rng = SeededRng(2);
      for (var i = 0; i < 60 * 3; i++) {
        c.tick(1 / 60, 2, rng, const Offset(400, 600), 300);
      }
      final star = c.star;
      expect(star, isNotNull);
      expect(star!.ready, isTrue);
      expect(
        (star.pos - const Offset(400, 600)).distance,
        lessThanOrEqualTo(300 * 0.4 + 1),
      );
    });

    test('consume clears the live star', () {
      final c = make();
      final rng = SeededRng(3);
      for (var i = 0; i < 60 * 3; i++) {
        c.tick(1 / 60, 2, rng, const Offset(400, 600), 300);
      }
      expect(c.star, isNotNull);
      c.consume();
      expect(c.star, isNull);
    });
  });

  group('Peg (static bumper)', () {
    test('hit() stamps the flash to full and tick() relaxes it', () {
      final peg = Peg(pos: const Offset(100, 100), radius: 20);
      expect(peg.flash, 0);
      peg.hit();
      expect(peg.flash, 1.0);
      peg.tick(0.1, 3.0); // 0.3 of the flash relaxed
      expect(peg.flash, closeTo(0.7, 1e-9));
      peg.tick(10, 3.0); // far past zero
      expect(peg.flash, 0);
    });
  });
}
