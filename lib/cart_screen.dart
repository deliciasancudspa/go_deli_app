import "package:flutter/material.dart";

class AppColors {
  static const Color primary    = Color(0xFFFF6B35);
  static const Color secondary  = Color(0xFF1A1A2E);
  static const Color accent     = Color(0xFFFFB800);
  static const Color success    = Color(0xFF22C55E);
  static const Color error      = Color(0xFFEF4444);
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface    = Color(0xFFFFFFFF);
  static const Color textDark   = Color(0xFF1A1A2E);
  static const Color textMedium = Color(0xFF374151);
  static const Color textLight  = Color(0xFF9CA3AF);
  static const Color border     = Color(0xFFE5E7EB);
  static const Color darkBg     = Color(0xFF0F1923);
  static const Color darkSurface= Color(0xFF1A2636);
  static const Color info       = Color(0xFF3B82F6);
}

class AppTheme {
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    fontFamily: "Nunito",
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textDark,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontFamily: "Nunito", fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: "Nunito", fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textLight),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    fontFamily: "Nunito",
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.darkSurface,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.darkBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontFamily: "Nunito", fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: "Nunito", fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
