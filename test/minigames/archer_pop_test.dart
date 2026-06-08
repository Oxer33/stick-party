import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/archer_pop/archer_pop.dart';

void main() {
  MiniGameContext ctxFor(int n, {int seed = 7}) {
    final players = [for (var i = 0; i < n; i++) PlayerSlot.defaults(i, isBot: true)];
    return MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(seed),
      zones: ZoneLayout.forPlayers(n),
    );
  }

  test('archer pop finishes with four bots and ranks all players', () {
    final g = ArcherPop()..init(ctxFor(4));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  for (final count in [1, 2, 3]) {
    test('archer pop finishes with $count player(s)', () {
      final g = ArcherPop()..init(ctxFor(count, seed: 21 + count));
      var n = 0;
      while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(g.status, MiniGameStatus.finished);
      expect(g.winResult!.ranking.toSet(),
          {for (var i = 0; i < count; i++) i});
    });
  }

  test('archer pop ends by time limit (~30s)', () {
    final g = ArcherPop()..init(ctxFor(2, seed: 5));
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      g.update(1 / 60);
    }
    // 30s limit at 60fps ~= 1800 frames; allow slack for hit-stop scaling.
    expect(n, lessThan(60 * 60));
    expect(g.status, MiniGameStatus.finished);
  });

  test('PACING: all-bot 4p round lasts > 1.5s and finishes within the limit',
      () {
    // The frenzy climax (faster, denser, more golden) must neither end the round
    // early nor stop it converging: across seeds it runs a real beat (> 1.5s)
    // yet always resolves by the 30s limit (~1800 frames; allow hit-stop slack).
    for (final seed in const [1, 7, 13, 21, 99]) {
      final g = ArcherPop()..init(ctxFor(4, seed: seed));
      var frames = 0;
      while (g.status != MiniGameStatus.finished && frames++ < 60 * 80) {
        g.update(1 / 60);
      }
      expect(frames, greaterThan(90),
          reason: 'seed $seed ended too fast (${frames / 60}s)');
      expect(g.status, MiniGameStatus.finished, reason: 'seed $seed');
      expect(frames, lessThan(60 * 60),
          reason: 'seed $seed overran (${frames / 60}s)');
    }
  });

  test('frenzy banner renders without throwing in the final stretch', () {
    // Advance into the frenzy window (final ~30% of the 30s limit), then render.
    final g = ArcherPop()..init(ctxFor(3, seed: 4));
    for (var i = 0; i < 60 * 24 && g.status != MiniGameStatus.finished; i++) {
      g.update(1 / 60);
    }
    final rec = ui.PictureRecorder();
    const size = Size(900, 1400);
    final canvas = ui.Canvas(rec, Offset.zero & size);
    expect(() => g.render(canvas, size), returnsNormally);
  });
}
