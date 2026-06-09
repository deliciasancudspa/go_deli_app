import "dart:async";
import "dart:io";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:image_picker/image_picker.dart";
import "package:shimmer/shimmer.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/theme/app_theme.dart";

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

  // Service category cache
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
  List<Map<String, dynamic>> _providers = [];

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
    // Load banners (5-min cache, date-filtered server-side)
    if (forceRefresh || _bannerStale) {
      try {
        final now = DateTime.now().toIso8601String();
        final raw = await _sb.from("banners")
            .select()
            .eq("is_active", true)
            .eq("banner_type", "web_servicios")
            .or("start_date.is.null,start_date.lte.$now")
            .or("end_date.is.null,end_date.gte.$now")
            .order("sort_order")
            .limit(5);
        _cachedBanners = (raw as List<dynamic>).cast<Map<String, dynamic>>();
        _bannerCachedAt = DateTime.now();
      } catch (_) {}
    }
    if (mounted) setState(() => _banners = List<Map<String,dynamic>>.from(_cachedBanners ?? []));

    // Load service categories from DB (30-min cache)
    if (forceRefresh || _catStale) {
      try {
        final raw = await _sb.from("service_categories")
            .select()
            .eq("is_active", true)
            .order("sort_order");
        _cachedServiceCats = List<Map<String,dynamic>>.from(raw as List);
        _catCachedAt = DateTime.now();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _dbServiceCats = List<Map<String,dynamic>>.from(_cachedServiceCats ?? []);
        if (_catIdx >= _allCats.length) _catIdx = 0;
      });
    }

    if (!forceRefresh) {
      final cached = _cache[_catKey];
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
      _cache[_catKey] = _CacheEntry(providers: list, timestamp: DateTime.now());
      if (mounted) setState(() { _providers = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
        SizedBox(
          height: 160,
          child: PageView.builder(
            controller: _bannerPageCtrl,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _bannerPage = i),
            itemBuilder: (_, i) {
              final b      = _banners[i];
              final imgUrl = b["image_url"] as String?;
              Color bg     = _kPurple;
              try {
                final hex = (b["bg_color"] as String?)?.replaceAll("#", "");
                if (hex != null && hex.length == 6) bg = Color(int.parse("FF$hex", radix: 16));
              } catch (_) {}
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
    return Scaffold(
      backgroundColor: _kBg,
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: _kOrange,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: _kDark,
            toolbarHeight: 56,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Servicios verificados",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, fontFamily: "Nunito")),
                Text("Directorio",
                    style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: "Nunito")),
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
                                color: active ? _kOrange : Colors.white,
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
      height: 180,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    ),
  );

  Widget _buildProviderCard(Map<String, dynamic> p) {
    final tags      = (p["tags"] as List?)?.cast<String>() ?? <String>[];
    final sponsored = p["sponsored"] == true;
    final priceFrom = p["price_from"] as int?;
    final avail     = p["availability"] as String?;
    final phone     = p["phone"] as String? ?? "";

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
                child: Center(child: Text(p["emoji"] ?? "🔧", style: const TextStyle(fontSize: 26))),
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

  String _fmtPrice(num p) =>
      "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  void _showContactSheet(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactSheet(provider: p, sb: _sb),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Contact + Request Sheet
// ════════════════════════════════════════════════════════════════════════════
class _ContactSheet extends StatefulWidget {
  final Map<String, dynamic> provider;
  final SupabaseClient sb;
  const _ContactSheet({required this.provider, required this.sb});
  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  bool _showForm = false;
  bool _sending  = false;

  final _descCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  DateTime? _preferredDate;
  TimeOfDay? _preferredTime;
  final List<XFile> _photos = [];
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _prefillAddress();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillAddress() async {
    try {
      final user = widget.sb.auth.currentUser;
      if (user == null) return;
      final u = await widget.sb.from("users").select("id").eq("auth_id", user.id).maybeSingle();
      if (u == null) return;
      final addr = await widget.sb.from("user_addresses")
          .select("address").eq("user_id", u["id"]).eq("is_default", true).maybeSingle();
      if (addr != null && mounted) {
        setState(() => _addrCtrl.text = addr["address"] as String? ?? "");
      }
    } catch (_) {}
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= 3) return;
    final img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (img != null && mounted) setState(() => _photos.add(img));
  }

  Future<void> _submitRequest() async {
    if (_descCtrl.text.trim().isEmpty || _preferredDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Completa la descripción y fecha preferida")),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final user = widget.sb.auth.currentUser;
      String? clientId;
      if (user != null) {
        final u = await widget.sb.from("users")
            .select("id").eq("auth_id", user.id).maybeSingle();
        clientId = u?["id"] as String?;
      }
      final photoUrls = <String>[];
      for (final f in _photos) {
        try {
          final bytes = await f.readAsBytes();
          final ext   = f.name.split(".").last;
          final path  = "service_requests/${DateTime.now().millisecondsSinceEpoch}_${f.name}";
          await widget.sb.storage.from("public").uploadBinary(
            path, bytes,
            fileOptions: FileOptions(contentType: "image/$ext"),
          );
          photoUrls.add(widget.sb.storage.from("public").getPublicUrl(path));
        } catch (_) {}
      }
      final d = _preferredDate!;
      await widget.sb.from("service_requests").insert({
        "provider_id": widget.provider["id"],
        if (clientId != null) "client_id": clientId,
        "description":     _descCtrl.text.trim(),
        "address":         _addrCtrl.text.trim(),
        "preferred_date":  "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}",
        if (_preferredTime != null)
          "preferred_time":
              "${_preferredTime!.hour.toString().padLeft(2, "0")}:${_preferredTime!.minute.toString().padLeft(2, "0")}",
        if (photoUrls.isNotEmpty) "photos": photoUrls,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Solicitud enviada. El proveedor te contactará pronto.")),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al enviar: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p     = widget.provider;
    final phone = p["phone"] as String? ?? "";
    final maxH  = MediaQuery.of(context).size.height * 0.92;

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
            // Provider header
            Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: AppColors.homePurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: Text(p["emoji"] ?? "🔧",
                    style: const TextStyle(fontSize: 28))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p["name"] ?? "",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(p["category"] ?? "",
                    style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
              ])),
            ]),

            if ((p["description"] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(p["description"] as String,
                  style: const TextStyle(color: AppColors.textMedium, fontSize: 14, height: 1.5)),
            ],
            const SizedBox(height: 20),

            if (!_showForm) ...[
              const Text("Opciones de contacto",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 12),
              if (phone.isNotEmpty) ...[
                _contactOption(
                  icon: Icons.phone_rounded, iconColor: AppColors.info,
                  label: "Llamar", subtitle: phone,
                  onTap: () => launchUrl(
                    Uri.parse("tel:$phone"), mode: LaunchMode.externalApplication),
                ),
                const SizedBox(height: 8),
                _contactOption(
                  icon: Icons.chat_rounded, iconColor: const Color(0xFF25D366),
                  label: "WhatsApp", subtitle: "Escríbele directamente",
                  onTap: () => launchUrl(
                    Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent("Hola, vi tu perfil en Go Deli y me gustaría cotizar un servicio.")}"),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _contactOption(
                icon: Icons.message_outlined, iconColor: AppColors.homePurple,
                label: "Mensaje interno", subtitle: "Chat dentro de la app",
                onTap: () {
                  Navigator.pop(context);
                  context.push("/chat/${p["id"]}");
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _showForm = true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: const Text("Solicitar visita"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.homeOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFamily: "Nunito"),
                  ),
                ),
              ),
            ] else ...[
              // Request form
              Row(children: [
                IconButton(
                  onPressed: () => setState(() => _showForm = false),
                  icon: const Icon(Icons.arrow_back_ios, size: 18, color: AppColors.textMedium),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                const Text("Solicitar visita",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 16),

              _fieldLabel("Descripción del trabajo *"),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: _inputDecor("Ej: Necesito reparar una fuga en el baño..."),
              ),
              const SizedBox(height: 14),

              _fieldLabel("Dirección"),
              const SizedBox(height: 6),
              TextField(
                controller: _addrCtrl,
                decoration: _inputDecor("Ej: Calle Los Pinos 123, Ancud",
                    prefix: const Icon(Icons.location_on_outlined, color: AppColors.homeOrange, size: 20)),
              ),
              const SizedBox(height: 14),

              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel("Fecha preferida *"),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                        builder: (ctx, child) => Theme(
                          data: ThemeData().copyWith(
                            colorScheme: const ColorScheme.light(primary: AppColors.homePurple),
                          ),
                          child: child!,
                        ),
                      );
                      if (d != null && mounted) setState(() => _preferredDate = d);
                    },
                    child: _dateBox(
                      icon: Icons.calendar_today_outlined,
                      text: _preferredDate != null
                          ? "${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}"
                          : "Seleccionar",
                      selected: _preferredDate != null,
                    ),
                  ),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel("Hora preferida"),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: const TimeOfDay(hour: 9, minute: 0),
                        builder: (ctx, child) => Theme(
                          data: ThemeData().copyWith(
                            colorScheme: const ColorScheme.light(primary: AppColors.homePurple),
                          ),
                          child: child!,
                        ),
                      );
                      if (t != null && mounted) setState(() => _preferredTime = t);
                    },
                    child: _dateBox(
                      icon: Icons.access_time,
                      text: _preferredTime != null
                          ? _preferredTime!.format(context)
                          : "Seleccionar",
                      selected: _preferredTime != null,
                    ),
                  ),
                ])),
              ]),
              const SizedBox(height: 14),

              _fieldLabel("Fotos (opcional, máx. 3)"),
              const SizedBox(height: 8),
              Row(children: [
                ..._photos.map((f) => Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                    image: DecorationImage(
                      image: FileImage(File(f.path)), fit: BoxFit.cover),
                  ),
                )),
                if (_photos.length < 3)
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.homeBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate_outlined, color: AppColors.textLight, size: 24),
                        SizedBox(height: 4),
                        Text("Agregar", style: TextStyle(color: AppColors.textLight, fontSize: 10)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _sending ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.homeOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFamily: "Nunito"),
                  ),
                  child: _sending
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Enviar solicitud"),
                ),
              ),
            ],
          ]),
        )),
      ]),
    );
  }

  Widget _contactOption({
    required IconData icon, required Color iconColor,
    required String label, required String subtitle,
    required VoidCallback onTap,
  }) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.homeBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.homeCardBorder),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            Text(subtitle, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
          ])),
          const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
        ]),
      ),
    );

  Widget _fieldLabel(String text) => Text(text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textMedium));

  InputDecoration _inputDecor(String hint, {Widget? prefix}) => InputDecoration(
    hintText: hint,
    prefixIcon: prefix,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.homePurple, width: 2)),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  Widget _dateBox({required IconData icon, required String text, required bool selected}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: selected ? AppColors.homePurple : AppColors.border),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: Row(children: [
        Icon(icon, size: 15, color: selected ? AppColors.homePurple : AppColors.textLight),
        const SizedBox(width: 6),
        Flexible(child: Text(text,
            style: TextStyle(
              color: selected ? AppColors.textDark : AppColors.textLight,
              fontSize: 12,
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
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
