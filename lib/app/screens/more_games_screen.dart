/// More Games: the cross-promo funnel. Lists the studio's catalog as cards;
/// tapping records a click and opens the (stub) store listing. Restyled glass;
/// the cross-promo actions / providers are unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/analytics_service.dart';
import '../../services/cross_promo_service.dart';
import '../providers.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';
import 'premium_card.dart';

class MoreGamesScreen extends ConsumerWidget {
  const MoreGamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final CrossPromoService promo = ref.watch(crossPromoProvider);
    final List<HouseAd> ads = promo.catalog;

    return GlassScaffold(
      title: l10n.moreGames,
      scroll: false,
      padding: EdgeInsets.zero,
      body: ads.isEmpty
          ? Center(
              child: Text(
                l10n.noGamesToShow,
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
                  eyebrow: l10n.fromTheStudio,
                  getLabel: l10n.actionGet,
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
  const _HouseAdCard({
    required this.ad,
    required this.eyebrow,
    required this.getLabel,
    required this.onTap,
  });

  final HouseAd ad;

  /// Localized "FROM THE STUDIO" eyebrow.
  final String eyebrow;

  /// Localized "GET" call-to-action label.
  final String getLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(ad.iconArgb);
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.gap),
      child: PremiumMediaTile(
        accent: color,
        onTap: onTap,
        leading: ProceduralIcon(label: ad.title, colorArgb: ad.iconArgb),
        eyebrow: eyebrow,
        title: ad.title,
        supporting: ad.blurb,
        trailing: _GetPill(accent: color, label: getLabel),
      ),
    );
  }
}

/// A solid accent "GET" call-to-action pill for a house-ad card.
class _GetPill extends StatelessWidget {
  const _GetPill({required this.accent, required this.label});

  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.5),
            blurRadius: 12,
            spreadRadius: -3,
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
