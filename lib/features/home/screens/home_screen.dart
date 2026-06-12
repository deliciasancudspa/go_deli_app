import "dart:async";
import "dart:convert";
import "dart:math";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:geocoding/geocoding.dart";
import "package:geolocator/geolocator.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:shimmer/shimmer.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../config/app_config.dart";
import "../../../services/notification_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/utils/category_match.dart";
import "../../../providers/cart_provider.dart";
import "../../mercados/screens/mercados_screen.dart";
import "../../servicios/screens/servicios_screen.dart";
import "../../pedidos/screens/pedidos_screen.dart";
import "../../profile/screens/profile_screen.dart";

// Palette shortcuts used throughout this file
const _kDark   = AppColors.homeDark;
const _kOrange = AppColors.homeOrange;
const _kPurple = AppColors.homePurple;
const _kBg     = AppColors.homeBackground;
const _kBorder = AppColors.homeCardBorder;

const _kAliadosUrl = "https://aliados.godeli.cl"; // actualizar con URL real

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIdx = 0;
  final _sb = Supabase.instance.client;

  // Home data
  List<Map<String, dynamic>> _banners    = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _allStores  = [];
  bool _loadingHome = true;
  Map<String, List<Map<String, dynamic>>> _featuredItems = {};
  double? _userLat;
  double? _userLng;

  // Selected category filter (null = Todos)
  Map<String, dynamic>? _selectedCat;

  // Header
  int    _notifCount      = 0;
  String _deliveryAddress = "";

  // Banner carousel
  final _bannerCtrl = PageController();
  int    _bannerPage = 0;
  Timer? _bannerTimer;
  StreamSubscription<void>?                      _notifSub;
  StreamSubscription<List<ConnectivityResult>>?  _connectSub;
  bool _isOnline = true;

  // ── 5-min in-memory cache ─────────────────────────────────────────────────
  static List<Map<String, dynamic>>? _cachedCategories;
  static List<Map<String, dynamic>>? _cachedBanners;
  static DateTime? _catCachedAt;
  static DateTime? _bannerCachedAt;
  static const _ttl = Duration(minutes: 5);

  bool get _catStale    => _catCachedAt    == null || DateTime.now().difference(_catCachedAt!)    > _ttl;
  bool get _bannerStale => _bannerCachedAt == null || DateTime.now().difference(_bannerCachedAt!) > _ttl;

  // ── Getters ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _featuredStores {
    final base = _selectedCat == null
        ? _allStores
        : _allStores.where((s) => storeMatchesCategory(s, _selectedCat!["name"] as String?)).toList();
    final list = base.where((s) => s["featured_order"] != null).toList()
      ..sort((a, b) => (a["featured_order"] as int).compareTo(b["featured_order"] as int));
    return list.take(8).toList();
  }

  List<Map<String, dynamic>> get _nearbyStores {
    var base = _selectedCat == null
        ? List<Map<String, dynamic>>.from(_allStores)
        : _allStores.where((s) => storeMatchesCategory(s, _selectedCat!["name"] as String?)).toList();
    final featured = _featuredStores;
    if (featured.isNotEmpty) {
      final ids = featured.map((s) => s["id"] as String).toSet();
      base = base.where((s) => !ids.contains(s["id"] as String)).toList();
    }
    if (_userLat != null && _userLng != null) {
      base.sort((a, b) {
        final aLat = (a["lat"] as num?)?.toDouble();
        final aLng = (a["lng"] as num?)?.toDouble();
        final bLat = (b["lat"] as num?)?.toDouble();
        final bLng = (b["lng"] as num?)?.toDouble();
        if (aLat == null || aLng == null) return 1;
        if (bLat == null || bLng == null) return -1;
        return _haversine(_userLat!, _userLng!, aLat, aLng)
            .compareTo(_haversine(_userLat!, _userLng!, bLat, bLng));
      });
    }
    return base;
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _loadDeliveryAddress();
    _loadData();
    _loadNotifCount();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLocationConfigured());
    _notifSub   = NotificationService().onNewNotification.listen((_) => _loadNotifCount());
    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (mounted && online != _isOnline) setState(() => _isOnline = online);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startBannerTimer());
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _connectSub?.cancel();
    _bannerTimer?.cancel();
    _bannerCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) setState(() => _isOnline = results.any((r) => r != ConnectivityResult.none));
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_banners.length <= 1 || !_bannerCtrl.hasClients) return;
      final next = (_bannerPage + 1) % _banners.length;
      _bannerCtrl.animateToPage(next, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  Future<void> _checkLocationConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getBool("location_configured") ?? false;
    if (!configured && mounted) context.go("/location");
  }

  Future<void> _loadDeliveryAddress() async {
    try {
      // Prefer address saved by LocationPermissionScreen
      final prefs    = await SharedPreferences.getInstance();
      final fromPref = prefs.getString("delivery_address") ?? "";
      final lat      = prefs.getDouble("delivery_lat");
      final lng      = prefs.getDouble("delivery_lng");
      if (lat != null && lng != null && mounted) {
        setState(() { _userLat = lat; _userLng = lng; });
      }
      if (fromPref.isNotEmpty) {
        if (mounted) setState(() => _deliveryAddress = fromPref);
        return;
      }
      // Fallback: default address from DB
      final user = _sb.auth.currentUser;
      if (user == null) return;
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).maybeSingle();
      if (u == null) return;
      final addr = await _sb
          .from("user_addresses")
          .select("address")
          .eq("user_id", u["id"])
          .eq("is_default", true)
          .maybeSingle();
      if (mounted) setState(() => _deliveryAddress = addr?["address"] as String? ?? "");
    } catch (_) {}
  }

  Future<void> _loadNotifCount() async {
    try {
      final user = _sb.auth.currentUser;
      if (user == null) return;
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).maybeSingle();
      if (u == null) return;
      final result = await _sb
          .from("orders")
          .select("id")
          .eq("client_id", u["id"])
          .neq("status", "delivered")
          .neq("status", "cancelled");
      if (mounted) setState(() => _notifCount = (result as List).length);
    } catch (_) {}
  }

  Future<void> _loadData({bool forceRefreshCache = false}) async {
    if (mounted) setState(() => _loadingHome = true);
    try {
      // Categories (cached 5 min)
      if (forceRefreshCache || _catStale) {
        final raw = await _sb.from("categories")
            .select()
            .eq("is_active", true)
            .order("sort_order");
        // Aceptar listas de pantallas ("home,mercados") además de "home"/"all"
        _cachedCategories = List<Map<String, dynamic>>.from(raw).where((c) {
          final s = (c["screens"] as String?) ?? "all";
          return s == "all" || s.split(",").map((x) => x.trim()).contains("home");
        }).toList();
        _catCachedAt = DateTime.now();
      }

      // Banners (cached 5 min, date-filtered server-side)
      if (forceRefreshCache || _bannerStale) {
        final now = DateTime.now().toIso8601String();
        final raw = await _sb.from("banners")
            .select()
            .eq("is_active", true)
            .eq("banner_type", "web_home")
            .or("start_date.is.null,start_date.lte.$now")
            .or("end_date.is.null,end_date.gte.$now")
            .order("sort_order")
            .limit(10);
        _cachedBanners = (raw as List<dynamic>).cast<Map<String, dynamic>>();
        _bannerCachedAt = DateTime.now();
      }

      // Stores (always fresh)
      final storesRaw = await _sb.from("stores").select().eq("status", "approved").eq("is_active", true);

      // Featured items for highlighted stores (is_featured OR discount_pct > 0)
      final featIds = (storesRaw as List).cast<Map<String, dynamic>>()
          .where((s) => s["featured_order"] != null)
          .map((s) => s["id"] as String)
          .toList();
      Map<String, List<Map<String, dynamic>>> featItems = {};
      if (featIds.isNotEmpty) {
        final raw = await _sb
            .from("menu_items")
            .select()
            .inFilter("store_id", featIds)
            .eq("is_available", true)
            .or("is_featured.eq.true,discount_pct.gt.0")
            .order("sort_order")
            .limit(40);
        for (final item in (raw as List).cast<Map<String, dynamic>>()) {
          final sid  = item["store_id"] as String;
          final list = featItems.putIfAbsent(sid, () => []);
          if (list.length < 4) list.add(item);
        }
      }

      if (mounted) setState(() {
        _categories    = List<Map<String, dynamic>>.from(_cachedCategories ?? []);
        _banners       = List<Map<String, dynamic>>.from(_cachedBanners    ?? []);
        _allStores     = List<Map<String, dynamic>>.from(storesRaw);
        _featuredItems = featItems;
        _loadingHome   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHome = false);
    }
  }

  // ── Root build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      backgroundColor: _kBg,
      body: IndexedStack(index: _navIdx, children: [
        _buildHome(cart),
        _buildMarkets(),
        _buildServicios(),
        _buildPedidos(),
        _buildPerfil(),
      ]),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Custom bottom nav ─────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    const labels = ["Inicio", "Mercados", "Servicios", "Pedidos", "Perfil"];
    const activeIcons   = [Icons.home_rounded, Icons.storefront_rounded, Icons.handyman_rounded, Icons.receipt_long_rounded, Icons.person_rounded];
    const inactiveIcons = [Icons.home_outlined, Icons.storefront_outlined, Icons.handyman_outlined, Icons.receipt_long_outlined, Icons.person_outline];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Row(
        children: List.generate(5, (i) {
          final active = _navIdx == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _navIdx = i),
              behavior: HitTestBehavior.opaque,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Indicador superior con gradiente
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: active ? AppColors.mainGradient : null,
                    color: active ? null : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(active ? activeIcons[i] : inactiveIcons[i],
                        color: active ? _kPurple : const Color(0xFF888888),
                        size: 22),
                    const SizedBox(height: 2),
                    Text(labels[i],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: active ? _kPurple : const Color(0xFF888888),
                          fontFamily: "Nunito",
                        )),
                  ]),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 0 — HOME
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHome(CartProvider cart) {
    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefreshCache: true),
      color: _kOrange,
      child: CustomScrollView(slivers: [

        // ── Header ──────────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          floating: false,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 56,
          flexibleSpace: const GradientFlexibleSpace(),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GestureDetector(
                onTap: () => context.push("/search"),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(Icons.search, color: Colors.white.withOpacity(0.70), size: 20),
                    const SizedBox(width: 8),
                    Text("Buscar tiendas o productos...",
                        style: TextStyle(color: Colors.white.withOpacity(0.70), fontSize: 14, fontFamily: "Nunito")),
                  ]),
                ),
              ),
            ),
          ),
          title: GestureDetector(
            onTap: _showAddressPicker,
            child: Row(children: [
              const Icon(Icons.location_on_rounded, color: _kOrange, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _deliveryAddress.isEmpty ? "¿A dónde enviamos tu pedido?" : _deliveryAddress,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: "Nunito"),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 18),
            ]),
          ),
          actions: [
            Stack(clipBehavior: Clip.none, children: [
              IconButton(
                onPressed: () async {
                  setState(() => _notifCount = 0);
                  await context.push("/notifications");
                  _loadNotifCount();
                },
                icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 24),
              ),
              if (_notifCount > 0) Positioned(right: 6, top: 6,
                child: Container(width: 14, height: 14,
                  decoration: const BoxDecoration(color: _kOrange, shape: BoxShape.circle),
                  child: Center(child: Text("${_notifCount > 9 ? "9+" : _notifCount}",
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900))))),
            ]),
            Stack(clipBehavior: Clip.none, children: [
              IconButton(
                onPressed: () => context.push("/cart"),
                icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 24),
              ),
              if (cart.itemCount > 0) Positioned(right: 6, top: 6,
                child: Container(width: 14, height: 14,
                  decoration: const BoxDecoration(color: _kPurple, shape: BoxShape.circle),
                  child: Center(child: Text("${cart.itemCount}",
                      style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900))))),
            ]),
            const SizedBox(width: 4),
          ],
        ),

        // ── Offline banner ───────────────────────────────────────────────────
        if (!_isOnline)
          SliverToBoxAdapter(child: Container(
            color: AppColors.warning,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text("Sin conexión – mostrando datos en caché",
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          )),

        // ── Banners ──────────────────────────────────────────────────────────
        SliverToBoxAdapter(child: _loadingHome ? _bannerShimmer() : _buildBanners()),

        // ── Categorías ───────────────────────────────────────────────────────
        const SliverToBoxAdapter(child: Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text("Categorías", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kDark)),
        )),
        SliverToBoxAdapter(child: _loadingHome ? _catsShimmer() : _buildCategories()),

        // ── Destacados ───────────────────────────────────────────────────────
        if (_loadingHome || _featuredStores.isNotEmpty) ...[
          const SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Text("Destacados para ti",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kDark)),
          )),
          if (_loadingHome)
            SliverToBoxAdapter(child: _storeShimmer())
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _featuredStoreCard(_featuredStores[i]),
                  childCount: _featuredStores.length,
                ),
              ),
            ),
        ],

        // ── Banner aliado ────────────────────────────────────────────────────
        SliverToBoxAdapter(child: _buildAliadoBanner()),

        // ── Cerca de ti ──────────────────────────────────────────────────────
        const SliverToBoxAdapter(child: Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text("Cerca de ti", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kDark)),
        )),

        if (_loadingHome)
          SliverToBoxAdapter(child: _storeShimmer())
        else if (_nearbyStores.isEmpty)
          const SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text("Sin tiendas en esta categoría",
                style: TextStyle(color: AppColors.textLight))),
          ))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _nearbyCard(_nearbyStores[i]),
                childCount: _nearbyStores.length,
              ),
            ),
          ),
      ]),
    );
  }

  // ── Address picker ────────────────────────────────────────────────────────
  Future<void> _showAddressPicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangeAddressSheet(currentAddress: _deliveryAddress),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _deliveryAddress = result);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("delivery_address", result);
    }
  }

  // ── Shimmer helpers ───────────────────────────────────────────────────────
  static const _shimmerBase      = Color(0xFFDDD0F0);
  static const _shimmerHighlight = Color(0xFFF5F0FF);

  Widget _bannerShimmer() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Shimmer.fromColors(baseColor: _shimmerBase, highlightColor: _shimmerHighlight,
      child: Container(height: 180, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)))),
  );

  Widget _catsShimmer() => SizedBox(
    height: 96,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(baseColor: _shimmerBase, highlightColor: _shimmerHighlight,
        child: Container(margin: const EdgeInsets.only(right: 8), width: 72, height: 88,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)))),
    ),
  );

  Widget _storeShimmer() => SizedBox(
    height: 200,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 3,
      itemBuilder: (_, __) => Shimmer.fromColors(baseColor: _shimmerBase, highlightColor: _shimmerHighlight,
        child: Container(margin: const EdgeInsets.only(right: 12), width: 190,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))),
    ),
  );

  // ── Banners ───────────────────────────────────────────────────────────────
  Widget _buildBanners() {
    if (_banners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _bannerCtrl,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _bannerPage = i),
            itemBuilder: (_, i) {
              final b      = _banners[i];
              final imgUrl = b["image_url"] as String?;
              Color bg     = _kOrange;
              try {
                final hex = (b["bg_color"] as String?)?.replaceAll("#", "");
                if (hex != null && hex.length == 6) bg = Color(int.parse("FF$hex", radix: 16));
              } catch (_) {}
              return GestureDetector(
                onTap: () => _handleBannerTap(b),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: bg,
                    image: imgUrl != null ? DecorationImage(
                        image: NetworkImage(imgUrl),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.18), BlendMode.darken)) : null,
                    boxShadow: [BoxShadow(color: bg.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: imgUrl == null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (b["title"] != null)
                              Text(b["title"], style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, fontFamily: "Nunito")),
                            if (b["subtitle"] != null) ...[
                              const SizedBox(height: 6),
                              Text(b["subtitle"], style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14, fontFamily: "Nunito")),
                            ],
                          ]),
                        )
                      : Stack(children: [
                          if (b["title"] != null)
                            Positioned(bottom: 20, left: 20, right: 20,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(b["title"], style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, fontFamily: "Nunito",
                                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
                                if (b["subtitle"] != null)
                                  Text(b["subtitle"], style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13, fontFamily: "Nunito")),
                              ])),
                        ]),
                ),
              );
            },
          ),
        ),
        if (_banners.length > 1) ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_banners.length, (i) =>
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _bannerPage == i ? 20 : 6, height: 6,
                decoration: BoxDecoration(
                  color: _bannerPage == i ? _kOrange : _kBorder,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            )),
        ],
      ]),
    );
  }

  void _handleBannerTap(Map<String, dynamic> b) {
    final type  = b["link_type"]  as String?;
    final value = b["link_value"] as String?;
    if (type == null || value == null) return;
    if (type == "store") { context.push("/store/$value"); return; }
    if (type == "category") {
      final cat = _categories.firstWhere(
          (c) => c["name"] == value || c["id"] == value, orElse: () => {});
      if (cat.isNotEmpty) setState(() => _selectedCat = cat);
      return;
    }
    if (type == "url") launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
  }

  // ── Categories ─────────────────────────────────────────────────────────────
  Widget _buildCategories() {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            final selected = _selectedCat == null;
            return GestureDetector(
              onTap: () => setState(() => _selectedCat = null),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? _kOrange.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected ? _kOrange : _kBorder, width: selected ? 2 : 1),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: selected ? _kOrange.withOpacity(0.15) : const Color(0xFFFFF3E8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(child: Text("🏪", style: TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(height: 4),
                  Text("Todas",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                          color: selected ? _kOrange : _kDark)),
                ]),
              ),
            );
          }
          final cat      = _categories[i - 1];
          final selected = _selectedCat?["id"] == cat["id"];
          Color iconBg   = const Color(0xFFFFF3E8);
          try {
            final hex = (cat["color"] as String?)?.replaceAll("#", "");
            if (hex != null && hex.length == 6) iconBg = Color(int.parse("FF$hex", radix: 16));
          } catch (_) {}
          return GestureDetector(
            onTap: () => setState(() => _selectedCat = selected ? null : cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color:  selected ? _kPurple.withOpacity(0.08) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? _kOrange : _kBorder, width: selected ? 2 : 1),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
                  child: (cat["image_url"] as String?) != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(cat["image_url"] as String,
                              width: 44, height: 44, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                  child: Text(cat["emoji"] as String? ?? "🍽️",
                                      style: const TextStyle(fontSize: 22)))))
                      : Center(child: Text(cat["emoji"] as String? ?? "🍽️",
                          style: const TextStyle(fontSize: 22))),
                ),
                const SizedBox(height: 4),
                Text(cat["name"] as String? ?? "",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                        color: selected ? _kOrange : _kDark)),
              ]),
            ),
          );
        },
      ),
    );
  }

  String _fmt(num p) => "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  // ── Featured store card (vertical, full-width with product scroll) ───────────
  Widget _featuredStoreCard(Map<String, dynamic> store) {
    final storeId   = store["id"] as String;
    final logoUrl   = store["logo_url"] as String?;
    final sponsored = store["sponsored"] == true;
    final isOpen    = store["is_open"] as bool? ?? true;
    final fee       = (store["delivery_fee_client"] as num?)?.toInt() ?? 0;
    final products  = _featuredItems[storeId] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(
            color: _kPurple.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 44, height: 44,
                child: logoUrl != null
                    ? Image.network(logoUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _coverPlaceholder(store, 44))
                    : _coverPlaceholder(store, 44),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(store["name"] ?? "",
                      style: const TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 14, color: _kDark),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (sponsored) Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(6)),
                  child: const Text("Destacado",
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
                if (!isOpen) Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text("Cerrado",
                      style: TextStyle(color: AppColors.error, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.star_rounded, color: _kOrange, size: 12),
                Text(" ${store["rating"] ?? "5.0"}",
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                const Text(" · ", style: TextStyle(color: AppColors.textLight, fontSize: 11)),
                const Icon(Icons.access_time_rounded, size: 11, color: AppColors.textLight),
                Text(" ${store["delivery_time"] ?? "30-45"} min",
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                const Text(" · ", style: TextStyle(color: AppColors.textLight, fontSize: 11)),
                fee == 0
                    ? Text("Envío gratis",
                        style: TextStyle(fontSize: 11, color: _kPurple, fontWeight: FontWeight.w700))
                    : Text("\$${fee.toStringAsFixed(0)}",
                        style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
              ]),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => context.push("/store/$storeId"),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: const Color(0xFFF0E5FF),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text("Entrar →",
                    style: TextStyle(color: Color(0xFF6B00B3),
                        fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
        if (products.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: products.length,
              itemBuilder: (_, i) => _featuredMiniCard(products[i], storeId),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _featuredMiniCard(Map<String, dynamic> item, String storeId) {
    final imgUrl    = item["image_url"] as String?;
    final discPct   = (item["discount_pct"] as int?) ?? 0;
    final price     = (item["price"] as num?)?.toInt() ?? 0;
    final origPrice = (item["original_price"] as num?)?.toInt();
    final showOrig  = discPct > 0 && origPrice != null && origPrice > price;

    return GestureDetector(
      onTap: () => context.push("/store/$storeId"),
      child: Container(
        width: 96,
        margin: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 96, height: 72,
                  child: imgUrl != null
                      ? Image.network(imgUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: _kBg,
                              child: Center(child: Text(
                                  item["emoji"] as String? ?? "🍽️",
                                  style: const TextStyle(fontSize: 26)))))
                      : Container(color: _kBg,
                          child: Center(child: Text(
                              item["emoji"] as String? ?? "🍽️",
                              style: const TextStyle(fontSize: 26)))),
                ),
              ),
              if (discPct > 0) Positioned(top: 4, left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                      color: _kOrange, borderRadius: BorderRadius.circular(6)),
                  child: Text("-$discPct%",
                      style: const TextStyle(color: Colors.white,
                          fontSize: 9, fontWeight: FontWeight.w900)),
                )),
            ]),
            const SizedBox(height: 4),
            Text(item["name"] as String? ?? "",
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _kDark),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const Spacer(),
            if (showOrig)
              Text(_fmt(origPrice as num),
                  style: const TextStyle(fontSize: 9, color: AppColors.textLight,
                      decoration: TextDecoration.lineThrough)),
            Builder(builder: (_) {
              try {
                final vs = item["variants"];
                List? vl;
                if (vs is String && vs.isNotEmpty) vl = jsonDecode(vs) as List;
                else if (vs is List && vs.isNotEmpty) vl = vs;
                if (vl != null && vl.isNotEmpty) {
                  final minP = vl.cast<Map<String, dynamic>>()
                      .map((v) => (v["price"] as num?)?.toInt() ?? price)
                      .reduce(min);
                  return Text("Desde ${_fmt(minP)}",
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kOrange));
                }
              } catch (_) {}
              try {
                final vgs = item["variant_groups"];
                List? vgl;
                if (vgs is String && vgs.isNotEmpty) vgl = jsonDecode(vgs) as List;
                else if (vgs is List && vgs.isNotEmpty) vgl = vgs;
                if (vgl != null && vgl.isNotEmpty) {
                  var minP = 2147483647;
                  for (final g in vgl.cast<Map<String, dynamic>>()) {
                    for (final it in (g["items"] as List? ?? []).cast<Map<String, dynamic>>()) {
                      final p = (it["price"] as num?)?.toInt() ?? price;
                      if (p < minP) minP = p;
                    }
                  }
                  if (minP < 2147483647) return Text("Desde ${_fmt(minP)}",
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _kOrange));
                }
              } catch (_) {}
              return Text(_fmt(price),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _kOrange));
            }),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder(Map<String, dynamic> s, double height) => Container(
    height: height, width: double.infinity,
    decoration: const BoxDecoration(gradient: AppColors.darkGradient),
    child: Center(child: Text(s["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 40))),
  );

  // ── "Únete como Aliado" banner ─────────────────────────────────────────────
  Widget _buildAliadoBanner() => GestureDetector(
    onTap: () => launchUrl(Uri.parse(_kAliadosUrl), mode: LaunchMode.externalApplication),
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.darkGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _kPurple.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("¿Tienes un negocio?",
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text("Únete como Aliado",
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, fontFamily: "Nunito")),
          const SizedBox(height: 6),
          Text("Llega a más clientes con Go Deli",
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(10)),
            child: const Text("Registrar mi negocio",
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ])),
        const SizedBox(width: 12),
        const Text("🏪", style: TextStyle(fontSize: 52)),
      ]),
    ),
  );

  // ── Nearby stores (vertical list) ─────────────────────────────────────────
  Widget _nearbyCard(Map<String, dynamic> s) {
    final logoUrl = s["logo_url"] as String?;
    return GestureDetector(
      onTap: () => context.push("/store/${s["id"]}"),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
          boxShadow: [BoxShadow(color: _kPurple.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: SizedBox(
              width: 96, height: 96,
              child: logoUrl != null
                  ? Image.network(logoUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _coverPlaceholder(s, 96))
                  : _coverPlaceholder(s, 96),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(s["name"] ?? "",
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _kDark),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (!(s["is_open"] ?? true)) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Text("Cerrado",
                        style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(s["category"] ?? "",
                    style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.star_rounded, color: _kOrange, size: 14),
                  Text(" ${s["rating"] ?? "5.0"}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text("·", style: TextStyle(color: AppColors.textLight)),
                  ),
                  const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textLight),
                  Text(" ${s["delivery_time"] ?? "30-45"} min",
                      style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.delivery_dining, size: 13, color: AppColors.textLight),
                  Builder(builder: (_) {
                    final cf = (s["delivery_fee_client"] as num?)?.toInt() ?? 0;
                    return Text(cf == 0 ? "  Gratis" : "  \$$cf",
                        style: TextStyle(fontSize: 12, color: cf == 0 ? _kPurple : AppColors.textLight, fontWeight: cf == 0 ? FontWeight.w700 : FontWeight.normal));
                  }),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 — MERCADOS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildMarkets() => const MercadosScreen();

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 — SERVICIOS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildServicios() => const ServiciosScreen();

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 — PEDIDOS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPedidos() => const PedidosScreen();

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 4 — PERFIL  (sin cambios)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPerfil() => const PerfilScreen();
}

// ════════════════════════════════════════════════════════════════════════════
// _PedidosTab — SIN CAMBIOS
// ════════════════════════════════════════════════════════════════════════════
class _PedidosTab extends StatefulWidget {
  @override
  State<_PedidosTab> createState() => _PedidosTabState();
}

class _PedidosTabState extends State<_PedidosTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  final _sb = Supabase.instance.client;

  final _statusLabels = {
    "pending": "⏳ Pendiente", "accepted": "✅ Confirmado",
    "preparing": "👨‍🍳 Preparando", "ready": "🎉 Listo",
    "assigned": "🛵 Asignado", "picked_up": "📦 Recogido",
    "on_the_way": "🚀 En camino", "delivered": "🏁 Entregado",
    "cancelled": "❌ Cancelado",
  };

  final _statusColors = {
    "pending": Color(0xFFF59E0B), "accepted": Color(0xFF3B82F6),
    "preparing": Color(0xFFFF6B35), "ready": Color(0xFF22C55E),
    "assigned": Color(0xFFF59E0B), "picked_up": Color(0xFF3B82F6),
    "on_the_way": Color(0xFFFF6B35), "delivered": Color(0xFF22C55E),
    "cancelled": Color(0xFFEF4444),
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) { setState(() => _loading = false); return; }
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).single();
      final orders = await _sb.from("orders")
          .select("*, stores(name,emoji), order_items(item_name,quantity)")
          .eq("client_id", u["id"])
          .order("created_at", ascending: false)
          .limit(30);
      if (mounted) setState(() { _orders = List<Map<String, dynamic>>.from(orders); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  String _fmt(num p) => "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_orders.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("📦", style: TextStyle(fontSize: 64)),
      const SizedBox(height: 16),
      const Text("Sin pedidos aún", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text("Tus pedidos aparecerán aquí", style: TextStyle(color: AppColors.textLight)),
    ]));
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        itemBuilder: (ctx, i) {
          final o      = _orders[i];
          final status = o["status"] as String? ?? "pending";
          final color  = _statusColors[status] ?? AppColors.textLight;
          final items  = (o["order_items"] as List?) ?? [];
          final isActive = !["delivered", "cancelled"].contains(status);
          return GestureDetector(
            onTap: () => Navigator.pushNamed(context, "/tracking/${o["id"]}"),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isActive ? color.withOpacity(0.4) : AppColors.border, width: isActive ? 2 : 1),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(o["stores"]?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o["stores"]?["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(items.take(2).map((i) => i["item_name"]).join(", "),
                        style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_fmt((o["total"] as num?) ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(_statusLabels[status] ?? status,
                          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ]),
                if (isActive) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => context.push("/tracking/${o["id"]}"),
                      icon: const Icon(Icons.location_on_outlined, size: 16),
                      label: const Text("Seguir pedido"),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 38),
                          padding: const EdgeInsets.symmetric(vertical: 8)),
                    ),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _PerfilTab — SIN CAMBIOS
// ════════════════════════════════════════════════════════════════════════════
class _PerfilTab extends StatefulWidget {
  const _PerfilTab();
  @override
  State<_PerfilTab> createState() => _PerfilTabState();
}

class _PerfilTabState extends State<_PerfilTab> {
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _orders    = [];
  List<Map<String, dynamic>> _addresses = [];
  bool _loading    = true;
  bool _showFavs   = false;
  final _sb = Supabase.instance.client;

  final _statusLabels = {
    "pending": "⏳ Pendiente", "accepted": "✅ Confirmado", "preparing": "👨‍🍳 Preparando",
    "ready": "🎉 Listo", "assigned": "🛵 Asignado", "picked_up": "📦 Recogido",
    "on_the_way": "🚀 En camino", "delivered": "🏁 Entregado", "cancelled": "❌ Cancelado",
  };
  final _statusColors = {
    "pending": Color(0xFFF59E0B), "accepted": Color(0xFF3B82F6), "preparing": Color(0xFFFF6B35),
    "ready": Color(0xFF22C55E), "assigned": Color(0xFFF59E0B), "picked_up": Color(0xFF3B82F6),
    "on_the_way": Color(0xFFFF6B35), "delivered": Color(0xFF22C55E), "cancelled": Color(0xFFEF4444),
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final authUser = _sb.auth.currentUser;
      if (authUser == null) { setState(() => _loading = false); return; }
      final u    = await _sb.from("users").select().eq("auth_id", authUser.id).single();
      final favs = await _sb.from("user_favorites")
          .select("*, stores(id,name,emoji,category,rating,delivery_time,delivery_fee,is_open)")
          .eq("user_id", u["id"]);
      final orders = await _sb.from("orders")
          .select("*, stores(name,emoji), order_items(item_name,quantity)")
          .eq("client_id", u["id"]).order("created_at", ascending: false).limit(20);
      final addrs = await _sb.from("user_addresses").select()
          .eq("user_id", u["id"]).order("is_default", ascending: false);
      if (mounted) setState(() {
        _user      = u;
        _favorites = List<Map<String, dynamic>>.from(favs);
        _orders    = List<Map<String, dynamic>>.from(orders);
        _addresses = List<Map<String, dynamic>>.from(addrs);
        _loading   = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _logout() async {
    await _sb.auth.signOut();
    if (mounted) context.go("/login");
  }

  String _fmt(num p) => "\$" + p.toStringAsFixed(0).replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.");

  void _showOrders() {
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95,
        builder: (ctx, ctrl) => Column(children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [
            const Text("Mis pedidos", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text("${_orders.length} pedidos", style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
          ])),
          const Divider(height: 1),
          Expanded(child: _orders.isEmpty
            ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text("📦", style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text("Sin pedidos aún", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textLight)),
              ]))
            : ListView.builder(controller: ctrl, padding: const EdgeInsets.all(16),
                itemCount: _orders.length,
                itemBuilder: (ctx, i) {
                  final o      = _orders[i];
                  final status = o["status"] as String? ?? "pending";
                  final color  = _statusColors[status] ?? AppColors.textLight;
                  final isActive = !["delivered", "cancelled"].contains(status);
                  final items  = (o["order_items"] as List?) ?? [];
                  final total  = (o["total"] as num?) ?? 0;
                  return GestureDetector(
                    onTap: () { Navigator.pop(ctx); context.push("/tracking/${o["id"]}"); },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isActive ? color.withOpacity(0.4) : AppColors.border, width: isActive ? 2 : 1)),
                      child: Row(children: [
                        Text(o["stores"]?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(o["stores"]?["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(items.take(2).map((x) => x["item_name"]).join(", "),
                              style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(_fmt(total), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
                          const SizedBox(height: 4),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(_statusLabels[status] ?? status,
                                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))),
                        ]),
                      ]),
                    ),
                  );
                })),
        ]),
      ),
    );
  }

  void _showAddresses() {
    showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) =>
        DraggableScrollableSheet(expand: false, initialChildSize: 0.7, maxChildSize: 0.92,
          builder: (ctx, ctrl) => Column(children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [
              const Text("Mis direcciones", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(onPressed: () => _addAddress(ctx, setModal),
                  icon: const Icon(Icons.add, size: 18), label: const Text("Agregar")),
            ])),
            const Divider(height: 1),
            Expanded(child: _addresses.isEmpty
              ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text("📍", style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text("Sin direcciones guardadas",
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textLight)),
                  SizedBox(height: 4),
                  Text("Agrega una dirección para pedir más rápido",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textLight, fontSize: 13)),
                ]))
              : ListView.builder(controller: ctrl, padding: const EdgeInsets.all(16),
                  itemCount: _addresses.length,
                  itemBuilder: (ctx, i) {
                    final a         = _addresses[i];
                    final isDefault = a["is_default"] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: isDefault ? AppColors.primary.withOpacity(0.5) : AppColors.border,
                              width: isDefault ? 2 : 1)),
                      child: Row(children: [
                        Container(width: 40, height: 40,
                          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: Icon(_labelIcon(a["label"]), color: AppColors.primary, size: 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(a["label"] ?? "Dirección",
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            if (isDefault) ...[
                              const SizedBox(width: 6),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                                child: const Text("Principal",
                                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                            ],
                          ]),
                          const SizedBox(height: 2),
                          Text(a["address"] ?? "",
                              style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                        ])),
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == "default") {
                              await _sb.from("user_addresses").update({"is_default": false}).eq("user_id", _user!["id"]);
                              await _sb.from("user_addresses").update({"is_default": true}).eq("id", a["id"]);
                            } else if (v == "delete") {
                              await _sb.from("user_addresses").delete().eq("id", a["id"]);
                            }
                            final addrs = await _sb.from("user_addresses").select()
                                .eq("user_id", _user!["id"]).order("is_default", ascending: false);
                            if (mounted) setState(() => _addresses = List<Map<String, dynamic>>.from(addrs));
                            setModal(() {});
                          },
                          itemBuilder: (_) => [
                            if (!isDefault) const PopupMenuItem(value: "default", child: Text("Establecer como principal")),
                            const PopupMenuItem(value: "delete", child: Text("Eliminar",
                                style: TextStyle(color: AppColors.error))),
                          ],
                        ),
                      ]),
                    );
                  })),
          ]),
        ),
      ),
    );
  }

  IconData _labelIcon(String? label) {
    if (label == "Casa") return Icons.home_outlined;
    if (label == "Trabajo") return Icons.work_outline;
    return Icons.location_on_outlined;
  }

  Future<void> _addAddress(BuildContext ctx, StateSetter setModal) async {
    String label = "Casa";
    final ctrl = TextEditingController();
    await showDialog(context: ctx, builder: (dCtx) => StatefulBuilder(builder: (dCtx, setD) => AlertDialog(
      title: const Text("Nueva dirección"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          value: label,
          decoration: InputDecoration(labelText: "Tipo",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          items: ["Casa", "Trabajo", "Otro"].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
          onChanged: (v) => setD(() => label = v!),
        ),
        const SizedBox(height: 12),
        TextField(controller: ctrl, maxLines: 2,
          decoration: InputDecoration(
            labelText: "Dirección completa",
            hintText: "Ej: Calle Los Pinos 123, Ancud",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("Cancelar")),
        ElevatedButton(
          onPressed: () async {
            if (ctrl.text.trim().isEmpty) return;
            final isEmpty = _addresses.isEmpty;
            await _sb.from("user_addresses").insert({
              "user_id": _user!["id"], "label": label,
              "address": ctrl.text.trim(), "is_default": isEmpty,
            });
            final addrs = await _sb.from("user_addresses").select()
                .eq("user_id", _user!["id"]).order("is_default", ascending: false);
            if (mounted) setState(() => _addresses = List<Map<String, dynamic>>.from(addrs));
            setModal(() {});
            if (dCtx.mounted) Navigator.pop(dCtx);
          },
          child: const Text("Guardar"),
        ),
      ],
    )));
  }

  void _showHelp() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(expand: false, initialChildSize: 0.75, maxChildSize: 0.95,
        builder: (ctx, ctrl) => ListView(controller: ctrl, padding: const EdgeInsets.all(20), children: [
          Container(margin: const EdgeInsets.only(bottom: 16), alignment: Alignment.center,
            child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          const Text("Centro de ayuda", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const Text("¿En qué podemos ayudarte?", style: TextStyle(color: AppColors.textLight, fontSize: 14)),
          const SizedBox(height: 20),
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Contacto directo",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: ElevatedButton.icon(onPressed: () {},
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text("WhatsApp", style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF25D366), foregroundColor: Colors.white,
                      minimumSize: const Size(0, 40)))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton.icon(onPressed: () {},
                  icon: const Icon(Icons.email_outlined, size: 16),
                  label: const Text("Email", style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: AppColors.primary,
                      minimumSize: const Size(0, 40)))),
              ]),
              const SizedBox(height: 8),
              const Center(child: Text("soporte@godeli.cl · Lun-Vie 9:00-20:00",
                  style: TextStyle(color: Colors.white70, fontSize: 12))),
            ])),
          const SizedBox(height: 20),
          const Text("Preguntas frecuentes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...[
            {"q": "¿Cuánto demora mi pedido?", "a": "El tiempo estimado depende del restaurante y la distancia. Normalmente entre 20 y 45 minutos."},
            {"q": "¿Puedo cancelar mi pedido?", "a": "Puedes cancelar mientras el restaurante no haya aceptado. Escríbenos si necesitas ayuda."},
            {"q": "¿Cuáles son los métodos de pago?", "a": "Aceptamos efectivo, tarjeta de crédito/débito y transferencia bancaria."},
            {"q": "¿Qué hago si mi pedido llegó incompleto?", "a": "Contáctanos por WhatsApp o email con tu número de pedido y lo solucionamos de inmediato."},
            {"q": "¿Cómo funciona el retiro en tienda?", "a": "Selecciona Retiro al hacer tu pedido. El restaurante te enviará un código cuando esté listo."},
            {"q": "¿Cómo ser aliado de Go Deli?", "a": "Escríbenos a soporte@godeli.cl con los datos de tu negocio. Te contactamos en 24 horas."},
          ].map((faq) => _faqItem(faq["q"]!, faq["a"]!)),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _faqItem(String q, String a) => Theme(
    data: ThemeData().copyWith(dividerColor: Colors.transparent),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(a, style: const TextStyle(color: AppColors.textMedium, fontSize: 13, height: 1.5)))],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_user == null) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("Inicia sesión para ver tu perfil", style: TextStyle(color: AppColors.textLight)),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: () => context.go("/login"), child: const Text("Iniciar sesión")),
    ]));

    final delivered  = _orders.where((o) => o["status"] == "delivered").length;
    final totalSpent = _orders.where((o) => o["status"] == "delivered")
        .fold(0.0, (s, o) => s + ((o["total"] as num?) ?? 0));

    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(child: Column(children: [
        const SizedBox(height: 16),
        CircleAvatar(radius: 48, backgroundColor: AppColors.primary,
          child: Text((_user!["name"] as String? ?? "U")[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900))),
        const SizedBox(height: 12),
        Text(_user!["name"] ?? "", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(_user!["email"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
        if (_user!["phone"] != null)
          Text(_user!["phone"], style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
        const SizedBox(height: 20),
      ])),

      Row(children: [
        Expanded(child: _statCard("$delivered", "Pedidos")),
        const SizedBox(width: 10),
        Expanded(child: _statCard("${_favorites.length}", "Favoritos")),
        const SizedBox(width: 10),
        Expanded(child: _statCard(_fmt(totalSpent), "Gastado")),
      ]),
      const SizedBox(height: 20),

      _menuItem(Icons.favorite_border, "Mis favoritos (${_favorites.length})",
          () => setState(() => _showFavs = !_showFavs)),
      if (_showFavs) ...[
        const SizedBox(height: 8),
        if (_favorites.isEmpty)
          Container(padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border)),
            child: const Center(child: Text("Sin tiendas favoritas aún",
                style: TextStyle(color: AppColors.textLight))))
        else
          ..._favorites.map((fav) {
            final store = fav["stores"] as Map<String, dynamic>?;
            if (store == null) return const SizedBox();
            return GestureDetector(
              onTap: () => context.push("/store/${store["id"]}"),
              child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Text(store["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(store["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(store["category"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                  ])),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
                ]),
              ),
            );
          }),
        const SizedBox(height: 8),
      ],

      _menuItem(Icons.receipt_long_outlined, "Mis pedidos ($delivered realizados)", _showOrders),
      _menuItem(Icons.notifications_outlined, "Notificaciones", () => context.push("/notifications")),
      _menuItem(Icons.location_on_outlined, "Mis direcciones (${_addresses.length})", _showAddresses),
      _menuItem(Icons.help_outline, "Ayuda y soporte", _showHelp),
      const SizedBox(height: 24),

      ElevatedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout),
        label: const Text("Cerrar sesión"),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error, minimumSize: const Size(double.infinity, 50)),
      ),
      const SizedBox(height: 16),
      const Center(child: Text("Go Deli v1.0.0",
          style: TextStyle(color: AppColors.textLight, fontSize: 12))),
      const SizedBox(height: 32),
    ]);
  }

  Widget _statCard(String value, String label) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border)),
    child: Column(children: [
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
        const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
      ]),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// _ChangeAddressSheet — GPS + Places autocomplete + saved addresses
// ════════════════════════════════════════════════════════════════════════════

class _ChangeAddressSheet extends StatefulWidget {
  final String currentAddress;
  const _ChangeAddressSheet({required this.currentAddress});
  @override
  State<_ChangeAddressSheet> createState() => _ChangeAddressSheetState();
}

class _ChangeAddressSheetState extends State<_ChangeAddressSheet> {
  final _sb         = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  final _dio        = Dio();

  bool _loadingGps    = false;
  bool _searching     = false;
  List<Map<String, dynamic>> _suggestions  = [];
  List<Map<String, dynamic>> _savedAddrs   = [];

  @override
  void initState() {
    super.initState();
    _loadSavedAddresses();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedAddresses() async {
    try {
      final user = _sb.auth.currentUser;
      if (user == null) return;
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).maybeSingle();
      if (u == null) return;
      final data = await _sb.from("user_addresses").select()
          .eq("user_id", u["id"]).order("is_default", ascending: false);
      if (mounted) setState(() => _savedAddrs = List<Map<String, dynamic>>.from(data));
    } catch (_) {}
  }

  Future<void> _useGps() async {
    setState(() => _loadingGps = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        _showError("Permiso de ubicación no concedido.");
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      String address;
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        final pm    = marks.firstOrNull;
        if (pm != null) {
          final parts = [pm.street, pm.locality, pm.administrativeArea]
              .where((p) => p != null && p.isNotEmpty).toList();
          address = parts.join(", ");
        } else {
          address = "${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}";
        }
      } catch (_) {
        address = "${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}";
      }
      if (mounted) Navigator.pop(context, address);
    } catch (_) {
      _showError("No se pudo obtener tu ubicación.");
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 3) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    if (mounted) setState(() => _searching = true);
    try {
      final resp = await _dio.get(
        "https://maps.googleapis.com/maps/api/place/autocomplete/json",
        queryParameters: {
          "input":      query,
          "key":        AppConfig.googleMapsApiKey,
          "language":   "es",
          "components": "country:cl",
        },
      );
      final preds = (resp.data["predictions"] as List?) ?? [];
      if (mounted) setState(() {
        _suggestions = preds.cast<Map<String, dynamic>>();
        _searching   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final placeId = place["place_id"] as String?;
    if (placeId == null) return;
    try {
      final resp = await _dio.get(
        "https://maps.googleapis.com/maps/api/place/details/json",
        queryParameters: {
          "place_id": placeId,
          "key":      AppConfig.googleMapsApiKey,
          "fields":   "formatted_address",
        },
      );
      final address = resp.data["result"]?["formatted_address"] as String? ?? "";
      if (address.isNotEmpty && mounted) Navigator.pop(context, address);
    } catch (_) {
      _showError("Error al seleccionar la dirección.");
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.88),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: AppColors.border, borderRadius: BorderRadius.circular(2))),
        // Title
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text("¿Dónde te entregamos?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kDark)),
          ),
        ),
        const SizedBox(height: 12),

        // GPS button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loadingGps ? null : _useGps,
              icon: _loadingGps
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(_loadingGps ? "Detectando..." : "Usar mi ubicación actual",
                style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange, foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: "Buscar dirección...",
              prefixIcon: const Icon(Icons.search, color: _kOrange),
              suffixIcon: _searching
                  ? const Padding(padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: _kPurple, strokeWidth: 2)))
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kPurple, width: 2)),
            ),
            onChanged: _searchPlaces,
          ),
        ),
        const SizedBox(height: 8),

        Flexible(child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // Autocomplete suggestions
            if (_suggestions.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 6),
                child: Text("Sugerencias",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textLight, letterSpacing: 0.5)),
              ),
              ...List.generate(_suggestions.length.clamp(0, 5), (i) {
                final s    = _suggestions[i];
                final main = s["structured_formatting"]?["main_text"] as String?
                    ?? s["description"] as String? ?? "";
                final sub  = s["structured_formatting"]?["secondary_text"] as String? ?? "";
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.location_on, color: _kOrange, size: 20),
                  title: Text(main,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: sub.isNotEmpty
                      ? Text(sub, style: const TextStyle(fontSize: 11,
                          color: AppColors.textLight))
                      : null,
                  onTap: () => _selectSuggestion(s),
                );
              }),
              const Divider(),
            ],

            // Saved addresses
            if (_savedAddrs.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 6),
                child: Text("Mis direcciones",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textLight, letterSpacing: 0.5)),
              ),
              ..._savedAddrs.map((a) {
                final isDefault = a["is_default"] == true;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _kPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                    child: Icon(
                      a["label"] == "Casa" ? Icons.home_outlined
                        : a["label"] == "Trabajo" ? Icons.work_outline
                        : Icons.location_on_outlined,
                      color: _kPurple, size: 18),
                  ),
                  title: Row(children: [
                    Text(a["label"] ?? "Dirección",
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _kPurple, borderRadius: BorderRadius.circular(6)),
                        child: const Text("Principal",
                          style: TextStyle(color: Colors.white,
                              fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  subtitle: Text(a["address"] ?? "",
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, a["address"] as String),
                );
              }),
            ],
          ],
        )),
      ]),
    );
  }
}
