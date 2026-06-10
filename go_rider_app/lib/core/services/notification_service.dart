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
      description: "Pedidos, mensajes y alertas para repartidores",
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
    _initialized = true;

    // Listen to FCM messages while app is in foreground — show as local notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final n = message.notification;
      if (n != null) {
        await show(title: n.title ?? "Go Rider", body: n.body ?? "", payload: "notifications");
      }
    });
  }

  // Ruta pendiente cuando la app se abre desde una notificación (app cerrada)
  static String? pendingRoute;

  // Tap en una notificación local → abrir las ofertas con el diálogo
  // de aceptar/rechazar directamente.
  static void _onTap(NotificationResponse response) {
    if (response.payload == "notifications") {
      openOffers();
    }
  }

  // Navega a la pantalla de ofertas abriendo el diálogo de la más reciente
  static void openOffers() {
    try {
      appRouter.push("/notifications?open=1");
    } catch (_) {
      pendingRoute = "/notifications?open=1";
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
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: "@drawable/ic_notification",
          color: Color(0xFFFF6B35),
        ),
      ),
      payload: payload,
    );
  }
}
