import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/input_zones.dart';
import 'package:stick_party/minigames/tank_duel/tank_duel.dart';
import 'package:stick_party/minigames/tank_duel/tank_fx.dart';

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

  test('a hold (down, wait, release) slows aim then fires; round resolves', () {
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
      if (n % 40 == 0) {
        expect(() => g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.down)),
            returnsNormally);
      }
      if (n % 40 == 12) {
        expect(() => g.onInput(const PlayerInput(playerId: 0, phase: InputPhase.up)),
            returnsNormally);
      }
      g.update(1 / 60);
    }
    expect(g.status, MiniGameStatus.finished);
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
}
