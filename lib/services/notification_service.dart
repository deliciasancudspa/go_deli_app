import "dart:async";
import "dart:ui" show Color;
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:supabase_flutter/supabase_flutter.dart";

class NotificationService {
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  RealtimeChannel? _ordersChannel;
  final Map<String, String> _lastOrderStatus = {};
  bool _initialized = false;

  final _controller = StreamController<void>.broadcast();
  Stream<void> get onNewNotification => _controller.stream;

  static const _channelId   = "go_deli_orders";
  static const _channelName = "Pedidos Go Deli";

  static const _statusMessages = {
    "accepted":   ["✅ Pedido confirmado",        "El restaurante aceptó tu pedido"],
    "preparing":  ["👨‍🍳 Preparando tu pedido",    "El restaurante está preparando tu pedido"],
    "ready":      ["🎉 ¡Pedido listo!",            "Tu pedido está listo para ser recogido"],
    "assigned":   ["🛵 Repartidor asignado",       "Un repartidor está en camino al restaurante"],
    "picked_up":  ["📦 Pedido recogido",           "El repartidor ya tiene tu pedido"],
    "on_the_way": ["🚀 ¡En camino!",              "Tu pedido está en camino hacia ti"],
    "delivered":  ["🏁 ¡Entregado!",              "¡Buen provecho! Tu pedido fue entregado"],
    "cancelled":  ["❌ Pedido cancelado",          "Tu pedido fue cancelado"],
  };

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId, _channelName,
      description: "Actualizaciones en tiempo real de tus pedidos",
      importance: Importance.high,
      playSound: true,
    ));

    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings("@drawable/ic_notification"),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    ));

    // Request FCM permission
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

    // Show FCM messages as local notifications when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final n = message.notification;
      if (n != null) {
        await show(n.title ?? "Go Deli", n.body ?? "");
        _controller.add(null);
      }
    });
  }

  // Dedupe: el listener Realtime y el push FCM generan el mismo aviso para
  // un cambio de estado; solo se muestra una vez.
  String? _lastShownKey;
  DateTime? _lastShownAt;

  Future<void> show(String title, String body) async {
    final key = "$title|$body";
    if (_lastShownKey == key &&
        _lastShownAt != null &&
        DateTime.now().difference(_lastShownAt!) < const Duration(seconds: 10)) {
      return;
    }
    _lastShownKey = key;
    _lastShownAt = DateTime.now();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: "@drawable/ic_notification",
          color: Color(0xFFFF6B35),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  void startOrderListener(String userId) {
    _ordersChannel?.unsubscribe();
    _ordersChannel = Supabase.instance.client
      .channel("notif_orders_$userId")
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: "public",
        table: "orders",
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: "client_id",
          value: userId,
        ),
        callback: (payload) {
          final status = payload.newRecord["status"] as String?;
          final orderId = payload.newRecord["id"] as String?;
          if (status == null || orderId == null) return;
          // Solo notificar cuando el ESTADO cambia — los pedidos se actualizan
          // también por otros campos (rider, códigos, etc.)
          if (_lastOrderStatus[orderId] == status) return;
          _lastOrderStatus[orderId] = status;
          final msg = _statusMessages[status];
          if (msg != null) { show(msg[0], msg[1]); _controller.add(null); }
        },
      ).subscribe();
  }

  void stopOrderListener() {
    _ordersChannel?.unsubscribe();
    _ordersChannel = null;
  }
}
