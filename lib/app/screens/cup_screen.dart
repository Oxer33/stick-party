/// Cup screen: runs a tournament of several mini-games one at a time, showing a
/// standings panel between games (with an optional house-ad / stub interstitial,
/// NEVER during a game) and a champion podium at the end.
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
import '../theme.dart';
import '../widgets/mini_game_view.dart';
import '../widgets/ui_kit.dart';

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
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
                ),
                child: Text(
                  'GAME ${_cup.index + 1}/${_cup.total}',
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
    return Scaffold(
      appBar: AppBar(
        title: Text('STANDINGS • ${_cup.index}/${_cup.total}'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: ListView(
                  children: <Widget>[
                    for (int i = 0; i < standings.length; i++)
                      _standingRow(i, standings[i]),
                    if (_showHouseAd) ...<Widget>[
                      const SizedBox(height: AppTokens.gap),
                      const _CupHouseAdCard(),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.gap),
              ElevatedButton(
                onPressed: _nextGame,
                child: Text('NEXT GAME (${_cup.index + 1}/${_cup.total})'),
              ),
            ],
          ),
        ),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('CHAMPION'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          child: Column(
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
                        color: AppColors.gold,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppTokens.gap),
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
                    child: OutlinedButton(
                      onPressed: _rematch,
                      child: const Text('REMATCH'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => context.go(AppRoutes.home),
                      child: const Text('HOME'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _championBanner(int championId) {
    final PlayerSlot? slot = _slotById(championId);
    if (slot == null) return const SizedBox.shrink();
    final Color color = Color(slot.colorArgb);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: color, width: 3),
      ),
      child: Column(
        children: <Widget>[
          const Text('🏆', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 8),
          Text(
            slot.name,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 28,
            ),
          ),
          const Text(
            'CUP CHAMPION',
            style: TextStyle(
              color: AppColors.onSurfaceMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radius),
      onTap: () => ref.read(crossPromoProvider).openStore(ad),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: <Widget>[
            ProceduralIcon(label: ad.title, colorArgb: ad.iconArgb),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ad.title,
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ad.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.onSurfaceMuted,
                      fontSize: 12,
                    ),
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
