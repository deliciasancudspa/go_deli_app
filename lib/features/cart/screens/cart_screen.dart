import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});
  String _fmt(int p) => "\$${p.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
  @override Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Tu carrito"), actions: [if (!cart.isEmpty) TextButton(onPressed: cart.clearCart, child: const Text("Vaciar", style: TextStyle(color: AppColors.error)))]),
      body: cart.isEmpty
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Carrito vacio", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textLight))]))
        : Column(children: [
            Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: cart.items.length, itemBuilder: (ctx, i) {
              final item = cart.items[i];
              return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: Row(children: [
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)), Text(_fmt(item.totalPrice), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700))])),
                Row(children: [
                  GestureDetector(onTap: () => cart.removeItem(item.id), child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle), child: const Icon(Icons.remove, color: Colors.white, size: 16))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text("${item.quantity}", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  GestureDetector(onTap: () => cart.addItem(item), child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 16))),
                ]),
              ]));
            })),
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.surface, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4))]), child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Subtotal", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)), Text(_fmt(cart.subtotal), style: const TextStyle(fontWeight: FontWeight.w700))]),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => context.push("/checkout"), child: Text("Ir a pagar - ${_fmt(cart.subtotal)}")),
            ])),
          ]),
    );
  }
}
