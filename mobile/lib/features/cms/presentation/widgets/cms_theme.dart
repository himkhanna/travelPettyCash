import 'package:flutter/material.dart';

import '../../../../app/theme.dart' as mobile;

/// CMS-only design tokens — keeps the admin console aligned with the
/// Dubai Protocol Department web look (deep navy, off-white surfaces,
/// restrained gold). Kept separate from `AppColors` so the mobile app's
/// forest-green + cream theme stays unchanged.
///
/// Field names mirror `AppColors` exactly so existing CMS code can swap
/// `AppColors` → `CmsColors` with no other edits.
abstract final class CmsColors {
  CmsColors._();

  // ───────── Brand (near-black ink) ─────────
  /// Primary ink for text + chips. The mockup uses near-black rather
  /// than the earlier deep navy — pairs better with the cream/white
  /// canvas and the green action button.
  static const Color brand = Color(0xFF111418);
  static const Color brandBrown = brand;        // legacy alias
  static const Color brandBrownDark = Color(0xFF06080A);

  /// Pale tint for selected sidebar items + chip backgrounds.
  static const Color brandTint = Color(0xFFEDEEF1);
  static const Color brandSoft = Color(0xFFF4F5F7);

  // ───────── Accent (action green) ─────────
  /// Primary CTA accent — matches the "+ New trip" button in the mockup.
  static const Color accent = Color(0xFF1E9E5C);
  static const Color accentDeep = Color(0xFF177A47);
  static const Color accentSoft = Color(0xFFE0F1E8);

  // ───────── Ceremonial gold (kept for super-admin badges, signatures) ─────────
  static const Color gold = Color(0xFFC7A465);
  static const Color goldOlive = gold;          // legacy alias
  static const Color goldSoft = Color(0xFFF4EAD0);
  static const Color goldDeep = Color(0xFF8D7331);

  // ───────── Surfaces ─────────
  /// Outer canvas — warm off-white, the dashboard's main background.
  static const Color surface = Color(0xFFFAF8F4);
  /// Card / panel surface — pure white for contrast against the canvas.
  static const Color surfaceCard = Color(0xFFFFFFFF);
  /// Sidebar background — a hair lighter than the canvas so the rail
  /// reads as a distinct surface without a heavy divider.
  static const Color sidebarBg = Color(0xFFFCFAF6);
  /// Slightly inset band (table headers, secondary panels).
  static const Color bgElev = Color(0xFFF1EFEA);
  /// Read-only wells.
  static const Color bgInset = Color(0xFFEBE9E4);
  /// Alias for top-level page surface (some screens reference this).
  static const Color bgCard = surfaceCard;
  static const Color cream = bgElev;            // legacy alias

  // ───────── Ink (text) ─────────
  static const Color textPrimary = Color(0xFF111418);
  static const Color textSecondary = Color(0xFF6B6E76);
  static const Color textTertiary = Color(0xFF9CA0A8);
  // Body-copy intensity — between primary and secondary.
  static const Color textBody = Color(0xFF3F4248);

  // ───────── Lines ─────────
  static const Color divider = Color(0xFFE8E5DE);
  static const Color line = divider;
  static const Color lineStrong = Color(0xFFD0CCC3);

  // ───────── Semantic ─────────
  static const Color success = accent;
  static const Color green = accent;
  static const Color greenSoft = accentSoft;

  static const Color outflow = Color(0xFFC54B3F);
  static const Color red = outflow;
  static const Color redSoft = Color(0xFFFAE0DC);

  static const Color warning = Color(0xFFD08A2A);
  static const Color amber = warning;
  static const Color amberSoft = Color(0xFFFAE7C9);

  static const Color blue = Color(0xFF2E5DA8);
  static const Color blueSoft = Color(0xFFE0E8F4);

  // ───────── Mission palette (used by the right-rail spend list) ─────────
  /// Stable cycle so the same mission gets the same accent across renders.
  static const List<Color> missionPalette = <Color>[
    Color(0xFF6B8A3F), // olive
    Color(0xFFD08A2A), // amber
    Color(0xFFA85C2A), // terracotta
    Color(0xFF6A6E9F), // dusty indigo
    Color(0xFFB14D6E), // muted plum
    Color(0xFF3E8068), // teal
  ];

  // ───────── Category color delegation ─────────
  /// Expense categories share their color set across mobile + CMS so the
  /// charts and the table dots match. Delegates to the mobile palette to
  /// avoid keeping two maps in sync.
  static Color forCategory(String code) => mobile.AppColors.forCategory(code);
}
