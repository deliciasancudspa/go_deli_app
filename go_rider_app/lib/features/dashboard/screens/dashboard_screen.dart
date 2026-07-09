import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/services/notification_service.dart";
import "../../../providers/rider_provider.dart";

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _stats = {};
  final _sb = Supabase.instance.client;
  bool _ordersSubscribed = false;
  bool _chatSubscribed = false;
  String _subscribedRiderId = "";
  String _subscribedUserId = "";
  RiderProvider? _riderRef;
  int _unreadNotifCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await NotificationService.requestPermission();
      _riderRef = context.read<RiderProvider>();
      _riderRef!.addListener(_onRiderUpdate);
      _loadStats();
      _loadUnreadCount();
      _subscribeRealtime();
    });
  }

  // Reconnect Realtime channels every time the app comes back to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resubscribeAll();
      _loadUnreadCount();
    }
  }

  void _resubscribeAll() {
    if (_subscribedRiderId.isNotEmpty) {
      _sb.channel("rider-orders-$_subscribedRiderId").unsubscribe();
      _sb.channel("rider-notifs-$_subscribedRiderId").unsubscribe();
    }
    if (_subscribedUserId.isNotEmpty) {
      _sb.channel("rider-chat-$_subscribedUserId").unsubscribe();
    }
    _ordersSubscribed = false;
    _chatSubscribed = false;
    _subscribedRiderId = "";
    _subscribedUserId = "";
    _subscribeRealtime();
  }

  void _onRiderUpdate() {
    if (!mounted) return;
    _loadStats();
    _loadUnreadCount();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _riderRef?.removeListener(_onRiderUpdate);
    if (_subscribedRiderId.isNotEmpty) {
      _sb.channel("rider-orders-$_subscribedRiderId").unsubscribe();
      _sb.channel("rider-notifs-$_subscribedRiderId").unsubscribe();
    }
    if (_subscribedUserId.isNotEmpty) _sb.channel("rider-chat-$_subscribedUserId").unsubscribe();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) return;
    try {
      final data = await _sb.from("notifications")
          .select("id")
          .eq("type", "order_offer")
          .eq("target", rider.riderId)
          .eq("is_read", false);
      if (mounted) setState(() => _unreadNotifCount = (data as List).length);
    } catch (_) {}
  }

  double _riderFeeForOrder(Map<String, dynamic> o) {
    // rider_fee es calculado al crear la orden (checkout) y garantizado por el
    // trigger calculate_order_fees(). Solo puede ser null/0 en delivery propio,
    // donde el rider de GoRider no participa.
    return (o["rider_fee"] as num?)?.toDouble() ?? 0;
  }

  Future<void> _loadStats() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) return;
    final today = DateTime.now().toIso8601String().split("T")[0];
    try {
      final orders = await _sb.from("orders").select("total, rider_fee, payment_method, status").eq("deliverer_id", rider.riderId).gte("created_at", today);
      final list = List<Map<String, dynamic>>.from(orders);
      final delivered = list.where((o) => o["status"] == "delivered").toList();

      // Total ganado = suma de rider_fee de todos los pedidos entregados
      final totalEarned = delivered.fold(0.0, (s, o) => s + _riderFeeForOrder(o));

      // Ganancias por pedidos en efectivo (el rider ya tiene este dinero en su bolsillo)
      final cashEarnings = delivered
          .where((o) => o["payment_method"] == "cash")
          .fold(0.0, (s, o) => s + _riderFeeForOrder(o));

      // A depositar = solo ganancias de pedidos con tarjeta (la plataforma debe transferirlas)
      final toDeposit = totalEarned - cashEarnings;

      // Total de efectivo que el rider cobró a clientes (incluye lo que debe rendir a la plataforma)
      final cashHandled = delivered
          .where((o) => o["payment_method"] == "cash")
          .fold(0.0, (s, o) => s + ((o["total"] as num?)?.toDouble() ?? 0));

      // Lo que el rider debe rendir a la plataforma del efectivo cobrado
      final toRemit = cashHandled - cashEarnings;

      if (mounted) setState(() {
        _stats = {
          "orders": delivered.length,
          "earned": totalEarned,
          "toDeposit": toDeposit,
          "toRemit": toRemit,
          "cashEarnings": cashEarnings,
        };
      });
    } catch (_) {}
  }

  void _subscribeRealtime() {
    final rider = context.read<RiderProvider>();

    // Orders + notifications: set up once when riderId is available
    if (!_ordersSubscribed && rider.riderId.isNotEmpty) {
      _ordersSubscribed = true;
      _subscribedRiderId = rider.riderId;
      final riderId = rider.riderId;
      try {
        // Orders subscription keeps server-side filter (performance)
        _sb.channel("rider-orders-$riderId").onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: "public",
          table: "orders",
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "deliverer_id", value: riderId),
          callback: (payload) {
            if (!mounted) return;
            context.read<RiderProvider>().loadActiveOrders();
            _loadStats();
            final rec = payload.newRecord;
            if (rec["status"] == "assigned") {
              NotificationService.show(title: "🛵 Nuevo pedido asignado", body: "Tienes un nuevo pedido. Revisa los detalles.");
            }
          },
        ).subscribe();
        // Notifications: no server-side filter to avoid silent Realtime filter failures.
        // Filter client-side in callback.
        _sb.channel("rider-notifs-$riderId").onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: "public",
          table: "notifications",
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            if ((rec["target"] as String?) != riderId) return;  // client-side filter
            context.read<RiderProvider>().loadActiveOrders();
            _loadStats();
            _loadUnreadCount();
            final emoji = rec["emoji"] as String? ?? "";
            final title = rec["title"] as String? ?? "Go Rider";
            final msg   = rec["message"] as String? ?? "";
            NotificationService.show(title: "$emoji $title", body: msg);
          },
        ).subscribe();
      } catch (_) { _ordersSubscribed = false; _subscribedRiderId = ""; }
    }

    // Chat: receiver_id stores users.id — set up separately when user loads
    if (!_chatSubscribed) {
      final userId = rider.user?["id"] as String? ?? "";
      if (userId.isNotEmpty) {
        _chatSubscribed = true;
        _subscribedUserId = userId;
        try {
          // Chat: no server-side filter — filter client-side
          _sb.channel("rider-chat-$userId").onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: "public",
            table: "chat_messages",
            callback: (payload) {
              if (!mounted) return;
              final rec = payload.newRecord;
              if ((rec["receiver_id"] as String?) != userId) return;
              final orderId = rec["order_id"] as String?;
              if (orderId == null) return;
              final msg = rec["message"] as String? ?? "";
              NotificationService.show(
                title: "💬 Mensaje del cliente",
                body: msg,
                payload: "/chat/$orderId",
              );
            },
          ).subscribe();
        } catch (_) { _chatSubscribed = false; _subscribedUserId = ""; }
      }
    }
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
              onTap: () async {
                await context.push("/notifications");
                if (mounted) _loadUnreadCount();
              },
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
                child: Stack(clipBehavior: Clip.none, children: [
                  const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
                  if (_unreadNotifCount > 0)
                    Positioned(
                      right: -2, top: -2,
                      child: Container(
                        width: 9, height: 9,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                ]),
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
              Expanded(child: _kpi("A depositar", _fmt((_stats["toDeposit"] ?? 0).toDouble()), Icons.account_balance_outlined, AppColors.info)),
              const SizedBox(width: 12),
              Expanded(child: _kpi("A rendir", _fmt((_stats["toRemit"] ?? 0).toDouble()), Icons.swap_horiz, AppColors.warning)),
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
              ...() {
                final hasAhead = rider.activeOrders.any((o) => o["status"] == "picked_up" || o["status"] == "on_the_way");
                return rider.activeOrders.map((o) => _orderCard(o, context, queued: hasAhead && o["status"] == "assigned"));
              }(),
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

  Widget _orderCard(Map<String, dynamic> o, BuildContext context, {bool queued = false}) {
    final statusColors = {"assigned": AppColors.warning, "picked_up": AppColors.info, "on_the_way": AppColors.accent};
    final statusLabels = {"assigned": "Ve al restaurante", "picked_up": "Lleva al cliente", "on_the_way": "En camino"};
    final color = queued ? AppColors.info : (statusColors[o["status"]] ?? AppColors.textLight);
    return GestureDetector(
      onTap: () => context.push("/order/${o["id"]}"),
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
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(queued ? "🕒 En cola" : (statusLabels[o["status"]] ?? o["status"]), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textLight),
            const SizedBox(width: 4),
            Expanded(child: Text(o["delivery_address"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 12))),
            Text("\$${((o["total"] as num?) ?? 0).toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accent)),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => context.push("/order/${o["id"]}"), child: const Text("Ver detalles"))),
        ]),
      ),
    );
  }
}
