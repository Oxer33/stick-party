import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/constants.dart';
import 'package:stick_party/core/result.dart';
import 'package:stick_party/services/ad_service.dart';
import 'package:stick_party/services/iap_service.dart';

void main() {
  group('StubIapService.products', () {
    const svc = StubIapService();

    test('is non-empty', () {
      expect(svc.products, isNotEmpty);
    });

    test('includes the expected product ids', () {
      final ids = svc.products.map((p) => p.id).toSet();
      expect(
        ids,
        containsAll(<String>[
          IapProductIds.removeAds,
          IapProductIds.unlockAll,
          IapProductIds.coinsSmall,
          IapProductIds.coinsMedium,
          IapProductIds.coinsLarge,
          IapProductIds.bundleCosmetics,
        ]),
      );
    });

    test('coin packs are consumable, entitlements are not', () {
      IapProduct byId(String id) => svc.products.firstWhere((p) => p.id == id);
      expect(byId(IapProductIds.coinsSmall).consumable, isTrue);
      expect(byId(IapProductIds.removeAds).consumable, isFalse);
      expect(byId(IapProductIds.unlockAll).consumable, isFalse);
      expect(byId(IapProductIds.bundleCosmetics).consumable, isFalse);
    });

    test('every product has a non-empty price label', () {
      for (final p in svc.products) {
        expect(p.priceLabel, isNotEmpty, reason: p.id);
      }
    });
  });

  group('StubIapService.buy', () {
    const svc = StubIapService();

    test('a known product returns Ok(id)', () async {
      final res = await svc.buy(IapProductIds.removeAds);
      expect(res.isOk, isTrue);
      expect(res.valueOrNull, IapProductIds.removeAds);
    });

    test('every catalog product is buyable', () async {
      for (final p in svc.products) {
        final res = await svc.buy(p.id);
        expect(res.isOk, isTrue, reason: p.id);
        expect((res as Ok<String>).value, p.id);
      }
    });

    test('an unknown product returns Err', () async {
      final res = await svc.buy('not_a_real_product');
      expect(res.isErr, isTrue);
      expect((res as Err<String>).message, contains('Unknown product'));
    });
  });

  group('StubIapService lifecycle', () {
    const svc = StubIapService();

    test('init completes without throwing', () async {
      await expectLater(svc.init(), completes);
    });

    test('restore is a no-op that completes', () async {
      await expectLater(svc.restore(), completes);
    });
  });

  group('StubAdService', () {
    const svc = StubAdService();

    test('bannerEnabled mirrors Monetize.networkAdsEnabled', () {
      expect(svc.bannerEnabled, Monetize.networkAdsEnabled);
    });

    test('showRewarded resolves true (offline grant for testing)', () async {
      expect(await svc.showRewarded(), isTrue);
    });

    test('init and showInterstitial complete without throwing', () async {
      await expectLater(svc.init(), completes);
      await expectLater(svc.showInterstitial(), completes);
    });
  });

  group('IapProduct value type', () {
    // Use non-const, field-differing instances so operator== runs in full.
    IapProduct make({
      String id = 'p',
      String title = 'T',
      String price = '€1',
      bool consumable = false,
    }) =>
        IapProduct(
            id: id, title: title, priceLabel: price, consumable: consumable);

    test('equal products compare equal with matching hashCode', () {
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });

    test('any differing field breaks equality', () {
      expect(make() == make(id: 'other'), isFalse);
      expect(make() == make(title: 'Other'), isFalse);
      expect(make() == make(price: '€9'), isFalse);
      expect(make() == make(consumable: true), isFalse);
    });

    test('toString includes id and price', () {
      final s = make(id: 'remove_ads', price: '€3.99').toString();
      expect(s, contains('remove_ads'));
      expect(s, contains('€3.99'));
    });
  });
}
