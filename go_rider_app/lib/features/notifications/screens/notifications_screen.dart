import "dart:async";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

const _kTimeout = 30;

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
      final order = await _sb.from("orders")
          .select("rider_search_status, deliverer_id")
          .eq("id", orderId)
          .single();

      final searchStatus = order["rider_search_status"] as String?;
      final assignedTo   = order["deliverer_id"] as String?;

      if (searchStatus != "assigned" || assignedTo != rider.riderId) {
        await _sb.from("notifications").update({"is_read": true}).eq("id", id);
        await _load();
        if (mounted) _showSnack("Este pedido ya no está disponible", AppColors.warning);
        return;
      }

      await _sb.from("orders").update({"status": "assigned"}).eq("id", orderId);
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
    if (orderId == null) {
      // No order_id — just mark read and remove
      try { await _sb.from("notifications").update({"is_read": true}).eq("id", id); } catch (_) {}
      await _load();
      return;
    }

    setState(() => _processing.add(id));
    try {
      await _sb.from("order_rejections").insert({"order_id": orderId, "rider_id": rider.riderId});
      await _sb.from("notifications").update({"is_read": true}).eq("id", id);
      await _load();
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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
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
                  const Text("Las nuevas ofertas aparecerán aquí", style: TextStyle(color: AppColors.textLight, fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  OutlinedButton(onPressed: _load, child: const Text("Actualizar")),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _notifications.length,
                    itemBuilder: (_, i) {
                      final notif = _notifications[i];
                      return _OfferCard(
                        key: ValueKey(notif["id"] as String),
                        notif: notif,
                        isProcessing: _processing.contains(notif["id"] as String),
                        onAccept: () => _accept(notif),
                        onExpired: () => _reject(notif),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-card widget — owns the countdown timer
// ─────────────────────────────────────────────────────────────────────────────
class _OfferCard extends StatefulWidget {
  final Map<String, dynamic> notif;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onExpired; // called both on "Rechazar" tap and timer expiry

  const _OfferCard({
    super.key,
    required this.notif,
    required this.isProcessing,
    required this.onAccept,
    required this.onExpired,
  });

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final raw     = widget.notif["created_at"] as String?;
    final created = raw != null ? (DateTime.tryParse(raw) ?? DateTime.now()) : DateTime.now();
    final elapsed = DateTime.now().toUtc().difference(created.toUtc()).inSeconds;
    _remaining    = (_kTimeout - elapsed).clamp(0, _kTimeout);

    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining--);
        if (_remaining <= 0) {
          _timer?.cancel();
          widget.onExpired();
        }
      });
    } else {
      // Already expired before the screen opened
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) widget.onExpired(); });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color get _timerColor {
    if (_remaining > 15) return AppColors.success;
    if (_remaining > 7)  return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final data       = (widget.notif["data"] as Map<String, dynamic>?) ?? {};
    final emoji      = widget.notif["emoji"] as String? ?? "🛵";
    final title      = data["title"] as String? ?? "Nuevo pedido";
    final message    = data["message"] as String? ?? "";
    final storeName  = data["store_name"] as String? ?? "";
    final storeEmoji = data["store_emoji"] as String? ?? "🍽️";
    final delivAddr  = data["delivery_address"] as String? ?? "";
    final total      = (data["total"] as num?)?.toDouble() ?? 0;
    final riderFee   = (data["rider_fee"] as num?)?.toDouble();
    final payMethod  = data["payment_method"] as String?;
    final itemsCount = (data["items_count"] as num?)?.toInt();
    final distance   = data["distance_km"] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _timerColor.withOpacity(0.45), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
          ),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textDark)),
              if (message.isNotEmpty)
                Text(message, style: const TextStyle(color: AppColors.textLight, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (total > 0)
                Text("\$${total.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.accent)),
              if (riderFee != null && riderFee > 0)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text("🛵 \$${riderFee.toStringAsFixed(0)} para ti",
                      style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              if (payMethod == "cash")
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: const Text("Efectivo", style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
            ]),
          ]),
        ),

        // Countdown bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text("Tiempo para responder",
                  style: TextStyle(fontSize: 11, color: _timerColor, fontWeight: FontWeight.w700)),
              Text("${_remaining}s",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _timerColor)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _remaining / _kTimeout,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(_timerColor),
                minHeight: 6,
              ),
            ),
          ]),
        ),

        // Detalles
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(children: [
            if (storeName.isNotEmpty)
              _detailRow(Text(storeEmoji, style: const TextStyle(fontSize: 13)), storeName),
            if (delivAddr.isNotEmpty)
              _detailRow(const Icon(Icons.location_on_outlined, size: 15, color: AppColors.textLight), delivAddr),
            if (itemsCount != null)
              _detailRow(const Icon(Icons.shopping_bag_outlined, size: 15, color: AppColors.textLight), "$itemsCount producto${itemsCount != 1 ? "s" : ""}"),
            if (distance != null)
              _detailRow(const Icon(Icons.route_outlined, size: 15, color: AppColors.textLight), "$distance km aproximados"),
          ]),
        ),

        // Botones
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: widget.isProcessing ? null : widget.onExpired,
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
              onPressed: widget.isProcessing ? null : widget.onAccept,
              icon: widget.isProcessing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check, size: 17),
              label: Text(widget.isProcessing ? "Procesando..." : "Aceptar"),
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

  Widget _detailRow(Widget icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(children: [
      SizedBox(width: 20, child: icon),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(color: AppColors.textMedium, fontSize: 13))),
    ]),
  );
}
