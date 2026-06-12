/// Daily screen: a once-per-day login bonus (persisted via the daily-claim
/// store) and the three deterministic daily missions with progress bars.
/// Restyled glass; claim logic / providers unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meta/daily.dart';
import '../providers.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';
import 'premium_card.dart';

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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DailyClaimStore store = ref.watch(dailyClaimStoreProvider);
    final LoginBonusResult bonus = DailyService.computeLoginBonus(
      store.lastClaimDayIso,
      store.loginIndex,
      todayIso: _todayIso,
    );

    return GlassScaffold(
      title: l10n.actionDaily,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(title: l10n.loginBonus),
          _LoginBonusCard(
            bonus: bonus,
            claimed: bonus.alreadyClaimedToday,
            onClaim: () => _claim(bonus),
          ),
          const SizedBox(height: 24),
          SectionHeader(title: l10n.todaysMissions, color: GlassColors.cyan),
          ..._missions.map((DailyMission m) => _MissionTile(mission: m)),
        ],
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {}); // refresh claim state
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          coins > 0 ? l10n.claimedCoins(coins) : l10n.rewardClaimed,
        ),
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isCoins = bonus.reward.kind == LoginRewardKind.coins;
    return PremiumPanel(
      accent: GlassColors.amber,
      highlight: true,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          _RewardBadge(
            icon: isCoins ? Icons.monetization_on : Icons.checkroom,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.dayN(bonus.dayIndex + 1), style: GlassText.overline),
                const SizedBox(height: 3),
                Text(
                  isCoins
                      ? l10n.coinsAmount(bonus.reward.amount)
                      : l10n.cosmeticReward(bonus.reward.amount),
                  style: GlassText.heading,
                ),
                const SizedBox(height: 3),
                Text(
                  claimed ? l10n.comeBackTomorrow : l10n.tapClaimToCollect,
                  style: GlassText.body.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: claimed ? null : onClaim,
            style: FilledButton.styleFrom(
              backgroundColor: GlassColors.amber,
              foregroundColor: GlassColors.base,
              minimumSize: const Size(96, 44),
            ),
            child: Text(claimed ? l10n.claimed : l10n.claim),
          ),
        ],
      ),
    );
  }
}

/// The amber illustration badge for the login-bonus card.
class _RewardBadge extends StatelessWidget {
  const _RewardBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kPremiumTileArtSize,
      height: kPremiumTileArtSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            GlassColors.amber,
            GlassColors.amber.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: GlassColors.amber.withValues(alpha: 0.45),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: GlassColors.base, size: 28),
    );
  }
}

class _MissionTile extends StatelessWidget {
  const _MissionTile({required this.mission});

  final DailyMission mission;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.gap),
      child: PremiumPanel(
        accent: GlassColors.cyan,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(_label(l10n, mission), style: GlassText.heading),
                ),
                AccentTag(
                  label: '+${mission.rewardCoins}',
                  accent: GlassColors.amber,
                  icon: Icons.monetization_on,
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
      ),
    );
  }

  String _label(AppLocalizations l10n, DailyMission m) {
    switch (m.type) {
      case DailyMissionType.playRounds:
        return l10n.missionPlayRounds(m.target);
      case DailyMissionType.winRounds:
        return l10n.missionWinRounds(m.target);
      case DailyMissionType.winCup:
        return l10n.missionWinCup;
      case DailyMissionType.tryNewGame:
        return l10n.missionTryNewGame;
      case DailyMissionType.playWithFriends:
        return l10n.missionPlayWithPlayers(m.target);
    }
  }
}

