/// More Games: the cross-promo funnel. Lists the studio's catalog as cards;
/// tapping records a click and opens the (stub) store listing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/analytics_service.dart';
import '../../services/cross_promo_service.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class MoreGamesScreen extends ConsumerWidget {
  const MoreGamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CrossPromoService promo = ref.watch(crossPromoProvider);
    final List<HouseAd> ads = promo.catalog;

    return Scaffold(
      appBar: AppBar(title: const Text('MORE GAMES')),
      body: SafeArea(
        child: ads.isEmpty
            ? const Center(child: Text('No games to show right now.'))
            : ListView.builder(
                padding: const EdgeInsets.all(AppTokens.pagePadding),
                itemCount: ads.length,
                itemBuilder: (BuildContext context, int i) {
                  final HouseAd ad = ads[i];
                  return _HouseAdCard(
                    ad: ad,
                    onTap: () => _open(ref, ad),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _open(WidgetRef ref, HouseAd ad) async {
    ref
        .read(analyticsProvider)
        .logEvent(AnalyticsEvents.houseAdClick, <String, Object?>{'id': ad.id});
    // openStore (stub) already records the click and logs the URL.
    await ref.read(crossPromoProvider).openStore(ad);
  }
}

class _HouseAdCard extends StatelessWidget {
  const _HouseAdCard({required this.ad, required this.onTap});

  final HouseAd ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(ad.iconArgb);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTokens.radius),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: <Widget>[
              ProceduralIcon(label: ad.title, colorArgb: ad.iconArgb, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      ad.title,
                      style: const TextStyle(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ad.blurb,
                      style: const TextStyle(
                        color: AppColors.onSurfaceMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
                ),
                child: const Text(
                  'GET',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
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
