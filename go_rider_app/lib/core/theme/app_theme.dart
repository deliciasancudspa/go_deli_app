import "package:flutter/material.dart";

class AppColors {
  static const Color primary    = Color(0xFF1A1A2E);
  static const Color accent     = Color(0xFFFF6B35);
  static const Color success    = Color(0xFF22C55E);
  static const Color error      = Color(0xFFEF4444);
  static const Color warning    = Color(0xFFF59E0B);
  static const Color info       = Color(0xFF3B82F6);
  static const Color background = Color(0xFFF0F2F5);
  static const Color surface    = Color(0xFFFFFFFF);
  static const Color textDark   = Color(0xFF1A1A2E);
  static const Color textMedium = Color(0xFF374151);
  static const Color textLight  = Color(0xFF9CA3AF);
  static const Color border     = Color(0xFFE5E7EB);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    fontFamily: "Nunito",
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, primary: AppColors.primary, secondary: AppColors.accent, surface: AppColors.surface, error: AppColors.error),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0, centerTitle: true, titleTextStyle: TextStyle(fontFamily: "Nunito", fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontFamily: "Nunito", fontSize: 16, fontWeight: FontWeight.w800))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: AppColors.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), hintStyle: const TextStyle(color: AppColors.textLight)),
    cardTheme: CardThemeData(color: AppColors.surface, elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: AppColors.surface, selectedItemColor: AppColors.accent, unselectedItemColor: AppColors.textLight, type: BottomNavigationBarType.fixed, elevation: 8),
  );
}
