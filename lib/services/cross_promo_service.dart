/// Cross-promo (house ads) — promotes the studio's own catalog in full-screen
/// slots that would otherwise go to network ads. Strategic in the offline MVP:
/// it is the only "ad" surface that actually does anything, driving installs
/// across the studio's portfolio at zero ad-network cost.
///
/// No external dependencies: icons are drawn procedurally later (only an accent
/// color is stored, [HouseAd.iconArgb]), and store links are opened via a stub
/// ([CrossPromoService.openStore]) — real deeplinking (url_launcher) is wired
/// later. Impression/click counts are kept in memory and queryable for tests.
library;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/rng.dart';

/// Immutable house-ad creative for one of the studio's games.
///
/// - [weight]: relative weight for weighted random selection (higher = more
///   often). Must be > 0 to be eligible.
/// - [iconArgb]: accent color (ARGB) for the procedurally drawn icon — no
///   image asset is referenced.
@immutable
class HouseAd {
  final String id;
  final String title;
  final String blurb;
  final String storeUrl;
  final int weight;
  final int iconArgb;

  const HouseAd({
    required this.id,
    required this.title,
    required this.blurb,
    required this.storeUrl,
    required this.weight,
    required this.iconArgb,
  });

  @override
  bool operator ==(Object other) =>
      other is HouseAd &&
      other.id == id &&
      other.title == title &&
      other.blurb == blurb &&
      other.storeUrl == storeUrl &&
      other.weight == weight &&
      other.iconArgb == iconArgb;

  @override
  int get hashCode =>
      Object.hash(id, title, blurb, storeUrl, weight, iconArgb);

  @override
  String toString() =>
      'HouseAd(id: $id, title: $title, weight: $weight)';
}

/// Default seed catalog: the studio's own games. Store URLs are placeholders
/// (replace with the real listing ids at publish time). These are public store
/// links, not secrets.
const List<HouseAd> kDefaultHouseAds = <HouseAd>[
  HouseAd(
    id: 'drink_sort',
    title: 'Drink Sort Bar',
    blurb: 'Pour, sort, relax. The cozy color-sorting puzzle.',
    storeUrl:
        'https://play.google.com/store/apps/details?id=com.stickstudio.drinksort',
    weight: 3,
    iconArgb: 0xFF4DC3FF,
  ),
  HouseAd(
    id: 'stick_rpg',
    title: 'Stickman: Dark Leveling',
    blurb: 'Level up your stickman in a dark fantasy idle RPG.',
    storeUrl:
        'https://play.google.com/store/apps/details?id=com.stickstudio.darkleveling',
    weight: 2,
    iconArgb: 0xFF8A5CFF,
  ),
];

/// Manages the house-ad catalog, selection, and impression/click tracking.
///
/// Stateful only for the in-memory analytics counters; selection is driven by
/// an injected [SeededRng] so tests are deterministic.
class CrossPromoService {
  /// Log prefix for the analytics debug hook.
  static const String _logTag = '[CrossPromo]';

  final List<HouseAd> _catalog;
  final Map<String, int> _impressions = <String, int>{};
  final Map<String, int> _clicks = <String, int>{};

  /// Builds a service over [catalog] (defaults to [kDefaultHouseAds]). The
  /// catalog is copied to an unmodifiable list to prevent external mutation.
  CrossPromoService({List<HouseAd>? catalog})
      : _catalog = List<HouseAd>.unmodifiable(catalog ?? kDefaultHouseAds);

  /// The house-ad catalog (unmodifiable).
  List<HouseAd> get catalog => _catalog;

  /// Pick a house ad by weight using [rng]. Returns null when the catalog is
  /// empty or all weights are non-positive.
  HouseAd? pickWeighted(SeededRng rng) {
    int totalWeight = 0;
    for (final HouseAd ad in _catalog) {
      if (ad.weight > 0) totalWeight += ad.weight;
    }
    if (totalWeight <= 0) return null;
    // roll in [0, totalWeight); walk the cumulative weights.
    int roll = rng.intRange(0, totalWeight);
    for (final HouseAd ad in _catalog) {
      if (ad.weight <= 0) continue;
      if (roll < ad.weight) return ad;
      roll -= ad.weight;
    }
    return null; // Unreachable when totalWeight > 0; defensive.
  }

  /// Whether a full-screen slot should be filled by a house ad rather than a
  /// (disabled) network ad. [houseShare] defaults to [Monetize.houseAdShare].
  ///
  /// [roundsSinceLast] is accepted for symmetry with the interstitial policy
  /// and future pacing rules; the current decision is a pure probability roll
  /// via [SeededRng.chance].
  bool shouldShowHouseAd({
    required int roundsSinceLast,
    double houseShare = Monetize.houseAdShare,
    required SeededRng rng,
  }) {
    return rng.chance(houseShare);
  }

  /// Record that [id] was displayed. In-memory counter plus an analytics hook.
  void recordImpression(String id) {
    _impressions[id] = (_impressions[id] ?? 0) + 1;
    debugPrint('$_logTag impression id=$id total=${_impressions[id]}');
  }

  /// Record that [id] was clicked. In-memory counter plus an analytics hook.
  void recordClick(String id) {
    _clicks[id] = (_clicks[id] ?? 0) + 1;
    debugPrint('$_logTag click id=$id total=${_clicks[id]}');
  }

  /// Impression count for [id] (0 if none). Queryable for tests.
  int impressionsOf(String id) => _impressions[id] ?? 0;

  /// Click count for [id] (0 if none). Queryable for tests.
  int clicksOf(String id) => _clicks[id] ?? 0;

  /// Open the store listing for [ad]. Stub: records a click and logs the URL.
  /// Real deeplinking (url_launcher) is wired later — no dependency here.
  Future<void> openStore(HouseAd ad) async {
    recordClick(ad.id);
    debugPrint('$_logTag openStore (stub) id=${ad.id} url=${ad.storeUrl}');
  }
}
