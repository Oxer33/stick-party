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
import '../../l10n/app_localizations.dart';
import '../screens/game_select_screen.dart';
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
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<MiniGameMeta> metas = allMiniGameMetas();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Header(label: l10n.gamesCount(metas.length)),
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
                name: localizedGameName(l10n, meta),
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
  const _Header({required this.label});

  final String label;

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
        Text(label, style: GlassText.overline.copyWith(fontSize: 12)),
        const Spacer(),
        const Icon(Icons.swipe, size: 16, color: GlassColors.textMuted),
      ],
    );
  }
}

/// Edge length of the framed glyph plate inside a tile.
const double _kPlateSize = 60;

/// Glyph size inside the plate.
const double _kGlyphSize = 48;

/// One game tile: a procedural icon seated on an accent-tinted "plate" (its own
/// depth shadow + leading-edge highlight) over the truncated game name. The
/// plate gives the row a premium-carousel feel; it press-scales on tap. Kept
/// cheap — no continuous animation runs in the scroll list, so the strip stays
/// smooth.
class _GameTile extends StatefulWidget {
  const _GameTile({
    required this.meta,
    required this.name,
    required this.colorArgb,
    required this.onTap,
  });

  final MiniGameMeta meta;

  /// Localized display name shown under the glyph.
  final String name;
  final int colorArgb;
  final VoidCallback onTap;

  @override
  State<_GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<_GameTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(widget.colorArgb);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? GlassTokens.pressScale : 1.0,
        duration: GlassTokens.pressDuration,
        curve: Curves.easeOut,
        child: SizedBox(
          width: _kTileWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _GlyphPlate(meta: widget.meta, name: widget.name, accent: accent),
              const SizedBox(height: 7),
              Text(
                widget.name,
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
      ),
    );
  }
}

/// The framed plate the glyph sits on: an accent-tinted fill with a soft accent
/// drop-shadow for depth and a bright top-leading edge highlight, so each tile
/// reads as a raised card in a carousel rather than a flat icon.
class _GlyphPlate extends StatelessWidget {
  const _GlyphPlate({
    required this.meta,
    required this.name,
    required this.accent,
  });

  final MiniGameMeta meta;
  final String name;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kPlateSize,
      height: _kPlateSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
        // A subtle vertical tint behind the glyph for body.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.20),
            accent.withValues(alpha: 0.05),
          ],
        ),
        // Top-leading edge catches the light; the base reads in shadow.
        border: Border.all(
          color: GlassColors.frost.withValues(alpha: 0.16),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.32),
            blurRadius: 14,
            spreadRadius: -3,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          GameGlyph(
            id: meta.id,
            label: name,
            colorArgb: accent.toARGB32(),
            size: _kGlyphSize,
          ),
          // A thin bright sliver along the very top edge for the "leading-edge
          // highlight" — a glass-carousel cue. Pointer-transparent.
          Positioned(
            top: 0,
            left: 8,
            right: 8,
            child: IgnorePointer(
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  gradient: LinearGradient(
                    colors: <Color>[
                      GlassColors.frost.withValues(alpha: 0.0),
                      GlassColors.frost.withValues(alpha: 0.5),
                      GlassColors.frost.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
