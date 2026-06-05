import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stick_party/meta/achievements.dart';
import 'package:stick_party/meta/streak.dart';

ProgressSnapshot snap({
  int roundsPlayed = 0,
  int cupsWon = 0,
  int knockouts = 0,
  Set<String> gamesPlayedIds = const <String>{},
  int maxPlayersInSession = 0,
  int bestStreak = 0,
}) =>
    ProgressSnapshot(
      roundsPlayed: roundsPlayed,
      cupsWon: cupsWon,
      knockouts: knockouts,
      gamesPlayedIds: gamesPlayedIds,
      maxPlayersInSession: maxPlayersInSession,
      bestStreak: bestStreak,
    );

void main() {
  group('registry', () {
    test('kAchievements is non-empty and achievementCount agrees', () {
      expect(kAchievements, isNotEmpty);
      expect(achievementCount, kAchievements.length);
    });

    test('all achievement ids are unique', () {
      final ids = kAchievements.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every achievement has a positive threshold and non-empty text', () {
      for (final a in kAchievements) {
        expect(a.threshold, greaterThan(0), reason: a.id);
        expect(a.name, isNotEmpty, reason: a.id);
        expect(a.description, isNotEmpty, reason: a.id);
      }
    });
  });

  group('isUnlocked flips at the threshold', () {
    test('the first-round achievement unlocks at exactly 1 round', () {
      final a = kAchievements.firstWhere((x) => x.id == 'rounds_first');
      expect(a.isUnlocked(snap(roundsPlayed: 0)), isFalse);
      expect(a.isUnlocked(snap(roundsPlayed: 1)), isTrue);
    });

    test('a 10-round tier needs 10 rounds', () {
      final a = kAchievements.firstWhere((x) => x.id == 'rounds_10');
      expect(a.isUnlocked(snap(roundsPlayed: 9)), isFalse);
      expect(a.isUnlocked(snap(roundsPlayed: 10)), isTrue);
      expect(a.isUnlocked(snap(roundsPlayed: 99)), isTrue);
    });

    test('cups, knockouts, full-party and streak gates fire at target', () {
      expect(
        kAchievements
            .firstWhere((x) => x.id == 'cups_1')
            .isUnlocked(snap(cupsWon: 1)),
        isTrue,
      );
      expect(
        kAchievements
            .firstWhere((x) => x.id == 'ko_10')
            .isUnlocked(snap(knockouts: 10)),
        isTrue,
      );
      expect(
        kAchievements.firstWhere((x) => x.id == 'social_full_party').isUnlocked(
              snap(maxPlayersInSession: kFullPartyPlayers),
            ),
        isTrue,
      );
      expect(
        kAchievements
            .firstWhere((x) => x.id == 'streak_7')
            .isUnlocked(snap(bestStreak: kStreakAchievementDays)),
        isTrue,
      );
    });

    test('variety achievement counts distinct games played', () {
      final a = kAchievements.firstWhere((x) => x.id == 'variety_all');
      final justUnder = <String>{
        for (var i = 0; i < kVarietyAllGamesTarget - 1; i++) 'g$i'
      };
      final atTarget = <String>{
        for (var i = 0; i < kVarietyAllGamesTarget; i++) 'g$i'
      };
      expect(a.isUnlocked(snap(gamesPlayedIds: justUnder)), isFalse);
      expect(a.isUnlocked(snap(gamesPlayedIds: atTarget)), isTrue);
    });
  });

  group('progressFraction is always within [0, 1]', () {
    test('clamps below and above the threshold', () {
      final a = kAchievements.firstWhere((x) => x.id == 'rounds_10');
      expect(a.progressFraction(snap(roundsPlayed: 0)), 0.0);
      expect(a.progressFraction(snap(roundsPlayed: 5)), closeTo(0.5, 1e-9));
      expect(a.progressFraction(snap(roundsPlayed: 10)), 1.0);
      // Overshoot does not exceed 1.0 (currentProgress is clamped).
      expect(a.progressFraction(snap(roundsPlayed: 9999)), 1.0);
    });

    test('currentProgress never exceeds the threshold or goes negative', () {
      for (final a in kAchievements) {
        // A huge snapshot in every dimension.
        final big = snap(
          roundsPlayed: 100000,
          cupsWon: 100000,
          knockouts: 100000,
          gamesPlayedIds: {for (var i = 0; i < 100; i++) 'g$i'},
          maxPlayersInSession: 100,
          bestStreak: 100000,
        );
        expect(a.currentProgress(big), lessThanOrEqualTo(a.threshold),
            reason: a.id);
        expect(a.currentProgress(ProgressSnapshot.empty),
            greaterThanOrEqualTo(0),
            reason: a.id);
      }
    });
  });

  group('unlockedCount', () {
    test('is 0 for an empty snapshot', () {
      expect(unlockedCount(ProgressSnapshot.empty), 0);
    });

    test('counts every achievement when all thresholds are met', () {
      final everything = snap(
        roundsPlayed: 100000,
        cupsWon: 100000,
        knockouts: 100000,
        gamesPlayedIds: {for (var i = 0; i < 100; i++) 'g$i'},
        maxPlayersInSession: 100,
        bestStreak: 100000,
      );
      expect(unlockedCount(everything), kAchievements.length);
    });
  });

  group('ProgressSnapshot helpers', () {
    test('distinctGamesPlayed reflects the set size', () {
      expect(snap(gamesPlayedIds: {'a', 'b', 'c'}).distinctGamesPlayed, 3);
    });

    test('streakProgress reads StreakState.best', () {
      expect(streakProgress(const StreakState(current: 2, best: 7)), 7);
    });

    test('empty snapshot has an empty games set', () {
      expect(setEquals(ProgressSnapshot.empty.gamesPlayedIds, <String>{}),
          isTrue);
    });
  });
}
