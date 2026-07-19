import "dart:async";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:geolocator/geolocator.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/services/connectivity_service.dart";
import "../../../core/services/notification_service.dart";
import "../../../core/utils/chile_time.dart";
import "../../../providers/rider_provider.dart";
import "../../../l10n/app_localizations.dart";

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _stats = {};
  final _sb = Supabase.instance.client;
  bool _ordersSubscribed = false;
  bool _chatSubscribed = false;
  String _subscribedRiderId = "";
  String _subscribedUserId = "";
  RiderProvider? _riderRef;
  int _unreadNotifCount = 0;
  StreamSubscription<Position>? _bgGpsSub;
  DateTime _lastGpsSend = DateTime(2000);
  Timer? _realtimeHealthTimer;
  // Live earnings counter
  double? _prevEarned;
  double? _lastDiff;
  DateTime? _lastDiffTime;
  Timer? _diffTimer;
  // Heatmap
  List<Map<String, dynamic>> _heatmapData = [];
  bool _showHeatmap = false;
  Timer? _heatmapTimer;
  String? _heatmapMessage;
  // Challenges
  List<Map<String, dynamic>> _challenges = [];
  bool _challengesLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await NotificationService.requestPermission();
      _riderRef = context.read<RiderProvider>();
      _riderRef!.addListener(_onRiderUpdate);
      _loadStats();
      _loadUnreadCount();
      _subscribeRealtime();
      _riderRef!.loadRatingStats();
      _loadChallenges();
    });
  }

  // Reconnect Realtime channels every time the app comes back to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resubscribeAll();
      _loadUnreadCount();
    }
  }

  void _resubscribeAll() {
    _stopRealtimeHealthCheck();
    if (_subscribedRiderId.isNotEmpty) {
      _sb.channel("rider-orders-$_subscribedRiderId").unsubscribe();
      _sb.channel("rider-notifs-$_subscribedRiderId").unsubscribe();
      _sb.channel("rider-notifs-upd-$_subscribedRiderId").unsubscribe();
    }
    if (_subscribedUserId.isNotEmpty) {
      _sb.channel("rider-chat-$_subscribedUserId").unsubscribe();
    }
    _ordersSubscribed = false;
    _chatSubscribed = false;
    _subscribedRiderId = "";
    _subscribedUserId = "";
    _subscribeRealtime();
  }

  void _onRiderUpdate() {
    if (!mounted) return;
    _loadStats();
    _loadUnreadCount();
    _subscribeRealtime();
    _syncBackgroundGps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _riderRef?.removeListener(_onRiderUpdate);
    _stopBackgroundGps();
    _stopRealtimeHealthCheck();
    _diffTimer?.cancel();
    _stopHeatmapPolling();
    if (_subscribedRiderId.isNotEmpty) {
      _sb.channel("rider-orders-$_subscribedRiderId").unsubscribe();
      _sb.channel("rider-notifs-$_subscribedRiderId").unsubscribe();
      _sb.channel("rider-notifs-upd-$_subscribedRiderId").unsubscribe();
    }
    if (_subscribedUserId.isNotEmpty) _sb.channel("rider-chat-$_subscribedUserId").unsubscribe();
    super.dispose();
  }

  // ── GPS en background mientras el rider está online esperando pedidos ──

  void _syncBackgroundGps() {
    final rider = context.read<RiderProvider>();
    if (rider.isOnline && _bgGpsSub == null) {
      _startBackgroundGps();
      _startHeatmapPolling();
    } else if (!rider.isOnline && _bgGpsSub != null) {
      _stopBackgroundGps();
      _stopHeatmapPolling();
    }
  }

  void _startBackgroundGps() {
    _stopBackgroundGps();
    debugPrint('[GoRider] Dashboard GPS stream iniciado');
    _lastGpsSend = DateTime(2000); // forzar primer envío inmediato
    _bgGpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    ).listen((pos) async {
      if (!mounted) return;
      final rider = context.read<RiderProvider>();
      if (!rider.isOnline) {
        _stopBackgroundGps();
        return;
      }
      // Throttle: enviar cada 45s, pero el stream sigue vivo → foreground service notification visible
      final now = DateTime.now();
      if (now.difference(_lastGpsSend).inSeconds < 45) return;
      _lastGpsSend = now;
      try {
        await rider.sendLocation(pos.latitude, pos.longitude);
      } catch (e) {
        debugPrint('[GoRider] Dashboard stream GPS: $e');
      }
    }, onError: (e) {
      debugPrint('[GoRider] Dashboard GPS stream error: $e');
    });
  }

  void _stopBackgroundGps() {
    if (_bgGpsSub != null) {
      _bgGpsSub!.cancel();
      _bgGpsSub = null;
      debugPrint('[GoRider] Dashboard GPS stream detenido');
    }
  }

  // ── Mapa de calor ─────────────────────────────────────────────────────────
  Future<void> _loadHeatmap() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty || !rider.isOnline) {
      if (mounted) {
        setState(() => _heatmapMessage = AppLocalizations.of(context)!.heatmapNeedOnline);
        _showHeatmap = false; // revertir toggle, no hay nada que mostrar
      }
      return;
    }
    try {
      final riderData = rider.rider;
      final communeId = riderData?["commune_id"] as String?;
      final data = await _sb.rpc("get_heatmap_data", params: {"p_commune_id": communeId});
      final list = List<Map<String, dynamic>>.from(data as List);
      if (mounted) {
        setState(() {
          _heatmapData = list;
          _heatmapMessage = list.isEmpty ? AppLocalizations.of(context)!.heatmapNoData : null;
          if (list.isEmpty) _showHeatmap = false; // revertir si no hay datos
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _heatmapMessage = AppLocalizations.of(context)!.heatmapError;
          _showHeatmap = false;
        });
      }
    }
  }

  void _startHeatmapPolling() {
    _heatmapTimer?.cancel();
    _heatmapTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadHeatmap());
    _loadHeatmap();
  }

  void _stopHeatmapPolling() {
    _heatmapTimer?.cancel();
    _heatmapTimer = null;
  }

  Future<void> _loadChallenges() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) return;
    try {
      final data = await _sb.rpc("get_active_challenges", params: {"p_rider_id": rider.riderId});
      if (mounted) setState(() { _challenges = List<Map<String, dynamic>>.from(data as List); _challengesLoaded = true; });
    } catch (_) {}
  }

  // ── Realtime health check — reconecta canales si se caen ──

  void _startRealtimeHealthCheck() {
    _stopRealtimeHealthCheck();
    _realtimeHealthTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final rider = context.read<RiderProvider>();
      if (!rider.isOnline) return;
      // Verificar que los canales sigan vivos haciendo un ping ligero a la BD.
      // Si falla, significa que la conexión se perdió y hay que reconectar.
      try {
        _sb.from("orders").select("id").limit(1).then((_) {
          // Canal vivo, no hacer nada
        }).catchError((_) {
          debugPrint('[GoRider] Realtime ping falló — reconectando...');
          _resubscribeAll();
        });
      } catch (_) {
        _resubscribeAll();
      }
    });
  }

  void _stopRealtimeHealthCheck() {
    _realtimeHealthTimer?.cancel();
    _realtimeHealthTimer = null;
  }

  Future<void> _loadUnreadCount() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) return;
    try {
      final data = await _sb.from("notifications")
          .select("id")
          .eq("type", "order_offer")
          .eq("target", rider.riderId)
          .eq("is_read", false);
      if (mounted) setState(() => _unreadNotifCount = (data as List).length);
    } catch (_) {}
  }

  double _riderFeeForOrder(Map<String, dynamic> o) {
    // rider_fee es calculado al crear la orden (checkout) y garantizado por el
    // trigger calculate_order_fees(). Solo puede ser null/0 en delivery propio,
    // donde el rider de GoRider no participa.
    return (o["rider_fee"] as num?)?.toDouble() ?? 0;
  }

  Future<void> _loadStats() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) return;
    final today = ChileTime.todayString();
    try {
      final orders = await _sb.from("orders").select("total, rider_fee, tip_amount, payment_method, status").eq("deliverer_id", rider.riderId).gte("created_at", today);
      final list = List<Map<String, dynamic>>.from(orders);
      final delivered = list.where((o) => o["status"] == "delivered").toList();

      // Total ganado = suma de rider_fee + propinas de todos los pedidos entregados
      final totalEarned = delivered.fold(0.0, (s, o) => s + _riderFeeForOrder(o) + ((o["tip_amount"] as num?)?.toDouble() ?? 0));

      // Ganancias por pedidos en efectivo (el rider ya tiene este dinero en su bolsillo)
      final cashEarnings = delivered
          .where((o) => o["payment_method"] == "cash")
          .fold(0.0, (s, o) => s + _riderFeeForOrder(o));

      // A depositar = solo ganancias de pedidos con tarjeta (la plataforma debe transferirlas)
      final toDeposit = totalEarned - cashEarnings;

      // Total de efectivo que el rider cobró a clientes (incluye lo que debe rendir a la plataforma)
      final cashHandled = delivered
          .where((o) => o["payment_method"] == "cash")
          .fold(0.0, (s, o) => s + ((o["total"] as num?)?.toDouble() ?? 0));

      // Lo que el rider debe rendir a la plataforma del efectivo cobrado
      final toRemit = cashHandled - cashEarnings;

      if (mounted) {
        // Live earnings: detect new earnings
        if (_prevEarned != null && totalEarned > _prevEarned!) {
          _lastDiff = totalEarned - _prevEarned!;
          _lastDiffTime = DateTime.now();
          _diffTimer?.cancel();
          _diffTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) setState(() { _lastDiff = null; _lastDiffTime = null; });
          });
        }
        _prevEarned = totalEarned;
        setState(() {
          _stats = {
            "orders": delivered.length,
            "earned": totalEarned,
            "toDeposit": toDeposit,
            "toRemit": toRemit,
            "cashEarnings": cashEarnings,
          };
        });
      }
    } catch (_) {}
  }

  void _subscribeRealtime() {
    final rider = context.read<RiderProvider>();

    // Orders + notifications: set up once when riderId is available
    if (!_ordersSubscribed && rider.riderId.isNotEmpty) {
      _ordersSubscribed = true;
      _subscribedRiderId = rider.riderId;
      final riderId = rider.riderId;
      try {
        // Orders subscription keeps server-side filter (performance)
        _sb.channel("rider-orders-$riderId").onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: "public",
          table: "orders",
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "deliverer_id", value: riderId),
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            final orderId = rec["id"] as String?;
            final status = rec["status"] as String?;
            // Limpiar notificación/alarma si el pedido fue cancelado o completado
            if (status == "cancelled" || status == "delivered" || status == "rejected") {
              if (orderId != null) NotificationService.resolveOffer(orderId);
            }
            context.read<RiderProvider>().loadActiveOrders();
            _loadStats();
            if (status == "assigned") {
              NotificationService.show(title: "🛵 Nuevo pedido asignado", body: "Tienes un nuevo pedido. Revisa los detalles.");
            }
          },
        ).subscribe();
        // Notifications: no server-side filter to avoid silent Realtime filter failures.
        // Filter client-side in callback.
        _sb.channel("rider-notifs-$riderId").onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: "public",
          table: "notifications",
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            if ((rec["target"] as String?) != riderId) return;  // client-side filter
            context.read<RiderProvider>().loadActiveOrders();
            _loadStats();
            _loadUnreadCount();
            final emoji = rec["emoji"] as String? ?? "";
            final title = rec["title"] as String? ?? "Go Rider";
            final msg   = rec["message"] as String? ?? "";
            final type   = rec["type"] as String? ?? "";
            final data   = rec["data"] as Map<String, dynamic>?;
            final orderId = data?["order_id"] as String?;

            // Order offers → persistent notification with looping alarm
            if (type == "order_offer" && orderId != null && orderId.isNotEmpty) {
              NotificationService.showOffer(
                title: "$emoji $title",
                body: msg,
                orderId: orderId,
              );
            } else {
              NotificationService.show(title: "$emoji $title", body: msg);
            }
          },
        ).subscribe();
        // Second subscription: UPDATE on notifications to detect when backend
        // marks an offer as read (order taken by another rider, cancelled, etc.)
        _sb.channel("rider-notifs-upd-$riderId").onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: "public",
          table: "notifications",
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            if ((rec["target"] as String?) != riderId) return;
            final isRead = rec["is_read"] as bool?;
            final type = rec["type"] as String?;
            final data = rec["data"] as Map<String, dynamic>?;
            final orderId = data?["order_id"] as String?;
            // If an order_offer was marked as read (expired, taken, cancelled),
            // dismiss the persistent notification and stop the alarm for it.
            if (isRead == true && type == "order_offer" && orderId != null) {
              NotificationService.resolveOffer(orderId);
            }
          },
        ).subscribe();
      } catch (_) { _ordersSubscribed = false; _subscribedRiderId = ""; }
      // Iniciar health check de Realtime una vez suscritos los canales
      _startRealtimeHealthCheck();
    }

    // Chat: receiver_id stores users.id — set up separately when user loads
    if (!_chatSubscribed) {
      final userId = rider.user?["id"] as String? ?? "";
      if (userId.isNotEmpty) {
        _chatSubscribed = true;
        _subscribedUserId = userId;
        try {
          // Chat: no server-side filter — filter client-side
          _sb.channel("rider-chat-$userId").onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: "public",
            table: "chat_messages",
            callback: (payload) {
              if (!mounted) return;
              final rec = payload.newRecord;
              if ((rec["receiver_id"] as String?) != userId) return;
              final orderId = rec["order_id"] as String?;
              if (orderId == null) return;
              final msg = rec["message"] as String? ?? "";
              NotificationService.show(
                title: "💬 Mensaje del cliente",
                body: msg,
                payload: "/chat/$orderId",
              );
            },
          ).subscribe();
        } catch (_) { _chatSubscribed = false; _subscribedUserId = ""; }
      }
    }
  }

  String _fmt(double n) => "\$${n.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  Future<void> _confirmExit(BuildContext ctx) async {
    final shouldExit = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text("Salir de Go Rider"),
        content: const Text("¿Deseas salir de la aplicación?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(AppLocalizations.of(ctx)!.cancel)),
          TextButton(onPressed: () => Navigator.pop(dCtx, true),  child: const Text("Salir")),
        ],
      ),
    );
    if (shouldExit == true) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    final tc = ThemeColors.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _confirmExit(context); },
      child: Scaffold(
      backgroundColor: tc.background,
      body: SafeArea(child: Column(children: [
        // Banner de desconexión
        ValueListenableBuilder<bool>(
          valueListenable: ConnectivityService.instance.isOnline,
          builder: (ctx, online, _) {
            if (online) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.red.shade700,
              child: Row(children: [
                const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(AppLocalizations.of(ctx)!.dashboardOfflineBanner, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
            );
          },
        ),
        Container(color: AppColors.primary, padding: const EdgeInsets.all(20), child: Column(children: [
          Row(children: [
            CircleAvatar(radius: 24, backgroundColor: AppColors.accent, child: Text(rider.riderName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLocalizations.of(context)!.dashboardHello(rider.riderName.split(" ")[0]), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              Row(children: [
                Text(rider.isOnline ? AppLocalizations.of(context)!.dashboardOnline : AppLocalizations.of(context)!.dashboardOffline, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                if (rider.ratingStats != null) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.star, color: Colors.amber.shade300, size: 14),
                  const SizedBox(width: 3),
                  Text("${rider.ratingStats!["avg_rating"]}", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w700)),
                  Text(" (${rider.ratingStats!["total_ratings"]})", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                ],
              ]),
            ])),
            GestureDetector(
              onTap: () async {
                await context.push("/notifications");
                if (mounted) _loadUnreadCount();
              },
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
                child: Stack(clipBehavior: Clip.none, children: [
                  const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
                  if (_unreadNotifCount > 0)
                    Positioned(
                      right: -2, top: -2,
                      child: Container(
                        width: 9, height: 9,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            GestureDetector(
              onTap: () async {
                final error = await rider.toggleOnline(context);
                _loadStats();
                if (error != null && mounted) {
                  final loc = AppLocalizations.of(context)!;
                  final msg = error == "gps_off" ? loc.toggleOnlineGpsOff : loc.toggleOnlineLocationDenied;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: AppColors.warning, behavior: SnackBarBehavior.floating),
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 64, height: 32,
                decoration: BoxDecoration(color: rider.isOnline ? AppColors.success : Colors.white24, borderRadius: BorderRadius.circular(16)),
                child: Stack(children: [
                  AnimatedPositioned(duration: const Duration(milliseconds: 300), left: rider.isOnline ? 34 : 2, top: 2, child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                ]),
              ),
            ),
          ]),
          if (!rider.isOnline) ...[
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.info_outline, color: Colors.white54, size: 18), const SizedBox(width: 8), Expanded(child: Text(AppLocalizations.of(context)!.dashboardActivateOnline, style: const TextStyle(color: Colors.white70, fontSize: 13)))])),
          ],
        ])),
        Expanded(child: RefreshIndicator(
          onRefresh: () async { await _loadStats(); await rider.loadActiveOrders(); },
          color: AppColors.accent,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(AppLocalizations.of(context)!.dashboardTodaySummary, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _kpi(AppLocalizations.of(context)!.dashboardOrders, "${_stats["orders"] ?? 0}", Icons.delivery_dining, AppColors.accent)),
              const SizedBox(width: 12),
              Expanded(child: Stack(clipBehavior: Clip.none, children: [
                _kpi(AppLocalizations.of(context)!.dashboardEarned, _fmt((_stats["earned"] ?? 0).toDouble()), Icons.attach_money, AppColors.success),
                if (_lastDiff != null)
                  Positioned(top: -6, right: -4, child: AnimatedOpacity(
                    opacity: _lastDiff != null ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 400),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: AppColors.success.withOpacity(0.4), blurRadius: 8)],
                      ),
                      child: Text("+${_fmt(_lastDiff!)}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  )),
              ])),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _kpi(AppLocalizations.of(context)!.dashboardToReceive, _fmt((_stats["toDeposit"] ?? 0).toDouble()), Icons.account_balance_outlined, AppColors.info)),
              const SizedBox(width: 12),
              Expanded(child: _kpi(AppLocalizations.of(context)!.dashboardToRemit, _fmt((_stats["toRemit"] ?? 0).toDouble()), Icons.swap_horiz, AppColors.warning)),
            ]),
            const SizedBox(height: 24),
            // ── Mapa de calor: resumen de demanda ──
            if (_heatmapData.isNotEmpty && _showHeatmap) _heatmapCard(),
            if (_heatmapMessage != null) _heatmapMessageCard(),
            // ── Desafíos activos ──
            if (_challenges.isNotEmpty) ...[
              Text(AppLocalizations.of(context)!.challengeActive, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ..._challenges.take(3).map((c) => _challengeCard(c)),
              const SizedBox(height: 16),
            ],
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
              Text(AppLocalizations.of(context)!.dashboardActiveOrders, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  final turnOn = !_showHeatmap;
                  setState(() {
                    _showHeatmap = turnOn;
                    _heatmapMessage = null;
                  });
                  if (turnOn) _loadHeatmap();
                },
                child: Text(_showHeatmap ? "Ocultar" : AppLocalizations.of(context)!.dashboardDemand, style: const TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: () => context.push("/performance"),
                child: Text(AppLocalizations.of(context)!.dashboardPerformance, style: const TextStyle(fontSize: 11)),
              ),
            ]),
            ]),
            const SizedBox(height: 8),
            if (rider.activeOrders.isEmpty)
              Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: tc.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: tc.border)), child: Column(children: [
                const Text("🛵", style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(rider.isOnline ? AppLocalizations.of(context)!.dashboardNoOrders : AppLocalizations.of(context)!.dashboardActivateOnline, style: TextStyle(color: tc.textLight, fontWeight: FontWeight.w600)),
              ]))
            else
              ...() {
                // Filter out cancelled/returned orders defensively (should be handled by provider already)
                final activeOnly = rider.activeOrders.where((o) {
                  final s = o["status"] as String?;
                  return s == "assigned" || s == "picked_up" || s == "on_the_way";
                }).toList();
                if (activeOnly.isEmpty) {
                  return [Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(color: tc.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: tc.border)),
                    child: Column(children: [
                      const Text("🛵", style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text(rider.isOnline ? AppLocalizations.of(context)!.dashboardNoOrders : AppLocalizations.of(context)!.dashboardActivateOnline, style: TextStyle(color: tc.textLight, fontWeight: FontWeight.w600)),
                    ]),
                  )];
                }
                final hasAhead = activeOnly.any((o) => o["status"] == "picked_up" || o["status"] == "on_the_way");
                return activeOnly.map((o) => _orderCard(o, context, queued: hasAhead && o["status"] == "assigned"));
              }(),
          ]),
        )),
      ])),
      ),
    );
  }

  static Widget _storeAvatar(String? logoUrl, String? emoji, {double size = 40}) {
    final fallback = Text(emoji ?? "🍽️", style: TextStyle(fontSize: size * 0.55));
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(logoUrl, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    }
    return SizedBox(width: size, height: size, child: Center(child: fallback));
  }

  Widget _heatmapCard() {
    final totalPending = _heatmapData.fold(0, (s, z) => s + ((z["pending_count"] as num?)?.toInt() ?? 0));
    final totalEarnings = _heatmapData.fold(0, (s, z) => s + ((z["potential_earnings"] as num?)?.toInt() ?? 0));
    final hottest = _heatmapData.reduce((a, b) =>
      ((a["pending_count"] as num?)?.toInt() ?? 0) > ((b["pending_count"] as num?)?.toInt() ?? 0) ? a : b);
    final hottestCount = (hottest["pending_count"] as num?)?.toInt() ?? 0;

    final loc2 = AppLocalizations.of(context)!;
    Color levelColor = AppColors.success;
    String levelLabel = loc2.heatmapLow;
    if (hottestCount >= 4) { levelColor = AppColors.error; levelLabel = loc2.heatmapHigh; }
    else if (hottestCount >= 2) { levelColor = AppColors.warning; levelLabel = loc2.heatmapMedium; }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: levelColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: levelColor.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: levelColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.whatshot, color: levelColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("${loc2.heatmapDemand} $levelLabel en tu zona", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: levelColor)),
            const SizedBox(height: 2),
            Text("${loc2.t(loc2.heatmapPendingOrders, {'n': '$totalPending'})} · ~\$${_fmt(totalEarnings.toDouble())} potencial",
                style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
          ]),
        ),
        if (hottestCount >= 4)
          const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
      ]),
    );
  }

  Widget _heatmapMessageCard() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.warning.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.warning.withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.info_outline, color: AppColors.warning, size: 22),
      const SizedBox(width: 12),
      Expanded(child: Text(_heatmapMessage!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMedium))),
      GestureDetector(
        onTap: () => setState(() => _heatmapMessage = null),
        child: const Icon(Icons.close, size: 18, color: AppColors.textLight),
      ),
    ]),
  );

  Widget _challengeCard(Map<String, dynamic> c) {
    final current = (c["current_count"] as num?)?.toInt() ?? 0;
    final target = (c["target_count"] as num?)?.toInt() ?? 1;
    final pct = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final completed = c["completed"] == true;
    final type = c["type"] as String? ?? "mission";
    final emoji = type == "streak" ? "🔥" : type == "badge" ? (c["badge_emoji"] as String? ?? "🏅") : "🎯";
    final color = completed ? AppColors.success : AppColors.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c["title"] as String? ?? "", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: color.withOpacity(0.12),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 2),
            Text("$current/$target · ${completed ? "✅ Completado" : "+\$${c["bonus_amount"] ?? 0}"}",
              style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
          ]),
        ),
      ]),
    );
  }

  Widget _kpi(String label, String value, IconData icon, Color color) {
    final tc = ThemeColors.of(context);
    return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: tc.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: tc.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 22), const SizedBox(height: 8),
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
      Text(label, style: TextStyle(fontSize: 12, color: tc.textLight, fontWeight: FontWeight.w600)),
    ]),
  );
  }

  Widget _orderCard(Map<String, dynamic> o, BuildContext context, {bool queued = false}) {
    final statusColors = {"assigned": AppColors.warning, "picked_up": AppColors.info, "on_the_way": AppColors.accent};
    final loc = AppLocalizations.of(context)!;
    final tc = ThemeColors.of(context);
    final statusLabels = {"assigned": loc.orderPickup, "picked_up": loc.orderDeliver, "on_the_way": loc.orderOnTheWay};
    final color = queued ? AppColors.info : (statusColors[o["status"]] ?? tc.textLight);
    return GestureDetector(
      onTap: () => context.push("/order/${o["id"]}"),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: tc.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.4), width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _storeAvatar(o["stores"]?["logo_url"] as String?, o["stores"]?["emoji"] as String?, size: 40),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o["stores"]?["name"] ?? "", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: tc.textDark)),
              Text(o["stores"]?["address"] ?? "", style: TextStyle(color: tc.textLight, fontSize: 12)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(queued ? loc.orderQueued : (statusLabels[o["status"]] ?? o["status"]), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 14, color: tc.textLight),
            const SizedBox(width: 4),
            Expanded(child: Text(o["delivery_address"] ?? "", style: TextStyle(color: tc.textLight, fontSize: 12))),
            Text("\$${((o["total"] as num?) ?? 0).toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accent)),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => context.push("/order/${o["id"]}"), child: Text(loc.dashboardViewDetails))),
        ]),
      ),
    );
  }
}
