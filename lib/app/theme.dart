/// The Stick Party Material 3 theme. The visual identity lives in the glass
/// design system ([GlassTokens]/[GlassColors] in `widgets/glass_tokens.dart`);
/// this file wires those tokens into a dark M3 [ThemeData] with a transparent
/// scaffold so the animated mesh background shows through every screen.
library;

import 'package:flutter/material.dart';

import 'widgets/glass_tokens.dart';

/// Material 3 dark "glass" theme. Default platform font (no google_fonts),
/// styled via weight + letter-spacing. Exported as [stickPartyTheme].
ThemeData stickPartyTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: GlassColors.violet,
    brightness: Brightness.dark,
  ).copyWith(
    primary: GlassColors.violet,
    secondary: GlassColors.magenta,
    tertiary: GlassColors.cyan,
    surface: GlassColors.base,
    onSurface: GlassColors.text,
  );

  final ThemeData base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Transparent: the MeshGradientBackground (via GlassScaffold) is the bg.
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
  );

  final RoundedRectangleBorder roundedShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(GlassTokens.radius),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: GlassColors.text,
      displayColor: GlassColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: GlassColors.text,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: GlassColors.baseHigh,
      shape: roundedShape,
      titleTextStyle: GlassText.heading.copyWith(fontSize: 18),
      contentTextStyle: GlassText.body,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GlassColors.baseHigh,
      contentTextStyle: GlassText.body.copyWith(color: GlassColors.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassTokens.radiusSmall),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: GlassColors.violet,
      inactiveTrackColor: Color(0x33FFFFFF),
      thumbColor: GlassColors.violet,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: GlassColors.violet,
      linearTrackColor: Color(0x22FFFFFF),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: GlassColors.textMuted,
        textStyle: GlassText.label.copyWith(fontSize: 13),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GlassColors.violet,
        foregroundColor: GlassColors.text,
        shape: roundedShape,
        textStyle: GlassText.label,
      ),
    ),
  );
}
