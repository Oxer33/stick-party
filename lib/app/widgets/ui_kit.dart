/// Small shared presentational widgets used across the shell screens, restyled
/// for the glass design system. Keeps screens DRY: coin/streak chips, a
/// procedural game icon, a podium row, a section header, a labelled progress bar
/// and a stat tile live here instead of being copy-pasted.
library;

import 'package:flutter/material.dart';

import '../../engine/player_manager.dart';
import '../../meta/streak.dart';
import 'glass_kit.dart';
import 'glass_tokens.dart';

/// A frosted chip showing the coin balance.
class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key, required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      icon: Icons.monetization_on,
      label: '$coins',
      accent: GlassColors.amber,
    );
  }
}

/// A flame chip that only appears once the streak is meaningful.
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key, required this.streak});

  final StreakState streak;

  @override
  Widget build(BuildContext context) {
    if (!streak.showFlame) return const SizedBox.shrink();
    return GlassChip(
      icon: streak.isHot ? Icons.local_fire_department : Icons.whatshot,
      label: '${streak.current}',
      accent: GlassColors.flame,
    );
  }
}

/// A small procedural icon: an accent-tinted rounded badge with a top sheen,
/// two faint decorative rings and a centered initial — reads as a crafted emblem
/// rather than a flat letter box. No image assets, no blur (cheap to paint).
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
    final double radius = GlassTokens.radiusSmall * (size / 48).clamp(0.7, 1.4);
    final BorderRadius shape = BorderRadius.circular(radius);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color, color.withValues(alpha: 0.5)],
        ),
        borderRadius: shape,
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Top-light sheen.
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: size * 0.46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Faint decorative ring, offset to the lower-right.
            Positioned(
              right: -size * 0.18,
              bottom: -size * 0.18,
              child: Container(
                width: size * 0.7,
                height: size * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: size * 0.06,
                  ),
                ),
              ),
            ),
            Text(
              label.isEmpty ? '?' : label.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: size * 0.44,
                shadows: <Shadow>[
                  Shadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
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
      padding: const EdgeInsets.only(bottom: GlassTokens.gap),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: color ?? GlassColors.violet,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(title, style: GlassText.title.copyWith(fontSize: 18)),
        ],
      ),
    );
  }
}

/// One row of a podium / ranking list as a frosted panel in the player's color.
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
    return Padding(
      padding: const EdgeInsets.only(bottom: GlassTokens.gapSmall),
      child: GlassPanel(
        radius: GlassTokens.radius,
        tint: highlight ? color : null,
        tintOpacity: 0.22,
        borderColor: highlight ? color.withValues(alpha: 0.8) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 36,
              child: Text(
                _medals[place] ?? '$place',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
                  color: GlassColors.text,
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
        Text(label, style: GlassText.body.copyWith(fontSize: 12)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: GlassColors.frost.withValues(alpha: 0.12),
            valueColor:
                AlwaysStoppedAnimation<Color>(color ?? GlassColors.cyan),
          ),
        ),
      ],
    );
  }
}

/// A stat tile: big number over a caption, in a frosted panel.
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
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              color: color ?? GlassColors.text,
              fontWeight: FontWeight.w900,
              fontSize: 28,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(caption, style: GlassText.body.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}
