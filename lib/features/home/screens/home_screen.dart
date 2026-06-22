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
import "../../../config/app_routes.dart";
import "../../../services/notification_service.dart";
import "../../../services/notification_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/utils/category_match.dart";
import "../../../core/services/location_service.dart";
import "../../../providers/cart_provider.dart";
import "../../mercados/screens/mercados_screen.dart";
import "../../servicios/screens/servicios_screen.dart";
import "../widgets/store_card.dart";
import "../../pedidos/screens/pedidos_screen.dart";
import "../../profile/screens/profile_screen.dart";

// Palette shortcuts used throughout this file
const _kDark   = AppColors.homeDark;
const _kOrange = AppColors.homeOrange;
const _kPurple = AppColors.homePurple;
const _kBg     = AppColors.homeBackground;
const _kBorder = AppColors.homeCardBorder;

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
  List<_HomeSection>          _homeSections = [];
  bool _loadingHome = true;
  Map<String, List<Map<String, dynamic>>> _featuredItems = {};
  double? _userLat;
  double? _userLng;

  // Comuna del usuario
  String? _userCommuneId;
  String? _userCommuneName;
  String? _userRegionName;

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
    // Procesar deep link pendiente de FCM (app abierta desde notificación)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final data = NotificationService.pendingFcmData;
      if (data != null) {
        NotificationService.pendingFcmData = null;
        _handleFcmData(data);
      }
    });
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

  void _handleFcmData(Map<String, dynamic> data) {
    final route = data["route"] ?? "";
    final storeId = data["store_id"] ?? "";
    final productId = data["product_id"] ?? "";
    final url = data["url"] ?? "";
    if (route == "store" && storeId.isNotEmpty) {
      appRouter.push("/store/$storeId");
    } else if (route == "product" && storeId.isNotEmpty) {
      appRouter.push("/product/$storeId");
    } else if (route == "url" && url.isNotEmpty) {
      appRouter.push("/home");
    } else if (route == "home") {
      appRouter.push("/home");
    }
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
      // Cargar comuna guardada
      final savedCommune = await LocationService.loadSavedCommune();
      if (savedCommune != null && mounted) {
        setState(() {
          _userCommuneId   = savedCommune['commune_id'];
          _userCommuneName = savedCommune['commune_name'];
          _userRegionName  = savedCommune['region_name'];
        });
      } else {
        // Fallback: si no hay comuna guardada pero sí hay coordenadas (GPS),
        // re-detectar la comuna desde las coordenadas
        final prefs = await SharedPreferences.getInstance();
        final lat = prefs.getDouble("delivery_lat");
        final lng = prefs.getDouble("delivery_lng");
        if (lat != null && lng != null) {
          final detected = await LocationService().detectAndSaveCommune(lat, lng);
          if (detected != null && mounted) {
            setState(() {
              _userCommuneId   = detected['commune_id'];
              _userCommuneName = detected['commune_name'];
              _userRegionName  = detected['region_name'];
            });
          }
        }
      }

      // Categories (cached 5 min)
      if (forceRefreshCache || _catStale) {
        final raw = await _sb.from("categories")
            .select()
            .eq("is_active", true)
            .order("sort_order");
        _cachedCategories = List<Map<String, dynamic>>.from(raw).where((c) {
          final s = (c["screens"] as String?) ?? "all";
          return s == "all" || s.split(",").map((x) => x.trim()).contains("home");
        }).toList();
        _catCachedAt = DateTime.now();
      }

      // Banners (cached 5 min, date/commune filter client-side)
      if (forceRefreshCache || _bannerStale) {
        final now = DateTime.now().toUtc();
        final raw = await _sb.from("banners")
            .select()
            .eq("is_active", true)
            .eq("banner_type", "web_home")
            .order("sort_order")
            .limit(20); // Fetch de más para filtrar fechas/comunas
        _cachedBanners = (raw as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((b) {
              // Date range filter
              final startDate = b['start_date'] as String?;
              final endDate   = b['end_date']   as String?;
              if (startDate != null && startDate.isNotEmpty) {
                try { if (now.isBefore(DateTime.parse(startDate))) return false; } catch (_) {}
              }
              if (endDate != null && endDate.isNotEmpty) {
                try { if (now.isAfter(DateTime.parse(endDate))) return false; } catch (_) {}
              }
              // Commune filter: global (null) or matches user commune
              if (_userCommuneId != null) {
                final bCommune = b['commune_id'] as String?;
                if (bCommune != null && bCommune != _userCommuneId) return false;
              }
              return true;
            }).toList();
        _bannerCachedAt = DateTime.now();
      }

      // Stores: filtrar por comuna (si no hay comuna, mostrar todas)
      List<dynamic> storesRaw;
      if (_userCommuneId != null) {
        storesRaw = await _sb.from("stores")
            .select()
            .eq("status", "approved")
            .eq("is_active", true)
            .eq("commune_id", _userCommuneId!);
      } else {
        storesRaw = await _sb.from("stores").select().eq("status", "approved").eq("is_active", true);
      }

      // Dynamic home sections: filter by screen server-side, commune client-side
      final sectionsRaw = await _sb
          .from("home_sections")
          .select("*, home_section_stores(sort_order, product_id, stores(id, name, logo_url, cover_url, emoji, rating, delivery_time, delivery_fee_client, delivery_fee_store, is_open, category, sponsored), menu_items!home_section_stores_product_id_fkey(id, name, price, image_url))")
          .or('screen.eq.home,screen.eq.all')
          .eq("is_active", true)
          .order("sort_order");
      final sections = (sectionsRaw)
          .cast<Map<String, dynamic>>()
          .where((s) {
            if (_userCommuneId != null) {
              final sCommune = s['commune_id'] as String?;
              // Mostrar secciones globales (null) o de la comuna del usuario
              if (sCommune != null && sCommune != _userCommuneId) return false;
            }
            return true;
          })
          .map((s) => _HomeSection.fromJson(s as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      // Featured items for highlighted stores
      final allStoresList = (storesRaw).cast<Map<String, dynamic>>();
      final featIds = allStoresList
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

      // Banners asignados a secciones: excluirlos del carrusel principal
      final sectionBannerIds = sections
          .where((s) => s.sectionType == 'banner' && s.bannerId != null)
          .map((s) => s.bannerId)
          .toSet();
      final carouselBanners = (List<Map<String, dynamic>>.from(_cachedBanners ?? []))
          .where((b) => !sectionBannerIds.contains(b['id'] as String?))
          .toList();

      if (mounted) setState(() {
        _categories    = List<Map<String, dynamic>>.from(_cachedCategories ?? []);
        _banners       = carouselBanners;
        _allStores     = allStoresList;
        _homeSections  = sections;
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

        // ── Si hay categoría seleccionada: resultados inmediatos ─────────────
        if (_selectedCat != null) ...[
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _nearbyCard(_nearbyStores[i]),
                  childCount: _nearbyStores.length,
                ),
              ),
            ),
        ] else ...[
          // ── Secciones dinámicas ─────────────────────────────────────────────
          if (_loadingHome)
            SliverToBoxAdapter(child: _storeShimmer())
          else
            ..._homeSections.map((sec) => SliverToBoxAdapter(
              child: sec.sectionType == "banner"
                  ? _buildBannerSection(sec)
                  : _buildStoreSection(sec),
            )),

          // ── Cerca de ti ────────────────────────────────────────────────────
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
        ],
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
      // Recargar datos con la nueva comuna
      _loadData(forceRefreshCache: true);
    }
  }

  // ── Shimmer helpers ───────────────────────────────────────────────────────
  static const _shimmerBase      = Color(0xFFDDD0F0);
  static const _shimmerHighlight = Color(0xFFF5F0FF);

  Widget _bannerShimmer() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Shimmer.fromColors(baseColor: _shimmerBase, highlightColor: _shimmerHighlight,
      child: const AspectRatio(aspectRatio: 2, child: SizedBox.expand()),
    ),
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
        AspectRatio(
          aspectRatio: 2,
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

  // ══════════════════════════════════════════════════════════════════════════
  // SECCIONES DINÁMICAS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStoreSection(_HomeSection sec) {
    if (sec.stores.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(sec.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kDark)),
        ),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: sec.stores.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: 200,
              child: StoreCard(
                store: sec.stores[i],
                displayMode: sec.displayMode,
                onTap: () {
                  final s = sec.stores[i];
                  if (sec.displayMode == 'product') {
                    final productId = (s['product_data'] as Map<String, dynamic>?)?['id'] as String?;
                    if (productId != null) {
                      context.push('/product/$productId');
                      return;
                    }
                  }
                  context.push('/store/${s["id"]}', extra: s);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBannerSection(_HomeSection sec) {
    // Mostrar solo el banner específico de esta sección, no todos los banners
    if (sec.bannerId == null) return const SizedBox.shrink();
    // Buscar en _cachedBanners (lista completa), no en _banners (solo carrusel)
    final banner = (_cachedBanners ?? <Map<String, dynamic>>[]).firstWhere(
      (b) => b['id'] == sec.bannerId,
      orElse: () => <String, dynamic>{},
    );
    if (banner.isEmpty) return const SizedBox.shrink();
    final imgUrl = banner["image_url"] as String?;
    Color bg = _kOrange;
    try {
      final hex = (banner["bg_color"] as String?)?.replaceAll("#", "");
      if (hex != null && hex.length == 6) bg = Color(int.parse("FF$hex", radix: 16));
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _handleBannerTap(banner),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: AspectRatio(
            aspectRatio: 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: bg,
                image: imgUrl != null ? DecorationImage(
                  image: NetworkImage(imgUrl),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.18), BlendMode.darken),
                ) : null,
                boxShadow: [
                  BoxShadow(
                    color: bg.withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _HomeSection — modelo para secciones dinámicas del home
// ════════════════════════════════════════════════════════════════════════════
class _HomeSection {
  final String id;
  final String title;
  final String sectionType;
  final String screen;
  final int sortOrder;
  final String displayMode; // 'cover' | 'logo' | 'product'
  final String? bannerId;
  final List<Map<String, dynamic>> stores;

  _HomeSection.fromJson(Map<String, dynamic> j)
      : id          = j['id'] as String,
        title       = j['title'] as String? ?? '',
        sectionType = j['section_type'] as String? ?? 'stores',
        screen      = j['screen'] as String? ?? 'home',
        sortOrder   = (j['sort_order'] as num?)?.toInt() ?? 0,
        displayMode = j['display_mode'] as String?
            ?? ((j['show_logos'] as bool? ?? false) ? 'logo' : 'cover'),
        bannerId    = j['banner_id'] as String?,
        stores      = (j['home_section_stores'] as List? ?? [])
            .where((s) => s['stores'] != null)
            .map((s) {
              final storeMap = Map<String, dynamic>.from(s['stores'] as Map);
              // Adjuntar datos del producto si existen
              if (s['menu_items'] != null) {
                storeMap['product_data'] = Map<String, dynamic>.from(s['menu_items'] as Map);
              }
              return storeMap;
            })
            .toList();
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

      // Detectar comuna desde las coordenadas GPS
      await LocationService().detectAndSaveCommune(pos.latitude, pos.longitude);

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

      // Detectar comuna desde el place_id
      await LocationService().detectFromPlaceId(placeId);

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
                  onTap: () async {
                    final address = a["address"] as String? ?? "";
                    // Detectar comuna desde la dirección guardada
                    try {
                      final locs = await locationFromAddress(address);
                      if (locs.isNotEmpty && mounted) {
                        await LocationService().detectAndSaveCommune(
                          locs.first.latitude,
                          locs.first.longitude,
                        );
                      }
                    } catch (_) {}
                    if (mounted) Navigator.pop(context, address);
                  },
                );
              }),
            ],
          ],
        )),
      ]),
    );
  }
}
