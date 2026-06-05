/// Player progress: an immutable [Progress] value plus a [ProgressRepository]
/// that loads/saves it through [Persistence].
///
/// Riverpod-free on purpose — providers wrap this later. Serialization stays
/// simple (ints, strings, lists, maps) to match the raw Hive box. Reads are
/// corruption-tolerant; writes are best-effort (see [Persistence]).
library;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../data/persistence.dart';
import 'achievements.dart';
import 'cosmetics.dart';
import 'streak.dart';

/// Hive keys for every persisted progress field. Centralised to avoid typos.
class ProgressKeys {
  ProgressKeys._();

  static const String coins = 'coins';
  static const String ownedCosmetics = 'owned_cosmetics';
  static const String selectedSkin = 'selected_skin';
  static const String recordsByGame = 'records_by_game';
  static const String cupsWon = 'cups_won';
  static const String roundsPlayed = 'rounds_played';
  static const String knockouts = 'knockouts';
  static const String maxPlayers = 'max_players_in_session';
  static const String streakCurrent = 'streak_current';
  static const String streakBest = 'streak_best';
}

@immutable
class Progress {
  const Progress({
    required this.coins,
    required this.ownedCosmetics,
    required this.selectedSkinId,
    required this.recordsByGame,
    required this.cupsWon,
    required this.roundsPlayed,
    required this.knockouts,
    required this.maxPlayersInSession,
    required this.streak,
  })  : assert(coins >= 0, 'coins must be >= 0'),
        assert(cupsWon >= 0, 'cupsWon must be >= 0'),
        assert(roundsPlayed >= 0, 'roundsPlayed must be >= 0'),
        assert(knockouts >= 0, 'knockouts must be >= 0'),
        assert(maxPlayersInSession >= 0, 'maxPlayersInSession must be >= 0');

  final int coins;
  final Set<String> ownedCosmetics;
  final String selectedSkinId;

  /// Best record per mini-game id (e.g. high score / fastest time as an int).
  final Map<String, int> recordsByGame;
  final int cupsWon;
  final int roundsPlayed;
  final int knockouts;
  final int maxPlayersInSession;
  final StreakState streak;

  /// Fresh progress for a brand-new player.
  factory Progress.initial() => const Progress(
        coins: 0,
        ownedCosmetics: <String>{},
        selectedSkinId: kDefaultSkinId,
        recordsByGame: <String, int>{},
        cupsWon: 0,
        roundsPlayed: 0,
        knockouts: 0,
        maxPlayersInSession: 0,
        streak: StreakState.empty(),
      );

  Progress copyWith({
    int? coins,
    Set<String>? ownedCosmetics,
    String? selectedSkinId,
    Map<String, int>? recordsByGame,
    int? cupsWon,
    int? roundsPlayed,
    int? knockouts,
    int? maxPlayersInSession,
    StreakState? streak,
  }) =>
      Progress(
        coins: coins ?? this.coins,
        ownedCosmetics: ownedCosmetics ?? this.ownedCosmetics,
        selectedSkinId: selectedSkinId ?? this.selectedSkinId,
        recordsByGame: recordsByGame ?? this.recordsByGame,
        cupsWon: cupsWon ?? this.cupsWon,
        roundsPlayed: roundsPlayed ?? this.roundsPlayed,
        knockouts: knockouts ?? this.knockouts,
        maxPlayersInSession: maxPlayersInSession ?? this.maxPlayersInSession,
        streak: streak ?? this.streak,
      );

  /// Read-view adapter for the achievements layer. Distinct games played are
  /// the keys of [recordsByGame]; best streak comes from [streak].
  ProgressSnapshot toSnapshot() => ProgressSnapshot(
        roundsPlayed: roundsPlayed,
        cupsWon: cupsWon,
        knockouts: knockouts,
        gamesPlayedIds: Set<String>.of(recordsByGame.keys),
        maxPlayersInSession: maxPlayersInSession,
        bestStreak: streak.best,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Progress &&
        other.coins == coins &&
        setEquals(other.ownedCosmetics, ownedCosmetics) &&
        other.selectedSkinId == selectedSkinId &&
        mapEquals(other.recordsByGame, recordsByGame) &&
        other.cupsWon == cupsWon &&
        other.roundsPlayed == roundsPlayed &&
        other.knockouts == knockouts &&
        other.maxPlayersInSession == maxPlayersInSession &&
        other.streak == streak;
  }

  @override
  int get hashCode => Object.hash(
        coins,
        Object.hashAllUnordered(ownedCosmetics),
        selectedSkinId,
        Object.hashAllUnordered(recordsByGame.keys),
        Object.hashAllUnordered(recordsByGame.values),
        cupsWon,
        roundsPlayed,
        knockouts,
        maxPlayersInSession,
        streak,
      );
}

/// Loads and persists [Progress] over a [Persistence] store.
///
/// Every mutator applies the change to an in-memory [Progress] and writes the
/// touched key(s). Persistence failures are non-fatal (best-effort), so the
/// returned [Progress] always reflects the intended new state.
class ProgressRepository {
  ProgressRepository(this._p);

  final Persistence _p;

  /// Builds a [Progress] from the store, tolerating missing/corrupt values.
  Progress load() {
    final int coins = _p.getInt(
      ProgressKeys.coins,
      fallback: 0,
      min: 0,
      max: Economy.maxCoins,
    );
    final Set<String> owned =
        _p.getStringList(ProgressKeys.ownedCosmetics).toSet();
    final String selected = _validSkinOrDefault(
      _p.getString(ProgressKeys.selectedSkin, fallback: kDefaultSkinId),
    );
    final Map<String, int> records =
        _decodeIntMap(_p.getMap(ProgressKeys.recordsByGame));
    final int cups = _p.getInt(ProgressKeys.cupsWon, min: 0);
    final int rounds = _p.getInt(ProgressKeys.roundsPlayed, min: 0);
    final int kos = _p.getInt(ProgressKeys.knockouts, min: 0);
    final int maxPlayers = _p.getInt(ProgressKeys.maxPlayers, min: 0);
    final int streakCur = _p.getInt(ProgressKeys.streakCurrent, min: 0);
    final int streakBest = _p.getInt(ProgressKeys.streakBest, min: 0);

    return Progress(
      coins: coins,
      ownedCosmetics: owned,
      selectedSkinId: selected,
      recordsByGame: records,
      cupsWon: cups,
      roundsPlayed: rounds,
      knockouts: kos,
      maxPlayersInSession: maxPlayers,
      // best must dominate current to keep the invariant after corruption.
      streak: StreakState(
        current: streakCur,
        best: streakBest < streakCur ? streakCur : streakBest,
      ),
    );
  }

  /// Persists every field of [p]. Best-effort.
  Future<void> save(Progress p) async {
    await _p.putInt(ProgressKeys.coins, p.coins, min: 0, max: Economy.maxCoins);
    await _p.putStringList(
        ProgressKeys.ownedCosmetics, p.ownedCosmetics.toList());
    await _p.putString(ProgressKeys.selectedSkin, p.selectedSkinId);
    await _p.putMap(ProgressKeys.recordsByGame, _encodeIntMap(p.recordsByGame));
    await _p.putInt(ProgressKeys.cupsWon, p.cupsWon, min: 0);
    await _p.putInt(ProgressKeys.roundsPlayed, p.roundsPlayed, min: 0);
    await _p.putInt(ProgressKeys.knockouts, p.knockouts, min: 0);
    await _p.putInt(ProgressKeys.maxPlayers, p.maxPlayersInSession, min: 0);
    await _p.putInt(ProgressKeys.streakCurrent, p.streak.current, min: 0);
    await _p.putInt(ProgressKeys.streakBest, p.streak.best, min: 0);
  }

  // -------------------------------------------------------------------------
  // Focused mutators (apply to [current], persist touched key, return result)
  // -------------------------------------------------------------------------

  /// Adds [delta] coins (may be negative), clamped to `[0, Economy.maxCoins]`.
  Future<Progress> addCoins(Progress current, int delta) async {
    final int next = _clamp(current.coins + delta, 0, Economy.maxCoins);
    final Progress updated = current.copyWith(coins: next);
    await _p.putInt(ProgressKeys.coins, next, min: 0, max: Economy.maxCoins);
    return updated;
  }

  /// Marks [cosmeticId] owned. Unknown or already-owned ids are no-ops (the
  /// same [current] instance is returned). Free cosmetics need no unlock.
  Future<Progress> unlockCosmetic(Progress current, String cosmeticId) async {
    final Cosmetic? c = cosmeticById(cosmeticId);
    if (c == null || c.isFree || current.ownedCosmetics.contains(cosmeticId)) {
      return current;
    }
    final Set<String> next = <String>{...current.ownedCosmetics, cosmeticId};
    final Progress updated = current.copyWith(ownedCosmetics: next);
    await _p.putStringList(ProgressKeys.ownedCosmetics, next.toList());
    return updated;
  }

  /// Selects [skinId] as the active stick skin. Rejects unknown ids and ids the
  /// player does not own (free skins are always owned).
  Future<Progress> setSelectedSkin(Progress current, String skinId) async {
    final Cosmetic? c = cosmeticById(skinId);
    final bool selectable = c != null &&
        c.type == CosmeticType.stickSkin &&
        isOwned(current.ownedCosmetics, c);
    if (!selectable) return current;
    final Progress updated = current.copyWith(selectedSkinId: skinId);
    await _p.putString(ProgressKeys.selectedSkin, skinId);
    return updated;
  }

  /// Records a result for [gameId], keeping the best (highest) [value].
  /// Lower-or-equal values are ignored (no-op).
  Future<Progress> recordResult(
    Progress current,
    String gameId,
    int value,
  ) async {
    if (gameId.isEmpty) return current;
    final int prev = current.recordsByGame[gameId] ?? _kNoRecord;
    if (value <= prev) return current;
    final Map<String, int> next = <String, int>{
      ...current.recordsByGame,
      gameId: value,
    };
    final Progress updated = current.copyWith(recordsByGame: next);
    await _p.putMap(ProgressKeys.recordsByGame, _encodeIntMap(next));
    return updated;
  }

  /// Increments rounds played by [by] (defaults to 1).
  Future<Progress> incRounds(Progress current, {int by = 1}) =>
      _bumpInt(current, ProgressKeys.roundsPlayed, current.roundsPlayed, by,
          (Progress p, int v) => p.copyWith(roundsPlayed: v));

  /// Increments knockouts by [by] (defaults to 1).
  Future<Progress> incKnockouts(Progress current, {int by = 1}) =>
      _bumpInt(current, ProgressKeys.knockouts, current.knockouts, by,
          (Progress p, int v) => p.copyWith(knockouts: v));

  /// Increments cups won by [by] (defaults to 1).
  Future<Progress> incCupsWon(Progress current, {int by = 1}) =>
      _bumpInt(current, ProgressKeys.cupsWon, current.cupsWon, by,
          (Progress p, int v) => p.copyWith(cupsWon: v));

  /// Raises the recorded max players in a session if [players] is larger.
  Future<Progress> recordSessionPlayers(Progress current, int players) async {
    if (players <= current.maxPlayersInSession) return current;
    final Progress updated = current.copyWith(maxPlayersInSession: players);
    await _p.putInt(ProgressKeys.maxPlayers, players, min: 0);
    return updated;
  }

  /// Persists a new [streak] (both current and best ints).
  Future<Progress> setStreak(Progress current, StreakState streak) async {
    final Progress updated = current.copyWith(streak: streak);
    await _p.putInt(ProgressKeys.streakCurrent, streak.current, min: 0);
    await _p.putInt(ProgressKeys.streakBest, streak.best, min: 0);
    return updated;
  }

  // -------------------------------------------------------------------------
  // internals
  // -------------------------------------------------------------------------

  /// Sentinel below any real record so the first result always wins.
  static const int _kNoRecord = -1;

  /// 32-bit positive cap for unbounded counters.
  static const int _kInt32Max = 0x7fffffff;

  Future<Progress> _bumpInt(
    Progress current,
    String key,
    int currentValue,
    int by,
    Progress Function(Progress p, int v) apply,
  ) async {
    if (by <= 0) return current;
    final int next = _clamp(currentValue + by, 0, _kInt32Max);
    final Progress updated = apply(current, next);
    await _p.putInt(key, next, min: 0);
    return updated;
  }

  String _validSkinOrDefault(String id) {
    final Cosmetic? c = cosmeticById(id);
    if (c != null && c.type == CosmeticType.stickSkin) return id;
    return kDefaultSkinId;
  }

  static Map<String, int> _decodeIntMap(Map<String, dynamic> raw) {
    final Map<String, int> out = <String, int>{};
    raw.forEach((String k, dynamic v) {
      if (v is int) {
        out[k] = v;
      } else if (v is num) {
        out[k] = v.toInt();
      }
    });
    return out;
  }

  static Map<String, dynamic> _encodeIntMap(Map<String, int> src) =>
      src.map<String, dynamic>(
        (String k, int v) => MapEntry<String, dynamic>(k, v),
      );

  static int _clamp(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
