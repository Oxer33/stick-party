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
      'tapping at the same IN-WINDOW cadence', () {
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

    // RHYTHM-OR-STUMBLE: only taps spaced inside the cadence window earn ground,
    // so we tap every 9 frames (9/60 = 0.15s, squarely inside 0.07..0.22) for
    // BOTH runners. Tapping once per frame (~0.0167s) would just stumble.
    const cadenceFrames = 9;

    // Helper: tap [ids] on the beat, advancing the sim a cadence's worth of
    // frames per beat so `sinceTap` lands in-window each time.
    void tapOnBeat(List<int> ids, int beats) {
      for (var b = 0; b < beats && g.status != MiniGameStatus.finished; b++) {
        for (final id in ids) {
          g.onInput(PlayerInput.down(id));
        }
        for (var f = 0; f < cadenceFrames; f++) {
          g.update(1 / 60);
        }
      }
    }

    // Give runner 0 a clean head start with several on-beat strides.
    tapOnBeat([0], 10);
    final gapStart = g.scores.of(0) - g.scores.of(1);
    expect(gapStart, greaterThan(0));

    // Now both tap on the SAME in-window cadence. Without catch-up the gap would
    // hold flat, so a shrinking gap proves the rubber-band only helps the one
    // behind. Stop before anyone finishes so we compare mid-race progress.
    tapOnBeat([0, 1], 30);
    final gapNow = g.scores.of(0) - g.scores.of(1);
    expect(gapNow, lessThan(gapStart),
        reason: 'the trailing runner must gain on an equal-rate leader');
    // But subtle: it must not have overtaken purely from the assist.
    expect(gapNow, greaterThanOrEqualTo(0));
  });

  test('rhythm beats blind mash: an on-beat runner outruns a frame-spammer', () {
    // The core of RHYTHM-OR-STUMBLE: tapping every frame (~0.0167s, far below
    // the 0.07 window floor) stumbles and gains almost nothing, while a steady
    // in-window cadence covers real ground. The rhythm runner must lead clearly.
    final players = [
      PlayerSlot.defaults(0), // rhythm (on-beat)
      PlayerSlot.defaults(1), // spammer (every frame)
    ];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(2),
    );
    final g = TapSprint()..init(ctx);

    const cadenceFrames = 9; // 0.15s — inside the window
    var frame = 0;
    for (var i = 0; i < 240 && g.status != MiniGameStatus.finished; i++) {
      g.onInput(PlayerInput.down(1)); // spammer taps EVERY frame → stumbles
      if (frame % cadenceFrames == 0) {
        g.onInput(PlayerInput.down(0)); // rhythm runner taps on the beat
      }
      g.update(1 / 60);
      frame++;
    }

    expect(g.scores.of(0), greaterThan(g.scores.of(1)),
        reason: 'steady rhythm must beat blind mashing');
    // The spammer should be badly stalled (mostly stumbling, ~no ground).
    expect(g.scores.of(1), lessThan(g.scores.of(0) * 0.6),
        reason: 'the frame-spammer should be left well behind');
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
