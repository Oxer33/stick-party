import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/engine/mini_game.dart';
import 'package:stick_party/engine/player_manager.dart';
import 'package:stick_party/engine/scoreboard.dart';

WinResult result(List<int> ranking, Map<int, num> scores) =>
    WinResult(ranking: ranking, finalScores: scores);

void main() {
  group('placement points (no ties)', () {
    test('4-player round: best earns 4 down to last earns 1', () {
      // Arrange: distinct scores so ranking is unambiguous.
      final r = result([0, 1, 2, 3], {0: 40, 1: 30, 2: 20, 3: 10});
      // Act
      final board = Scoreboard().addResult(r, mode: GameMode.ffa);
      // Assert
      expect(board.pointsOf(0), 4);
      expect(board.pointsOf(1), 3);
      expect(board.pointsOf(2), 2);
      expect(board.pointsOf(3), 1);
    });

    test('2-player round: winner 2, loser 1', () {
      final r = result([0, 1], {0: 5, 1: 2});
      final board = Scoreboard().addResult(r, mode: GameMode.ffa);
      expect(board.pointsOf(0), 2);
      expect(board.pointsOf(1), 1);
    });

    test('points are derived from finalScores, not the supplied order', () {
      // ranking order is wrong on purpose; scores say player 3 is best.
      final r = result([0, 1, 2, 3], {0: 1, 1: 2, 2: 3, 3: 4});
      final board = Scoreboard().addResult(r, mode: GameMode.ffa);
      expect(board.pointsOf(3), 4); // highest score => most points
      expect(board.pointsOf(0), 1); // lowest score => least points
    });
  });

  group('ties share the higher placement', () {
    test('two tie for first in a 4-player round', () {
      // Players 0 and 1 tie for the top score.
      final r = result([0, 1, 2, 3], {0: 50, 1: 50, 2: 20, 3: 10});
      final board = Scoreboard().addResult(r, mode: GameMode.ffa);
      // Both share the highest placement (4 points each).
      expect(board.pointsOf(0), 4);
      expect(board.pointsOf(1), 4);
      // Next distinct player gets the 3rd slot's points (4 - 2 = 2).
      expect(board.pointsOf(2), 2);
      expect(board.pointsOf(3), 1);
    });

    test('all four tie -> everyone gets full points', () {
      final r = result([0, 1, 2, 3], {0: 7, 1: 7, 2: 7, 3: 7});
      final board = Scoreboard().addResult(r, mode: GameMode.ffa);
      for (final id in [0, 1, 2, 3]) {
        expect(board.pointsOf(id), 4, reason: 'id=$id');
      }
    });

    test('tie for last shares the lowest placement', () {
      final r = result([0, 1, 2, 3], {0: 30, 1: 20, 2: 5, 3: 5});
      final board = Scoreboard().addResult(r, mode: GameMode.ffa);
      expect(board.pointsOf(0), 4);
      expect(board.pointsOf(1), 3);
      // 2 and 3 tie at the 3rd index => 4 - 2 = 2 points each.
      expect(board.pointsOf(2), 2);
      expect(board.pointsOf(3), 2);
    });
  });

  group('immutability', () {
    test('addResult returns a new instance and leaves the original empty', () {
      final original = Scoreboard();
      final r = result([0, 1], {0: 9, 1: 1});
      final next = original.addResult(r, mode: GameMode.ffa);
      expect(identical(original, next), isFalse);
      expect(original.pointsOf(0), 0); // unchanged
      expect(next.pointsOf(0), 2);
    });

    test('accumulates across multiple rounds', () {
      var board = Scoreboard();
      board = board.addResult(result([0, 1], {0: 5, 1: 1}), mode: GameMode.ffa);
      board = board.addResult(result([1, 0], {1: 9, 0: 1}), mode: GameMode.ffa);
      // P0: 2 (round1 win) + 1 (round2 loss) = 3.
      expect(board.pointsOf(0), 3);
      // P1: 1 + 2 = 3.
      expect(board.pointsOf(1), 3);
    });

    test('points map is unmodifiable', () {
      final board = Scoreboard({0: 5});
      expect(() => board.points[0] = 99, throwsUnsupportedError);
    });
  });

  group('standings ordering', () {
    test('orders by points desc, breaking ties by ascending id', () {
      final board = Scoreboard({0: 10, 1: 30, 2: 30, 3: 5});
      // 1 and 2 tie at 30 -> lower id (1) first.
      expect(board.standings(), [1, 2, 0, 3]);
    });

    test('includes zero-point players', () {
      final board = Scoreboard({0: 0, 1: 0, 2: 1});
      expect(board.standings(), [2, 0, 1]);
    });

    test('standings list is unmodifiable', () {
      final board = Scoreboard({0: 1});
      expect(() => board.standings().add(9), throwsUnsupportedError);
    });
  });

  group('leader', () {
    test('is the top of standings', () {
      final board = Scoreboard({0: 10, 1: 50, 2: 20});
      expect(board.leader, 1);
    });

    test('lowest id wins a points tie', () {
      final board = Scoreboard({2: 40, 5: 40});
      expect(board.leader, 2);
    });

    test('is null for an empty board', () {
      expect(Scoreboard().leader, isNull);
    });
  });

  group('empty handling', () {
    test('pointsOf returns 0 for an unseen player', () {
      expect(Scoreboard().pointsOf(99), 0);
    });

    test('empty ranking throws ArgumentError', () {
      final r = result(<int>[], <int, num>{});
      expect(
        () => Scoreboard().addResult(r, mode: GameMode.ffa),
        throwsArgumentError,
      );
    });
  });
}
