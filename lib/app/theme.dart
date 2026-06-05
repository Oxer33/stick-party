import 'package:flutter/material.dart';

/// Visual design tokens for the Stick Party shell. Centralised so screens never
/// hardcode raw radii / paddings (no magic numbers at call sites).
class AppTokens {
  AppTokens._();

  /// Corner radius for cards, buttons and dialogs.
  static const double radius = 18;

  /// Smaller radius for chips / badges.
  static const double radiusSmall = 12;

  /// Standard screen padding.
  static const double pagePadding = 20;

  /// Gap between stacked elements.
  static const double gap = 16;

  /// Minimum height for primary tappable buttons (thumb-friendly).
  static const double buttonHeight = 64;
}

/// Brand palette for the dark "party" theme.
class AppColors {
  AppColors._();

  /// Near-black app background.
  static const Color background = Color(0xFF0E0F13);

  /// Slightly raised surface (cards).
  static const Color surface = Color(0xFF1A1C22);

  /// Higher surface for nested elements.
  static const Color surfaceHigh = Color(0xFF24262E);

  /// Vivid primary accent (electric magenta-pink).
  static const Color primary = Color(0xFFFF2D78);

  /// Secondary accent (cyan).
  static const Color secondary = Color(0xFF22E0D6);

  /// Tertiary accent (warm gold) for coins / highlights.
  static const Color gold = Color(0xFFFFC93C);

  /// Streak flame accent.
  static const Color flame = Color(0xFFFF7A1A);

  /// Primary readable text.
  static const Color onSurface = Color(0xFFF4F5F7);

  /// Muted text.
  static const Color onSurfaceMuted = Color(0xFF9AA0AC);
}

/// Material 3 dark "party" theme. Default platform font (no google_fonts).
ThemeData stickPartyTheme() {
  const ColorScheme scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.secondary,
    onSecondary: Color(0xFF06201E),
    tertiary: AppColors.gold,
    onTertiary: Color(0xFF231A00),
    error: Color(0xFFFF5A5A),
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    surfaceContainerHighest: AppColors.surfaceHigh,
    outline: Color(0xFF3A3D47),
  );

  final ThemeData base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
  );

  final RoundedRectangleBorder roundedShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTokens.radius),
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
        color: AppColors.onSurface,
      ),
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        color: AppColors.onSurface,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: AppColors.onSurfaceMuted,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: roundedShape,
      clipBehavior: Clip.antiAlias,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: AppColors.onSurface,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(AppTokens.buttonHeight),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
        shape: roundedShape,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppTokens.buttonHeight),
        shape: roundedShape,
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.onSurface,
        minimumSize: const Size.fromHeight(AppTokens.buttonHeight),
        side: const BorderSide(color: AppColors.primary, width: 2),
        shape: roundedShape,
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.primary,
      thumbColor: AppColors.primary,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: roundedShape,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.surfaceHigh,
    ),
  );
}
