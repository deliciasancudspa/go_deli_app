import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});
  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  final _sb = Supabase.instance.client;

  final _labels = {
    "pending": "Pendiente", "accepted": "Aceptado", "preparing": "Preparando",
    "ready": "Listo", "assigned": "Asignado", "picked_up": "Recogido",
    "on_the_way": "En camino", "delivered": "Entregado", "cancelled": "Cancelado",
  };
  final _colors = {
    "pending": AppColors.accent, "accepted": Colors.blue,
    "preparing": Colors.orange, "ready": AppColors.success,
    "on_the_way": Colors.orange, "delivered": AppColors.success,
    "cancelled": AppColors.error,
  };

  String _fmt(dynamic p) => "\$${(p as num).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final user = _sb.auth.currentUser;
      if (user == null) { setState(() => _loading = false); return; }
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).maybeSingle();
      if (u == null) { setState(() => _loading = false); return; }
      final o = await _sb.from("orders").select("*, stores(name,emoji), order_items(item_name,quantity,item_price,subtotal)").eq("client_id", u["id"]).order("created_at", ascending: false);
      if (mounted) setState(() { _orders = List<Map<String, dynamic>>.from(o); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Mis pedidos")),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _orders.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.border),
              const SizedBox(height: 16),
              const Text("Aun no tienes pedidos", style: TextStyle(fontSize: 16, color: AppColors.textLight, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => context.go("/home"), child: const Text("Pedir ahora")),
            ]))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length,
                itemBuilder: (ctx, i) {
                  final o = _orders[i];
                  final items = (o["order_items"] as List?) ?? [];
                  final statusColor = _colors[o["status"]] ?? AppColors.textLight;
                  return GestureDetector(
                    onTap: () => _showOrderDetail(context, o),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Row(children: [
                            Text(o["stores"]?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 10),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(o["stores"]?["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              Text("${items.length} producto${items.length != 1 ? "s" : ""}", style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                            ]),
                          ]),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(_fmt(o["total"]), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(_labels[o["status"]] ?? o["status"], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: statusColor)),
                            ),
                          ]),
                        ]),
                        if (items.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Text(items.take(2).map((i) => "${i["quantity"]}x ${i["item_name"]}").join(", ") + (items.length > 2 ? " +${items.length - 2} mas" : ""), style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                        ],
                        if (o["status"] == "delivered") ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: OutlinedButton(
                              onPressed: () => context.push("/home"),
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
                              child: const Text("Repetir pedido"),
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: ElevatedButton(
                              onPressed: () => _rateOrder(context, o["id"]),
                              child: const Text("Calificar"),
                            )),
                          ]),
                        ],
                        if (o["status"] == "on_the_way" || o["status"] == "preparing") ...[
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: () => context.push("/tracking/${o["id"]}"),
                            child: const Text("Ver seguimiento"),
                          ),
                        ],
                      ]),
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _showOrderDetail(BuildContext context, Map<String, dynamic> o) {
    final items = (o["order_items"] as List?) ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Text(o["stores"]?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o["stores"]?["name"] ?? "", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text("Pedido #${(o["id"] as String).substring(0, 8).toUpperCase()}", style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
              ]),
            ]),
            const SizedBox(height: 20),
            const Text("Productos", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textLight)),
            const SizedBox(height: 8),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("${item["quantity"]}x ${item["item_name"]}", style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(_fmt(item["subtotal"]), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            )),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Subtotal", style: TextStyle(color: AppColors.textLight)),
              Text(_fmt(o["subtotal"]), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Envio", style: TextStyle(color: AppColors.textLight)),
              Text(_fmt(o["delivery_fee"]), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Total", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text(_fmt(o["total"]), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.primary)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textLight),
              const SizedBox(width: 6),
              Expanded(child: Text(o["delivery_address"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 13))),
            ]),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
          ]),
        ),
      ),
    );
  }

  void _rateOrder(BuildContext context, String orderId) {
    int rating = 5;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(
      title: const Text("Calificar pedido"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Como fue tu experiencia?"),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => GestureDetector(
          onTap: () => setDialogState(() => rating = i + 1),
          child: Icon(i < rating ? Icons.star : Icons.star_outline, color: Colors.amber, size: 36),
        ))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          try {
            final o = _orders.firstWhere((x) => x["id"] == orderId, orElse: () => {});
            final storeId = o["store_id"] as String?;
            // Insertar en reviews y marcar orden como rated (consistente con PedidosScreen)
            await _sb.from("reviews").insert({
              "order_id": orderId,
              if (storeId != null) "store_id": storeId,
              "rating_store": rating,
            });
            await _sb.from("orders").update({
              "rated": true,
              "rated_at": DateTime.now().toIso8601String(),
            }).eq("id", orderId);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gracias por tu calificacion!")));
              setState(() {});
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error al guardar calificacion")));
            }
          }
        }, child: const Text("Enviar")),
      ],
    )));
  }
}
