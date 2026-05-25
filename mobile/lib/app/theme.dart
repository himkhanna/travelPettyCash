import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the PDD Delegation Expenses app.
///
/// Aligned with the Protocol Department palette already in use by the
/// admin CMS (`lib/features/cms/presentation/widgets/cms_theme.dart`) —
/// near-black brand, warm off-white surfaces, restrained ceremonial gold
/// for sign-off flourishes, and an action-green accent.
///
/// The mobile app previously used a forest-green palette ("brand
/// 0xFF0E3A35"); this re-tokenisation re-targets every existing semantic
/// name (`brand`, `gold`, `ink1`, …) so per-screen widgets pick up the
/// new theme without per-screen edits.
///
/// **Adding tokens:** new colors must be added here under a semantic name
/// — not inlined as hex anywhere in feature code.
abstract final class AppColors {
  // ───────── Surfaces ─────────
  /// Page-level canvas (outermost background). Warm off-white, matches the
  /// CMS dashboard's `surface`.
  static const Color bgPage = Color(0xFFFAF8F4);

  /// In-app surface — the background under most widgets when you peel
  /// content off the page canvas.
  static const Color bgApp = Color(0xFFFAF8F4);

  /// Card / panel surface. Solid white for elevation contrast on bgApp.
  static const Color bgCard = Color(0xFFFFFFFF);

  /// Slightly-elevated band for nested sections (e.g. category strip,
  /// table headers).
  static const Color bgElev = Color(0xFFF1EFEA);

  /// Inset / input wells (read-only computed fields).
  static const Color bgInset = Color(0xFFEBE9E4);

  // ───────── Ink (text) ─────────
  /// Primary text. High contrast on every surface above.
  static const Color ink1 = Color(0xFF111418);

  /// Secondary text — body copy intensity.
  static const Color ink2 = Color(0xFF3F4248);

  /// Muted / placeholder text — list subtitles, meta lines.
  static const Color ink3 = Color(0xFF6B6E76);

  /// Disabled / divider-on-text intensity.
  static const Color ink4 = Color(0xFF9CA0A8);

  // ───────── Brand (near-black ink) ─────────
  /// Brand primary — buttons, header bands, donut arcs, brand chips.
  static const Color brand = Color(0xFF111418);

  /// Brand pressed / deeper tone for headers + hero gradients.
  static const Color brandDeep = Color(0xFF06080A);

  /// Translucent brand background for active states / icon tiles.
  static const Color brandTint = Color(0xFFEDEEF1);

  /// Softest brand background — for low-contrast informational panels.
  static const Color brandSoft = Color(0xFFF4F5F7);

  // ───────── Accent (ceremonial gold) ─────────
  /// Accent for sign-off, premium CTAs, decorative highlights.
  static const Color gold = Color(0xFFC7A465);
  static const Color goldSoft = Color(0xFFF4EAD0);
  static const Color goldDeep = Color(0xFF8D7331);

  // ───────── Semantic ─────────
  /// Action green — primary CTAs (e.g. "+ New trip"), inflow indicators.
  static const Color green = Color(0xFF1E9E5C);
  static const Color greenSoft = Color(0xFFE0F1E8);
  static const Color red = Color(0xFFC54B3F);
  static const Color redSoft = Color(0xFFFAE0DC);
  static const Color amber = Color(0xFFD08A2A);
  static const Color amberSoft = Color(0xFFFAE7C9);
  static const Color blue = Color(0xFF2E5DA8);
  static const Color blueSoft = Color(0xFFE0E8F4);

  // ───────── Lines ─────────
  static const Color line = Color(0xFFE8E5DE);
  static const Color lineStrong = Color(0xFFD0CCC3);

  // ───────── Legacy aliases (to be removed after screen rebuild) ─────────
  // These keep brown-palette references compiling. When you touch a widget
  // that uses one of these, migrate it to the semantic name on the right.
  static const Color brandBrown = brand;
  static const Color brandBrownDark = brandDeep;
  static const Color cream = bgElev;
  static const Color creamSoft = bgApp;
  static const Color goldOlive = gold;
  static const Color success = green;
  static const Color inflow = green;
  static const Color outflow = red;
  static const Color warning = amber;
  static const Color surface = bgApp;
  static const Color surfaceCard = bgCard;
  static const Color divider = line;
  static const Color textPrimary = ink1;
  static const Color textSecondary = ink3;
  static const Color textOnBrand = bgCard;

  // ───────── Category palette ─────────
  // 8-key map keyed on backend ExpenseCategory.code. Aligned to the
  // designer's category-color set, extended to cover the codes the Spring
  // backend seeds (PHONE/ENTERTAINMENT/TIPS/TRAVEL aren't in the prototype
  // — we pick adjacent palette entries that read consistently).
  static const Map<String, Color> categoryColors = <String, Color>{
    'FOOD': amber, // meals — coffee
    'TRANSPORT': blue, // transp — car
    'HOTEL': Color(0xFF7E4B2E), // lodge — bed (brown)
    'PHONE': ink2, // office tone — handset
    'ENTERTAINMENT': Color(0xFF7B5BA8), // purple — keeps current
    'TIPS': red, // gifts adjacent
    'TRAVEL': green, // plane — green
    'OTHERS': ink3, // muted
  };

  static Color forCategory(String code) =>
      categoryColors[code.toUpperCase()] ?? ink3;

  static Color forCategoryBg(String code) {
    switch (code.toUpperCase()) {
      case 'FOOD':
        return amberSoft;
      case 'TRANSPORT':
        return blueSoft;
      case 'HOTEL':
        return const Color(0xFFEFE0D2);
      case 'PHONE':
        return const Color(0xFFE5E8E6);
      case 'ENTERTAINMENT':
        return const Color(0xFFE6DDF1);
      case 'TIPS':
        return redSoft;
      case 'TRAVEL':
        return greenSoft;
      case 'OTHERS':
      default:
        return const Color(0xFFEFEDE6);
    }
  }
}

/// Typography per design handoff: Geist for body/headings, Geist Mono with
/// tabular numerals for monetary amounts. Pulled from Google Fonts so we
/// don't need to ship the font as an asset; the package caches per-app.
abstract final class AppTypography {
  /// The Google Fonts family used for body + heading text. The handoff
  /// specifies Geist, but the google_fonts package version pinned in this
  /// repo (6.2.1) predates the addition of Geist to its catalog. Inter is
  /// the closest visual substitute — both are clean geometric sans-serifs
  /// designed for UI density; we'll flip to "Geist" the moment we bump
  /// google_fonts to a version that ships it.
  static const String _sansFamily = 'Inter';
  static const String _monoFamily = 'JetBrains Mono';

  /// Returns a TextStyle in the sans family with the supplied properties
  /// merged in. Prefer this over direct GoogleFonts calls in feature code.
  static TextStyle geist({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.getFont(
      _sansFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.ink1,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Mono font for amounts. Use the `.num` semantic — anything monetary.
  /// Always tabular so digits line up vertically in tables and totals.
  static TextStyle geistMono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.getFont(
      _monoFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.ink1,
      letterSpacing: letterSpacing ?? -0.01,
    ).copyWith(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }

  /// Tiny uppercase label — "BALANCE", "SPENT", section headers.
  static TextStyle microLabel({Color? color}) => geist(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.06 * 11,
        color: color ?? AppColors.ink3,
      );

  /// Body default.
  static TextStyle body({Color? color}) => geist(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.ink1,
        height: 1.45,
      );

  /// Subtitle / meta.
  static TextStyle sub({Color? color}) => geist(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.ink3,
      );

  /// Section heading.
  static TextStyle heading({Color? color}) => geist(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.ink1,
        letterSpacing: -0.015 * 22,
      );

  /// Hero amount on balance cards (top-right of bigger UI moments).
  static TextStyle hero({Color? color}) => geistMono(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.bgCard,
        letterSpacing: -0.02 * 32,
      );

  static const String displayFamily = 'Geist';
}

/// Radius scale per handoff: 8/12/14/16/18/20/22/28.
abstract final class AppRadii {
  static const Radius xs = Radius.circular(8);
  static const Radius sm = Radius.circular(12);
  static const Radius md = Radius.circular(16);
  static const Radius lg = Radius.circular(20);
  static const Radius xl = Radius.circular(28);

  // Legacy aliases.
  static const Radius card = md;
  static const Radius button = Radius.circular(14);
  static const Radius chip = sm;
}

/// Spacing scale per handoff: 4/6/8/10/12/14/16/18/20/24.
abstract final class AppSpacing {
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s18 = 18;
  static const double s20 = 20;
  static const double s24 = 24;

  // Legacy aliases — same physical values, semantic names.
  static const double xs = s4;
  static const double sm = s8;
  static const double md = s16;
  static const double lg = s24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Shadow recipes per handoff. The mobile theme uses a neutral dark tint
/// (formerly forest-green) so the new near-black brand doesn't cast a
/// muddy coloured shadow against the off-white canvas.
abstract final class AppShadows {
  /// Elevated card — used on balance cards, action tiles.
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x40111418),
      blurRadius: 28,
      offset: Offset(0, 12),
      spreadRadius: -16,
    ),
  ];

  /// FAB shadow — stronger and tighter than card.
  static const List<BoxShadow> fab = <BoxShadow>[
    BoxShadow(
      color: Color(0x60111418),
      blurRadius: 28,
      offset: Offset(0, 14),
      spreadRadius: -10,
    ),
  ];

  /// Toast/modal float — neutral, not brand-tinted.
  static const List<BoxShadow> toast = <BoxShadow>[
    BoxShadow(
      color: Color(0x4D000000),
      blurRadius: 28,
      offset: Offset(0, 14),
      spreadRadius: -10,
    ),
  ];
}

/// Reusable gradient for the hero balance card — deep forest green with a
/// hint of the deeper tone at top-right to give it depth.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[AppColors.brand, AppColors.brandDeep],
);

ThemeData buildPddTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    primary: AppColors.brand,
    onPrimary: AppColors.bgCard,
    secondary: AppColors.gold,
    surface: AppColors.bgApp,
    error: AppColors.red,
    brightness: Brightness.light,
  );

  // Inter applied as the global text theme (Geist substitute — see
  // `AppTypography._sansFamily`). Headlines + body share the family; mono
  // is opted into per-call via AppTypography.geistMono (which now resolves
  // to JetBrains Mono).
  final TextTheme textTheme = GoogleFonts.getTextTheme(
    'Inter',
    ThemeData.light().textTheme,
  ).apply(
    bodyColor: AppColors.ink1,
    displayColor: AppColors.ink1,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.bgApp,
    cardTheme: const CardThemeData(
      color: AppColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.md),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bgApp,
      foregroundColor: AppColors.ink1,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.geist(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.ink1,
      ),
    ),
    // Buttons: 48px tall, 14 radius, 18 horizontal padding per handoff.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.bgCard,
        minimumSize: const Size(double.infinity, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(AppRadii.button),
        ),
        textStyle: AppTypography.geist(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brand,
        side: const BorderSide(color: AppColors.line),
        minimumSize: const Size(double.infinity, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(AppRadii.button),
        ),
        textStyle: AppTypography.geist(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgCard,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(AppRadii.sm),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(AppRadii.sm),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(AppRadii.sm),
        borderSide: BorderSide(color: AppColors.brand, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
  );
}
