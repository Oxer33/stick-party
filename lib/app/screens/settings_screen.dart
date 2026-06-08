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
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';
import 'premium_card.dart';

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
          PremiumPanel(
            accent: GlassColors.violet,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const _OptionBadge(
                        icon: Icons.smart_toy, accent: GlassColors.violet),
                    const SizedBox(width: 12),
                    Text('CPU difficulty', style: GlassText.heading),
                  ],
                ),
                const SizedBox(height: 12),
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
          PremiumPanel(
            accent: GlassColors.cyan,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const _OptionBadge(
                        icon: Icons.vibration, accent: GlassColors.cyan),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text('Screen shake', style: GlassText.heading)),
                    AccentTag(
                      label: '${(shake * 100).round()}%',
                      accent: GlassColors.cyan,
                    ),
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
          PremiumMediaTile(
            accent: GlassColors.amber,
            leading: const _OptionBadge(
                icon: Icons.restore, accent: GlassColors.amber),
            title: 'Restore purchases',
            supporting: 'Re-apply your one-time unlocks',
            trailing: const Icon(Icons.chevron_right, color: GlassColors.amber),
            onTap: () => _restore(context, ref),
          ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'DATA', color: GlassColors.flame),
          PremiumMediaTile(
            accent: GlassColors.flame,
            leading: const _OptionBadge(
                icon: Icons.delete_outline, accent: GlassColors.flame),
            title: 'Reset progress',
            titleColor: GlassColors.flame,
            supporting: 'Erase coins, unlocks and stats',
            trailing:
                const Icon(Icons.chevron_right, color: GlassColors.flame),
            onTap: () => _confirmReset(context, ref),
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

/// A small rounded accent badge holding a setting-row icon — the leading
/// "illustration" that gives each option the same crafted footprint as the
/// premium media tiles elsewhere.
class _OptionBadge extends StatelessWidget {
  const _OptionBadge({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kPremiumTileArtSize,
      height: kPremiumTileArtSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[accent, accent.withValues(alpha: 0.55)],
        ),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.4),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 26),
    );
  }
}

class _AboutNote extends StatelessWidget {
  const _AboutNote();

  @override
  Widget build(BuildContext context) {
    return PremiumPanel(
      accent: GlassColors.violet,
      glow: false,
      padding: const EdgeInsets.all(16),
      child: Column(
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
      ),
    );
  }
}
