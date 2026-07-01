import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

// Webpay se abre en navegador externo (Chrome) para que:
// - la autenticación 3DS del banco funcione nativamente
// - las apps de billetera/banca reciban notificaciones push
// - los deep links entre banco y app bancaria funcionen sin restricciones
// Chrome Custom Tab NO sirve para esto: no propaga deep links a apps bancarias.
//
// Cuando el pago termina, webpay-return redirige a godeli-webpay://done
// → Chrome se cierra → app vuelve al frente → didChangeAppLifecycleState
// → _checkPaymentStatus consulta la DB y navega al resultado.

class WebpayScreen extends StatefulWidget {
  final String webpayUrl;
  final String webpayToken;
  final String orderId;

  const WebpayScreen({
    super.key,
    required this.webpayUrl,
    required this.webpayToken,
    required this.orderId,
  });

  @override
  State<WebpayScreen> createState() => _WebpayScreenState();
}

class _WebpayScreenState extends State<WebpayScreen> with WidgetsBindingObserver {
  final _sb = Supabase.instance.client;
  bool _handled = false;
  bool _checking = false;
  // Indica si Chrome Custom Tab fue abierto al menos una vez
  bool _launched = false;

  // Transbank Webpay Plus acepta token_ws como query param GET.
  // Data: URI con formulario POST no funciona en Android: ni Chrome Custom Tab
  // ni externalApplication soportan el esquema data: — tira ACTIVITY_NOT_FOUND.
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
    // Abrir Chrome Custom Tab en el próximo frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _openBrowser());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openBrowser() async {
    if (_handled) return;
    setState(() => _launched = true);
    try {
      // Chrome Custom Tab no propaga deep links a apps bancarias (3DS, wallets).
      // externalApplication abre Chrome completo, que sí soporta la redirección
      // nativa al banco para autenticación y notificaciones push de la app bancaria.
      await launchUrl(
        Uri.parse(_payUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("No se pudo abrir el navegador: $e"),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
          .single();

      final payStatus = data["payment_status"] as String? ?? "pending";
      if (payStatus == "paid" && !_handled) {
        _handleResult("approved", widget.orderId);
      } else if (payStatus == "failed" && !_handled) {
        _handleResult("rejected", widget.orderId);
      }
      // Si sigue "pending": el usuario cerró el tab sin pagar, dejamos la pantalla activa
    } catch (_) {
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _handleResult(String status, String orderId) {
    if (!mounted || _handled) return;
    _handled = true;
    _clearState();

    if (status == "approved") {
      context.read<CartProvider>().clearCart();
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
  }

  Future<void> _clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("pending_webpay_order_id");
    await prefs.remove("pending_webpay_token");
    await prefs.remove("pending_webpay_url");
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
                "Completa el pago en el navegador y vuelve aquí cuando termines.",
                style: TextStyle(color: AppColors.textLight),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
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
