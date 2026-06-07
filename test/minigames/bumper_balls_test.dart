import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/bumper_balls/bumper_balls.dart';

/// Frames-per-second the headless sim is stepped at.
const int _fps = 60;

/// Hard floor: an all-bot round must never end this fast (guards against an
/// instant-end regression where a single dash ejects an idle ball at once).
const double _minRoundSec = 1.5;

/// Generous upper bound for the headless loop (well past the in-game limit).
const int _maxFrames = 60 * 80;

BumperBalls _build(int count, int seed) {
  final players = [
    for (var i = 0; i < count; i++) PlayerSlot.defaults(i, isBot: true)
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
      expect(
        g.winResult!.ranking.toSet(),
        {for (var i = 0; i < count; i++) i},
        reason: '$count players',
      );
    }
  });

  test('tap and hold/release inputs never throw and the round resolves', () {
    final players = [
      for (var i = 0; i < 3; i++) PlayerSlot.defaults(i, isBot: i != 0)
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
      // Quick tap (down+up same frame) and a held charge (down, wait, up).
      if (n % 30 == 0) {
        expect(() => g.onInput(PlayerInput.down(0)), returnsNormally);
        expect(
          () => g.onInput(
              const PlayerInput(playerId: 0, phase: InputPhase.up)),
          returnsNormally,
        );
      }
      if (n % 47 == 0) {
        expect(() => g.onInput(PlayerInput.down(0)), returnsNormally);
      }
      if (n % 47 == 9) {
        expect(
          () => g.onInput(
              const PlayerInput(playerId: 0, phase: InputPhase.up)),
          returnsNormally,
        );
      }
      g.update(1 / _fps);
      n++;
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2});
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
}
