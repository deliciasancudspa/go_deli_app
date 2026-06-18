import "dart:convert";
import "package:http/http.dart" as http;
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:geolocator/geolocator.dart";
import "../../config/app_config.dart";

/// Resultado de una consulta de ruta entre dos puntos.
class RouteResult {
  final List<LatLng> points;     // puntos para dibujar la polyline
  final double distanceMeters;   // distancia de la ruta
  final String? durationText;    // ej: "12 min"
  final bool isFallback;         // true si se usó línea recta (sin Directions API)

  RouteResult({
    required this.points,
    required this.distanceMeters,
    this.durationText,
    this.isFallback = false,
  });

  double get distanceKm => distanceMeters / 1000.0;
}

/// Consulta la ruta de conducción más rápida entre dos puntos usando la
/// Google Directions API. Si la API falla (CORS en web, cuota, sin red, etc.)
/// devuelve una línea recta entre origen y destino para no romper la UI.
class DirectionsService {
  static Future<RouteResult> getRoute(LatLng origin, LatLng destination) async {
    final fallback = RouteResult(
      points: [origin, destination],
      distanceMeters: Geolocator.distanceBetween(
        origin.latitude, origin.longitude,
        destination.latitude, destination.longitude,
      ),
      isFallback: true,
    );

    try {
      final uri = Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=${origin.latitude},${origin.longitude}"
        "&destination=${destination.latitude},${destination.longitude}"
        "&mode=driving&alternatives=false&language=es"
        "&key=${AppConfig.googleMapsApiKey}",
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return fallback;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data["status"] != "OK") return fallback;

      final routes = data["routes"] as List?;
      if (routes == null || routes.isEmpty) return fallback;

      final route = routes.first as Map<String, dynamic>;
      final overview = (route["overview_polyline"] as Map?)?["points"] as String?;
      if (overview == null) return fallback;

      final pts = _decodePolyline(overview);
      if (pts.length < 2) return fallback;

      double dist = fallback.distanceMeters;
      String? dur;
      final legs = route["legs"] as List?;
      if (legs != null && legs.isNotEmpty) {
        final leg = legs.first as Map<String, dynamic>;
        dist = ((leg["distance"] as Map?)?["value"] as num?)?.toDouble() ?? dist;
        dur = (leg["duration"] as Map?)?["text"] as String?;
      }

      return RouteResult(points: pts, distanceMeters: dist, durationText: dur);
    } catch (_) {
      return fallback;
    }
  }

  /// Decodifica el formato encoded polyline de Google a una lista de LatLng.
  static List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    final int len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
