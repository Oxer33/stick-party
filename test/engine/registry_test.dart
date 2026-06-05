import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/engine/registry.dart';

void main() {
  group('registry size', () {
    test('there are exactly 15 mini-games', () {
      expect(miniGameCount, 15);
      expect(allMiniGameIds.length, 15);
    });

    test('all ids are unique', () {
      expect(allMiniGameIds.toSet().length, allMiniGameIds.length);
    });

    test('allMiniGameIds list is unmodifiable', () {
      expect(() => allMiniGameIds.add('x'), throwsUnsupportedError);
    });
  });

  group('createMiniGame', () {
    test('every registered id builds a non-null game whose meta.id matches', () {
      for (final id in allMiniGameIds) {
        final game = createMiniGame(id);
        expect(game, isNotNull, reason: id);
        expect(game.meta.id, id, reason: 'meta.id must equal registry key $id');
      }
    });

    test('returns a fresh instance on each call', () {
      final id = allMiniGameIds.first;
      final a = createMiniGame(id);
      final b = createMiniGame(id);
      expect(identical(a, b), isFalse);
    });

    test('throws ArgumentError for an unknown id', () {
      expect(() => createMiniGame('nope'), throwsArgumentError);
      expect(() => createMiniGame(''), throwsArgumentError);
    });
  });

  group('allMiniGameMetas', () {
    test('has one meta per game with matching ids', () {
      final metas = allMiniGameMetas();
      expect(metas.length, 15);
      expect(
        metas.map((m) => m.id).toList(),
        allMiniGameIds,
        reason: 'meta order should match id order',
      );
    });

    test('every meta has sane player bounds', () {
      for (final m in allMiniGameMetas()) {
        expect(m.minPlayers, greaterThanOrEqualTo(1), reason: m.id);
        expect(m.maxPlayers, greaterThanOrEqualTo(m.minPlayers), reason: m.id);
        expect(m.name, isNotEmpty, reason: m.id);
      }
    });
  });

  group('miniGameIdsForPlayers', () {
    test('every returned id for 2 players actually supports 2', () {
      final ids = miniGameIdsForPlayers(2);
      expect(ids, isNotEmpty);
      for (final id in ids) {
        expect(createMiniGame(id).meta.supportsPlayers(2), isTrue, reason: id);
      }
    });

    test('filters out games that do not support the count', () {
      // Every id NOT in the 2-player list must indeed reject 2 players.
      final supports2 = miniGameIdsForPlayers(2).toSet();
      for (final id in allMiniGameIds) {
        final ok = createMiniGame(id).meta.supportsPlayers(2);
        expect(supports2.contains(id), ok, reason: id);
      }
    });

    test('an impossible player count yields an empty list', () {
      expect(miniGameIdsForPlayers(99), isEmpty);
      expect(miniGameIdsForPlayers(0), isEmpty);
    });
  });
}
