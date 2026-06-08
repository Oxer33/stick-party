/// Game select: a grid of mini-games supported by the current player count.
/// Tapping a card launches that game for a single quick-play round. The grid is
/// a polished game picker: each card has a distinct procedural [GameGlyph], the
/// game name, the supported player-count range and the input-hint chip, an
/// accent edge + glow and a tap press-scale. Logic/nav unchanged.
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
import '../widgets/game_glyphs.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import 'premium_card.dart';

/// Glyph size inside a game card.
const double _kGlyphSize = 60;

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
                mainAxisSpacing: GlassTokens.gap,
                crossAxisSpacing: GlassTokens.gap,
                childAspectRatio: 0.82,
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

/// One game tile: glyph illustration, name, player-range + input-hint chips,
/// accent edge + glow, press-scale on tap.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.meta,
    required this.colorArgb,
    required this.onTap,
  });

  final MiniGameMeta meta;
  final int colorArgb;
  final VoidCallback onTap;

  /// "1-4" / "2-4" / "3" depending on the meta's supported range.
  String get _playerRange => meta.minPlayers == meta.maxPlayers
      ? '${meta.minPlayers}'
      : '${meta.minPlayers}-${meta.maxPlayers}';

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(colorArgb);
    return PressableCard(
      onTap: onTap,
      child: PremiumPanel(
        accent: accent,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                GameGlyph(
                  id: meta.id,
                  label: meta.name,
                  colorArgb: colorArgb,
                  size: _kGlyphSize,
                ),
                const Spacer(),
                AccentTag(
                  label: _playerRange,
                  accent: accent,
                  icon: Icons.person,
                ),
              ],
            ),
            const Spacer(),
            Text(
              meta.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GlassText.heading,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AccentTag(label: meta.inputHint, accent: accent),
            ),
          ],
        ),
      ),
    );
  }
}
