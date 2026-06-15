/// Shared "premium" card primitives used across the shell screens to lift the
/// menu cards above a plain icon+label: a tap press-scale wrapper, a thin accent
/// edge/header strip, an accent glow shadow, and a reusable media tile
/// (illustration + title + supporting line + optional trailing).
///
/// These compose the existing glass tokens / [GlassPanel] — no new design
/// system. Kept in `screens/` (the only writable area) so every screen shares
/// one implementation instead of copy-pasting the same press/glow/edge code.
///
/// Performance: cards are static. The only per-frame work is the tap
/// [AnimatedScale] (a single transform on press), and each [GlassPanel] already
/// wraps itself in a [RepaintBoundary]. No blur is used anywhere here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../widgets/glass_kit.dart';
import '../widgets/glass_tokens.dart';

/// Local layout constants for the premium card family (no magic numbers inline).
class _Card {
  _Card._();

  /// Height of the thin accent strip that sits at the top edge of a card.
  static const double accentEdge = 4;

  /// Default media-tile illustration size.
  static const double tileArt = 56;

  /// Inner padding for a media tile.
  static const EdgeInsets tilePad = EdgeInsets.all(14);

  /// Gap between the illustration and the text column.
  static const double artGap = 14;

  /// Tint opacity for an unselected premium card.
  static const double tint = 0.10;

  /// Tint opacity for a selected / highlighted premium card.
  static const double tintActive = 0.18;

  /// Border opacity for an unselected premium card edge.
  static const double border = 0.42;

  /// Border opacity for a selected / highlighted premium card edge.
  static const double borderActive = 0.85;

  /// Outer accent-glow shadow parameters.
  static const double glowBlur = 28;
  static const double glowSpread = -6;
  static const Offset glowOffset = Offset(0, 12);
  static const double glowAlpha = 0.42;

  // ── Breathing glow (slow, low-amplitude "alive" pulse on the outer glow) ──
  /// Min/max opacity the breathing glow swings between (centred near
  /// [glowAlpha] so a still card and a breathing one look the same on average).
  static const double glowPulseMin = 0.34;
  static const double glowPulseMax = 0.52;

  /// One full inhale→exhale of the breathing glow.
  static const Duration glowPulsePeriod = Duration(milliseconds: 2600);

  // ── Decorative depth layer (turns the flat tint into a lit, glassy surface) ──
  /// Diagonal accent wash, strongest at the top-left corner.
  static const double washTop = 0.24;

  /// Glassy white highlight along the very top edge.
  static const double sheen = 0.12;

  /// Soft accent bloom blooming out of the bottom-right corner.
  static const double bloom = 0.22;
}

/// Wraps [child] so it shrinks to [GlassTokens.pressScale] on tap-down and
/// invokes [onTap] on release. Use on every card that navigates so taps feel
/// physical. When [onTap] is null the child is returned inert (no gesture).
class PressableCard extends StatefulWidget {
  const PressableCard({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? GlassTokens.pressScale : 1,
        duration: GlassTokens.pressDuration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A thin horizontal accent bar — the "edge" that gives each premium card a
/// small jolt of color and a clear top hierarchy line. Rounded to match the
/// card's [radius].
class AccentEdge extends StatelessWidget {
  const AccentEdge({
    super.key,
    required this.accent,
    this.radius = GlassTokens.radius,
  });

  final Color accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _Card.accentEdge,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[accent, accent.withValues(alpha: 0.35)],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
      ),
    );
  }
}

/// A soft outer glow in [accent], used to make a premium card feel lit. Wrap a
/// card with this (it adds only a box-shadow; the rounded fill comes from the
/// inner [GlassPanel]).
///
/// When [pulse] is set the glow gains a slow, low-amplitude "breathing" swing
/// so the card feels alive. The breath is a single lightweight
/// flutter_animate effect on a behind-content glow layer (no per-card
/// [AnimationController]); the content paints over it unchanged, so this is
/// cheap even with many cards on screen.
class AccentGlow extends StatelessWidget {
  const AccentGlow({
    super.key,
    required this.accent,
    required this.child,
    this.radius = GlassTokens.radius,
    this.enabled = true,
    this.pulse = false,
  });

  final Color accent;
  final Widget child;
  final double radius;
  final bool enabled;

  /// Slowly breathe the glow opacity instead of holding it steady.
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    if (!pulse) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: _Card.glowAlpha),
              blurRadius: _Card.glowBlur,
              spreadRadius: _Card.glowSpread,
              offset: _Card.glowOffset,
            ),
          ],
        ),
        child: child,
      );
    }

    // Breathing variant: paint the glow as its own layer behind the content and
    // oscillate its opacity between min/max. The child is NOT inside the
    // animated subtree, so only the cheap glow box repaints each frame.
    final Widget breathingGlow = IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: _Card.glowPulseMax),
              blurRadius: _Card.glowBlur,
              spreadRadius: _Card.glowSpread,
              offset: _Card.glowOffset,
            ),
          ],
        ),
      ),
    )
        .animate(onPlay: (AnimationController c) => c.repeat(reverse: true))
        .fadeIn(
          begin: _Card.glowPulseMin / _Card.glowPulseMax,
          duration: _Card.glowPulsePeriod,
          curve: Curves.easeInOut,
        );

    return Stack(
      children: <Widget>[
        Positioned.fill(child: breathingGlow),
        child,
      ],
    );
  }
}

/// A premium glass surface: accent-tinted [GlassPanel] with an optional top
/// accent edge and outer accent glow. This is the shared "card body" — callers
/// supply the inner content. [highlight] swaps to the stronger tint/border used
/// for selected/owned states.
class PremiumPanel extends StatelessWidget {
  const PremiumPanel({
    super.key,
    required this.accent,
    required this.child,
    this.padding,
    this.highlight = false,
    this.showEdge = true,
    this.glow = true,
    this.glowPulse = true,
    this.radius = GlassTokens.radius,
  });

  final Color accent;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool highlight;
  final bool showEdge;
  final bool glow;

  /// Slowly breathe the outer accent glow so the card feels alive. Only has an
  /// effect when [glow] is on. Defaults on — it is one cheap repeating
  /// flutter_animate effect per card (no [AnimationController] spam), and the
  /// card content is excluded from the animated subtree.
  final bool glowPulse;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final Widget panel = GlassPanel(
      radius: radius,
      tint: accent,
      tintOpacity: highlight ? _Card.tintActive : _Card.tint,
      borderColor: accent.withValues(
        alpha: highlight ? _Card.borderActive : _Card.border,
      ),
      padding: EdgeInsets.zero,
      child: Stack(
        children: <Widget>[
          // Lit, dimensional surface behind the content (accent wash + top
          // sheen + corner bloom). Cheap: layered gradients, no blur.
          Positioned.fill(child: _CardDecor(accent: accent, radius: radius)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showEdge) AccentEdge(accent: accent, radius: radius),
              Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ],
          ),
        ],
      ),
    );
    return AccentGlow(
      accent: accent,
      radius: radius,
      enabled: glow,
      pulse: glowPulse,
      child: panel,
    );
  }
}

/// Decorative depth behind a [PremiumPanel]'s content: a diagonal accent wash,
/// a glassy top sheen, and a soft corner bloom — layered gradients (no blur)
/// that turn the flat accent tint into a lit, three-dimensional surface.
class _CardDecor extends StatelessWidget {
  const _CardDecor({required this.accent, required this.radius});

  final Color accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final BorderRadius br = BorderRadius.circular(radius);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Diagonal accent wash — strongest at the top-left, fading out.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: br,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  accent.withValues(alpha: _Card.washTop),
                  accent.withValues(alpha: 0),
                ],
                stops: const <double>[0, 0.6],
              ),
            ),
          ),
          // Glassy top sheen.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: br,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.white.withValues(alpha: _Card.sheen),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const <double>[0, 0.3],
              ),
            ),
          ),
          // Soft accent bloom out of the bottom-right corner.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: br,
              gradient: RadialGradient(
                center: const Alignment(1.0, 1.1),
                radius: 0.95,
                colors: <Color>[
                  accent.withValues(alpha: _Card.bloom),
                  accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A polished horizontal list tile: leading illustration, a bold title with a
/// muted supporting line, and an optional trailing widget — all on a
/// [PremiumPanel]. Used for shop / more-games / daily / records rows so every
/// secondary card has the same strong hierarchy.
class PremiumMediaTile extends StatelessWidget {
  const PremiumMediaTile({
    super.key,
    required this.accent,
    required this.leading,
    required this.title,
    this.supporting,
    this.eyebrow,
    this.trailing,
    this.onTap,
    this.highlight = false,
    this.titleColor,
  });

  /// Accent color driving the edge / glow / tint.
  final Color accent;

  /// Leading illustration (a `GameGlyph`, `ProceduralIcon`, badge, …).
  final Widget leading;

  /// Bold primary label.
  final String title;

  /// Muted second line (price / count / status / blurb).
  final String? supporting;

  /// Optional tiny overline above the title (e.g. "MORE GAMES").
  final String? eyebrow;

  /// Optional trailing widget (a button, chip, check, chevron).
  final Widget? trailing;

  /// Tap handler — when set the whole tile is a press-scale button.
  final VoidCallback? onTap;

  /// Selected / owned styling.
  final bool highlight;

  /// Override the title color (e.g. muted for a locked row).
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final Widget body = PremiumPanel(
      accent: accent,
      highlight: highlight,
      padding: _Card.tilePad,
      child: Row(
        children: <Widget>[
          leading,
          const SizedBox(width: _Card.artGap),
          Expanded(child: _text()),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: GlassTokens.gapSmall),
            trailing!,
          ],
        ],
      ),
    );
    return PressableCard(onTap: onTap, child: body);
  }

  Widget _text() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          Text(eyebrow!, style: GlassText.overline),
          const SizedBox(height: 3),
        ],
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: titleColor == null
              ? GlassText.heading
              : GlassText.heading.copyWith(color: titleColor),
        ),
        if (supporting != null) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            supporting!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GlassText.body.copyWith(fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// A compact accent pill for a status / hint / count line (TAP, "1-4", "+10").
/// Filled-tint variant reads as a small badge sitting under a title.
class AccentTag extends StatelessWidget {
  const AccentTag({
    super.key,
    required this.label,
    required this.accent,
    this.icon,
  });

  final String label;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSmall - 6),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            // Tiny soft accent halo behind the glyph so the tag icon glows.
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.55),
                    blurRadius: 6,
                    spreadRadius: -1,
                  ),
                ],
              ),
              child: Icon(icon, color: accent, size: 12),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The default media-tile illustration size, exported for callers that build a
/// custom leading widget and want to match the tile's art footprint.
const double kPremiumTileArtSize = _Card.tileArt;
