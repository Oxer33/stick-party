/// Settings: bot difficulty, shake intensity, restore purchases, reset progress
/// (with confirmation), and a short about/legal note.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/bots.dart';
import '../../services/iap_service.dart';
import '../../services/purchase_applier.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BotDifficulty difficulty = ref.watch(difficultyProvider);
    final double shake = ref.watch(shakeIntensityProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('SETTINGS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          children: <Widget>[
            const SectionHeader(title: 'GAMEPLAY'),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('CPU difficulty',
                      style: TextStyle(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  SegmentedButton<BotDifficulty>(
                    segments: const <ButtonSegment<BotDifficulty>>[
                      ButtonSegment<BotDifficulty>(
                          value: BotDifficulty.easy, label: Text('Easy')),
                      ButtonSegment<BotDifficulty>(
                          value: BotDifficulty.medium, label: Text('Medium')),
                      ButtonSegment<BotDifficulty>(
                          value: BotDifficulty.hard, label: Text('Hard')),
                    ],
                    selected: <BotDifficulty>{difficulty},
                    onSelectionChanged: (Set<BotDifficulty> sel) =>
                        ref.read(difficultyProvider.notifier).state =
                            sel.first,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text('Screen shake',
                          style: TextStyle(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w700)),
                      Text('${(shake * 100).round()}%',
                          style: const TextStyle(
                              color: AppColors.onSurfaceMuted)),
                    ],
                  ),
                  Slider(
                    value: shake,
                    onChanged: (double v) =>
                        ref.read(shakeIntensityProvider.notifier).state = v,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'PURCHASES', color: AppColors.gold),
            _Card(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Restore purchases',
                    style: TextStyle(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w700)),
                subtitle: const Text('Re-apply your one-time unlocks',
                    style: TextStyle(color: AppColors.onSurfaceMuted)),
                trailing: const Icon(Icons.restore, color: AppColors.onSurface),
                onTap: () => _restore(context, ref),
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'DATA', color: AppColors.flame),
            _Card(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reset progress',
                    style: TextStyle(
                        color: AppColors.flame, fontWeight: FontWeight.w700)),
                subtitle: const Text('Erase coins, unlocks and stats',
                    style: TextStyle(color: AppColors.onSurfaceMuted)),
                trailing:
                    const Icon(Icons.delete_outline, color: AppColors.flame),
                onTap: () => _confirmReset(context, ref),
              ),
            ),
            const SizedBox(height: 24),
            const _AboutNote(),
          ],
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final IapService iap = ref.read(iapServiceProvider);
    await iap.restore();
    // Re-apply restorable entitlements (idempotent; consumables grant nothing).
    for (final IapProduct p in iap.products) {
      if (p.consumable) continue;
      final PurchaseGrant grant = PurchaseApplier.apply(p.id, isRestore: true);
      if (!grant.isEmpty) {
        await ref.read(progressProvider.notifier).applyPurchaseGrant(grant);
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Purchases restored.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text(
          'This permanently erases your coins, cosmetics and stats. '
          'This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.flame),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('RESET'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(progressProvider.notifier).resetAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Progress reset.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppColors.surfaceHigh),
      ),
      child: child,
    );
  }
}

class _AboutNote extends StatelessWidget {
  const _AboutNote();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Text(
          'Stick Party',
          style: TextStyle(
              color: AppColors.onSurface, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Rated Everyone. Plays fully offline. No accounts, no tracking. '
          'In-app purchases are cosmetic only and never affect gameplay — '
          'no loot boxes, no pay-to-win, no dark patterns.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurfaceMuted.withValues(alpha: 0.9),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
