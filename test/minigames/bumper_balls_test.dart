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
