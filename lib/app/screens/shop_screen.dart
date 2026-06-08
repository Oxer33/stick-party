/// Shop: cosmetics (free auto-owned, coin-buyable, selectable skins) and the
/// real-money IAP catalog. Honest price labels, cosmetics-only — no dark
/// patterns, no pay-to-win. Restyled glass; all purchase actions unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result.dart';
import '../../meta/cosmetics.dart';
import '../../meta/progress_store.dart';
import '../../services/analytics_service.dart';
import '../../services/iap_service.dart';
import '../../services/purchase_applier.dart';
import '../providers.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';
import 'premium_card.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Progress progress = ref.watch(progressProvider);
    final List<IapProduct> products = ref.watch(iapServiceProvider).products;

    final List<Cosmetic> skins = kCosmetics
        .where((Cosmetic c) => c.type == CosmeticType.stickSkin)
        .toList(growable: false);
    final List<Cosmetic> themes = kCosmetics
        .where((Cosmetic c) => c.type == CosmeticType.mapTheme)
        .toList(growable: false);

    return GlassScaffold(
      title: 'SHOP',
      actions: <Widget>[CoinBadge(coins: progress.coins)],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'STICK SKINS'),
          ...skins.map(
              (Cosmetic c) => _CosmeticTile(cosmetic: c, progress: progress)),
          const SizedBox(height: 24),
          const SectionHeader(title: 'MAP THEMES', color: GlassColors.cyan),
          ...themes.map(
              (Cosmetic c) => _CosmeticTile(cosmetic: c, progress: progress)),
          const SizedBox(height: 24),
          const SectionHeader(title: 'STORE', color: GlassColors.amber),
          ...products.map((IapProduct p) => _IapTile(product: p)),
          const SizedBox(height: GlassTokens.gapSmall),
          const _EthicsNote(),
        ],
      ),
    );
  }
}

class _CosmeticTile extends ConsumerWidget {
  const _CosmeticTile({required this.cosmetic, required this.progress});

  final Cosmetic cosmetic;
  final Progress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool owned = isOwned(progress.ownedCosmetics, cosmetic);
    final bool isSkin = cosmetic.type == CosmeticType.stickSkin;
    final bool selected = isSkin && progress.selectedSkinId == cosmetic.id;
    final int iconArgb = cosmetic.paletteArgb.isNotEmpty
        ? cosmetic.paletteArgb.first
        : GlassColors.violet.toARGB32();
    final Color accent = Color(iconArgb);
    final String status = owned
        ? (cosmetic.isFree
            ? 'Free • always yours'
            : (selected ? 'Equipped' : 'Owned'))
        : '${cosmetic.priceCoins} coins';

    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.gapSmall),
      child: PremiumMediaTile(
        accent: accent,
        highlight: selected,
        leading: ProceduralIcon(label: cosmetic.name, colorArgb: iconArgb),
        title: cosmetic.name,
        eyebrow: isSkin ? 'STICK SKIN' : 'MAP THEME',
        supporting: status,
        trailing: _action(context, ref, owned, selected, isSkin),
      ),
    );
  }

  Widget _action(
    BuildContext context,
    WidgetRef ref,
    bool owned,
    bool selected,
    bool isSkin,
  ) {
    if (!owned) {
      final bool affordable = progress.coins >= cosmetic.priceCoins;
      return FilledButton(
        onPressed: affordable ? () => _buy(context, ref) : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, 40),
          backgroundColor: GlassColors.amber,
          foregroundColor: GlassColors.base,
        ),
        child: const Text('BUY'),
      );
    }
    if (isSkin) {
      return selected
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.check_circle, color: GlassColors.violet),
            )
          : OutlinedButton(
              onPressed: () =>
                  ref.read(progressProvider.notifier).selectSkin(cosmetic.id),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(88, 40),
                foregroundColor: GlassColors.text,
                side: BorderSide(
                  color: GlassColors.frost.withValues(alpha: 0.3),
                ),
              ),
              child: const Text('USE'),
            );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Icon(Icons.check, color: GlassColors.textMuted),
    );
  }

  Future<void> _buy(BuildContext context, WidgetRef ref) async {
    final bool ok =
        await ref.read(progressProvider.notifier).buyCosmetic(cosmetic.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Unlocked ${cosmetic.name}!' : 'Not enough coins.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _IapTile extends ConsumerWidget {
  const _IapTile({required this.product});

  final IapProduct product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final IconData glyph =
        product.consumable ? Icons.monetization_on : Icons.lock_open;
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.gapSmall),
      child: PremiumMediaTile(
        accent: GlassColors.amber,
        leading: _IapBadge(icon: glyph),
        title: product.title,
        eyebrow: product.consumable ? 'COIN PACK' : 'UNLOCK',
        supporting:
            product.consumable ? 'Top up your coins' : 'One-time unlock',
        trailing: FilledButton(
          onPressed: () => _buy(context, ref),
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: GlassColors.amber,
            foregroundColor: GlassColors.base,
          ),
          // Real, honest price label from the store catalog.
          child: Text(product.priceLabel),
        ),
      ),
    );
  }

  Future<void> _buy(BuildContext context, WidgetRef ref) async {
    final IapService iap = ref.read(iapServiceProvider);
    final Result<String> result = await iap.buy(product.id);
    if (!context.mounted) return;

    await result.fold(
      (String id) async {
        final PurchaseGrant grant =
            PurchaseApplier.apply(id, isRestore: false);
        await ref.read(progressProvider.notifier).applyPurchaseGrant(grant);
        ref.read(analyticsProvider).logEvent(
          AnalyticsEvents.iapBuy,
          <String, Object?>{'id': id},
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchased ${product.title}.'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      (Err<String> err) async {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: ${err.message}'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}

/// A small amber rounded badge holding an IAP product's glyph, sized to match
/// the media-tile illustration footprint.
class _IapBadge extends StatelessWidget {
  const _IapBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kPremiumTileArtSize,
      height: kPremiumTileArtSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            GlassColors.amber,
            GlassColors.amber.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: GlassColors.amber.withValues(alpha: 0.4),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: GlassColors.base, size: 28),
    );
  }
}

class _EthicsNote extends StatelessWidget {
  const _EthicsNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Purchases are cosmetic only and never affect gameplay. '
        'Prices shown are real and set by the app store.',
        textAlign: TextAlign.center,
        style: GlassText.body.copyWith(fontSize: 12),
      ),
    );
  }
}
