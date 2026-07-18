import "dart:math";
import "package:flutter/material.dart";
import "package:flutter/foundation.dart";
import "package:flutter/gestures.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:geolocator/geolocator.dart";
import "../../../core/services/directions_service.dart";
import "../../../core/theme/app_theme.dart";

/// Mapa reutilizable que dibuja la ruta de conducción entre [origin] y
/// [destination]. Recalcula la ruta cuando cambia el destino o cuando el
/// origen se mueve más de ~120 m (para no saturar la Directions API con cada
/// actualización de GPS). Si [origin] es null solo muestra el destino.
class RouteMapView extends StatefulWidget {
  final LatLng? origin;
  final LatLng destination;
  final String originLabel;
  final String destinationLabel;
  final double originHue;
  final double destinationHue;
  final double height;
  final bool embedded; // true: dentro de un scroll (captura gestos del mapa)
  final bool fullScreen; // true: ocupa todo el espacio disponible (ignora height)
  final Widget? floatingChild; // widgets superpuestos sobre el mapa (ej: botones)
  final void Function(RouteResult route)? onRouteReady;
  final void Function(GoogleMapController)? onMapCreated;

  const RouteMapView({
    super.key,
    required this.origin,
    required this.destination,
    this.originLabel = "Tú",
    this.destinationLabel = "Destino",
    this.originHue = BitmapDescriptor.hueAzure,
    this.destinationHue = BitmapDescriptor.hueRed,
    this.height = 240,
    this.embedded = false,
    this.fullScreen = false,
    this.floatingChild,
    this.onRouteReady,
    this.onMapCreated,
  });

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView> {
  GoogleMapController? _ctrl;
  RouteResult? _route;
  LatLng? _lastRoutedOrigin;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  @override
  void didUpdateWidget(RouteMapView old) {
    super.didUpdateWidget(old);
    final destChanged = old.destination != widget.destination;
    final originMoved = _movedEnough(_lastRoutedOrigin, widget.origin);
    if (destChanged || originMoved) {
      _fetchRoute();
    } else if (widget.origin != old.origin) {
      setState(() {}); // mover marcador de origen sin recalcular la ruta
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  bool _movedEnough(LatLng? a, LatLng? b) {
    if (b == null) return false;
    if (a == null) return true;
    return Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude) > 120;
  }

  Future<void> _fetchRoute() async {
    if (widget.origin == null) {
      if (mounted) setState(() => _route = null);
      _fitCamera();
      return;
    }
    if (_fetching) return;
    _fetching = true;
    final origin = widget.origin!;
    _lastRoutedOrigin = origin;
    final result = await DirectionsService.getRoute(origin, widget.destination);
    _fetching = false;
    if (!mounted) return;
    setState(() => _route = result);
    widget.onRouteReady?.call(result);
    _fitCamera();
  }

  void _applyDarkMode(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark && _ctrl != null) {
      _ctrl!.setMapStyle(AppColors.mapDarkStyle);
    }
  }

  void _fitCamera() {
    if (_ctrl == null) return;
    final pts = <LatLng>[
      if (widget.origin != null) widget.origin!,
      widget.destination,
      ...?_route?.points,
    ];
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _ctrl!.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    _ctrl!.animateCamera(CameraUpdate.newLatLngBounds(_boundsFor(pts), 60));
  }

  LatLngBounds _boundsFor(List<LatLng> pts) {
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Set<Marker> get _markers {
    final m = <Marker>{};
    if (widget.origin != null) {
      m.add(Marker(
        markerId: const MarkerId("origin"),
        position: widget.origin!,
        icon: BitmapDescriptor.defaultMarkerWithHue(widget.originHue),
        infoWindow: InfoWindow(title: widget.originLabel),
      ));
    }
    m.add(Marker(
      markerId: const MarkerId("dest"),
      position: widget.destination,
      icon: BitmapDescriptor.defaultMarkerWithHue(widget.destinationHue),
      infoWindow: InfoWindow(title: widget.destinationLabel),
    ));
    return m;
  }

  Set<Polyline> get _polylines {
    final pts = _route?.points;
    if (pts == null || pts.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId("route"),
        points: pts,
        color: AppColors.accent,
        width: 5,
        geodesic: true,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.origin ?? widget.destination;

    Widget mapWidget = GoogleMap(
      initialCameraPosition: CameraPosition(target: initial, zoom: 14),
      markers: _markers,
      polylines: _polylines,
      myLocationButtonEnabled: !widget.fullScreen,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: widget.fullScreen,
      onMapCreated: (c) {
        _ctrl = c;
        _fitCamera();
        _applyDarkMode(context);
        widget.onMapCreated?.call(c);
      },
      gestureRecognizers: widget.embedded
          ? <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
            }
          : const <Factory<OneSequenceGestureRecognizer>>{},
    );

    if (widget.fullScreen) {
      // Full screen: render map inside a Stack to allow floating widgets
      return Stack(children: [
        mapWidget,
        if (widget.floatingChild != null) widget.floatingChild!,
      ]);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: mapWidget,
      ),
    );
  }
}
