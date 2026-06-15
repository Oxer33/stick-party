/// Players setup: choose seat count (1–4), human/CPU per seat, accent color,
/// the match mode, and bot difficulty. START launches quick-play or a cup.
/// Restyled with glass cards + segmented controls; logic/nav unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/bots.dart';
import '../../engine/player_manager.dart';
import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_scaffold.dart';
import '../widgets/glass_tokens.dart';
import 'premium_card.dart';

class PlayersSetupScreen extends ConsumerWidget {
  const PlayersSetupScreen({super.key, required this.isCup});

  /// True when START should start a cup, false for a single quick-play round.
  final bool isCup;

  static const int _maxPlayers = 4;
  static const int _minPlayers = 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PlayerManager manager = ref.watch(playersSetupProvider);
    final PlayersSetupController controller =
        ref.read(playersSetupProvider.notifier);
    final BotDifficulty difficulty = ref.watch(difficultyProvider);

    return GlassScaffold(
      title: isCup ? l10n.cupSetupTitle : l10n.playersTitle,
      scroll: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Seat count stepper.
          PremiumPanel(
            accent: GlassColors.violet,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(l10n.playersTitle, style: GlassText.label),
                    const SizedBox(height: 2),
                    Text(
                      l10n.playersAddUpTo(_maxPlayers),
                      style: GlassText.body.copyWith(fontSize: 11),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    _RoundIconButton(
                      icon: Icons.remove,
                      enabled: manager.count > _minPlayers,
                      onTap: controller.removePlayer,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '${manager.count}',
                        style: GlassText.display.copyWith(fontSize: 30),
                      ),
                    ),
                    _RoundIconButton(
                      icon: Icons.add,
                      enabled: manager.count < _maxPlayers,
                      onTap: () => controller.addPlayer(isBot: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: GlassTokens.gap),
          // Seats.
          Expanded(
            child: ListView.separated(
              itemCount: manager.count,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: GlassTokens.gapSmall),
              itemBuilder: (BuildContext context, int i) {
                final PlayerSlot slot = manager.slots[i];
                return _SeatTile(
                  slot: slot,
                  onToggleBot: () => controller.toggleBot(i),
                  onCycleColor: () => controller.cycleColor(i),
                )
                    .animate()
                    .fadeIn(delay: (GlassTokens.stagger * i))
                    .slideX(begin: 0.12, end: 0, curve: Curves.easeOutCubic);
              },
            ),
          ),
          const SizedBox(height: GlassTokens.gap),
          // Mode selector.
          _ModeSelector(
            count: manager.count,
            selected: manager.mode,
            onChanged: controller.setMode,
          ),
          // Difficulty selector.
          _DifficultySelector(
            selected: difficulty,
            onChanged: (BotDifficulty d) =>
                ref.read(difficultyProvider.notifier).state = d,
          ),
          const SizedBox(height: GlassTokens.gap),
          GlassButton(
            label: isCup ? l10n.startCup : l10n.actionStart,
            icon: Icons.play_arrow_rounded,
            primary: true,
            onTap: () => _start(context),
          )
              // Confident entrance, then a slow inviting breath to pull the eye
              // to the primary action. Relies on GlassButton's own accent glow.
              .animate()
              .fadeIn(duration: 320.ms, curve: Curves.easeOut)
              .slideY(begin: 0.18, end: 0, curve: Curves.easeOutCubic)
              .then()
              .animate(onPlay: (AnimationController c) => c.repeat(reverse: true))
              .scaleXY(
                begin: 1,
                end: 1.025,
                duration: 1400.ms,
                curve: Curves.easeInOut,
              ),
        ],
      ),
    );
  }

  void _start(BuildContext context) {
    if (isCup) {
      context.push(AppRoutes.cup);
    } else {
      context.push(AppRoutes.select);
    }
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.slot,
    required this.onToggleBot,
    required this.onCycleColor,
  });

  final PlayerSlot slot;
  final VoidCallback onToggleBot;
  final VoidCallback onCycleColor;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color color = Color(slot.colorArgb);
    return PremiumPanel(
      accent: color,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          _ColorSwatch(color: color, isBot: slot.isBot, onTap: onCycleColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  slot.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GlassText.heading,
                ),
                const SizedBox(height: 5),
                AccentTag(
                  label: slot.isBot ? l10n.seatCpu : l10n.seatHuman,
                  accent: color,
                  icon: slot.isBot ? Icons.smart_toy : Icons.person,
                ),
              ],
            ),
          ),
          const SizedBox(width: GlassTokens.gapSmall),
          // Human / CPU toggle (logic unchanged).
          _Segmented(
            options: <String>[l10n.seatHuman, l10n.seatCpu],
            selectedIndex: slot.isBot ? 1 : 0,
            onSelected: (_) => onToggleBot(),
            accent: color,
          ),
        ],
      ),
    );
  }
}

/// A tappable, characterful seat avatar: a rounded swatch in the player's color
/// with a top sheen, a human/robot face, and a gentle pulsing halo in the
/// player's own color so each seat feels alive. A small recolor hint badge
/// reads as "tap to change color".
///
/// Stateful so the halo can breathe via a looping [AnimationController]; the
/// pulse rebuilds only the swatch (a tiny subtree), keeping it cheap.
class _ColorSwatch extends StatefulWidget {
  const _ColorSwatch({
    required this.color,
    required this.isBot,
    required this.onTap,
  });

  final Color color;
  final bool isBot;
  final VoidCallback onTap;

  @override
  State<_ColorSwatch> createState() => _ColorSwatchState();
}

class _ColorSwatchState extends State<_ColorSwatch>
    with SingleTickerProviderStateMixin {
  /// Edge length of the swatch.
  static const double _size = 52;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.color;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // Breathing halo in the player's color (eased sine, repaint-only).
            AnimatedBuilder(
              animation: _pulse,
              builder: (BuildContext context, Widget? child) {
                final double t =
                    Curves.easeInOut.transform(_pulse.value);
                final double glow = 8 + t * 12;
                final double spread = -3 + t * 2;
                return Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[color, color.withValues(alpha: 0.55)],
                    ),
                    borderRadius:
                        BorderRadius.circular(GlassTokens.radiusSmall),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2 + t * 0.18),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: 0.35 + t * 0.3),
                        blurRadius: glow,
                        spreadRadius: spread,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              // Face + top sheen never change → built once, not per frame.
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  // Soft top sheen for a glossy, lit feel.
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: _size * 0.42,
                      margin: const EdgeInsets.fromLTRB(3, 3, 3, 0),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(GlassTokens.radiusSmall - 2),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0.32),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    widget.isBot ? Icons.smart_toy : Icons.face,
                    color: Colors.white,
                    size: 26,
                  ),
                ],
              ),
            ),
            // Small recolor affordance tucked into the corner.
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: GlassColors.base,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: const Icon(
                  Icons.palette,
                  color: GlassColors.frost,
                  size: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Match-mode selector. Available modes depend on the seat count.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.count,
    required this.selected,
    required this.onChanged,
  });

  final int count;
  final GameMode selected;
  final ValueChanged<GameMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<GameMode> modes = _modesFor(count);
    if (modes.length <= 1) return const SizedBox.shrink();
    final int index = modes.indexOf(selected).clamp(0, modes.length - 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.modeLabel, style: GlassText.label),
          const SizedBox(height: 8),
          _Segmented(
            options: <String>[
              for (final GameMode m in modes) _modeLabel(l10n, m),
            ],
            selectedIndex: index,
            onSelected: (int i) => onChanged(modes[i]),
            expand: true,
            accent: GlassColors.cyan,
          ),
        ],
      ),
    );
  }

  /// Modes that make sense for [count] seats. With exactly 2 seats the match is
  /// inherently a 1-v-1, so we offer no choice (the selector hides itself when
  /// there is a single option) — picking "free for all" vs "1 v 1" would be a
  /// distinction without a difference.
  static List<GameMode> _modesFor(int count) {
    switch (count) {
      case 2:
        return <GameMode>[GameMode.duel1v1];
      case 4:
        return <GameMode>[GameMode.ffa, GameMode.team2v2];
      default:
        return <GameMode>[GameMode.ffa];
    }
  }

  static String _modeLabel(AppLocalizations l10n, GameMode m) {
    switch (m) {
      case GameMode.ffa:
        return l10n.modeFreeForAll;
      case GameMode.duel1v1:
        return l10n.modeDuel1v1;
      case GameMode.team2v2:
        return l10n.modeTeam2v2;
      case GameMode.team3v3:
        return l10n.modeTeam3v3;
    }
  }
}

class _DifficultySelector extends StatelessWidget {
  const _DifficultySelector({required this.selected, required this.onChanged});

  final BotDifficulty selected;
  final ValueChanged<BotDifficulty> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.cpuDifficulty, style: GlassText.label),
        const SizedBox(height: 8),
        _Segmented(
          options: <String>[
            l10n.difficultyEasy,
            l10n.difficultyMedium,
            l10n.difficultyHard,
          ],
          selectedIndex: BotDifficulty.values.indexOf(selected),
          onSelected: (int i) => onChanged(BotDifficulty.values[i]),
          expand: true,
          accent: GlassColors.amber,
        ),
      ],
    );
  }
}

/// A glass segmented control: a frosted track with an accent-tinted active pill.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.expand = false,
    this.accent,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool expand;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      for (int i = 0; i < options.length; i++)
        _buildSegment(i, options[i], i == selectedIndex),
    ];
    final Widget row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: expand
          ? <Widget>[for (final Widget c in children) Expanded(child: c)]
          : children,
    );
    return GlassPanel(
      radius: GlassTokens.radiusSmall,
      blur: GlassTokens.blurChip,
      shadow: false,
      padding: const EdgeInsets.all(3),
      child: row,
    );
  }

  Widget _buildSegment(int i, String label, bool active) {
    final Color accentColor = accent ?? GlassColors.violet;
    return GestureDetector(
      onTap: () => onSelected(i),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    accentColor,
                    accentColor.withValues(alpha: 0.78),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(GlassTokens.radiusSmall - 3),
          border: active
              ? Border.all(color: Colors.white.withValues(alpha: 0.28))
              : null,
          // Stacked translucent layers → a soft accent bloom on selection.
          boxShadow: active
              ? <BoxShadow>[
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.55),
                    blurRadius: 16,
                    spreadRadius: -3,
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: -1,
                  ),
                ]
              : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: active ? Colors.white : GlassColors.textMuted,
            fontWeight: active ? FontWeight.w900 : FontWeight.w800,
            fontSize: 12,
            letterSpacing: active ? 0.3 : 0,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: GlassPanel(
        radius: 999,
        blur: GlassTokens.blurChip,
        shadow: false,
        tint: enabled ? GlassColors.violet : null,
        tintOpacity: 0.3,
        padding: const EdgeInsets.all(10),
        child: Icon(
          icon,
          color: enabled ? Colors.white : GlassColors.textMuted,
        ),
      ),
    );
  }
}
