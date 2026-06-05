/// Daily engagement: a progressive login bonus and a deterministic set of
/// daily missions derived from the calendar date (ISO `YYYY-MM-DD`).
///
/// Everything here is PURE: same ISO string ⇒ same missions and same bonus.
/// Persistence (which day was last claimed, mission progress) lives in the
/// repository layer.
library;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/rng.dart';

/// Length of a valid ISO date string `YYYY-MM-DD`.
const int kIsoDateLength = 10;

/// Number of distinct daily missions generated per day.
const int kDailyMissionCount = 3;

/// Length of the rotating login-bonus cycle.
const int kLoginBonusCycleDays = 7;

// ---------------------------------------------------------------------------
// Login bonus
// ---------------------------------------------------------------------------

/// What a single login-bonus day grants.
enum LoginRewardKind { coins, cosmeticToken }

/// One day of the login-bonus cycle. Immutable value.
@immutable
class LoginReward {
  const LoginReward({
    required this.kind,
    required this.amount,
  }) : assert(amount >= 0, 'amount must be >= 0');

  final LoginRewardKind kind;

  /// Coins when [kind] is coins; number of cosmetic-unlock tokens otherwise.
  final int amount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LoginReward && other.kind == kind && other.amount == amount;
  }

  @override
  int get hashCode => Object.hash(kind, amount);

  @override
  String toString() => 'LoginReward(${kind.name}, $amount)';
}

/// Result of evaluating the login bonus for a given day.
@immutable
class LoginBonusResult {
  const LoginBonusResult({
    required this.dayIndex,
    required this.reward,
    required this.alreadyClaimedToday,
  });

  /// 0-based slot within the [kLoginBonusCycleDays] cycle.
  final int dayIndex;

  /// Reward for [dayIndex].
  final LoginReward reward;

  /// True when [DailyService.computeLoginBonus] decided today was already
  /// granted (same ISO day).
  final bool alreadyClaimedToday;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LoginBonusResult &&
        other.dayIndex == dayIndex &&
        other.reward == reward &&
        other.alreadyClaimedToday == alreadyClaimedToday;
  }

  @override
  int get hashCode => Object.hash(dayIndex, reward, alreadyClaimedToday);
}

// ---------------------------------------------------------------------------
// Missions
// ---------------------------------------------------------------------------

enum DailyMissionType {
  playRounds,
  winRounds,
  winCup,
  tryNewGame,
  playWithFriends,
}

@immutable
class DailyMission {
  const DailyMission({
    required this.id,
    required this.type,
    required this.target,
    required this.progress,
    required this.rewardCoins,
    required this.completed,
    required this.claimed,
  })  : assert(target > 0, 'target must be > 0'),
        assert(progress >= 0, 'progress must be >= 0'),
        assert(rewardCoins >= 0, 'rewardCoins must be >= 0');

  final String id;
  final DailyMissionType type;
  final int target;
  final int progress;
  final int rewardCoins;
  final bool completed;
  final bool claimed;

  /// Progress as a [0, 1] fraction for UI bars.
  double get progressFraction =>
      target <= 0 ? 1.0 : (progress / target).clamp(0.0, 1.0);

  DailyMission copyWith({
    int? progress,
    bool? completed,
    bool? claimed,
  }) =>
      DailyMission(
        id: id,
        type: type,
        target: target,
        progress: progress ?? this.progress,
        rewardCoins: rewardCoins,
        completed: completed ?? this.completed,
        claimed: claimed ?? this.claimed,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'target': target,
        'progress': progress,
        'rewardCoins': rewardCoins,
        'completed': completed,
        'claimed': claimed,
      };

  /// Rebuilds a mission from a stored map, clamping/coercing corrupt values.
  factory DailyMission.fromMap(Map<dynamic, dynamic> map) {
    final int parsedTarget = (map['target'] as num?)?.toInt() ?? 1;
    final int safeTarget = parsedTarget < 1 ? 1 : parsedTarget;
    final int parsedProgress = (map['progress'] as num?)?.toInt() ?? 0;
    final int safeProgress = parsedProgress < 0
        ? 0
        : (parsedProgress > safeTarget ? safeTarget : parsedProgress);
    final int parsedReward = (map['rewardCoins'] as num?)?.toInt() ?? 0;
    return DailyMission(
      id: map['id'] as String? ?? '',
      type: DailyMissionType.values.firstWhere(
        (DailyMissionType t) => t.name == map['type'],
        orElse: () => DailyMissionType.playRounds,
      ),
      target: safeTarget,
      progress: safeProgress,
      rewardCoins: parsedReward < 0 ? 0 : parsedReward,
      completed: map['completed'] as bool? ?? false,
      claimed: map['claimed'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DailyMission &&
        other.id == id &&
        other.type == type &&
        other.target == target &&
        other.progress == progress &&
        other.rewardCoins == rewardCoins &&
        other.completed == completed &&
        other.claimed == claimed;
  }

  @override
  int get hashCode => Object.hash(
        id,
        type,
        target,
        progress,
        rewardCoins,
        completed,
        claimed,
      );
}

/// Pure daily-content generator. No persistence, no side effects.
class DailyService {
  DailyService._();

  /// Fixed 7-day login cycle. Days 3 and 6 grant cosmetic-unlock tokens; the
  /// rest grant escalating coins built off [Economy.coinsPerRoundWin].
  static const List<LoginReward> loginCycle = <LoginReward>[
    LoginReward(kind: LoginRewardKind.coins, amount: Economy.coinsPerRoundWin),
    LoginReward(
        kind: LoginRewardKind.coins, amount: Economy.coinsPerRoundWin * 2),
    LoginReward(kind: LoginRewardKind.cosmeticToken, amount: 1),
    LoginReward(
        kind: LoginRewardKind.coins, amount: Economy.coinsPerRoundWin * 3),
    LoginReward(kind: LoginRewardKind.coins, amount: Economy.coinsPerCupWin),
    LoginReward(kind: LoginRewardKind.cosmeticToken, amount: 1),
    LoginReward(
        kind: LoginRewardKind.coins, amount: Economy.coinsPerCupWin * 2),
  ];

  /// Computes today's login bonus.
  ///
  /// [lastDayIso] is the ISO date the bonus was last granted ('' if never).
  /// [streakIndex] is the login-day counter the caller is tracking (0-based for
  /// the very first claim). The reward slot rotates over [kLoginBonusCycleDays].
  ///
  /// When [todayIso] equals [lastDayIso] the result is flagged
  /// [LoginBonusResult.alreadyClaimedToday] so the caller can skip granting.
  static LoginBonusResult computeLoginBonus(
    String lastDayIso,
    int streakIndex, {
    String? todayIso,
  }) {
    final String today = todayIso ?? isoForDate(DateTime.now());
    final int cycleLen = loginCycle.length;
    // Defensive: cycle is non-empty by construction, but guard div-by-zero.
    final int safeLen = cycleLen == 0 ? 1 : cycleLen;
    final int safeIndex = streakIndex < 0 ? 0 : streakIndex;
    final int slot = safeIndex % safeLen;
    final LoginReward reward = cycleLen == 0
        ? const LoginReward(kind: LoginRewardKind.coins, amount: 0)
        : loginCycle[slot];
    return LoginBonusResult(
      dayIndex: slot,
      reward: reward,
      alreadyClaimedToday: lastDayIso == today,
    );
  }

  /// Builds the deterministic mission set for [iso].
  ///
  /// The RNG is seeded from the ISO string hash, so a given date always yields
  /// the same three missions on every device.
  static List<DailyMission> generateForDay(String iso) {
    final SeededRng rng = SeededRng(_seedFromIso(iso));
    final List<_MissionTemplate> pool = List<_MissionTemplate>.of(_pool);
    _shuffleDeterministic(pool, rng);
    final int take =
        pool.length < kDailyMissionCount ? pool.length : kDailyMissionCount;
    return List<DailyMission>.generate(
      take,
      (int i) {
        final _MissionTemplate t = pool[i];
        return DailyMission(
          id: '$iso#$i',
          type: t.type,
          target: t.target,
          progress: 0,
          rewardCoins: t.rewardCoins,
          completed: false,
          claimed: false,
        );
      },
      growable: false,
    );
  }

  /// Advances every mission of [type] by [inc], flagging completion. Returns a
  /// new list (immutable). Non-positive [inc] is a no-op (returns input).
  static List<DailyMission> applyEvent(
    List<DailyMission> missions,
    DailyMissionType type,
    int inc,
  ) {
    if (inc <= 0) return missions;
    return missions.map((DailyMission m) {
      if (m.type != type || m.completed) return m;
      final int nextProgress = (m.progress + inc).clamp(0, m.target);
      final bool nowCompleted = nextProgress >= m.target;
      return m.copyWith(progress: nextProgress, completed: nowCompleted);
    }).toList(growable: false);
  }

  /// ISO `YYYY-MM-DD` for [d] in its local calendar day.
  static String isoForDate(DateTime d) {
    final String yy = d.year.toString().padLeft(4, '0');
    final String mm = d.month.toString().padLeft(2, '0');
    final String dd = d.day.toString().padLeft(2, '0');
    return '$yy-$mm-$dd';
  }

  // -------------------------------------------------------------------------
  // internals
  // -------------------------------------------------------------------------

  /// 31-bit positive rolling hash of [iso] for use as an RNG seed. Applied per
  /// char with a mask so the fold never overflows on long inputs.
  static int _seedFromIso(String iso) {
    int acc = 0;
    for (final int c in iso.codeUnits) {
      acc = (acc * 31 + c) & 0x7fffffff;
    }
    return acc;
  }

  /// Fisher–Yates shuffle driven by [SeededRng] for deterministic ordering.
  static void _shuffleDeterministic(
    List<_MissionTemplate> list,
    SeededRng rng,
  ) {
    for (int i = list.length - 1; i > 0; i--) {
      final int j = rng.intRange(0, i + 1);
      final _MissionTemplate tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }

  static const List<_MissionTemplate> _pool = <_MissionTemplate>[
    _MissionTemplate(
      type: DailyMissionType.playRounds,
      target: 5,
      rewardCoins: Economy.coinsPerRoundWin,
    ),
    _MissionTemplate(
      type: DailyMissionType.winRounds,
      target: 3,
      rewardCoins: Economy.coinsPerRoundWin * 2,
    ),
    _MissionTemplate(
      type: DailyMissionType.winCup,
      target: 1,
      rewardCoins: Economy.coinsPerCupWin,
    ),
    _MissionTemplate(
      type: DailyMissionType.tryNewGame,
      target: 1,
      rewardCoins: Economy.coinsPerRoundWin,
    ),
    _MissionTemplate(
      type: DailyMissionType.playWithFriends,
      target: 2,
      rewardCoins: Economy.coinsPerRoundWin * 2,
    ),
  ];
}

@immutable
class _MissionTemplate {
  const _MissionTemplate({
    required this.type,
    required this.target,
    required this.rewardCoins,
  });

  final DailyMissionType type;
  final int target;
  final int rewardCoins;
}
