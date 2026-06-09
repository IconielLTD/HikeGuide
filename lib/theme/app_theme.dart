import 'package:flutter/material.dart';

/// Olive military dark palette — the single source of truth for colours.
/// Values come straight from the design brief; do not hardcode hex elsewhere.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF1A1F14);
  static const Color surface = Color(0xFF252B1C);
  static const Color primaryText = Color(0xFFE8E0C8);
  static const Color secondaryText = Color(0xFF9A9980);
  static const Color accent = Color(0xFFC8962A); // amber: buttons, active, routes
  static const Color fire = Color(0xFFB84A2A); // warning / fire

  // Access overlays are drawn at 40% opacity on the map.
  static const Color openAccess = Color(0xFF4A6B3A); // CRoW Open Access
  static const Color forestryEngland = Color(0xFF2E5C4A); // Forestry England
}

/// Text styles for guide content. The brief asks for a serif/slab-serif face for
/// guide prose (calm, "learn it properly" feel) and a clean sans for UI chrome.
/// 'serif' resolves to the platform serif on Android — no bundled font needed yet.
class AppText {
  AppText._();

  static const String serif = 'serif';

  /// One guide step per screen — large, generous line height.
  static const TextStyle guideStep = TextStyle(
    fontFamily: serif,
    fontSize: 20,
    height: 1.55,
    color: AppColors.primaryText,
  );

  static const TextStyle guideBody = TextStyle(
    fontFamily: serif,
    fontSize: 18,
    height: 1.6,
    color: AppColors.primaryText,
  );
}

ThemeData buildHikeGuideTheme() {
  final ThemeData base = ThemeData.dark(useMaterial3: true);

  final ColorScheme scheme = const ColorScheme.dark().copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.background,
    secondary: AppColors.accent,
    onSecondary: AppColors.background,
    surface: AppColors.surface,
    onSurface: AppColors.primaryText,
    error: AppColors.fire,
    onError: AppColors.primaryText,
  );

  final TextTheme text = base.textTheme
      .apply(bodyColor: AppColors.primaryText, displayColor: AppColors.primaryText)
      .copyWith(
        // Min 18sp body text per the brief.
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.5),
        bodyMedium: base.textTheme.bodyMedium
            ?.copyWith(fontSize: 16, height: 1.45, color: AppColors.secondaryText),
        titleLarge: base.textTheme.titleLarge
            ?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 18),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    cardColor: AppColors.surface,
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.primaryText,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.primaryText,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.accent,
      unselectedItemColor: AppColors.secondaryText,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 12),
      showUnselectedLabels: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.background,
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    dividerColor: AppColors.secondaryText.withValues(alpha: 0.2),
    iconTheme: const IconThemeData(color: AppColors.primaryText),
  );
}
