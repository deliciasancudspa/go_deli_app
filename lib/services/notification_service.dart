import "dart:async";
import "dart:ui" show Color;
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../config/app_routes.dart";

class NotificationService {
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;
  NotificationService._();

  /// Datos FCM pendientes de procesar cuando la app fue abierta desde cerrada
  static Map<String, dynamic>? pendingFcmData;

  final _plugin = FlutterLocalNotificationsPlugin();
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _chatChannel;
  final Map<String, String> _lastOrderStatus = {};
  bool _initialized = false;

  final _controller = StreamController<void>.broadcast();
  Stream<void> get onNewNotification => _controller.stream;

  static const _channelId          = "go_deli_orders";
  static const _channelName        = "Pedidos Go Deli";
  static const _channelDesc        = "Actualizaciones en tiempo real de tus pedidos";
  static const _chatChannelId      = "go_deli_chat";
  static const _chatChannelName    = "Chat Go Deli";
  static const _chatChannelDesc    = "Mensajes del chat con el repartidor";

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
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _chatChannelId, _chatChannelName,
      description: _chatChannelDesc,
      importance: Importance.high,
      playSound: true,
    ));

    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings("@drawable/ic_notification"),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    // Request FCM permission
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);

    // FCM messages in foreground:
    // - If the message has a proper notification field → show it
    // - If data-only, try to derive status from data.payload or skip (Realtime handles it)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final n = message.notification;
      final data = message.data;

      // Prefer the notification field when it has text
      if (n != null && (n.body?.isNotEmpty ?? false)) {
        await show(n.title ?? "Go Deli", n.body!, orderId: data["order_id"]);
        _controller.add(null);
        return;
      }

      // Data-only push: extract status from data to build the notification
      final status = data["status"] as String?;
      if (status != null && status.isNotEmpty) {
        final msg = _statusMessages[status];
        if (msg != null) {
          await show(msg[0], msg[1], orderId: data["order_id"]);
          _controller.add(null);
        }
      }
    });
  }

  // Dedupe: evita que el listener Realtime y el push FCM generen el mismo
  // aviso dos veces para un mismo cambio de estado en una misma orden.
  String? _lastShownKey;
  DateTime? _lastShownAt;

  Future<void> show(String title, String body, {String? orderId}) async {
    // Include orderId in dedupe key so different orders with the same status
    // both show notifications (e.g., two orders both going to "preparing")
    final key = orderId != null ? "$orderId|$title|$body" : "$title|$body";
    if (_lastShownKey == key &&
        _lastShownAt != null &&
        DateTime.now().difference(_lastShownAt!) < const Duration(seconds: 10)) {
      return;
    }
    _lastShownKey = key;
    _lastShownAt = DateTime.now();

    // Sanity: never show a notification with empty title AND body
    final safeTitle = title.isNotEmpty ? title : "Go Deli";
    final safeBody  = body.isNotEmpty ? body : "Toca para ver los detalles";

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      safeTitle,
      safeBody,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: "@drawable/ic_notification",
          color: const Color(0xFFFF6B35),
          styleInformation: BigTextStyleInformation(safeBody),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: orderId != null ? "/tracking/$orderId" : null,
    );
  }

  static void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      appRouter.push(payload);
    } catch (_) {}
  }

  Future<void> showChat(String title, String body, String orderId) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _chatChannelId, _chatChannelName,
          channelDescription: _chatChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: "@drawable/ic_notification",
          color: const Color(0xFFFF6B35),
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: "/chat/$orderId",
    );
  }

  void startChatListener(String userId) {
    _chatChannel?.unsubscribe();
    _chatChannel = Supabase.instance.client
      .channel("notif_chat_$userId")
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: "public",
        table: "chat_messages",
        callback: (payload) {
          final rec = payload.newRecord;
          if ((rec["receiver_id"] as String?) != userId) return;
          final orderId = rec["order_id"] as String?;
          if (orderId == null) return;
          final senderType = rec["sender_type"] as String? ?? "";
          if (senderType == "client") return;
          final msg = rec["message"] as String? ?? "";
          showChat("💬 Repartidor", msg, orderId);
          _controller.add(null);
        },
      ).subscribe();
  }

  void stopChatListener() {
    _chatChannel?.unsubscribe();
    _chatChannel = null;
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
          if (msg != null) {
            show(msg[0], msg[1], orderId: orderId);
            _controller.add(null);
          }
        },
      ).subscribe();
  }

  void stopOrderListener() {
    _ordersChannel?.unsubscribe();
    _ordersChannel = null;
  }
}
