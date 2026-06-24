import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "package:webview_flutter/webview_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

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
  late final WebViewController _controller;
  final _sb = Supabase.instance.client;
  bool _loading = true;
  bool _handled = false; // evitar doble manejo del resultado

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _saveState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) {
          setState(() => _loading = false);
          // Redirigir window.open() al mismo frame para evitar que
          // la autenticación 3DS del banco abra el navegador del sistema
          _controller.runJavaScript(
            "window.open=function(u,n,f){if(u)window.location.href=u;return window;};",
          );
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.navigate;

          // Deep link de retorno desde webpay-return
          if (uri.scheme == "godeli-webpay") {
            final status  = uri.queryParameters["status"]   ?? "error";
            final orderId = uri.queryParameters["order_id"] ?? widget.orderId;
            _handleResult(status, orderId);
            return NavigationDecision.prevent;
          }

          // App nativa del banco (billetera, etc.) — abrir externamente
          if (uri.scheme != "http" && uri.scheme != "https") {
            _launchExternal(uri);
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(
        Uri.parse(widget.webpayToken.isEmpty
            ? widget.webpayUrl
            : "${widget.webpayUrl}?token_ws=${widget.webpayToken}"),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Abrir app externa (banco/billetera) con verificación previa
  Future<void> _launchExternal(Uri uri) async {
    try {
      final ok = await canLaunchUrl(uri);
      if (ok) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No se encontró la app del banco en este dispositivo"),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No se pudo abrir la app del banco"),
        ));
      }
    }
  }

  // Guardar estado pendiente en SharedPreferences
  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("pending_webpay_order_id", widget.orderId);
    await prefs.setString("pending_webpay_token", widget.webpayToken);
    await prefs.setString("pending_webpay_url", widget.webpayUrl);
  }

  // Limpiar estado pendiente
  Future<void> _clearState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("pending_webpay_order_id");
    await prefs.remove("pending_webpay_token");
    await prefs.remove("pending_webpay_url");
  }

  // Cuando la app vuelve al frente, verificar si el pago ya se procesó
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_handled) {
      _checkPaymentStatus();
    }
  }

  Future<void> _checkPaymentStatus() async {
    try {
      final data = await _sb
          .from("orders")
          .select("payment_status, status")
          .eq("id", widget.orderId)
          .single();

      final payStatus = data["payment_status"] as String? ?? "pending";
      if (payStatus == "paid" && !_handled) {
        _handleResult("approved", widget.orderId);
      } else if (payStatus == "failed" && !_handled) {
        _handleResult("rejected", widget.orderId);
      }
      // Si sigue "pending", el usuario aún no pagó — dejar el WebView activo
    } catch (_) {}
  }

  void _handleResult(String status, String orderId) {
    if (!mounted || _handled) return;
    _handled = true;
    _clearState();

    if (status == "approved") {
      context.read<CartProvider>().clearCart();
      context.go("/order-success/$orderId");
    } else {
      final msg = status == "cancelled"
          ? "Pago cancelado"
          : "Pago rechazado — intenta con otro método";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: status == "cancelled" ? AppColors.warning : AppColors.error,
      ));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.webpayToken.isEmpty ? "Pago con Khipu" : "Pago con WebPay"),
        backgroundColor: Colors.transparent,
        flexibleSpace: const GradientFlexibleSpace(),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("¿Cancelar pago?"),
                content: const Text("Si sales ahora el pago no se completará."),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Seguir pagando")),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _clearState();
                      context.pop();
                    },
                    child: const Text("Salir", style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: Stack(children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                widget.webpayToken.isEmpty ? "Conectando con Khipu..." : "Conectando con WebPay...",
                style: const TextStyle(color: AppColors.textLight),
              ),
            ]),
          ),
      ]),
    );
  }
}
