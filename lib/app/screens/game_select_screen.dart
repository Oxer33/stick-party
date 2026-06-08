/// Game select: a grid of mini-games supported by the current player count.
/// Tapping a card launches that game for a single quick-play round. Restyled as
/// glass cards; logic/nav unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../engine/registry.dart';
import '../providers.dart';
import '../router.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';

class GameSelectScreen extends ConsumerWidget {
  const GameSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerManager players = ref.watch(playersSetupProvider);
    final List<MiniGameMeta> metas = allMiniGameMetas()
        .where((MiniGameMeta m) => m.supportsPlayers(players.count))
        .toList(growable: false);

    return GlassScaffold(
      title: 'PICK A GAME',
      scroll: false,
      padding: EdgeInsets.zero,
      body: metas.isEmpty
          ? Center(
              child: Text(
                'No games for this player count.',
                style: GlassText.body,
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(GlassTokens.pagePadding),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: GlassTokens.gapSmall,
                crossAxisSpacing: GlassTokens.gapSmall,
                childAspectRatio: 0.95,
              ),
              itemCount: metas.length,
              itemBuilder: (BuildContext context, int i) {
                final MiniGameMeta meta = metas[i];
                return _GameCard(
                  meta: meta,
                  colorArgb: PlayerPalette.argb[i % PlayerPalette.argb.length],
                  onTap: () => context.push(
                    AppRoutes.play,
                    // A lone human always gets one CPU opponent so every game
                    // (sumo, soccer, …) makes sense played solo.
                    extra: PlayArgs(
                      gameId: meta.id,
                      players: players.count == 1
                          ? players.addSlot(isBot: true)
                          : players,
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(delay: (GlassTokens.stagger * (i % 6)))
                    .slideY(begin: 0.18, end: 0, curve: Curves.easeOutCubic);
              },
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
    final Color accent = Color(colorArgb);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassPanel(
        tint: accent,
        tintOpacity: 0.08,
        borderColor: accent.withValues(alpha: 0.4),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ProceduralIcon(label: meta.name, colorArgb: colorArgb, size: 56),
            const Spacer(),
            Text(
              meta.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GlassText.heading,
            ),
            const SizedBox(height: 8),
            _HintChip(label: meta.inputHint, accent: accent),
          ],
        ),
      ),
    );
  }
}

/// A small accent-tinted pill for a game's input hint (TAP / HOLD / MASH).
class _HintChip extends StatelessWidget {
  const _HintChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
