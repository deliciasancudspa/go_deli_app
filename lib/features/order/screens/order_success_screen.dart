import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "../../../core/theme/app_theme.dart";
class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key});
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.primary, body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 120, height: 120, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Center(child: Icon(Icons.check, size: 64, color: AppColors.primary))),
    const SizedBox(height: 32),
    const Text("Pedido confirmado!", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
    const SizedBox(height: 12),
    Text("Tu pedido esta siendo preparado", style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 16)),
    const SizedBox(height: 40),
    ElevatedButton(onPressed: () => context.go("/home"), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary), child: const Text("Volver al inicio")),
    const SizedBox(height: 12),
    TextButton(onPressed: () => context.push("/orders"), child: const Text("Ver mis pedidos", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
  ]))))); 
}