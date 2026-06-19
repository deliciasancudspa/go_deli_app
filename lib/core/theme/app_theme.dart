import "package:flutter/material.dart";

class AppColors {
  // ── Paleta nueva ──────────────────────────────────────────────────────────
  static const Color primary    = Color(0xFF9E00FF);   // morado principal
  static const Color secondary  = Color(0xFF7B00CC);   // morado oscuro
  static const Color accent     = Color(0xFFFF6B00);   // naranja principal
  static const Color success    = Color(0xFF22C55E);
  static const Color error      = Color(0xFFEF4444);
  static const Color warning    = Color(0xFFF59E0B);
  static const Color info       = Color(0xFF3B82F6);
  static const Color background = Color(0xFFF8F4FF);   // fondo claro con tinte morado
  static const Color surface    = Color(0xFFFFFFFF);
  static const Color textDark   = Color(0xFF1A1A2E);
  static const Color textMedium = Color(0xFF374151);
  static const Color textLight  = Color(0xFF9CA3AF);
  static const Color border     = Color(0xFFE5E0F0);   // borde con tinte morado

  // Home screen palette
  static const Color homeDark       = Color(0xFF1A0033);   // fondo oscuro
  static const Color homeOrange     = Color(0xFFFF6B00);   // naranja
  static const Color homePurple     = Color(0xFF9E00FF);   // morado
  static const Color homeBackground = Color(0xFFF8F4FF);   // fondo claro
  static const Color homeCardBorder = Color(0x229E00FF);

  // ── Gradientes ────────────────────────────────────────────────────────────
  static const LinearGradient mainGradient = LinearGradient(
    colors: [Color(0xFF9E00FF), Color(0xFFFF6B00)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF7B00CC), Color(0xFFFF4500)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

// ── WaveClipper ───────────────────────────────────────────────────────────────
class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 35);
    path.quadraticBezierTo(size.width * 0.25, size.height + 10, size.width * 0.5, size.height - 20);
    path.quadraticBezierTo(size.width * 0.75, size.height - 50, size.width, size.height - 25);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }
  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

// ── Widget helper para AppBar con gradiente plano ─────────────────────────────
class GradientFlexibleSpace extends StatelessWidget {
  const GradientFlexibleSpace({super.key});
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(gradient: AppColors.mainGradient),
  );
}

class AppTheme {
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    fontFamily: "Nunito",
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, fontFamily: "Nunito"),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFamily: "Nunito"),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        side: const BorderSide(color: AppColors.accent, width: 2),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFamily: "Nunito"),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textLight),
      prefixIconColor: AppColors.accent,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Color(0xFF888888),
      type: BottomNavigationBarType.fixed,
      elevation: 12,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textDark),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark),
      bodyLarge: TextStyle(color: AppColors.textMedium),
      bodyMedium: TextStyle(color: AppColors.textMedium),
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: const Color(0xFF121212),
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: Color(0xFF1E1E1E),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1E1E1E),
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Colors.grey,
    ),
    cardTheme: CardThemeData(color: const Color(0xFF1E1E1E), elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
      bodyLarge: TextStyle(color: Color(0xFFB0B0B0)),
      bodyMedium: TextStyle(color: Color(0xFF909090)),
    ),
  );
}
