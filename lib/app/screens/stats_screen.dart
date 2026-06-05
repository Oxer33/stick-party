/// Stats screen: lifetime progress counters, per-game best records, and the
/// achievement list (locked / unlocked) computed from a progress snapshot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/registry.dart';
import '../../meta/achievements.dart';
import '../../meta/progress_store.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Progress progress = ref.watch(progressProvider);
    final ProgressSnapshot snapshot = progress.toSnapshot();
    final int unlocked = unlockedCount(snapshot);

    return Scaffold(
      appBar: AppBar(title: const Text('STATS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          children: <Widget>[
            const SectionHeader(title: 'CAREER'),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                StatTile(
                  value: '${progress.coins}',
                  caption: 'Coins',
                  color: AppColors.gold,
                ),
                StatTile(
                  value: '${progress.roundsPlayed}',
                  caption: 'Rounds played',
                ),
                StatTile(
                  value: '${progress.cupsWon}',
                  caption: 'Cups won',
                  color: AppColors.secondary,
                ),
                StatTile(
                  value: '${progress.knockouts}',
                  caption: 'Knockouts',
                  color: AppColors.flame,
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (progress.recordsByGame.isNotEmpty) ...<Widget>[
              const SectionHeader(
                  title: 'BEST SCORES', color: AppColors.secondary),
              ..._recordRows(progress),
              const SizedBox(height: 24),
            ],
            SectionHeader(
              title: 'ACHIEVEMENTS  $unlocked/$achievementCount',
              color: AppColors.gold,
            ),
            ...kAchievements.map(
              (Achievement a) => _AchievementTile(
                achievement: a,
                snapshot: snapshot,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _recordRows(Progress progress) {
    final List<Widget> rows = <Widget>[];
    progress.recordsByGame.forEach((String gameId, int value) {
      rows.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTokens.radius),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _gameName(gameId),
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    });
    return rows;
  }

  /// Resolve a friendly game name from the registry, tolerating unknown ids.
  String _gameName(String gameId) {
    try {
      return createMiniGame(gameId).meta.name;
    } catch (_) {
      return gameId;
    }
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.achievement, required this.snapshot});

  final Achievement achievement;
  final ProgressSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final bool unlocked = achievement.isUnlocked(snapshot);
    final int current = achievement.currentProgress(snapshot);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(
          color: unlocked ? AppColors.gold : AppColors.surfaceHigh,
          width: unlocked ? 2 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            unlocked ? Icons.emoji_events : Icons.lock_outline,
            color: unlocked ? AppColors.gold : AppColors.onSurfaceMuted,
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  achievement.name,
                  style: TextStyle(
                    color: unlocked
                        ? AppColors.onSurface
                        : AppColors.onSurfaceMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: const TextStyle(
                    color: AppColors.onSurfaceMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                LabeledProgressBar(
                  fraction: achievement.progressFraction(snapshot),
                  label: '$current/${achievement.threshold}',
                  color: unlocked ? AppColors.gold : AppColors.secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
