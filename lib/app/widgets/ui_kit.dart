/// Small shared presentational widgets used across the shell screens. Keeps the
/// screens DRY: coin/streak badges, a procedural game icon, a podium row and a
/// section header live here instead of being copy-pasted.
library;

import 'package:flutter/material.dart';

import '../../engine/player_manager.dart';
import '../../meta/streak.dart';
import '../theme.dart';

/// A pill showing the coin balance.
class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key, required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: AppColors.gold, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.monetization_on, color: AppColors.gold, size: 18),
          const SizedBox(width: 6),
          Text(
            '$coins',
            style: const TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A flame pill that only appears once the streak is meaningful.
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, required this.streak});

  final StreakState streak;

  @override
  Widget build(BuildContext context) {
    if (!streak.showFlame) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: AppColors.flame, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            streak.isHot ? Icons.local_fire_department : Icons.whatshot,
            color: AppColors.flame,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            '${streak.current}',
            style: const TextStyle(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small procedural icon: a colored rounded box with a centered glyph (e.g. a
/// game's initial). No image assets.
class ProceduralIcon extends StatelessWidget {
  const ProceduralIcon({
    super.key,
    required this.label,
    required this.colorArgb,
    this.size = 48,
  });

  final String label;
  final int colorArgb;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(colorArgb);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color, color.withValues(alpha: 0.55)],
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
      ),
      alignment: Alignment.center,
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// A left-aligned section title with a colored accent bar.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.color});

  final String title;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.gap),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: color ?? AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

/// One row of a podium / ranking list in the player's accent color.
class PodiumRow extends StatelessWidget {
  const PodiumRow({
    super.key,
    required this.place,
    required this.slot,
    this.trailing,
    this.highlight = false,
  });

  /// 1-based placement.
  final int place;
  final PlayerSlot slot;
  final String? trailing;
  final bool highlight;

  static const Map<int, String> _medals = <int, String>{
    1: '🥇',
    2: '🥈',
    3: '🥉',
  };

  @override
  Widget build(BuildContext context) {
    final Color color = Color(slot.colorArgb);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: highlight ? color.withValues(alpha: 0.20) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(
          color: highlight ? color : AppColors.surfaceHigh,
          width: highlight ? 2.5 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 36,
            child: Text(
              _medals[place] ?? '$place',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              slot.name,
              style: TextStyle(
                color: AppColors.onSurface,
                fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
        ],
      ),
    );
  }
}

/// A labelled progress bar (used by daily missions and achievements).
class LabeledProgressBar extends StatelessWidget {
  const LabeledProgressBar({
    super.key,
    required this.fraction,
    required this.label,
    this.color,
  });

  final double fraction;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: AppColors.onSurfaceMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: AppColors.surfaceHigh,
            valueColor:
                AlwaysStoppedAnimation<Color>(color ?? AppColors.secondary),
          ),
        ),
      ],
    );
  }
}

/// A stat tile: big number over a caption.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.caption,
    this.color,
  });

  final String value;
  final String caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              color: color ?? AppColors.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(
              color: AppColors.onSurfaceMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
