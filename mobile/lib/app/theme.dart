import 'package:flutter/material.dart';

/// PDD Petty Cash palette per CLAUDE.md §8 — approximated from the approved mockups.
///
/// Do not introduce off-palette colors. New tokens must be added here and named.
abstract final class AppColors {
  // Brand
  static const Color brandBrown = Color(0xFF5C4A2F);
  static const Color brandBrownDark = Color(0xFF3F311F);
  static const Color cream = Color(0xFFF5EFE3);
  static const Color creamSoft = Color(0xFFFAF6EC);
  static const Color goldOlive = Color(0xFFB89B5E);

  // Status
  static const Color success = Color(0xFF6BA368);
  static const Color inflow = Color(0xFF6BA368);
  static const Color outflow = Color(0xFFC0463A);
  static const Color warning = Color(0xFFD9A23A);

  // Surfaces
  static const Color surface = Color(0xFFFAF6EC);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color divider = Color(0x1A000000);
  static const Color textPrimary = Color(0xFF2D2418);
  static const Color textSecondary = Color(0xFF6E6253);
  static const Color textOnBrand = Color(0xFFFAF6EC);

  // Category palette per screen-inventory.md §11 — LOCKED.
  // These map to ExpenseCategory.code; any new category must add a color here.
  static const Map<String, Color> categoryColors = <String, Color>{
    'FOOD': Color(0xFFCF7A4F),
    'TRANSPORT': Color(0xFF4F7CB8),
    'HOTEL': Color(0xFF1F3A66),
    'PHONE': Color(0xFF6E6253),
    'ENTERTAINMENT': Color(0xFF7B5BA8),
    'TIPS': Color(0xFFB89B5E),
    'TRAVEL': Color(0xFF6BA368),
    'OTHERS': Color(0xFFC0463A),
  };

  static Color forCategory(String code) =>
      categoryColors[code.toUpperCase()] ?? textSecondary;
}

abstract final class AppTypography {
  static const String displayFamily = 'PDDDisplay';

  static TextTheme textTheme(BuildContext context) {
    final TextTheme base = Theme.of(context).textTheme;
    return base.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );
  }
}

abstract final class AppRadii {
  static const Radius card = Radius.circular(16);
  static const Radius button = Radius.circular(28);
  static const Radius chip = Radius.circular(12);
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

ThemeData buildPddTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brandBrown,
    primary: AppColors.brandBrown,
    onPrimary: AppColors.textOnBrand,
    secondary: AppColors.goldOlive,
    surface: AppColors.surface,
    error: AppColors.outflow,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    cardTheme: const CardThemeData(
      color: AppColors.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brandBrown,
        foregroundColor: AppColors.textOnBrand,
        minimumSize: const Size(double.infinity, 52),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(AppRadii.button),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brandBrown,
        side: const BorderSide(color: AppColors.brandBrown),
        minimumSize: const Size(double.infinity, 52),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(AppRadii.button),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1),
  );
}
