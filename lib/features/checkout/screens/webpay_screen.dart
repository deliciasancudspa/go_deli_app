import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
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

class _WebpayScreenState extends State<WebpayScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          // Interceptar el deep link que envía webpay-return tras confirmar el pago
          if (uri?.scheme == "godeli-webpay") {
            final status  = uri?.queryParameters["status"]   ?? "error";
            final orderId = uri?.queryParameters["order_id"] ?? widget.orderId;
            _handleResult(status, orderId);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(
        // WebPay requiere token en query param; Khipu ya incluye la URL completa
        Uri.parse(widget.webpayToken.isEmpty
            ? widget.webpayUrl
            : "${widget.webpayUrl}?token_ws=${widget.webpayToken}"),
      );
  }

  void _handleResult(String status, String orderId) {
    if (!mounted) return;
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
                    onPressed: () { Navigator.pop(context); context.pop(); },
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
              Text(widget.webpayToken.isEmpty ? "Conectando con Khipu..." : "Conectando con WebPay...", style: const TextStyle(color: AppColors.textLight)),
            ]),
          ),
      ]),
    );
  }
}
