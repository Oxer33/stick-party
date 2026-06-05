import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/meta/streak.dart';

void main() {
  // Use UTC dates because StreakService compares on the calendar day in UTC.
  DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

  group('StreakService.onPlayDay', () {
    test('first ever play (null lastPlay) sets current to 1', () {
      // Arrange
      const prev = StreakState.empty();
      // Act
      final next = StreakService.onPlayDay(
        prev,
        today: day(2026, 6, 5),
        lastPlay: null,
      );
      // Assert
      expect(next.current, 1);
      expect(next.best, 1);
    });

    test('same calendar day leaves the streak unchanged', () {
      const prev = StreakState(current: 4, best: 9);
      final next = StreakService.onPlayDay(
        prev,
        today: day(2026, 6, 5),
        lastPlay: day(2026, 6, 5),
      );
      expect(next, prev);
      expect(next.current, 4);
      expect(next.best, 9);
    });

    test('same day even at a different clock time is unchanged', () {
      const prev = StreakState(current: 2, best: 2);
      final next = StreakService.onPlayDay(
        prev,
        today: DateTime.utc(2026, 6, 5, 23, 59),
        lastPlay: DateTime.utc(2026, 6, 5, 0, 1),
      );
      expect(next.current, 2);
    });

    test('playing yesterday increments current by 1', () {
      const prev = StreakState(current: 3, best: 3);
      final next = StreakService.onPlayDay(
        prev,
        today: day(2026, 6, 5),
        lastPlay: day(2026, 6, 4),
      );
      expect(next.current, 4);
      expect(next.best, 4);
    });

    test('a multi-day gap resets current to 1', () {
      const prev = StreakState(current: 8, best: 8);
      final next = StreakService.onPlayDay(
        prev,
        today: day(2026, 6, 5),
        lastPlay: day(2026, 6, 2), // 3-day gap
      );
      expect(next.current, 1);
      // best is preserved (monotonic).
      expect(next.best, 8);
    });

    test('clock moving backwards resets current to 1', () {
      const prev = StreakState(current: 5, best: 5);
      final next = StreakService.onPlayDay(
        prev,
        today: day(2026, 6, 1),
        lastPlay: day(2026, 6, 5), // last play in the "future"
      );
      expect(next.current, 1);
      expect(next.best, 5);
    });

    test('best is monotonic and rises with a new high', () {
      const prev = StreakState(current: 6, best: 6);
      final next = StreakService.onPlayDay(
        prev,
        today: day(2026, 6, 5),
        lastPlay: day(2026, 6, 4),
      );
      expect(next.current, 7);
      expect(next.best, 7); // new record
    });

    test('best never decreases when current resets', () {
      const prev = StreakState(current: 10, best: 10);
      final next = StreakService.onPlayDay(
        prev,
        today: day(2026, 6, 20),
        lastPlay: day(2026, 6, 1),
      );
      expect(next.current, 1);
      expect(next.best, 10);
    });

    test('a continuous multi-day run builds up correctly', () {
      var state = const StreakState.empty();
      DateTime? last;
      for (var d = 1; d <= 5; d++) {
        final today = day(2026, 6, d);
        state = StreakService.onPlayDay(state, today: today, lastPlay: last);
        last = today;
      }
      expect(state.current, 5);
      expect(state.best, 5);
    });
  });

  group('StreakState flags', () {
    test('showFlame at/above the flame threshold', () {
      expect(const StreakState(current: kStreakFlameThreshold, best: 5).showFlame,
          isTrue);
      expect(
          const StreakState(current: kStreakFlameThreshold - 1, best: 5)
              .showFlame,
          isFalse);
    });

    test('isHot at/above the hot threshold', () {
      expect(
          const StreakState(current: kStreakHotThreshold, best: 9).isHot, isTrue);
      expect(
          const StreakState(current: kStreakHotThreshold - 1, best: 9).isHot,
          isFalse);
    });
  });

  group('StreakState value type', () {
    test('copyWith overrides only the named fields', () {
      const s = StreakState(current: 3, best: 8);
      expect(s.copyWith(current: 4), const StreakState(current: 4, best: 8));
      expect(s.copyWith(best: 9), const StreakState(current: 3, best: 9));
      expect(s.copyWith(), s);
    });

    test('equality and hashCode compare current and best', () {
      // Field-differing (non-identical) instances exercise the operator body.
      final a = StreakState(current: 2, best: 5);
      final b = StreakState(current: 2, best: 5);
      final c = StreakState(current: 2, best: 6);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('toString reports current and best', () {
      expect(const StreakState(current: 3, best: 7).toString(),
          'StreakState(current: 3, best: 7)');
    });
  });
}
