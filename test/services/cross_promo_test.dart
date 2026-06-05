import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/core/rng.dart';
import 'package:stick_party/services/cross_promo_service.dart';

void main() {
  group('pickWeighted', () {
    test('returns an ad from the catalog (seeded)', () {
      final svc = CrossPromoService();
      final ad = svc.pickWeighted(SeededRng(1));
      expect(ad, isNotNull);
      expect(svc.catalog.contains(ad), isTrue);
    });

    test('is deterministic for a fixed seed', () {
      final svc = CrossPromoService();
      final a = svc.pickWeighted(SeededRng(7));
      final b = svc.pickWeighted(SeededRng(7));
      expect(a, b);
    });

    test('returns null for an empty catalog', () {
      final svc = CrossPromoService(catalog: const []);
      expect(svc.pickWeighted(SeededRng(1)), isNull);
    });

    test('returns null when all weights are non-positive', () {
      final svc = CrossPromoService(catalog: const [
        HouseAd(
          id: 'zero',
          title: 'Zero',
          blurb: 'b',
          storeUrl: 'u',
          weight: 0,
          iconArgb: 0xFF000000,
        ),
      ]);
      expect(svc.pickWeighted(SeededRng(1)), isNull);
    });

    test('only ever returns positively-weighted ads', () {
      final svc = CrossPromoService(catalog: const [
        HouseAd(
          id: 'live',
          title: 'Live',
          blurb: 'b',
          storeUrl: 'u',
          weight: 5,
          iconArgb: 0xFF111111,
        ),
        HouseAd(
          id: 'dead',
          title: 'Dead',
          blurb: 'b',
          storeUrl: 'u',
          weight: 0,
          iconArgb: 0xFF222222,
        ),
      ]);
      for (var seed = 0; seed < 50; seed++) {
        expect(svc.pickWeighted(SeededRng(seed))!.id, 'live');
      }
    });

    test('catalog is unmodifiable', () {
      final svc = CrossPromoService();
      expect(
        () => svc.catalog.add(const HouseAd(
              id: 'x',
              title: 't',
              blurb: 'b',
              storeUrl: 'u',
              weight: 1,
              iconArgb: 0xFF000000,
            )),
        throwsUnsupportedError,
      );
    });
  });

  group('shouldShowHouseAd respects the share', () {
    test('a 0.0 share never shows', () {
      final svc = CrossPromoService();
      for (var seed = 0; seed < 50; seed++) {
        final show = svc.shouldShowHouseAd(
          roundsSinceLast: 1,
          houseShare: 0.0,
          rng: SeededRng(seed),
        );
        expect(show, isFalse, reason: 'seed=$seed');
      }
    });

    test('a 1.0 share always shows', () {
      final svc = CrossPromoService();
      for (var seed = 0; seed < 50; seed++) {
        final show = svc.shouldShowHouseAd(
          roundsSinceLast: 1,
          houseShare: 1.0,
          rng: SeededRng(seed),
        );
        expect(show, isTrue, reason: 'seed=$seed');
      }
    });
  });

  group('impression/click counters', () {
    test('recordImpression increments a queryable counter', () {
      final svc = CrossPromoService();
      expect(svc.impressionsOf('drink_sort'), 0);
      svc.recordImpression('drink_sort');
      svc.recordImpression('drink_sort');
      expect(svc.impressionsOf('drink_sort'), 2);
    });

    test('recordClick increments a queryable counter', () {
      final svc = CrossPromoService();
      expect(svc.clicksOf('stick_rpg'), 0);
      svc.recordClick('stick_rpg');
      expect(svc.clicksOf('stick_rpg'), 1);
    });

    test('counters are per-id and independent', () {
      final svc = CrossPromoService();
      svc.recordImpression('a');
      svc.recordClick('b');
      expect(svc.impressionsOf('a'), 1);
      expect(svc.impressionsOf('b'), 0);
      expect(svc.clicksOf('b'), 1);
      expect(svc.clicksOf('a'), 0);
    });

    test('openStore records a click for the ad', () async {
      final svc = CrossPromoService();
      final ad = svc.catalog.first;
      await svc.openStore(ad);
      expect(svc.clicksOf(ad.id), 1);
    });
  });

  group('default catalog', () {
    test('kDefaultHouseAds is non-empty with positive weights', () {
      expect(kDefaultHouseAds, isNotEmpty);
      for (final ad in kDefaultHouseAds) {
        expect(ad.weight, greaterThan(0), reason: ad.id);
        expect(ad.id, isNotEmpty);
      }
    });
  });
}
