/// Daily screen: a once-per-day login bonus (persisted via the daily-claim
/// store) and the three deterministic daily missions with progress bars.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../meta/daily.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class DailyScreen extends ConsumerStatefulWidget {
  const DailyScreen({super.key});

  @override
  ConsumerState<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends ConsumerState<DailyScreen> {
  late String _todayIso;
  late List<DailyMission> _missions;

  @override
  void initState() {
    super.initState();
    _todayIso = DailyService.isoForDate(DateTime.now());
    _missions = DailyService.generateForDay(_todayIso);
  }

  bool get _claimedToday =>
      ref.read(dailyClaimStoreProvider).lastClaimDayIso == _todayIso;

  @override
  Widget build(BuildContext context) {
    final DailyClaimStore store = ref.watch(dailyClaimStoreProvider);
    final LoginBonusResult bonus = DailyService.computeLoginBonus(
      store.lastClaimDayIso,
      store.loginIndex,
      todayIso: _todayIso,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('DAILY')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          children: <Widget>[
            const SectionHeader(title: 'LOGIN BONUS'),
            _LoginBonusCard(
              bonus: bonus,
              claimed: bonus.alreadyClaimedToday,
              onClaim: () => _claim(bonus),
            ),
            const SizedBox(height: 24),
            const SectionHeader(
                title: "TODAY'S MISSIONS", color: AppColors.secondary),
            ..._missions.map((DailyMission m) => _MissionTile(mission: m)),
          ],
        ),
      ),
    );
  }

  Future<void> _claim(LoginBonusResult bonus) async {
    if (_claimedToday) return;

    final int coins = _coinsFor(bonus.reward);
    if (coins > 0) {
      await ref.read(progressProvider.notifier).addCoins(coins);
    }
    // Advance the cycle index and record today's claim.
    final DailyClaimStore store = ref.read(dailyClaimStoreProvider);
    await store.markClaimed(_todayIso, store.loginIndex + 1);

    if (!mounted) return;
    setState(() {}); // refresh claim state
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(coins > 0 ? 'Claimed +$coins coins!' : 'Reward claimed!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Coins granted for a reward. Cosmetic-token days have no token model in the
  /// MVP, so they pay out an equivalent coin amount instead (honest, no loss).
  int _coinsFor(LoginReward reward) {
    switch (reward.kind) {
      case LoginRewardKind.coins:
        return reward.amount;
      case LoginRewardKind.cosmeticToken:
        return reward.amount * DailyService.loginCycle.first.amount;
    }
  }
}

class _LoginBonusCard extends StatelessWidget {
  const _LoginBonusCard({
    required this.bonus,
    required this.claimed,
    required this.onClaim,
  });

  final LoginBonusResult bonus;
  final bool claimed;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final bool isCoins = bonus.reward.kind == LoginRewardKind.coins;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppColors.gold),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isCoins ? Icons.monetization_on : Icons.checkroom,
            color: AppColors.gold,
            size: 40,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Day ${bonus.dayIndex + 1}',
                  style: const TextStyle(
                    color: AppColors.onSurfaceMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isCoins
                      ? '+${bonus.reward.amount} coins'
                      : '${bonus.reward.amount} cosmetic reward',
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: claimed ? null : onClaim,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: const Color(0xFF231A00),
              minimumSize: const Size(96, 44),
            ),
            child: Text(claimed ? 'CLAIMED' : 'CLAIM'),
          ),
        ],
      ),
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({required this.mission});

  final DailyMission mission;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppColors.surfaceHigh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _label(mission),
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '+${mission.rewardCoins}',
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LabeledProgressBar(
            fraction: mission.progressFraction,
            label: '${mission.progress}/${mission.target}',
          ),
        ],
      ),
    );
  }

  String _label(DailyMission m) {
    switch (m.type) {
      case DailyMissionType.playRounds:
        return 'Play ${m.target} rounds';
      case DailyMissionType.winRounds:
        return 'Win ${m.target} rounds';
      case DailyMissionType.winCup:
        return 'Win a cup';
      case DailyMissionType.tryNewGame:
        return 'Try a new game';
      case DailyMissionType.playWithFriends:
        return 'Play with ${m.target} players';
    }
  }
}
