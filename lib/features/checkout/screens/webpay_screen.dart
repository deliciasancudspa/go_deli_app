import "dart:async";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

// Webpay se abre en Chrome Custom Tab para que:
// - el retorno a la app (godeli-webpay://done) funcione de forma confiable
// - la comunicación banco → Webpay no se rompa al volver de la app bancaria
// - Android 11+ y Chrome moderno ya propagan deep links a apps bancarias desde Custom Tabs
//
// externalApplication (Chrome completo) NO sirve: las apps bancarias no pueden
// devolver el control a la pestaña de Chrome que inició el flujo Webpay,
// rompiendo la comunicación banco → Webpay y dejando el pago en el aire.
//
// Detección de pago completado (3 mecanismos redundantes):
// 1. Supabase Realtime — webpay-return actualiza payment_status → WebSocket avisa al instante
// 2. Polling cada 3s — fallback si Realtime se desconecta o no llega el evento
// 3. didChangeAppLifecycleState + botón "Ya pagué" — verificaciones manuales

class WebpayScreen extends StatefulWidget {
  final String webpayUrl;
  final String webpayToken;
  final String orderId;
  final String? storeId;

  const WebpayScreen({
    super.key,
    required this.webpayUrl,
    required this.webpayToken,
    required this.orderId,
    this.storeId,
  });

  @override
  State<WebpayScreen> createState() => _WebpayScreenState();
}

class _WebpayScreenState extends State<WebpayScreen> with WidgetsBindingObserver {
  final _sb = Supabase.instance.client;
  bool _handled = false;
  bool _checking = false;
  bool _launched = false;
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;
  Timer? _pollTimer;

  // La URL base de Transbank no incluye el token; hay que pasarlo como
  // query param token_ws para que el formulario sepa qué transacción cargar.
  // (Es el mismo nombre de parámetro que Transbank usa para devolver el
  // resultado al return_url, pero en este contexto es entrada al formulario.)
  String get _payUrl {
    if (widget.webpayToken.isEmpty) return widget.webpayUrl;
    final sep = widget.webpayUrl.contains('?') ? '&' : '?';
    return '${widget.webpayUrl}$sep'
        'token_ws=${Uri.encodeQueryComponent(widget.webpayToken)}';
  }

  bool get _isKhipu => widget.webpayToken.isEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _saveState();
    _startRealtime();
    _startPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openBrowser());
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ─── Supabase Realtime ───────────────────────────────────────────
  // Escucha cambios en payment_status vía WebSocket. Cuando
  // webpay-return marca la orden como paid/failed, la app se entera
  // al instante sin depender del deep link godeli-webpay://done.
  void _startRealtime() {
    _realtimeSub = _sb
        .from("orders")
        .stream(primaryKey: ["id"])
        .eq("id", widget.orderId)
        .listen(_onRealtimeEvent, onError: (_) {});
  }

  void _onRealtimeEvent(List<Map<String, dynamic>> rows) {
    if (_handled || !mounted) return;
    for (final row in rows) {
      final status = row["payment_status"] as String? ?? "";
      if (status == "paid") {
        _handleResult("approved", widget.orderId);
        return;
      } else if (status == "failed") {
        _handleResult("rejected", widget.orderId);
        return;
      }
    }
  }

  // ─── Polling (fallback) ──────────────────────────────────────────
  // Cada 3s consulta la BD. Si Realtime funciona, este poll es inocuo
  // porque _handled evita doble navegación. Si Realtime falla, este
  // poll detecta el pago en máximo 3s después de que webpay-return
  // actualiza la orden.
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_handled && mounted && _launched) {
        _checkPaymentStatus();
      }
    });
  }

  Future<void> _openBrowser() async {
    if (_handled) return;
    setState(() => _launched = true);
    try {
      // Chrome Custom Tab (inAppBrowserView):
      // - La pestaña vive en el proceso de Chrome pero está vinculada a la app
      // - Cuando el usuario salta a MACH/BancoEstado/banco, la Custom Tab
      //   sobrevive en background y recibe el retorno
      // - Al finalizar, el redirect godeli-webpay://done abre la app directo
      // - Android 11+ soporta que Custom Tabs lancen apps externas (bancos)
      //
      // externalApplication NO se usa porque el banco no puede devolver el
      // control a la pestaña correcta de Chrome, rompiendo el flujo Webpay.
      await launchUrl(
        Uri.parse(_payUrl),
        mode: LaunchMode.inAppBrowserView,
      );
    } catch (e) {
      // Fallback: si Custom Tabs no está disponible, usar navegador externo
      try {
        await launchUrl(
          Uri.parse(_payUrl),
          mode: LaunchMode.externalApplication,
        );
      } catch (e2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("No se pudo abrir el navegador: $e2"),
            backgroundColor: AppColors.error,
          ));
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cuando el usuario vuelve de Chrome/MACH/banco, verificamos
    // inmediatamente (sin esperar el próximo tick del polling).
    if (state == AppLifecycleState.resumed && !_handled && _launched) {
      _checkPaymentStatus();
    }
  }

  Future<void> _checkPaymentStatus() async {
    if (_checking || _handled) return;
    setState(() => _checking = true);
    try {
      final data = await _sb
          .from("orders")
          .select("payment_status")
          .eq("id", widget.orderId)
          .maybeSingle();

      if (data == null) return;
      final payStatus = data["payment_status"] as String? ?? "pending";
      if (payStatus == "paid" && !_handled) {
        _handleResult("approved", widget.orderId);
      } else if (payStatus == "failed" && !_handled) {
        _handleResult("rejected", widget.orderId);
      }
    } catch (_) {
      // Silencioso: el siguiente poll lo reintentará
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _handleResult(String status, String orderId) {
    if (!mounted || _handled) return;
    _handled = true;
    _clearState();

    if (status == "approved") {
      if (widget.storeId != null) {
        context.read<CartProvider>().clearStoreCart(widget.storeId!);
      }
      context.go("/order-success/$orderId");
    } else if (status == "rejected") {
      // Pago rechazado — webpay-return ya marcó la orden como cancelled/failed.
      // Volver al checkout para que el usuario pueda crear un nuevo pedido.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("❌ Pago rechazado por el banco. Crea un nuevo pedido para intentarlo de nuevo."),
        backgroundColor: AppColors.error,
        duration: Duration(seconds: 6),
      ));
      Navigator.of(context).pop();
    } else {
      // cancelled — el pago no se completó (timeout, usuario canceló en Transbank)
      // La orden sigue en pending_payment, se puede reintentar desde el checkout.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Pago cancelado — puedes intentarlo de nuevo"),
        backgroundColor: AppColors.warning,
        duration: Duration(seconds: 4),
      ));
      Navigator.of(context).pop();
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("pending_webpay_order_id", widget.orderId);
    await prefs.setString("pending_webpay_token", widget.webpayToken);
    await prefs.setString("pending_webpay_url", widget.webpayUrl);
    if (widget.storeId != null) {
      await prefs.setString("pending_webpay_store_id", widget.storeId!);
    }
  }

  Future<void> _clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("pending_webpay_order_id");
    await prefs.remove("pending_webpay_token");
    await prefs.remove("pending_webpay_url");
    await prefs.remove("pending_webpay_store_id");
  }

  Widget _buildPulseDot() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.8),
        shape: BoxShape.circle,
      ),
    );
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("¿Cancelar pago?"),
        content: const Text("Si sales ahora el pago no se completará."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Seguir pagando"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // cerrar dialog
              _clearState();
              Navigator.of(context).pop(); // cerrar WebpayScreen
            },
            child: const Text("Salir", style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _isKhipu ? "Pago con Khipu" : "Pago con WebPay";
    final conectando = _isKhipu ? "Conectando con Khipu..." : "Conectando con WebPay...";

    return Scaffold(
      appBar: AppBar(
        title: Text(label),
        backgroundColor: Colors.transparent,
        flexibleSpace: const GradientFlexibleSpace(),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _confirmCancel,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_checking)
                const CircularProgressIndicator(color: AppColors.primary)
              else
                const Icon(Icons.open_in_browser, size: 64, color: AppColors.primary),
              const SizedBox(height: 24),
              Text(
                _checking ? "Verificando pago..." : conectando,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                "Completa el pago en el navegador.\nLa app detectará el pago automáticamente.",
                style: TextStyle(color: AppColors.textLight),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Indicador de monitoreo activo (Realtime + polling)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPulseDot(),
                  const SizedBox(width: 8),
                  const Text(
                    "Escuchando confirmación…",
                    style: TextStyle(fontSize: 12, color: AppColors.textLight),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (!_checking) ...[
                ElevatedButton.icon(
                  onPressed: _openBrowser,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text("Abrir navegador de pago"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _checkPaymentStatus,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Ya pagué — verificar"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
