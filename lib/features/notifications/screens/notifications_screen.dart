import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  final _sb = Supabase.instance.client;

  static const _statusInfo = {
    "pending_payment": {"label": "Esperando pago",     "icon": Icons.payment_outlined,       "color": Color(0xFFF59E0B)},
    "pending":         {"label": "Pedido recibido",    "icon": Icons.receipt_outlined,       "color": Color(0xFFF59E0B)},
    "accepted":        {"label": "Pedido confirmado",   "icon": Icons.check_circle_outline,   "color": Color(0xFF3B82F6)},
    "preparing":       {"label": "Preparando tu pedido","icon": Icons.restaurant_outlined,    "color": Color(0xFFFF6B35)},
    "ready":           {"label": "¡Pedido listo!",      "icon": Icons.celebration_outlined,   "color": Color(0xFF22C55E)},
    "assigned":        {"label": "Repartidor asignado", "icon": Icons.delivery_dining,        "color": Color(0xFFF59E0B)},
    "picked_up":       {"label": "Pedido recogido",     "icon": Icons.inventory_2_outlined,   "color": Color(0xFF3B82F6)},
    "on_the_way":      {"label": "En camino a tu dirección","icon": Icons.rocket_launch_outlined,"color": Color(0xFFFF6B35)},
    "delivered":       {"label": "¡Entregado!",         "icon": Icons.where_to_vote_outlined, "color": Color(0xFF22C55E)},
    "cancelled":       {"label": "Pedido cancelado",    "icon": Icons.cancel_outlined,        "color": Color(0xFFEF4444)},
    "returned":        {"label": "Pedido devuelto",     "icon": Icons.assignment_return_outlined,"color": Color(0xFFEF4444)},
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) { setState(() => _loading = false); return; }
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).single();
      final orders = await _sb.from("orders")
        .select("id, status, created_at, updated_at, total, order_type, stores(name, emoji, logo_url)")
        .eq("client_id", u["id"])
        .order("updated_at", ascending: false)
        .limit(40);
      if (mounted) setState(() {
        _orders = List<Map<String, dynamic>>.from(orders);
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  String _timeAgo(String? dateStr) {
    if (dateStr == null) return "";
    final date = DateTime.tryParse(dateStr)?.toLocal();
    if (date == null) return "";
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return "Ahora mismo";
    if (diff.inMinutes < 60) return "Hace ${diff.inMinutes} min";
    if (diff.inHours < 24) return "Hace ${diff.inHours} h";
    if (diff.inDays == 1) return "Ayer";
    if (diff.inDays < 7) return "Hace ${diff.inDays} días";
    return "${date.day}/${date.month}/${date.year}";
  }

  Widget _storeAvatar(Map<String, dynamic>? store) {
    final logoUrl = store?["logo_url"] as String?;
    final emoji = store?["emoji"] as String? ?? "🍽️";
    return CircleAvatar(
      radius: 12,
      backgroundColor: AppColors.border,
      backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
      child: logoUrl == null ? Text(emoji, style: const TextStyle(fontSize: 12)) : null,
    );
  }

  String _fmt(num? p) {
    if (p == null) return "\$0";
    return "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Notificaciones"),
        backgroundColor: Colors.transparent,
        flexibleSpace: const GradientFlexibleSpace(),
        actions: [
          if (_orders.isNotEmpty) TextButton(
            onPressed: _load,
            child: const Text("Actualizar", style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : _orders.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("🔔", style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text("Sin notificaciones aún", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text("Aquí verás las actualizaciones de tus pedidos", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textLight)),
            ]))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.accent,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _orders.length,
                itemBuilder: (ctx, i) {
                  final o = _orders[i];
                  final status = o["status"] as String? ?? "pending";
                  final info = _statusInfo[status] ?? _statusInfo["pending"]!;
                  final color = info["color"] as Color;
                  final icon  = info["icon"] as IconData;
                  final label = info["label"] as String;
                  final isActive = !["delivered", "cancelled"].contains(status);
                  final store = o["stores"] as Map<String, dynamic>?;

                  return GestureDetector(
                    onTap: () => context.push("/tracking/${o["id"]}"),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive ? color.withOpacity(0.35) : AppColors.border,
                          width: isActive ? 1.5 : 1,
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          // Icono de estado
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          // Contenido
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(label,
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                                  color: isActive ? AppColors.textDark : AppColors.textMedium))),
                              Text(_timeAgo(o["updated_at"]),
                                style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
                            ]),
                            const SizedBox(height: 3),
                            Row(children: [
                              _storeAvatar(store),
                              const SizedBox(width: 6),
                              Expanded(child: Text(store?["name"] ?? "",
                                style: const TextStyle(color: AppColors.textMedium, fontSize: 13),
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(_fmt(o["total"] as num?),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary)),
                              const Text(" · ", style: TextStyle(color: AppColors.textLight)),
                              Text((o["order_type"] == "pickup") ? "Retiro en tienda" : "Delivery",
                                style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                            ]),
                          ])),
                          // Flecha
                          if (isActive) const Padding(
                            padding: EdgeInsets.only(left: 4, top: 2),
                            child: Icon(Icons.chevron_right, color: AppColors.textLight, size: 18),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
