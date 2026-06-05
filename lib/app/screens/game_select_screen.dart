/// Game select: a grid of mini-games supported by the current player count.
/// Tapping a card launches that game for a single quick-play round.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../engine/registry.dart';
import '../providers.dart';
import '../router.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class GameSelectScreen extends ConsumerWidget {
  const GameSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerManager players = ref.watch(playersSetupProvider);
    final List<MiniGameMeta> metas = allMiniGameMetas()
        .where((MiniGameMeta m) => m.supportsPlayers(players.count))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('PICK A GAME')),
      body: SafeArea(
        child: metas.isEmpty
            ? const Center(
                child: Text('No games for this player count.'),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(AppTokens.pagePadding),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.95,
                ),
                itemCount: metas.length,
                itemBuilder: (BuildContext context, int i) {
                  final MiniGameMeta meta = metas[i];
                  return _GameCard(
                    meta: meta,
                    colorArgb:
                        PlayerPalette.argb[i % PlayerPalette.argb.length],
                    onTap: () => context.push(
                      AppRoutes.play,
                      extra: PlayArgs(gameId: meta.id, players: players),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.meta,
    required this.colorArgb,
    required this.onTap,
  });

  final MiniGameMeta meta;
  final int colorArgb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: Border.all(color: AppColors.surfaceHigh),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ProceduralIcon(label: meta.name, colorArgb: colorArgb, size: 56),
            const Spacer(),
            Text(
              meta.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Color(colorArgb).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                meta.inputHint,
                style: TextStyle(
                  color: Color(colorArgb),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
