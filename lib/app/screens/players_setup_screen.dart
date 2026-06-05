/// Players setup: choose seat count (1–4), human/CPU per seat, accent color,
/// the match mode, and bot difficulty. START launches quick-play or a cup.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/bots.dart';
import '../../engine/player_manager.dart';
import '../providers.dart';
import '../router.dart';
import '../theme.dart';

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

    return Scaffold(
      appBar: AppBar(title: Text(isCup ? 'CUP SETUP' : 'PLAYERS')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Seat count stepper.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text('PLAYERS',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, letterSpacing: 1)),
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
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: AppColors.onSurface,
                          ),
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
              const SizedBox(height: AppTokens.gap),
              // Seats.
              Expanded(
                child: ListView.separated(
                  itemCount: manager.count,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int i) {
                    final PlayerSlot slot = manager.slots[i];
                    return _SeatTile(
                      slot: slot,
                      onToggleBot: () => controller.toggleBot(i),
                      onCycleColor: () => controller.cycleColor(i),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppTokens.gap),
              // Mode selector.
              _ModeSelector(
                count: manager.count,
                selected: manager.mode,
                onChanged: controller.setMode,
              ),
              const SizedBox(height: AppTokens.gap),
              // Difficulty selector.
              _DifficultySelector(
                selected: difficulty,
                onChanged: (BotDifficulty d) =>
                    ref.read(difficultyProvider.notifier).state = d,
              ),
              const SizedBox(height: AppTokens.gap),
              ElevatedButton(
                onPressed: () => _start(context),
                child: Text(isCup ? 'START CUP' : 'START'),
              ),
            ],
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: <Widget>[
          // Tappable color swatch.
          GestureDetector(
            onTap: onCycleColor,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
              ),
              child: const Icon(Icons.palette, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              slot.name,
              style: const TextStyle(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          // Human / CPU toggle.
          _Segmented(
            options: const <String>['HUMAN', 'CPU'],
            selectedIndex: slot.isBot ? 1 : 0,
            onSelected: (_) => onToggleBot(),
          ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('MODE',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final GameMode m in modes)
              ChoiceChip(
                label: Text(_modeLabel(m)),
                selected: m == selected,
                onSelected: (_) => onChanged(m),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceHigh,
                labelStyle: TextStyle(
                  color: m == selected ? Colors.white : AppColors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Modes that make sense for [count] seats.
  static List<GameMode> _modesFor(int count) {
    switch (count) {
      case 2:
        return <GameMode>[GameMode.ffa, GameMode.duel1v1];
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
        const Text('CPU DIFFICULTY',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
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

/// A small segmented control.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.expand = false,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool expand;

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
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
      ),
      child: row,
    );
  }

  Widget _buildSegment(int i, String label, bool active) {
    return GestureDetector(
      onTap: () => onSelected(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusSmall - 2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : AppColors.onSurfaceMuted,
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
    return Material(
      color: enabled ? AppColors.primary : AppColors.surfaceHigh,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            color: enabled ? Colors.white : AppColors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}
