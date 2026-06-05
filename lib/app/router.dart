/// App navigation: a single [GoRouter] with all shell routes.
///
/// Payloads that don't belong in the URL (a built [PlayerManager], a finished
/// [WinResult]) ride along in [GoRouterState.extra] via the small typed args
/// classes below. Screens read providers for everything else.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../engine/mini_game.dart';
import '../engine/player_manager.dart';
import 'screens/cup_screen.dart';
import 'screens/daily_screen.dart';
import 'screens/game_select_screen.dart';
import 'screens/home_screen.dart';
import 'screens/more_games_screen.dart';
import 'screens/play_screen.dart';
import 'screens/players_setup_screen.dart';
import 'screens/result_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shop_screen.dart';
import 'screens/stats_screen.dart';

/// Centralised route paths (no string literals scattered across screens).
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String setup = '/setup';
  static const String select = '/select';
  static const String play = '/play';
  static const String cup = '/cup';
  static const String result = '/result';
  static const String shop = '/shop';
  static const String daily = '/daily';
  static const String stats = '/stats';
  static const String settings = '/settings';
  static const String more = '/more';
}

/// `extra` payload for the players-setup screen: which flow it feeds.
class SetupArgs {
  const SetupArgs({required this.isCup});

  /// True when START should launch a cup, false for a single quick-play round.
  final bool isCup;
}

/// `extra` payload for [PlayScreen].
class PlayArgs {
  const PlayArgs({required this.gameId, required this.players});

  final String gameId;
  final PlayerManager players;
}

/// `extra` payload for [ResultScreen] after a single quick-play round.
class ResultArgs {
  const ResultArgs({
    required this.result,
    required this.players,
    required this.gameId,
    required this.coinsEarned,
  });

  final WinResult result;
  final PlayerManager players;
  final String gameId;
  final int coinsEarned;
}

/// Builds the application router.
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (BuildContext context, GoRouterState state) =>
            const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        builder: (BuildContext context, GoRouterState state) {
          final Object? extra = state.extra;
          final bool isCup = extra is SetupArgs ? extra.isCup : false;
          return PlayersSetupScreen(isCup: isCup);
        },
      ),
      GoRoute(
        path: AppRoutes.select,
        builder: (BuildContext context, GoRouterState state) =>
            const GameSelectScreen(),
      ),
      GoRoute(
        path: AppRoutes.play,
        builder: (BuildContext context, GoRouterState state) {
          final Object? extra = state.extra;
          if (extra is! PlayArgs) {
            return const _MissingArgsScreen(route: 'play');
          }
          return PlayScreen(args: extra);
        },
      ),
      GoRoute(
        path: AppRoutes.cup,
        builder: (BuildContext context, GoRouterState state) =>
            const CupScreen(),
      ),
      GoRoute(
        path: AppRoutes.result,
        builder: (BuildContext context, GoRouterState state) {
          final Object? extra = state.extra;
          if (extra is! ResultArgs) {
            return const _MissingArgsScreen(route: 'result');
          }
          return ResultScreen(args: extra);
        },
      ),
      GoRoute(
        path: AppRoutes.shop,
        builder: (BuildContext context, GoRouterState state) =>
            const ShopScreen(),
      ),
      GoRoute(
        path: AppRoutes.daily,
        builder: (BuildContext context, GoRouterState state) =>
            const DailyScreen(),
      ),
      GoRoute(
        path: AppRoutes.stats,
        builder: (BuildContext context, GoRouterState state) =>
            const StatsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.more,
        builder: (BuildContext context, GoRouterState state) =>
            const MoreGamesScreen(),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        _RouteErrorScreen(message: state.error?.toString() ?? 'Unknown route'),
  );
}

/// Shown when a route is entered without its required [extra] payload (e.g. a
/// deep link). Falls back to home instead of crashing.
class _MissingArgsScreen extends StatelessWidget {
  const _MissingArgsScreen({required this.route});

  final String route;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Nothing to show for "$route".'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('HOME'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic router error fallback.
class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('HOME'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
