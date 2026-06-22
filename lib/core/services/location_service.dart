import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';

/// Servicio de geolocalización para detectar la comuna del usuario.
///
/// Usa tres estrategias en cascada:
/// 1. Google Geocoding API (address_components → administrative_area_level_3 / level_2)
/// 2. Fallback: package geocoding (subAdministrativeArea, administrativeArea, locality)
/// 3. Match contra la tabla communes de Supabase (RPC exacto → fuzzy → normalizado)
class LocationService {
  static const _prefsCommuneId   = 'user_commune_id';
  static const _prefsCommuneName = 'user_commune_name';
  static const _prefsRegionName  = 'user_region_name';
  static const _prefsRegionId    = 'user_region_id';

  final _sb   = Supabase.instance.client;
  final _dio  = Dio();

  static const _accentsMap = {
    'á':'a','à':'a','â':'a','ã':'a','ä':'a','å':'a',
    'é':'e','è':'e','ê':'e','ë':'e',
    'í':'i','ì':'i','î':'i','ï':'i',
    'ó':'o','ò':'o','ô':'o','õ':'o','ö':'o',
    'ú':'u','ù':'u','û':'u','ü':'u',
    'ñ':'n','ç':'c',
    'Á':'A','À':'A','Â':'A','Ã':'A','Ä':'A','Å':'A',
    'É':'E','È':'E','Ê':'E','Ë':'E',
    'Í':'I','Ì':'I','Î':'I','Ï':'I',
    'Ó':'O','Ò':'O','Ô':'O','Õ':'O','Ö':'O',
    'Ú':'U','Ù':'U','Û':'U','Ü':'U',
    'Ñ':'N','Ç':'C',
  };

  /// Normaliza un nombre para matching: sin acentos, lowercase, sin prefijos comunes.
  static String _normalize(String s) {
    var out = s;
    _accentsMap.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.toLowerCase().trim();
    // Quitar prefijos comunes
    final prefixes = ['comuna de ', 'comuna ', 'municipio de ', 'municipio '];
    for (final p in prefixes) {
      if (out.startsWith(p)) out = out.substring(p.length).trim();
    }
    return out;
  }

  /// Detecta la comuna desde coordenadas (lat, lng) y la persiste en SharedPreferences.
  /// Retorna el map {commune_id, commune_name, region_name, region_id} o null si falla.
  Future<Map<String, String>?> detectAndSaveCommune(double lat, double lng) async {
    debugPrint('[LocationService] detectAndSaveCommune($lat, $lng)');
    final result = await _detectCommune(lat, lng);
    if (result != null) {
      debugPrint('[LocationService] ✅ Comuna detectada: ${result['commune_name']} (${result['region_name']})');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsCommuneId,   result['commune_id']!);
      await prefs.setString(_prefsCommuneName, result['commune_name']!);
      await prefs.setString(_prefsRegionName,  result['region_name']!);
      await prefs.setString(_prefsRegionId,    result['region_id']!);

      // Guardar commune_id en la BD para que admin push pueda filtrar por comuna
      try {
        final authId = Supabase.instance.client.auth.currentUser?.id;
        if (authId != null) {
          await Supabase.instance.client
            .from('users')
            .update({'commune_id': result['commune_id']})
            .eq('auth_id', authId);
          debugPrint('[LocationService] ✅ commune_id guardado en BD para admin push');
        }
      } catch (e) {
        debugPrint('[LocationService] ⚠️ No se pudo guardar commune_id en BD: $e');
      }
    } else {
      debugPrint('[LocationService] ❌ No se pudo detectar la comuna');
    }
    return result;
  }

  /// Detecta la comuna desde una dirección de texto (Google Places Details).
  /// Usa el place_id para obtener address_components y extraer la comuna.
  Future<Map<String, String>?> detectFromPlaceId(String placeId) async {
    debugPrint('[LocationService] detectFromPlaceId($placeId)');
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
      if (result == null) {
        debugPrint('[LocationService] Place Details: result es null');
        return null;
      }

      // Extraer comuna de address_components
      final components = result['address_components'] as List? ?? [];
      String? communeName;
      String? regionName;

      for (final comp in components.cast<Map<String, dynamic>>()) {
        final types = List<String>.from(comp['types'] ?? []);
        final longName = comp['long_name'] as String? ?? '';

        // administrative_area_level_3 = comuna en Chile (ej: Providencia, Ancud)
        // administrative_area_level_2 = región   en Chile (ej: Metropolitana de Santiago)
        if (types.contains('administrative_area_level_3') && communeName == null) {
          communeName = longName;
        }
        if (types.contains('administrative_area_level_2') && regionName == null) {
          regionName = longName;
        }
        // Algunas direcciones en Chile solo llegan a level_2 (comuna = level_2 cuando no hay level_3)
        if (types.contains('administrative_area_level_2') && communeName == null) {
          final isRegion = await _isRegion(longName);
          if (!isRegion) communeName = longName;
        }
      }

      if (communeName == null) {
        debugPrint('[LocationService] Place Details: no se encontró comuna en address_components');
        return null;
      }

      debugPrint('[LocationService] Place Details → comuna: $communeName, región: $regionName');
      return await _matchCommuneInDb(communeName, regionName);
    } catch (e) {
      debugPrint('[LocationService] Place Details ERROR: $e');
      return null;
    }
  }

  /// Detecta comuna desde lat/lng usando primero Google Geocoding API,
  /// luego fallback a package geocoding.
  Future<Map<String, String>?> _detectCommune(double lat, double lng) async {
    // Estrategia 1: Google Geocoding API (web service)
    try {
      debugPrint('[LocationService] Intentando Google Geocoding API...');
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng':   '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
          'key':      AppConfig.googleMapsApiKey,
          'language': 'es',
        },
      );
      final status = resp.data['status'] as String? ?? '';
      debugPrint('[LocationService] Google Geocoding status: $status');
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
            debugPrint('[LocationService] Google Geocoding → comuna: $communeName, región: $regionName');
            return await _matchCommuneInDb(communeName, regionName);
          }
        }
        debugPrint('[LocationService] Google Geocoding: no se encontró administrative_area_level_3 en los resultados');
      }
    } catch (e) {
      debugPrint('[LocationService] Google Geocoding ERROR: $e');
    }

    // Estrategia 2: fallback con package geocoding (gratis, usa plataforma nativa)
    try {
      debugPrint('[LocationService] Intentando geocoding package...');
      final marks = await placemarkFromCoordinates(lat, lng);
      final pm = marks.firstOrNull;
      if (pm != null) {
        debugPrint('[LocationService] placemark → adminArea: ${pm.administrativeArea}, '
            'subAdmin: ${pm.subAdministrativeArea}, locality: ${pm.locality}, '
            'street: ${pm.street}');

        // En Chile, la comuna suele estar en subAdministrativeArea o locality,
        // NO en administrativeArea (que suele ser la provincia o región).
        // Probamos en orden de especificidad:
        final candidates = <String>[
          if (pm.subAdministrativeArea != null && pm.subAdministrativeArea!.isNotEmpty)
            pm.subAdministrativeArea!,
          if (pm.locality != null && pm.locality!.isNotEmpty)
            pm.locality!,
          if (pm.administrativeArea != null && pm.administrativeArea!.isNotEmpty)
            pm.administrativeArea!,
        ];

        for (final candidate in candidates) {
          debugPrint('[LocationService] Probando candidato: "$candidate"');
          final match = await _matchCommuneInDb(candidate, pm.subAdministrativeArea);
          if (match != null) {
            debugPrint('[LocationService] ✅ Match con "$candidate"');
            return match;
          }
        }
        debugPrint('[LocationService] Ningún candidato matcheó una comuna');
      } else {
        debugPrint('[LocationService] placemarkFromCoordinates: no results');
      }
    } catch (e) {
      debugPrint('[LocationService] geocoding package ERROR: $e');
    }

    return null;
  }

  /// Busca la comuna en la tabla communes de Supabase.
  /// Prueba múltiples estrategias: RPC exacta → RPC normalizada → fuzzy ilike → fuzzy normalizado.
  Future<Map<String, String>?> _matchCommuneInDb(String communeName, String? regionHint) async {
    final normalized = _normalize(communeName);
    debugPrint('[LocationService] _matchCommuneInDb("$communeName", hint: "$regionHint") → normalizado: "$normalized"');

    // Estrategia A: RPC find_commune con nombre exacto
    try {
      final result = await _sb.rpc('find_commune', params: {
        'p_name':   communeName,
        'p_region': regionHint,
      });
      if (result != null && (result is String) && result.isNotEmpty) {
        final communeId = result;
        final data = await _sb.from('communes')
            .select('id, name, regions!inner(id, name)')
            .eq('id', communeId)
            .maybeSingle();
        if (data != null) {
          debugPrint('[LocationService] ✅ RPC exacto: ${data['name']}');
          return _buildResult(data);
        }
      }
    } catch (e) {
      debugPrint('[LocationService] RPC find_commune exacto ERROR: $e');
    }

    // Estrategia B: RPC find_commune con nombre normalizado (sin acentos)
    if (normalized != communeName.toLowerCase()) {
      try {
        // Capitalizar primera letra para el RPC (que hace match case-insensitive)
        final capitalized = normalized[0].toUpperCase() + normalized.substring(1);
        final result = await _sb.rpc('find_commune', params: {
          'p_name':   capitalized,
          'p_region': regionHint,
        });
        if (result != null && (result is String) && result.isNotEmpty) {
          final communeId = result;
          final data = await _sb.from('communes')
              .select('id, name, regions!inner(id, name)')
              .eq('id', communeId)
              .maybeSingle();
          if (data != null) {
            debugPrint('[LocationService] ✅ RPC normalizado: ${data['name']}');
            return _buildResult(data);
          }
        }
      } catch (e) {
        debugPrint('[LocationService] RPC find_commune normalizado ERROR: $e');
      }
    }

    // Estrategia C: RPC fuzzy_match_commune (server-side, tolerante a acentos y variaciones)
    try {
      final result = await _sb.rpc('fuzzy_match_commune', params: {
        'p_name':   communeName,
        'p_region': regionHint,
      });
      if (result != null && (result is String) && result.isNotEmpty) {
        final communeId = result;
        final data = await _sb.from('communes')
            .select('id, name, regions!inner(id, name)')
            .eq('id', communeId)
            .maybeSingle();
        if (data != null) {
          debugPrint('[LocationService] ✅ fuzzy_match_commune RPC: ${data['name']}');
          return _buildResult(data);
        }
      }
    } catch (e) {
      debugPrint('[LocationService] fuzzy_match_commune RPC ERROR: $e');
    }

    // Estrategia D: Fuzzy ilike con el nombre original
    try {
      final data = await _sb.from('communes')
          .select('id, name, regions!inner(id, name)')
          .ilike('name', '%$communeName%')
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();
      if (data != null) {
        debugPrint('[LocationService] ✅ Fuzzy ilike original: ${data['name']}');
        return _buildResult(data);
      }
    } catch (e) {
      debugPrint('[LocationService] Fuzzy ilike original ERROR: $e');
    }

    // Estrategia E: Fuzzy ilike con nombre normalizado
    if (normalized != communeName.toLowerCase()) {
      try {
        final data = await _sb.from('communes')
            .select('id, name, regions!inner(id, name)')
            .ilike('name', '%$normalized%')
            .eq('is_active', true)
            .limit(1)
            .maybeSingle();
        if (data != null) {
          debugPrint('[LocationService] ✅ Fuzzy ilike normalizado: ${data['name']}');
          return _buildResult(data);
        }
      } catch (e) {
        debugPrint('[LocationService] Fuzzy ilike normalizado ERROR: $e');
      }
    }

    // Estrategia F: Buscar por primera palabra significativa (>= 4 chars)
    // Ej: "Santiago Centro" → buscar "Santiago", "Providencia" → ya se probó
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.length >= 4).toList();
    if (words.length > 1 && words.first != normalized) {
      for (final word in words) {
        try {
          final data = await _sb.from('communes')
              .select('id, name, regions!inner(id, name)')
              .ilike('name', '%$word%')
              .eq('is_active', true)
              .limit(1)
              .maybeSingle();
          if (data != null) {
            debugPrint('[LocationService] ✅ Fuzzy por palabra "$word": ${data['name']}');
            return _buildResult(data);
          }
        } catch (e) {
          debugPrint('[LocationService] Fuzzy palabra "$word" ERROR: $e');
        }
      }
    }

    debugPrint('[LocationService] ❌ No se encontró match para "$communeName"');
    return null;
  }

  /// Construye el mapa de resultado desde un registro de communes + regions.
  Map<String, String> _buildResult(Map<String, dynamic> data) {
    return {
      'commune_id':   data['id'] as String,
      'commune_name': data['name'] as String,
      'region_id':    (data['regions'] as Map)['id'] as String,
      'region_name':  (data['regions'] as Map)['name'] as String,
    };
  }

  /// Verifica si un nombre corresponde a una región de Chile.
  Future<bool> _isRegion(String name) async {
    try {
      final data = await _sb.from('regions')
          .select('id')
          .ilike('name', name)
          .limit(1);
      return (data as List).isNotEmpty;
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
