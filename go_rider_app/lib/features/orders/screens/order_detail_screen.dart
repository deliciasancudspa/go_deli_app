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
  double? _riderLat, _riderLng;
  double? _routeKm;
  String? _routeEta;
  bool _hasOrderAhead = false;
  Timer? _gpsTimer;
  int _codeAttempts = 0;
  bool _codeLocked = false;
  final _sb = Supabase.instance.client;
  final _deliveryCodeCtrl = TextEditingController();

  // Voice navigation
  VoiceNavigationService? _voiceNav;
  bool _voiceNavEnabled = false;
  List<NavStep>? _voiceSteps;

  // Bottom sheet controller
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  static const double _minSheetSize = 0.15;  // collapsed: solo handle + status
  static const double _midSheetSize = 0.45;  // parcial: info cards visibles
  static const double _maxSheetSize = 0.85;  // expandido: todo visible

  bool get _isQueued => _hasOrderAhead && _order?["status"] == "assigned";
  RealtimeChannel? _orderChannel;
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
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final riderId = context.read<RiderProvider>().riderId;
      final o = await _sb.from("orders")
        .select("*, stores(name,emoji,logo_url,address,phone,lat,lng), users!client_id(name,phone), order_items(item_name,quantity,item_price)")
        .eq("id", widget.orderId)
        .single();
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

  // ── Acciones ─────────────────────────────────────────
  Future<void> _call(String? phone) async {
    if (phone == null) return;
    final uri = Uri.parse("tel:$phone");
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openMaps(String? address, {double? lat, double? lng}) async {
    if (address == null && lat == null) return;
    final q = (lat != null && lng != null) ? "$lat,$lng" : Uri.encodeComponent(address ?? "");
    if (q.isEmpty) return;
    final uri = Uri.parse("https://maps.google.com/?q=$q");
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _navigateTo(double lat, double lng) async {
    final uri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving");
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWaze(double lat, double lng) async {
    final uri = Uri.parse("https://waze.com/ul?ll=$lat,$lng&navigate=yes");
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showNavigationChooser(LatLng dest) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const Text("Navegar con...", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0xFF4285F4).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.map, color: Color(0xFF4285F4), size: 24),
              ),
              title: const Text("Google Maps", style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text("Indicaciones paso a paso", style: TextStyle(fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () {
                Navigator.pop(ctx);
                _navigateTo(dest.latitude, dest.longitude);
              },
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0xFF33CCFF).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.explore_outlined, color: Color(0xFF33CCFF), size: 24),
              ),
              title: const Text("Waze", style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text("Alertas de tráfico en tiempo real", style: TextStyle(fontSize: 12)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () {
                Navigator.pop(ctx);
                _openWaze(dest.latitude, dest.longitude);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _updateStatus(String newStatus) async {
    final rider = context.read<RiderProvider>();
    await rider.updateOrderStatus(widget.orderId, newStatus);
    if (newStatus == "delivered") _stopGps();
    await _load();
    if (newStatus == "delivered" && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.orderDeliveryConfirmed), backgroundColor: AppColors.success));
      context.go("/dashboard");
    }
  }

  Future<void> _showReturnDialog(String reason) async {
    final label = reason == "not_found" ? "Cliente no localizado" : "Cliente rechazó el pedido";
    final note = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReturnDialogSheet(label: label),
    );
    if (note != null && mounted) {
      await _processReturn(reason, note, label);
    }
  }

  Future<void> _showIncidentDialog() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context, isScrollControlled: true,
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
      double? lat, lng;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 5));
        lat = pos.latitude; lng = pos.longitude;
      } catch (_) { lat = _riderLat; lng = _riderLng; }
      if (lat == null || lng == null) {
        if (mounted) {
          setState(() => _deliveryLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No se pudo obtener tu ubicación. Intenta de nuevo."), backgroundColor: AppColors.error));
        }
        return;
      }
      final result = await _sb.rpc("rider_report_incident", params: {
        "p_order_id": widget.orderId, "p_reason": reason, "p_note": note,
        "p_lat": lat, "p_lng": lng,
      });
      if (result == "ok" && mounted) {
        _stopGps();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Incidente reportado. Soporte te contactará."), backgroundColor: AppColors.warning));
        context.go("/dashboard");
      } else {
        if (mounted) {
          setState(() => _deliveryLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $result"), backgroundColor: AppColors.error));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deliveryLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al reportar: $e"), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _processReturn(String reason, String note, String reasonLabel) async {
    final riderName = context.read<RiderProvider>().riderName;
    final codigo = widget.orderId.substring(0, 8).toUpperCase();
    final storeId = _order?["store_id"] as String?;
    try {
      final noteText = note.isEmpty ? reasonLabel : note;
      await _sb.from("orders").update({
        "status": "returned", "return_reason": reason,
        "return_note": note.isEmpty ? null : note,
        "returned_at": ChileTime.now().toIso8601String(),
      }).eq("id", widget.orderId);
      if (storeId != null) {
        await _sb.from("notifications").insert({
          "target": storeId, "title": "Pedido devuelto",
          "message": "El pedido #$codigo fue devuelto. Nota: $noteText", "emoji": "↩️",
        });
      }
      await _sb.from("notifications").insert({
        "target": "admin", "title": "Pedido devuelto",
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
              const SnackBar(content: Text("Demasiados intentos. Usa la verificación alternativa."), backgroundColor: AppColors.warning, duration: Duration(seconds: 4)));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Código incorrecto. ${3 - _codeAttempts} intento(s) restante(s)."), backgroundColor: AppColors.error));
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _deliveryLoading = false);
    }
  }

  Future<void> _confirmDeliveryWithoutCode() async {
    setState(() => _deliveryLoading = true);
    try {
      final result = await _sb.rpc("rider_confirm_delivery_override", params: {"p_order_id": widget.orderId});
      if (result == "ok" && mounted) {
        _stopGps();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Entrega confirmada (verificación alternativa)"), backgroundColor: AppColors.warning));
        context.go("/dashboard");
      } else {
        if (mounted) {
          setState(() => _deliveryLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $result"), backgroundColor: AppColors.error));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deliveryLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error));
      }
    }
  }

  // ── Store closed / Delay / SOS dialogs ─────────────
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

  Future<void> _showDelayDialog() async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => const _DelayDialog());
    if (result != null && mounted) {
      try {
        await _sb.rpc("rider_notify_delay", params: {"p_order_id": widget.orderId, "p_minutes": result["minutes"] as int, "p_note": result["note"] as String});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cliente notificado de la demora"), backgroundColor: AppColors.info));
      } catch (_) {}
    }
  }

  Future<void> _showSosDialog() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), backgroundColor: Colors.red.shade50,
      title: const Row(children: [Icon(Icons.shield_outlined, color: Colors.red, size: 28), SizedBox(width: 10), Expanded(child: Text("Cliente agresivo?", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.red)))]),
      content: const Text("Esto enviará una alerta inmediata al equipo de soporte con tu ubicación. Ellos te contactarán.\n\nNo estás solo. Si te sientes en peligro, prioriza tu seguridad y aléjate del lugar.", style: TextStyle(fontSize: 14, height: 1.5)),
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
        if (mounted) { setState(() => _deliveryLoading = false); if (result == "ok") { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alerta enviada. Soporte te contactará."), backgroundColor: Colors.red, duration: Duration(seconds: 5))); } }
      } catch (e) { if (mounted) { setState(() => _deliveryLoading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error)); } }
    }
  }

  String _fmt(double n) => "\$${n.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  // ══════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    final l10n = AppLocalizations.of(context)!;
    final tc = ThemeColors.of(context);
    if (_order == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(l10n.orderNotFound)));

    final status = _order!["status"] as String;
    final items = (_order!["order_items"] as List?) ?? [];
    final total = (_order!["total"] as num?)?.toDouble() ?? 0;
    final riderFee = (_order!["rider_fee"] as num?)?.toDouble() ?? 0;
    final tipAmount = (_order!["tip_amount"] as num?)?.toDouble() ?? 0;
    final payMethod = _order!["payment_method"] as String?;
    final pickupCode = _order!["pickup_code"] as String?;
    final store = _order!["stores"] as Map?;
    final storeLat = (store?["lat"] as num?)?.toDouble();
    final storeLng = (store?["lng"] as num?)?.toDouble();
    final clientLat = (_order!["delivery_lat"] as num?)?.toDouble();
    final clientLng = (_order!["delivery_lng"] as num?)?.toDouble();

    // Determine destination based on status
    LatLng? destLatLng;
    String destLabel = "";
    double destHue = BitmapDescriptor.hueViolet;
    if (status == "assigned" && storeLat != null && storeLng != null) {
      destLatLng = LatLng(storeLat, storeLng);
      destLabel = store?["name"] as String? ?? "Tienda";
      destHue = BitmapDescriptor.hueOrange;
    } else if ((status == "picked_up" || status == "on_the_way") && clientLat != null && clientLng != null) {
      destLatLng = LatLng(clientLat, clientLng);
      destLabel = "Cliente";
      destHue = BitmapDescriptor.hueViolet;
    }

    final origin = (_riderLat != null && _riderLng != null) ? LatLng(_riderLat!, _riderLng!) : null;

    return Scaffold(
      body: Stack(children: [
        // ════════════════ MAPA FULL-SCREEN ════════════════
        if (destLatLng != null)
          Positioned.fill(
            child: RouteMapView(
              origin: _isQueued ? null : origin,
              destination: destLatLng,
              originLabel: "Tú",
              destinationLabel: destLabel,
              destinationHue: destHue,
              fullScreen: true,
              onRouteReady: (r) {
                if (mounted) setState(() { _routeKm = r.distanceKm; _routeEta = r.durationText; });
                if (r.steps != null && r.steps!.isNotEmpty) {
                  _voiceSteps = r.steps;
                  _voiceNav?.dispose();
                  _voiceNav = VoiceNavigationService();
                  _voiceNav!.initialize();
                  // Auto-start voice navigation — rider can disable manually
                  _voiceNav!.startNavigation(r.steps!).then((_) {
                    if (mounted) setState(() => _voiceNavEnabled = true);
                  });
                }
              },
              // Top overlay + nav buttons inside the same Stack as the map
              // so they render on top of the Google Maps platform view (Android)
              floatingChild: destLatLng != null
                  ? Stack(children: [
                      // ── Top overlay: back button, status pill, GPS ──
                      _topOverlay(status),
                      // ── Bottom nav FABs ──
                      Positioned(
                        bottom: 16, right: 16,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          // Recenter button
                          FloatingActionButton.small(
                            heroTag: "recenter",
                            backgroundColor: Colors.white,
                            onPressed: () {}, // map auto-fits via RouteMapView
                            child: const Icon(Icons.my_location, color: AppColors.primary),
                          ),
                          const SizedBox(height: 10),
                          // Google Maps / Waze navigation
                          FloatingActionButton(
                            heroTag: "navigate",
                            backgroundColor: AppColors.accent,
                            onPressed: () { if (destLatLng != null) _showNavigationChooser(destLatLng!); },
                            child: const Icon(Icons.navigation, color: Colors.white, size: 28),
                          ),
                        ]),
                      ),
                    ])
                  : null,
            ),
          )
        else
          // No map available yet — show gradient background
          Container(color: AppColors.primary),

        // ════════════════ BOTTOM DRAGGABLE SHEET ════════════════
        // Rendered BEFORE top overlay so it doesn't block back-button taps
        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: _midSheetSize,
          minChildSize: _minSheetSize,
          maxChildSize: _maxSheetSize,
          snap: true,
          snapSizes: [_minSheetSize, _midSheetSize, _maxSheetSize],
          builder: (ctx, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: tc.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // ── Handle ──
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: tc.border, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Status header (compact) ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _sheetStatusHeader(status, l10n),
                  ),
                  const SizedBox(height: 12),

                  // ── Pickup code ──
                  if (pickupCode != null && status == "assigned")
                    _pickupCodeCard(pickupCode),

                  // ── Store info ──
                  _infoCard("Restaurante", store?["emoji"] ?? "🍽️", store?["name"] ?? "", store?["address"] ?? "", store?["phone"], logoUrl: store?["logo_url"] as String?),
                  const SizedBox(height: 10),

                  // ── Client info ──
                  _infoCard("Cliente", "👤", _order!["users"]?["name"] ?? "Cliente", _order!["delivery_address"] ?? "", _order!["users"]?["phone"],
                    reference: _order!["delivery_reference"] as String?,
                  ),
                  const SizedBox(height: 10),

                  // ── Products ──
                  _productsCard(items, total, riderFee, tipAmount, payMethod),
                  const SizedBox(height: 12),

                  // ── Chat (only after pickup — rider and client need to coordinate) ──
                  if (status == "picked_up" || status == "on_the_way") ...[
                    _actionButton(Icons.chat_bubble_outline, "Chat con el cliente", AppColors.accent,
                        onTap: () => context.push("/chat/${widget.orderId}")),
                    const SizedBox(height: 6),
                  ],

                  // ── Return / Incident (picked_up / on_the_way) ──
                  if (status == "picked_up" || status == "on_the_way") ...[
                    Row(children: [
                      Expanded(child: _actionButton(Icons.person_off_outlined, "No localizado", AppColors.warning, onTap: () => _showReturnDialog("not_found"), compact: true)),
                      const SizedBox(width: 8),
                      Expanded(child: _actionButton(Icons.block, "Rechazado", AppColors.error, onTap: () => _showReturnDialog("rejected"), compact: true)),
                    ]),
                    const SizedBox(height: 6),
                    _actionButton(Icons.warning_amber_rounded, "Reportar incidente", const Color(0xFFDC2626), onTap: _showIncidentDialog),
                    const SizedBox(height: 6),
                  ],

                  // ── Waiting for store pickup code (assigned) ──
                  if (status == "assigned") ...[
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.info.withOpacity(0.3)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline, color: AppColors.info, size: 18),
                        SizedBox(width: 10),
                        Expanded(child: Text(
                          "Espera a que la tienda ingrese el código de retiro.\nEl pedido se confirmará automáticamente.",
                          style: TextStyle(color: AppColors.info, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    // Store problems
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.warning.withOpacity(0.2))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text("Problemas en la tienda", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight)),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: _actionButton(Icons.store_outlined, "Tienda cerrada", AppColors.warning, onTap: _showStoreClosedDialog, compact: true, mini: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _actionButton(Icons.hourglass_empty, "Avisar demora", AppColors.info, onTap: _showDelayDialog, compact: true, mini: true)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // ── On the way (picked_up) ──
                  if (status == "picked_up")
                    _bigButton("En camino al cliente", AppColors.accent, Icons.delivery_dining, onTap: () => _updateStatus("on_the_way")),

                  // ── Delivery code (on_the_way) ──
                  if (status == "on_the_way") ...[
                    _deliveryCodeSection(l10n),
                    const SizedBox(height: 6),
                    _actionButton(Icons.shield_outlined, "Cliente agresivo — Pedir ayuda", Colors.red.shade700, onTap: _showSosDialog, borderWidth: 1.5),
                    const SizedBox(height: 6),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        ),

        // ════════════════ TOP OVERLAY ════════════════
        // Rendered AFTER the DraggableScrollableSheet so it's always tappable
        // Route info bar
        if (_routeKm != null && !_isQueued)
          Positioned(
            top: 96, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)]),
              child: Row(children: [
                const Icon(Icons.route_outlined, color: AppColors.accent, size: 18),
                const SizedBox(width: 8),
                Text("${_routeKm!.toStringAsFixed(1)} km", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                if (_routeEta != null) ...[
                  const SizedBox(width: 8),
                  Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.textLight, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(_routeEta!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textMedium)),
                ],
                const Spacer(),
                if (_voiceNav != null)
                  GestureDetector(
                    onTap: () async {
                      if (_voiceNavEnabled) {
                        _voiceNav!.stopNavigation();
                        setState(() => _voiceNavEnabled = false);
                      } else if (_voiceSteps != null && _voiceSteps!.isNotEmpty) {
                        await _voiceNav!.startNavigation(_voiceSteps!);
                        setState(() => _voiceNavEnabled = true);
                      }
                    },
                    child: Icon(_voiceNavEnabled ? Icons.volume_up : Icons.volume_off,
                        color: _voiceNavEnabled ? AppColors.accent : AppColors.textLight, size: 22),
                  ),
              ]),
            ),
          ),

        // Queued banner
        if (_isQueued)
          Positioned(
            top: 96, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.95),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)],
              ),
              child: const Row(children: [
                Icon(Icons.schedule, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Expanded(child: Text("Pedido en cola. Termina tu entrega en curso primero.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
              ]),
            ),
          ),

        // Back button, status pill & GPS — only shown when there's NO map
        // (when map is visible, they're rendered inside RouteMapView.floatingChild
        //  to stay above the Google Maps platform view on Android)
        if (destLatLng == null) _topOverlay(status),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SHEET WIDGETS
  // ══════════════════════════════════════════════════════════════════════════════

  /// Top overlay: back button + status pill + GPS indicator.
  /// Used both inside RouteMapView.floatingChild (map visible) and directly
  /// in the outer Stack (no map), so it's always on top and tappable.
  Widget _topOverlay(String status) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)]),
                child: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.primary),
              ),
            ),
            const Spacer(),
            _statusPill(status),
            const Spacer(),
            if (_gpsActive)
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.9), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)]),
                child: const Icon(Icons.gps_fixed, color: Colors.white, size: 20),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    final labels = {"assigned": "Recoger pedido", "picked_up": "Pedido recogido", "on_the_way": "En camino", "delivered": "Entregado", "cancelled": "Cancelado"};
    final colors = {"assigned": AppColors.warning, "picked_up": AppColors.info, "on_the_way": AppColors.accent, "delivered": AppColors.success, "cancelled": AppColors.error};
    final emojis = {"assigned": "🛵", "picked_up": "📦", "on_the_way": "🚀", "delivered": "✅", "cancelled": "❌"};
    final color = colors[status] ?? AppColors.textLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 10)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emojis[status] ?? "⏳", style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text(labels[status] ?? status, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _sheetStatusHeader(String status, AppLocalizations l10n) {
    return Row(children: [
      Text("Pedido #${widget.orderId.substring(0, 8).toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const Spacer(),
      if (_gpsActive) ...[
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(l10n.gps, style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w700)),
      ],
    ]);
  }

  Widget _pickupCodeCard(String code) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppColors.accent, Color(0xFFE55D2B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(children: [
      const Text("Código de retiro", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 6),
      Text(code, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 8)),
      const SizedBox(height: 4),
      const Text("Muestra este código al restaurante", style: TextStyle(color: Colors.white60, fontSize: 11)),
    ]),
  );

  Widget _infoCard(String label, String emoji, String name, String subtitle, String? phone, {String? logoUrl, String? reference}) {
    final tc = ThemeColors.of(context);
    return Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: tc.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: tc.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tc.textLight)),
      const SizedBox(height: 8),
      Row(children: [
        _storeAvatar(logoUrl, emoji, size: 36),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: tc.textDark)),
          if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(color: tc.textLight, fontSize: 11)),
        ])),
        if (phone != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _call(phone),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.phone, color: AppColors.success, size: 18),
            ),
          ),
        ],
      ]),
      if (reference != null && reference.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.warning.withOpacity(0.35))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: AppColors.warning, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(reference, style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 12, height: 1.35))),
          ]),
        ),
      ],
    ]),
  );
  }

  Widget _productsCard(List items, double total, double riderFee, double tipAmount, String? payMethod) {
    final tc = ThemeColors.of(context);
    return Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: tc.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: tc.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Productos", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: tc.textDark)),
      const SizedBox(height: 10),
      ...items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text("${item["quantity"]}× ", style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent)),
          Expanded(child: Text(item["item_name"] ?? "", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: tc.textDark))),
          Text("\$${((item["item_price"] as num?) ?? 0).toStringAsFixed(0)}", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: tc.textDark)),
        ]),
      )),
      const Divider(),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text("Total", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: tc.textDark)),
        Text(_fmt(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accent)),
      ]),
      if (riderFee > 0) ...[
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.monetization_on_outlined, size: 15, color: AppColors.success),
            const SizedBox(width: 4),
            Text("Tu ganancia", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: tc.textDark)),
          ]),
          Text(_fmt(riderFee), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.success)),
        ]),
      ],
      if (tipAmount > 0) ...[
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.card_giftcard, size: 15, color: AppColors.warning),
            const SizedBox(width: 4),
            Text("🎁 Propina", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: tc.textDark)),
          ]),
          Text("+${_fmt(tipAmount)}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.warning)),
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
            Text("Cobra ${_fmt(total)} en efectivo", style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
      ],
    ]),
  );
  }

  Widget _actionButton(IconData icon, String label, Color color, {VoidCallback? onTap, bool compact = false, bool mini = false, double borderWidth = 1}) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color, width: borderWidth),
      minimumSize: compact ? const Size(0, 42) : (mini ? const Size(0, 36) : const Size(double.infinity, 44)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: TextStyle(fontSize: mini ? 11 : 13, fontWeight: FontWeight.w700),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: mini ? 14 : 16), label: Text(label), style: style),
    );
  }

  Widget _bigButton(String label, Color color, IconData icon, {VoidCallback? onTap}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      style: ElevatedButton.styleFrom(backgroundColor: color, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
  );

  Widget _deliveryCodeSection(AppLocalizations l10n) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.success.withOpacity(0.4), width: 2)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.lock_outline, color: AppColors.success, size: 18),
        const SizedBox(width: 8),
        Text(l10n.orderConfirmDelivery, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.success)),
      ]),
      const SizedBox(height: 4),
      Text(l10n.orderCodeHint, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
      const SizedBox(height: 10),
      if (!_codeLocked) ...[
        Row(children: [
          Expanded(
            child: TextField(
              controller: _deliveryCodeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 6),
              decoration: const InputDecoration(hintText: "0000", counterText: "", contentPadding: EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _deliveryLoading ? null : _confirmDelivery,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size(90, 48)),
            child: _deliveryLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Confirmar"),
          ),
        ]),
        if (_codeAttempts > 0) ...[
          const SizedBox(height: 4),
          Text("${_codeAttempts} intento(s) fallido(s)", style: TextStyle(fontSize: 11, color: AppColors.error.withOpacity(0.8))),
        ],
      ] else ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.warning.withOpacity(0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 16),
              SizedBox(width: 6),
              Expanded(child: Text("Verificación alternativa", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning, fontSize: 12))),
            ]),
            const SizedBox(height: 6),
            const Text("El cliente no puede verificar su identidad. Confirma bajo tu responsabilidad.", style: TextStyle(color: AppColors.textLight, fontSize: 11)),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _deliveryLoading ? null : _confirmDeliveryWithoutCode,
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: Text(l10n.orderCodeAlternative, style: const TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, minimumSize: const Size(0, 42)),
            )),
          ]),
        ),
      ],
    ]),
  );

  static Widget _storeAvatar(String? logoUrl, String? emoji, {double size = 36}) {
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// DIALOGS & SHEETS (preserved from original)
// ═══════════════════════════════════════════════════════════════════════════════

class _ReturnDialogSheet extends StatefulWidget {
  final String label;
  const _ReturnDialogSheet({required this.label});
  @override
  State<_ReturnDialogSheet> createState() => _ReturnDialogSheetState();
}

class _ReturnDialogSheetState extends State<_ReturnDialogSheet> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Devolver pedido", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(widget.label, style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
        const SizedBox(height: 16),
        TextField(controller: _ctrl, maxLines: 3, decoration: InputDecoration(hintText: "Nota de devolución (opcional)...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar"))),
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
  void dispose() { _noteCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 20, right: 20, top: 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFDC2626).withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 26)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Reportar incidente", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text("¿Qué sucedió durante la entrega?", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
          ])),
        ]),
        const SizedBox(height: 16),
        ..._reasons.map((r) {
          final isSelected = _selected == r["id"];
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: InkWell(
            onTap: () => setState(() => _selected = r["id"]),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: isSelected ? const Color(0xFFDC2626).withOpacity(0.08) : AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: isSelected ? const Color(0xFFDC2626) : AppColors.border, width: isSelected ? 2 : 1)),
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
          ));
        }),
        const SizedBox(height: 8),
        TextField(controller: _noteCtrl, maxLines: 2, decoration: InputDecoration(hintText: "Detalles adicionales (opcional)...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.edit_note, size: 20))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), child: const Text("Cancelar"))),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton.icon(onPressed: _selected == null ? null : () { Navigator.pop(context, {"reason": _selected!, "note": _noteCtrl.text.trim()}); }, icon: const Icon(Icons.send, size: 18), label: const Text("Reportar", style: TextStyle(fontWeight: FontWeight.w800)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), disabledBackgroundColor: AppColors.border, minimumSize: const Size(0, 48)))),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }
}

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
        const Row(children: [Icon(Icons.store_outlined, color: AppColors.warning, size: 24), SizedBox(width: 10), Expanded(child: Text("Tienda cerrada", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)))]),
        const SizedBox(height: 8),
        const Text("El pedido será cancelado y se notificará al cliente y al administrador.", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
        const SizedBox(height: 16),
        TextField(controller: _ctrl, maxLines: 2, decoration: InputDecoration(hintText: "Detalles (opcional)...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar"))),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context, _ctrl.text.trim()), style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning), child: const Text("Confirmar", style: TextStyle(color: Colors.white)))),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }
}

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
      title: const Row(children: [Icon(Icons.hourglass_empty, color: AppColors.info, size: 24), SizedBox(width: 10), Text("Avisar demora", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("El cliente recibirá una notificación con el tiempo estimado de espera.", style: TextStyle(color: AppColors.textLight, fontSize: 13)),
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
        TextField(controller: _noteCtrl, maxLines: 2, decoration: InputDecoration(hintText: "Nota adicional (opcional)...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.edit_note, size: 20))),
      ]),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar"))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context, {"minutes": _minutes, "note": _noteCtrl.text.trim()}), style: ElevatedButton.styleFrom(backgroundColor: AppColors.info), child: const Text("Notificar", style: TextStyle(color: Colors.white)))),
      ])],
    );
  }
}
