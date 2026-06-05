import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/constants.dart';
import 'package:stick_party/services/ad_frequency.dart';

void main() {
  // Wall-clock helpers in ms; the seconds gap is Monetize.interstitialMinSecondsGap.
  const minGapMs = Monetize.interstitialMinSecondsGap * 1000;

  group('shouldShowInterstitial', () {
    test('is false when the player owns remove-ads', () {
      final ok = AdFrequency.shouldShowInterstitial(
        roundsSinceLast: 99,
        removeAds: true,
        nowEpochMs: 1000000,
        lastEpochMs: 0,
      );
      expect(ok, isFalse);
    });

    test('is false until the round gap is met', () {
      // One round short of the minimum.
      final tooSoon = AdFrequency.shouldShowInterstitial(
        roundsSinceLast: Monetize.interstitialMinRoundGap - 1,
        removeAds: false,
        nowEpochMs: minGapMs + 1,
        lastEpochMs: 0,
      );
      expect(tooSoon, isFalse);
    });

    test('is false until the seconds gap is met (even with enough rounds)', () {
      final tooSoon = AdFrequency.shouldShowInterstitial(
        roundsSinceLast: Monetize.interstitialMinRoundGap + 5,
        removeAds: false,
        nowEpochMs: minGapMs - 1, // 1ms short
        lastEpochMs: 0,
      );
      expect(tooSoon, isFalse);
    });

    test('requires BOTH gaps: round met but time not -> false', () {
      final ok = AdFrequency.shouldShowInterstitial(
        roundsSinceLast: Monetize.interstitialMinRoundGap,
        removeAds: false,
        nowEpochMs: 10000,
        lastEpochMs: 9000, // only 1s elapsed
      );
      expect(ok, isFalse);
    });

    test('is true once both round and seconds gaps are satisfied', () {
      final ok = AdFrequency.shouldShowInterstitial(
        roundsSinceLast: Monetize.interstitialMinRoundGap,
        removeAds: false,
        nowEpochMs: minGapMs,
        lastEpochMs: 0,
      );
      expect(ok, isTrue);
    });

    test('lastEpochMs of 0 trivially satisfies the time gap', () {
      final ok = AdFrequency.shouldShowInterstitial(
        roundsSinceLast: Monetize.interstitialMinRoundGap + 1,
        removeAds: false,
        nowEpochMs: minGapMs + 50,
        lastEpochMs: 0,
      );
      expect(ok, isTrue);
    });
  });

  group('canShowRewarded', () {
    test('is true while under the daily cap', () {
      expect(AdFrequency.canShowRewarded(0), isTrue);
      expect(AdFrequency.canShowRewarded(Monetize.rewardedDailyCap - 1), isTrue);
    });

    test('is false at and above the daily cap', () {
      expect(AdFrequency.canShowRewarded(Monetize.rewardedDailyCap), isFalse);
      expect(AdFrequency.canShowRewarded(Monetize.rewardedDailyCap + 3), isFalse);
    });
  });

  group('AdFrequencyState transitions', () {
    test('withRoundCompleted bumps the round counter only', () {
      const s = AdFrequencyState();
      final next = s.withRoundCompleted();
      expect(next.roundsSinceInterstitial, 1);
      expect(next.rewardedToday, 0);
      expect(next.lastInterstitialEpochMs, 0);
    });

    test('withInterstitialShown resets rounds and records the timestamp', () {
      const s = AdFrequencyState(roundsSinceInterstitial: 5);
      final next = s.withInterstitialShown(123456);
      expect(next.roundsSinceInterstitial, 0);
      expect(next.lastInterstitialEpochMs, 123456);
    });

    test('withRewardedGranted increments the daily count', () {
      const s = AdFrequencyState(rewardedToday: 2);
      expect(s.withRewardedGranted().rewardedToday, 3);
    });

    test('withDailyReset zeroes the rewarded count', () {
      const s = AdFrequencyState(rewardedToday: 9);
      expect(s.withDailyReset().rewardedToday, 0);
    });

    test('is immutable: copyWith returns a new instance', () {
      const s = AdFrequencyState();
      final next = s.withRoundCompleted();
      expect(identical(s, next), isFalse);
      expect(s.roundsSinceInterstitial, 0); // original untouched
    });

    test('value equality holds for identical states', () {
      const a = AdFrequencyState(
          roundsSinceInterstitial: 1,
          rewardedToday: 2,
          lastInterstitialEpochMs: 3);
      const b = AdFrequencyState(
          roundsSinceInterstitial: 1,
          rewardedToday: 2,
          lastInterstitialEpochMs: 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
