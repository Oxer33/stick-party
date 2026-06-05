/// More Games: the cross-promo funnel. Lists the studio's catalog as cards;
/// tapping records a click and opens the (stub) store listing. Restyled glass;
/// the cross-promo actions / providers are unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/analytics_service.dart';
import '../../services/cross_promo_service.dart';
import '../providers.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';

class MoreGamesScreen extends ConsumerWidget {
  const MoreGamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CrossPromoService promo = ref.watch(crossPromoProvider);
    final List<HouseAd> ads = promo.catalog;

    return GlassScaffold(
      title: 'MORE GAMES',
      scroll: false,
      padding: EdgeInsets.zero,
      body: ads.isEmpty
          ? Center(
              child: Text(
                'No games to show right now.',
                style: GlassText.body,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(GlassTokens.pagePadding),
              itemCount: ads.length,
              itemBuilder: (BuildContext context, int i) {
                final HouseAd ad = ads[i];
                return _HouseAdCard(
                  ad: ad,
                  onTap: () => _open(ref, ad),
                )
                    .animate()
                    .fadeIn(delay: (GlassTokens.stagger * i))
                    .slideY(begin: 0.18, end: 0, curve: Curves.easeOutCubic);
              },
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
      padding: const EdgeInsets.only(bottom: GlassTokens.gap),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: GlassPanel(
          tint: color,
          tintOpacity: 0.10,
          borderColor: color.withValues(alpha: 0.5),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              ProceduralIcon(label: ad.title, colorArgb: ad.iconArgb, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(ad.title, style: GlassText.heading),
                    const SizedBox(height: 4),
                    Text(ad.blurb, style: GlassText.body),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 12,
                      spreadRadius: -3,
                    ),
                  ],
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
