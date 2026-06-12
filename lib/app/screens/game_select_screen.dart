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
import '../../l10n/app_localizations.dart';
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PlayerManager players = ref.watch(playersSetupProvider);
    final List<MiniGameMeta> metas = allMiniGameMetas()
        .where((MiniGameMeta m) => m.supportsPlayers(players.count))
        .toList(growable: false);

    return GlassScaffold(
      title: l10n.pickAGame,
      scroll: false,
      padding: EdgeInsets.zero,
      body: metas.isEmpty
          ? Center(
              child: Text(
                l10n.noGamesForPlayerCount,
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
    final AppLocalizations l10n = AppLocalizations.of(context);
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
                  // Glyph art is seeded from the stable English name so the
                  // procedural icon stays identical across locales.
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
              localizedGameName(l10n, meta),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GlassText.heading,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: AccentTag(
                label: localizedInputHint(l10n, meta.inputHint),
                accent: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Localized display name for a game, resolved by its registry id. Falls back to
/// the English [MiniGameMeta.name] for any id without a translation key.
String localizedGameName(AppLocalizations l10n, MiniGameMeta meta) {
  switch (meta.id) {
    case 'sumo_smash':
      return l10n.game_sumo_smash;
    case 'bumper_balls':
      return l10n.game_bumper_balls;
    case 'one_touch_soccer':
      return l10n.game_one_touch_soccer;
    case 'tank_duel':
      return l10n.game_tank_duel;
    case 'archer_pop':
      return l10n.game_archer_pop;
    case 'chicken_jump':
      return l10n.game_chicken_jump;
    case 'falling_dodge':
      return l10n.game_falling_dodge;
    case 'tap_sprint':
      return l10n.game_tap_sprint;
    case 'tug_of_war':
      return l10n.game_tug_of_war;
    case 'button_masher':
      return l10n.game_button_masher;
    case 'reaction_duel':
      return l10n.game_reaction_duel;
    case 'snake_arena':
      return l10n.game_snake_arena;
    case 'paint_splash':
      return l10n.game_paint_splash;
    case 'catch_the_star':
      return l10n.game_catch_the_star;
    case 'color_memory':
      return l10n.game_color_memory;
    default:
      return meta.name;
  }
}

/// Localized input-hint chip text for a [MiniGameMeta.inputHint] value.
///
/// Handles the single-token hints (TAP / HOLD / MASH / MOVE / DRAG) plus the
/// compound "DRAG / HOLD" used by the shove games, composing it from the two
/// localized tokens. Any unrecognized hint falls back to the raw English value.
String localizedInputHint(AppLocalizations l10n, String hint) {
  switch (hint.toUpperCase()) {
    case 'TAP':
      return l10n.hint_tap;
    case 'HOLD':
      return l10n.hint_hold;
    case 'MASH':
      return l10n.hint_mash;
    case 'MOVE':
      return l10n.hint_move;
    case 'DRAG':
      return l10n.hint_drag;
    case 'DRAG / HOLD':
      return '${l10n.hint_drag} / ${l10n.hint_hold}';
    default:
      return hint;
  }
}
