import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/sumo_smash/sumo_smash.dart';

SumoSmash _run(int count, int seed) {
  final players = [
    for (var i = 0; i < count; i++) PlayerSlot.defaults(i, isBot: true)
  ];
  final ctx = MiniGameContext(
    players: players,
    arena: const Size(800, 1200),
    rng: SeededRng(seed),
    zones: ZoneLayout.forPlayers(count),
  );
  final g = SumoSmash()..init(ctx);
  var n = 0;
  while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
    g.update(1 / 60);
  }
  return g;
}

void main() {
  test('sumo finishes with all bots', () {
    final g = _run(4, 7);
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult, isNotNull);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2, 3});
  });

  test('sumo finishes for 1..3 players with a full ranking', () {
    for (final count in const [1, 2, 3]) {
      final g = _run(count, 11 + count);
      expect(g.status, MiniGameStatus.finished, reason: '$count players');
      expect(g.winResult, isNotNull, reason: '$count players');
      expect(
        g.winResult!.ranking.toSet(),
        {for (var i = 0; i < count; i++) i},
        reason: '$count players',
      );
    }
  });

  test('a tap does not throw and the round still resolves', () {
    final players = [for (var i = 0; i < 3; i++) PlayerSlot.defaults(i, isBot: i != 0)];
    final ctx = MiniGameContext(
      players: players,
      arena: const Size(800, 1200),
      rng: SeededRng(5),
      zones: ZoneLayout.forPlayers(3),
    );
    final g = SumoSmash()..init(ctx);
    var n = 0;
    while (g.status != MiniGameStatus.finished && n++ < 60 * 80) {
      if (n % 20 == 0) {
        expect(() => g.onInput(PlayerInput.down(0)), returnsNormally);
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
    expect(g.winResult!.ranking.toSet(), {0, 1, 2});
  });

  test('render does not throw before or after finish', () {
    final g = SumoSmash()
      ..init(MiniGameContext(
        players: [for (var i = 0; i < 4; i++) PlayerSlot.defaults(i, isBot: true)],
        arena: const Size(900, 1400),
        rng: SeededRng(3),
        zones: ZoneLayout.forPlayers(4),
      ));
    final rec = PictureRecorder();
    const size = Size(900, 1400);
    final canvas = Canvas(rec, Offset.zero & size);
    expect(() => g.render(canvas, size), returnsNormally);
    for (var i = 0; i < 60 * 80 && g.status != MiniGameStatus.finished; i++) {
      g.update(1 / 60);
    }
    expect(() => g.render(canvas, size), returnsNormally);
  });
}
