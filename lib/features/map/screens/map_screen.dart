import "package:flutter/material.dart";
import "package:flutter/widgets.dart";
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
  bool _loading = true;
  final _sb = Supabase.instance.client;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final order = await _sb.from("orders")
        .select("*, stores(name,emoji,address), deliverers(current_lat,current_lng,users(name,phone))")
        .eq("id", widget.orderId)
        .single();
      if (mounted) setState(() { _order = order; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _openGoogleMaps() async {
    final deliverer = _order?["deliverers"];
    String query = "";
    if (deliverer?["current_lat"] != null) {
      query = "${deliverer["current_lat"]},${deliverer["current_lng"]}";
    } else if (_order?["delivery_address"] != null) {
      query = Uri.encodeComponent(_order!["delivery_address"]);
    }
    final uri = Uri.parse("https://maps.google.com/?q=$query");
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    final deliverer = _order?["deliverers"];
    final riderName = deliverer?["users"]?["name"] ?? "Repartidor";
    final riderPhone = deliverer?["users"]?["phone"];
    final riderLat = deliverer?["current_lat"];
    final riderLng = deliverer?["current_lng"];
    final status = _order?["status"] as String? ?? "";
    final hasLocation = riderLat != null && riderLng != null;
    final statusLabels = {
      "assigned": "🛵 Repartidor en camino al restaurante",
      "picked_up": "📦 Repartidor recogió tu pedido",
      "on_the_way": "🚀 Tu pedido está en camino",
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Seguimiento"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
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

          // Info repartidor
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Column(children: [
              Row(children: [
                CircleAvatar(radius: 24, backgroundColor: AppColors.accent.withOpacity(0.15), child: const Text("🛵", style: TextStyle(fontSize: 22))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(riderName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(hasLocation ? "📍 Ubicación disponible" : "📍 Obteniendo ubicación...", style: TextStyle(color: hasLocation ? AppColors.success : AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
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
                const SizedBox(height: 16),
                Row(children: [
                  const Icon(Icons.location_on, color: AppColors.accent, size: 18),
                  const SizedBox(width: 8),
                  Text("Lat: ${riderLat?.toStringAsFixed(4)}, Lng: ${riderLng?.toStringAsFixed(4)}", style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 16),

          // Boton abrir en Google Maps
          ElevatedButton.icon(
            onPressed: _openGoogleMaps,
            icon: const Icon(Icons.map_outlined),
            label: const Text("Abrir en Google Maps"),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
          ),
          const SizedBox(height: 12),

          // Direccion de entrega
          if (_order?["delivery_address"] != null) Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Dirección de entrega", style: TextStyle(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w600)),
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
