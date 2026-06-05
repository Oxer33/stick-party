/// Home / main menu. Title, coin + streak badges, primary navigation buttons,
/// a daily-claim hint dot, and a house-ad teaser card (the cross-promo funnel).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/rng.dart';
import '../../meta/daily.dart';
import '../../meta/progress_store.dart';
import '../../services/analytics_service.dart';
import '../../services/cross_promo_service.dart';
import '../providers.dart';
import '../router.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Progress progress = ref.watch(progressProvider);
    final bool dailyAvailable = _dailyAvailable(ref);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Top bar: coins + streak.
              Row(
                children: <Widget>[
                  CoinBadge(coins: progress.coins),
                  const SizedBox(width: 10),
                  StreakBadge(streak: progress.streak),
                ],
              ),
              // Scrollable middle so the menu never overflows on short screens.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 24),
                      // Title.
                      Text(
                        'STICK',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.displayLarge?.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 64,
                                ),
                      ),
                      Text(
                        'PARTY',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.displayLarge?.copyWith(
                                  color: AppColors.secondary,
                                  fontSize: 64,
                                ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '2 • 3 • 4 PLAYER GAMES',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.onSurfaceMuted,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Primary actions.
                      ElevatedButton(
                        onPressed: () => context.push(
                          AppRoutes.setup,
                          extra: const SetupArgs(isCup: false),
                        ),
                        child: const Text('QUICK PLAY'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          minimumSize:
                              const Size.fromHeight(AppTokens.buttonHeight),
                          backgroundColor: AppColors.secondary,
                          foregroundColor: const Color(0xFF06201E),
                        ),
                        onPressed: () => context.push(
                          AppRoutes.setup,
                          extra: const SetupArgs(isCup: true),
                        ),
                        child: const Text('CUP'),
                      ),
                      const SizedBox(height: 20),
                      // Secondary grid.
                      Row(
                        children: <Widget>[
                          _MenuTile(
                            icon: Icons.storefront,
                            label: 'SHOP',
                            onTap: () => context.push(AppRoutes.shop),
                          ),
                          const SizedBox(width: 12),
                          _MenuTile(
                            icon: Icons.calendar_today,
                            label: 'DAILY',
                            showDot: dailyAvailable,
                            onTap: () => context.push(AppRoutes.daily),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          _MenuTile(
                            icon: Icons.bar_chart,
                            label: 'STATS',
                            onTap: () => context.push(AppRoutes.stats),
                          ),
                          const SizedBox(width: 12),
                          _MenuTile(
                            icon: Icons.settings,
                            label: 'SETTINGS',
                            onTap: () => context.push(AppRoutes.settings),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _HouseAdTeaser(),
            ],
          ),
        ),
      ),
    );
  }

  /// True when the login bonus has not yet been claimed for today's calendar
  /// day. Read-only check (claiming happens on the daily screen).
  bool _dailyAvailable(WidgetRef ref) {
    final DailyClaimStore store = ref.read(dailyClaimStoreProvider);
    final String today = DailyService.isoForDate(DateTime.now());
    return store.lastClaimDayIso != today;
  }
}

/// A square secondary-menu tile with an optional "available" dot.
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        onTap: onTap,
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTokens.radius),
            border: Border.all(color: AppColors.surfaceHigh),
          ),
          child: Stack(
            children: <Widget>[
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, color: AppColors.onSurface, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              if (showDot)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small "More Games" teaser card driven by the cross-promo service. Tapping
/// records a click, opens the (stub) store, and routes to the full list.
class _HouseAdTeaser extends ConsumerStatefulWidget {
  const _HouseAdTeaser();

  @override
  ConsumerState<_HouseAdTeaser> createState() => _HouseAdTeaserState();
}

class _HouseAdTeaserState extends ConsumerState<_HouseAdTeaser> {
  HouseAd? _ad;

  @override
  void initState() {
    super.initState();
    // Pick once per mount so the teaser is stable while the menu is visible.
    final CrossPromoService promo = ref.read(crossPromoProvider);
    _ad = promo.pickWeighted(SeededRng());
    if (_ad != null) {
      promo.recordImpression(_ad!.id);
      ref
          .read(analyticsProvider)
          .logEvent(AnalyticsEvents.houseAdImpression, <String, Object?>{
        'id': _ad!.id,
        'surface': 'home_teaser',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final HouseAd? ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radius),
      onTap: () => _onTap(ad),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTokens.radius),
          border: Border.all(color: Color(ad.iconArgb).withValues(alpha: 0.6)),
        ),
        child: Row(
          children: <Widget>[
            ProceduralIcon(label: ad.title, colorArgb: ad.iconArgb),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'MORE GAMES',
                    style: TextStyle(
                      color: AppColors.onSurfaceMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ad.title,
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.onSurfaceMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _onTap(HouseAd ad) async {
    final CrossPromoService promo = ref.read(crossPromoProvider);
    ref
        .read(analyticsProvider)
        .logEvent(AnalyticsEvents.houseAdClick, <String, Object?>{'id': ad.id});
    await promo.openStore(ad); // stub also records the click
    if (!mounted) return;
    context.push(AppRoutes.more);
  }
}
