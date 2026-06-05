/// Pure purchase-grant routing — maps a product id to the entitlements it
/// grants. No gameplay/progression unlocks (ethics): only ad removal,
/// cosmetics, and soft-currency convenience.
///
/// [isRestore] is true when replaying owned purchases at startup. On restore,
/// CONSUMABLES (coin packs) are NOT re-granted — that would let players farm
/// currency every boot. Entitlements (remove-ads, unlock-all, cosmetic bundle)
/// ARE restored because they are idempotent and one-time by nature.
///
/// Pure and side-effect free: returns an immutable [PurchaseGrant] the caller
/// applies to its state. Unknown ids yield an empty grant (defensive no-op).
library;

import 'package:flutter/foundation.dart';

import 'iap_service.dart';

/// Soft-currency amounts granted per coin pack. Named constants — no magic
/// numbers. Tunable here without touching routing logic.
abstract final class CoinPackAmounts {
  static const int small = 100;
  static const int medium = 500;
  static const int large = 1500;
}

/// Immutable description of what a purchase grants.
///
/// - [removeAds]: disable ads.
/// - [unlockAll]: unlock every cosmetic.
/// - [coins]: soft currency to add (0 on restore for consumables).
/// - [cosmeticIds]: specific cosmetic ids to unlock.
@immutable
class PurchaseGrant {
  final bool removeAds;
  final bool unlockAll;
  final int coins;
  final List<String> cosmeticIds;

  const PurchaseGrant({
    this.removeAds = false,
    this.unlockAll = false,
    this.coins = 0,
    this.cosmeticIds = const <String>[],
  });

  /// An empty grant (nothing granted) — used for unknown ids.
  static const PurchaseGrant empty = PurchaseGrant();

  /// True when this grant confers nothing.
  bool get isEmpty =>
      !removeAds && !unlockAll && coins == 0 && cosmeticIds.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is PurchaseGrant &&
      other.removeAds == removeAds &&
      other.unlockAll == unlockAll &&
      other.coins == coins &&
      listEquals(other.cosmeticIds, cosmeticIds);

  @override
  int get hashCode =>
      Object.hash(removeAds, unlockAll, coins, Object.hashAll(cosmeticIds));

  @override
  String toString() => 'PurchaseGrant(removeAds: $removeAds, unlockAll: '
      '$unlockAll, coins: $coins, cosmeticIds: $cosmeticIds)';
}

/// Pure routing from product id to [PurchaseGrant].
abstract final class PurchaseApplier {
  /// Cosmetic ids unlocked by the cosmetics bundle. Placeholder ids — the real
  /// cosmetic catalog is defined elsewhere later.
  static const List<String> _bundleCosmeticIds = <String>[
    'cosmetic_aurora',
    'cosmetic_ocean',
    'cosmetic_ember',
  ];

  /// Map [productId] to the grant it confers.
  ///
  /// When [isRestore] is true, consumable coin packs grant 0 coins (no
  /// re-grant on boot); entitlements are still granted (idempotent). Unknown
  /// ids return [PurchaseGrant.empty]. No progression/gameplay unlocks are
  /// ever granted here.
  static PurchaseGrant apply(String productId, {required bool isRestore}) {
    switch (productId) {
      case IapProductIds.removeAds:
        // Entitlement: idempotent, always restorable.
        return const PurchaseGrant(removeAds: true);
      case IapProductIds.unlockAll:
        // Entitlement: idempotent, always restorable.
        return const PurchaseGrant(unlockAll: true);
      case IapProductIds.bundleCosmetics:
        // Entitlement: cosmetic unlocks, idempotent and restorable.
        return const PurchaseGrant(cosmeticIds: _bundleCosmeticIds);
      case IapProductIds.coinsSmall:
        if (isRestore) return PurchaseGrant.empty;
        return const PurchaseGrant(coins: CoinPackAmounts.small);
      case IapProductIds.coinsMedium:
        if (isRestore) return PurchaseGrant.empty;
        return const PurchaseGrant(coins: CoinPackAmounts.medium);
      case IapProductIds.coinsLarge:
        if (isRestore) return PurchaseGrant.empty;
        return const PurchaseGrant(coins: CoinPackAmounts.large);
      default:
        // Unknown id: defensive empty grant.
        return PurchaseGrant.empty;
    }
  }
}
