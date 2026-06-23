import "dart:async";
import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:shimmer/shimmer.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/utils/color_utils.dart";
import "../../../core/utils/price_formatter.dart";
import "../../../core/services/location_service.dart";

const _kDark   = AppColors.homeDark;
const _kOrange = AppColors.homeOrange;
const _kPurple = AppColors.homePurple;
const _kBorder = AppColors.homeCardBorder;
const _kBg     = AppColors.homeBackground;

class ServiciosScreen extends StatefulWidget {
  const ServiciosScreen({super.key});
  @override
  State<ServiciosScreen> createState() => _ServiciosScreenState();
}

class _CacheEntry {
  final List<Map<String, dynamic>> providers;
  final DateTime timestamp;
  _CacheEntry({required this.providers, required this.timestamp});
}

class _ServiciosScreenState extends State<ServiciosScreen> {
  static const _ttl       = Duration(minutes: 5);
  static const _bannerTtl = Duration(minutes: 5);
  static const _catTtl    = Duration(minutes: 30);
  static final Map<String, _CacheEntry> _cache = {};

  // Banner cache
  static List<Map<String, dynamic>>? _cachedBanners;
  static DateTime?                   _bannerCachedAt;
  bool get _bannerStale => _bannerCachedAt == null ||
      DateTime.now().difference(_bannerCachedAt!) > _bannerTtl;

  // Category cache — ahora usa tabla categories con filtro screens='servicios'
  static List<Map<String, dynamic>>? _cachedServiceCats;
  static DateTime?                   _catCachedAt;
  bool get _catStale => _catCachedAt == null ||
      DateTime.now().difference(_catCachedAt!) > _catTtl;

  List<Map<String, dynamic>> _dbServiceCats = [];

  List<Map<String, dynamic>> get _allCats => [
    const {"key": "Todo", "emoji": "🔧", "label": "Todo"},
    ..._dbServiceCats.map((c) => {
      "key":       c["name"]      as String? ?? "",
      "emoji":     c["emoji"]     as String? ?? "🔧",
      "label":     c["name"]      as String? ?? "",
      "image_url": c["image_url"] as String?,
    }),
  ];

  String get _catKey {
    final cats = _allCats;
    if (_catIdx >= cats.length) return "Todo";
    return cats[_catIdx]["key"] as String;
  }

  int    _catIdx    = 0;
  bool   _loading   = true;
  String? _error;
  List<Map<String, dynamic>> _providers = [];
  String? _communeId;

  // Banners
  List<Map<String, dynamic>> _banners    = [];
  int                         _bannerPage = 0;
  final _bannerPageCtrl = PageController();
  Timer?                      _bannerTimer;

  final _sb = Supabase.instance.client;

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

  Future<void> _loadData({bool forceRefresh = false}) async {
    // Load banners (5-min cache, date-filtered client-side)
    if (forceRefresh || _bannerStale) {
      try {
        final now = DateTime.now().toUtc();
        final raw = await _sb.from("banners")
            .select()
            .eq("is_active", true)
            .eq("banner_type", "web_servicios")
            .order("sort_order")
            .limit(10);
        _cachedBanners = (raw as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((b) {
              final startDate = b['start_date'] as String?;
              final endDate   = b['end_date']   as String?;
              if (startDate != null && startDate.isNotEmpty) {
                try { if (now.isBefore(DateTime.parse(startDate))) return false; } catch (_) {}
              }
              if (endDate != null && endDate.isNotEmpty) {
                try { if (now.isAfter(DateTime.parse(endDate))) return false; } catch (_) {}
              }
              return true;
            }).toList();
        _bannerCachedAt = DateTime.now();
      } catch (_) {}
    }
    if (mounted) setState(() => _banners = List<Map<String,dynamic>>.from(_cachedBanners ?? []));

    // Load categories filtradas por screens='servicios' (misma tabla que home/mercados)
    if (forceRefresh || _catStale) {
      try {
        final raw = await _sb.from("categories")
            .select()
            .eq("is_active", true)
            .order("sort_order");
        final allCats = List<Map<String,dynamic>>.from(raw as List);
        // Filtrar solo las que aplican a servicios (mismo patrón que home y mercados)
        _cachedServiceCats = allCats.where((c) {
          final s = (c["screens"] as String?) ?? "all";
          return s == "all" || s.split(",").map((x) => x.trim()).contains("servicios");
        }).toList();
        _catCachedAt = DateTime.now();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _dbServiceCats = List<Map<String,dynamic>>.from(_cachedServiceCats ?? []);
        if (_catIdx >= _allCats.length) _catIdx = 0;
      });
    }

    // Cargar comuna guardada para filtrar y armar cache key
    final savedCommune = await LocationService.loadSavedCommune();
    _communeId = savedCommune?['commune_id'];
    // Fallback: si no hay comuna guardada pero sí coordenadas, re-detectar
    if (_communeId == null) {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble("delivery_lat");
      final lng = prefs.getDouble("delivery_lng");
      if (lat != null && lng != null) {
        final detected = await LocationService().detectAndSaveCommune(lat, lng);
        _communeId = detected?['commune_id'];
      }
    }

    final cacheKey = '${_catKey}_${_communeId ?? "all"}';
    if (!forceRefresh) {
      final cached = _cache[cacheKey];
      if (cached != null && DateTime.now().difference(cached.timestamp) < _ttl) {
        if (mounted) setState(() { _providers = cached.providers; _loading = false; });
        return;
      }
    }
    if (mounted) setState(() => _loading = true);
    try {
      var query = _sb.from("service_providers")
          .select()
          .eq("is_active", true)
          .eq("status", "approved");
      if (_communeId != null) query = query.eq("commune_id", _communeId!);
      if (_catKey != "Todo") query = query.eq("category", _catKey);
      final raw = await query;
      final list = List<Map<String, dynamic>>.from(raw as List);
      list.sort((a, b) {
        final afo = a["featured_order"] as int?;
        final bfo = b["featured_order"] as int?;
        if (afo == null && bfo == null) return _cmpRating(a, b);
        if (afo == null) return 1;
        if (bfo == null) return -1;
        if (afo != bfo) return afo.compareTo(bfo);
        return _cmpRating(a, b);
      });
      _cache[cacheKey] = _CacheEntry(providers: list, timestamp: DateTime.now());
      if (mounted) setState(() { _providers = list; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'No pudimos cargar los datos. Verifica tu conexión.'; });
      debugPrint('ServiciosScreen _loadData error: $e');
    }
  }

  int _cmpRating(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ar = (a["rating"] as num?)?.toDouble() ?? 0;
    final br = (b["rating"] as num?)?.toDouble() ?? 0;
    return br.compareTo(ar);
  }

  // ── Banners widget ────────────────────────────────────────────────────────────

  Widget _buildBannersWidget() {
    if (_banners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(children: [
        AspectRatio(
          aspectRatio: 2,
          child: PageView.builder(
            controller: _bannerPageCtrl,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _bannerPage = i),
            itemBuilder: (_, i) {
              final b      = _banners[i];
              final imgUrl = b["image_url"] as String?;
              final bg = parseHexColor(b["bg_color"] as String?, fallback: _kPurple);
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
    if (type == "url") launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: _kBg,
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.textLight),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textLight, fontSize: 15)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _loadData(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
            ),
          ]),
        )),
      );
    }
    return Scaffold(
      backgroundColor: _kBg,
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: _kOrange,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: Colors.transparent,
            flexibleSpace: const GradientFlexibleSpace(),
            toolbarHeight: 56,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Servicios verificados",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, fontFamily: "Nunito")),
                Text("Directorio",
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11, fontFamily: "Nunito")),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: () => showSearch(
                    context: context,
                    delegate: _ProviderSearchDelegate(_providers)),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  itemCount: _allCats.length,
                  itemBuilder: (_, i) {
                    final cat    = _allCats[i];
                    final active = _catIdx == i;
                    final imgUrl = cat["image_url"] as String?;
                    return GestureDetector(
                      onTap: () {
                        if (_catIdx == i) return;
                        setState(() { _catIdx = i; _loading = true; });
                        _loadData();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: active
                              ? _kOrange.withOpacity(0.25)
                              : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active ? _kOrange : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          imgUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(imgUrl,
                                      width: 18, height: 18, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Text(
                                          cat["emoji"] as String,
                                          style: const TextStyle(fontSize: 15))))
                              : Text(cat["emoji"] as String,
                                  style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 4),
                          Text(cat["label"] as String,
                              style: TextStyle(
                                color: active ? _kOrange : Colors.white.withOpacity(0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFamily: "Nunito",
                              )),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Verification banner
          SliverToBoxAdapter(child: _buildVerificationBanner()),

          // Promo banners (if any)
          if (!_loading && _banners.isNotEmpty)
            SliverToBoxAdapter(child: _buildBannersWidget()),

          // Provider list / shimmer / empty
          if (_loading)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, __) => _shimmerCard(),
                childCount: 4,
              ),
            )
          else if (_providers.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildProviderCard(_providers[i]),
                  childCount: _providers.length,
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildVerificationBanner() => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF9E00FF), Color(0xFF6B00B3)],
        begin: Alignment.centerLeft, end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(children: [
      Text("✅", style: TextStyle(fontSize: 22)),
      SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Proveedores verificados por Go Deli",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        SizedBox(height: 2),
        Text("Empresa con RUT, antecedentes y experiencia comprobada",
            style: TextStyle(color: Colors.white70, fontSize: 11)),
      ])),
    ]),
  );

  Widget _buildEmptyState() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
    child: Column(children: [
      const Text("🔧", style: TextStyle(fontSize: 56)),
      const SizedBox(height: 16),
      Text(
        "No hay proveedores de ${_catKey == "Todo" ? "servicios" : _catKey} disponibles aún",
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textMedium),
      ),
    ]),
  );

  Widget _shimmerCard() => Shimmer.fromColors(
    baseColor: const Color(0xFFDDD0F0),
    highlightColor: const Color(0xFFF5F0FF),
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: const AspectRatio(aspectRatio: 2, child: SizedBox.expand()),
    ),
  );

  Widget _buildProviderCard(Map<String, dynamic> p) {
    final tags      = (p["tags"] as List?)?.cast<String>() ?? <String>[];
    final sponsored = p["sponsored"] == true;
    final priceFrom = p["price_from"] as int?;
    final avail     = p["availability"] as String?;
    final phone     = p["phone"] as String? ?? "";
    final services  = (p["services"] as String?)?.trim() ?? "";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: _kPurple.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // A) Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: _kPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: (p["logo_url"] as String?)?.isNotEmpty == true
                    ? Image.network(p["logo_url"] as String, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                            child: Text(p["emoji"] ?? "🔧", style: const TextStyle(fontSize: 26))))
                    : Center(child: Text(p["emoji"] ?? "🔧", style: const TextStyle(fontSize: 26))),
              ),
              Positioned(right: -3, bottom: -3,
                child: Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: _kPurple, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Center(child: Text("✓",
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
                )),
            ]),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(p["name"] ?? "",
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textDark),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (sponsored) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(8)),
                  child: const Text("Destacado",
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(p["category"] ?? "",
                  style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 14),
                const SizedBox(width: 2),
                Text("${p["rating"] ?? "5.0"}",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const Text("  ·  ", style: TextStyle(color: AppColors.textLight, fontSize: 12)),
                const Icon(Icons.work_outline, size: 12, color: AppColors.textLight),
                const SizedBox(width: 2),
                Text("${p["jobs_count"] ?? 0} trabajos",
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                if ((p["response_time"] as String?) != null) ...[
                  const Text("  ·  ", style: TextStyle(color: AppColors.textLight, fontSize: 12)),
                  const Icon(Icons.access_time, size: 12, color: AppColors.textLight),
                  const SizedBox(width: 2),
                  Flexible(child: Text(p["response_time"] as String,
                      style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ]),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showContactSheet(p),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: _kOrange, borderRadius: BorderRadius.circular(10)),
                child: const Text("Contactar",
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),

        // B) Service tags
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Wrap(spacing: 6, runSpacing: 4,
              children: tags.take(4).map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _kPurple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kPurple.withOpacity(0.2)),
                ),
                child: Text(tag, style: TextStyle(color: _kPurple, fontSize: 11, fontWeight: FontWeight.w700)),
              )).toList(),
            ),
          ),

        // B2) Servicios que presta
        if (services.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.handyman_outlined, size: 14, color: _kPurple),
              const SizedBox(width: 6),
              Expanded(child: Text(services,
                  style: const TextStyle(color: AppColors.textMedium, fontSize: 12, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          ),

        // C) Footer
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (priceFrom != null && priceFrom > 0)
                Row(children: [
                  const Text("Desde ",
                      style: TextStyle(color: AppColors.textLight, fontSize: 12)),
                  Text(_fmtPrice(priceFrom),
                      style: const TextStyle(color: _kOrange, fontWeight: FontWeight.w900, fontSize: 15)),
                ]),
              if (avail != null && avail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(children: [
                    const Icon(Icons.schedule, size: 12, color: AppColors.textLight),
                    const SizedBox(width: 4),
                    Flexible(child: Text(avail,
                        style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ])),
            if (phone.isNotEmpty)
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse(
                    "https://wa.me/$phone?text=${Uri.encodeComponent("Hola, vi tu perfil en Go Deli y me gustaría cotizar un servicio.")}"),
                  mode: LaunchMode.externalApplication,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chat_rounded, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text("WhatsApp",
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  String _fmtPrice(num p) => fmtCLP(p.toInt());

  void _showContactSheet(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProviderDetailSheet(provider: p),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Provider Detail Sheet — cobertura, respuesta, horarios, servicios,
// descripción y botones de Llamar / WhatsApp.
// ════════════════════════════════════════════════════════════════════════════
class _ProviderDetailSheet extends StatelessWidget {
  final Map<String, dynamic> provider;
  const _ProviderDetailSheet({required this.provider});

  @override
  Widget build(BuildContext context) {
    final p        = provider;
    final phone    = (p["phone"] as String? ?? "").trim();
    final waRaw    = (p["whatsapp"] as String?)?.trim() ?? "";
    final whatsapp = waRaw.isNotEmpty ? waRaw : phone;
    final logo     = p["logo_url"] as String?;
    final portada  = p["photo_url"] as String?;
    final desc     = (p["description"] as String?)?.trim() ?? "";
    final services = (p["services"] as String?)?.trim() ?? "";
    final coverage = (p["coverage"] as String?)?.trim() ?? "";
    final response = (p["response_time"] as String?)?.trim() ?? "";
    final avail    = (p["availability"] as String?)?.trim() ?? "";
    final maxH     = MediaQuery.of(context).size.height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
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
            // Portada
            if (portada != null && portada.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(portada,
                    width: double.infinity, height: 150, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
              const SizedBox(height: 16),
            ],
            // Header
            Row(children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppColors.homePurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: logo != null && logo.isNotEmpty
                    ? Image.network(logo, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                            child: Text(p["emoji"] ?? "🔧",
                                style: const TextStyle(fontSize: 30))))
                    : Center(child: Text(p["emoji"] ?? "🔧",
                        style: const TextStyle(fontSize: 30))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p["name"] ?? "",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(p["category"] ?? "",
                    style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 15),
                  const SizedBox(width: 2),
                  Text("${p["rating"] ?? "5.0"}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const Text("  ·  ", style: TextStyle(color: AppColors.textLight, fontSize: 12)),
                  Text("${p["jobs_count"] ?? 0} trabajos",
                      style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                ]),
              ])),
            ]),

            // Descripción de la empresa
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text("Sobre la empresa",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 6),
              Text(desc,
                  style: const TextStyle(color: AppColors.textMedium, fontSize: 14, height: 1.5)),
            ],

            // Info: cobertura / tiempo de respuesta / horarios
            if (coverage.isNotEmpty || response.isNotEmpty || avail.isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.homeBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.homeCardBorder),
                ),
                child: Column(children: [
                  if (coverage.isNotEmpty)
                    _infoRow(Icons.place_outlined, "Cobertura", coverage),
                  if (response.isNotEmpty) ...[
                    if (coverage.isNotEmpty) const SizedBox(height: 10),
                    _infoRow(Icons.bolt_outlined, "Tiempo de respuesta", response),
                  ],
                  if (avail.isNotEmpty) ...[
                    if (coverage.isNotEmpty || response.isNotEmpty) const SizedBox(height: 10),
                    _infoRow(Icons.schedule_outlined, "Disponibilidad", avail),
                  ],
                ]),
              ),
            ],

            // Servicios que ofrece
            if (services.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text("Servicios que ofrece",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 6),
              Text(services,
                  style: const TextStyle(color: AppColors.textMedium, fontSize: 14, height: 1.5)),
            ],

            // Botones de contacto
            const SizedBox(height: 24),
            Row(children: [
              if (phone.isNotEmpty)
                Expanded(child: ElevatedButton.icon(
                  onPressed: () => launchUrl(
                      Uri.parse("tel:$phone"), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: const Text("Llamar"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFamily: "Nunito"),
                  ),
                )),
              if (phone.isNotEmpty && whatsapp.isNotEmpty) const SizedBox(width: 10),
              if (whatsapp.isNotEmpty)
                Expanded(child: ElevatedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse("https://wa.me/$whatsapp?text=${Uri.encodeComponent("Hola, vi tu perfil en Go Deli y me gustaría cotizar un servicio.")}"),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: const Text("WhatsApp"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFamily: "Nunito"),
                  ),
                )),
            ]),
          ]),
        )),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) =>
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: AppColors.homePurple),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textLight)),
        const SizedBox(height: 1),
        Text(value,
            style: const TextStyle(color: AppColors.textDark, fontSize: 13, fontWeight: FontWeight.w600, height: 1.35)),
      ])),
    ]);
}

// ════════════════════════════════════════════════════════════════════════════
// Search Delegate
// ════════════════════════════════════════════════════════════════════════════
class _ProviderSearchDelegate extends SearchDelegate<String> {
  final List<Map<String, dynamic>> providers;
  _ProviderSearchDelegate(this.providers);

  @override String get searchFieldLabel => "Buscar proveedor o servicio...";

  @override
  List<Widget> buildActions(BuildContext ctx) => [
    if (query.isNotEmpty)
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ""),
  ];

  @override
  Widget buildLeading(BuildContext ctx) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(ctx, ""));

  @override Widget buildResults(BuildContext ctx)     => _buildList(ctx);
  @override Widget buildSuggestions(BuildContext ctx) => _buildList(ctx);

  Widget _buildList(BuildContext ctx) {
    final q = query.toLowerCase().trim();
    final results = q.isEmpty
        ? providers
        : providers.where((p) =>
            (p["name"] as String? ?? "").toLowerCase().contains(q) ||
            (p["category"] as String? ?? "").toLowerCase().contains(q) ||
            ((p["tags"] as List?)?.any((t) => (t as String).toLowerCase().contains(q)) ?? false))
        .toList();

    if (results.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text("🔍", style: TextStyle(fontSize: 40)),
          SizedBox(height: 12),
          Text("Sin resultados", style: TextStyle(color: AppColors.textLight)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final p = results[i];
        return ListTile(
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.homePurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(p["emoji"] ?? "🔧",
                style: const TextStyle(fontSize: 22))),
          ),
          title: Text(p["name"] ?? "",
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(p["category"] ?? "",
              style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
          onTap: () => close(ctx, p["id"] as String? ?? ""),
        );
      },
    );
  }
}
