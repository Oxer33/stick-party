/// Analytics boundary — interface plus an offline debug stub.
///
/// OFFLINE MVP: no analytics SDK / no network. [StubAnalyticsService] logs
/// events via debugPrint so event wiring is verifiable in development. A real
/// implementation (e.g. Firebase Analytics) is a later step; this interface is
/// the seam for it. Event names are centralized as constants so producers and
/// any future dashboard agree on the schema.
library;

import 'package:flutter/foundation.dart';

/// Canonical analytics event names. Use these constants instead of string
/// literals at call sites to avoid typos and schema drift.
abstract final class AnalyticsEvents {
  static const String roundStart = 'round_start';
  static const String roundEnd = 'round_end';
  static const String cupWin = 'cup_win';
  static const String houseAdImpression = 'house_ad_impression';
  static const String houseAdClick = 'house_ad_click';
  static const String iapBuy = 'iap_buy';
}

/// Abstraction over analytics logging. [params] is an optional bag of typed
/// values associated with the event.
abstract class AnalyticsService {
  void logEvent(String name, [Map<String, Object?> params]);
}

/// Offline debug [AnalyticsService] — prints events instead of sending them.
class StubAnalyticsService implements AnalyticsService {
  const StubAnalyticsService();

  /// Log prefix so events are greppable in debug output.
  static const String _logTag = '[Analytics]';

  @override
  void logEvent(String name, [Map<String, Object?> params = const {}]) {
    if (params.isEmpty) {
      debugPrint('$_logTag $name');
    } else {
      debugPrint('$_logTag $name $params');
    }
  }
}
