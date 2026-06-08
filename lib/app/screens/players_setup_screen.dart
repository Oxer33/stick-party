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
    final PlayerManager manager = ref.watch(playersSetupProvider);
    final PlayersSetupController controller =
        ref.read(playersSetupProvider.notifier);
    final BotDifficulty difficulty = ref.watch(difficultyProvider);

    return GlassScaffold(
      title: isCup ? 'CUP SETUP' : 'PLAYERS',
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
                    Text('PLAYERS', style: GlassText.label),
                    const SizedBox(height: 2),
                    Text(
                      'Add up to $_maxPlayers',
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
            label: isCup ? 'START CUP' : 'START',
            icon: Icons.play_arrow_rounded,
            primary: true,
            onTap: () => _start(context),
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
                  label: slot.isBot ? 'CPU' : 'HUMAN',
                  accent: color,
                  icon: slot.isBot ? Icons.smart_toy : Icons.person,
                ),
              ],
            ),
          ),
          const SizedBox(width: GlassTokens.gapSmall),
          // Human / CPU toggle (logic unchanged).
          _Segmented(
            options: const <String>['HUMAN', 'CPU'],
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
/// with a top sheen and a human/robot face, plus a small recolor hint badge so
/// it reads as "tap to change color".
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.isBot,
    required this.onTap,
  });

  final Color color;
  final bool isBot;
  final VoidCallback onTap;

  /// Edge length of the swatch.
  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[color, color.withValues(alpha: 0.55)],
                ),
                borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                isBot ? Icons.smart_toy : Icons.face,
                color: Colors.white,
                size: 26,
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
    final List<GameMode> modes = _modesFor(count);
    if (modes.length <= 1) return const SizedBox.shrink();
    final int index = modes.indexOf(selected).clamp(0, modes.length - 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('MODE', style: GlassText.label),
          const SizedBox(height: 8),
          _Segmented(
            options: <String>[for (final GameMode m in modes) _modeLabel(m)],
            selectedIndex: index,
            onSelected: (int i) => onChanged(modes[i]),
            expand: true,
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

  static String _modeLabel(GameMode m) {
    switch (m) {
      case GameMode.ffa:
        return 'FREE FOR ALL';
      case GameMode.duel1v1:
        return '1 v 1';
      case GameMode.team2v2:
        return '2 v 2';
      case GameMode.team3v3:
        return '3 v 3';
    }
  }
}

class _DifficultySelector extends StatelessWidget {
  const _DifficultySelector({required this.selected, required this.onChanged});

  final BotDifficulty selected;
  final ValueChanged<BotDifficulty> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('CPU DIFFICULTY', style: GlassText.label),
        const SizedBox(height: 8),
        _Segmented(
          options: const <String>['EASY', 'MEDIUM', 'HARD'],
          selectedIndex: BotDifficulty.values.indexOf(selected),
          onSelected: (int i) => onChanged(BotDifficulty.values[i]),
          expand: true,
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
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(GlassTokens.radiusSmall - 3),
          boxShadow: active
              ? <BoxShadow>[
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: -3,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : GlassColors.textMuted,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
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
