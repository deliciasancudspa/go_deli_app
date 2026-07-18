import "dart:async";
import "dart:convert" show jsonEncode, jsonDecode;
import "dart:math" as math;
import "dart:typed_data";
import "dart:ui" show Color;
import "package:audioplayers/audioplayers.dart";
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

  // ── Alarm / persistent offer sound ────────────────────────────────────────
  static AudioPlayer? _alarmPlayer;
  static Timer? _alarmAutoStopTimer;
  static final Set<String> _activeOfferIds = {};
  static bool _alarmPlaying = false;
  static Uint8List? _cachedAlarmWav;
  static int _persistentNotifId = -1;

  /// Timeout en segundos para la oferta (coincide con _kTimeout en
  /// notifications_screen.dart y v_timeout en dispatch_engine.sql).
  static const int offerTimeoutSecs = 45;

  // ── Init ──────────────────────────────────────────────────────────────────

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
        final payload = jsonEncode(message.data);

        // ¿Es una oferta de pedido?
        final isOffer = message.data["route"] == "notifications" &&
            (message.data["order_id"]?.isNotEmpty ?? false);
        if (isOffer) {
          await showOffer(
            title: safeTitle,
            body: safeBody,
            orderId: message.data["order_id"]!,
            payload: payload,
          );
        } else {
          await show(title: safeTitle, body: safeBody, payload: payload);
        }
      }
    });
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  /// Ruta pendiente cuando la app se abre desde una notificación (app cerrada)
  static String? pendingRoute;

  static void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    // ¿Payload JSON con datos de FCM?
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final route = data["route"] as String?;
      final orderId = data["order_id"] as String?;
      if (route == "notifications" && orderId != null && orderId.isNotEmpty) {
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

  static void openOffers() {
    try {
      appRouter.push("/notifications?open=1");
    } catch (_) {
      pendingRoute = "/notifications?open=1";
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          appRouter.push("/notifications?open=1");
          pendingRoute = null;
        } catch (_) {}
      });
    }
  }

  static void openOffer(String orderId, Map<String, dynamic> data) {
    try {
      appRouter.push("/notifications?open=1&order_id=$orderId");
    } catch (_) {
      openOffers();
    }
  }

  // ── Permissions ───────────────────────────────────────────────────────────

  static Future<void> requestPermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    if (!_initialized) await init();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // ── Standard notification (chat, assigned orders, etc.) ───────────────────

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

  // ── Persistent order-offer notification + looping alarm ───────────────────

  /// Shows a persistent (non-dismissible) notification for an order offer AND
  /// starts the looping alarm sound. The sound keeps playing until
  /// [stopOfferAlarm] is called or the auto-stop timer fires.
  static Future<void> showOffer({
    required String title,
    required String body,
    required String orderId,
    String? payload,
  }) async {
    if (!_initialized) await init();
    _activeOfferIds.add(orderId);

    // Persistent notification — ongoing=true so the user can't swipe it away
    final id = ++_idCounter;
    _persistentNotifId = id;
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          ongoing: true,
          autoCancel: false,
          icon: "@drawable/ic_notification",
          color: Color(0xFFFF6B35),
          category: AndroidNotificationCategory.alarm,
        ),
      ),
      payload: payload,
    );

    // Start the looping alarm sound
    await _startAlarmSound();
  }

  /// Starts the looping alarm audio. Safe to call multiple times — only the
  /// first call actually starts playback; subsequent calls are no-ops.
  static Future<void> _startAlarmSound() async {
    if (_alarmPlaying) return;
    _alarmPlaying = true;

    try {
      _alarmPlayer?.dispose();
      _alarmPlayer = AudioPlayer();
      await _alarmPlayer!.play(BytesSource(_getAlarmWav()));
      _alarmPlayer!.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer!.setVolume(1.0);
    } catch (_) {
      _alarmPlaying = false;
    }

    // Auto-stop: cancela sonido y notificación cuando expire la oferta
    _alarmAutoStopTimer?.cancel();
    _alarmAutoStopTimer = Timer(
      Duration(seconds: offerTimeoutSecs + 5), // 5 s de margen
      () {
        stopOfferAlarm();
        dismissOfferNotifications();
      },
    );
  }

  /// Stops the looping alarm audio. Call when the rider opens the offers screen
  /// or when all offers have been resolved.
  static Future<void> stopOfferAlarm() async {
    _alarmAutoStopTimer?.cancel();
    _alarmAutoStopTimer = null;
    _alarmPlaying = false;
    try {
      await _alarmPlayer?.stop();
    } catch (_) {}
  }

  /// Removes an offer from tracking. If no more active offers remain, stops
  /// the alarm and dismisses all persistent notifications.
  static Future<void> resolveOffer(String orderId) async {
    _activeOfferIds.remove(orderId);
    if (_activeOfferIds.isEmpty) {
      await stopOfferAlarm();
      await dismissOfferNotifications();
    }
  }

  /// Cancels all persistent offer notifications from the system tray.
  static Future<void> dismissOfferNotifications() async {
    if (_persistentNotifId > 0) {
      try {
        await _plugin.cancel(_persistentNotifId);
      } catch (_) {}
      _persistentNotifId = -1;
    }
  }

  /// Cancels ALL local notifications and stops the alarm. Use on sign out.
  static Future<void> cancelAll() async {
    await stopOfferAlarm();
    _activeOfferIds.clear();
    if (_persistentNotifId > 0) {
      try {
        await _plugin.cancel(_persistentNotifId);
      } catch (_) {}
      _persistentNotifId = -1;
    }
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Whether there are active (unresolved) offers being tracked.
  static bool get hasActiveOffers => _activeOfferIds.isNotEmpty;
  static bool get isAlarmPlaying => _alarmPlaying;

  // ── Alarm WAV generation ──────────────────────────────────────────────────

  /// Generates an insistent alarm tone (alternating 800 Hz / 1000 Hz) that
  /// sounds like a phone ringing. Designed to be played in a loop via
  /// [ReleaseMode.loop]. The WAV is cached after the first generation.
  static Uint8List _getAlarmWav() {
    if (_cachedAlarmWav != null) return _cachedAlarmWav!;
    _cachedAlarmWav = _buildAlarmWav();
    return _cachedAlarmWav!;
  }

  /// Builds a ~3-second WAV with an alternating tone pattern:
  ///   400 ms tone A  →  200 ms silence  →  400 ms tone B  →  200 ms silence
  ///   400 ms tone A  →  200 ms silence  →  400 ms tone B  →  400 ms silence (tail)
  /// This creates a "ring-ring … ring-ring" pattern that loops cleanly.
  static Uint8List _buildAlarmWav() {
    const sampleRate = 22050;
    const freqA = 800.0;  // Hz — primer tono
    const freqB = 1000.0; // Hz — segundo tono

    // Patrón: toneA(400ms) + gap(200ms) + toneB(400ms) + gap(200ms) = 1200 ms
    // Repetimos 2 veces = 2400 ms + un poco de cola para que el loop sea limpio
    const toneSamples = 22050 * 400 ~/ 1000; // sampleRate * 400 ms
    const gapSamples  = 22050 * 200 ~/ 1000; // sampleRate * 200 ms
    const totalSamples = (toneSamples + gapSamples) * 4; // 2 ciclos completos

    final d = ByteData(44 + totalSamples * 2);

    // RIFF header
    d.setUint8(0, 0x52); d.setUint8(1, 0x49); d.setUint8(2, 0x46); d.setUint8(3, 0x46);
    d.setUint32(4, 36 + totalSamples * 2, Endian.little);
    d.setUint8(8, 0x57); d.setUint8(9, 0x41); d.setUint8(10, 0x56); d.setUint8(11, 0x45);

    // fmt chunk
    d.setUint8(12, 0x66); d.setUint8(13, 0x6d); d.setUint8(14, 0x74); d.setUint8(15, 0x20);
    d.setUint32(16, 16, Endian.little);
    d.setUint16(20, 1, Endian.little);   // PCM
    d.setUint16(22, 1, Endian.little);   // mono
    d.setUint32(24, sampleRate, Endian.little);
    d.setUint32(28, sampleRate * 2, Endian.little);
    d.setUint16(32, 2, Endian.little);   // block align
    d.setUint16(34, 16, Endian.little);  // bits per sample

    // data chunk
    d.setUint8(36, 0x64); d.setUint8(37, 0x61); d.setUint8(38, 0x74); d.setUint8(39, 0x61);
    d.setUint32(40, totalSamples * 2, Endian.little);

    int offset = 44;
    // 2 ciclos del patrón ring-ring
    for (int cycle = 0; cycle < 2; cycle++) {
      // Tono A (800 Hz) — 400 ms
      _fillTone(d, offset, toneSamples, sampleRate, freqA);
      offset += toneSamples * 2;
      // Silencio — 200 ms
      _fillSilence(d, offset, gapSamples);
      offset += gapSamples * 2;
      // Tono B (1000 Hz) — 400 ms
      _fillTone(d, offset, toneSamples, sampleRate, freqB);
      offset += toneSamples * 2;
      // Silencio — 200 ms
      _fillSilence(d, offset, gapSamples);
      offset += gapSamples * 2;
    }

    return d.buffer.asUint8List();
  }

  static void _fillTone(ByteData d, int offset, int samples, int sampleRate, double freq) {
    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      // Envelope suave al inicio y final del tono para evitar clicks
      double env = 1.0;
      final attackSamples = (sampleRate * 0.02).toInt(); // 20 ms attack
      final releaseSamples = (sampleRate * 0.03).toInt(); // 30 ms release
      if (i < attackSamples) {
        env = i / attackSamples;
      } else if (i >= samples - releaseSamples) {
        env = (samples - i) / releaseSamples;
      }
      final s = (math.sin(2 * math.pi * freq * t) * env * 28000).round().clamp(-32768, 32767);
      d.setInt16(offset + i * 2, s, Endian.little);
    }
  }

  static void _fillSilence(ByteData d, int offset, int samples) {
    for (int i = 0; i < samples; i++) {
      d.setInt16(offset + i * 2, 0, Endian.little);
    }
  }
}
