import "package:flutter/material.dart";
import "dart:async";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/theme/app_theme.dart";

class MapScreen extends StatefulWidget {
  final String orderId;
  const MapScreen({super.key, required this.orderId});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapCtrl;
  Map<String, dynamic>? _order;
  double? _riderLat, _riderLng;
  String? _delivererId;
  bool _loading = true;
  bool _following = true;
  Timer? _pollTimer;
  final _sb = Supabase.instance.client;

  static const _defaultPos = LatLng(-41.8695, -73.8303); // Ancud

  String get _riderName => _order?["deliverers"]?["users"]?["name"] ?? "Repartidor";
  String? get _riderPhone => _order?["deliverers"]?["users"]?["phone"] as String?;
  bool get _hasLocation => _riderLat != null && _riderLng != null;

  Set<Marker> get _markers {
    if (!_hasLocation) return {};
    return {
      Marker(
        markerId: const MarkerId("rider"),
        position: LatLng(_riderLat!, _riderLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(title: _riderName, snippet: "Tu repartidor"),
      ),
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final order = await _sb.from("orders")
        .select("*, stores(name,emoji,address), deliverers(id,current_lat,current_lng,users(name,phone))")
        .eq("id", widget.orderId)
        .single();
      if (!mounted) return;
      final d = order["deliverers"];
      setState(() {
        _order = order;
        _delivererId = d?["id"] as String?;
        _riderLat = (d?["current_lat"] as num?)?.toDouble();
        _riderLng = (d?["current_lng"] as num?)?.toDouble();
        _loading = false;
      });
      if (_delivererId != null) _subscribeRider();
      if (_hasLocation && _following) _animateTo(_riderLat!, _riderLng!);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRider() {
    _sb.channel("rider_map_${widget.orderId}")
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: "public",
        table: "deliverers",
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "id", value: _delivererId!),
        callback: (payload) {
          final r = payload.newRecord;
          if (!mounted || r["current_lat"] == null) return;
          setState(() {
            _riderLat = (r["current_lat"] as num).toDouble();
            _riderLng = (r["current_lng"] as num).toDouble();
          });
          if (_following) _animateTo(_riderLat!, _riderLng!);
        },
      ).subscribe();

    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_delivererId == null || !mounted) return;
      try {
        final d = await _sb.from("deliverers")
          .select("current_lat,current_lng")
          .eq("id", _delivererId!)
          .single();
        if (mounted && d["current_lat"] != null) {
          setState(() {
            _riderLat = (d["current_lat"] as num).toDouble();
            _riderLng = (d["current_lng"] as num).toDouble();
          });
          if (_following) _animateTo(_riderLat!, _riderLng!);
        }
      } catch (_) {}
    });
  }

  void _animateTo(double lat, double lng) {
    _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: LatLng(lat, lng), zoom: 15),
    ));
  }

  Future<void> _openGoogleMaps() async {
    String q = _hasLocation
      ? "$_riderLat,$_riderLng"
      : Uri.encodeComponent(_order?["delivery_address"] ?? "");
    if (q.isEmpty) return;
    final uri = Uri.parse("https://maps.google.com/?q=$q");
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }

    final status = _order?["status"] as String? ?? "";
    final initialPos = _hasLocation ? LatLng(_riderLat!, _riderLng!) : _defaultPos;

    final statusLabels = {
      "assigned":  "🛵 Repartidor en camino al restaurante",
      "picked_up": "📦 Repartidor recogió tu pedido",
      "on_the_way": "🚀 Tu pedido está en camino",
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text("Seguimiento en vivo"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          if (_hasLocation) Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              const Text("En vivo", style: TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
        ],
      ),
      body: Stack(children: [
        // Mapa principal
        GoogleMap(
          initialCameraPosition: CameraPosition(target: initialPos, zoom: 15),
          onMapCreated: (ctrl) {
            _mapCtrl = ctrl;
            if (_hasLocation) _animateTo(_riderLat!, _riderLng!);
          },
          markers: _markers,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onCameraMoveStarted: () { if (_following) setState(() => _following = false); },
        ),

        // Botón "Seguir" cuando el usuario mueve el mapa manualmente
        if (!_following && _hasLocation) Positioned(
          top: 16, right: 16,
          child: FloatingActionButton.small(
            onPressed: () {
              setState(() => _following = true);
              _animateTo(_riderLat!, _riderLng!);
            },
            backgroundColor: Colors.white,
            child: const Icon(Icons.my_location, color: AppColors.primary),
          ),
        ),

        // Panel inferior
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, -3))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),

              // Info repartidor
              Row(children: [
                CircleAvatar(radius: 22,
                  backgroundColor: AppColors.accent.withOpacity(0.15),
                  child: const Text("🛵", style: TextStyle(fontSize: 20))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_riderName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 7, height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: _hasLocation ? AppColors.success : AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      _hasLocation ? "Ubicación en tiempo real" : "Obteniendo ubicación...",
                      style: TextStyle(
                        color: _hasLocation ? AppColors.success : AppColors.warning,
                        fontSize: 12, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ])),
                if (_riderPhone != null) IconButton(
                  onPressed: () async {
                    final uri = Uri.parse("tel:$_riderPhone");
                    if (await canLaunchUrl(uri)) launchUrl(uri);
                  },
                  icon: const Icon(Icons.phone, color: AppColors.primary),
                  style: IconButton.styleFrom(backgroundColor: AppColors.primary.withOpacity(0.1)),
                ),
              ]),

              // Estado del pedido
              if (statusLabels[status] != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(statusLabels[status]!, textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 13)),
                ),
              ],

              // Dirección de entrega
              if (_order?["delivery_address"] != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.location_on_outlined, color: AppColors.textLight, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_order!["delivery_address"],
                    style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openGoogleMaps,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text("Abrir en Google Maps"),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
