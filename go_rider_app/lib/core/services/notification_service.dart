import "package:flutter_local_notifications/flutter_local_notifications.dart";

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _permissionRequested = false;

  static const _channelId = "go_rider_channel";
  static const _channelName = "Go Rider Notificaciones";
  static int _idCounter = 0;

  static Future<void> init() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings("@mipmap/ic_launcher");
    await _plugin.initialize(const InitializationSettings(android: androidSettings));
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: "Pedidos, mensajes y alertas para repartidores",
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
    _initialized = true;
  }

  // Call this from a visible screen (Activity in foreground) so the dialog appears
  static Future<void> requestPermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    if (!_initialized) await init();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
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
        ),
      ),
      payload: payload,
    );
  }
}
