/// A horizontal "games catalog" strip for the home menu: every registered
/// minigame as a small procedural tile (colored glyph + name), behind a
/// "15 GAMES" header. It makes the catalog feel rich at a glance and routes the
/// player into the setup flow when a tile is tapped.
///
/// Pure presentation: it reads the in-memory registry via [allMiniGameMetas] and
/// owns no state. Each tile cycles through the player palette for variety.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../engine/mini_game.dart';
import '../../engine/registry.dart';
import 'game_glyphs.dart';
import 'glass_tokens.dart';

/// Height of the horizontal tile strip.
const double _kStripHeight = 104;

/// Width of one game tile.
const double _kTileWidth = 84;

/// A horizontal scroller of all minigames. Tapping a tile invokes [onTapGame]
/// with that game's id (the home screen routes it into setup).
class GamesShowcase extends StatelessWidget {
  const GamesShowcase({super.key, required this.onTapGame});

  /// Called with the tapped game's id.
  final ValueChanged<String> onTapGame;

  @override
  Widget build(BuildContext context) {
    final List<MiniGameMeta> metas = allMiniGameMetas();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Header(count: metas.length),
        const SizedBox(height: GlassTokens.gapSmall),
        SizedBox(
          height: _kStripHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: metas.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: GlassTokens.gapSmall),
            itemBuilder: (BuildContext context, int i) {
              final MiniGameMeta meta = metas[i];
              return _GameTile(
                meta: meta,
                colorArgb: PlayerPalette.argb[i % PlayerPalette.argb.length],
                onTap: () => onTapGame(meta.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "15 GAMES" eyebrow with an accent bar and a small swipe hint.
class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: kAccentGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text('$count GAMES', style: GlassText.overline.copyWith(fontSize: 12)),
        const Spacer(),
        const Icon(Icons.swipe, size: 16, color: GlassColors.textMuted),
      ],
    );
  }
}

/// One game tile: a procedural icon over the (truncated) game name.
class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.meta,
    required this.colorArgb,
    required this.onTap,
  });

  final MiniGameMeta meta;
  final int colorArgb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(colorArgb);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _kTileWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GameGlyph(
                id: meta.id, label: meta.name, colorArgb: colorArgb, size: 52),
            const SizedBox(height: 6),
            Text(
              meta.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GlassText.body.copyWith(
                fontSize: 10.5,
                height: 1.05,
                color: accent.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
