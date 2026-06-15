/// Reusable glassmorphism components: a frosted [GlassPanel], a pressable
/// [GlassButton], and a small [GlassChip] pill. All built on `BackdropFilter`
/// clipped to a rounded rect, with a subtle top-light sheen, a hairline white
/// border and a soft outer shadow for depth.
///
/// Performance: blur sigmas + gradients are precomputed from tokens (no
/// per-frame allocation), and each panel is wrapped in a [RepaintBoundary] so a
/// pressing button never repaints siblings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'glass_tokens.dart';

/// A frosted translucent surface: ClipRRect → BackdropFilter(blur) → a
/// white-sheen gradient container with a hairline border and optional accent
/// tint. Use this as the base for every card/section.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = GlassTokens.radius,
    this.blur = GlassTokens.blur,
    this.tint,
    this.tintOpacity = GlassTokens.tintOpacity,
    this.border = true,
    this.borderColor,
    this.shadow = true,
    this.innerHighlight = true,
  });

  /// Contents of the panel.
  final Widget child;

  /// Inner padding (defaults to none so callers control density).
  final EdgeInsetsGeometry? padding;

  /// Corner radius.
  final double radius;

  /// Backdrop blur sigma.
  final double blur;

  /// Optional accent color overlaid faintly to tint the glass.
  final Color? tint;

  /// Opacity of the accent [tint] overlay.
  final double tintOpacity;

  /// Whether to draw the hairline edge.
  final bool border;

  /// Override the default white border (e.g. an accent edge).
  final Color? borderColor;

  /// Whether to cast a soft outer shadow for depth.
  final bool shadow;

  /// Whether to draw the thin glassy highlight line that catches light along
  /// the very top inner edge (sells the frosted bevel). Cheap: one gradient
  /// strip, no blur. Defaults on; pass `false` for flat surfaces.
  final bool innerHighlight;

  @override
  Widget build(BuildContext context) {
    final BorderRadius shape = BorderRadius.circular(radius);
    final Color edge = borderColor ??
        GlassColors.frost.withValues(alpha: GlassTokens.borderOpacity);

    // Fake frosted glass: a translucent light→dark gradient fill instead of a
    // BackdropFilter blur. The blur was the menu's main lag source (one GPU
    // backdrop pass per card); this reads as glass and is cheap to draw.
    // The sheen is a touch stronger at the top so the surface reads lit, then
    // falls to the deep base for depth.
    Widget panel = ClipRRect(
      borderRadius: shape,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              GlassColors.frost.withValues(alpha: GlassTokens.sheenTop + 0.10),
              GlassColors.frost.withValues(alpha: GlassTokens.sheenTop + 0.02),
              GlassColors.base.withValues(alpha: 0.52),
            ],
            stops: const <double>[0.0, 0.22, 0.92],
          ),
          border: border ? Border.all(color: edge, width: 1) : null,
        ),
        child: _withHighlight(
          shape,
          tint == null
              ? child
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: shape,
                    color: tint!.withValues(alpha: tintOpacity),
                  ),
                  child: child,
                ),
        ),
      ),
    );

    if (!shadow) return RepaintBoundary(child: panel);

    // Two stacked shadows: a soft ambient pool plus a slightly deeper, tighter
    // drop for lift. Both are cheap box-shadows (no blur pass on the content).
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: GlassColors.base.withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: GlassColors.base.withValues(alpha: 0.50),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: panel,
      ),
    );
  }

  /// Overlays a thin top-edge highlight line on [content] (skipped when
  /// [innerHighlight] is false). A single non-pointer-hitting gradient strip
  /// that fakes the lit bevel of real frosted glass.
  Widget _withHighlight(BorderRadius shape, Widget content) {
    if (!innerHighlight) return content;
    return Stack(
      children: <Widget>[
        content,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: radius,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: shape.topLeft,
                  topRight: shape.topRight,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    GlassColors.frost.withValues(alpha: 0.22),
                    GlassColors.frost.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A big, finger-friendly frosted button. Scales to [GlassTokens.pressScale] on
/// tap-down; when [primary] it gains an accent glow ring. Label is bold +
/// uppercase with wide letter-spacing.
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.accent,
    this.primary = false,
    this.height = GlassTokens.buttonHeight,
    this.trailing,
  });

  /// Button caption (rendered uppercase).
  final String label;

  /// Tap handler.
  final VoidCallback onTap;

  /// Optional leading icon.
  final IconData? icon;

  /// Accent color for the glow / tint (defaults to violet).
  final Color? accent;

  /// Primary buttons get a stronger accent tint + glow ring.
  final bool primary;

  /// Fixed button height.
  final double height;

  /// Optional trailing widget (e.g. a notification dot).
  final Widget? trailing;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  /// Bumped on every tap so a one-shot highlight sweep replays. Used as the
  /// flutter_animate key — changing it restarts the (non-repeating) sweep.
  int _tapCount = 0;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _onTap() {
    setState(() => _tapCount++);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? GlassColors.violet;
    // Crisper press: primary buttons dip a touch deeper than the shared token
    // so the big CTA feels punchier; secondary keep the standard press.
    final double pressScale =
        widget.primary ? GlassTokens.pressScale - 0.02 : GlassTokens.pressScale;

    final Widget content = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (widget.icon != null) ...<Widget>[
              Icon(widget.icon, color: GlassColors.text, size: 22),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                widget.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GlassText.label,
              ),
            ),
          ],
        ),
        if (widget.trailing != null)
          Positioned(top: 8, right: 8, child: widget.trailing!),
      ],
    );

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: _onTap,
      child: AnimatedScale(
        scale: _pressed ? pressScale : 1,
        duration: GlassTokens.pressDuration,
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GlassTokens.radius),
            // Primary: a strong accent bloom (breathes below). Secondary: a
            // faint accent border-glow so even quiet buttons feel lit.
            boxShadow: widget.primary
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 26,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.22),
                      blurRadius: 14,
                      spreadRadius: -6,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: _buttonSurface(accent, content),
        ),
      ),
    );
  }

  /// The glass surface for the button, with a one-shot tap highlight sweep and
  /// (for primary) a slow breathing glow overlay.
  Widget _buttonSurface(Color accent, Widget content) {
    final Widget panel = GlassPanel(
      radius: GlassTokens.radius,
      tint: accent,
      tintOpacity: widget.primary ? 0.28 : 0.12,
      borderColor: widget.primary ? accent.withValues(alpha: 0.7) : null,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: <Widget>[
            // Quick highlight sweep that replays each tap (keyed by _tapCount).
            Positioned.fill(
              child: IgnorePointer(
                child: _TapSweep(
                  key: ValueKey<int>(_tapCount),
                  active: _tapCount > 0,
                  radius: GlassTokens.radius,
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );

    if (!widget.primary) return panel;

    // Gentle breathing bloom: a slow, low-amplitude scale on a soft accent
    // halo behind the panel. One lightweight repeating effect, not a per-frame
    // controller, so it is cheap even with several primary buttons on screen.
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GlassTokens.radius),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.40),
                    blurRadius: 22,
                    spreadRadius: -8,
                  ),
                ],
              ),
            ),
          )
              .animate(
                onPlay: (AnimationController c) => c.repeat(reverse: true),
              )
              .fadeIn(duration: 1800.ms, begin: 0.45)
              .scaleXY(
                begin: 0.97,
                end: 1.02,
                duration: 1800.ms,
                curve: Curves.easeInOut,
              ),
        ),
        panel,
      ],
    );
  }
}

/// A one-shot diagonal light sweep that crosses a button surface once when
/// [active] flips true. Built on flutter_animate's [shimmer] (no extra
/// controller wiring); rebuilding with a fresh key replays it on each tap.
class _TapSweep extends StatelessWidget {
  const _TapSweep({
    super.key,
    required this.active,
    required this.radius,
  });

  final bool active;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();
    // A faint white fill is the sweep "material"; shimmer slides a brighter
    // band across it, then the whole thing fades out so nothing lingers.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: GlassColors.frost.withValues(alpha: 0.06),
        child: const SizedBox.expand(),
      ),
    )
        .animate()
        .shimmer(
          duration: 520.ms,
          color: GlassColors.frost.withValues(alpha: 0.55),
        )
        .fadeOut(delay: 380.ms, duration: 220.ms);
  }
}

/// A small frosted pill for coins / streak / settings. Optional [accent] tints
/// the border + icon. Tappable when [onTap] is supplied.
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.icon,
    this.accent,
    this.onTap,
  });

  /// Chip caption.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Accent for the icon + border.
  final Color? accent;

  /// Optional tap handler (makes the chip interactive).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color accentColor = accent ?? GlassColors.violet;
    final Widget chip = GlassPanel(
      radius: GlassTokens.radiusSmall,
      blur: GlassTokens.blurChip,
      shadow: false,
      innerHighlight: false,
      borderColor: accentColor.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, color: accentColor, size: 18),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: GlassText.label.copyWith(fontSize: 13, letterSpacing: 0.4),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: chip,
    );
  }
}
