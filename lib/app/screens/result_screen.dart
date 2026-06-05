/// Result screen for a single quick-play round: a placement podium in player
/// colors, coins earned, and rematch / next-game / home actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/player_manager.dart';
import '../router.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.args});

  final ResultArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerManager players = args.players;
    final List<int> ranking = args.result.ranking;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RESULTS'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (args.coinsEarned > 0)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTokens.radius),
                      border: Border.all(color: AppColors.gold),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.monetization_on,
                            color: AppColors.gold),
                        const SizedBox(width: 8),
                        Text(
                          '+${args.coinsEarned}',
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn().scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1, 1),
                      ),
                ),
              const SizedBox(height: AppTokens.gap),
              Expanded(
                child: ListView.builder(
                  itemCount: ranking.length,
                  itemBuilder: (BuildContext context, int i) {
                    final int playerId = ranking[i];
                    final PlayerSlot? slot = _slotById(players, playerId);
                    if (slot == null) return const SizedBox.shrink();
                    final num score = args.result.finalScores[playerId] ?? 0;
                    return PodiumRow(
                      place: i + 1,
                      slot: slot,
                      trailing: '${score.round()}',
                      highlight: i == 0,
                    )
                        .animate()
                        .fadeIn(delay: (80 * i).ms)
                        .slideX(begin: 0.15, end: 0);
                  },
                ),
              ),
              const SizedBox(height: AppTokens.gap),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.pushReplacement(
                        AppRoutes.play,
                        extra: PlayArgs(
                          gameId: args.gameId,
                          players: players,
                        ),
                      ),
                      child: const Text('REMATCH'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => context.go(AppRoutes.select),
                      child: const Text('NEXT'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('HOME'),
              ),
            ],
          ),
        ),
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
