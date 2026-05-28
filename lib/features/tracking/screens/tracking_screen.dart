import "package:flutter/material.dart";
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
  final _msgs = {"pending": "Esperando confirmacion", "accepted": "Restaurante confirmo", "preparing": "Preparando tu pedido", "ready": "Listo para recoger", "assigned": "Repartidor asignado", "picked_up": "Repartidor en camino", "on_the_way": "Tu pedido esta en camino", "delivered": "Entregado! Buen provecho", "cancelled": "Pedido cancelado"};
  @override void initState() { super.initState(); _load(); _subscribe(); }
  Future<void> _load() async { final o = await _sb.from("orders").select("*, stores(name,emoji)").eq("id", widget.orderId).single(); if (mounted) setState(() => _order = o); }
  void _subscribe() { _sb.channel("order_${widget.orderId}").onPostgresChanges(event: PostgresChangeEvent.update, schema: "public", table: "orders", filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "id", value: widget.orderId), callback: (_) => _load()).subscribe(); }
  @override Widget build(BuildContext context) {
    if (_order == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    final steps = ["pending", "accepted", "preparing", "ready", "assigned", "picked_up", "on_the_way", "delivered"];
    final cur = steps.indexOf(_order!["status"] ?? "pending");
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: const Text("Seguimiento")), body: Column(children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight)), child: Text(_msgs[_order!["status"]] ?? "", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
      Expanded(child: ListView(padding: const EdgeInsets.all(20), children: steps.asMap().entries.map((e) { final done = e.key <= cur; final isCur = e.key == cur; return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Column(children: [Container(width: 32, height: 32, decoration: BoxDecoration(color: done ? AppColors.primary : AppColors.border, shape: BoxShape.circle), child: Icon(done ? Icons.check : Icons.circle_outlined, color: done ? Colors.white : AppColors.textLight, size: 16)), if (e.key < steps.length-1) Container(width: 2, height: 40, color: done ? AppColors.primary : AppColors.border)]), const SizedBox(width: 16), Expanded(child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msgs[e.value] ?? "", style: TextStyle(fontWeight: isCur ? FontWeight.w800 : FontWeight.w600, color: done ? AppColors.textDark : AppColors.textLight))))]); }).toList())),
      if (_order!["pickup_code"] != null) Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withOpacity(0.3))), child: Column(children: [const Text("Codigo de retiro", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textLight)), const SizedBox(height: 8), Text(_order!["pickup_code"], style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 8))])),
    ]));
  }
}