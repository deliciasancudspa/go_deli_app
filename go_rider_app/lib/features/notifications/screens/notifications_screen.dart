import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  final Set<String> _processing = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) { if (mounted) setState(() => _loading = false); return; }
    try {
      final data = await _sb.from("notifications")
        .select()
        .eq("type", "order_offer")
        .eq("target", rider.riderId)
        .eq("is_read", false)
        .order("created_at", ascending: false);
      if (mounted) setState(() { _notifications = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _accept(Map<String, dynamic> notif) async {
    final id = notif["id"] as String;
    if (_processing.contains(id)) return;
    final rider = context.read<RiderProvider>();
    final orderId = (notif["data"] as Map?)?["order_id"] as String?;
    if (orderId == null) { _showSnack("Notificación sin pedido asociado", AppColors.error); return; }

    setState(() => _processing.add(id));
    try {
      await _sb.from("orders").update({"status": "assigned", "deliverer_id": rider.riderId}).eq("id", orderId);
      await _sb.from("notifications").update({"is_read": true}).eq("id", id);
      rider.loadActiveOrders();
      await _load();
      if (mounted) _showSnack("✅ Pedido aceptado", AppColors.success);
    } catch (e) {
      if (mounted) _showSnack("Error al aceptar: $e", AppColors.error);
    } finally {
      if (mounted) setState(() => _processing.remove(id));
    }
  }

  Future<void> _reject(Map<String, dynamic> notif) async {
    final id = notif["id"] as String;
    if (_processing.contains(id)) return;
    final rider = context.read<RiderProvider>();
    final orderId = (notif["data"] as Map?)?["order_id"] as String?;
    if (orderId == null) { _showSnack("Notificación sin pedido asociado", AppColors.error); return; }

    setState(() => _processing.add(id));
    try {
      await _sb.from("order_rejections").insert({"order_id": orderId, "rider_id": rider.riderId});
      await _sb.from("notifications").update({"is_read": true}).eq("id", id);
      await _load();
      if (mounted) _showSnack("Pedido rechazado", AppColors.textLight);
    } catch (e) {
      if (mounted) _showSnack("Error al rechazar: $e", AppColors.error);
    } finally {
      if (mounted) setState(() => _processing.remove(id));
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Ofertas de pedidos"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () { setState(() => _loading = true); _load(); }),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : _notifications.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("📭", style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              const Text("Sin ofertas pendientes", style: TextStyle(color: AppColors.textLight, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text("Las nuevas ofertas de pedidos aparecerán aquí", style: TextStyle(color: AppColors.textLight, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: _load, child: const Text("Actualizar")),
            ]))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.accent,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _notifications.length,
                itemBuilder: (_, i) => _offerCard(_notifications[i]),
              ),
            ),
    );
  }

  Widget _offerCard(Map<String, dynamic> notif) {
    final id = notif["id"] as String;
    final data = (notif["data"] as Map<String, dynamic>?) ?? {};
    final isProcessing = _processing.contains(id);

    final emoji       = notif["emoji"] as String? ?? "🛵";
    final title       = data["title"] as String? ?? "Nuevo pedido";
    final message     = data["message"] as String? ?? "";
    final storeName   = data["store_name"] as String? ?? "";
    final storeEmoji  = data["store_emoji"] as String? ?? "🍽️";
    final delivAddr   = data["delivery_address"] as String? ?? "";
    final total       = (data["total"] as num?)?.toDouble() ?? 0;
    final payMethod   = data["payment_method"] as String?;
    final itemsCount  = (data["items_count"] as num?)?.toInt();
    final distance    = data["distance_km"] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withOpacity(0.35), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(17))),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textDark)),
              if (message.isNotEmpty) Text(message, style: const TextStyle(color: AppColors.textLight, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            if (total > 0) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text("\$${total.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.accent)),
              if (payMethod == "cash") Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                child: const Text("Efectivo", style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ]),
          ]),
        ),

        // Detalles
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(children: [
            if (storeName.isNotEmpty) _detailRow(Text(storeEmoji), storeName, null),
            if (delivAddr.isNotEmpty) _detailRow(const Icon(Icons.location_on_outlined, size: 15, color: AppColors.textLight), delivAddr, null),
            if (itemsCount != null) _detailRow(const Icon(Icons.shopping_bag_outlined, size: 15, color: AppColors.textLight), "$itemsCount producto${itemsCount != 1 ? "s" : ""}", null),
            if (distance != null) _detailRow(const Icon(Icons.route_outlined, size: 15, color: AppColors.textLight), "$distance km aproximados", null),
          ]),
        ),

        // Botones
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: isProcessing ? null : () => _reject(notif),
              icon: const Icon(Icons.close, size: 17),
              label: const Text("Rechazar"),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(0, 46),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(
              onPressed: isProcessing ? null : () => _accept(notif),
              icon: isProcessing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check, size: 17),
              label: Text(isProcessing ? "Procesando..." : "Aceptar"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                minimumSize: const Size(0, 46),
              ),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _detailRow(Widget icon, String text, String? trailing) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(children: [
      SizedBox(width: 20, child: icon),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(color: AppColors.textMedium, fontSize: 13))),
      if (trailing != null) Text(trailing, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
    ]),
  );
}
