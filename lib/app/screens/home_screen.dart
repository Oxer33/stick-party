/// Home / main menu — the glass showcase. A shimmering gradient title, a frosted
/// chip row (coins, streak, settings), a grid of large glass buttons, a
/// daily-claim hint dot, and a house-ad teaser card (the cross-promo funnel).
///
/// Navigation, providers and the cross-promo flow are unchanged from the
/// original; only the presentation is glass.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/rng.dart';
import '../../meta/daily.dart';
import '../../meta/progress_store.dart';
import '../../meta/streak.dart';
import '../../services/analytics_service.dart';
import '../../services/cross_promo_service.dart';
import '../providers.dart';
import '../router.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/mesh_background.dart';
import '../widgets/ui_kit.dart';

/// Big logo type size.
const double _kTitleSize = 64;

/// Height of each menu button.
const double _kMenuButtonHeight = 76;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Progress progress = ref.watch(progressProvider);
    final bool dailyAvailable = _dailyAvailable(ref);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MeshGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(GlassTokens.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TopChips(coins: progress.coins, streak: progress.streak)
                    .animate()
                    .fadeIn(duration: GlassTokens.entrance)
                    .slideY(begin: -0.3, end: 0, curve: Curves.easeOutCubic),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const SizedBox(height: 28),
                        const _Title(),
                        const SizedBox(height: 28),
                        _MenuGrid(dailyAvailable: dailyAvailable),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: GlassTokens.gap),
                const _HouseAdTeaser()
                    .animate()
                    .fadeIn(delay: 360.ms, duration: GlassTokens.entrance)
                    .slideY(begin: 0.4, end: 0, curve: Curves.easeOutCubic),
              ],
            ),
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

/// The frosted top chip row: coins, streak (conditional) and a settings cog.
class _TopChips extends StatelessWidget {
  const _TopChips({required this.coins, required this.streak});

  final int coins;
  final StreakState streak;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        CoinBadge(coins: coins),
        const SizedBox(width: GlassTokens.gapSmall),
        StreakBadge(streak: streak),
        const Spacer(),
        GlassChip(
          icon: Icons.settings,
          label: 'SETTINGS',
          accent: GlassColors.cyan,
          onTap: () => context.push(AppRoutes.settings),
        ),
      ],
    );
  }
}

/// The two-word gradient logo + subtitle. Kept as two separate [Text] widgets
/// ("STICK" / "PARTY") so the smoke test can find each independently.
class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final TextStyle titleStyle = GlassText.display.copyWith(
      fontSize: _kTitleSize,
    );
    return Column(
      children: <Widget>[
        gradientText(
          'STICK',
          style: titleStyle,
          textAlign: TextAlign.center,
          gradient: const LinearGradient(
            colors: <Color>[GlassColors.violet, GlassColors.magenta],
          ),
        )
            .animate(onPlay: (AnimationController c) => c.repeat(reverse: true))
            .shimmer(
              duration: 2600.ms,
              color: GlassColors.frost.withValues(alpha: 0.5),
            ),
        gradientText(
          'PARTY',
          style: titleStyle,
          textAlign: TextAlign.center,
          gradient: const LinearGradient(
            colors: <Color>[GlassColors.magenta, GlassColors.cyan],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '2 • 3 • 4 PLAYER GAMES',
          textAlign: TextAlign.center,
          style: GlassText.overline.copyWith(letterSpacing: 4),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 600.ms)
        .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1));
  }
}

/// The main menu: a primary QUICK PLAY button then a 2-col grid of glass tiles.
class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.dailyAvailable});

  final bool dailyAvailable;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = <Widget>[
      GlassButton(
        label: 'QUICK PLAY',
        icon: Icons.sports_esports,
        primary: true,
        accent: GlassColors.violet,
        height: _kMenuButtonHeight,
        onTap: () => context.push(
          AppRoutes.setup,
          extra: const SetupArgs(isCup: false),
        ),
      ),
      GlassButton(
        label: 'CUP',
        icon: Icons.emoji_events,
        accent: GlassColors.amber,
        height: _kMenuButtonHeight,
        onTap: () => context.push(
          AppRoutes.setup,
          extra: const SetupArgs(isCup: true),
        ),
      ),
      GlassButton(
        label: 'SHOP',
        icon: Icons.storefront,
        accent: GlassColors.magenta,
        height: _kMenuButtonHeight,
        onTap: () => context.push(AppRoutes.shop),
      ),
      GlassButton(
        label: 'DAILY',
        icon: Icons.calendar_today,
        accent: GlassColors.cyan,
        height: _kMenuButtonHeight,
        trailing: dailyAvailable ? const _NotifyDot() : null,
        onTap: () => context.push(AppRoutes.daily),
      ),
      GlassButton(
        label: 'STATS',
        icon: Icons.bar_chart,
        accent: GlassColors.flame,
        height: _kMenuButtonHeight,
        onTap: () => context.push(AppRoutes.stats),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: GlassTokens.gapSmall,
      crossAxisSpacing: GlassTokens.gapSmall,
      childAspectRatio: 1.9,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        for (int i = 0; i < tiles.length; i++)
          tiles[i]
              .animate()
              .fadeIn(
                delay: (GlassTokens.stagger * i) + const Duration(milliseconds: 120),
                duration: GlassTokens.entrance,
              )
              .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic),
      ],
    );
  }
}

/// A small accent dot used as a "something to claim" indicator.
class _NotifyDot extends StatelessWidget {
  const _NotifyDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: GlassColors.magenta,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: GlassColors.magenta.withValues(alpha: 0.8),
            blurRadius: 8,
          ),
        ],
      ),
    ).animate(onPlay: (AnimationController c) => c.repeat(reverse: true)).fadeIn(
          duration: 800.ms,
        );
  }
}

/// A "More Games" teaser card driven by the cross-promo service. Tapping records
/// a click, opens the (stub) store, and routes to the full list.
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
    final Color accent = Color(ad.iconArgb);
    return GestureDetector(
      onTap: () => _onTap(ad),
      behavior: HitTestBehavior.opaque,
      child: GlassPanel(
        tint: accent,
        tintOpacity: 0.10,
        borderColor: accent.withValues(alpha: 0.5),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            ProceduralIcon(label: ad.title, colorArgb: ad.iconArgb),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('MORE GAMES', style: GlassText.overline),
                  const SizedBox(height: 2),
                  Text(
                    ad.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GlassText.heading,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: GlassColors.textMuted),
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
