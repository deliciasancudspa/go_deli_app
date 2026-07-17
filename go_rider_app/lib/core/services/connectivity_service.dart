import "dart:async";
import "package:flutter/foundation.dart";
import "package:connectivity_plus/connectivity_plus.dart";

/// Monitorea la conectividad del dispositivo y expone un [ValueNotifier] para
/// que las pantallas reaccionen a cambios de red en tiempo real.
///
/// Uso:
/// ```dart
/// final cs = ConnectivityService.instance;
/// ValueListenableBuilder<bool>(
///   valueListenable: cs.isOnline,
///   builder: (ctx, online, _) => online ? ... : offlineBanner,
/// )
/// ```
class ConnectivityService {
  ConnectivityService._() {
    _init();
  }

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  /// `true` mientras haya Wi‑Fi, mobile data o ethernet.
  final ValueNotifier<bool> isOnline = ValueNotifier(true);

  StreamSubscription<List<ConnectivityResult>>? _sub;

  void _init() {
    // Valor inicial
    _connectivity.checkConnectivity().then((results) {
      isOnline.value = _isConnected(results);
    });
    // Cambios en tiempo real
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = _isConnected(results);
      if (isOnline.value != online) {
        isOnline.value = online;
        debugPrint('[ConnectivityService] ${online ? "ONLINE" : "OFFLINE"}');
      }
    });
  }

  bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) =>
      r == ConnectivityResult.wifi ||
      r == ConnectivityResult.mobile ||
      r == ConnectivityResult.ethernet);
  }

  /// Libera recursos. Solo necesario en tests.
  void dispose() {
    _sub?.cancel();
    isOnline.dispose();
  }
}
