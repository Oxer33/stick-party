/// Reusable glassmorphism components: a frosted [GlassPanel], a pressable
/// [GlassButton], and a small [GlassChip] pill. All built on `BackdropFilter`
/// clipped to a rounded rect, with a subtle top-light sheen, a hairline white
/// border and a soft outer shadow for depth.
///
/// Performance: blur sigmas + gradients are precomputed from tokens (no
/// per-frame allocation), and each panel is wrapped in a [RepaintBoundary] so a
/// pressing button never repaints siblings.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final BorderRadius shape = BorderRadius.circular(radius);
    final Color edge = borderColor ??
        GlassColors.frost.withValues(alpha: GlassTokens.borderOpacity);

    Widget panel = ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: shape,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                GlassColors.frost.withValues(alpha: GlassTokens.sheenTop),
                GlassColors.frost.withValues(alpha: GlassTokens.sheenBottom),
              ],
            ),
            border: border ? Border.all(color: edge, width: 1) : null,
          ),
          child: tint == null
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

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: GlassColors.base.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: panel,
      ),
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

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? GlassColors.violet;

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
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? GlassTokens.pressScale : 1,
        duration: GlassTokens.pressDuration,
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GlassTokens.radius),
            boxShadow: widget.primary
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 26,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: GlassPanel(
            radius: GlassTokens.radius,
            tint: accent,
            tintOpacity: widget.primary ? 0.28 : 0.12,
            borderColor:
                widget.primary ? accent.withValues(alpha: 0.7) : null,
            child: SizedBox(
              height: widget.height,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
