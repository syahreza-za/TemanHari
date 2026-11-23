import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tema Cozy Material 3 dengan palet hangat (Terracotta, Sand, Sage, Warm Night)
/// agar aplikasi terasa akrab dan menenangkan, bukan seperti aplikasi kantor yang kaku.
class AppTheme {
  // Palet Warna Hangat (Light)
  static const Color warmTerracotta = Color(0xFFD96B43);
  static const Color warmCreamBg = Color(0xFFFDF8F3);
  static const Color warmSurfaceCard = Color(0xFFFFFFFF);
  static const Color warmSurfaceSoft = Color(0xFFF5ECE3);
  static const Color warmTextPrimary = Color(0xFF2B211B);
  static const Color warmTextSecondary = Color(0xFF6F5D53);

  // Palet Warna Malam Hangat (Dark)
  static const Color darkWarmBg = Color(0xFF181412);
  static const Color darkWarmSurface = Color(0xFF231D1A);
  static const Color darkWarmSurfaceSoft = Color(0xFF2F2723);
  static const Color darkTerracotta = Color(0xFFF08C67);

  // Warna Badge Sumber Kalender & Tugas
  static const Color outlookBlue = Color(0xFF2B7CD3);
  static const Color googleGreen = Color(0xFF2E8B57);
  static const Color taskAmber = Color(0xFFD9822B);
  static const Color conflictCoral = Color(0xFFD64545);

  static ThemeData lightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: warmTerracotta,
      brightness: Brightness.light,
      primary: warmTerracotta,
      surface: warmCreamBg,
      surfaceContainerLowest: warmSurfaceCard,
      surfaceContainerLow: warmSurfaceSoft,
      onSurface: warmTextPrimary,
      onSurfaceVariant: warmTextSecondary,
    );

    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: warmCreamBg,
      textTheme: baseTextTheme.apply(
        bodyColor: warmTextPrimary,
        displayColor: warmTextPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: warmCreamBg,
        foregroundColor: warmTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: warmTextPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: warmSurfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: warmTextPrimary.withValues(alpha: 0.06)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: warmSurfaceCard,
        indicatorColor: warmTerracotta.withValues(alpha: 0.16),
        elevation: 2,
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return baseTextTheme.labelMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? warmTerracotta : warmTextSecondary,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: warmSurfaceSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }

  static ThemeData darkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: darkTerracotta,
      brightness: Brightness.dark,
      primary: darkTerracotta,
      surface: darkWarmBg,
      surfaceContainerLowest: darkWarmSurface,
      surfaceContainerLow: darkWarmSurfaceSoft,
    );

    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData.dark().textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkWarmBg,
      textTheme: baseTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: darkWarmBg,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkWarmSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkWarmSurface,
        indicatorColor: darkTerracotta.withValues(alpha: 0.22),
        elevation: 2,
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return baseTextTheme.labelMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? darkTerracotta : Colors.white70,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkWarmSurfaceSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }
}
