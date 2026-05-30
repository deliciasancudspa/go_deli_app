import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";

class OrderSuccessScreen extends StatefulWidget {
  final String orderId;
  const OrderSuccessScreen({super.key, required this.orderId});
  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _order;
  late AnimationController _ctrl;
  late Animation<double> _scale;
  final _sb = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _scale = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _load();
  }

  Future<void> _load() async {
    final o = await _sb.from("orders").select("*, stores(name,emoji)").eq("id", widget.orderId).single();
    if (mounted) setState(() => _order = o);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código copiado"), backgroundColor: AppColors.success, duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final isPickup = _order?["order_type"] == "pickup";
    final pickupCode = _order?["pickup_code"] as String?;
    final deliveryCode = _order?["delivery_code"] as String?;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 32),

            // Animacion check
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.success], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.success.withOpacity(0.4), blurRadius: 30, spreadRadius: 5)],
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 64),
              ),
            ),
            const SizedBox(height: 24),

            const Text("¡Pedido confirmado!", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              isPickup ? "Dirígete a la tienda con tu código de retiro" : "Tu pedido está siendo preparado",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textLight, fontSize: 15),
            ),
            const SizedBox(height: 32),

            // Info tienda
            if (_order != null) Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Text(_order!["stores"]?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_order!["stores"]?["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(isPickup ? "Retiro en tienda" : "Delivery a domicilio", style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                ])),
                Text("\$${((_order!["total"] as num?)?.toStringAsFixed(0)) ?? "0"}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.primary)),
              ]),
            ),
            const SizedBox(height: 20),

            // Codigo de retiro en tienda
            if (isPickup && pickupCode != null) _codeCard(
              title: "Tu código de retiro",
              subtitle: "Muestra este código en la tienda para retirar tu pedido",
              code: pickupCode,
              color: AppColors.primary,
              icon: Icons.store_outlined,
            ),

            // Codigo de entrega delivery
            if (!isPickup && deliveryCode != null) _codeCard(
              title: "Código de entrega",
              subtitle: "Entrega este código al repartidor cuando recibas tu pedido",
              code: deliveryCode,
              color: AppColors.accent,
              icon: Icons.delivery_dining,
            ),

            const SizedBox(height: 24),

            // Botones
            ElevatedButton.icon(
              onPressed: () => context.go("/tracking/${widget.orderId}"),
              icon: const Icon(Icons.location_on_outlined),
              label: const Text("Seguir mi pedido"),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go("/"),
              icon: const Icon(Icons.home_outlined),
              label: const Text("Volver al inicio"),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  Widget _codeCard({required String title, required String subtitle, required String code, required Color color, required IconData icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
        ]),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: AppColors.textLight, fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => _copyCode(code),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(code, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: color, letterSpacing: 8)),
              const SizedBox(width: 12),
              Icon(Icons.copy, color: color, size: 20),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text("Toca para copiar", style: TextStyle(color: color.withOpacity(0.7), fontSize: 11)),
      ]),
    );
  }
}
