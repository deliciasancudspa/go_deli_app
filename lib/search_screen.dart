import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _addrCtrl   = TextEditingController();
  final _couponCtrl = TextEditingController();
  String _pay = "cash";
  bool _loading = false;
  bool _couponApplied = false;
  double _discount = 0;
  final _sb = Supabase.instance.client;

  String _fmt(num p) => "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    if (code == "BIENVENIDO") {
      setState(() { _couponApplied = true; _discount = 0.10; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cupon aplicado: 10% de descuento"), backgroundColor: AppColors.success));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cupon invalido"), backgroundColor: AppColors.error));
    }
  }

  Future<void> _place() async {
    if (_addrCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingresa tu direccion")));
      return;
    }
    setState(() => _loading = true);
    try {
      final cart = context.read<CartProvider>();
      final user = _sb.auth.currentUser!;
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).single();
      final s = await _sb.from("stores").select("delivery_fee,fixed_fee,commission_pct").eq("id", cart.currentStoreId!).single();
      final fee     = (s["delivery_fee"] as num).toInt();
      final fix     = (s["fixed_fee"] as num).toInt();
      final pct     = (s["commission_pct"] as num).toDouble();
      final subtotal = cart.subtotal;
      final discountAmt = (_discount * subtotal).toInt();
      final finalSubtotal = subtotal - discountAmt;
      final platFee = (finalSubtotal * pct / 100).toInt();
      final total   = finalSubtotal + fee;
      final order = await _sb.from("orders").insert({
        "client_id": u["id"], "store_id": cart.currentStoreId,
        "subtotal": finalSubtotal, "delivery_fee": fee,
        "platform_fee": platFee, "fixed_fee": fix,
        "total": total, "delivery_address": _addrCtrl.text,
        "payment_method": _pay, "status": "pending",
        "coupon_code": _couponApplied ? _couponCtrl.text.trim().toUpperCase() : null,
        "discount": discountAmt,
      }).select().single();
      await _sb.from("order_items").insert(cart.items.map((i) => {
        "order_id": order["id"], "menu_item_id": i.id,
        "item_name": i.name, "item_price": i.price,
        "quantity": i.quantity, "subtotal": i.totalPrice,
      }).toList());
      cart.clearCart();
      if (mounted) context.go("/order-success");
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final discount = (_discount * cart.subtotal).toInt();
    final total = cart.subtotal - discount;
    final methods = [
      {"id": "cash", "label": "Efectivo", "icon": Icons.payments_outlined},
      {"id": "card", "label": "Tarjeta", "icon": Icons.credit_card},
      {"id": "transfer", "label": "Transferencia", "icon": Icons.account_balance_outlined},
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Confirmar pedido")),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _sectionTitle("Direccion de entrega"),
        TextFormField(
          controller: _addrCtrl,
          decoration: const InputDecoration(hintText: "Ej: Calle Principal 123", prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.primary)),
        ),
        const SizedBox(height: 20),
        _sectionTitle("Metodo de pago"),
        Row(children: methods.map((m) => Expanded(child: GestureDetector(
          onTap: () => setState(() => _pay = m["id"] as String),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _pay == m["id"] ? AppColors.primary.withOpacity(0.1) : AppColors.surface,
              border: Border.all(color: _pay == m["id"] ? AppColors.primary : AppColors.border, width: _pay == m["id"] ? 2 : 1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Icon(m["icon"] as IconData, color: _pay == m["id"] ? AppColors.primary : AppColors.textLight, size: 24),
              const SizedBox(height: 4),
              Text(m["label"] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _pay == m["id"] ? AppColors.primary : AppColors.textMedium)),
            ]),
          ),
        ))).toList()),
        const SizedBox(height: 20),
        _sectionTitle("Cupon de descuento"),
        Row(children: [
          Expanded(child: TextFormField(
            controller: _couponCtrl,
            enabled: !_couponApplied,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: "Ej: BIENVENIDO",
              prefixIcon: const Icon(Icons.local_offer_outlined, color: AppColors.primary),
              suffixIcon: _couponApplied ? const Icon(Icons.check_circle, color: AppColors.success) : null,
            ),
          )),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _couponApplied ? null : _applyCoupon,
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 52)),
            child: Text(_couponApplied ? "OK" : "Aplicar"),
          ),
        ]),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            _sectionTitle("Resumen del pedido"),
            ...cart.items.map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text("${i.quantity}x ${i.name}", style: const TextStyle(color: AppColors.textMedium, fontWeight: FontWeight.w600))),
                Text(_fmt(i.totalPrice), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            )),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Subtotal", style: TextStyle(color: AppColors.textLight)),
              Text(_fmt(cart.subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            if (discount > 0) ...[
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Descuento", style: TextStyle(color: AppColors.success)),
                Text("-${_fmt(discount)}", style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
              ]),
            ],
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Total", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              Text(_fmt(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.primary)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _loading ? null : _place,
          child: _loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text("Confirmar pedido · ${_fmt(total)}"),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMedium)),
  );
}
