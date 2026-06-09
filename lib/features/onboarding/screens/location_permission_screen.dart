import "dart:async";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:geocoding/geocoding.dart";
import "package:geolocator/geolocator.dart";
import "package:go_router/go_router.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../config/app_config.dart";
import "../../../core/theme/app_theme.dart";

const _kDark   = Color(0xFF1A0033);
const _kOrange = Color(0xFFFF6B00);
const _kPurple = Color(0xFF9E00FF);

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});
  @override
  State<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _loadingGps  = false;
  bool _showManual  = false;
  bool _searching   = false;

  final _searchCtrl = TextEditingController();
  final _dio        = Dio();
  List<Map<String, dynamic>> _suggestions = [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── GPS ───────────────────────────────────────────────────────────────────

  Future<void> _useGps() async {
    setState(() => _loadingGps = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _showError("Permiso denegado permanentemente. Actívalo en Ajustes.");
        return;
      }
      if (perm == LocationPermission.denied) {
        _showError("Permiso de ubicación requerido.");
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      String address;
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        final pm    = marks.firstOrNull;
        if (pm != null) {
          final parts = [pm.street, pm.locality, pm.administrativeArea]
              .where((p) => p != null && p.isNotEmpty).toList();
          address = parts.join(", ");
        } else {
          address = "${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}";
        }
      } catch (_) {
        address = "${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}";
      }

      await _saveAndNavigate(address, pos.latitude, pos.longitude);
    } on TimeoutException catch (_) {
      _showError("No se pudo obtener tu ubicación. Intenta de nuevo.");
    } catch (e) {
      _showError("Error al obtener ubicación.");
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  // ── Places autocomplete ───────────────────────────────────────────────────

  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 3) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    if (mounted) setState(() => _searching = true);
    try {
      final resp = await _dio.get(
        "https://maps.googleapis.com/maps/api/place/autocomplete/json",
        queryParameters: {
          "input":      query,
          "key":        AppConfig.googleMapsApiKey,
          "language":   "es",
          "components": "country:cl",
        },
      );
      final preds = (resp.data["predictions"] as List?) ?? [];
      if (mounted) setState(() {
        _suggestions = preds.cast<Map<String, dynamic>>();
        _searching   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectPlace(Map<String, dynamic> place) async {
    final placeId = place["place_id"] as String?;
    if (placeId == null) return;
    try {
      final resp = await _dio.get(
        "https://maps.googleapis.com/maps/api/place/details/json",
        queryParameters: {
          "place_id": placeId,
          "key":      AppConfig.googleMapsApiKey,
          "fields":   "geometry,formatted_address",
        },
      );
      final result   = resp.data["result"] as Map<String, dynamic>?;
      final address  = result?["formatted_address"] as String? ?? "";
      final location = result?["geometry"]?["location"] as Map?;
      final lat      = (location?["lat"] as num?)?.toDouble();
      final lng      = (location?["lng"] as num?)?.toDouble();
      await _saveAndNavigate(address, lat, lng);
    } catch (_) {
      _showError("Error al obtener la dirección seleccionada.");
    }
  }

  // ── Persist & navigate ────────────────────────────────────────────────────

  Future<void> _saveAndNavigate(String address, double? lat, double? lng) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("delivery_address", address);
    if (lat != null) await prefs.setDouble("delivery_lat", lat);
    if (lng != null) await prefs.setDouble("delivery_lng", lng);
    await prefs.setBool("location_configured", true);

    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      if (authUser != null) {
        await Supabase.instance.client
            .from("users")
            .update({"default_address": address})
            .eq("auth_id", authUser.id);
      }
    } catch (_) {}

    if (mounted) context.go("/home");
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kDark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset("assets/images/logo.png",
                  height: 60, filterQuality: FilterQuality.high),
              const SizedBox(height: 40),
              const Text("🗺️", style: TextStyle(fontSize: 80)),
              const SizedBox(height: 24),
              const Text("¿Dónde te entregamos?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  fontFamily: "Nunito",
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Necesitamos tu ubicación para mostrarte\nlas tiendas disponibles en tu zona",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),

              // ── GPS button ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadingGps ? null : _useGps,
                  icon: _loadingGps
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text("📍", style: TextStyle(fontSize: 20)),
                  label: Text(
                    _loadingGps ? "Obteniendo ubicación..." : "Usar mi ubicación actual",
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _kOrange.withOpacity(0.6),
                    disabledForegroundColor: Colors.white70,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Manual address button ───────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _showManual = !_showManual;
                    if (!_showManual) {
                      _searchCtrl.clear();
                      _suggestions = [];
                    }
                  }),
                  icon: const Text("✍️", style: TextStyle(fontSize: 20)),
                  label: const Text(
                    "Ingresar dirección",
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kPurple,
                    side: const BorderSide(color: _kPurple, width: 2),
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

              // ── Manual search field ─────────────────────────────────────
              if (_showManual) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Busca tu dirección...",
                    hintStyle:
                        TextStyle(color: Colors.white.withOpacity(0.45)),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white54),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)))
                        : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: _kPurple.withOpacity(0.4)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: _kPurple, width: 2),
                    ),
                  ),
                  onChanged: _searchPlaces,
                ),
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _kPurple.withOpacity(0.3)),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _suggestions.length.clamp(0, 5),
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: Colors.white.withOpacity(0.1)),
                      itemBuilder: (_, i) {
                        final s    = _suggestions[i];
                        final main = s["structured_formatting"]
                                ?["main_text"] as String? ??
                            s["description"] as String? ?? "";
                        final sub = s["structured_formatting"]
                                ?["secondary_text"] as String? ??
                            "";
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on,
                              color: _kOrange, size: 20),
                          title: Text(main,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                          subtitle: sub.isNotEmpty
                              ? Text(sub,
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 11))
                              : null,
                          onTap: () => _selectPlace(s),
                        );
                      },
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 40),
              Text(
                "Puedes cambiarla cuando quieras desde el inicio",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
