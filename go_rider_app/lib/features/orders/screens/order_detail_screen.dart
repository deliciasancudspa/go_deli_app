import "package:flutter/material.dart";
import "dart:async";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:geolocator/geolocator.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";
import "../../map/widgets/route_map_view.dart";

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
  bool _deliveryLoading = false;
  double? _riderLat, _riderLng; // ubicación en vivo del rider para el mapa
  double? _routeKm;             // distancia de la ruta calculada
  String? _routeEta;            // tiempo estimado (ej: "12 min")
  Timer? _gpsTimer;
  RealtimeChannel? _orderChannel;
  final _sb = Supabase.instance.client;
  final _deliveryCodeCtrl = TextEditingController();

  static const _activeStatuses = ["assigned", "picked_up", "on_the_way"];

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeOrder();
  }

  void _subscribeOrder() {
    _orderChannel = _sb.channel("order-detail-${widget.orderId}")
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: "public",
          table: "orders",
          callback: (payload) {
            if (!mounted) return;
            final id = payload.newRecord["id"] as String?;
            if (id != widget.orderId) return;
            _load();
          },
        ).subscribe();
  }

  @override
  void dispose() {
    _stopGps();
    _deliveryCodeCtrl.dispose();
    _orderChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await _sb.from("orders")
        .select("*, stores(name,emoji,address,phone,lat,lng), users!client_id(name,phone), order_items(item_name,quantity,item_price)")
        .eq("id", widget.orderId)
        .single();
      if (mounted) {
        setState(() { _order = o; _loading = false; });
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
      await _sendGps();
      _gpsTimer = Timer.periodic(const Duration(seconds: 8), (_) => _sendGps());
    } catch (_) {}
  }

  Future<void> _sendGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() { _riderLat = pos.latitude; _riderLng = pos.longitude; });
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

  Future<void> _openMaps(String? address, {double? lat, double? lng}) async {
    if (address == null && lat == null) return;
    final q = (lat != null && lng != null)
      ? "$lat,$lng"
      : Uri.encodeComponent(address ?? "");
    if (q.isEmpty) return;
    final uri = Uri.parse("https://maps.google.com/?q=$q");
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Abre navegación paso a paso (turn-by-turn) en Google Maps hacia el destino
  Future<void> _navigateTo(double lat, double lng) async {
    final uri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving");
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

  Future<void> _showReturnDialog(String reason) async {
    final label = reason == "not_found" ? "Cliente no localizado" : "Cliente rechazó el pedido";
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReturnDialogSheet(label: label),
    );
    if (note != null && mounted) {
      await _processReturn(reason, note, label);
    }
  }

  Future<void> _processReturn(String reason, String note, String reasonLabel) async {
    // Read sync values before any await to avoid context-after-dispose issues
    final riderName = context.read<RiderProvider>().riderName;
    final codigo = widget.orderId.substring(0, 8).toUpperCase();
    final storeId = _order?["store_id"] as String?;
    try {
      final noteText = note.isEmpty ? reasonLabel : note;

      await _sb.from("orders").update({
        "status": "returned",
        "return_reason": reason,
        "return_note": note.isEmpty ? null : note,
        "returned_at": DateTime.now().toIso8601String(),
      }).eq("id", widget.orderId);

      if (storeId != null) {
        await _sb.from("notifications").insert({
          "target": storeId,
          "title": "Pedido devuelto",
          "message": "El pedido #$codigo fue devuelto. Nota: $noteText",
          "emoji": "↩️",
        });
      }

      await _sb.from("notifications").insert({
        "target": "admin",
        "title": "Pedido devuelto",
        "message": "Pedido #$codigo devuelto por $riderName. Razón: $reasonLabel. Nota: ${note.isEmpty ? "-" : note}",
        "emoji": "⚠️",
      });

      _stopGps();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Devolución registrada"), backgroundColor: AppColors.warning));
        context.go("/dashboard");
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error));
    }
  }

  Future<void> _confirmDelivery() async {
    final entered = _deliveryCodeCtrl.text.trim().toUpperCase();
    if (entered.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingresa el código de 4 dígitos"), backgroundColor: AppColors.warning));
      return;
    }
    setState(() => _deliveryLoading = true);
    try {
      final result = await _sb.from("orders").select("delivery_code").eq("id", widget.orderId).single();
      final dbCode = (result["delivery_code"] as String?)?.toUpperCase() ?? "";
      if (entered == dbCode) {
        await _updateStatus("delivered");
      } else {
        if (mounted) {
          setState(() => _deliveryLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código incorrecto, intenta de nuevo"), backgroundColor: AppColors.error));
        }
      }
    } catch (_) {
      if (mounted) setState(() => _deliveryLoading = false);
    }
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
    final mapSection = _routeMapSection(status);

    final statusEmojis  = {"assigned":"🛵","picked_up":"📦","on_the_way":"🚀","delivered":"✅","cancelled":"❌"};
    final statusLabels  = {"assigned":"Ve al restaurante","picked_up":"Pedido recogido","on_the_way":"En camino al cliente","delivered":"Entregado","cancelled":"Cancelado"};
    final statusDescs   = {"assigned":"Dirígete al restaurante y muestra el código de retiro","picked_up":"Lleva el pedido al cliente","on_the_way":"Pide el código de entrega al cliente","delivered":"Entrega completada","cancelled":"Pedido cancelado"};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text("Pedido #${widget.orderId.substring(0,8).toUpperCase()}"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [
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
            Text(statusDescs[status] ?? "", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14)),
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

        // Mapa con la ruta según el estado del pedido
        if (mapSection != null) mapSection,

        // Código de retiro (visible solo cuando status == assigned)
        if (pickupCode != null && status == "assigned")
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 2)),
            child: Column(children: [
              const Text("Muestra este código al restaurante", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textLight, fontSize: 13)),
              const SizedBox(height: 8),
              Text(pickupCode, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.accent, letterSpacing: 8)),
            ]),
          ),

        _infoCard("Restaurante", _order!["stores"]?["emoji"] ?? "🍽️", _order!["stores"]?["name"] ?? "", _order!["stores"]?["address"] ?? "", _order!["stores"]?["phone"], _order!["stores"]?["address"]),
        const SizedBox(height: 12),
        _infoCard("Cliente", "👤", _order!["users"]?["name"] ?? "Cliente", _order!["delivery_address"] ?? "", _order!["users"]?["phone"], _order!["delivery_address"],
          lat: (_order!["delivery_lat"] as num?)?.toDouble(),
          lng: (_order!["delivery_lng"] as num?)?.toDouble(),
        ),
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

        // Botón de chat (visible en todos los estados activos)
        if (_activeStatuses.contains(status)) ...[
          OutlinedButton.icon(
            onPressed: () => context.push("/chat/${widget.orderId}"),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text("Chat con el cliente"),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.accent),
              minimumSize: const Size(double.infinity, 46),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Botones devolución (solo cuando el rider ya tiene el pedido)
        if (status == "picked_up" || status == "on_the_way") ...[
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _showReturnDialog("not_found"),
              icon: const Icon(Icons.person_off_outlined, size: 16),
              label: const Text("No localizado", overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: const BorderSide(color: AppColors.warning),
                minimumSize: const Size(0, 44),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _showReturnDialog("rejected"),
              icon: const Icon(Icons.block, size: 16),
              label: const Text("Pedido rechazado", overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(0, 44),
              ),
            )),
          ]),
          const SizedBox(height: 10),
        ],

        // Acción: En camino (solo picked_up)
        if (status == "picked_up") ElevatedButton.icon(
          onPressed: () => _updateStatus("on_the_way"),
          icon: const Icon(Icons.delivery_dining),
          label: const Text("En camino al cliente"),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size(double.infinity, 50)),
        ),

        // Acción: Confirmar entrega con código (solo on_the_way)
        if (status == "on_the_way") ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.success.withOpacity(0.4), width: 2)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.lock_outline, color: AppColors.success, size: 18),
                SizedBox(width: 8),
                Text("Confirmar entrega", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.success)),
              ]),
              const SizedBox(height: 4),
              const Text("Pide al cliente el código de 4 dígitos", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _deliveryCodeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 6),
                    decoration: const InputDecoration(
                      hintText: "0000",
                      counterText: "",
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _deliveryLoading ? null : _confirmDelivery,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size(100, 52)),
                  child: _deliveryLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Confirmar"),
                ),
              ]),
            ]),
          ),
        ],

        const SizedBox(height: 20),
      ]),
    );
  }

  // Mapa con la ruta de conducción según el estado del pedido:
  //  - assigned            → ruta del rider hacia la tienda (recoger)
  //  - picked_up/on_the_way→ ruta del rider hacia el cliente (entregar)
  Widget? _routeMapSection(String status) {
    final store = _order!["stores"] as Map?;
    final storeLat = (store?["lat"] as num?)?.toDouble();
    final storeLng = (store?["lng"] as num?)?.toDouble();
    final clientLat = (_order!["delivery_lat"] as num?)?.toDouble();
    final clientLng = (_order!["delivery_lng"] as num?)?.toDouble();

    LatLng dest;
    String destLabel;
    String title;
    double destHue;

    if (status == "assigned") {
      if (storeLat == null || storeLng == null) return null;
      dest = LatLng(storeLat, storeLng);
      destLabel = store?["name"] as String? ?? "Tienda";
      title = "🛵 Ruta a la tienda";
      destHue = BitmapDescriptor.hueOrange;
    } else if (status == "picked_up" || status == "on_the_way") {
      if (clientLat == null || clientLng == null) return null;
      dest = LatLng(clientLat, clientLng);
      destLabel = "Cliente";
      title = "🚀 Ruta al cliente";
      destHue = BitmapDescriptor.hueViolet;
    } else {
      return null;
    }

    final origin = (_riderLat != null && _riderLng != null) ? LatLng(_riderLat!, _riderLng!) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          if (_routeKm != null)
            Text("${_routeKm!.toStringAsFixed(1)} km${_routeEta != null ? " · $_routeEta" : ""}",
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        RouteMapView(
          origin: origin,
          destination: dest,
          originLabel: "Tú",
          destinationLabel: destLabel,
          destinationHue: destHue,
          height: 220,
          embedded: true,
          onRouteReady: (r) {
            if (mounted) setState(() { _routeKm = r.distanceKm; _routeEta = r.durationText; });
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _navigateTo(dest.latitude, dest.longitude),
            icon: const Icon(Icons.navigation_outlined, size: 18),
            label: const Text("Navegar con Google Maps"),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size(double.infinity, 46)),
          ),
        ),
        if (origin == null) ...[
          const SizedBox(height: 8),
          const Row(children: [
            Icon(Icons.gps_fixed, size: 13, color: AppColors.textLight),
            SizedBox(width: 6),
            Expanded(child: Text("Obteniendo tu ubicación GPS...", style: TextStyle(color: AppColors.textLight, fontSize: 12))),
          ]),
        ],
      ]),
    );
  }

  Widget _infoCard(String title, String emoji, String name, String subtitle, String? phone, String? address, {double? lat, double? lng}) =>
    Container(
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
          onPressed: () => _openMaps(address, lat: lat, lng: lng),
          icon: const Icon(Icons.map_outlined, size: 16),
          label: const Text("Ver mapa"),
        )),
      ]),
    ]),
  );
}

// Bottom sheet for return note — manages TextEditingController via StatefulWidget lifecycle
class _ReturnDialogSheet extends StatefulWidget {
  final String label;
  const _ReturnDialogSheet({required this.label});
  @override
  State<_ReturnDialogSheet> createState() => _ReturnDialogSheetState();
}

class _ReturnDialogSheetState extends State<_ReturnDialogSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24, right: 24, top: 24,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Devolver pedido", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(widget.label, style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: "Nota de devolución (opcional)...",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("Confirmar"),
          )),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }
}
