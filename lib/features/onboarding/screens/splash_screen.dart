import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _fade  = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.easeIn)));
    _scale = Tween<double>(begin: 0.75, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      context.go("/onboarding");
      return;
    }
    final prefs             = await SharedPreferences.getInstance();
    final locationConfigured = prefs.getBool("location_configured") ?? false;
    if (!mounted) return;
    context.go(locationConfigured ? "/home" : "/location");
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        // Detalles decorativos con los colores de la nueva paleta
        Positioned(top: -80, right: -80, child: Container(
          width: 320, height: 320,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF6B00).withOpacity(0.12),
          ),
        )),
        Positioned(bottom: -60, left: -60, child: Container(
          width: 260, height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF9E00FF).withOpacity(0.15),
          ),
        )),
        Positioned(top: 180, left: -40, child: Container(
          width: 160, height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF6B00).withOpacity(0.08),
          ),
        )),
        Positioned(bottom: 140, right: -30, child: Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF9E00FF).withOpacity(0.10),
          ),
        )),

        // Solo el logo, nada debajo
        Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Image.asset(
                "assets/images/logo.png",
                width: 220,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
