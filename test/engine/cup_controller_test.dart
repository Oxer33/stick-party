import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/engine/cup_controller.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';

WinResult result(List<int> ranking, Map<int, num> scores) =>
    WinResult(ranking: ranking, finalScores: scores);

void main() {
  group('construction', () {
    test('positions at index 0 with an empty board by default', () {
      final c = CupController(gameIds: const ['a', 'b', 'c']);
      expect(c.index, 0);
      expect(c.total, 3);
      expect(c.currentGameId, 'a');
      expect(c.isComplete, isFalse);
      expect(c.champion, isNull);
    });

    test('gameIds list is unmodifiable', () {
      final c = CupController(gameIds: const ['a', 'b']);
      expect(() => c.gameIds.add('x'), throwsUnsupportedError);
    });

    test('throws on empty gameIds', () {
      expect(() => CupController(gameIds: const []), throwsArgumentError);
    });

    test('throws on negative or out-of-range index', () {
      expect(
        () => CupController(gameIds: const ['a'], index: -1),
        throwsArgumentError,
      );
      expect(
        () => CupController(gameIds: const ['a', 'b'], index: 3),
        throwsArgumentError,
      );
    });

    test('index == length is allowed (a completed cup)', () {
      final c = CupController(gameIds: const ['a', 'b'], index: 2);
      expect(c.isComplete, isTrue);
      expect(c.currentGameId, isNull);
    });
  });

  group('recordResult advances and accumulates', () {
    test('returns a NEW controller with index advanced and board updated', () {
      final c0 = CupController(gameIds: const ['a', 'b']);
      final r = result([0, 1], {0: 10, 1: 5});

      // Act
      final c1 = c0.recordResult(r, mode: GameMode.ffa);

      // Assert: original untouched (immutability).
      expect(identical(c0, c1), isFalse);
      expect(c0.index, 0);
      expect(c0.board.pointsOf(0), 0);
      // New controller advanced and scored.
      expect(c1.index, 1);
      expect(c1.currentGameId, 'b');
      expect(c1.board.pointsOf(0), 2); // winner of a 2-player round
      expect(c1.board.pointsOf(1), 1);
    });

    test('records through to completion and exposes the champion', () {
      var c = CupController(gameIds: const ['a', 'b']);
      c = c.recordResult(result([0, 1], {0: 9, 1: 1}), mode: GameMode.ffa);
      expect(c.isComplete, isFalse);
      c = c.recordResult(result([0, 1], {0: 9, 1: 1}), mode: GameMode.ffa);
      expect(c.isComplete, isTrue);
      expect(c.currentGameId, isNull);
      // Player 0 won both rounds -> champion.
      expect(c.champion, 0);
    });

    test('throws StateError when recording past completion', () {
      var c = CupController(gameIds: const ['only']);
      c = c.recordResult(result([0], {0: 1}), mode: GameMode.ffa);
      expect(c.isComplete, isTrue);
      expect(
        () => c.recordResult(result([0], {0: 1}), mode: GameMode.ffa),
        throwsStateError,
      );
    });
  });

  group('champion', () {
    test('is null until the cup is complete', () {
      final c = CupController(gameIds: const ['a', 'b'])
          .recordResult(result([1, 0], {1: 9, 0: 1}), mode: GameMode.ffa);
      expect(c.isComplete, isFalse);
      expect(c.champion, isNull);
    });
  });

  group('CupController.random', () {
    final pool = ['g0', 'g1', 'g2', 'g3', 'g4', 'g5'];

    test('picks N distinct ids drawn from the pool', () {
      final c = CupController.random(pool, 4, SeededRng(42));
      expect(c.gameIds.length, 4);
      expect(c.gameIds.toSet().length, 4, reason: 'ids must be distinct');
      for (final id in c.gameIds) {
        expect(pool.contains(id), isTrue);
      }
    });

    test('is deterministic for a fixed seed', () {
      final a = CupController.random(pool, 5, SeededRng(7));
      final b = CupController.random(pool, 5, SeededRng(7));
      expect(a.gameIds, b.gameIds);
    });

    test('clamps count down to the pool size', () {
      final c = CupController.random(pool, 99, SeededRng(1));
      expect(c.gameIds.length, pool.length);
      expect(c.gameIds.toSet().length, pool.length);
    });

    test('throws on an empty pool', () {
      expect(
        () => CupController.random(const [], 3, SeededRng(1)),
        throwsArgumentError,
      );
    });

    test('throws when count < 1', () {
      expect(
        () => CupController.random(pool, 0, SeededRng(1)),
        throwsArgumentError,
      );
    });
  });
}
