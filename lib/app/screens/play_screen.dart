/// Play screen: hosts a single [MiniGameView] round. On finish it records the
/// result, awards round-win coins when a human wins, and routes to the result
/// screen. A corner quit button returns home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../engine/mini_game.dart';
import '../../engine/player_manager.dart';
import '../../services/analytics_service.dart';
import '../providers.dart';
import '../router.dart';
import '../widgets/mini_game_view.dart';

class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen({super.key, required this.args});

  final PlayArgs args;

  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).logEvent(
      AnalyticsEvents.roundStart,
      <String, Object?>{'game': widget.args.gameId},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MiniGameView(
        gameId: widget.args.gameId,
        players: widget.args.players,
        difficulty: ref.read(difficultyProvider),
        onQuit: () => context.go(AppRoutes.home),
        onFinish: _onFinish,
      ),
    );
  }

  Future<void> _onFinish(WinResult result) async {
    if (_handled) return; // onFinish is guaranteed once, but be defensive.
    _handled = true;

    final PlayerManager players = widget.args.players;
    final int? winnerId = result.winner;
    final num winnerScore =
        winnerId == null ? 0 : (result.finalScores[winnerId] ?? 0);

    // Record the round + per-game best + session size.
    final progress = ref.read(progressProvider.notifier);
    await progress.recordResult(
      gameId: widget.args.gameId,
      score: winnerScore.round(),
      playerCount: players.count,
    );

    // Award coins only when a HUMAN won (the device's player perspective).
    int coinsEarned = 0;
    final bool humanWon = winnerId != null &&
        players.slots.any((PlayerSlot s) => s.id == winnerId && !s.isBot);
    if (humanWon) {
      await progress.awardRoundWin();
      coinsEarned = Economy.coinsPerRoundWin;
    }

    ref.read(analyticsProvider).logEvent(
      AnalyticsEvents.roundEnd,
      <String, Object?>{
        'game': widget.args.gameId,
        'winner': winnerId,
        'coins': coinsEarned,
      },
    );

    if (!mounted) return;
    context.pushReplacement(
      AppRoutes.result,
      extra: ResultArgs(
        result: result,
        players: players,
        gameId: widget.args.gameId,
        coinsEarned: coinsEarned,
      ),
    );
  }
}
