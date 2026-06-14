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
/// instant-end regression where a single dash ejects an idle ball at once).
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

/// Run one 4-player round where slots 0 and 1 are HUMAN-driven and slots 2..3
/// are bots, scripting two contrasting play styles for the two humans:
///
///  * [blindId] (the SPAMMER): fires an instant down→up every frame with NO
///    hold and NO drag — the worst-case button-masher. With the commit gate this
///    means charge≈0: no nearest-aim assist (it is EARNED by holding), a stale
///    aim that whiffs, the charge-root that traps it, and commit-gated knockback
///    that cannot eject — so it self-rings on the closing edge instead.
///  * [skilledId] (the COMMITTER): presses, HOLDS to full charge, then releases —
///    every cycle. The hold unlocks the kid-safe nearest-rival aim AND a fully
///    committed dash (and the momentum-keep rocket), so it lands real ring-outs.
///
/// Returns the finished game so the caller can compare KO scores / ranks.
BumperBalls _runSpamVsSkill(
  int seed, {
  required int blindId,
  required int skilledId,
}) {
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
  // The committer's cycle: press (down), let the charge fill over ~0.75s of
  // [update] ticks (charge accrues while held — no positional holdTick is sent,
  // so NO drag registers and the kid-safe nearest-rival aim is the EARNED
  // fallback), then release (up). A brief gap, then repeat. Sending no drag is
  // deliberate: a holdTick would carry a normPos that reads as a thumb-drag to a
  // fixed screen point, which is NOT the auto-aim path we want to exercise.
  const holdFrames = 45; // ~0.75s of charge accrual (full charge is ~0.6s)
  const gapFrames = 16; // clear the ~0.24s dash cooldown before the next press
  const cycle = holdFrames + gapFrames;
  var n = 0;
  while (g.status != MiniGameStatus.finished && n++ < _maxFrames) {
    // SPAMMER: instant down then up, same frame, every frame, no aim, no hold.
    g.onInput(PlayerInput.down(blindId));
    g.onInput(PlayerInput(playerId: blindId, phase: InputPhase.up));
    // COMMITTER: down → (charge fills during update) → up. No drag.
    final phase = n % cycle;
    if (phase == 0) {
      g.onInput(PlayerInput.down(skilledId));
    } else if (phase == holdFrames) {
      g.onInput(PlayerInput(playerId: skilledId, phase: InputPhase.up));
    }
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

      // Lower floor: a charged shove must not eject an idle ball immediately —
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

  test(
    'tap, drag and charged-rocket inputs never throw and the round resolves',
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
        // No-drag tap (down+up same frame) → fires at nearest, never throws.
        if (n % 30 == 0) {
          expect(() => g.onInput(PlayerInput.down(0)), returnsNormally);
          expect(
            () =>
                g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up)),
            returnsNormally,
          );
        }
        // Drag-charge rocket: press, drag the thumb across, release after a long
        // hold so the charge passes the rocket threshold.
        if (n % 47 == 0) {
          expect(
            () => g.onInput(PlayerInput.down(0, const Offset(0.5, 0.7))),
            returnsNormally,
          );
        }
        if (n % 47 == 6) {
          expect(
            () => g.onInput(
              const PlayerInput(
                playerId: 0,
                phase: InputPhase.holdTick,
                normPos: Offset(0.1, 0.6),
              ),
            ),
            returnsNormally,
          );
        }
        if (n % 47 == 40) {
          expect(
            () => g.onInput(
              const PlayerInput(
                playerId: 0,
                phase: InputPhase.up,
                normPos: Offset(0.1, 0.6),
              ),
            ),
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

  test('ROCKET DASH: a charged drag keeps a round resolving and ranks everyone '
      'across seeds (momentum-keep must not stall or crash the sim)', () {
    // The rocket-dash counteracts ring-friction for ~1s; this guards that a
    // human spamming charged drags (arming rockets repeatedly) never softlocks
    // the sim, never throws, and still converges to a full ranking. Several
    // seeds so it is not luck of one RNG.
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
        final phase = n % 24;
        if (phase == 0) {
          g.onInput(PlayerInput.down(0, const Offset(0.25, 0.7)));
        } else if (phase < 18) {
          // Drag toward the opposite corner → a definite aim past the deadzone.
          g.onInput(
            const PlayerInput(
              playerId: 0,
              phase: InputPhase.holdTick,
              normPos: Offset(0.85, 0.85),
            ),
          );
        } else if (phase == 18) {
          g.onInput(
            const PlayerInput(
              playerId: 0,
              phase: InputPhase.up,
              normPos: Offset(0.85, 0.85),
            ),
          );
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
    // Draw a few frames in so aim arrows / trails / charge are exercised.
    for (var i = 0; i < 120; i++) {
      g.update(1 / _fps);
    }
    expect(() => g.render(canvas, size), returnsNormally);
    _runToFinish(g);
    expect(() => g.render(canvas, size), returnsNormally);
  });

  // ── DESIGN LAW: button-spam must LOSE to skilled, committed, aimed play ──────

  test('SPAM LOSES: a blind every-frame dasher (no aim, no hold) finishes BELOW '
      'a committer who holds to charge an aimed dash — fewer KOs and never wins, '
      'across seeds and regardless of spawn slot', () {
    // The headline guarantee of the rework. Both styles are HUMAN-driven in the
    // same deterministic round against identical bots (slots 2..3), so the only
    // difference is HOW each plays:
    //   * blind  = down→up every frame: charge≈0 → no earned nearest-aim, a
    //              stale whiffing aim, the charge-root that traps it, and
    //              commit-gated knockback that can't eject. It cannot bank
    //              ring-outs; it self-rings on the closing edge instead (a
    //              NEGATIVE score is allowed and expected).
    //   * skilled = down, hold to full charge, release: unlocks the kid-safe
    //              nearest-rival aim AND a fully committed dash → real KOs.
    // For EVERY trial the spammer can NEVER take first; ACROSS seeds the
    // committer must STRICTLY bank more total ring-outs AND out-score the spammer
    // in the clear majority of trials. We run both slot orderings so the win is
    // the BEHAVIOR (commit + aim), not a favourable spawn position.
    var skilledScoreTotal = 0.0;
    var blindScoreTotal = 0.0;
    var skilledStrictWins = 0;
    var trials = 0;
    for (final seed in const [1, 7, 13, 21, 99]) {
      for (final swap in const [false, true]) {
        final blindId = swap ? 1 : 0;
        final skilledId = swap ? 0 : 1;
        final g = _runSpamVsSkill(seed, blindId: blindId, skilledId: skilledId);
        expect(g.status, MiniGameStatus.finished);

        final scores = g.winResult!.finalScores;
        final blindScore = (scores[blindId] ?? 0).toDouble();
        final skilledScore = (scores[skilledId] ?? 0).toDouble();

        // Per trial the LAW: a blind every-frame dasher can NEVER take first.
        // (In a chaotic respawn brawl a bot can occasionally edge the committer
        // at a single seed — both behind bots — so we do NOT force a strict
        // per-seed committer>=spammer rank; we prove the spammer never wins here
        // and that the committer STRICTLY DOMINATES in aggregate below.)
        expect(
          g.winResult!.ranking.indexOf(blindId),
          greaterThan(0),
          reason: 'seed $seed swap=$swap: a blind every-frame dasher WON',
        );

        skilledScoreTotal += skilledScore;
        blindScoreTotal += blindScore;
        if (skilledScore > blindScore) skilledStrictWins++;
        trials++;
      }
    }
    // ACROSS seeds the committer must STRICTLY dominate: more total ring-outs…
    expect(
      skilledScoreTotal,
      greaterThan(blindScoreTotal),
      reason: 'committer total ($skilledScoreTotal) did not beat the spammer '
          'total ($blindScoreTotal) — button-spam is competitive!',
    );
    // …and out-score the spammer outright in the clear majority of trials.
    expect(
      skilledStrictWins * 2,
      greaterThan(trials),
      reason: 'committer out-scored the spammer in only $skilledStrictWins of '
          '$trials trials',
    );
  });

  test('SPAM NEVER WINS: a blind dasher never finishes 1st in a mixed round '
      '(against a committer + bots), across seeds and spawn slots', () {
    // The robust corollary of the design law: whatever the seed, button-mashing
    // cannot take the round. A blind dasher (charge≈0, no aim, commit-gated
    // knockback) must never end up [ranking.first]. This is deliberately a
    // weaker, flake-proof claim than an exact score bound (a stray floored bump
    // could nudge a rim-teetering bot once) — but it is the guarantee that
    // matters for the table: skill, not flailing, wins.
    for (final seed in const [1, 7, 13, 21, 99, 123, 256]) {
      for (final swap in const [false, true]) {
        final blindId = swap ? 1 : 0;
        final skilledId = swap ? 0 : 1;
        final g = _runSpamVsSkill(seed, blindId: blindId, skilledId: skilledId);
        expect(
          g.winResult!.ranking.first,
          isNot(blindId),
          reason: 'seed $seed swap=$swap: a blind dasher WON the round',
        );
      }
    }
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
}
