import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _stats = {};
  final _sb = Supabase.instance.client;
  bool _subscribed = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _subscribeRealtime();
    // Safety net: if riderId wasn't ready at initState, retry after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_subscribed) _subscribeRealtime();
    });
  }

  @override
  void dispose() {
    final riderId = context.read<RiderProvider>().riderId;
    if (riderId.isNotEmpty) {
      _sb.channel("rider-orders-$riderId").unsubscribe();
      _sb.channel("rider-notifs-$riderId").unsubscribe();
    }
    super.dispose();
  }

  Future<void> _loadStats() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) return;
    final today = DateTime.now().toIso8601String().split("T")[0];
    try {
      final orders = await _sb.from("orders").select("total, payment_method, status").eq("deliverer_id", rider.riderId).gte("created_at", today);
      final list = List<Map<String, dynamic>>.from(orders);
      final delivered = list.where((o) => o["status"] == "delivered").toList();
      final totalEarned = delivered.fold(0.0, (s, o) => s + ((o["total"] as num) * 0.15));
      final cashReceived = delivered.where((o) => o["payment_method"] == "cash").fold(0.0, (s, o) => s + (o["total"] as num));
      if (mounted) setState(() { _stats = {"orders": delivered.length, "earned": totalEarned, "cash": cashReceived, "toDeposit": totalEarned - cashReceived}; });
    } catch (_) {}
  }

  void _subscribeRealtime() {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) return;
    if (_subscribed) return;
    _subscribed = true;
    try {
      _sb.channel("rider-orders-${rider.riderId}").onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: "public",
        table: "orders",
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "deliverer_id", value: rider.riderId),
        callback: (_) { rider.loadActiveOrders(); _loadStats(); },
      ).subscribe();
      _sb.channel("rider-notifs-${rider.riderId}").onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: "public",
        table: "notifications",
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "target", value: rider.riderId),
        callback: (_) { rider.loadActiveOrders(); _loadStats(); },
      ).subscribe();
    } catch (_) { _subscribed = false; }
  }

  String _fmt(double n) => "\$${n.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  Future<void> _confirmExit(BuildContext ctx) async {
    final shouldExit = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text("Salir de Go Rider"),
        content: const Text("¿Deseas salir de la aplicación?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(dCtx, true),  child: const Text("Salir")),
        ],
      ),
    );
    if (shouldExit == true) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _confirmExit(context); },
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: Column(children: [
        Container(color: AppColors.primary, padding: const EdgeInsets.all(20), child: Column(children: [
          Row(children: [
            CircleAvatar(radius: 24, backgroundColor: AppColors.accent, child: Text(rider.riderName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Hola, ${rider.riderName.split(" ")[0]}!", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              Text(rider.isOnline ? "En linea" : "Desconectado", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
            ])),
            GestureDetector(
              onTap: () => context.go("/notifications"),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
                child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
              ),
            ),
            GestureDetector(
              onTap: () async { await rider.toggleOnline(); _loadStats(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 64, height: 32,
                decoration: BoxDecoration(color: rider.isOnline ? AppColors.success : Colors.white24, borderRadius: BorderRadius.circular(16)),
                child: Stack(children: [
                  AnimatedPositioned(duration: const Duration(milliseconds: 300), left: rider.isOnline ? 34 : 2, top: 2, child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                ]),
              ),
            ),
          ]),
          if (!rider.isOnline) ...[
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.info_outline, color: Colors.white54, size: 18), SizedBox(width: 8), Text("Activa tu modo online para recibir pedidos", style: TextStyle(color: Colors.white70, fontSize: 13))])),
          ],
        ])),
        Expanded(child: RefreshIndicator(
          onRefresh: () async { await _loadStats(); await rider.loadActiveOrders(); },
          color: AppColors.accent,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text("Resumen de hoy", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMedium)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _kpi("Pedidos", "${_stats["orders"] ?? 0}", Icons.delivery_dining, AppColors.accent)),
              const SizedBox(width: 12),
              Expanded(child: _kpi("Ganado", _fmt((_stats["earned"] ?? 0).toDouble()), Icons.attach_money, AppColors.success)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _kpi("Efectivo", _fmt((_stats["cash"] ?? 0).toDouble()), Icons.payments_outlined, AppColors.warning)),
              const SizedBox(width: 12),
              Expanded(child: _kpi("A depositar", _fmt((_stats["toDeposit"] ?? 0).toDouble()), Icons.account_balance_outlined, AppColors.info)),
            ]),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Pedidos activos", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              TextButton(onPressed: () => context.go("/orders"), child: const Text("Ver todos")),
            ]),
            const SizedBox(height: 8),
            if (rider.activeOrders.isEmpty)
              Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)), child: Column(children: [
                const Text("🛵", style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(rider.isOnline ? "Sin pedidos asignados" : "Activa tu modo online", style: const TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
              ]))
            else
              ...rider.activeOrders.map((o) => _orderCard(o, context)),
          ]),
        )),
      ])),
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 22), const SizedBox(height: 8),
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _orderCard(Map<String, dynamic> o, BuildContext context) {
    final statusColors = {"assigned": AppColors.warning, "picked_up": AppColors.info, "on_the_way": AppColors.accent};
    final statusLabels = {"assigned": "Ve al restaurante", "picked_up": "Lleva al cliente", "on_the_way": "En camino"};
    final color = statusColors[o["status"]] ?? AppColors.textLight;
    return GestureDetector(
      onTap: () => context.go("/order/${o["id"]}"),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.4), width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(o["stores"]?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o["stores"]?["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(o["stores"]?["address"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(statusLabels[o["status"]] ?? o["status"], style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textLight),
            const SizedBox(width: 4),
            Expanded(child: Text(o["delivery_address"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 12))),
            Text("\$${((o["total"] as num?) ?? 0).toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accent)),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => context.go("/order/${o["id"]}"), child: const Text("Ver detalles"))),
        ]),
      ),
    );
  }
}
