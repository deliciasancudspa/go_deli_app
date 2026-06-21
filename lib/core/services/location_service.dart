import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';

/// Servicio de geolocalización para detectar la comuna del usuario.
///
/// Usa tres estrategias en cascada:
/// 1. Google Geocoding API (administrative_area_level_2 en Chile = comuna)
/// 2. Fallback: package geocoding (placemark.administrativeArea)
/// 3. Fuzzy match contra la tabla communes de Supabase
class LocationService {
  static const _prefsCommuneId   = 'user_commune_id';
  static const _prefsCommuneName = 'user_commune_name';
  static const _prefsRegionName  = 'user_region_name';
  static const _prefsRegionId    = 'user_region_id';

  final _sb  = Supabase.instance.client;
  final _dio = Dio();

  /// Detecta la comuna desde coordenadas (lat, lng) y la persiste en SharedPreferences.
  /// Retorna el map {commune_id, commune_name, region_name, region_id} o null si falla.
  Future<Map<String, String>?> detectAndSaveCommune(double lat, double lng) async {
    final result = await _detectCommune(lat, lng);
    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsCommuneId,   result['commune_id']!);
      await prefs.setString(_prefsCommuneName, result['commune_name']!);
      await prefs.setString(_prefsRegionName,  result['region_name']!);
      await prefs.setString(_prefsRegionId,    result['region_id']!);
    }
    return result;
  }

  /// Detecta la comuna desde una dirección de texto (Google Places Details).
  /// Usa el place_id para obtener address_components y extraer la comuna.
  Future<Map<String, String>?> detectFromPlaceId(String placeId) async {
    try {
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'key':      AppConfig.googleMapsApiKey,
          'fields':   'address_components,geometry',
          'language': 'es',
        },
      );
      final result = resp.data['result'] as Map<String, dynamic>?;
      if (result == null) return null;

      // Extraer comuna de address_components
      final components = result['address_components'] as List? ?? [];
      String? communeName;
      String? regionName;

      for (final comp in components.cast<Map<String, dynamic>>()) {
        final types = List<String>.from(comp['types'] ?? []);
        final longName = comp['long_name'] as String? ?? '';

        // administrative_area_level_3 = comuna en Chile (ej: Providencia, Ancud)
        // administrative_area_level_2 = región   en Chile (ej: Metropolitana de Santiago)
        // administrative_area_level_1 = provincia (no la usamos)
        if (types.contains('administrative_area_level_3') && communeName == null) {
          communeName = longName;
        }
        if (types.contains('administrative_area_level_2') && regionName == null) {
          regionName = longName;
        }
        // Algunas direcciones en Chile solo llegan a level_2 (comuna = level_2 cuando no hay level_3)
        if (types.contains('administrative_area_level_2') && communeName == null) {
          // Verificar si este level_2 es realmente una comuna (no una región)
          final isRegion = await _isRegion(longName);
          if (!isRegion) communeName = longName;
        }
      }

      if (communeName == null) return null;

      // Buscar en la BD de GoDeli
      return await _matchCommuneInDb(communeName, regionName);
    } catch (_) {
      return null;
    }
  }

  /// Detecta comuna desde lat/lng usando primero Google Geocoding API,
  /// luego fallback a package geocoding.
  Future<Map<String, String>?> _detectCommune(double lat, double lng) async {
    // Estrategia 1: Google Geocoding API
    try {
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng':   '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
          'key':      AppConfig.googleMapsApiKey,
          'language': 'es',
        },
      );
      final results = resp.data['results'] as List?;
      if (results != null && results.isNotEmpty) {
        for (final r in results.cast<Map<String, dynamic>>()) {
          final components = r['address_components'] as List? ?? [];
          String? communeName;
          String? regionName;

          for (final comp in components.cast<Map<String, dynamic>>()) {
            final types = List<String>.from(comp['types'] ?? []);
            final longName = comp['long_name'] as String? ?? '';

            if (types.contains('administrative_area_level_3') && communeName == null) {
              communeName = longName;
            }
            if (types.contains('administrative_area_level_2') && regionName == null) {
              regionName = longName;
            }
          }

          if (communeName != null) {
            return await _matchCommuneInDb(communeName, regionName);
          }
        }
      }
    } catch (_) {}

    // Estrategia 2: fallback con package geocoding (gratis, offline-friendly)
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      final pm = marks.firstOrNull;
      if (pm != null) {
        final adminArea = pm.administrativeArea; // puede ser comuna o provincia
        final subAdmin  = pm.subAdministrativeArea;
        if (adminArea != null) {
          return await _matchCommuneInDb(adminArea, subAdmin);
        }
        if (pm.locality != null) {
          return await _matchCommuneInDb(pm.locality!, subAdmin);
        }
      }
    } catch (_) {}

    return null;
  }

  /// Busca la comuna en la tabla communes de Supabase.
  /// Hace match exacto primero, luego fuzzy (case-insensitive, sin acentos).
  Future<Map<String, String>?> _matchCommuneInDb(String communeName, String? regionHint) async {
    // Match exacto
    try {
      final result = await _sb.rpc('find_commune', params: {
        'p_name':   communeName,
        'p_region': regionHint,
      });
      if (result != null && (result as String).isNotEmpty) {
        final communeId = result as String;
        // Obtener detalles completos
        final data = await _sb.from('communes')
            .select('id, name, regions!inner(id, name)')
            .eq('id', communeId)
            .single();
        return {
          'commune_id':   data['id'] as String,
          'commune_name': data['name'] as String,
          'region_id':    (data['regions'] as Map)['id'] as String,
          'region_name':  (data['regions'] as Map)['name'] as String,
        };
      }
    } catch (_) {}

    // Fuzzy match: buscar por similitud
    try {
      final data = await _sb.from('communes')
          .select('id, name, regions!inner(id, name)')
          .ilike('name', '%$communeName%')
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();
      if (data != null) {
        return {
          'commune_id':   data['id'] as String,
          'commune_name': data['name'] as String,
          'region_id':    (data['regions'] as Map)['id'] as String,
          'region_name':  (data['regions'] as Map)['name'] as String,
        };
      }
    } catch (_) {}

    return null;
  }

  /// Verifica si un nombre corresponde a una región de Chile.
  Future<bool> _isRegion(String name) async {
    try {
      final data = await _sb.from('regions')
          .select('id')
          .ilike('name', name)
          .limit(1);
      return (data is List && data.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Carga la comuna guardada desde SharedPreferences.
  /// Retorna null si el usuario no ha configurado ubicación.
  static Future<Map<String, String>?> loadSavedCommune() async {
    final prefs = await SharedPreferences.getInstance();
    final id   = prefs.getString(_prefsCommuneId);
    final name = prefs.getString(_prefsCommuneName);
    if (id == null || name == null) return null;
    return {
      'commune_id':   id,
      'commune_name': name,
      'region_name':  prefs.getString(_prefsRegionName) ?? '',
      'region_id':    prefs.getString(_prefsRegionId) ?? '',
    };
  }

  /// Lista todas las comunas (para dropdowns). Cacheable.
  Future<List<Map<String, dynamic>>> listCommunes() async {
    final data = await _sb.rpc('list_communes');
    return (data as List).cast<Map<String, dynamic>>();
  }
}
