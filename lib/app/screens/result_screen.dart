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
import '../widgets/game_glyphs.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';
import 'premium_card.dart';

class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.args});

  final ResultArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerManager players = args.players;
    final List<int> ranking = args.result.ranking;
    final PlayerSlot? winner =
        ranking.isEmpty ? null : _slotById(players, ranking.first);

    return GlassScaffold(
      title: 'RESULTS',
      showBack: false,
      scroll: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (winner != null)
            _WinnerBanner(
              winner: winner,
              gameId: args.gameId,
              score: args.result.finalScores[winner.id]?.round() ?? 0,
              coinsEarned: args.coinsEarned,
            ),
          const SizedBox(height: GlassTokens.gap),
          Expanded(
            child: ListView.builder(
              // Places 2..n live in the list; the winner is the hero banner.
              itemCount: ranking.length > 1 ? ranking.length - 1 : 0,
              itemBuilder: (BuildContext context, int i) {
                final int rank = i + 1; // 0-based index into the runners-up
                final int playerId = ranking[rank];
                final PlayerSlot? slot = _slotById(players, playerId);
                if (slot == null) return const SizedBox.shrink();
                final num score = args.result.finalScores[playerId] ?? 0;
                return PodiumRow(
                  place: rank + 1,
                  slot: slot,
                  trailing: '${score.round()}',
                )
                    .animate()
                    .fadeIn(delay: (GlassTokens.stagger * rank))
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

/// The celebratory winner hero: the played game's glyph crowned with a trophy,
/// the winner's name in their color, their score and (when earned) the coins
/// from this round — all on a strongly-tinted premium panel that pops in.
class _WinnerBanner extends StatelessWidget {
  const _WinnerBanner({
    required this.winner,
    required this.gameId,
    required this.score,
    required this.coinsEarned,
  });

  final PlayerSlot winner;
  final String gameId;
  final int score;
  final int coinsEarned;

  /// Edge length of the crowned game glyph.
  static const double _glyphSize = 72;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(winner.colorArgb);
    return PremiumPanel(
      accent: color,
      highlight: true,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        children: <Widget>[
          _crownedGlyph(color),
          const SizedBox(height: 10),
          Text('WINNER', style: GlassText.overline.copyWith(letterSpacing: 4)),
          const SizedBox(height: 4),
          Text(
            winner.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GlassText.display.copyWith(
              fontSize: 30,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AccentTag(
                label: '$score PTS',
                accent: color,
                icon: Icons.military_tech,
              ),
              if (coinsEarned > 0) ...<Widget>[
                const SizedBox(width: GlassTokens.gapSmall),
                AccentTag(
                  label: '+$coinsEarned',
                  accent: GlassColors.amber,
                  icon: Icons.monetization_on,
                ),
              ],
            ],
          ),
        ],
      ),
    ).animate().fadeIn().scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1, 1),
          curve: Curves.easeOutBack,
          duration: 500.ms,
        );
  }

  /// The game glyph with a trophy badge tucked into its top-right corner.
  Widget _crownedGlyph(Color color) {
    return SizedBox(
      width: _glyphSize + 14,
      height: _glyphSize + 8,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          GameGlyph(
            id: gameId,
            label: gameId,
            colorArgb: winner.colorArgb,
            size: _glyphSize,
          ),
          Positioned(
            top: -6,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: GlassColors.amber,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: GlassColors.amber.withValues(alpha: 0.6),
                    blurRadius: 10,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.emoji_events,
                color: GlassColors.base,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
