import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override State<CheckoutScreen> createState() => _CheckoutScreenState();
}
class _CheckoutScreenState extends State<CheckoutScreen> {
  final _addrCtrl = TextEditingController();
  String _pay = "cash";
  bool _loading = false;
  final _sb = Supabase.instance.client;
  String _fmt(int p) => "\$${p.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
  Future<void> _place() async {
    if (_addrCtrl.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingresa tu direccion"))); return; }
    setState(() => _loading = true);
    try {
      final cart = context.read<CartProvider>(); final user = _sb.auth.currentUser!;
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).single();
      final s = await _sb.from("stores").select("delivery_fee,fixed_fee,commission_pct").eq("id", cart.currentStoreId!).single();
      final fee = (s["delivery_fee"] as num).toInt(); final fix = (s["fixed_fee"] as num).toInt();
      final pct = (s["commission_pct"] as num).toDouble();
      final platFee = (cart.subtotal * pct / 100).toInt(); final total = cart.subtotal + fee;
      final order = await _sb.from("orders").insert({"client_id": u["id"], "store_id": cart.currentStoreId, "subtotal": cart.subtotal, "delivery_fee": fee, "platform_fee": platFee, "fixed_fee": fix, "total": total, "delivery_address": _addrCtrl.text, "payment_method": _pay, "status": "pending"}).select().single();
      await _sb.from("order_items").insert(cart.items.map((i) => {"order_id": order["id"], "menu_item_id": i.id, "item_name": i.name, "item_price": i.price, "quantity": i.quantity, "subtotal": i.totalPrice}).toList());
      cart.clearCart(); if (mounted) context.go("/order-success");
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
    finally { setState(() => _loading = false); }
  }
  @override Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final methods = [{"id": "cash", "label": "Efectivo"}, {"id": "card", "label": "Tarjeta"}, {"id": "transfer", "label": "Transferencia"}];
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: const Text("Confirmar pedido")),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text("Direccion de entrega", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 12),
        TextFormField(controller: _addrCtrl, decoration: const InputDecoration(hintText: "Ej: Calle Principal 123", prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.primary))),
        const SizedBox(height: 24), const Text("Metodo de pago", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 12),
        Row(children: methods.map((m) => Expanded(child: GestureDetector(onTap: () => setState(() => _pay = m["id"]!), child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _pay == m["id"] ? AppColors.primary.withOpacity(0.1) : AppColors.surface, border: Border.all(color: _pay == m["id"] ? AppColors.primary : AppColors.border, width: _pay == m["id"] ? 2 : 1), borderRadius: BorderRadius.circular(14)), child: Center(child: Text(m["label"]!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _pay == m["id"] ? AppColors.primary : AppColors.textMedium))))))).toList()),
        const SizedBox(height: 24),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: Column(children: [
          const Text("Resumen", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 12),
          ...cart.items.map((i) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("${i.quantity}x ${i.name}", style: const TextStyle(color: AppColors.textMedium, fontWeight: FontWeight.w600)), Text(_fmt(i.totalPrice))]))),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Total", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text(_fmt(cart.subtotal), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.primary))]),
        ])),
      ]),
      bottomNavigationBar: Padding(padding: const EdgeInsets.all(16), child: ElevatedButton(onPressed: _loading ? null : _place, child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text("Confirmar pedido - ${_fmt(cart.subtotal)}"))),
    );
  }
}
