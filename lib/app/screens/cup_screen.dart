/// Cup screen: runs a tournament of several mini-games one at a time, showing a
/// standings panel between games (with an optional house-ad / stub interstitial,
/// NEVER during a game) and a champion podium at the end.
///
/// The cup controller logic and the ad / house-ad gating are unchanged from the
/// original; only the presentation (standings, between-game card, champion) is
/// restyled with glass.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/rng.dart';
import '../../engine/cup_controller.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../engine/registry.dart';
import '../../services/analytics_service.dart';
import '../../services/cross_promo_service.dart';
import '../providers.dart';
import '../router.dart';
import '../widgets/game_glyphs.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/mini_game_view.dart';
import '../widgets/ui_kit.dart';
import 'premium_card.dart';

/// Internal cup phase.
enum _CupPhase { playing, standings, complete }

class CupScreen extends ConsumerStatefulWidget {
  const CupScreen({super.key});

  @override
  ConsumerState<CupScreen> createState() => _CupScreenState();
}

class _CupScreenState extends ConsumerState<CupScreen> {
  late PlayerManager _players;
  late CupController _cup;
  final SeededRng _rng = SeededRng();
  _CupPhase _phase = _CupPhase.playing;
  bool _resultHandled = false;
  bool _showHouseAd = false;

  @override
  void initState() {
    super.initState();
    _players = ref.read(playersSetupProvider);
    _cup = _buildCup(_players);
  }

  /// Builds a cup from games supported by the roster's player count.
  CupController _buildCup(PlayerManager players) {
    final List<String> pool = allMiniGameIds
        .where((String id) =>
            createMiniGame(id).meta.supportsPlayers(players.count))
        .toList(growable: false);
    final List<String> safePool = pool.isEmpty ? allMiniGameIds : pool;
    final int count = Cup.defaultGames.clamp(Cup.minGames, safePool.length);
    return CupController.random(safePool, count, _rng);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _CupPhase.playing:
        return _buildPlaying();
      case _CupPhase.standings:
        return _buildStandings();
      case _CupPhase.complete:
        return _buildChampion();
    }
  }

  // --- Playing --------------------------------------------------------------

  Widget _buildPlaying() {
    final String? gameId = _cup.currentGameId;
    if (gameId == null) {
      // Defensive: nothing to play → jump to results.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _phase = _CupPhase.complete);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          MiniGameView(
            key: ValueKey<int>(_cup.index), // fresh runner per game
            gameId: gameId,
            players: _players,
            difficulty: ref.read(difficultyProvider),
            onQuit: () => context.go(AppRoutes.home),
            onFinish: _onGameFinish,
          ),
          // Cup progress chip.
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: GlassChip(
                icon: Icons.emoji_events,
                label: 'GAME ${_cup.index + 1}/${_cup.total}',
                accent: GlassColors.amber,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onGameFinish(WinResult result) async {
    if (_resultHandled) return;
    _resultHandled = true;

    // Fold the result into the cup standings.
    final CupController next = _cup.recordResult(result, mode: _players.mode);

    // Decide (between games only) whether to fill a slot with a house ad.
    final bool showAd = !next.isComplete &&
        ref.read(crossPromoProvider).shouldShowHouseAd(
              roundsSinceLast: 1,
              rng: _rng,
            );

    if (!mounted) return;
    setState(() {
      _cup = next;
      _showHouseAd = showAd;
      _phase = next.isComplete ? _CupPhase.complete : _CupPhase.standings;
    });

    if (next.isComplete) {
      await _awardChampionIfHuman(next);
    }
  }

  // --- Standings ------------------------------------------------------------

  Widget _buildStandings() {
    final List<int> standings = _cup.board.standings();
    final String? nextGameId = _cup.currentGameId;
    return GlassScaffold(
      title: 'STANDINGS • ${_cup.index}/${_cup.total}',
      showBack: false,
      scroll: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (nextGameId != null)
            _NextGameCard(
              gameId: nextGameId,
              gameNumber: _cup.index + 1,
              total: _cup.total,
            ),
          const SizedBox(height: GlassTokens.gap),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (int i = 0; i < standings.length; i++)
                  _standingRow(i, standings[i])
                      .animate()
                      .fadeIn(delay: (GlassTokens.stagger * i))
                      .slideX(begin: 0.12, end: 0),
                if (_showHouseAd) ...<Widget>[
                  const SizedBox(height: GlassTokens.gap),
                  const _CupHouseAdCard(),
                ],
              ],
            ),
          ),
          const SizedBox(height: GlassTokens.gap),
          GlassButton(
            label: 'NEXT GAME (${_cup.index + 1}/${_cup.total})',
            icon: Icons.play_arrow_rounded,
            primary: true,
            onTap: _nextGame,
          ),
        ],
      ),
    );
  }

  Widget _standingRow(int index, int playerId) {
    final PlayerSlot? slot = _slotById(playerId);
    if (slot == null) return const SizedBox.shrink();
    return PodiumRow(
      place: index + 1,
      slot: slot,
      trailing: '${_cup.board.pointsOf(playerId)} pts',
      highlight: index == 0,
    );
  }

  void _nextGame() {
    setState(() {
      _resultHandled = false;
      _showHouseAd = false;
      _phase = _CupPhase.playing;
    });
  }

  // --- Champion -------------------------------------------------------------

  Future<void> _awardChampionIfHuman(CupController cup) async {
    final int? championId = cup.champion;
    final bool humanChampion = championId != null &&
        _players.slots.any((PlayerSlot s) => s.id == championId && !s.isBot);
    ref.read(analyticsProvider).logEvent(
      AnalyticsEvents.cupWin,
      <String, Object?>{'champion': championId, 'human': humanChampion},
    );
    if (humanChampion) {
      await ref.read(progressProvider.notifier).awardCupWin();
    }
  }

  Widget _buildChampion() {
    final List<int> standings = _cup.board.standings();
    final int? championId = _cup.champion;
    final bool humanChampion = championId != null &&
        _players.slots.any((PlayerSlot s) => s.id == championId && !s.isBot);

    return GlassScaffold(
      title: 'CHAMPION',
      showBack: false,
      scroll: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 8),
          if (championId != null) _championBanner(championId),
          if (humanChampion)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+${Economy.coinsPerCupWin} coins',
                  style: const TextStyle(
                    color: GlassColors.amber,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          const SizedBox(height: GlassTokens.gap),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (int i = 0; i < standings.length; i++)
                  _standingRow(i, standings[i]),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: GlassButton(
                  label: 'REMATCH',
                  icon: Icons.refresh,
                  onTap: _rematch,
                ),
              ),
              const SizedBox(width: GlassTokens.gapSmall),
              Expanded(
                child: GlassButton(
                  label: 'HOME',
                  icon: Icons.home_rounded,
                  primary: true,
                  onTap: () => context.go(AppRoutes.home),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _championBanner(int championId) {
    final PlayerSlot? slot = _slotById(championId);
    if (slot == null) return const SizedBox.shrink();
    final Color color = Color(slot.colorArgb);
    return PremiumPanel(
      accent: color,
      highlight: true,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      child: Column(
        children: <Widget>[
          _ChampionTrophy(color: color),
          const SizedBox(height: 10),
          Text(
            'CUP CHAMPION',
            style: GlassText.overline.copyWith(letterSpacing: 4),
          ),
          const SizedBox(height: 4),
          Text(
            slot.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GlassText.display.copyWith(fontSize: 30, color: color),
          ),
        ],
      ),
    ).animate().fadeIn().scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1, 1),
          curve: Curves.easeOutBack,
        );
  }

  void _rematch() {
    setState(() {
      _resultHandled = false;
      _showHouseAd = false;
      _cup = _buildCup(_players);
      _phase = _CupPhase.playing;
    });
  }

  PlayerSlot? _slotById(int id) {
    for (final PlayerSlot s in _players.slots) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// A house-ad card shown between cup games (never during a game).
class _CupHouseAdCard extends ConsumerStatefulWidget {
  const _CupHouseAdCard();

  @override
  ConsumerState<_CupHouseAdCard> createState() => _CupHouseAdCardState();
}

class _CupHouseAdCardState extends ConsumerState<_CupHouseAdCard> {
  HouseAd? _ad;

  @override
  void initState() {
    super.initState();
    final CrossPromoService promo = ref.read(crossPromoProvider);
    _ad = promo.pickWeighted(SeededRng());
    if (_ad != null) {
      promo.recordImpression(_ad!.id);
      // Stub interstitial: logs only (offline no-op), keeps the flow exercised.
      ref.read(adServiceProvider).showInterstitial();
    }
  }

  @override
  Widget build(BuildContext context) {
    final HouseAd? ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    final Color color = Color(ad.iconArgb);
    return PremiumMediaTile(
      accent: color,
      leading: ProceduralIcon(label: ad.title, colorArgb: ad.iconArgb),
      eyebrow: 'MORE GAMES',
      title: ad.title,
      supporting: ad.blurb.isNotEmpty ? ad.blurb : null,
      trailing: const Icon(Icons.chevron_right, color: GlassColors.textMuted),
      onTap: () => ref.read(crossPromoProvider).openStore(ad),
    );
  }
}

/// The "next game" round card on the cup standings: the upcoming mini-game's
/// procedural glyph, a "NEXT GAME" eyebrow and the round position — a premium
/// bracket-style header that makes each round feel like a real tournament step.
class _NextGameCard extends StatelessWidget {
  const _NextGameCard({
    required this.gameId,
    required this.gameNumber,
    required this.total,
  });

  final String gameId;
  final int gameNumber;
  final int total;

  /// Glyph size inside the round card.
  static const double _glyphSize = 56;

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      accent: GlassColors.amber,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          GameGlyph(
            id: gameId,
            label: gameId,
            colorArgb: GlassColors.amber.toARGB32(),
            size: _glyphSize,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('NEXT GAME', style: GlassText.overline),
                const SizedBox(height: 3),
                Text('Round $gameNumber of $total', style: GlassText.heading),
              ],
            ),
          ),
          AccentTag(
            label: '$gameNumber/$total',
            accent: GlassColors.amber,
            icon: Icons.emoji_events,
          ),
        ],
      ),
    );
  }
}

/// The amber trophy emblem at the top of the champion banner — a procedural
/// badge (no asset) matching the premium illustration footprint.
class _ChampionTrophy extends StatelessWidget {
  const _ChampionTrophy({required this.color});

  final Color color;

  /// Edge length of the trophy badge.
  static const double _size = 76;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            GlassColors.amber,
            Color(0xFFF59E0B),
          ],
        ),
        borderRadius: BorderRadius.circular(GlassTokens.radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: GlassColors.amber.withValues(alpha: 0.5),
            blurRadius: 22,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.emoji_events,
        color: GlassColors.base,
        size: 42,
      ),
    );
  }
}
