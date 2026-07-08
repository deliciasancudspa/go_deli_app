import "package:dio/dio.dart";
import "package:geolocator/geolocator.dart";
import "../../config/app_config.dart";

/// Resultado de una consulta de ruta entre dos puntos.
class RouteResult {
  final double distanceMeters;  // distancia de la ruta (carretera o línea recta)
  final String? durationText;   // ej: "12 min"
  final bool isFallback;        // true si se usó línea recta (sin Directions API)

  RouteResult({
    required this.distanceMeters,
    this.durationText,
    this.isFallback = false,
  });

  double get distanceKm => distanceMeters / 1000.0;
}

/// Consulta la distancia de conducción más rápida entre dos puntos usando la
/// Google Directions API. Si la API falla (timeout, cuota, sin red, etc.)
/// devuelve distancia en línea recta (Haversine) para no romper la UI.
class DirectionsService {
  static final Dio _dio = Dio();

  static Future<RouteResult> getRoute(
    double originLat, double originLng,
    double destLat, double destLng,
  ) async {
    final fallback = RouteResult(
      distanceMeters: Geolocator.distanceBetween(
        originLat, originLng, destLat, destLng,
      ),
      isFallback: true,
    );

    try {
      final uri = Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=$originLat,$originLng"
        "&destination=$destLat,$destLng"
        "&mode=driving&alternatives=false&language=es"
        "&key=${AppConfig.googleMapsApiKey}",
      );
      final resp = await _dio.get(
        uri.toString(),
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      if (resp.statusCode != 200) return fallback;

      final data = resp.data as Map<String, dynamic>;
      if (data["status"] != "OK") return fallback;

      final routes = data["routes"] as List?;
      if (routes == null || routes.isEmpty) return fallback;

      final route = routes.first as Map<String, dynamic>;
      double dist = fallback.distanceMeters;
      String? dur;

      final legs = route["legs"] as List?;
      if (legs != null && legs.isNotEmpty) {
        final leg = legs.first as Map<String, dynamic>;
        dist = ((leg["distance"] as Map?)?["value"] as num?)?.toDouble() ?? dist;
        dur  = (leg["duration"] as Map?)?["text"] as String?;
      }

      return RouteResult(distanceMeters: dist, durationText: dur);
    } catch (_) {
      return fallback;
    }
  }
}
