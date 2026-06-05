/// Settings: bot difficulty, shake intensity, restore purchases, reset progress
/// (with confirmation), and a short about/legal note. Restyled glass; all
/// actions / providers unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/bots.dart';
import '../../services/iap_service.dart';
import '../../services/purchase_applier.dart';
import '../providers.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BotDifficulty difficulty = ref.watch(difficultyProvider);
    final double shake = ref.watch(shakeIntensityProvider);

    return GlassScaffold(
      title: 'SETTINGS',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'GAMEPLAY'),
          GlassPanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('CPU difficulty', style: GlassText.heading),
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
                      ref.read(difficultyProvider.notifier).state = sel.first,
                ),
              ],
            ),
          ),
          const SizedBox(height: GlassTokens.gapSmall),
          GlassPanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text('Screen shake', style: GlassText.heading),
                    Text('${(shake * 100).round()}%', style: GlassText.body),
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
          const SectionHeader(title: 'PURCHASES', color: GlassColors.amber),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Restore purchases', style: GlassText.heading),
              subtitle: Text('Re-apply your one-time unlocks',
                  style: GlassText.body),
              trailing: const Icon(Icons.restore, color: GlassColors.text),
              onTap: () => _restore(context, ref),
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'DATA', color: GlassColors.flame),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            borderColor: GlassColors.flame.withValues(alpha: 0.5),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Reset progress',
                style: GlassText.heading.copyWith(color: GlassColors.flame),
              ),
              subtitle: Text('Erase coins, unlocks and stats',
                  style: GlassText.body),
              trailing:
                  const Icon(Icons.delete_outline, color: GlassColors.flame),
              onTap: () => _confirmReset(context, ref),
            ),
          ),
          const SizedBox(height: 24),
          const _AboutNote(),
        ],
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
            style: FilledButton.styleFrom(backgroundColor: GlassColors.flame),
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

class _AboutNote extends StatelessWidget {
  const _AboutNote();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text('Stick Party', style: GlassText.heading),
        const SizedBox(height: 6),
        Text(
          'Rated Everyone. Plays fully offline. No accounts, no tracking. '
          'In-app purchases are cosmetic only and never affect gameplay — '
          'no loot boxes, no pay-to-win, no dark patterns.',
          textAlign: TextAlign.center,
          style: GlassText.body.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}
