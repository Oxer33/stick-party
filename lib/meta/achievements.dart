/// Party milestones. A static registry of [Achievement]s, each reading a single
/// immutable [ProgressSnapshot] to compute progress and unlock state.
///
/// Pure data + pure functions: no persistence, no Flutter widget imports. The
/// repository builds the [ProgressSnapshot]; the UI renders [kAchievements].
library;

import 'package:flutter/foundation.dart';

import 'streak.dart';

/// Number of distinct mini-games in the roster, used by the "play them all"
/// achievement. Roster ids are strings (see engine `MiniGameMeta.id`); this is
/// the target count rather than a hard enum so adding games is data-only.
const int kVarietyAllGamesTarget = 8;

/// Players required in one session for the social "full party" achievement.
const int kFullPartyPlayers = 4;

/// Days required for the streak achievement.
const int kStreakAchievementDays = 7;

/// Groups achievements into UI sections.
enum AchievementCategory { beginner, cups, knockouts, variety, social }

/// Read-only view of player progress that achievements compute against.
///
/// Deliberately small and decoupled from the storage model: the repository
/// adapts `Progress` into this snapshot.
@immutable
class ProgressSnapshot {
  const ProgressSnapshot({
    required this.roundsPlayed,
    required this.cupsWon,
    required this.knockouts,
    required this.gamesPlayedIds,
    required this.maxPlayersInSession,
    required this.bestStreak,
  })  : assert(roundsPlayed >= 0, 'roundsPlayed must be >= 0'),
        assert(cupsWon >= 0, 'cupsWon must be >= 0'),
        assert(knockouts >= 0, 'knockouts must be >= 0'),
        assert(maxPlayersInSession >= 0, 'maxPlayersInSession must be >= 0'),
        assert(bestStreak >= 0, 'bestStreak must be >= 0');

  final int roundsPlayed;
  final int cupsWon;
  final int knockouts;
  final Set<String> gamesPlayedIds;
  final int maxPlayersInSession;
  final int bestStreak;

  /// Count of distinct mini-games the player has tried.
  int get distinctGamesPlayed => gamesPlayedIds.length;

  /// Empty starting snapshot.
  static const ProgressSnapshot empty = ProgressSnapshot(
    roundsPlayed: 0,
    cupsWon: 0,
    knockouts: 0,
    gamesPlayedIds: <String>{},
    maxPlayersInSession: 0,
    bestStreak: 0,
  );
}

/// Function computing the current progress value for an achievement.
typedef ProgressOfSnapshot = int Function(ProgressSnapshot s);

@immutable
class Achievement {
  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.threshold,
    required this.progressOf,
  }) : assert(threshold > 0, 'threshold must be > 0');

  final String id;
  final String name;
  final String description;
  final AchievementCategory category;
  final int threshold;
  final ProgressOfSnapshot progressOf;

  /// Raw progress clamped to `[0, threshold]`.
  int currentProgress(ProgressSnapshot s) {
    final int raw = progressOf(s);
    if (raw < 0) return 0;
    if (raw > threshold) return threshold;
    return raw;
  }

  /// Unlocked once progress reaches the threshold.
  bool isUnlocked(ProgressSnapshot s) => progressOf(s) >= threshold;

  /// Progress as a `[0, 1]` fraction for UI bars.
  double progressFraction(ProgressSnapshot s) {
    if (threshold <= 0) return 1.0;
    return currentProgress(s) / threshold;
  }
}

// Shared progress extractors (DRY across multiple tiers).
int _rounds(ProgressSnapshot s) => s.roundsPlayed;
int _cups(ProgressSnapshot s) => s.cupsWon;
int _knockouts(ProgressSnapshot s) => s.knockouts;
int _distinctGames(ProgressSnapshot s) => s.distinctGamesPlayed;
int _maxPlayers(ProgressSnapshot s) => s.maxPlayersInSession;
int _bestStreak(ProgressSnapshot s) => s.bestStreak;

/// Full achievement registry (14 entries across 5 categories).
const List<Achievement> kAchievements = <Achievement>[
  // ----- Beginner: rounds played -------------------------------------------
  Achievement(
    id: 'rounds_first',
    name: 'First Brawl',
    description: 'Play your first round',
    category: AchievementCategory.beginner,
    threshold: 1,
    progressOf: _rounds,
  ),
  Achievement(
    id: 'rounds_10',
    name: 'Warmed Up',
    description: 'Play 10 rounds',
    category: AchievementCategory.beginner,
    threshold: 10,
    progressOf: _rounds,
  ),
  Achievement(
    id: 'rounds_50',
    name: 'Regular',
    description: 'Play 50 rounds',
    category: AchievementCategory.beginner,
    threshold: 50,
    progressOf: _rounds,
  ),
  Achievement(
    id: 'rounds_200',
    name: 'Veteran',
    description: 'Play 200 rounds',
    category: AchievementCategory.beginner,
    threshold: 200,
    progressOf: _rounds,
  ),
  Achievement(
    id: 'rounds_500',
    name: 'Unstoppable',
    description: 'Play 500 rounds',
    category: AchievementCategory.beginner,
    threshold: 500,
    progressOf: _rounds,
  ),

  // ----- Cups won ----------------------------------------------------------
  Achievement(
    id: 'cups_1',
    name: 'First Cup',
    description: 'Win a cup',
    category: AchievementCategory.cups,
    threshold: 1,
    progressOf: _cups,
  ),
  Achievement(
    id: 'cups_10',
    name: 'Cup Collector',
    description: 'Win 10 cups',
    category: AchievementCategory.cups,
    threshold: 10,
    progressOf: _cups,
  ),
  Achievement(
    id: 'cups_50',
    name: 'Champion',
    description: 'Win 50 cups',
    category: AchievementCategory.cups,
    threshold: 50,
    progressOf: _cups,
  ),

  // ----- Knockouts ---------------------------------------------------------
  Achievement(
    id: 'ko_10',
    name: 'Brawler',
    description: 'Knock out 10 rivals',
    category: AchievementCategory.knockouts,
    threshold: 10,
    progressOf: _knockouts,
  ),
  Achievement(
    id: 'ko_50',
    name: 'Demolisher',
    description: 'Knock out 50 rivals',
    category: AchievementCategory.knockouts,
    threshold: 50,
    progressOf: _knockouts,
  ),
  Achievement(
    id: 'ko_200',
    name: 'Annihilator',
    description: 'Knock out 200 rivals',
    category: AchievementCategory.knockouts,
    threshold: 200,
    progressOf: _knockouts,
  ),

  // ----- Variety -----------------------------------------------------------
  Achievement(
    id: 'variety_all',
    name: 'Jack of All Games',
    description: 'Play every mini-game',
    category: AchievementCategory.variety,
    threshold: kVarietyAllGamesTarget,
    progressOf: _distinctGames,
  ),

  // ----- Social ------------------------------------------------------------
  Achievement(
    id: 'social_full_party',
    name: 'Full House',
    description: 'Play with $kFullPartyPlayers players',
    category: AchievementCategory.social,
    threshold: kFullPartyPlayers,
    progressOf: _maxPlayers,
  ),
  Achievement(
    id: 'streak_7',
    name: 'Week Warrior',
    description: 'Play $kStreakAchievementDays days in a row',
    category: AchievementCategory.social,
    threshold: kStreakAchievementDays,
    progressOf: _bestStreak,
  ),
];

/// Count of unlocked achievements for [s]. Pure.
int unlockedCount(ProgressSnapshot s) {
  int n = 0;
  for (final Achievement a in kAchievements) {
    if (a.isUnlocked(s)) n++;
  }
  return n;
}

/// Total number of achievements in the registry.
int get achievementCount => kAchievements.length;

/// A [StreakState] adapter: pulls the value the streak achievement reads.
int streakProgress(StreakState streak) => streak.best;
