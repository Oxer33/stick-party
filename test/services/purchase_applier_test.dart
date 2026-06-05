import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/services/iap_service.dart';
import 'package:stick_party/services/purchase_applier.dart';

void main() {
  group('entitlements (always granted, including restore)', () {
    test('removeAds grants on fresh buy and on restore', () {
      final fresh =
          PurchaseApplier.apply(IapProductIds.removeAds, isRestore: false);
      final restored =
          PurchaseApplier.apply(IapProductIds.removeAds, isRestore: true);
      expect(fresh.removeAds, isTrue);
      expect(restored.removeAds, isTrue);
    });

    test('unlockAll grants on fresh buy and on restore', () {
      final fresh =
          PurchaseApplier.apply(IapProductIds.unlockAll, isRestore: false);
      final restored =
          PurchaseApplier.apply(IapProductIds.unlockAll, isRestore: true);
      expect(fresh.unlockAll, isTrue);
      expect(restored.unlockAll, isTrue);
    });

    test('cosmetics bundle grants the same cosmetic ids on buy and restore', () {
      final fresh = PurchaseApplier.apply(IapProductIds.bundleCosmetics,
          isRestore: false);
      final restored = PurchaseApplier.apply(IapProductIds.bundleCosmetics,
          isRestore: true);
      expect(fresh.cosmeticIds, isNotEmpty);
      expect(restored.cosmeticIds, fresh.cosmeticIds);
    });
  });

  group('consumables (coin packs)', () {
    test('small/medium/large grant their amounts on a fresh buy', () {
      expect(
        PurchaseApplier.apply(IapProductIds.coinsSmall, isRestore: false).coins,
        CoinPackAmounts.small,
      );
      expect(
        PurchaseApplier.apply(IapProductIds.coinsMedium, isRestore: false).coins,
        CoinPackAmounts.medium,
      );
      expect(
        PurchaseApplier.apply(IapProductIds.coinsLarge, isRestore: false).coins,
        CoinPackAmounts.large,
      );
    });

    test('coins are NOT re-granted on restore (empty grant)', () {
      for (final id in [
        IapProductIds.coinsSmall,
        IapProductIds.coinsMedium,
        IapProductIds.coinsLarge,
      ]) {
        final grant = PurchaseApplier.apply(id, isRestore: true);
        expect(grant.coins, 0, reason: id);
        expect(grant, PurchaseGrant.empty, reason: id);
      }
    });

    test('coin pack amounts ascend small < medium < large', () {
      expect(CoinPackAmounts.small, lessThan(CoinPackAmounts.medium));
      expect(CoinPackAmounts.medium, lessThan(CoinPackAmounts.large));
    });
  });

  group('unknown id', () {
    test('returns the empty grant on buy and restore', () {
      expect(PurchaseApplier.apply('mystery', isRestore: false),
          PurchaseGrant.empty);
      expect(PurchaseApplier.apply('mystery', isRestore: true),
          PurchaseGrant.empty);
      expect(PurchaseApplier.apply('', isRestore: false).isEmpty, isTrue);
    });
  });

  group('PurchaseGrant value semantics', () {
    test('empty grant confers nothing', () {
      expect(PurchaseGrant.empty.isEmpty, isTrue);
      expect(PurchaseGrant.empty.removeAds, isFalse);
      expect(PurchaseGrant.empty.coins, 0);
      expect(PurchaseGrant.empty.cosmeticIds, isEmpty);
    });

    test('a coin grant is not empty', () {
      const g = PurchaseGrant(coins: 100);
      expect(g.isEmpty, isFalse);
    });

    test('equality compares all fields including cosmetic ids', () {
      const a = PurchaseGrant(cosmeticIds: ['x', 'y']);
      const b = PurchaseGrant(cosmeticIds: ['x', 'y']);
      const c = PurchaseGrant(cosmeticIds: ['x']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
