import "dart:async";
import "dart:convert";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:shimmer/shimmer.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/utils/category_match.dart";
import "../../../core/utils/color_utils.dart";
import "../../../providers/cart_provider.dart";

const _kDark   = AppColors.homeDark;
const _kOrange = AppColors.homeOrange;
const _kPurple = AppColors.homePurple;
const _kBg     = AppColors.homeBackground;
const _kBorder = AppColors.homeCardBorder;

class MercadosScreen extends StatefulWidget {
  const MercadosScreen({super.key});
  @override
  State<MercadosScreen> createState() => _MercadosScreenState();
}

class _MercadosScreenState extends State<MercadosScreen> {
  final _sb = Supabase.instance.client;

  int     _mainCatIdx      = 0;
  String? _activeSubCat;

  List<Map<String, dynamic>>                      _stores          = [];
  List<String>                                    _subCats         = [];
  Map<String, List<Map<String, dynamic>>>         _featuredProds   = {};
  Map<String, List<Map<String, dynamic>>>         _currentProds    = {};
  bool _loading         = true;
  bool _loadingProds    = false;

  // Banners
  List<Map<String, dynamic>> _banners     = [];
  int                         _bannerPage  = 0;
  final _bannerPageCtrl = PageController();
  Timer?                      _bannerTimer;

  static final Map<String, _CacheEntry> _cache = {};
  static const _ttl = Duration(minutes: 3);

  // Banner cache
  static List<Map<String, dynamic>>? _cachedBanners;
  static DateTime?                   _bannerCachedAt;
  static const _bannerTtl = Duration(minutes: 5);
  bool get _bannerStale => _bannerCachedAt == null ||
      DateTime.now().difference(_bannerCachedAt!) > _bannerTtl;

  // Category cache (30-min)
  static List<Map<String, dynamic>>? _cachedMainCats;
  static DateTime?                   _catCachedAt;
  static const _catTtl = Duration(minutes: 30);
  bool get _catStale => _catCachedAt == null ||
      DateTime.now().difference(_catCachedAt!) > _catTtl;

  List<Map<String, dynamic>> _dbCats = [];

  List<Map<String, dynamic>> get _allCats => [
    const {"key": "Todas", "emoji": "🔍", "label": "Todas"},
    ..._dbCats.map((c) => {
      "key":       c["name"]      as String? ?? "",
      "emoji":     c["emoji"]     as String? ?? "🏪",
      "label":     c["name"]      as String? ?? "",
      "image_url": c["image_url"] as String?,
    }),
  ];

  String get _catKey {
    final cats = _allCats;
    if (_mainCatIdx >= cats.length) return "Todas";
    return cats[_mainCatIdx]["key"] as String;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startBannerTimer());
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageCtrl.dispose();
    super.dispose();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_banners.length <= 1 || !_bannerPageCtrl.hasClients) return;
      final next = (_bannerPage + 1) % _banners.length;
      _bannerPageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (mounted) setState(() { _loading = true; _activeSubCat = null; });

    // Load banners (5-min cache, date-filtered server-side)
    if (forceRefresh || _bannerStale) {
      try {
        final now = DateTime.now().toIso8601String();
        final raw = await _sb.from("banners")
            .select()
            .eq("is_active", true)
            .eq("banner_type", "web_mercados")
            .or("start_date.is.null,start_date.lte.$now")
            .or("end_date.is.null,end_date.gte.$now")
            .order("sort_order")
            .limit(5);
        _cachedBanners = (raw as List<dynamic>).cast<Map<String, dynamic>>();
        _bannerCachedAt = DateTime.now();
      } catch (_) {}
    }
    if (mounted) setState(() => _banners = List<Map<String,dynamic>>.from(_cachedBanners ?? []));

    // Load main categories from DB (30-min cache)
    if (forceRefresh || _catStale) {
      try {
        final raw = await _sb.from("categories")
            .select()
            .eq("is_active", true)
            .order("sort_order");
        // Aceptar listas de pantallas ("home,mercados") además de "mercados"/"all"
        _cachedMainCats = List<Map<String,dynamic>>.from(raw as List).where((c) {
          final s = (c["screens"] as String?) ?? "all";
          return s == "all" || s.split(",").map((x) => x.trim()).contains("mercados");
        }).toList();
        _catCachedAt = DateTime.now();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _dbCats = List<Map<String,dynamic>>.from(_cachedMainCats ?? []);
        if (_mainCatIdx >= _allCats.length) _mainCatIdx = 0;
      });
    }

    final key    = _catKey;
    final cached = _cache[key];
    if (!forceRefresh && cached != null &&
        DateTime.now().difference(cached.timestamp) < _ttl) {
      if (mounted) setState(() {
        _stores        = cached.stores;
        _subCats       = cached.subCats;
        _featuredProds = cached.products;
        _currentProds  = cached.products;
        _loading       = false;
      });
      return;
    }

    try {
      // 1 – stores
      final storesRaw = await _sb.from("stores").select().eq("is_active", true).eq("status", "approved");

      // Filtro tolerante en cliente: los nombres de categoría del aliado no
      // siempre son idénticos a los del admin ("Supermercado" vs "Mercado",
      // listas separadas por coma, etc.)
      final stores = List<Map<String, dynamic>>.from(storesRaw)
          .where((s) => storeMatchesCategory(s, key == "Todas" ? null : key))
          .toList()
        ..sort((a, b) {
          final fa = a["featured_order"] as int?;
          final fb = b["featured_order"] as int?;
          if (fa != null && fb != null) return fa.compareTo(fb);
          if (fa != null) return -1;
          if (fb != null) return 1;
          return (a["name"] as String? ?? "").compareTo(b["name"] as String? ?? "");
        });

      final storeIds = stores.map((s) => s["id"] as String).toList();

      // 2 – subcategories (skip for "Todas" — cross-category chips are meaningless)
      List<String> subCats = [];
      if (storeIds.isNotEmpty && key != "Todas") {
        final catsRaw = await _sb
            .from("menu_categories")
            .select("name")
            .inFilter("store_id", storeIds)
            .eq("is_visible", true)
            .order("sort_order");
        final seen = <String>{};
        for (final c in catsRaw as List) {
          final name = c["name"] as String?;
          if (name != null && seen.add(name)) subCats.add(name);
        }
      }

      // 3 – featured products (is_featured OR discount_pct > 0)
      Map<String, List<Map<String, dynamic>>> prods = {};
      if (storeIds.isNotEmpty) {
        final raw = await _sb
            .from("menu_items")
            .select()
            .inFilter("store_id", storeIds)
            .eq("is_available", true)
            .or("is_featured.eq.true,discount_pct.gt.0")
            .order("sort_order")
            .limit(60);
        for (final item in (raw as List).cast<Map<String, dynamic>>()) {
          final sid  = item["store_id"] as String;
          final list = prods.putIfAbsent(sid, () => []);
          if (list.length < 6) list.add(item);
        }
      }

      _cache[key] = _CacheEntry(
          stores: stores, subCats: subCats, products: prods,
          timestamp: DateTime.now());

      if (mounted) setState(() {
        _stores        = stores;
        _subCats       = subCats;
        _featuredProds = prods;
        _currentProds  = prods;
        _loading       = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applySubcat(String? name) async {
    if (name == null) {
      setState(() { _activeSubCat = null; _currentProds = _featuredProds; });
      return;
    }
    setState(() { _activeSubCat = name; _loadingProds = true; });
    try {
      final storeIds = _stores.map((s) => s["id"] as String).toList();
      final catsRaw  = await _sb
          .from("menu_categories")
          .select("id,store_id")
          .inFilter("store_id", storeIds)
          .eq("name", name);
      final catIds = (catsRaw as List).map((c) => c["id"] as String).toList();
      if (catIds.isEmpty) {
        if (mounted) setState(() { _currentProds = {}; _loadingProds = false; });
        return;
      }
      final raw = await _sb
          .from("menu_items")
          .select()
          .inFilter("category_id", catIds)
          .eq("is_available", true)
          .order("sort_order")
          .limit(60);
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final item in (raw as List).cast<Map<String, dynamic>>()) {
        final sid  = item["store_id"] as String;
        final list = grouped.putIfAbsent(sid, () => []);
        if (list.length < 6) list.add(item);
      }
      if (mounted) setState(() { _currentProds = grouped; _loadingProds = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingProds = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      backgroundColor: _kBg,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: cart.isEmpty ? null : _buildCartFab(cart),
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: _kOrange,
        child: CustomScrollView(slivers: [
          _buildAppBar(cart),
          if (!_loading && _subCats.isNotEmpty) _buildSubCatRow(),
          ..._buildBody(cart),
        ]),
      ),
    );
  }

  // ── App bar ──────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar(CartProvider cart) => SliverAppBar(
    pinned: true,
    floating: false,
    automaticallyImplyLeading: false,
    backgroundColor: Colors.transparent,
    flexibleSpace: const GradientFlexibleSpace(),
    toolbarHeight: 60,
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(76),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _allCats.length,
            itemBuilder: (_, i) {
              final cat    = _allCats[i];
              final active = _mainCatIdx == i;
              final imgUrl = cat["image_url"] as String?;
              return GestureDetector(
                onTap: () {
                  if (active) return;
                  if ((cat["key"] as String).contains("otiller")) {
                    _showAgeVerification(i);
                  } else {
                    setState(() => _mainCatIdx = i);
                    _loadData();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: active
                        ? _kOrange.withOpacity(0.25)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: active
                        ? Border.all(color: _kOrange, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      imgUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(imgUrl,
                                  width: 26, height: 26, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Text(
                                      cat["emoji"] as String,
                                      style: const TextStyle(fontSize: 20))))
                          : Text(cat["emoji"] as String,
                              style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 2),
                      Text(cat["label"] as String,
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: active ? _kOrange : Colors.white.withOpacity(0.85),
                              fontFamily: "Nunito")),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("Mercados y minimarkets",
          style: TextStyle(color: Colors.white, fontSize: 15,
              fontWeight: FontWeight.w900, fontFamily: "Nunito")),
      Text(_mainCatIdx == 0 ? "Todas las categorías" : (_allCats.length > _mainCatIdx ? _allCats[_mainCatIdx]["label"] as String : ""),
          style: TextStyle(color: Colors.white.withOpacity(0.85),
              fontSize: 11, fontFamily: "Nunito")),
    ]),
    actions: [
      IconButton(
        icon: const Icon(Icons.search, color: Colors.white),
        onPressed: () => showSearch(
            context: context,
            delegate: _StoreSearchDelegate(_stores)),
      ),
      const SizedBox(width: 4),
    ],
  );

  // ── Subcategory chips ────────────────────────────────────────────────────────

  SliverToBoxAdapter _buildSubCatRow() => SliverToBoxAdapter(
    child: Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _chip("Todo", null),
            ..._subCats.map((s) => _chip(s, s)),
          ],
        ),
      ),
    ),
  );

  Widget _chip(String label, String? value) {
    final active = _activeSubCat == value;
    return GestureDetector(
      onTap: () => _applySubcat(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _kOrange : Colors.white,
          border: Border.all(
              color: active ? _kOrange : const Color(0x339E00FF)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.textLight)),
      ),
    );
  }

  // ── Banners widget ────────────────────────────────────────────────────────────

  Widget _buildBannersWidget() {
    if (_banners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _bannerPageCtrl,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _bannerPage = i),
            itemBuilder: (_, i) {
              final b      = _banners[i];
              final imgUrl = b["image_url"] as String?;
              final bg = parseHexColor(b["bg_color"] as String?, fallback: _kOrange);
              return GestureDetector(
                onTap: () => _handleBannerTap(b),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: bg,
                    image: imgUrl != null
                        ? DecorationImage(
                            image: NetworkImage(imgUrl),
                            fit: BoxFit.cover,
                            colorFilter: ColorFilter.mode(
                                Colors.black.withOpacity(0.15), BlendMode.darken))
                        : null,
                    boxShadow: [BoxShadow(
                        color: bg.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4))],
                  ),
                  child: imgUrl == null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (b["title"] != null)
                                Text(b["title"] as String,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: "Nunito")),
                              if (b["subtitle"] != null) ...[
                                const SizedBox(height: 4),
                                Text(b["subtitle"] as String,
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.85),
                                        fontSize: 13)),
                              ],
                            ],
                          ),
                        )
                      : Stack(children: [
                          if (b["title"] != null)
                            Positioned(
                              bottom: 16, left: 16, right: 16,
                              child: Text(b["title"] as String,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: "Nunito",
                                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
                            ),
                        ]),
                ),
              );
            },
          ),
        ),
        if (_banners.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_banners.length, (i) =>
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _bannerPage == i ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _bannerPage == i ? _kOrange : _kBorder,
                  borderRadius: BorderRadius.circular(3),
                ),
              )),
          ),
        ],
      ]),
    );
  }

  void _handleBannerTap(Map<String, dynamic> b) {
    final type  = b["link_type"]  as String?;
    final value = b["link_value"] as String?;
    if (type == null || type == "none" || value == null || value.isEmpty) return;
    if (type == "store")    context.push("/store/$value");
    if (type == "url")      launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
  }

  // ── Body slivers ─────────────────────────────────────────────────────────────

  List<Widget> _buildBody(CartProvider cart) {
    if (_loading) {
      return [SliverToBoxAdapter(child: _buildShimmer())];
    }
    if (_stores.isEmpty) {
      return [
        if (_banners.isNotEmpty) SliverToBoxAdapter(child: _buildBannersWidget()),
        SliverFillRemaining(hasScrollBody: false, child: _buildEmpty()),
      ];
    }
    return [
      if (_banners.isNotEmpty) SliverToBoxAdapter(child: _buildBannersWidget()),
      if (_loadingProds)
        const SliverToBoxAdapter(
          child: LinearProgressIndicator(
              color: _kOrange,
              backgroundColor: _kBg,
              minHeight: 2),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _buildStoreCard(_stores[i], cart),
            childCount: _stores.length,
          ),
        ),
      ),
    ];
  }

  // ── Store card ───────────────────────────────────────────────────────────────

  Widget _buildStoreCard(Map<String, dynamic> store, CartProvider cart) {
    final storeId   = store["id"] as String;
    final logoUrl   = store["logo_url"] as String?;
    final sponsored = store["sponsored"] == true;
    final isOpen    = store["is_open"] as bool? ?? true;
    final fee       = (store["delivery_fee_client"] as num?)?.toInt() ?? 0;
    final products  = _currentProds[storeId] ?? [];

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
        // ── header row ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 44, height: 44,
                child: logoUrl != null
                    ? Image.network(logoUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarPh(store))
                    : _avatarPh(store),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(store["name"] ?? "",
                        style: const TextStyle(fontWeight: FontWeight.w800,
                            fontSize: 14, color: _kDark),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (sponsored) _badge("Destacado", _kOrange),
                  if (!isOpen)
                    _badge("Cerrado", AppColors.error,
                        bg: AppColors.error.withOpacity(0.1),
                        textColor: AppColors.error),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star_rounded, color: _kOrange, size: 12),
                  Text(" ${store["rating"] ?? "5.0"}",
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  const Text(" · ",
                      style: TextStyle(color: AppColors.textLight, fontSize: 11)),
                  const Icon(Icons.access_time_rounded,
                      size: 11, color: AppColors.textLight),
                  Text(" ${store["delivery_time"] ?? "30-45"} min",
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textLight)),
                  const Text(" · ",
                      style: TextStyle(color: AppColors.textLight, fontSize: 11)),
                  fee == 0
                      ? Text("Envío gratis",
                          style: TextStyle(fontSize: 11,
                              color: _kPurple, fontWeight: FontWeight.w700))
                      : Text(_fmt(fee),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textLight)),
                ]),
              ],
            )),
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
        // ── products scroll ───────────────────────────────
        if (products.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 152,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: products.length,
              itemBuilder: (_, i) =>
                  _buildMiniCard(products[i], store, cart),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _badge(String text, Color color,
      {Color? bg, Color? textColor}) =>
      Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: bg ?? color,
            borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                color: textColor ?? Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800)),
      );

  Widget _avatarPh(Map<String, dynamic> store) => Container(
    color: AppColors.secondary,
    child: Center(child: Text(
        store["emoji"] as String? ?? "🛒",
        style: const TextStyle(fontSize: 22))),
  );

  // ── Mini product card ────────────────────────────────────────────────────────

  Widget _buildMiniCard(Map<String, dynamic> item,
      Map<String, dynamic> store, CartProvider cart) {
    final imgUrl   = item["image_url"] as String?;
    final discPct  = (item["discount_pct"] as int?) ?? 0;
    final price    = (item["price"] as num?)?.toInt() ?? 0;
    final origPrice = (item["original_price"] as num?)?.toInt();
    final showOrig = discPct > 0 && origPrice != null && origPrice > price;

    return GestureDetector(
      // Abrir la ficha completa del producto (detalles por categoría)
      onTap: () => context.push("/product/${item["id"]}"),
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 100, height: 70,
                  child: imgUrl != null
                      ? Image.network(imgUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _prodPh(item))
                      : _prodPh(item),
                ),
              ),
              if (discPct > 0)
                Positioned(
                  top: 4, left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: _kOrange, borderRadius: BorderRadius.circular(6)),
                    child: Text("-$discPct%",
                        style: const TextStyle(color: Colors.white,
                            fontSize: 9, fontWeight: FontWeight.w900)),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(item["name"] as String? ?? "",
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: _kDark),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const Spacer(),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showOrig)
                    Text(_fmt(origPrice as num),
                        style: const TextStyle(
                            fontSize: 9, color: AppColors.textLight,
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
                            .reduce((a, b) => a < b ? a : b);
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
              )),
              GestureDetector(
                onTap: () => _itemHasVariants(item)
                    ? context.push("/product/${item["id"]}")
                    : _addToCart(item, store, cart),
                child: Container(
                  width: 24, height: 24,
                  decoration: const BoxDecoration(
                      color: _kOrange, shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: Colors.white, size: 14),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _prodPh(Map<String, dynamic> item) => Container(
    color: _kBg,
    child: Center(child: Text(
        item["emoji"] as String? ?? "🛒",
        style: const TextStyle(fontSize: 28))),
  );

  // ── Cart logic ───────────────────────────────────────────────────────────────

  bool _itemHasVariants(Map<String, dynamic> item) {
    // Variantes, grupos de variantes, opciones o recomendaciones (todas se
    // configuran en el panel de aliados) requieren pasar por el detalle.
    for (final key in const ["variants", "variant_groups", "options", "recommendations"]) {
      try {
        final v = item[key];
        if (v == null) continue;
        final raw = v is String ? (v.isNotEmpty ? jsonDecode(v) as List : const []) : v as List;
        if (raw.isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
  }

  void _addToCart(Map<String, dynamic> item, Map<String, dynamic> store,
      CartProvider cart) {
    final storeId   = store["id"] as String;
    final storeName = store["name"] as String? ?? "";
    final cartItem  = CartItem(
      id:        item["id"] as String,
      storeId:   storeId,
      storeName: storeName,
      name:      item["name"] as String? ?? "",
      price:     (item["price"] as num).toInt(),
      emoji:     item["emoji"] as String? ?? "🛒",
      imageUrl:  item["image_url"] as String?,
    );

    if (cart.currentStoreId != null && cart.currentStoreId != storeId) {
      final fromStore = cart.items.isNotEmpty
          ? cart.items.first.storeName
          : "otra tienda";
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("¿Vaciar carrito?",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: Text(
              "Ya tienes productos de $fromStore. "
              "¿Vaciar carrito y agregar de $storeName?",
              style: const TextStyle(fontSize: 14, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancelar",
                  style: TextStyle(fontWeight: FontWeight.w700,
                      color: AppColors.textLight)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                cart.clearCart();
                cart.addItem(cartItem);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange, foregroundColor: Colors.white),
              child: const Text("Vaciar y agregar",
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    } else {
      cart.addItem(cartItem);
    }
  }

  // ── Cart FAB ─────────────────────────────────────────────────────────────────

  Widget _buildCartFab(CartProvider cart) => GestureDetector(
    onTap: () => context.push("/cart"),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _kOrange,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: _kOrange.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(
          "Ver carrito · ${cart.itemCount} "
          "${cart.itemCount == 1 ? "producto" : "productos"} "
          "· ${_fmt(cart.subtotal)}",
          style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w800, fontSize: 13,
              fontFamily: "Nunito"),
        ),
      ]),
    ),
  );

  // ── Shimmer / empty ───────────────────────────────────────────────────────────

  Widget _buildShimmer() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Column(
      children: List.generate(3, (_) => Shimmer.fromColors(
        baseColor: const Color(0xFFDDD0F0),
        highlightColor: const Color(0xFFF5F0FF),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 120,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16)),
        ),
      )),
    ),
  );

  Widget _buildEmpty() {
    final cats = _allCats;
    final cat = cats.length > _mainCatIdx ? cats[_mainCatIdx] : cats[0];
    return Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(cat["emoji"] as String, style: const TextStyle(fontSize: 64)),
        const SizedBox(height: 16),
        Text(
          "No hay ${cat["label"]}s disponibles\ncerca de ti aún",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16,
              fontWeight: FontWeight.w700, color: AppColors.textLight),
        ),
      ],
    ));
  }

  // ── Age verification ──────────────────────────────────────────────────────────

  void _showAgeVerification(int targetIdx) => showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("🍺 Verificación de edad",
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: const Text(
          "Esta sección contiene productos con alcohol. "
          "¿Confirmas que eres mayor de 18 años?",
          style: TextStyle(fontSize: 15, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("No, soy menor",
              style: TextStyle(color: AppColors.error,
                  fontWeight: FontWeight.w700)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            setState(() => _mainCatIdx = targetIdx);
            _loadData();
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text("Sí, soy mayor de 18"),
        ),
      ],
    ),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _fmt(num p) => "\$${p.toStringAsFixed(0).replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
}

// ── Cache model ────────────────────────────────────────────────────────────────

class _CacheEntry {
  final List<Map<String, dynamic>> stores;
  final List<String> subCats;
  final Map<String, List<Map<String, dynamic>>> products;
  final DateTime timestamp;
  const _CacheEntry({
    required this.stores,
    required this.subCats,
    required this.products,
    required this.timestamp,
  });
}

// ── Search delegate ────────────────────────────────────────────────────────────

class _StoreSearchDelegate extends SearchDelegate<String> {
  final List<Map<String, dynamic>> stores;

  _StoreSearchDelegate(this.stores)
      : super(searchFieldLabel: "Buscar tiendas...");

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context).copyWith(
    appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.secondary, foregroundColor: Colors.white),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
    ),
  );

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = ""),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ""));

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final q        = query.toLowerCase().trim();
    final filtered = q.isEmpty
        ? stores
        : stores.where((s) {
            final name = (s["name"] as String? ?? "").toLowerCase();
            final cat  = (s["category"] as String? ?? "").toLowerCase();
            return name.contains(q) || cat.contains(q);
          }).toList();

    if (filtered.isEmpty) return const Center(
      child: Text("Sin resultados",
          style: TextStyle(color: AppColors.textLight)));

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final s = filtered[i];
        return ListTile(
          leading: Text(s["emoji"] as String? ?? "🛒",
              style: const TextStyle(fontSize: 28)),
          title: Text(s["name"] as String? ?? "",
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            "${s["category"] ?? ""} · "
            "${s["delivery_time"] ?? "30-45"} min",
            style: const TextStyle(color: AppColors.textLight, fontSize: 12),
          ),
          trailing: const Icon(Icons.arrow_forward_ios,
              size: 14, color: AppColors.textLight),
          onTap: () {
            close(context, s["id"] as String);
            context.push("/store/${s["id"]}");
          },
        );
      },
    );
  }
}
