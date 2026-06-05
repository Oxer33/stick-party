/// Daily PLAY-streak (consecutive calendar days the player opened a match).
///
/// This is a *play* streak, not a win streak: simply playing on consecutive
/// days extends it. State is immutable; [StreakService] is a pure function with
/// no persistence — the repository layer owns reading/writing.
library;

import 'package:flutter/foundation.dart';

/// Minimum [StreakState.current] for the flame badge to show.
const int kStreakFlameThreshold = 3;

/// Minimum [StreakState.current] for the "hot" (intense) state.
const int kStreakHotThreshold = 5;

@immutable
class StreakState {
  const StreakState({required this.current, required this.best})
      : assert(current >= 0, 'current must be >= 0'),
        assert(best >= 0, 'best must be >= 0');

  /// Empty/starting streak.
  const StreakState.empty()
      : current = 0,
        best = 0;

  final int current;
  final int best;

  /// Show a small flame once the streak is meaningful.
  bool get showFlame => current >= kStreakFlameThreshold;

  /// Intense state for longer streaks.
  bool get isHot => current >= kStreakHotThreshold;

  StreakState copyWith({int? current, int? best}) =>
      StreakState(current: current ?? this.current, best: best ?? this.best);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StreakState &&
        other.current == current &&
        other.best == best;
  }

  @override
  int get hashCode => Object.hash(current, best);

  @override
  String toString() => 'StreakState(current: $current, best: $best)';
}

/// Pure transitions for the play-streak. No persistence, no side effects.
class StreakService {
  StreakService._();

  static const int _firstDayValue = 1;
  static const int _step = 1;

  /// Folds [today] into the streak given the [lastPlay] day.
  ///
  /// Rules (compared on the calendar day only, in UTC, to avoid DST drift):
  /// - [lastPlay] is null              → first ever play → current = 1.
  /// - [lastPlay] is the same day      → already counted → unchanged.
  /// - [lastPlay] is exactly yesterday → current + 1.
  /// - any other gap (incl. clock back)→ reset → current = 1.
  ///
  /// [best] is always raised to at least the new [current].
  static StreakState onPlayDay(
    StreakState prev, {
    required DateTime today,
    required DateTime? lastPlay,
  }) {
    final DateTime todayUtc = _dateOnlyUtc(today);

    int nextCurrent;
    if (lastPlay == null) {
      nextCurrent = _firstDayValue;
    } else {
      final DateTime lastUtc = _dateOnlyUtc(lastPlay);
      final int diffDays = todayUtc.difference(lastUtc).inDays;
      if (diffDays == 0) {
        // Same calendar day: no change at all (current and best preserved).
        return prev;
      } else if (diffDays == _step) {
        nextCurrent = prev.current + _step;
      } else {
        // Gap > 1 day or clock moved backwards → start over.
        nextCurrent = _firstDayValue;
      }
    }

    final int nextBest = nextCurrent > prev.best ? nextCurrent : prev.best;
    return prev.copyWith(current: nextCurrent, best: nextBest);
  }

  /// Normalises a [DateTime] to midnight UTC of its calendar day so that
  /// `difference(...).inDays` is an exact whole-day count.
  static DateTime _dateOnlyUtc(DateTime d) {
    final DateTime u = d.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }
}
