import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";

class TrackingScreen extends StatefulWidget {
  final String orderId;
  const TrackingScreen({super.key, required this.orderId});
  @override State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  Map<String, dynamic>? _order;
  final _sb = Supabase.instance.client;

  final _msgsDelivery = {
    "pending":   "Esperando confirmacion del restaurante",
    "accepted":  "Restaurante confirmo tu pedido",
    "preparing": "Preparando tu pedido",
    "ready":     "Listo! Esperando repartidor",
    "assigned":  "Repartidor asignado",
    "picked_up": "Repartidor recogió tu pedido",
    "on_the_way":"Tu pedido esta en camino",
    "delivered": "Entregado! Buen provecho 🎉",
    "cancelled": "Pedido cancelado",
  };

  final _msgsPickup = {
    "pending":   "Esperando confirmacion del restaurante",
    "accepted":  "Restaurante confirmo tu pedido",
    "preparing": "Preparando tu pedido",
    "ready":     "Tu pedido esta listo para retirar!",
    "delivered": "Pedido retirado exitosamente 🎉",
    "cancelled": "Pedido cancelado",
  };

  final _iconsDelivery = {
    "pending":   "⏳", "accepted": "✅", "preparing": "👨‍🍳",
    "ready":     "🎉", "assigned": "🛵", "picked_up": "📦",
    "on_the_way":"🚀", "delivered":"🏁", "cancelled": "❌",
  };

  final _iconsPickup = {
    "pending":   "⏳", "accepted": "✅", "preparing": "👨‍🍳",
    "ready":     "🏪", "delivered":"🏁", "cancelled": "❌",
  };

  @override
  void initState() { super.initState(); _load(); _subscribe(); }

  Future<void> _load() async {
    final o = await _sb.from("orders").select("*, stores(name,emoji)").eq("id", widget.orderId).single();
    if (mounted) setState(() => _order = o);
  }

  void _subscribe() {
    _sb.channel("order_${widget.orderId}")
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: "public",
        table: "orders",
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "id", value: widget.orderId),
        callback: (_) => _load(),
      ).subscribe();
  }

  @override
  Widget build(BuildContext context) {
    if (_order == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));

    final isPickup = _order!["order_type"] == "pickup";
    final msgs  = isPickup ? _msgsPickup  : _msgsDelivery;
    final icons = isPickup ? _iconsPickup : _iconsDelivery;

    final steps = isPickup
      ? ["pending", "accepted", "preparing", "ready", "delivered"]
      : ["pending", "accepted", "preparing", "ready", "assigned", "picked_up", "on_the_way", "delivered"];

    final status = _order!["status"] as String? ?? "pending";
    final cur = steps.indexOf(status);
    final isDone = status == "delivered";

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Seguimiento del pedido"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(children: [
        // Header estado actual
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDone ? [AppColors.success, const Color(0xFF16A34A)] : [AppColors.primary, const Color(0xFF5B21B6)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
          child: Column(children: [
            Text(icons[status] ?? "⏳", style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(msgs[status] ?? "", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text("${_order!["stores"]?["emoji"] ?? ""} ${_order!["stores"]?["name"] ?? ""}", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
          ]),
        ),

        // Steps
        Expanded(child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ...steps.asMap().entries.map((e) {
              final idx  = e.key;
              final step = e.value;
              final done = idx <= cur;
              final isCur = idx == cur;
              final isLast = idx == steps.length - 1;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: done ? AppColors.primary : AppColors.border,
                      shape: BoxShape.circle,
                      boxShadow: isCur ? [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 10)] : [],
                    ),
                    child: Center(child: done
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : Text("${idx+1}", style: const TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                  if (!isLast) AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 2, height: 44,
                    color: done ? AppColors.primary : AppColors.border,
                  ),
                ]),
                const SizedBox(width: 16),
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                  child: Text(
                    msgs[step] ?? step,
                    style: TextStyle(
                      fontWeight: isCur ? FontWeight.w800 : FontWeight.w600,
                      fontSize: isCur ? 15 : 14,
                      color: done ? AppColors.textDark : AppColors.textLight,
                    ),
                  ),
                )),
              ]);
            }),

            // Info tipo de pedido
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Tipo de entrega", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
                  Text(isPickup ? "🏪 Retiro en tienda" : "🛵 Delivery", style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                if (!isPickup && _order!["delivery_address"] != null) ...[
                  const Divider(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text("Dirección", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
                    Expanded(child: Text(_order!["delivery_address"], textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  ]),
                ],
                const Divider(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text("Total", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
                  Text("\$${((_order!["total"] as num?)?.toStringAsFixed(0)) ?? "0"}", style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.accent, fontSize: 16)),
                ]),
              ]),
            ),

            // Codigo de retiro en tienda
            if (isPickup && _order!["pickup_code"] != null && status == "ready") ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.success.withOpacity(0.4), width: 2),
                ),
                child: Column(children: [
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.store, color: AppColors.success, size: 20),
                    SizedBox(width: 8),
                    Text("Tu código de retiro", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
                  ]),
                  const SizedBox(height: 6),
                  const Text("Muéstralo en la tienda para retirar tu pedido", style: TextStyle(color: AppColors.textLight, fontSize: 12), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(_order!["pickup_code"], style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.success, letterSpacing: 8)),
                ]),
              ),
            ],

            // Codigo de entrega delivery
            if (!isPickup && _order!["delivery_code"] != null && ["on_the_way","picked_up"].contains(status)) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 2),
                ),
                child: Column(children: [
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.delivery_dining, color: AppColors.accent, size: 20),
                    SizedBox(width: 8),
                    Text("Tu código de entrega", style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
                  ]),
                  const SizedBox(height: 6),
                  const Text("Entrégalo al repartidor cuando recibas tu pedido", style: TextStyle(color: AppColors.textLight, fontSize: 12), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(_order!["delivery_code"], style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.accent, letterSpacing: 8)),
                ]),
              ),
            ],

            // Boton ver mapa
            if (["assigned","picked_up","on_the_way"].contains(status)) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push("/map/${widget.orderId}"),
                icon: const Icon(Icons.map_outlined),
                label: const Text("Ver en mapa"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],

            // Boton chat con repartidor
            if (["picked_up","on_the_way"].contains(status)) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => context.push("/chat/${widget.orderId}"),
                icon: const Icon(Icons.chat_outlined),
                label: const Text("Chatear con el repartidor"),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],

            const SizedBox(height: 24),
          ],
        )),
      ]),
    );
  }
}
