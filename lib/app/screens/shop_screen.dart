/// Shop: cosmetics (free auto-owned, coin-buyable, selectable skins) and the
/// real-money IAP catalog. Honest price labels, cosmetics-only — no dark
/// patterns, no pay-to-win.
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
import '../theme.dart';
import '../widgets/ui_kit.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('SHOP'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppTokens.gap),
            child: Center(child: CoinBadge(coins: progress.coins)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          children: <Widget>[
            const SectionHeader(title: 'STICK SKINS'),
            ...skins.map((Cosmetic c) =>
                _CosmeticTile(cosmetic: c, progress: progress)),
            const SizedBox(height: 24),
            const SectionHeader(
                title: 'MAP THEMES', color: AppColors.secondary),
            ...themes.map((Cosmetic c) =>
                _CosmeticTile(cosmetic: c, progress: progress)),
            const SizedBox(height: 24),
            const SectionHeader(title: 'STORE', color: AppColors.gold),
            ...products.map((IapProduct p) => _IapTile(product: p)),
            const SizedBox(height: 12),
            const _EthicsNote(),
          ],
        ),
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
        : AppColors.primary.toARGB32();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.surfaceHigh,
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          ProceduralIcon(label: cosmetic.name, colorArgb: iconArgb),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  cosmetic.name,
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  owned
                      ? (cosmetic.isFree ? 'Free' : 'Owned')
                      : '${cosmetic.priceCoins} coins',
                  style: const TextStyle(
                    color: AppColors.onSurfaceMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _action(context, ref, owned, selected, isSkin),
        ],
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
          backgroundColor: AppColors.gold,
          foregroundColor: const Color(0xFF231A00),
        ),
        child: const Text('BUY'),
      );
    }
    if (isSkin) {
      return selected
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.check_circle, color: AppColors.primary),
            )
          : OutlinedButton(
              onPressed: () =>
                  ref.read(progressProvider.notifier).selectSkin(cosmetic.id),
              style: OutlinedButton.styleFrom(minimumSize: const Size(88, 40)),
              child: const Text('USE'),
            );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Icon(Icons.check, color: AppColors.onSurfaceMuted),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppColors.surfaceHigh),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  product.title,
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.consumable ? 'Coin pack' : 'One-time unlock',
                  style: const TextStyle(
                    color: AppColors.onSurfaceMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _buy(context, ref),
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            // Real, honest price label from the store catalog.
            child: Text(product.priceLabel),
          ),
        ],
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

class _EthicsNote extends StatelessWidget {
  const _EthicsNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Purchases are cosmetic only and never affect gameplay. '
        'Prices shown are real and set by the app store.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
      ),
    );
  }
}
