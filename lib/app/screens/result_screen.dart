/// Result screen for a single quick-play round: a placement podium in player
/// colors, coins earned, and rematch / next-game / home actions. Restyled glass;
/// logic/nav unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/player_manager.dart';
import '../router.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';

class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.args});

  final ResultArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerManager players = args.players;
    final List<int> ranking = args.result.ranking;

    return GlassScaffold(
      title: 'RESULTS',
      showBack: false,
      scroll: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (args.coinsEarned > 0)
            Center(child: _CoinsEarned(coins: args.coinsEarned)),
          const SizedBox(height: GlassTokens.gap),
          Expanded(
            child: ListView.builder(
              itemCount: ranking.length,
              itemBuilder: (BuildContext context, int i) {
                final int playerId = ranking[i];
                final PlayerSlot? slot = _slotById(players, playerId);
                if (slot == null) return const SizedBox.shrink();
                final num score = args.result.finalScores[playerId] ?? 0;
                final Widget row = PodiumRow(
                  place: i + 1,
                  slot: slot,
                  trailing: '${score.round()}',
                  highlight: i == 0,
                );
                // Winner gets a subtle bounce; others slide in staggered.
                if (i == 0) {
                  return row.animate().fadeIn().scale(
                        begin: const Offset(0.85, 0.85),
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack,
                        duration: 500.ms,
                      );
                }
                return row
                    .animate()
                    .fadeIn(delay: (GlassTokens.stagger * i))
                    .slideX(begin: 0.15, end: 0);
              },
            ),
          ),
          const SizedBox(height: GlassTokens.gap),
          Row(
            children: <Widget>[
              Expanded(
                child: GlassButton(
                  label: 'REMATCH',
                  icon: Icons.refresh,
                  onTap: () => context.pushReplacement(
                    AppRoutes.play,
                    extra: PlayArgs(gameId: args.gameId, players: players),
                  ),
                ),
              ),
              const SizedBox(width: GlassTokens.gapSmall),
              Expanded(
                child: GlassButton(
                  label: 'NEXT',
                  icon: Icons.grid_view_rounded,
                  primary: true,
                  onTap: () => context.go(AppRoutes.select),
                ),
              ),
            ],
          ),
          const SizedBox(height: GlassTokens.gapSmall),
          TextButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('HOME'),
          ),
        ],
      ),
    );
  }

  PlayerSlot? _slotById(PlayerManager players, int id) {
    for (final PlayerSlot s in players.slots) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// A frosted amber chip announcing coins earned this round.
class _CoinsEarned extends StatelessWidget {
  const _CoinsEarned({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      tint: GlassColors.amber,
      tintOpacity: 0.16,
      borderColor: GlassColors.amber.withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.monetization_on, color: GlassColors.amber),
          const SizedBox(width: 8),
          Text(
            '+$coins',
            style: const TextStyle(
              color: GlassColors.amber,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale(
          begin: const Offset(0.8, 0.8),
          end: const Offset(1, 1),
        );
  }
}
