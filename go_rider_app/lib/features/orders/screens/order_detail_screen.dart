import "package:flutter/material.dart";
import "dart:async";
import "package:flutter/foundation.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:geolocator/geolocator.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/services/connectivity_service.dart";
import "../../../core/utils/chile_time.dart";
import "../../../providers/rider_provider.dart";
import "../../map/widgets/route_map_view.dart";
import "../../../core/services/voice_navigation_service.dart";
import "../../../core/services/directions_service.dart";
import "../../../l10n/app_localizations.dart";

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
  bool _hasOrderAhead = false;  // el rider tiene otro pedido en curso por delante
  Timer? _gpsTimer;
  int _codeAttempts = 0;        // intentos fallidos de código de entrega
  bool _codeLocked = false;     // 3 intentos fallidos → verificación alternativa

  // Navegación por voz
  VoiceNavigationService? _voiceNav;
  bool _voiceNavEnabled = false;
  List<NavStep>? _voiceSteps;

  // Pedido en cola: aceptado mientras el rider aún tiene otro pedido en ruta.
  // No se navega hasta entregar el de adelante.
  bool get _isQueued => _hasOrderAhead && _order?["status"] == "assigned";
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
    _voiceNav?.dispose();
    _deliveryCodeCtrl.dispose();
    _orderChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final riderId = context.read<RiderProvider>().riderId;
      final o = await _sb.from("orders")
        .select("*, stores(name,emoji,logo_url,address,phone,lat,lng), users!client_id(name,phone), order_items(item_name,quantity,item_price)")
        .eq("id", widget.orderId)
        .single();
      // ¿El rider tiene otro pedido en curso por delante? (para la cola)
      bool ahead = false;
      if (riderId.isNotEmpty) {
        final others = await _sb.from("orders").select("id")
            .eq("deliverer_id", riderId)
            .inFilter("status", ["picked_up", "on_the_way"])
            .neq("id", widget.orderId);
        ahead = (others as List).isNotEmpty;
      }
      if (mounted) {
        setState(() { _order = o; _hasOrderAhead = ahead; _loading = false; });
        // No iniciar GPS para un pedido en cola: la navegación es del de adelante
        if (_activeStatuses.contains(o["status"]) && !_isQueued) _startGps();
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
      if (perm == LocationPermission.deniedForever) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS desactivado permanentemente. Actívalo en Ajustes del sistema.'), backgroundColor: AppColors.error));
        return;
      }
      setState(() => _gpsActive = true);
      await _sendGps();
      _gpsTimer = Timer.periodic(const Duration(seconds: 8), (_) => _sendGps());
    } catch (e) {
      debugPrint('[GoRider] OrderDetail _startGps error: $e');
    }
  }

  Future<void> _sendGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() { _riderLat = pos.latitude; _riderLng = pos.longitude; });
        await context.read<RiderProvider>().sendLocation(pos.latitude, pos.longitude);
        // Navegación por voz: monitorear posición vs pasos de ruta
        if (_voiceNav != null && _voiceNavEnabled) {
          _voiceNav!.checkPosition(LatLng(pos.latitude, pos.longitude));
        }
      }
    } catch (e) {
      debugPrint('[GoRider] OrderDetail _sendGps error: $e');
    }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.orderDeliveryConfirmed), backgroundColor: AppColors.success));
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

  // ── Reporte de incidente ─────────────────────────────────────────────────

  Future<void> _showIncidentDialog() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _IncidentSheet(),
    );
    if (result != null && mounted) {
      await _processIncident(result["reason"]!, result["note"] ?? "");
    }
  }

  Future<void> _processIncident(String reason, String note) async {
    setState(() => _deliveryLoading = true);
    try {
      // Intentar obtener ubicación fresca primero (más precisa para el incidente)
      double? lat, lng;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 5));
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        // Fallback: última ubicación conocida del GPS en vivo
        lat = _riderLat;
        lng = _riderLng;
      }

      if (lat == null || lng == null) {
        if (mounted) {
          setState(() => _deliveryLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No se pudo obtener tu ubicación. Intenta de nuevo."), backgroundColor: AppColors.error),
          );
        }
        return;
      }

      final result = await _sb.rpc("rider_report_incident", params: {
        "p_order_id": widget.orderId,
        "p_reason": reason,
        "p_note": note,
        "p_lat": lat,
        "p_lng": lng,
      });

      if (result == "ok" && mounted) {
        _stopGps();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Incidente reportado. Soporte te contactará."), backgroundColor: AppColors.warning),
        );
        context.go("/dashboard");
      } else {
        if (mounted) {
          setState(() => _deliveryLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $result"), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deliveryLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al reportar: $e"), backgroundColor: AppColors.error),
        );
      }
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
        "returned_at": ChileTime.now().toIso8601String(),
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
        _codeAttempts = 0;
        await _updateStatus("delivered");
      } else {
        _codeAttempts++;
        if (mounted) {
          setState(() => _deliveryLoading = false);
          if (_codeAttempts >= 3) {
            setState(() => _codeLocked = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Demasiados intentos. Usa la verificación alternativa."), backgroundColor: AppColors.warning, duration: Duration(seconds: 4)),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Código incorrecto. ${3 - _codeAttempts} intento(s) restante(s)."), backgroundColor: AppColors.error),
            );
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _deliveryLoading = false);
    }
  }

  /// Verificación alternativa: confirma la entrega sin código (admin es notificado).
  Future<void> _confirmDeliveryWithoutCode() async {
    setState(() => _deliveryLoading = true);
    try {
      final result = await _sb.rpc("rider_confirm_delivery_override", params: {
        "p_order_id": widget.orderId,
      });

      if (result == "ok" && mounted) {
        _stopGps();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Entrega confirmada (verificación alternativa)"), backgroundColor: AppColors.warning));
        context.go("/dashboard");
      } else {
        if (mounted) {
          setState(() => _deliveryLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $result"), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deliveryLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    final l10n = AppLocalizations.of(context)!;
    if (_order == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(l10n.orderNotFound)));

    final status = _order!["status"] as String;
    final items = (_order!["order_items"] as List?) ?? [];
    final total = (_order!["total"] as num?)?.toDouble() ?? 0;
    final riderFee = (_order!["rider_fee"] as num?)?.toDouble() ?? 0;
    final payMethod = _order!["payment_method"] as String?;
    final pickupCode = _order!["pickup_code"] as String?;
    // Mientras esté en cola no se navega: se muestra aviso en vez del mapa de ruta.
    final mapSection = _isQueued ? null : _routeMapSection(status);

    final statusEmojis  = {"assigned":"🛵","picked_up":"📦","on_the_way":"🚀","delivered":"✅","cancelled":"❌"};
    final statusLabels  = {"assigned":l10n.orderPickup,"picked_up":l10n.orderPickedUp,"on_the_way":l10n.orderOnTheWay,"delivered":l10n.orderDelivered,"cancelled":l10n.orderCancelled};
    final statusDescs   = {"assigned":l10n.orderStatusPickupDesc,"picked_up":l10n.orderStatusPickedUpDesc,"on_the_way":l10n.orderStatusOnWayDesc,"delivered":l10n.orderStatusDeliveredDesc,"cancelled":l10n.orderStatusCancelledDesc};

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
              Text(l10n.gps, style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Banner de desconexión
        ValueListenableBuilder<bool>(
          valueListenable: ConnectivityService.instance.isOnline,
          builder: (ctx, online, _) {
            if (online) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Expanded(child: Text(l10n.dashboardOfflineBanner, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
            );
          },
        ),
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
                  Text(l10n.orderSharingLocation, style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 16),

        // Aviso de pedido en cola (aceptado mientras hay otro en ruta)
        if (_isQueued)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.info.withOpacity(0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.schedule, color: AppColors.info, size: 22),
              SizedBox(width: 10),
              Expanded(child: Text(
                "Pedido en cola. Termina primero tu entrega en curso; al confirmarla se activará la navegación de este pedido.",
                style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w600, fontSize: 13),
              )),
            ]),
          ),

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

        _infoCard("Restaurante", _order!["stores"]?["emoji"] ?? "🍽️", _order!["stores"]?["name"] ?? "", _order!["stores"]?["address"] ?? "", _order!["stores"]?["phone"], _order!["stores"]?["address"],
          logoUrl: _order!["stores"]?["logo_url"] as String?),
        const SizedBox(height: 12),
        _infoCard("Cliente", "👤", _order!["users"]?["name"] ?? "Cliente", _order!["delivery_address"] ?? "", _order!["users"]?["phone"], _order!["delivery_address"],
          lat: (_order!["delivery_lat"] as num?)?.toDouble(),
          lng: (_order!["delivery_lng"] as num?)?.toDouble(),
          reference: _order!["delivery_reference"] as String?,
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
              const Text("Total del pedido", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text("\$${total.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.accent)),
            ]),
            if (riderFee > 0) ...[
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Row(children: [
                  Icon(Icons.monetization_on_outlined, size: 16, color: AppColors.success),
                  SizedBox(width: 4),
                  Text("Tu ganancia", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
                Text("\$${riderFee.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.success)),
              ]),
            ],
            final tipAmount = (_order!["tip_amount"] as num?)?.toDouble() ?? 0;
            if (tipAmount > 0) ...[
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Row(children: [
                  Icon(Icons.card_giftcard, size: 16, color: AppColors.warning),
                  SizedBox(width: 4),
                  Text("🎁 Propina", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
                Text("+\$${tipAmount.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.warning)),
              ]),
            ],
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showIncidentDialog(),
              icon: const Icon(Icons.warning_amber_rounded, size: 18),
              label: const Text("Reportar incidente", style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Acción: Recogí el pedido (solo assigned)
        if (status == "assigned") ...[
          ElevatedButton.icon(
            onPressed: () => _updateStatus("picked_up"),
            icon: const Icon(Icons.shopping_bag),
              label: Text(l10n.orderConfirmPickup),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 10),
          // Problemas en la tienda
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.warning.withOpacity(0.2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Problemas en la tienda", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => _showStoreClosedDialog(),
                  icon: const Icon(Icons.store_outlined, size: 16),
                  label: const Text("Tienda cerrada", style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning, side: const BorderSide(color: AppColors.warning), minimumSize: const Size(0, 42)),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => _showDelayDialog(),
                  icon: const Icon(Icons.hourglass_empty, size: 16),
                  label: const Text("Avisar demora", style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.info, side: const BorderSide(color: AppColors.info), minimumSize: const Size(0, 42)),
                )),
              ]),
            ]),
          ),
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
              Row(children: [
                const Icon(Icons.lock_outline, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Text(l10n.orderConfirmDelivery, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.success)),
              ]),
              const SizedBox(height: 4),
              Text(l10n.orderCodeHint, style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
              const SizedBox(height: 12),
              if (!_codeLocked) ...[
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
                if (_codeAttempts > 0) ...[
                  const SizedBox(height: 6),
                  Text(l10n.t(l10n.orderCodeAttempts, {'n': '$_codeAttempts'}), style: TextStyle(fontSize: 11, color: AppColors.error.withOpacity(0.8))),
                ],
              ] else ...[
                // Verificación alternativa tras 3 intentos fallidos
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.warning.withOpacity(0.3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text("Verificación alternativa", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning, fontSize: 13))),
                    ]),
                    const SizedBox(height: 8),
                    const Text("El cliente no puede verificar su identidad con el código. Confirma bajo tu responsabilidad.", style: TextStyle(color: AppColors.textLight, fontSize: 12)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _deliveryLoading ? null : _confirmDeliveryWithoutCode,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(l10n.orderCodeAlternative),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, minimumSize: const Size(0, 46)),
                      ),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          // SOS — Cliente agresivo
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showSosDialog(),
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: const Text("Cliente agresivo — Pedir ayuda", style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade400, width: 1.5),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
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
          // Toggle navegación por voz
          if (_voiceNav != null && (_routeKm ?? 0) > 0)
            IconButton(
              icon: Icon(_voiceNavEnabled ? Icons.volume_up : Icons.volume_off, size: 20),
              color: _voiceNavEnabled ? AppColors.accent : AppColors.textLight,
              tooltip: _voiceNavEnabled ? 'Navegación por voz activada' : 'Activar navegación por voz',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () async {
                if (_voiceNavEnabled) {
                  _voiceNav!.stopNavigation();
                  setState(() => _voiceNavEnabled = false);
                } else if (_voiceNav != null && _voiceSteps != null && _voiceSteps!.isNotEmpty) {
                  await _voiceNav!.startNavigation(_voiceSteps!);
                  setState(() => _voiceNavEnabled = true);
                }
              },
            ),
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
            // Guardar steps para navegación por voz
            if (r.steps != null && r.steps!.isNotEmpty) {
              _voiceSteps = r.steps;
              _voiceNav?.dispose();
              _voiceNav = VoiceNavigationService();
              _voiceNav!.initialize();
            }
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

  Widget _infoCard(String title, String emoji, String name, String subtitle, String? phone, String? address, {double? lat, double? lng, String? reference, String? logoUrl}) =>
    Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
      const SizedBox(height: 8),
      Row(children: [
        _storeAvatar(logoUrl, emoji, size: 40),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
        ])),
      ]),
      // Referencia de entrega (visible solo para el rider)
      if (reference != null && reference.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warning.withOpacity(0.35)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: AppColors.warning, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              reference,
              style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 13, height: 1.35),
            )),
          ]),
        ),
      ],
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

  // ── Tienda cerrada ──────────────────────────────────────────────────────

  Future<void> _showStoreClosedDialog() async {
    final note = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StoreClosedSheet(),
    );
    if (note != null && mounted) {
      setState(() => _deliveryLoading = true);
      try {
        final result = await _sb.rpc("rider_report_store_closed", params: {"p_order_id": widget.orderId, "p_note": note});
        if (mounted) {
          if (result == "ok") { _stopGps(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tienda cerrada reportada"), backgroundColor: AppColors.warning)); context.go("/dashboard"); }
          else { setState(() => _deliveryLoading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $result"), backgroundColor: AppColors.error)); }
        }
      } catch (e) {
        if (mounted) { setState(() => _deliveryLoading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error)); }
      }
    }
  }

  // ── Avisar demora ────────────────────────────────────────────────────────

  Future<void> _showDelayDialog() async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => const _DelayDialog());
    if (result != null && mounted) {
      try {
        await _sb.rpc("rider_notify_delay", params: {"p_order_id": widget.orderId, "p_minutes": result["minutes"] as int, "p_note": result["note"] as String});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cliente notificado de la demora"), backgroundColor: AppColors.info));
      } catch (_) {}
    }
  }

  // ── SOS (cliente agresivo) ───────────────────────────────────────────────

  Future<void> _showSosDialog() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), backgroundColor: Colors.red.shade50,
      title: const Row(children: [Icon(Icons.shield_outlined, color: Colors.red, size: 28), SizedBox(width: 10), Expanded(child: Text("Cliente agresivo?", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.red)))]),
      content: const Text("Esto enviara una alerta inmediata al equipo de soporte con tu ubicacion. Ellos te contactaran.\n\nNo estas solo. Si te sientes en peligro, prioriza tu seguridad y alejate del lugar.", style: TextStyle(fontSize: 14, height: 1.5)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)), child: const Text("Cancelar"))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.shield_outlined, size: 18), label: const Text("Enviar alerta", style: TextStyle(fontWeight: FontWeight.w800)), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size(0, 46)))),
      ])],
    ));
    if (confirm == true && mounted) {
      setState(() => _deliveryLoading = true);
      try {
        double? lat = _riderLat, lng = _riderLng;
        if (lat == null || lng == null) { try { final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)).timeout(const Duration(seconds: 5)); lat = pos.latitude; lng = pos.longitude; } catch (_) {} }
        final result = await _sb.rpc("rider_sos_alert", params: {"p_order_id": widget.orderId, "p_lat": lat ?? 0, "p_lng": lng ?? 0, "p_note": ""});
        if (mounted) { setState(() => _deliveryLoading = false); if (result == "ok") { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alerta enviada. Soporte te contactara."), backgroundColor: Colors.red, duration: Duration(seconds: 5))); } }
      } catch (e) { if (mounted) { setState(() => _deliveryLoading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error)); } }
    }
  }
}

  Widget _storeAvatar(String? logoUrl, String? emoji, {double size = 40}) {
    final fallback = Text(emoji ?? "🍽️", style: TextStyle(fontSize: size * 0.55));
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(logoUrl, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    }
    return SizedBox(width: size, height: size, child: Center(child: fallback));
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

// ── Bottom sheet para reporte de incidente ──────────────────────────────────
class _IncidentSheet extends StatefulWidget {
  const _IncidentSheet();
  @override
  State<_IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends State<_IncidentSheet> {
  final _noteCtrl = TextEditingController();
  String? _selected;

  static const _reasons = [
    {"id": "vehicle_breakdown", "emoji": "🚗", "label": "Vehículo averiado", "desc": "Pinchazo, motor, falla mecánica"},
    {"id": "traffic_accident",  "emoji": "💥", "label": "Accidente de tránsito", "desc": "Choque, colisión, despiste"},
    {"id": "medical_emergency", "emoji": "🏥", "label": "Emergencia médica", "desc": "Lesión, malestar repentino"},
    {"id": "stolen",            "emoji": "🚨", "label": "Pedido robado", "desc": "Asalto, hurto del pedido"},
    {"id": "damaged_order",     "emoji": "📦", "label": "Pedido dañado", "desc": "Se derramó, rompió o contaminó"},
    {"id": "other",             "emoji": "📝", "label": "Otro", "desc": "Especificar en la nota"},
  ];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20, right: 20, top: 20,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: const Color(0xFFDC2626).withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 26),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Reportar incidente", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text("¿Qué sucedió durante la entrega?", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
          ])),
        ]),
        const SizedBox(height: 16),

        // Opciones de incidente
        ..._reasons.map((r) {
          final isSelected = _selected == r["id"];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => setState(() => _selected = r["id"]),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFDC2626).withOpacity(0.08) : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFDC2626) : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(children: [
                  Text(r["emoji"]!, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r["label"]!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: isSelected ? const Color(0xFFDC2626) : AppColors.textDark)),
                    Text(r["desc"]!, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                  ])),
                  if (isSelected) const Icon(Icons.check_circle, color: Color(0xFFDC2626), size: 22),
                ]),
              ),
            ),
          );
        }),

        const SizedBox(height: 8),

        // Nota adicional
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: "Detalles adicionales (opcional)...",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.edit_note, size: 20),
          ),
        ),
        const SizedBox(height: 16),

        // Acciones
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            child: const Text("Cancelar"),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton.icon(
            onPressed: _selected == null ? null : () {
              Navigator.pop(context, {
                "reason": _selected!,
                "note": _noteCtrl.text.trim(),
              });
            },
            icon: const Icon(Icons.send, size: 18),
            label: const Text("Reportar", style: TextStyle(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              disabledBackgroundColor: AppColors.border,
              minimumSize: const Size(0, 48),
            ),
          )),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Tienda cerrada ──────────────────────────────────────────────────────────
class _StoreClosedSheet extends StatefulWidget {
  const _StoreClosedSheet();
  @override
  State<_StoreClosedSheet> createState() => _StoreClosedSheetState();
}

class _StoreClosedSheetState extends State<_StoreClosedSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.store_outlined, color: AppColors.warning, size: 24),
          SizedBox(width: 10),
          Expanded(child: Text("Tienda cerrada", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        const Text("El pedido sera cancelado y se notificara al cliente y al administrador.", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          maxLines: 2,
          decoration: InputDecoration(hintText: "Detalles (opcional)...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar"))),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text("Confirmar", style: TextStyle(color: Colors.white)),
          )),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Dialog: Avisar demora ──────────────────────────────────────────────────
class _DelayDialog extends StatefulWidget {
  const _DelayDialog();
  @override
  State<_DelayDialog> createState() => _DelayDialogState();
}

class _DelayDialogState extends State<_DelayDialog> {
  int _minutes = 10;
  final _noteCtrl = TextEditingController();

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.hourglass_empty, color: AppColors.info, size: 24),
        SizedBox(width: 10),
        Text("Avisar demora", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("El cliente recibira una notificacion con el tiempo estimado de espera.", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
        const SizedBox(height: 16),
        const Text("Tiempo estimado de demora:", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: _minutes > 5 ? () => setState(() => _minutes -= 5) : null, icon: const Icon(Icons.remove_circle_outline)),
          const SizedBox(width: 8),
          Text("$_minutes min", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.info)),
          const SizedBox(width: 8),
          IconButton(onPressed: _minutes < 60 ? () => setState(() => _minutes += 5) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(hintText: "Nota adicional (opcional)...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.edit_note, size: 20)),
        ),
      ]),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar"))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(context, {"minutes": _minutes, "note": _noteCtrl.text.trim()}),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.info),
            child: const Text("Notificar", style: TextStyle(color: Colors.white)),
          )),
        ]),
      ],
    );
  }
}
