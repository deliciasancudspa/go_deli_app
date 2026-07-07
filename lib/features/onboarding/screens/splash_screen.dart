import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../providers/auth_provider.dart";
import "../../../providers/cart_provider.dart";

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

    // Si el usuario viene de un enlace de recuperacion de contrasena,
    // redirigir a la pantalla de nueva contrasena
    try {
      final auth = context.read<AuthProvider>();
      if (auth.needsPasswordReset) {
        context.go("/reset-password");
        return;
      }
    } catch (_) {}

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      context.go("/onboarding");
      return;
    }
    final prefs = await SharedPreferences.getInstance();

    // Si hay un pago Webpay pendiente, verificar que la orden siga viva
    // antes de redirigir. Si la orden ya fue pagada, cancelada o no existe,
    // limpiamos SharedPreferences y seguimos al home normalmente.
    final pendingOrderId = prefs.getString("pending_webpay_order_id");
    if (pendingOrderId != null && pendingOrderId.isNotEmpty) {
      if (!mounted) return;

      // Verificar estado real de la orden en BD
      String? payStatus;
      try {
        final data = await Supabase.instance.client
            .from("orders")
            .select("payment_status")
            .eq("id", pendingOrderId)
            .maybeSingle();
        payStatus = data?["payment_status"] as String?;
      } catch (_) {
        // Si no podemos consultar, asumir que la orden ya no es válida
      }

      if (payStatus == "paid") {
        // El pago se completó mientras la app estaba fuera → ir a éxito
        await _clearPendingWebpayPrefs(prefs);
        if (!mounted) return;
        context.go("/order-success/$pendingOrderId");
        return;
      } else if (payStatus == "pending") {
        // Orden sigue pendiente → restaurar el storeId para que el redirect
        // de /checkout no caiga en /cart, y mostrar el diálogo de continuar.
        final savedStoreId = prefs.getString("pending_webpay_store_id");
        if (!mounted) return;
        if (savedStoreId != null && savedStoreId.isNotEmpty) {
          try {
            context.read<CartProvider>().activeStoreId = savedStoreId;
          } catch (_) {}
        }
        if (!mounted) return;
        context.go("/checkout");
        return;
      } else {
        // payStatus es null (orden no existe), "failed", u otro →
        // la orden ya no es relevante, limpiar y seguir al home
        await _clearPendingWebpayPrefs(prefs);
      }
    }

    // Si hay un pago de Mercado Pago pendiente, verificar que la orden siga viva
    final pendingMpOrderId = prefs.getString("pending_mp_order_id");
    if (pendingMpOrderId != null && pendingMpOrderId.isNotEmpty) {
      if (!mounted) return;

      String? payStatus;
      try {
        final data = await Supabase.instance.client
            .from("orders")
            .select("payment_status")
            .eq("id", pendingMpOrderId)
            .maybeSingle();
        payStatus = data?["payment_status"] as String?;
      } catch (_) {}

      if (payStatus == "paid") {
        await _clearPendingMercadoPagoPrefs(prefs);
        if (!mounted) return;
        context.go("/order-success/$pendingMpOrderId");
        return;
      } else if (payStatus == "pending") {
        final savedStoreId = prefs.getString("pending_mp_store_id");
        if (!mounted) return;
        if (savedStoreId != null && savedStoreId.isNotEmpty) {
          try {
            context.read<CartProvider>().activeStoreId = savedStoreId;
          } catch (_) {}
        }
        if (!mounted) return;
        context.go("/checkout");
        return;
      } else {
        await _clearPendingMercadoPagoPrefs(prefs);
      }
    }

    if (!mounted) return;
    final locationConfigured = prefs.getBool("location_configured") ?? false;
    if (!mounted) return;
    context.go(locationConfigured ? "/home" : "/location");
  }

  Future<void> _clearPendingWebpayPrefs(SharedPreferences prefs) async {
    await prefs.remove("pending_webpay_order_id");
    await prefs.remove("pending_webpay_token");
    await prefs.remove("pending_webpay_url");
    await prefs.remove("pending_webpay_store_id");
  }

  Future<void> _clearPendingMercadoPagoPrefs(SharedPreferences prefs) async {
    await prefs.remove("pending_mp_order_id");
    await prefs.remove("pending_mp_init_point");
    await prefs.remove("pending_mp_store_id");
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
