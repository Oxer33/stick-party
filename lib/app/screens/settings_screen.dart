/// Settings: bot difficulty, shake intensity, UI language, restore purchases,
/// reset progress (with confirmation), and a short about/legal note. Restyled
/// glass; all actions / providers unchanged. User-facing copy is localized via
/// the generated [AppLocalizations]; the language picker endonyms are static.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/bots.dart';
import '../../l10n/app_localizations.dart';
import '../../services/iap_service.dart';
import '../../services/purchase_applier.dart';
import '../providers.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import '../widgets/ui_kit.dart';
import 'premium_card.dart';

/// One selectable UI language: a persisted locale [code] ('' = follow system)
/// and the endonym [label] shown in the picker. Endonyms are intentionally NOT
/// translated — each language names itself.
class _LanguageOption {
  const _LanguageOption(this.code, this.label);

  /// Locale code persisted to [ShellKeys.appLocaleTag]; '' means system default.
  final String code;

  /// Native name of the language (or the localized "System default" label).
  final String label;
}

/// The ten shipped languages, in the order shown in the picker. The leading
/// "system default" row uses an empty code and a localized label supplied at
/// build time.
const List<_LanguageOption> _kLanguages = <_LanguageOption>[
  _LanguageOption('en', 'English'),
  _LanguageOption('es', 'Español'),
  _LanguageOption('pt', 'Português (BR)'),
  _LanguageOption('fr', 'Français'),
  _LanguageOption('de', 'Deutsch'),
  _LanguageOption('it', 'Italiano'),
  _LanguageOption('ja', '日本語'),
  _LanguageOption('ko', '한국어'),
  _LanguageOption('zh', '中文(简体)'),
  _LanguageOption('ru', 'Русский'),
];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BotDifficulty difficulty = ref.watch(difficultyProvider);
    final double shake = ref.watch(shakeIntensityProvider);
    final Locale? locale = ref.watch(localeProvider);

    // Each top-level section fades/rises in sequence so the screen assembles
    // itself rather than snapping in — purely an entrance flourish.
    final List<Widget> sections = <Widget>[
      SectionHeader(title: l10n.sectionGameplay),
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
                Text(l10n.cpuDifficulty, style: GlassText.heading),
              ],
            ),
            const SizedBox(height: 12),
            // Accent-tinted segmented control: the selected difficulty glows
            // violet. Selection/value logic is unchanged — styling only.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (Widget child, Animation<double> a) =>
                  FadeTransition(opacity: a, child: child),
              child: Container(
                key: ValueKey<BotDifficulty>(difficulty),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: GlassColors.violet.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: SegmentedButton<BotDifficulty>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: GlassColors.violet,
                    selectedForegroundColor: Colors.white,
                    foregroundColor: GlassColors.textMuted,
                  ),
                  segments: <ButtonSegment<BotDifficulty>>[
                    ButtonSegment<BotDifficulty>(
                        value: BotDifficulty.easy,
                        label: Text(l10n.difficultyEasy)),
                    ButtonSegment<BotDifficulty>(
                        value: BotDifficulty.medium,
                        label: Text(l10n.difficultyMedium)),
                    ButtonSegment<BotDifficulty>(
                        value: BotDifficulty.hard,
                        label: Text(l10n.difficultyHard)),
                  ],
                  selected: <BotDifficulty>{difficulty},
                  onSelectionChanged: (Set<BotDifficulty> sel) =>
                      ref.read(difficultyProvider.notifier).state = sel.first,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: GlassTokens.gapSmall),
      _ShakeControl(
        value: shake,
        onChanged: (double v) =>
            ref.read(shakeIntensityProvider.notifier).state = v,
      ),
      const SizedBox(height: 24),
      SectionHeader(title: l10n.sectionLanguage, color: GlassColors.cyan),
      _LanguagePicker(
        selectedCode: locale?.languageCode ?? '',
        systemLabel: l10n.languageSystem,
        onSelected: (String code) => _selectLanguage(ref, code),
      ),
      const SizedBox(height: 24),
      SectionHeader(title: l10n.sectionPurchases, color: GlassColors.amber),
      PremiumMediaTile(
        accent: GlassColors.amber,
        leading: const _OptionBadge(
            icon: Icons.restore, accent: GlassColors.amber),
        title: l10n.restorePurchases,
        supporting: l10n.restorePurchasesDesc,
        trailing: const Icon(Icons.chevron_right, color: GlassColors.amber),
        onTap: () => _restore(context, ref),
      ),
      const SizedBox(height: 24),
      SectionHeader(title: l10n.sectionData, color: GlassColors.flame),
      PremiumMediaTile(
        accent: GlassColors.flame,
        leading: const _OptionBadge(
            icon: Icons.delete_outline, accent: GlassColors.flame),
        title: l10n.resetProgress,
        titleColor: GlassColors.flame,
        supporting: l10n.resetProgressDesc,
        trailing: const Icon(Icons.chevron_right, color: GlassColors.flame),
        onTap: () => _confirmReset(context, ref),
      ),
      const SizedBox(height: 24),
      const _AboutNote(),
    ];

    return GlassScaffold(
      title: l10n.settingsTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < sections.length; i++)
            sections[i]
                .animate()
                .fadeIn(
                  delay: (GlassTokens.stagger * i),
                  duration: 300.ms,
                  curve: Curves.easeOut,
                )
                .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  /// Applies a language choice: updates the live [localeProvider] (empty code ⇒
  /// follow system ⇒ null) and persists the tag so it survives a relaunch.
  void _selectLanguage(WidgetRef ref, String code) {
    ref.read(localeProvider.notifier).state =
        code.isEmpty ? null : Locale(code);
    ref.read(persistenceProvider).putString(ShellKeys.appLocaleTag, code);
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
      SnackBar(
        content: Text(l10n.purchasesRestored),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.resetConfirmTitle),
        content: Text(l10n.resetConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: GlassColors.flame),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionReset),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(progressProvider.notifier).resetAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.progressReset),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// The screen-shake panel: the live percentage tag, a cyan track that fills to
/// the current intensity with a glow that grows with it, and the real [Slider]
/// layered on top. Visual-only — the slider's value/callback are unchanged, so
/// dragging behaves exactly as before; the fill simply mirrors the value.
class _ShakeControl extends StatelessWidget {
  const _ShakeControl({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  /// Height of the decorative fill track behind the slider.
  static const double _trackHeight = 8;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double t = value.clamp(0.0, 1.0);
    return PremiumPanel(
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
              Expanded(child: Text(l10n.screenShake, style: GlassText.heading)),
              AccentTag(
                label: '${(t * 100).round()}%',
                accent: GlassColors.cyan,
              ),
            ],
          ),
          // Animated track fill + the live slider stacked on top of it.
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Decorative fill: a frosted base with a cyan portion that
                // widens with intensity and glows brighter as it grows.
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    return Container(
                      height: _trackHeight,
                      decoration: BoxDecoration(
                        color: GlassColors.frost.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(_trackHeight),
                      ),
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        height: _trackHeight,
                        width: c.maxWidth * t,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              GlassColors.cyan.withValues(alpha: 0.65),
                              GlassColors.cyan,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(_trackHeight),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: GlassColors.cyan
                                  .withValues(alpha: 0.25 + t * 0.4),
                              blurRadius: 6 + t * 10,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                // The real control — transparent track so the fill shows
                // through; logic and value are untouched.
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.white,
                    overlayColor: GlassColors.cyan.withValues(alpha: 0.2),
                  ),
                  child: Slider(value: value, onChanged: onChanged),
                ),
              ],
            ),
          ),
        ],
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

/// The language section body: a "System default" row followed by one row per
/// shipped language, each showing its endonym and a check on the active choice.
/// Built on the same [PremiumPanel] glass as the other settings cards so it
/// reads as part of the set. Selecting a row calls [onSelected] with the locale
/// code ('' for system default).
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.selectedCode,
    required this.systemLabel,
    required this.onSelected,
  });

  /// Currently active locale code ('' when following the system).
  final String selectedCode;

  /// Localized label for the system-default row.
  final String systemLabel;

  /// Called with the chosen locale code ('' = system default).
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<_LanguageOption> rows = <_LanguageOption>[
      _LanguageOption('', systemLabel),
      ..._kLanguages,
    ];
    return PremiumPanel(
      accent: GlassColors.cyan,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: GlassColors.frost.withValues(alpha: 0.08),
              ),
            _LanguageRow(
              label: rows[i].label,
              selected: rows[i].code == selectedCode,
              onTap: () => onSelected(rows[i].code),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single tappable language row: the endonym on the left, a cyan check on the
/// right when active. The active row gains a soft cyan wash + glow and a left
/// accent rail, and its check pops in with a scale/fade so selecting a language
/// feels responsive. Press-scales via [PressableCard] to match the card feel.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableCard(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusSmall - 2),
          // Soft accent wash + glow behind the active language.
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    GlassColors.cyan.withValues(alpha: 0.18),
                    GlassColors.cyan.withValues(alpha: 0.04),
                  ],
                )
              : null,
          border: Border(
            left: BorderSide(
              color: selected ? GlassColors.cyan : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                style: GlassText.heading.copyWith(
                  color: selected ? GlassColors.cyan : GlassColors.text,
                  fontWeight:
                      selected ? FontWeight.w800 : GlassText.heading.fontWeight,
                ),
                child: Text(label),
              ),
            ),
            // The check pops in (scale + fade) the moment a row becomes active;
            // unselected rows show a faint outline placeholder.
            if (selected)
              const Icon(
                Icons.check_circle,
                color: GlassColors.cyan,
                size: 22,
              )
                  .animate(key: const ValueKey<bool>(true))
                  .scaleXY(
                    begin: 0.4,
                    end: 1,
                    duration: 260.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 160.ms)
            else
              Icon(
                Icons.circle_outlined,
                color: GlassColors.frost.withValues(alpha: 0.25),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

class _AboutNote extends StatelessWidget {
  const _AboutNote();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return PremiumPanel(
      accent: GlassColors.violet,
      glow: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Text('Stick Party', style: GlassText.heading),
          const SizedBox(height: 6),
          Text(
            l10n.aboutBody,
            textAlign: TextAlign.center,
            style: GlassText.body.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
