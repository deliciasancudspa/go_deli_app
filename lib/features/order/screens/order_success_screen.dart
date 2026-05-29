import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "../../../core/theme/app_theme.dart";

class OrderSuccessScreen extends StatefulWidget {
  const OrderSuccessScreen({super.key});
  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scale = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: 130, height: 130,
              decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.success.withOpacity(0.4), blurRadius: 30, spreadRadius: 5)]),
              child: const Icon(Icons.check, color: Colors.white, size: 64),
            ),
          ),
          const SizedBox(height: 32),
          const Text("Pedido confirmado!", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Text("Tu pedido esta siendo preparado. Te notificaremos cuando este en camino.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15, height: 1.5)),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _infoItem("⏱️", "20-35 min", "Tiempo estimado"),
              Container(width: 1, height: 40, color: Colors.white24),
              _infoItem("📍", "En camino", "Estado"),
            ]),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go("/orders"),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(double.infinity, 52)),
            child: const Text("Ver mis pedidos"),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go("/home"),
            child: const Text("Volver al inicio", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
          ),
        ]),
      ))),
    );
  }

  Widget _infoItem(String emoji, String value, String label) => Column(children: [
    Text(emoji, style: const TextStyle(fontSize: 24)),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
  ]);
}
