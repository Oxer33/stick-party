/// Stats screen: lifetime progress counters, per-game best records, and the
/// achievement list (locked / unlocked) computed from a progress snapshot.
/// Restyled glass; providers / logic unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/registry.dart';
import '../../l10n/app_localizations.dart';
import '../../meta/achievements.dart';
import '../../meta/progress_store.dart';
import '../providers.dart';
import '../widgets/game_glyphs.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';
import 'premium_card.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Progress progress = ref.watch(progressProvider);
    final ProgressSnapshot snapshot = progress.toSnapshot();
    final int unlocked = unlockedCount(snapshot);

    return GlassScaffold(
      title: l10n.actionStats,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(title: l10n.statsCareer),
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
                caption: l10n.statCoins,
                color: GlassColors.amber,
              ),
              StatTile(
                value: '${progress.roundsPlayed}',
                caption: l10n.statRoundsPlayed,
              ),
              StatTile(
                value: '${progress.cupsWon}',
                caption: l10n.statCupsWon,
                color: GlassColors.cyan,
              ),
              StatTile(
                value: '${progress.knockouts}',
                caption: l10n.statKnockouts,
                color: GlassColors.flame,
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (progress.recordsByGame.isNotEmpty) ...<Widget>[
            SectionHeader(title: l10n.statsBestScores, color: GlassColors.cyan),
            ..._recordRows(l10n, progress),
            const SizedBox(height: 24),
          ],
          SectionHeader(
            title: l10n.statsAchievements(unlocked, achievementCount),
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

  List<Widget> _recordRows(AppLocalizations l10n, Progress progress) {
    final List<Widget> rows = <Widget>[];
    progress.recordsByGame.forEach((String gameId, int value) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: GlassTokens.gapSmall),
          child: PremiumMediaTile(
            accent: GlassColors.cyan,
            leading: GameGlyph(
              id: gameId,
              label: _gameName(gameId),
              colorArgb: GlassColors.cyan.toARGB32(),
              size: 44,
            ),
            title: _gameName(gameId),
            supporting: l10n.statBestScore,
            trailing: Text(
              '$value',
              style: const TextStyle(
                color: GlassColors.cyan,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
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
    final Color accent = unlocked ? GlassColors.amber : GlassColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.gap),
      child: PremiumPanel(
        accent: accent,
        highlight: unlocked,
        glow: unlocked,
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
