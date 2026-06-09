import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:geolocator/geolocator.dart";
import "package:geocoding/geocoding.dart";
import "package:dio/dio.dart";
import "../../../core/theme/app_theme.dart";
import "../../../config/app_config.dart";

class AddressPickerScreen extends StatefulWidget {
  const AddressPickerScreen({super.key});
  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  GoogleMapController? _mapCtrl;
  LatLng _center = const LatLng(-41.8695, -73.8303);
  String _address = "Mueve el mapa para seleccionar";
  bool _loading = true;
  bool _geocoding = false;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  bool _showSuggestions = false;

  final _dio = Dio();

  @override
  void initState() {
    super.initState();
    _init();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        _center = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
      _reverseGeocode(_center);
    }
  }

  void _onSearchChanged() {
    final text = _searchCtrl.text.trim();
    if (text.length < 3) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    _fetchSuggestions(text);
  }

  Future<void> _fetchSuggestions(String input) async {
    setState(() => _searching = true);
    try {
      final res = await _dio.get(
        "https://maps.googleapis.com/maps/api/place/autocomplete/json",
        queryParameters: {
          "input": input,
          "key": AppConfig.googleMapsApiKey,
          "language": "es",
          "components": "country:cl",
        },
      );
      final predictions = res.data["predictions"] as List? ?? [];
      if (mounted) {
        setState(() {
          _suggestions = predictions.map((p) => {
            "description": p["description"] as String,
            "place_id": p["place_id"] as String,
          }).toList();
          _showSuggestions = _suggestions.isNotEmpty;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    _searchFocus.unfocus();
    setState(() { _showSuggestions = false; _geocoding = true; _address = suggestion["description"]; });
    _searchCtrl.text = suggestion["description"];
    try {
      final res = await _dio.get(
        "https://maps.googleapis.com/maps/api/place/details/json",
        queryParameters: {
          "place_id": suggestion["place_id"],
          "key": AppConfig.googleMapsApiKey,
          "fields": "geometry,formatted_address",
          "language": "es",
        },
      );
      final result = res.data["result"];
      if (result != null) {
        final loc = result["geometry"]["location"];
        final pos = LatLng((loc["lat"] as num).toDouble(), (loc["lng"] as num).toDouble());
        final formattedAddress = result["formatted_address"] as String? ?? suggestion["description"];
        _center = pos;
        _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 17)));
        if (mounted) setState(() { _address = formattedAddress; _geocoding = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    if (!mounted) return;
    setState(() { _geocoding = true; _center = pos; });
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.street, p.locality, p.administrativeArea]
          .where((s) => s != null && s.isNotEmpty).cast<String>().toList();
        if (mounted) setState(() => _address = parts.join(", "));
      } else {
        if (mounted) setState(() => _address = "");
      }
    } catch (_) {
      if (mounted) setState(() => _address = "");
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 16),
            Text("Obteniendo tu ubicación...", style: TextStyle(color: AppColors.textLight)),
          ]),
        ),
      );
    }

    return Scaffold(
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _center, zoom: 16),
          onMapCreated: (c) => _mapCtrl = c,
          onCameraMove: (pos) {
            _center = pos.target;
            if (_showSuggestions) setState(() => _showSuggestions = false);
          },
          onCameraIdle: () => _reverseGeocode(_center),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          buildingsEnabled: true,
        ),

        // Pin fijo en el centro
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_pin, color: AppColors.accent, size: 52),
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.3), shape: BoxShape.circle),
                ),
              ]),
            ),
          ),
        ),

        // Barra de búsqueda superior
        SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  // Botón volver
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8)]),
                      child: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 2))]),
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: "Buscar dirección...",
                          hintStyle: const TextStyle(color: AppColors.textLight, fontSize: 14),
                          prefixIcon: _searching
                            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)))
                            : const Icon(Icons.search, color: AppColors.accent, size: 20),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear, size: 18, color: AppColors.textLight), onPressed: () { _searchCtrl.clear(); setState(() { _suggestions = []; _showSuggestions = false; }); })
                            : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              // Sugerencias
              if (_showSuggestions)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 4))]),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final s = _suggestions[i];
                        return InkWell(
                          onTap: () => _selectSuggestion(s),
                          borderRadius: i == 0
                            ? const BorderRadius.vertical(top: Radius.circular(14))
                            : i == _suggestions.length - 1 ? const BorderRadius.vertical(bottom: Radius.circular(14)) : BorderRadius.zero,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(children: [
                              const Icon(Icons.location_on_outlined, color: AppColors.accent, size: 18),
                              const SizedBox(width: 10),
                              Expanded(child: Text(s["description"], style: const TextStyle(fontSize: 13, color: AppColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis)),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Botón GPS (derecha)
        Positioned(
          right: 16,
          bottom: 200,
          child: GestureDetector(
            onTap: () async {
              try {
                final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
                final latlng = LatLng(pos.latitude, pos.longitude);
                _mapCtrl?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: latlng, zoom: 17)));
              } catch (_) {}
            },
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8)]),
              child: const Icon(Icons.my_location, color: AppColors.primary, size: 22),
            ),
          ),
        ),

        // Panel inferior
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, -4))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.location_on, color: AppColors.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Dirección seleccionada", style: TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (_geocoding)
                    const Row(children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text("Identificando dirección...", style: TextStyle(color: AppColors.textLight, fontSize: 14)),
                    ])
                  else if (_address.isEmpty)
                    const Text("No se pudo identificar la dirección. Mueve el mapa o busca manualmente.", style: TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600))
                  else
                    Text(_address, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark), maxLines: 3, overflow: TextOverflow.ellipsis),
                ])),
              ]),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: (_geocoding || _address.isEmpty) ? null : () => Navigator.pop(context, {
                  "address": _address,
                  "lat": _center.latitude,
                  "lng": _center.longitude,
                }),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("Confirmar esta dirección"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
