/// Ad service boundary — interface plus an offline no-op stub.
///
/// OFFLINE MVP: network ads are disabled ([Monetize.networkAdsEnabled] is
/// false). [StubAdService] performs no real ad calls so the whole monetization
/// flow stays testable without the AdMob SDK. Wiring a real implementation
/// against google_mobile_ads is a P4 step (see docs/ROADMAP) — it would add a
/// second `AdService` implementation; this interface is the seam for it.
library;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';

/// Abstraction over full-screen and banner ads. Pure async surface; gating
/// (frequency, remove-ads) is decided by [AdFrequency] before calling these.
abstract class AdService {
  /// Initialize the underlying SDK. No-op for the stub.
  Future<void> init();

  /// Show an interstitial. The caller must have already confirmed it is
  /// allowed via the frequency policy and that no round is in progress.
  Future<void> showInterstitial();

  /// Show a rewarded ad. Resolves true when the reward should be granted,
  /// false when the user dismissed it or it failed to show.
  Future<bool> showRewarded();

  /// Whether banner ads are enabled on this build.
  bool get bannerEnabled;
}

/// Offline no-op [AdService].
///
/// - [init] does nothing.
/// - [showInterstitial] logs and returns; no ad is shown.
/// - [showRewarded] returns true so rewarded-gated flows are exercisable
///   offline and in tests.
/// - [bannerEnabled] mirrors [Monetize.networkAdsEnabled] (false in the MVP).
class StubAdService implements AdService {
  const StubAdService();

  /// Log prefix so stub activity is greppable in debug output.
  static const String _logTag = '[StubAdService]';

  @override
  Future<void> init() async {
    debugPrint('$_logTag init (offline no-op; '
        'networkAdsEnabled=${Monetize.networkAdsEnabled})');
  }

  @override
  Future<void> showInterstitial() async {
    debugPrint('$_logTag showInterstitial (no-op, no network ad shown)');
  }

  @override
  Future<bool> showRewarded() {
    debugPrint('$_logTag showRewarded (no-op, granting reward for offline '
        'flow testing)');
    return Future<bool>.value(true);
  }

  @override
  bool get bannerEnabled => Monetize.networkAdsEnabled;
}
