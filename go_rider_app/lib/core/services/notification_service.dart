import "dart:convert" show jsonEncode, jsonDecode;
import "dart:ui" show Color;
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "../../config/app_routes.dart";

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _permissionRequested = false;

  static const _channelId   = "go_rider_channel";
  static const _channelName = "Go Rider Notificaciones";
  static const _channelDesc = "Pedidos, mensajes y alertas para repartidores";
  static int _idCounter = 0;

  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings("@drawable/ic_notification");
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onTap,
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
    _initialized = true;

    // Listen to FCM messages while app is in foreground — show as local notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final n = message.notification;
      if (n != null) {
        final safeTitle = (n.title?.isNotEmpty ?? false) ? n.title! : "Go Rider";
        final safeBody  = (n.body?.isNotEmpty ?? false) ? n.body! : "Tienes una nueva notificación";
        // Pass full FCM data as JSON payload so _onTap can navigate directly
        final payload = jsonEncode(message.data);
        await show(title: safeTitle, body: safeBody, payload: payload);
      }
    });
  }

  // Ruta pendiente cuando la app se abre desde una notificación (app cerrada)
  static String? pendingRoute;

  // Tap en una notificación local → navega directo a la oferta o al payload.
  static void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    // ¿Payload JSON con datos de FCM?
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final route = data["route"] as String?;
      final orderId = data["order_id"] as String?;
      if (route == "notifications" && orderId != null && orderId.isNotEmpty) {
        // Navegar directo a la pantalla de oferta con los datos de la notificación
        openOffer(orderId, data);
        return;
      }
      if (route != null) {
        openOffers();
        return;
      }
    } catch (_) { /* no es JSON, seguir con payload clásico */ }
    if (payload == "notifications") {
      openOffers();
    } else {
      try {
        appRouter.push(payload);
      } catch (_) {
        pendingRoute = payload;
      }
    }
  }

  // Navega a la pantalla de ofertas abriendo el diálogo de la más reciente
  static void openOffers() {
    try {
      appRouter.push("/notifications?open=1");
    } catch (_) {
      pendingRoute = "/notifications?open=1";
      // App puede estar reanudándose; reintentar tras breve delay
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          appRouter.push("/notifications?open=1");
          pendingRoute = null;
        } catch (_) {}
      });
    }
  }

  // Navega directo a la tarjeta de oferta con los datos del FCM
  static void openOffer(String orderId, Map<String, dynamic> data) {
    try {
      appRouter.push("/notifications?open=1&order_id=$orderId");
    } catch (_) {
      // Fallback: abrir notificaciones
      openOffers();
    }
  }

  static Future<void> requestPermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    if (!_initialized) await init();
    // Request Android 13+ permission
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    // Request FCM permission (iOS + Android 13+)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await init();
    final id = ++_idCounter;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: "@drawable/ic_notification",
          color: const Color(0xFFFF6B35),
        ),
      ),
      payload: payload,
    );
  }
}
