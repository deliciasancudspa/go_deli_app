import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";
import "../../../providers/auth_provider.dart";
import "dart:math";

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _addressCtrl = TextEditingController();
  final _refCtrl     = TextEditingController();
  final _couponCtrl  = TextEditingController();
  String _deliveryType = "delivery";
  String _payMethod    = "cash";
  double _discount     = 0;
  String _couponCode   = "";
  String? _couponMsg;
  bool _couponValid    = false;
  bool _loading        = false;
  Map<String, dynamic>? _storeData;
  final _sb = Supabase.instance.client;

  @override
  void initState() { super.initState(); _loadStore(); }

  Future<void> _loadStore() async {
    final cart = context.read<CartProvider>();
    if (cart.currentStoreId == null) return;
    final store = await _sb.from("stores").select().eq("id", cart.currentStoreId!).single();
    if (mounted) setState(() => _storeData = store);
  }

  String _generateCode() {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    final r = Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _fmt(num p) => "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  bool get _allowPickup => _storeData?["allow_pickup"] == true;

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim().toUpperCase();
    if (code == "BIENVENIDO") {
      setState(() { _discount = 0.10; _couponCode = code; _couponValid = true; _couponMsg = "✅ 10% de descuento aplicado"; });
    } else {
      setState(() { _discount = 0; _couponCode = ""; _couponValid = false; _couponMsg = "❌ Cupón no válido"; });
    }
  }

  Future<void> _placeOrder() async {
    if (_deliveryType == "delivery" && _addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingresa tu dirección de entrega"), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _loading = true);
    try {
      final cart   = context.read<CartProvider>();
      final auth   = context.read<AuthProvider>();
      final subtotal   = cart.subtotal;
      final discAmt    = (subtotal * _discount).round();
      final finalSub   = subtotal - discAmt;
      final delivFee   = _deliveryType == "delivery" ? (_storeData?["delivery_fee"] ?? 1990) as num : 0;
      final platformFee = (finalSub * ((_storeData?["commission_pct"] ?? 7) as num) / 100).round();
      final fixedFee   = (_storeData?["fixed_fee"] ?? 3000) as num;
      final total      = finalSub + delivFee;
      final pickupCode = _generateCode();
      final delivCode  = _deliveryType == "delivery" ? _generateCode() : null;

      final u = await _sb.from("users").select("id").eq("auth_id", auth.user!.id).single();
      final order = await _sb.from("orders").insert({
        "client_id": u["id"],
        "store_id": cart.currentStoreId,
        "subtotal": finalSub,
        "delivery_fee": delivFee,
        "platform_fee": platformFee,
        "fixed_fee": fixedFee,
        "total": total,
        "delivery_address": _deliveryType == "delivery" ? _addressCtrl.text.trim() : null,
        "delivery_reference": _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        "payment_method": _payMethod,
        "order_type": _deliveryType,
        "status": "pending",
        "coupon_code": _couponCode.isEmpty ? null : _couponCode,
        "discount": discAmt,
        "pickup_code": pickupCode,
        "delivery_code": delivCode,
      }).select().single();

      await _sb.from("order_items").insert(cart.items.map((item) => {
        "order_id": order["id"],
        "menu_item_id": item.id,
        "item_name": item.name,
        "item_price": item.price,
        "quantity": item.quantity,
        "subtotal": item.price * item.quantity,
      }).toList());

      cart.clearCart();
      if (mounted) context.go("/order-success/${order["id"]}");
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final subtotal  = cart.subtotal;
    final discAmt   = (subtotal * _discount).round();
    final finalSub  = subtotal - discAmt;
    final delivFee  = _deliveryType == "delivery" ? (_storeData?["delivery_fee"] ?? 1990) as num : 0;
    final total     = finalSub + delivFee;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Confirmar pedido"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Tipo de entrega
        const Text("Tipo de entrega", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _typeBtn("delivery", "🛵 Delivery", "Entrega a domicilio")),
          const SizedBox(width: 12),
          if (_allowPickup) Expanded(child: _typeBtn("pickup", "🏪 Retiro", "Retira en tienda")),
        ]),
        const SizedBox(height: 20),

        // Direccion (solo delivery)
        if (_deliveryType == "delivery") ...[
          const Text("Dirección de entrega", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressCtrl,
            decoration: const InputDecoration(hintText: "Ej: Calle Principal 123, Ancud", prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.primary)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _refCtrl,
            decoration: const InputDecoration(hintText: "Referencia (opcional)", prefixIcon: Icon(Icons.info_outline, color: AppColors.primary)),
          ),
          const SizedBox(height: 20),
        ],

        // Metodo de pago
        const Text("Método de pago", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (_deliveryType == "pickup")
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withOpacity(0.3))),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text("El retiro en tienda requiere pago con tarjeta o transferencia", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13))),
            ]),
          )
        else
          _payMethodCard("cash", "💵", "Efectivo", "Paga al recibir"),
        const SizedBox(height: 8),
        _payMethodCard("card", "💳", "Tarjeta", "Débito o crédito"),
        const SizedBox(height: 8),
        _payMethodCard("transfer", "📱", "Transferencia", "Pago digital"),
        const SizedBox(height: 20),

        // Cupon
        const Text("Cupón de descuento", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(
            controller: _couponCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: "Ej: BIENVENIDO", prefixIcon: Icon(Icons.local_offer_outlined, color: AppColors.primary)),
          )),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _applyCoupon,
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 52)),
            child: const Text("Aplicar"),
          ),
        ]),
        if (_couponMsg != null) ...[
          const SizedBox(height: 8),
          Text(_couponMsg!, style: TextStyle(color: _couponValid ? AppColors.success : AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 20),

        // Resumen
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            ...cart.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text("${item.quantity}x ${item.name}", style: const TextStyle(fontSize: 13))),
                Text(_fmt(item.price * item.quantity), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            )),
            const Divider(),
            _summaryRow("Subtotal", _fmt(subtotal)),
            if (discAmt > 0) _summaryRow("Descuento", "-${_fmt(discAmt)}", color: AppColors.success),
            if (_deliveryType == "delivery") _summaryRow("Envío", _fmt(delivFee)),
            const Divider(thickness: 2),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Total", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              Text(_fmt(total), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.primary)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: _loading ? null : _placeOrder,
          child: _loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text("Confirmar pedido · ${_fmt(total)}"),
        ),
        const SizedBox(height: 32),
      ])),
    );
  }

  Widget _typeBtn(String type, String label, String sub) {
    final selected = _deliveryType == type;
    return GestureDetector(
      onTap: () => setState(() {
        _deliveryType = type;
        if (type == "pickup") _payMethod = "card";
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Column(children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: selected ? AppColors.primary : AppColors.textDark)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
        ]),
      ),
    );
  }

  Widget _payMethodCard(String method, String emoji, String label, String sub) {
    final selected = _payMethod == method;
    final disabled = _deliveryType == "pickup" && method == "cash";
    return GestureDetector(
      onTap: disabled ? null : () => setState(() => _payMethod = method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: disabled ? AppColors.background : selected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected && !disabled ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: disabled ? AppColors.textLight : AppColors.textDark)),
            Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
          ]),
          const Spacer(),
          if (selected && !disabled) const Icon(Icons.check_circle, color: AppColors.primary),
        ]),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textMedium)),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color ?? AppColors.textDark)),
    ]),
  );
}
