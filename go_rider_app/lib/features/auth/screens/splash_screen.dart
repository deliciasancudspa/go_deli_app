import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/services/notification_service.dart";
import "../../../providers/rider_provider.dart";

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
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fade  = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _scale = Tween<double>(begin: 0.8, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    // Check session directly — RiderProvider may still be loading profile
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      context.go("/login");
      return;
    }

    // Session exists: poll until BOTH user and deliverer data are loaded (max 5s)
    final rider = context.read<RiderProvider>();
    for (int i = 0; i < 25; i++) {
      if (rider.profileLoaded) break;
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
    }
    if (!mounted) return;

    if (!rider.isLoggedIn) {
      context.go("/login");
    } else if (!rider.isApproved) {
      context.go("/pending");
    } else {
      context.go("/dashboard");
      // Si la app se abrió desde una notificación de pedido, abrir la oferta
      final pending = NotificationService.pendingRoute;
      if (pending != null) {
        NotificationService.pendingRoute = null;
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) context.push(pending);
        });
      }
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        // Detalles decorativos con los colores de la app sobre fondo blanco
        Positioned(top: -80, right: -80, child: Container(
          width: 300, height: 300,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFF6B35).withOpacity(0.08)),
        )),
        Positioned(bottom: -60, left: -60, child: Container(
          width: 240, height: 240,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7C3AED).withOpacity(0.08)),
        )),
        Positioned(top: 160, left: -40, child: Container(
          width: 140, height: 140,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7C3AED).withOpacity(0.05)),
        )),
        // Solo el logo
        Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Image.asset("assets/images/logo.png", width: 240, filterQuality: FilterQuality.high),
            ),
          ),
        ),
      ]),
    );
  }
}
