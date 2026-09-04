import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Fixed status/semantic colors -- not user-customizable, so off and
/// breaker status indicators stay legible regardless of accent choice.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF1565C0);
  static const danger = Color(0xFFD32F2F);
  static const warning = Color(0xFFF9A825);
  static const success = Color(0xFF2E7D32);
  static const backgroundLight = Color(0xFFF8F9FA);
  static const backgroundDark = Color(0xFF121212);
}

class AccentPreset {
  const AccentPreset(this.name, this.color);

  final String name;
  final Color color;
}

const kAccentPresets = [
  AccentPreset('Blue', AppColors.primary),
  AccentPreset('Teal', Color(0xFF00796B)),
  AccentPreset('Indigo', Color(0xFF3949AB)),
  AccentPreset('Purple', Color(0xFF6A1B9A)),
  AccentPreset('Deep Orange', Color(0xFFD84315)),
  AccentPreset('Pink', Color(0xFFD81B60)),
  AccentPreset('Amber', Color(0xFFFFB300)),
  AccentPreset('Lime', Color(0xFFC0CA33)),
  AccentPreset('Cyan', Color(0xFF00ACC1)),
  AccentPreset('Red', Color(0xFFE53935)),
];

class AppTheme {
  AppTheme._();

  static ThemeData light(
    Color seed, {
    double cardRadius = DesignTokens.radiusMedium,
    VisualDensity visualDensity = VisualDensity.standard,
  }) =>
      _build(
        seed,
        Brightness.light,
        cardRadius: cardRadius,
        visualDensity: visualDensity,
      );

  static ThemeData dark(
    Color seed, {
    double cardRadius = DesignTokens.radiusMedium,
    bool trueBlack = false,
    VisualDensity visualDensity = VisualDensity.standard,
  }) =>
      _build(
        seed,
        Brightness.dark,
        cardRadius: cardRadius,
        trueBlack: trueBlack,
        visualDensity: visualDensity,
      );

  static ThemeData _build(
    Color seed,
    Brightness brightness, {
    required double cardRadius,
    bool trueBlack = false,
    required VisualDensity visualDensity,
  }) {
    final isDark = brightness == Brightness.dark;
    
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      primary: seed,
      error: AppColors.danger,
      brightness: brightness,
      surface: isDark ? (trueBlack ? Colors.black : const Color(0xFF1E1E1E)) : Colors.white,
    );

    final scaffoldBg = isDark 
        ? (trueBlack ? Colors.black : AppColors.backgroundDark) 
        : AppColors.backgroundLight;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      visualDensity: visualDensity,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? colorScheme.surface : seed,
        foregroundColor: Colors.white,
        elevation: DesignTokens.elevationNone,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: DesignTokens.elevationNone,
        margin: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMedium, 
          vertical: DesignTokens.spacingSmall
        ),
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingMedium),
          elevation: DesignTokens.elevationNone,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius / 1.5),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius / 1.5),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cardRadius / 1.5),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(DesignTokens.spacingMedium),
      ),
    );
  }
}
