import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:stick_party/core/constants.dart';
import 'package:stick_party/data/persistence.dart';
import 'package:stick_party/meta/cosmetics.dart';
import 'package:stick_party/meta/progress_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<dynamic> box;
  late Persistence persistence;
  late ProgressRepository repo;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('stick_party_progress_');
    Hive.init(dir.path);
  });

  setUp(() async {
    box = await Hive.openBox<dynamic>(
        'progress_test_${DateTime.now().microsecondsSinceEpoch}');
    persistence = Persistence.withBox(box);
    repo = ProgressRepository(persistence);
  });

  tearDown(() async {
    await box.clear();
    await box.close();
  });

  group('load defaults', () {
    test('an empty store loads initial-like defaults', () {
      final p = repo.load();
      expect(p.coins, 0);
      expect(p.ownedCosmetics, isEmpty);
      expect(p.selectedSkinId, kDefaultSkinId);
      expect(p.recordsByGame, isEmpty);
      expect(p.cupsWon, 0);
      expect(p.roundsPlayed, 0);
      expect(p.knockouts, 0);
      expect(p.maxPlayersInSession, 0);
      expect(p.streak.current, 0);
      expect(p.streak.best, 0);
    });

    test('an invalid stored skin falls back to the default', () async {
      await persistence.putString(ProgressKeys.selectedSkin, 'bogus_skin');
      expect(repo.load().selectedSkinId, kDefaultSkinId);
    });

    test('load enforces best >= current after corruption', () async {
      await persistence.putInt(ProgressKeys.streakCurrent, 9);
      await persistence.putInt(ProgressKeys.streakBest, 2);
      final p = repo.load();
      expect(p.streak.current, 9);
      expect(p.streak.best, 9);
    });
  });

  group('addCoins', () {
    test('adds and persists coins', () async {
      var p = repo.load();
      p = await repo.addCoins(p, 30);
      expect(p.coins, 30);
      expect(repo.load().coins, 30); // persisted
    });

    test('clamps to Economy.maxCoins', () async {
      var p = repo.load();
      p = await repo.addCoins(p, Economy.maxCoins + 5000);
      expect(p.coins, Economy.maxCoins);
      expect(repo.load().coins, Economy.maxCoins);
    });

    test('never goes below zero', () async {
      var p = repo.load();
      p = await repo.addCoins(p, 10);
      p = await repo.addCoins(p, -100);
      expect(p.coins, 0);
    });
  });

  group('unlockCosmetic', () {
    test('unlocks a paid cosmetic and persists it', () async {
      final paid = kCosmetics.firstWhere((c) => c.unlock == UnlockKind.coins);
      var p = repo.load();
      p = await repo.unlockCosmetic(p, paid.id);
      expect(p.ownedCosmetics, contains(paid.id));
      expect(repo.load().ownedCosmetics, contains(paid.id));
    });

    test('free cosmetics are a no-op (already owned)', () async {
      final free = kCosmetics.firstWhere((c) => c.unlock == UnlockKind.free);
      final p0 = repo.load();
      final p1 = await repo.unlockCosmetic(p0, free.id);
      expect(identical(p0, p1), isTrue); // same instance returned
      expect(p1.ownedCosmetics, isEmpty);
    });

    test('an unknown id is a no-op', () async {
      final p0 = repo.load();
      final p1 = await repo.unlockCosmetic(p0, 'no_such_cosmetic');
      expect(identical(p0, p1), isTrue);
    });
  });

  group('setSelectedSkin', () {
    test('selects an owned/free stick skin and persists it', () async {
      // A free stick skin other than the default is always owned.
      final freeSkin = kCosmetics.firstWhere((c) =>
          c.type == CosmeticType.stickSkin &&
          c.unlock == UnlockKind.free &&
          c.id != kDefaultSkinId);
      var p = repo.load();
      p = await repo.setSelectedSkin(p, freeSkin.id);
      expect(p.selectedSkinId, freeSkin.id);
      expect(repo.load().selectedSkinId, freeSkin.id);
    });

    test('rejects an unowned paid skin', () async {
      final paidSkin = kCosmetics.firstWhere((c) =>
          c.type == CosmeticType.stickSkin && c.unlock == UnlockKind.coins);
      final p0 = repo.load();
      final p1 = await repo.setSelectedSkin(p0, paidSkin.id);
      expect(p1.selectedSkinId, kDefaultSkinId); // unchanged
    });

    test('selecting a paid skin works once it is owned', () async {
      final paidSkin = kCosmetics.firstWhere((c) =>
          c.type == CosmeticType.stickSkin && c.unlock == UnlockKind.coins);
      var p = repo.load();
      p = await repo.unlockCosmetic(p, paidSkin.id);
      p = await repo.setSelectedSkin(p, paidSkin.id);
      expect(p.selectedSkinId, paidSkin.id);
    });
  });

  group('counters persist', () {
    test('incRounds increments and persists', () async {
      var p = repo.load();
      p = await repo.incRounds(p);
      p = await repo.incRounds(p, by: 2);
      expect(p.roundsPlayed, 3);
      expect(repo.load().roundsPlayed, 3);
    });

    test('incCupsWon increments and persists', () async {
      var p = repo.load();
      p = await repo.incCupsWon(p);
      expect(p.cupsWon, 1);
      expect(repo.load().cupsWon, 1);
    });

    test('incKnockouts increments and persists', () async {
      var p = repo.load();
      p = await repo.incKnockouts(p, by: 5);
      expect(p.knockouts, 5);
      expect(repo.load().knockouts, 5);
    });

    test('a non-positive increment is a no-op', () async {
      final p0 = repo.load();
      final p1 = await repo.incRounds(p0, by: 0);
      expect(identical(p0, p1), isTrue);
    });

    test('recordSessionPlayers only raises the max', () async {
      var p = repo.load();
      p = await repo.recordSessionPlayers(p, 3);
      expect(p.maxPlayersInSession, 3);
      // A smaller value does not lower it.
      p = await repo.recordSessionPlayers(p, 2);
      expect(p.maxPlayersInSession, 3);
      expect(repo.load().maxPlayersInSession, 3);
    });
  });

  group('recordResult', () {
    test('keeps the best (highest) value and persists', () async {
      var p = repo.load();
      p = await repo.recordResult(p, 'snake_arena', 50);
      expect(p.recordsByGame['snake_arena'], 50);
      // A lower value is ignored.
      p = await repo.recordResult(p, 'snake_arena', 30);
      expect(p.recordsByGame['snake_arena'], 50);
      // A higher value wins.
      p = await repo.recordResult(p, 'snake_arena', 80);
      expect(p.recordsByGame['snake_arena'], 80);
      expect(repo.load().recordsByGame['snake_arena'], 80);
    });

    test('an empty game id is a no-op', () async {
      final p0 = repo.load();
      final p1 = await repo.recordResult(p0, '', 10);
      expect(identical(p0, p1), isTrue);
    });
  });

  group('toSnapshot', () {
    test('maps fields including distinct games and best streak', () async {
      var p = repo.load();
      p = await repo.incRounds(p, by: 4);
      p = await repo.incCupsWon(p, by: 2);
      p = await repo.incKnockouts(p, by: 6);
      p = await repo.recordSessionPlayers(p, 4);
      p = await repo.recordResult(p, 'g1', 1);
      p = await repo.recordResult(p, 'g2', 2);

      final snap = p.toSnapshot();
      expect(snap.roundsPlayed, 4);
      expect(snap.cupsWon, 2);
      expect(snap.knockouts, 6);
      expect(snap.maxPlayersInSession, 4);
      expect(snap.distinctGamesPlayed, 2);
      expect(snap.gamesPlayedIds, containsAll(<String>['g1', 'g2']));
      expect(snap.bestStreak, p.streak.best);
    });
  });

  group('save + reload', () {
    test('a full save round-trips every field', () async {
      var p = repo.load();
      p = await repo.addCoins(p, 123);
      p = await repo.incRounds(p, by: 7);
      final paid = kCosmetics.firstWhere((c) => c.unlock == UnlockKind.coins);
      p = await repo.unlockCosmetic(p, paid.id);
      await repo.save(p);

      final reloaded = repo.load();
      expect(reloaded.coins, 123);
      expect(reloaded.roundsPlayed, 7);
      expect(reloaded.ownedCosmetics, contains(paid.id));
    });
  });
}
