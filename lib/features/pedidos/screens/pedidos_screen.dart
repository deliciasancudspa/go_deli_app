import "dart:async";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:shimmer/shimmer.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

const _kDark   = AppColors.homeDark;
const _kOrange = AppColors.homeOrange;
const _kPurple = AppColors.homePurple;

const _kActiveStatuses  = ["pending_payment","pending","accepted","preparing","ready","assigned","picked_up","on_the_way"];
const _kHistoryStatuses = ["delivered","cancelled","returned"];

// 4-step visual progress: which actual statuses count as "done" for each step
const _kStepDoneWhen = [
  ["accepted","preparing","ready","assigned","picked_up","on_the_way","delivered"],
  ["ready","assigned","picked_up","on_the_way","delivered"],
  ["on_the_way","delivered"],
  ["delivered"],
];
const _kStepLabels = ["Confirmado","Preparando","En camino","Entregado"];
const _kStepEmojis = ["✓","✓","🛵","🏠"];

// ════════════════════════════════════════════════════════════════════════════
class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});
  @override State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen>
    with TickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  String? _userId;

  Map<String, dynamic>? _activeOrder;
  List<Map<String, dynamic>> _orders = [];
  bool _loading     = true;
  bool _loadingMore = false;
  bool _hasMore     = true;
  int  _filterIdx   = 0;
  int  _page        = 0;
  static const _pageSize = 20;

  final _scrollCtrl = ScrollController();
  RealtimeChannel? _channel;

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.35, end: 1.0).animate(_pulseCtrl);
    _scrollCtrl.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scrollCtrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 120) {
      _loadMore();
    }
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (refresh) setState(() { _loading = true; _page = 0; _hasMore = true; _orders = []; });
    try {
      final user = _sb.auth.currentUser;
      if (user == null) { if (mounted) setState(() => _loading = false); return; }
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).maybeSingle();
      if (u == null) { if (mounted) setState(() => _loading = false); return; }
      _userId = u["id"] as String;
      await Future.wait([_loadActive(), _loadHistory(reset: true)]);
      _subscribeRealtime();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadActive() async {
    if (_userId == null) return;
    try {
      // Carga principal: orden + tienda + items. Sin join a deliverers porque
      // puede no existir aún (orden recién aceptada) y causar que maybeSingle
      // retorne null.
      final res = await _sb.from("orders")
          .select("*, stores(id,name,emoji,is_active,is_open), order_items(menu_item_id,item_name,item_price,quantity)")
          .eq("client_id", _userId!)
          .inFilter("status", _kActiveStatuses)
          .order("created_at", ascending: false)
          .limit(1)
          .maybeSingle();
      if (mounted) setState(() => _activeOrder = res);
    } catch (e) {
      debugPrint("[Pedidos] _loadActive error: $e");
    }
  }

  Future<void> _loadHistory({bool reset = false}) async {
    if (_userId == null) return;
    final offset = reset ? 0 : _page * _pageSize;
    try {
      final raw = await _sb.from("orders")
          .select("*, stores(id,name,emoji), order_items(menu_item_id,item_name,item_price,quantity)")
          .eq("client_id", _userId!)
          .inFilter("status", _kHistoryStatuses)
          .order("created_at", ascending: false)
          .range(offset, offset + _pageSize - 1);
      final list = List<Map<String, dynamic>>.from(raw as List);
      if (mounted) setState(() {
        if (reset) _orders = list; else _orders.addAll(list);
        _hasMore = list.length == _pageSize;
        if (reset) _page = 1; else _page++;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    // _page se incrementa dentro de _loadHistory (reset=false).
    // No incrementar aquí para evitar saltar páginas.
    await _loadHistory();
    if (mounted) setState(() => _loadingMore = false);
  }

  void _subscribeRealtime() {
    if (_userId == null) return;
    _channel?.unsubscribe();
    _channel = _sb.channel("orders-client-$_userId")
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: "public", table: "orders",
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq, column: "client_id", value: _userId!),
          callback: (_) {
            // Solo recargar la orden activa. El historial no se resetea para
            // no perder la posición de scroll/paginación del usuario.
            _loadActive();
          },
        ).subscribe();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _fmtDate(String? d) {
    if (d == null) return "";
    final dt = DateTime.parse(d).toLocal();
    const m = ["ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"];
    return "${dt.day} ${m[dt.month-1]} · ${dt.hour.toString().padLeft(2,"0")}:${dt.minute.toString().padLeft(2,"0")}";
  }

  String _fmt(num p) =>
      "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  String _orderNum(String id) => "#${id.substring(0, 6).toUpperCase()}";

  List<Map<String, dynamic>> get _filtered {
    switch (_filterIdx) {
      case 1: return [];
      case 2: return _orders.where((o) => o["status"] == "delivered").toList();
      case 3: return _orders.where((o) => o["status"] == "cancelled").toList();
      case 4: return _orders.where((o) => o["status"] == "returned").toList();
      default: return _orders;
    }
  }

  bool get _showActive => _activeOrder != null && (_filterIdx == 0 || _filterIdx == 1);

  // ── Root build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasActive = _activeOrder != null;
    return Scaffold(
      backgroundColor: AppColors.homeBackground,
      body: RefreshIndicator(
        onRefresh: () => _loadData(refresh: true),
        color: _kOrange,
        child: CustomScrollView(controller: _scrollCtrl, slivers: [
          // Header
          SliverAppBar(
            pinned: true, automaticallyImplyLeading: false,
            backgroundColor: Colors.transparent,
            flexibleSpace: const GradientFlexibleSpace(),
            toolbarHeight: 56,
            title: Row(children: [
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Mis pedidos", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, fontFamily: "Nunito")),
                  Text("Historial",   style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: "Nunito")),
                ],
              )),
              if (hasActive) _buildActiveBadge(),
            ]),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(46),
              child: SizedBox(height: 46, child: _buildFilterTabs()),
            ),
          ),

          // Body
          if (_loading)
            SliverList(delegate: SliverChildBuilderDelegate((_, __) => _shimmer(), childCount: 3))
          else ...[
            if (_showActive) SliverToBoxAdapter(child: _buildActiveCard()),
            if (_filtered.isEmpty && !(_showActive))
              SliverToBoxAdapter(child: _buildEmpty())
            else if (_filtered.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildOrderCard(_filtered[i]),
                  childCount: _filtered.length,
                )),
              ),
            if (_loadingMore)
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(color: _kOrange)),
              )),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ]),
      ),
    );
  }

  // ── Active badge (header right) ────────────────────────────────────────
  Widget _buildActiveBadge() => AnimatedBuilder(
    animation: _pulseAnim,
    builder: (_, __) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Opacity(opacity: _pulseAnim.value,
          child: Container(width: 6, height: 6,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
        const SizedBox(width: 5),
        const Text("1 activo", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    ),
  );

  // ── Filter tabs ────────────────────────────────────────────────────────
  Widget _buildFilterTabs() => ListView.builder(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    itemCount: 5,
    itemBuilder: (_, i) {
      const labels = ["Todos","🔄 En curso","✅ Entregados","❌ Cancelados","↩️ Devueltos"];
      final active = _filterIdx == i;
      return GestureDetector(
        onTap: () => setState(() => _filterIdx = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: active ? _kOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? _kOrange : Colors.white.withOpacity(0.15)),
          ),
          child: Text(labels[i], style: TextStyle(
            color: active ? Colors.white : Colors.white.withOpacity(0.55),
            fontSize: 12, fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            fontFamily: "Nunito",
          )),
        ),
      );
    },
  );

  // ════════════════════════════════════════════════════════════════════════
  // ACTIVE ORDER CARD
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildActiveCard() {
    final o      = _activeOrder!;
    final status = o["status"] as String? ?? "pending";
    final store  = o["stores"] as Map<String, dynamic>? ?? {};
    final rider  = o["deliverers"] as Map<String, dynamic>?;
    final riderUser = rider?["users"] as Map<String, dynamic>?;
    final total  = (o["total"] as num?) ?? 0;
    final hasRider = ["assigned","picked_up","on_the_way"].contains(status);
    final isOnTheWay = status == "on_the_way";
    final isPendingPayment = status == "pending_payment";
    final orderType = o["order_type"] as String? ?? "delivery";
    final pickupCode   = o["pickup_code"]   as String?;
    final deliveryCode = o["delivery_code"] as String?;
    // delivery orders: show delivery_code to rider when on_the_way
    // pickup orders:   show pickup_code to store when accepted/preparing/ready
    final showDelivCode  = orderType == "delivery" && isOnTheWay && deliveryCode != null;
    final showPickupCode = orderType == "pickup"   &&
        ["accepted","preparing","ready"].contains(status) && pickupCode != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        gradient: AppColors.mainGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: _kOrange.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Label pulsante
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Row(children: [
              if (!isPendingPayment) ...[
                Opacity(opacity: _pulseAnim.value,
                  child: Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                const SizedBox(width: 6),
              ],
              Text(isPendingPayment
                  ? "⏳ Pago pendiente · ${_orderNum(o["id"] as String)}"
                  : "Pedido en curso · ${_orderNum(o["id"] as String)}",
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("${store["emoji"] ?? "🍽️"}  ${store["name"] ?? ""}",
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
            Text(_fmt(total),
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
          ]),
        ),

        // Progress bar
        _buildProgressBar(status),
        const SizedBox(height: 12),

        // Indicador de pago pendiente (webpay/khipu no confirmado aún)
        if (isPendingPayment)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              const Text("⏳", style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("Esperando confirmación de pago…",
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () => _retryPayment(o),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("Pagar", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),

        // Delivery code: cliente se lo muestra al repartidor cuando llega
        if (showDelivCode) ...[
          _buildCodeBox(context, o["delivery_code"] as String, "🔐", "Tu código de confirmación", "Muéstralo al repartidor cuando llegue"),
        ],
        // Pickup code: cliente se lo muestra en la tienda para retirar
        if (showPickupCode) ...[
          _buildCodeBox(context, o["pickup_code"] as String, "🏪", "Tu código de retiro", "Muéstralo en la tienda para retirar tu pedido"),
        ],

        // Rider + buttons footer
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.15),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Column(children: [
            if (hasRider && riderUser != null) ...[
              Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(child: Text("🛵", style: TextStyle(fontSize: 18)))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(riderUser["name"] ?? "Repartidor",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  if ((rider?["rating"] as num?) != null)
                    Row(children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 13),
                      Text(" ${(rider!["rating"] as num).toStringAsFixed(1)}",
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ]),
                ])),
              ]),
              const SizedBox(height: 10),
            ],
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => context.push("/tracking/${o["id"]}"),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text("📍", style: TextStyle(fontSize: 14)),
                    SizedBox(width: 4),
                    Text("Rastrear", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                  ]),
                ),
              )),
              if (hasRider) ...[
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: () => context.push("/chat/${o["id"]}"),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text("💬", style: TextStyle(fontSize: 14)),
                      SizedBox(width: 4),
                      Text("Chat", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                )),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _buildProgressBar(String status) {
    // Para pending_payment, no mostrar progreso — el pedido aún no ha sido
    // confirmado porque el pago no se ha completado.
    final isPendingPayment = status == "pending_payment";
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: List.generate(4, (i) {
        final done    = isPendingPayment ? false : _kStepDoneWhen[i].contains(status);
        final current = isPendingPayment ? false : (!done && (i == 0 || _kStepDoneWhen[i-1].contains(status)));
        final isLast  = i == 3;
        return Expanded(child: Row(children: [
          Expanded(child: Column(children: [
            // Circle
            AnimatedBuilder(animation: _pulseAnim, builder: (_, __) {
              return Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? Colors.white
                      : current
                          ? Colors.white.withOpacity(_pulseAnim.value * 0.6)
                          : Colors.white.withOpacity(0.15),
                  border: Border.all(
                    color: done || current ? Colors.white : Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Center(child: done
                    ? Text(_kStepEmojis[i],
                        style: TextStyle(fontSize: i < 2 ? 13 : 14,
                            color: i < 2 ? _kOrange : null))
                    : current
                        ? Container(width: 8, height: 8,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))
                        : const SizedBox.shrink()),
              );
            }),
            const SizedBox(height: 4),
            Text(_kStepLabels[i],
                style: TextStyle(
                  color: done ? Colors.white : Colors.white.withOpacity(0.55),
                  fontSize: 9, fontWeight: FontWeight.w700,
                ), textAlign: TextAlign.center),
          ])),
          if (!isLast)
            Expanded(child: Container(
              height: 2, margin: const EdgeInsets.only(bottom: 18),
              color: _kStepDoneWhen[i].contains(status)
                  ? Colors.white
                  : Colors.white.withOpacity(0.25),
            )),
        ]));
      })),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // HISTORY ORDER CARD
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildOrderCard(Map<String, dynamic> o) {
    final status  = o["status"] as String? ?? "delivered";
    final store   = o["stores"] as Map<String, dynamic>? ?? {};
    final items   = (o["order_items"] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total   = (o["total"] as num?) ?? 0;
    final rated   = o["rated"] == true;

    final itemSummary = items.map((i) => "${i["item_name"]}").join(", ");
    final summary = itemSummary.length > 60
        ? "${itemSummary.substring(0, 57)}..."
        : itemSummary;

    return GestureDetector(
      onTap: () => _showDetail(o),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.homeCardBorder),
          boxShadow: [BoxShadow(color: _kPurple.withOpacity(0.05), blurRadius: 8, offset: const Offset(0,3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // A) Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14,14,14,8),
            child: Row(children: [
              Container(width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _kPurple.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(store["emoji"] ?? "🍽️",
                    style: const TextStyle(fontSize: 22)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(store["name"] ?? "",
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textDark),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text("${_fmtDate(o["created_at"] as String?)} · ${items.length} producto${items.length == 1 ? "" : "s"}",
                    style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
              ])),
              const SizedBox(width: 8),
              _statusPill(status),
            ]),
          ),
          // B) Items
          if (summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14,0,14,8),
              child: Text(summary,
                  style: const TextStyle(color: AppColors.textMedium, fontSize: 12),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          // C) Footer
          Container(
            padding: const EdgeInsets.fromLTRB(14,10,14,12),
            decoration: BoxDecoration(
              color: AppColors.homeBackground,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Row(children: [
              Text(_fmt(total),
                  style: const TextStyle(color: _kOrange, fontWeight: FontWeight.w900, fontSize: 16)),
              const Spacer(),
              if (status == "delivered" && !rated)
                _actionBtn("⭐ Calificar", onTap: () => _showRating(o)),
              if (status == "delivered" && !rated) const SizedBox(width: 8),
              if (status == "delivered" || status == "cancelled")
                _actionBtn("🔄 Repetir", filled: false, onTap: () => _repeatOrder(o)),
              if (status == "returned")
                _actionBtn("Ver motivo", filled: false, onTap: () => _showReturnNote(o)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _statusPill(String status) {
    const configs = {
      "delivered": (Color(0xFFE8FFE8), Color(0xFF2A6B2A), "✅ Entregado"),
      "cancelled": (Color(0xFFFFE8E8), Color(0xFF8A0000), "❌ Cancelado"),
      "returned":  (Color(0xFFF3F4F6), Color(0xFF374151), "↩️ Devuelto"),
    };
    final cfg = configs[status];
    if (cfg == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: cfg.$1, borderRadius: BorderRadius.circular(8)),
      child: Text(cfg.$3, style: TextStyle(color: cfg.$2, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _actionBtn(String label, {required VoidCallback onTap, bool filled = true}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? _kOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: filled ? _kOrange : _kOrange.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(
              color: filled ? Colors.white : _kOrange,
              fontSize: 11, fontWeight: FontWeight.w800,
            )),
      ),
    );

  // ── Empty state ────────────────────────────────────────────────────────
  Widget _buildEmpty() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
    child: Column(children: [
      const Text("📦", style: TextStyle(fontSize: 60)),
      const SizedBox(height: 16),
      Text(
        _filterIdx == 0 ? "Aún no tienes pedidos" : "Sin pedidos en este filtro",
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textMedium),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      if (_filterIdx == 0) ...[
        const Text("Explora las tiendas y haz tu primer pedido",
            style: TextStyle(color: AppColors.textLight), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () {
            // pop to HomeScreen tab 0
            if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(12)),
            child: const Text("Explorar tiendas",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    ]),
  );

  // ── Shimmer ────────────────────────────────────────────────────────────
  Widget _shimmer() => Shimmer.fromColors(
    baseColor: const Color(0xFFDDD0F0),
    highlightColor: const Color(0xFFF5F0FF),
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      height: 110,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    ),
  );

  // ════════════════════════════════════════════════════════════════════════
  // ORDER DETAIL SHEET
  // ════════════════════════════════════════════════════════════════════════
  void _showDetail(Map<String, dynamic> o) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetailSheet(order: o, sb: _sb),
    );
  }

  // ── Return note ────────────────────────────────────────────────────────
  void _showReturnNote(Map<String, dynamic> o) {
    final note = o["return_note"] as String? ?? "Sin información disponible";
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Motivo de devolución"),
      content: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.error.withOpacity(0.06), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.error.withOpacity(0.2))),
        child: Text(note, style: const TextStyle(color: AppColors.textMedium, fontSize: 14, height: 1.5)),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cerrar"))],
    ));
  }

  // ── Retry pending payment ────────────────────────────────────────────────
  Future<void> _retryPayment(Map<String, dynamic> order) async {
    final orderId   = order["id"] as String;
    final payMethod = order["payment_method"] as String? ?? "webpay";
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text("Pago pendiente"),
      content: Text(payMethod == "khipu"
          ? "Tu transferencia Khipu aún no ha sido confirmada. ¿Deseas cancelar este pedido y volver a intentarlo?"
          : "El pago con WebPay no se completó. ¿Deseas cancelar este pedido y volver a intentarlo?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
        TextButton(onPressed: () => Navigator.pop(context, true),
          child: const Text("Sí, volver a intentar", style: TextStyle(color: AppColors.error))),
      ],
    ));
    if (confirmed == true) {
      try {
        await _sb.from("orders").update({
          "status": "cancelled",
          "payment_status": "failed",
        }).eq("id", orderId);
      } catch (_) {}
      if (mounted) setState(() { _orders.removeWhere((o) => o["id"] == orderId); _activeOrder = null; });
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // REPEAT ORDER
  // ════════════════════════════════════════════════════════════════════════
  Future<void> _repeatOrder(Map<String, dynamic> o) async {
    final storeId = o["store_id"] as String? ?? (o["stores"] as Map?)?.cast<String, dynamic>()["id"] as String?;
    if (storeId == null) return;

    try {
      final store = await _sb.from("stores")
          .select("id,name,emoji,is_active,is_open").eq("id", storeId).maybeSingle();
      if (store == null || store["is_active"] != true) {
        if (!mounted) return;
        _showSnack("Esta tienda ya no está disponible");
        return;
      }

      final items = ((o["order_items"] as List?)?.cast<Map<String, dynamic>>() ?? []);
      if (items.isEmpty) { if (mounted) context.push("/store/$storeId"); return; }

      final itemIds = items.map((i) => i["menu_item_id"]).whereType<String>().toList();
      if (itemIds.isEmpty) { if (mounted) context.push("/store/$storeId"); return; }

      final menuRaw = await _sb.from("menu_items")
          .select("id,name,price,image_url,is_available")
          .inFilter("id", itemIds);
      final menuItems = List<Map<String, dynamic>>.from(menuRaw as List);
      final available   = menuItems.where((m) => m["is_available"] == true).toList();
      final unavailable = menuItems.where((m) => m["is_available"] != true).toList();

      if (!mounted) return;

      if (available.isEmpty) {
        _showSnack("Ningún producto está disponible ahora");
        return;
      }

      Future<void> doAdd(List<Map<String, dynamic>> toAdd) async {
        final cart = context.read<CartProvider>();
        for (final m in toAdd) {
          final orig = items.firstWhere((i) => i["menu_item_id"] == m["id"], orElse: () => {});
          final qty = (orig["quantity"] as int?) ?? 1;
          for (var i = 0; i < qty; i++) {
            cart.addItem(CartItem(
              id: m["id"] as String,
              storeId: storeId,
              storeName: store["name"] as String? ?? "",
              name: m["name"] as String? ?? orig["item_name"] as String? ?? "",
              price: (m["price"] as num).toInt(),
              imageUrl: m["image_url"] as String?,
            ));
          }
        }
        if (mounted) context.push("/cart");
      }

      if (store["is_open"] == false) {
        final add = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
          title: const Text("Tienda cerrada"),
          content: const Text("Esta tienda está cerrada ahora. ¿Agregar al carrito para cuando abra?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Agregar")),
          ],
        ));
        if (add == true) await doAdd(available);
        return;
      }

      if (unavailable.isNotEmpty) {
        final add = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
          title: const Text("Algunos productos no disponibles"),
          content: Text("${unavailable.length} producto${unavailable.length > 1 ? "s" : ""} ya no ${unavailable.length > 1 ? "están disponibles" : "está disponible"}. ¿Agregar solo los disponibles?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Agregar disponibles")),
          ],
        ));
        if (add == true) await doAdd(available);
        return;
      }

      await doAdd(available);
    } catch (e) {
      if (mounted) _showSnack("Error al repetir pedido: $e");
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ════════════════════════════════════════════════════════════════════════
  // RATING SHEET
  // ════════════════════════════════════════════════════════════════════════
  void _showRating(Map<String, dynamic> o) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _RatingSheet(
        order: o, sb: _sb,
        onSubmitted: () {
          final idx = _orders.indexWhere((x) => x["id"] == o["id"]);
          if (idx >= 0 && mounted) {
            setState(() => _orders[idx] = {..._orders[idx], "rated": true});
          }
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ORDER DETAIL SHEET
// ════════════════════════════════════════════════════════════════════════════
class _OrderDetailSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final SupabaseClient sb;
  const _OrderDetailSheet({required this.order, required this.sb});
  @override State<_OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends State<_OrderDetailSheet> {
  List<Map<String, dynamic>> _fullItems = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final raw = await widget.sb.from("order_items")
          .select("*").eq("order_id", widget.order["id"]);
      if (mounted) setState(() {
        _fullItems = List<Map<String, dynamic>>.from(raw as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(num p) =>
      "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  @override
  Widget build(BuildContext context) {
    final o     = widget.order;
    final store = (o["stores"] as Map<String, dynamic>?) ?? {};
    final status = o["status"] as String? ?? "";
    final returnNote = o["return_note"] as String?;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            Text(store["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(store["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text("Pedido #${(o["id"] as String).substring(0,6).toUpperCase()}",
                  style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
            ])),
          ]),
        ),
        const Divider(height: 1),
        Flexible(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Items
            if (_loading)
              const Center(child: CircularProgressIndicator(color: AppColors.homeOrange))
            else ...[
              const Text("Productos", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 8),
              ..._fullItems.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Text("${item["quantity"]}×", style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textLight, fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item["item_name"] ?? "",
                      style: const TextStyle(fontSize: 13, color: AppColors.textDark))),
                  Text(_fmt((item["item_price"] as num?) ?? 0),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              )),
              const Divider(height: 20),
              _detailRow("Subtotal", _fmt((o["subtotal"] as num?) ?? 0)),
              if ((o["delivery_fee"] as num?) != null && (o["delivery_fee"] as num) > 0)
                _detailRow("Envío", _fmt(o["delivery_fee"] as num)),
              if ((o["discount"] as num?) != null && (o["discount"] as num) > 0)
                _detailRow("Descuento", "-${_fmt(o["discount"] as num)}", color: AppColors.success),
              const Divider(height: 12),
              _detailRow("Total", _fmt((o["total"] as num?) ?? 0),
                  bold: true, color: AppColors.homeOrange),
            ],
            const SizedBox(height: 12),
            if ((o["delivery_address"] as String?)?.isNotEmpty == true) ...[
              const Text("Dirección de entrega",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.location_on_outlined, color: AppColors.textLight, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(o["delivery_address"] as String,
                    style: const TextStyle(color: AppColors.textMedium, fontSize: 13))),
              ]),
              const SizedBox(height: 12),
            ],
            if (returnNote != null && returnNote.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.error.withOpacity(0.2)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Motivo de devolución",
                      style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(returnNote, style: const TextStyle(color: AppColors.textMedium, fontSize: 13, height: 1.5)),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: status == "delivered"
                    ? const Color(0xFFE8FFE8)
                    : status == "cancelled"
                        ? const Color(0xFFFFE8E8)
                        : AppColors.homeBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Text(status == "delivered" ? "✅" : status == "cancelled" ? "❌" : "↩️",
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  status == "delivered" ? "Entregado correctamente"
                      : status == "cancelled" ? "Pedido cancelado"
                          : "Pedido devuelto",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: status == "delivered" ? const Color(0xFF2A6B2A)
                        : status == "cancelled" ? const Color(0xFF8A0000)
                            : AppColors.textMedium,
                  ),
                ),
              ]),
            ),
          ]),
        )),
      ]),
    );
  }

  Widget _detailRow(String label, String value, {bool bold = false, Color? color}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
        Text(value, style: TextStyle(
          fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
          fontSize: bold ? 15 : 13,
          color: color ?? AppColors.textDark,
        )),
      ]),
    );
}

Widget _buildCodeBox(BuildContext context, String code, String icon, String title, String subtitle) =>
  Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(gradient: AppColors.darkGradient, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(code, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 10, fontFamily: "monospace")),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Código copiado")));
          },
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.copy, color: Colors.white54, size: 13),
            SizedBox(width: 4),
            Text("Copiar", style: TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ),
      ]),
    ),
  );

// ════════════════════════════════════════════════════════════════════════════
// RATING SHEET
// ════════════════════════════════════════════════════════════════════════════
class _RatingSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final SupabaseClient sb;
  final VoidCallback onSubmitted;
  const _RatingSheet({required this.order, required this.sb, required this.onSubmitted});
  @override State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int  _storeRating = 5;
  int  _riderRating = 5;
  bool _sending = false;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      final o        = widget.order;
      final storeId  = o["store_id"] as String? ?? (o["stores"] as Map?)?.cast<String, dynamic>()["id"] as String?;
      final delivId  = o["deliverer_id"] as String?;
      String? clientId;
      final user = widget.sb.auth.currentUser;
      if (user != null) {
        final u = await widget.sb.from("users").select("id").eq("auth_id", user.id).maybeSingle();
        clientId = u?["id"] as String?;
      }

      // Insert review
      await widget.sb.from("reviews").insert({
        "order_id":       o["id"],
        if (clientId != null) "client_id": clientId,
        if (storeId  != null) "store_id":  storeId,
        if (delivId  != null) "deliverer_id": delivId,
        "rating_store": _storeRating,
        "rating_rider": _riderRating,
        if (_commentCtrl.text.trim().isNotEmpty) "comment": _commentCtrl.text.trim(),
      });

      // Recalculate store rating
      if (storeId != null) {
        final reviews = await widget.sb.from("reviews")
            .select("rating_store").eq("store_id", storeId);
        final ratings = List<Map<String, dynamic>>.from(reviews as List)
            .map((r) => (r["rating_store"] as num?)?.toDouble() ?? 0)
            .where((r) => r > 0).toList();
        if (ratings.isNotEmpty) {
          final avg = ratings.reduce((a, b) => a + b) / ratings.length;
          await widget.sb.from("stores").update({"rating": avg.toStringAsFixed(1)}).eq("id", storeId);
        }
      }

      // Recalculate rider rating
      if (delivId != null) {
        final reviews = await widget.sb.from("reviews")
            .select("rating_rider").eq("deliverer_id", delivId);
        final ratings = List<Map<String, dynamic>>.from(reviews as List)
            .map((r) => (r["rating_rider"] as num?)?.toDouble() ?? 0)
            .where((r) => r > 0).toList();
        if (ratings.isNotEmpty) {
          final avg = ratings.reduce((a, b) => a + b) / ratings.length;
          await widget.sb.from("deliverers").update({"rating": avg.toStringAsFixed(1)}).eq("id", delivId);
        }
      }

      // Mark order as rated
      await widget.sb.from("orders").update({
        "rated":    true,
        "rated_at": DateTime.now().toIso8601String(),
      }).eq("id", o["id"]);

      widget.onSubmitted();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ ¡Gracias por tu reseña!")),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = (widget.order["stores"] as Map<String, dynamic>?) ?? {};
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
        )),
        Flexible(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Column(children: [
              Text(store["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text("¿Cómo estuvo tu pedido?",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(store["name"] ?? "",
                  style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
            ])),
            const SizedBox(height: 24),

            const Text("Califica la tienda",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            _buildStars(_storeRating, (v) => setState(() => _storeRating = v)),
            const SizedBox(height: 20),

            const Text("Califica al repartidor",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            _buildStars(_riderRating, (v) => setState(() => _riderRating = v)),
            const SizedBox(height: 20),

            const Text("Comentario (opcional)",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "¿Qué te pareció el servicio?",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.homePurple, width: 2)),
                filled: true, fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.homeOrange, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFamily: "Nunito"),
                ),
                child: _sending
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Enviar calificación"),
              ),
            ),
          ]),
        )),
      ]),
    );
  }

  Widget _buildStars(int current, ValueChanged<int> onChange) =>
    Row(children: List.generate(5, (i) => GestureDetector(
      onTap: () => onChange(i + 1),
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Icon(
          i < current ? Icons.star_rounded : Icons.star_outline_rounded,
          color: i < current ? const Color(0xFFFFB800) : AppColors.textLight,
          size: 36,
        ),
      ),
    )));
}
