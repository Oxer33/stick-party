/// Stats screen: lifetime progress counters, per-game best records, and the
/// achievement list (locked / unlocked) computed from a progress snapshot.
/// Restyled glass; providers / logic unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/registry.dart';
import '../../meta/achievements.dart';
import '../../meta/progress_store.dart';
import '../providers.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Progress progress = ref.watch(progressProvider);
    final ProgressSnapshot snapshot = progress.toSnapshot();
    final int unlocked = unlockedCount(snapshot);

    return GlassScaffold(
      title: 'STATS',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'CAREER'),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: GlassTokens.gapSmall,
            crossAxisSpacing: GlassTokens.gapSmall,
            childAspectRatio: 1.7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              StatTile(
                value: '${progress.coins}',
                caption: 'Coins',
                color: GlassColors.amber,
              ),
              StatTile(
                value: '${progress.roundsPlayed}',
                caption: 'Rounds played',
              ),
              StatTile(
                value: '${progress.cupsWon}',
                caption: 'Cups won',
                color: GlassColors.cyan,
              ),
              StatTile(
                value: '${progress.knockouts}',
                caption: 'Knockouts',
                color: GlassColors.flame,
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (progress.recordsByGame.isNotEmpty) ...<Widget>[
            const SectionHeader(title: 'BEST SCORES', color: GlassColors.cyan),
            ..._recordRows(progress),
            const SizedBox(height: 24),
          ],
          SectionHeader(
            title: 'ACHIEVEMENTS  $unlocked/$achievementCount',
            color: GlassColors.amber,
          ),
          ...kAchievements.map(
            (Achievement a) => _AchievementTile(
              achievement: a,
              snapshot: snapshot,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _recordRows(Progress progress) {
    final List<Widget> rows = <Widget>[];
    progress.recordsByGame.forEach((String gameId, int value) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _gameName(gameId),
                    style:
                        GlassText.heading.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '$value',
                  style: const TextStyle(
                    color: GlassColors.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.gap),
      child: GlassPanel(
        tint: unlocked ? GlassColors.amber : null,
        tintOpacity: 0.12,
        borderColor: unlocked ? GlassColors.amber.withValues(alpha: 0.7) : null,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(
              unlocked ? Icons.emoji_events : Icons.lock_outline,
              color: unlocked ? GlassColors.amber : GlassColors.textMuted,
              size: 32,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    achievement.name,
                    style: GlassText.heading.copyWith(
                      color:
                          unlocked ? GlassColors.text : GlassColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    achievement.description,
                    style: GlassText.body.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  LabeledProgressBar(
                    fraction: achievement.progressFraction(snapshot),
                    label: '$current/${achievement.threshold}',
                    color: unlocked ? GlassColors.amber : GlassColors.cyan,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
