import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/minigames/tap_sprint/tap_sprint.dart';

void main() {
  test('tap sprint finishes with full ranking (4 bots)', () {
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
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
    expect(g.winResult!.winner, isNotNull);

    // Sim-length floor + ceiling: the all-bot race must outlast the bot warmup
    // (no instant finish) and still resolve inside the hard time limit (~30s).
    final simSeconds = n / 60.0;
    expect(simSeconds, greaterThan(1.5));
    expect(simSeconds, lessThanOrEqualTo(31.0));
  });

  test('rubber-band comeback: a trailing runner closes the gap on a leader '
      'tapping at the same rate', () {
    final players = [
      PlayerSlot.defaults(0), // leader (human)
      PlayerSlot.defaults(1), // trailing (human)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(7),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = TapSprint()..init(ctx);

    // Give runner 0 a head start, then both tap once per frame at the SAME rate.
    for (var i = 0; i < 40; i++) {
      g.onInput(PlayerInput.down(0));
    }
    g.update(1 / 60);
    final gapStart = g.scores.of(0) - g.scores.of(1);
    expect(gapStart, greaterThan(0));

    // Race a stretch with both tapping equally; without catch-up the gap would
    // hold flat, so a shrinking gap proves the rubber-band only helps the one
    // behind. Stop before anyone finishes so we compare mid-race progress.
    for (var i = 0; i < 200 && g.status != MiniGameStatus.finished; i++) {
      g.onInput(PlayerInput.down(0));
      g.onInput(PlayerInput.down(1));
      g.update(1 / 60);
    }
    final gapNow = g.scores.of(0) - g.scores.of(1);
    expect(gapNow, lessThan(gapStart),
        reason: 'the trailing runner must gain on an equal-rate leader');
    // But subtle: it must not have overtaken purely from the assist.
    expect(gapNow, greaterThanOrEqualTo(0));
  });

  test('tap sprint solo player finishes', () {
    final ctx = MiniGameContext(
      players: [PlayerSlot.defaults(0, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(3),
      zones: ZoneLayout.forPlayers(1),
    );
    final g = TapSprint()..init(ctx);

    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }

    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking, [0]);
  });

  test('tap sprint render does not throw mid-round', () {
    final ctx = MiniGameContext(
      players: [for (var i = 0; i < 3; i++) PlayerSlot.defaults(i, isBot: true)],
      arena: const Size(800, 1200),
      rng: SeededRng(11),
      zones: ZoneLayout.forPlayers(3),
    );
    final g = TapSprint()..init(ctx);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    g.update(1 / 60);
    expect(() => g.render(canvas, const Size(800, 1200)), returnsNormally);
  });
}
