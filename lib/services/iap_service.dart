/// In-app purchase boundary — interface, offline stub, and product catalog.
///
/// OFFLINE MVP: no in_app_purchase plugin. [StubIapService] returns a static
/// catalog and simulates successful purchases so buy/restore flows are
/// testable without a store. Real wiring against the store APIs is a later
/// step; this interface is the seam for it.
///
/// Price labels here are PLACEHOLDERS — the real localized prices come from the
/// store at runtime. Product IDs are stable string keys (not secrets).
library;

import '../core/result.dart';

/// Stable product identifiers. These are catalog keys, not secrets; real store
/// SKUs are configured in the store console at the account stage.
abstract final class IapProductIds {
  static const String removeAds = 'remove_ads';
  static const String unlockAll = 'unlock_all';
  static const String coinsSmall = 'coins_small';
  static const String coinsMedium = 'coins_medium';
  static const String coinsLarge = 'coins_large';
  static const String bundleCosmetics = 'bundle_cosmetics';
}

/// Immutable description of a purchasable product.
///
/// [consumable] is true for coin packs (granted each purchase, never restored)
/// and false for entitlements (remove-ads, unlock-all, cosmetic bundle) which
/// are restorable.
class IapProduct {
  final String id;
  final String title;
  final String priceLabel;
  final bool consumable;

  const IapProduct({
    required this.id,
    required this.title,
    required this.priceLabel,
    required this.consumable,
  });

  @override
  bool operator ==(Object other) =>
      other is IapProduct &&
      other.id == id &&
      other.title == title &&
      other.priceLabel == priceLabel &&
      other.consumable == consumable;

  @override
  int get hashCode => Object.hash(id, title, priceLabel, consumable);

  @override
  String toString() =>
      'IapProduct(id: $id, title: $title, priceLabel: $priceLabel, '
      'consumable: $consumable)';
}

/// Abstraction over the store. [buy] returns a [Result] carrying the purchased
/// product id on success or a human-readable message on failure.
abstract class IapService {
  /// Initialize the store connection. No-op for the stub.
  Future<void> init();

  /// The available products. For the stub this is the static catalog.
  List<IapProduct> get products;

  /// Attempt to purchase [id]. Ok(id) on success, Err(message) on failure
  /// (e.g. unknown product, store unavailable, user cancelled).
  Future<Result<String>> buy(String id);

  /// Restore previously owned non-consumable entitlements.
  Future<void> restore();
}

/// Offline stub [IapService].
///
/// - [init] does nothing.
/// - [products] is the static [catalog].
/// - [buy] validates the id against the catalog and returns Ok(id) to simulate
///   a successful purchase (Err for unknown ids).
/// - [restore] is a no-op.
class StubIapService implements IapService {
  const StubIapService();

  /// Static product catalog with placeholder price labels (real prices come
  /// from the store later).
  static const List<IapProduct> catalog = <IapProduct>[
    IapProduct(
      id: IapProductIds.removeAds,
      title: 'Remove Ads',
      priceLabel: '€3.99',
      consumable: false,
    ),
    IapProduct(
      id: IapProductIds.unlockAll,
      title: 'Unlock All Cosmetics',
      priceLabel: '€6.99',
      consumable: false,
    ),
    IapProduct(
      id: IapProductIds.coinsSmall,
      title: 'Small Coin Pack',
      priceLabel: '€0.99',
      consumable: true,
    ),
    IapProduct(
      id: IapProductIds.coinsMedium,
      title: 'Medium Coin Pack',
      priceLabel: '€2.99',
      consumable: true,
    ),
    IapProduct(
      id: IapProductIds.coinsLarge,
      title: 'Large Coin Pack',
      priceLabel: '€7.99',
      consumable: true,
    ),
    IapProduct(
      id: IapProductIds.bundleCosmetics,
      title: 'Cosmetics Bundle',
      priceLabel: '€4.99',
      consumable: false,
    ),
  ];

  @override
  Future<void> init() async {
    // Offline stub: nothing to initialize.
  }

  @override
  List<IapProduct> get products => catalog;

  @override
  Future<Result<String>> buy(String id) async {
    final bool known = catalog.any((IapProduct p) => p.id == id);
    if (!known) {
      return Err<String>('Unknown product id: $id');
    }
    // Simulated successful purchase so downstream grant flows are testable.
    return Ok<String>(id);
  }

  @override
  Future<void> restore() async {
    // Offline stub: nothing to restore.
  }
}
