/// Pure ad-frequency policy — no SDK, no I/O, fully unit-testable.
///
/// Offline MVP rules (see [Monetize] in core/constants.dart):
///  - Interstitial: only AFTER a round ends (the caller invokes this at that
///    point — NEVER mid-round). Requires BOTH a minimum number of rounds since
///    the last interstitial AND a minimum wall-clock gap. Disabled entirely
///    when the player owns remove-ads.
///  - Rewarded: capped per day to avoid ad-fatigue.
///
/// All methods are static and side-effect free; [AdFrequencyState] is an
/// immutable snapshot the caller persists between rounds.
library;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';

/// Immutable counters the caller persists across rounds/sessions.
///
/// - [roundsSinceInterstitial]: rounds completed since the last interstitial.
/// - [rewardedToday]: rewarded ads granted in the current local day.
/// - [lastInterstitialEpochMs]: wall-clock ms of the last interstitial show
///   (0 when none shown yet).
@immutable
class AdFrequencyState {
  final int roundsSinceInterstitial;
  final int rewardedToday;
  final int lastInterstitialEpochMs;

  const AdFrequencyState({
    this.roundsSinceInterstitial = 0,
    this.rewardedToday = 0,
    this.lastInterstitialEpochMs = 0,
  });

  AdFrequencyState copyWith({
    int? roundsSinceInterstitial,
    int? rewardedToday,
    int? lastInterstitialEpochMs,
  }) {
    return AdFrequencyState(
      roundsSinceInterstitial:
          roundsSinceInterstitial ?? this.roundsSinceInterstitial,
      rewardedToday: rewardedToday ?? this.rewardedToday,
      lastInterstitialEpochMs:
          lastInterstitialEpochMs ?? this.lastInterstitialEpochMs,
    );
  }

  /// New state after one round completes (no interstitial shown).
  AdFrequencyState withRoundCompleted() =>
      copyWith(roundsSinceInterstitial: roundsSinceInterstitial + 1);

  /// New state after an interstitial is shown at [nowEpochMs]: resets the
  /// round counter and records the timestamp.
  AdFrequencyState withInterstitialShown(int nowEpochMs) => copyWith(
        roundsSinceInterstitial: 0,
        lastInterstitialEpochMs: nowEpochMs,
      );

  /// New state after a rewarded ad is granted (increments the daily count).
  AdFrequencyState withRewardedGranted() =>
      copyWith(rewardedToday: rewardedToday + 1);

  /// New state at the start of a new local day (resets the rewarded cap).
  AdFrequencyState withDailyReset() => copyWith(rewardedToday: 0);

  @override
  bool operator ==(Object other) =>
      other is AdFrequencyState &&
      other.roundsSinceInterstitial == roundsSinceInterstitial &&
      other.rewardedToday == rewardedToday &&
      other.lastInterstitialEpochMs == lastInterstitialEpochMs;

  @override
  int get hashCode => Object.hash(
        roundsSinceInterstitial,
        rewardedToday,
        lastInterstitialEpochMs,
      );

  @override
  String toString() => 'AdFrequencyState(roundsSinceInterstitial: '
      '$roundsSinceInterstitial, rewardedToday: $rewardedToday, '
      'lastInterstitialEpochMs: $lastInterstitialEpochMs)';
}

/// Pure decision functions for ad gating. Stateless — feed it the current
/// counters and it returns a verdict. The caller owns timing and persistence.
abstract final class AdFrequency {
  /// Whether an interstitial may be shown RIGHT NOW.
  ///
  /// IMPORTANT: the caller MUST only invoke this between rounds (e.g. on the
  /// round-end screen), NEVER mid-round — that gating is a caller
  /// responsibility this pure function cannot enforce.
  ///
  /// Returns false when:
  ///  - [removeAds] is true (player paid to remove ads), or
  ///  - fewer than [Monetize.interstitialMinRoundGap] rounds have elapsed
  ///    since the last interstitial, or
  ///  - fewer than [Monetize.interstitialMinSecondsGap] seconds have elapsed
  ///    since the last interstitial.
  ///
  /// [nowEpochMs] and [lastEpochMs] are wall-clock milliseconds; a
  /// [lastEpochMs] of 0 (never shown) trivially satisfies the time gap.
  static bool shouldShowInterstitial({
    required int roundsSinceLast,
    required bool removeAds,
    required int nowEpochMs,
    required int lastEpochMs,
  }) {
    if (removeAds) return false;
    if (roundsSinceLast < Monetize.interstitialMinRoundGap) return false;
    final int elapsedMs = nowEpochMs - lastEpochMs;
    final int minGapMs = Monetize.interstitialMinSecondsGap * 1000;
    if (elapsedMs < minGapMs) return false;
    return true;
  }

  /// Whether another rewarded ad may be granted today.
  ///
  /// True while [rewardedToday] is below [Monetize.rewardedDailyCap].
  static bool canShowRewarded(int rewardedToday) =>
      rewardedToday < Monetize.rewardedDailyCap;
}
