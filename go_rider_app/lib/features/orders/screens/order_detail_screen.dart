import "package:flutter/material.dart";
import "dart:async";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:geolocator/geolocator.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  bool _gpsActive = false;
  Timer? _gpsTimer;
  final _sb = Supabase.instance.client;

  static const _activeStatuses = ["assigned", "picked_up", "on_the_way"];

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _stopGps(); super.dispose(); }

  Future<void> _load() async {
    try {
      final o = await _sb.from("orders")
        .select("*, stores(name,emoji,address,phone), users!client_id(name,phone), order_items(item_name,quantity,item_price)")
        .eq("id", widget.orderId)
        .single();
      if (mounted) {
        setState(() { _order = o; _loading = false; });
        // Iniciar GPS si el pedido está activo
        if (_activeStatuses.contains(o["status"])) _startGps();
      }
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  // ── GPS ──────────────────────────────────────────────
  Future<void> _startGps() async {
    if (_gpsActive) return;
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;

      setState(() => _gpsActive = true);
      await _sendGps(); // envío inmediato
      _gpsTimer = Timer.periodic(const Duration(seconds: 8), (_) => _sendGps());
    } catch (_) {}
  }

  Future<void> _sendGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      if (mounted) {
        await context.read<RiderProvider>().sendLocation(pos.latitude, pos.longitude);
      }
    } catch (_) {}
  }

  void _stopGps() {
    _gpsTimer?.cancel();
    _gpsActive = false;
  }
  // ─────────────────────────────────────────────────────

  Future<void> _call(String? phone) async {
    if (phone == null) return;
    final uri = Uri.parse("tel:$phone");
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openMaps(String? address) async {
    if (address == null) return;
    final uri = Uri.parse("https://maps.google.com/?q=${Uri.encodeComponent(address)}");
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _updateStatus(String newStatus) async {
    final rider = context.read<RiderProvider>();
    await rider.updateOrderStatus(widget.orderId, newStatus);
    if (newStatus == "delivered") _stopGps();
    await _load();
    if (newStatus == "delivered" && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Entrega confirmada!"), backgroundColor: AppColors.success));
      context.go("/dashboard");
    }
  }

  void _showDeliveryConfirm(double total, String? payMethod) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Confirmar entrega"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Confirma que el pedido fue entregado al cliente."),
        if (payMethod == "cash") ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Text("Recuerda cobrar \$${total.toStringAsFixed(0)} en efectivo.", style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); _updateStatus("delivered"); },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          child: const Text("Confirmar"),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (_order == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text("Pedido no encontrado")));

    final status = _order!["status"] as String;
    final items = (_order!["order_items"] as List?) ?? [];
    final total = (_order!["total"] as num?)?.toDouble() ?? 0;
    final payMethod = _order!["payment_method"] as String?;
    final pickupCode = _order!["pickup_code"] as String?;

    final statusEmojis  = {"assigned":"🛵","picked_up":"📦","on_the_way":"🚀","delivered":"✅","cancelled":"❌"};
    final statusLabels  = {"assigned":"Ve al restaurante","picked_up":"Pedido recogido","on_the_way":"En camino al cliente","delivered":"Entregado","cancelled":"Cancelado"};
    final statusDescs   = {"assigned":"Dirígete al restaurante y muestra el codigo de retiro","picked_up":"Lleva el pedido al cliente","on_the_way":"El cliente esta esperando su pedido","delivered":"Entrega completada","cancelled":"Pedido cancelado"};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text("Pedido #${widget.orderId.substring(0,8).toUpperCase()}"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go("/orders")),
        actions: [
          // Indicador GPS en vivo
          if (_gpsActive) Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              const Text("GPS", style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Header estado
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF2d1b69)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: [
            Text(statusEmojis[status] ?? "⏳", style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text(statusLabels[status] ?? status, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(statusDescs[status] ?? "", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
            // GPS activo badge
            if (_gpsActive) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.location_on, color: AppColors.success, size: 14),
                  SizedBox(width: 6),
                  Text("Compartiendo ubicación en tiempo real", style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        // Código de retiro
        if (pickupCode != null && status == "assigned")
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 2)),
            child: Column(children: [
              const Text("Muestra este codigo al restaurante", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textLight, fontSize: 13)),
              const SizedBox(height: 8),
              Text(pickupCode, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.accent, letterSpacing: 8)),
            ]),
          ),

        _infoCard("Restaurante", _order!["stores"]?["emoji"] ?? "🍽️", _order!["stores"]?["name"] ?? "", _order!["stores"]?["address"] ?? "", _order!["stores"]?["phone"], _order!["stores"]?["address"]),
        const SizedBox(height: 12),
        _infoCard("Cliente", "👤", _order!["users"]?["name"] ?? "Cliente", _order!["delivery_address"] ?? "", _order!["users"]?["phone"], _order!["delivery_address"]),
        const SizedBox(height: 12),

        // Productos
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Productos", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 12),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text("${item["quantity"]}x ", style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
                Expanded(child: Text(item["item_name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w600))),
                Text("\$${((item["item_price"] as num?) ?? 0).toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            )),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Total", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text("\$${total.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.accent)),
            ]),
            if (payMethod == "cash") ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.payments_outlined, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Text("Cobra \$${total.toStringAsFixed(0)} en efectivo", style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 20),

        // Botones de acción
        if (status == "assigned") ElevatedButton.icon(
          onPressed: () => _updateStatus("picked_up"),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text("Confirmar retiro del restaurante"),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size(double.infinity, 50)),
        ),
        if (status == "picked_up") ElevatedButton.icon(
          onPressed: () => _updateStatus("on_the_way"),
          icon: const Icon(Icons.delivery_dining),
          label: const Text("En camino al cliente"),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size(double.infinity, 50)),
        ),
        if (status == "on_the_way") ElevatedButton.icon(
          onPressed: () => _showDeliveryConfirm(total, payMethod),
          icon: const Icon(Icons.check_circle),
          label: const Text("Confirmar entrega"),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size(double.infinity, 50)),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _infoCard(String title, String emoji, String name, String subtitle, String? phone, String? address) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
      const SizedBox(height: 8),
      Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
        ])),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        if (phone != null) Expanded(child: OutlinedButton.icon(
          onPressed: () => _call(phone),
          icon: const Icon(Icons.phone, size: 16),
          label: const Text("Llamar"),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent, side: const BorderSide(color: AppColors.accent)),
        )),
        if (phone != null && address != null) const SizedBox(width: 8),
        if (address != null) Expanded(child: ElevatedButton.icon(
          onPressed: () => _openMaps(address),
          icon: const Icon(Icons.map_outlined, size: 16),
          label: const Text("Ver mapa"),
        )),
      ]),
    ]),
  );
}
