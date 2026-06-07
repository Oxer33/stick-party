import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/one_touch_soccer/one_touch_soccer.dart';

/// Builds an all-bot 4-player soccer round and advances it at a fixed 60 fps
/// step until it finishes (or a hard cap is hit), returning the elapsed seconds.
double _runToFinish(OneTouchSoccer g, {int maxFrames = 60 * 80}) {
  const step = 1 / 60;
  var frames = 0;
  while (g.status != MiniGameStatus.finished && frames < maxFrames) {
    g.update(step);
    frames++;
  }
  return frames * step;
}

OneTouchSoccer _buildAllBots(int seed) {
  final players = [for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)];
  final ctx = MiniGameContext(
    players: players,
    arena: const Size(800, 1200),
    rng: SeededRng(seed),
    zones: ZoneLayout.forPlayers(4),
  );
  return OneTouchSoccer()..init(ctx);
}

void main() {
  test('one touch soccer finishes with all bots', () {
    final g = _buildAllBots(7);
    _runToFinish(g);

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('an all-bot round lasts past the bot warmup and finishes within limit',
      () {
    // PACING guard: with bots warming up + a dead-center kickoff the ball is
    // never instantly scored, so the round must run a real contest (well past
    // 1.5 s) yet still resolve inside the time limit (45 s budget at 60 fps).
    for (final seed in [1, 7, 13, 21, 99]) {
      final g = _buildAllBots(seed);
      final elapsed = _runToFinish(g, maxFrames: 60 * 50);

      expect(g.status, MiniGameStatus.finished,
          reason: 'seed $seed should resolve within the time limit');
      expect(elapsed, greaterThan(1.5),
          reason: 'seed $seed ended too fast (no real match)');
      expect(elapsed, lessThanOrEqualTo(45.0),
          reason: 'seed $seed overran the match budget');
    }
  });

  test('a held-then-released input is accepted as directed control', () {
    // AGENCY guard: a single human striker sweeps its aim, holds to charge and
    // releases — a player-directed action, never auto-targeting the ball. A lone
    // player cannot end the round on their own before the timer, so the game
    // must still be running and must accept the directed input without error.
    final ctx = MiniGameContext(
      players: const [PlayerSlot(id: 0, name: 'P1', colorArgb: 0xFFFFFFFF)],
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = OneTouchSoccer()..init(ctx);

    g.update(1 / 60); // a beat before acting
    g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.down));
    for (var i = 0; i < 40; i++) {
      g.onInput(
          const PlayerInput(playerId: 0, phase: InputPhase.holdTick, dt: 1 / 60));
      g.update(1 / 60);
    }
    g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up));
    g.update(1 / 60);

    expect(g.status, MiniGameStatus.running);
  });
}
