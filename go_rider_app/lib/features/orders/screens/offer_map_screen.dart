import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../map/widgets/route_map_view.dart";

/// Vista previa de una oferta de pedido sobre un mapa: muestra la ruta entre
/// la tienda y el cliente, cuánto ganará el rider y la distancia. Devuelve
/// `true` (aceptar) o `false` (rechazar) al hacer pop.
class OfferMapScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> offerData; // notif["data"]
  const OfferMapScreen({super.key, required this.orderId, required this.offerData});

  @override
  State<OfferMapScreen> createState() => _OfferMapScreenState();
}

class _OfferMapScreenState extends State<OfferMapScreen> {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _order;
  bool _loading = true;
  double? _routeKm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // maybeSingle: en ofertas abiertas la RLS puede no dejar leer el pedido
      // todavía (deliverer_id NULL). En ese caso _order queda null y la pantalla
      // muestra los datos que vienen en la notificación.
      final o = await _sb.from("orders")
          .select("delivery_lat,delivery_lng,delivery_address,delivery_reference,rider_fee,total,delivery_distance,payment_method,stores(name,emoji,lat,lng,address)")
          .eq("id", widget.orderId)
          .maybeSingle();
      if (mounted) setState(() { _order = o; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  LatLng? get _storePos {
    final s = _order?["stores"] as Map?;
    final lat = (s?["lat"] as num?)?.toDouble();
    final lng = (s?["lng"] as num?)?.toDouble();
    return (lat != null && lng != null) ? LatLng(lat, lng) : null;
  }

  LatLng? get _clientPos {
    final lat = (_order?["delivery_lat"] as num?)?.toDouble();
    final lng = (_order?["delivery_lng"] as num?)?.toDouble();
    return (lat != null && lng != null) ? LatLng(lat, lng) : null;
  }

  double get _riderFee {
    final fromOrder = (_order?["rider_fee"] as num?)?.toDouble();
    if (fromOrder != null && fromOrder > 0) return fromOrder;
    return (widget.offerData["rider_fee"] as num?)?.toDouble() ?? 0;
  }

  String get _distanceLabel {
    // Prioridad 1: delivery_distance del pedido (haversine, usada para fees y cobertura)
    final meters = (_order?["delivery_distance"] as num?)?.toDouble();
    if (meters != null) return "${(meters / 1000).toStringAsFixed(1)} km";
    // Prioridad 2: distance_km del payload de la notificación
    final fromOffer = widget.offerData["distance_km"]?.toString();
    if (fromOffer != null) return "$fromOffer km";
    // Prioridad 3: ruta calculada por Google Directions (distancia real de manejo)
    if (_routeKm != null) return "~${_routeKm!.toStringAsFixed(1)} km (ruta)";
    return "—";
  }

  @override
  Widget build(BuildContext context) {
    final store = _order?["stores"] as Map?;
    final storeName = store?["name"] as String? ?? widget.offerData["store_name"] as String? ?? "Tienda";
    final storeEmoji = store?["emoji"] as String? ?? widget.offerData["store_emoji"] as String? ?? "🏪";
    final delivAddr = _order?["delivery_address"] as String? ?? widget.offerData["delivery_address"] as String? ?? "";
    final delivRef  = _order?["delivery_reference"] as String? ?? widget.offerData["delivery_reference"] as String?;
    final payMethod = _order?["payment_method"] as String?;
    final total = (_order?["total"] as num?)?.toDouble() ?? (widget.offerData["total"] as num?)?.toDouble() ?? 0;

    final storePos = _storePos;
    final clientPos = _clientPos;
    final canShowMap = storePos != null && clientPos != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Nueva oferta de pedido"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context, false)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Stack(children: [
              // Mapa o placeholder
              Positioned.fill(
                child: canShowMap
                    ? RouteMapView(
                        origin: storePos,
                        destination: clientPos,
                        originLabel: storeName,
                        destinationLabel: "Cliente",
                        originHue: BitmapDescriptor.hueOrange,
                        destinationHue: BitmapDescriptor.hueViolet,
                        height: double.infinity,
                        onRouteReady: (r) {
                          if (mounted) setState(() => _routeKm = r.distanceKm);
                        },
                      )
                    : Container(
                        color: AppColors.border.withOpacity(0.3),
                        child: const Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.map_outlined, size: 56, color: AppColors.textLight),
                            SizedBox(height: 12),
                            Text("Mapa no disponible para este pedido",
                                style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
              ),

              // Panel inferior con detalles y acciones
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 14, offset: const Offset(0, -3))],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Center(child: Container(width: 42, height: 4, margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),

                    // Ganancia + distancia
                    Row(children: [
                      Expanded(child: _metric("🛵 Ganarás", "\$${_riderFee.toStringAsFixed(0)}", AppColors.success)),
                      const SizedBox(width: 12),
                      Expanded(child: _metric("📍 Distancia", _distanceLabel, AppColors.info)),
                    ]),
                    const SizedBox(height: 14),

                    // Tienda
                    Row(children: [
                      Text(storeEmoji, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text("Recoger en", style: TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w700)),
                        Text(storeName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ])),
                    ]),
                    if (delivAddr.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.location_on_outlined, size: 20, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text("Entregar en", style: TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w700)),
                          Text(delivAddr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        ])),
                      ]),
                    ],
                    if (delivRef != null && delivRef.isNotEmpty) ...[
                      const SizedBox(height: 8),
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
                            delivRef,
                            style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 13, height: 1.35),
                          )),
                        ]),
                      ),
                    ],

                    if (payMethod == "cash") ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.payments_outlined, size: 16, color: AppColors.warning),
                          const SizedBox(width: 6),
                          Text("Cobra \$${total.toStringAsFixed(0)} en efectivo",
                              style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700, fontSize: 12)),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context, false),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text("Rechazar"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text("Aceptar"),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size(0, 50)),
                      )),
                    ]),
                  ]),
                ),
              ),
            ]),
    );
  }

  Widget _metric(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMedium, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
    ]),
  );
}
