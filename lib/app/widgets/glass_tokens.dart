/// Glassmorphism design tokens: spacing, radii, blur, opacities, the accent
/// palette and shared text styles. Centralised so glass widgets and screens
/// never hardcode raw numbers / colors at call sites (no magic numbers).
library;

import 'package:flutter/material.dart';

/// Layout + glass tuning tokens.
class GlassTokens {
  GlassTokens._();

  /// Default panel / card corner radius.
  static const double radius = 24;

  /// Smaller radius for chips / pills / badges.
  static const double radiusSmall = 14;

  /// Standard screen edge padding.
  static const double pagePadding = 20;

  /// Gap between stacked elements.
  static const double gap = 16;

  /// Smaller gap.
  static const double gapSmall = 10;

  /// Default backdrop blur sigma for panels.
  static const double blur = 18;

  /// Lighter blur for small chips (cheaper).
  static const double blurChip = 12;

  /// Minimum height for primary tappable glass buttons (thumb-friendly).
  static const double buttonHeight = 64;

  /// White-gradient top opacity for the frosted sheen.
  static const double sheenTop = 0.14;

  /// White-gradient bottom opacity for the frosted sheen.
  static const double sheenBottom = 0.04;

  /// 1px border opacity (white) on glass edges.
  static const double borderOpacity = 0.18;

  /// Default accent-tint overlay opacity inside a panel.
  static const double tintOpacity = 0.10;

  /// Scale a glass button shrinks to on tap-down.
  static const double pressScale = 0.96;

  /// Press animation duration.
  static const Duration pressDuration = Duration(milliseconds: 110);

  /// Base entrance animation duration for screen content.
  static const Duration entrance = Duration(milliseconds: 420);

  /// Per-item stagger for entrance lists/grids.
  static const Duration stagger = Duration(milliseconds: 60);
}

/// Glass color palette. The mesh background owns the deep base; everything in
/// the foreground is translucent white + vivid accents.
class GlassColors {
  GlassColors._();

  /// Deep indigo / near-black base behind everything.
  static const Color base = Color(0xFF0C0A18);

  /// Slightly lighter indigo used in the mesh base gradient.
  static const Color baseHigh = Color(0xFF15102B);

  /// Primary accent: vivid violet.
  static const Color violet = Color(0xFF8B5CF6);

  /// Secondary accent: magenta / pink.
  static const Color magenta = Color(0xFFEC4899);

  /// Tertiary accent: cyan.
  static const Color cyan = Color(0xFF22D3EE);

  /// Warm amber for coins / highlights.
  static const Color amber = Color(0xFFFBBF24);

  /// Streak flame accent.
  static const Color flame = Color(0xFFFB7234);

  /// Bright readable text on glass.
  static const Color text = Color(0xFFF5F3FF);

  /// Muted text on glass.
  static const Color textMuted = Color(0xFFB6B2D6);

  /// Pure frosted white used for sheens / borders.
  static const Color frost = Colors.white;
}

/// Shared text styles: bold display/title with negative letter-spacing for
/// headings, plus body + label. Kept here so screens stay DRY.
class GlassText {
  GlassText._();

  /// Big hero title (e.g. the home logo word).
  static const TextStyle display = TextStyle(
    fontWeight: FontWeight.w900,
    fontSize: 60,
    height: 0.98,
    letterSpacing: -2,
    color: GlassColors.text,
  );

  /// Top-bar / section title.
  static const TextStyle title = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 22,
    letterSpacing: -0.5,
    color: GlassColors.text,
  );

  /// Card / list-item heading.
  static const TextStyle heading = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 16,
    letterSpacing: -0.2,
    color: GlassColors.text,
  );

  /// Body copy.
  static const TextStyle body = TextStyle(
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: GlassColors.textMuted,
  );

  /// Uppercase button / chip label.
  static const TextStyle label = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 14,
    letterSpacing: 1.4,
    color: GlassColors.text,
  );

  /// Tiny eyebrow / overline label.
  static const TextStyle overline = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 11,
    letterSpacing: 2,
    color: GlassColors.textMuted,
  );
}

/// Default vivid gradient used by [gradientText] and accent glows.
const LinearGradient kAccentGradient = LinearGradient(
  colors: <Color>[GlassColors.violet, GlassColors.magenta, GlassColors.cyan],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Paints [text] with a horizontal [gradient] via a [ShaderMask]. Falls back to
/// [kAccentGradient]. The base text color must be opaque white for the shader
/// to show through unaltered.
Widget gradientText(
  String text, {
  required TextStyle style,
  Gradient gradient = kAccentGradient,
  TextAlign textAlign = TextAlign.start,
}) {
  return ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: (Rect bounds) => gradient.createShader(bounds),
    child: Text(
      text,
      textAlign: textAlign,
      style: style.copyWith(color: GlassColors.frost),
    ),
  );
}
