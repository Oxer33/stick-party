import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/meta/cosmetics.dart';

void main() {
  group('catalog', () {
    test('contains both free and coins-locked items', () {
      final hasFree = kCosmetics.any((c) => c.unlock == UnlockKind.free);
      final hasCoins = kCosmetics.any((c) => c.unlock == UnlockKind.coins);
      expect(hasFree, isTrue);
      expect(hasCoins, isTrue);
    });

    test('all cosmetic ids are unique', () {
      final ids = kCosmetics.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('free items have priceCoins 0 and isFree true', () {
      for (final c in kCosmetics.where((c) => c.unlock == UnlockKind.free)) {
        expect(c.priceCoins, 0, reason: c.id);
        expect(c.isFree, isTrue, reason: c.id);
      }
    });

    test('coins items have a positive price and are not free', () {
      for (final c in kCosmetics.where((c) => c.unlock == UnlockKind.coins)) {
        expect(c.priceCoins, greaterThan(0), reason: c.id);
        expect(c.isFree, isFalse, reason: c.id);
      }
    });

    test('every cosmetic has a non-empty palette and name', () {
      for (final c in kCosmetics) {
        expect(c.paletteArgb, isNotEmpty, reason: c.id);
        expect(c.name, isNotEmpty, reason: c.id);
      }
    });

    test('the default skin exists and is a free stick skin', () {
      final def = cosmeticById(kDefaultSkinId);
      expect(def, isNotNull);
      expect(def!.type, CosmeticType.stickSkin);
      expect(def.isFree, isTrue);
    });
  });

  group('isOwned', () {
    test('free cosmetics are always owned, even with an empty set', () {
      final free = kCosmetics.firstWhere((c) => c.unlock == UnlockKind.free);
      expect(isOwned(<String>{}, free), isTrue);
    });

    test('coins cosmetics are owned only when present in the set', () {
      final paid = kCosmetics.firstWhere((c) => c.unlock == UnlockKind.coins);
      expect(isOwned(<String>{}, paid), isFalse);
      expect(isOwned({paid.id}, paid), isTrue);
    });

    test('owning an unrelated id does not unlock a different paid item', () {
      final paid = kCosmetics.firstWhere((c) => c.unlock == UnlockKind.coins);
      expect(isOwned({'some_other_id'}, paid), isFalse);
    });
  });

  group('cosmeticById', () {
    test('returns the matching cosmetic', () {
      final c = cosmeticById(kDefaultSkinId);
      expect(c?.id, kDefaultSkinId);
    });

    test('returns null for an unknown id', () {
      expect(cosmeticById('does_not_exist'), isNull);
    });
  });

  group('Cosmetic value equality', () {
    // Non-const factory so each call is a distinct instance: this forces the
    // full operator== body to run (const canonicalization would short-circuit).
    Cosmetic make({
      String id = 'x',
      String name = 'X',
      CosmeticType type = CosmeticType.trail,
      UnlockKind unlock = UnlockKind.coins,
      int priceCoins = 100,
      List<int> palette = const <int>[0xFF000000],
    }) =>
        Cosmetic(
          id: id,
          name: name,
          type: type,
          unlock: unlock,
          priceCoins: priceCoins,
          paletteArgb: palette,
        );

    test('two equal cosmetics compare equal with matching hashCode', () {
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });

    test('any differing field breaks equality', () {
      expect(make() == make(id: 'y'), isFalse);
      expect(make() == make(name: 'Y'), isFalse);
      expect(make() == make(type: CosmeticType.mapTheme), isFalse);
      expect(make() == make(unlock: UnlockKind.free), isFalse);
      expect(make() == make(priceCoins: 200), isFalse);
      expect(make() == make(palette: const <int>[0xFFFFFFFF]), isFalse);
    });
  });
}
