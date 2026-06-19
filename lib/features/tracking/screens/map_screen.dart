// ⚠️ DEPRECATED — Este archivo es código muerto.
// El mapa real se usa desde features/map/screens/map_screen.dart (con Google Maps).
// app_routes.dart enruta /map/:orderId a features/map/, no a este archivo.
// Conservado solo como referencia; eliminar en próxima limpieza.

import "package:flutter/material.dart";
import "dart:async";
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
  Map<String, dynamic>? _order;
  double? _riderLat;
  double? _riderLng;
  String? _delivererId;
  bool _loading = true;
  Timer? _pollTimer;
  final _sb = Supabase.instance.client;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _pollTimer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    try {
      final order = await _sb.from("orders")
        .select("*, stores(name,emoji,address), deliverers(id,current_lat,current_lng,users(name,phone))")
        .eq("id", widget.orderId)
        .single();
      if (!mounted) return;
      final deliverer = order["deliverers"];
      setState(() {
        _order = order;
        _delivererId = deliverer?["id"] as String?;
        _riderLat = (deliverer?["current_lat"] as num?)?.toDouble();
        _riderLng = (deliverer?["current_lng"] as num?)?.toDouble();
        _loading = false;
      });
      if (_delivererId != null) _subscribeRider();
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _subscribeRider() {
    // Realtime: se actualiza cada vez que el rider envía su GPS
    _sb.channel("rider_location_${_delivererId}")
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: "public",
        table: "deliverers",
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "id", value: _delivererId!),
        callback: (payload) {
          final newRow = payload.newRecord;
          if (mounted && newRow["current_lat"] != null) {
            setState(() {
              _riderLat = (newRow["current_lat"] as num).toDouble();
              _riderLng = (newRow["current_lng"] as num).toDouble();
            });
          }
        },
      ).subscribe();

    // Polling cada 10 seg como respaldo
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_delivererId == null) return;
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
        }
      } catch (_) {}
    });
  }

  Future<void> _openGoogleMaps() async {
    String query = "";
    if (_riderLat != null) {
      query = "$_riderLat,$_riderLng";
    } else if (_order?["delivery_address"] != null) {
      query = Uri.encodeComponent(_order!["delivery_address"]);
    }
    if (query.isEmpty) return;
    final uri = Uri.parse("https://maps.google.com/?q=$query");
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));

    final deliverer = _order?["deliverers"];
    final riderName = deliverer?["users"]?["name"] ?? "Repartidor";
    final riderPhone = deliverer?["users"]?["phone"];
    final hasLocation = _riderLat != null && _riderLng != null;
    final status = _order?["status"] as String? ?? "";

    final statusLabels = {
      "assigned":  "🛵 Repartidor en camino al restaurante",
      "picked_up": "📦 Repartidor recogió tu pedido",
      "on_the_way":"🚀 Tu pedido está en camino",
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Seguimiento en vivo"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          if (hasLocation) Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              const Text("En vivo", style: TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Estado actual
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              const Text("🛵", style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(statusLabels[status] ?? status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(riderName, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 20),

          // Info repartidor + ubicación
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Column(children: [
              Row(children: [
                CircleAvatar(radius: 24, backgroundColor: AppColors.accent.withOpacity(0.15), child: const Text("🛵", style: TextStyle(fontSize: 22))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(riderName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 8, height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: hasLocation ? AppColors.success : AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      hasLocation ? "Ubicación en tiempo real" : "Obteniendo ubicación...",
                      style: TextStyle(color: hasLocation ? AppColors.success : AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ])),
                if (riderPhone != null) IconButton(
                  onPressed: () async {
                    final uri = Uri.parse("tel:$riderPhone");
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                  icon: const Icon(Icons.phone, color: AppColors.primary),
                  style: IconButton.styleFrom(backgroundColor: AppColors.primary.withOpacity(0.1)),
                ),
              ]),

              if (hasLocation) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.07), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.my_location, color: AppColors.success, size: 18),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("Posición actual del repartidor", style: TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
                      Text("${_riderLat!.toStringAsFixed(5)}, ${_riderLng!.toStringAsFixed(5)}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    ]),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),

          // Botón Google Maps
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: hasLocation ? _openGoogleMaps : null,
              icon: const Icon(Icons.map_outlined),
              label: Text(hasLocation ? "Abrir ubicación en Google Maps" : "Esperando ubicación del repartidor"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Dirección de entrega
          if (_order?["delivery_address"] != null) Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Tu dirección de entrega", style: TextStyle(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_order!["delivery_address"], style: const TextStyle(fontWeight: FontWeight.w700)),
              ])),
            ]),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}
