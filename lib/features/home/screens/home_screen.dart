import "package:flutter/material.dart";
import "dart:async";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";
import "../../../providers/auth_provider.dart";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIdx = 0;
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _banners = [];
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;
  String _selectedCat = "Todos";
  final _sb = Supabase.instance.client;
  final _bannerCtrl = PageController();
  int _bannerPage = 0;
  Timer? _bannerTimer;

  final _categories = [
    {"name": "Todos",            "emoji": "⭐"},
    {"name": "Restaurante",      "emoji": "🍽️"},
    {"name": "Fast Food",        "emoji": "🍔"},
    {"name": "Sushi",            "emoji": "🍣"},
    {"name": "Heladería",        "emoji": "🍦"},
    {"name": "Pastelería",       "emoji": "🎂"},
    {"name": "Farmacias",        "emoji": "💊"},
    {"name": "Pet Shop",         "emoji": "🐾"},
    {"name": "Ferreterías",      "emoji": "🔧"},
    {"name": "Librería y Regalos","emoji": "📚"},
    {"name": "Tecnología",       "emoji": "💻"},
    {"name": "Otros",            "emoji": "🏪"},
  ];

  final _marketCategories = [
    {"name": "Supermercado",  "emoji": "🛒"},
    {"name": "Minimarket",    "emoji": "🏪"},
    {"name": "Carnicería",    "emoji": "🥩"},
    {"name": "Verdulería",    "emoji": "🥦"},
    {"name": "Botillería",    "emoji": "🍺"},
  ];

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startBannerTimer());
  }

  void _startBannerTimer() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_banners.isEmpty || !_bannerCtrl.hasClients) return;
      final next = (_bannerPage + 1) % _banners.length;
      _bannerCtrl.animateToPage(next, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() { _bannerTimer?.cancel(); _bannerCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stores  = await _sb.from("stores").select().eq("status", "approved").eq("is_active", true);
      final banners = await _sb.from("banners").select().eq("is_active", true).eq("banner_type", "app").order("sort_order").limit(6);
      final services = await _sb.from("service_providers").select().eq("status", "approved").eq("is_active", true);
      if (mounted) setState(() {
        _stores   = List<Map<String, dynamic>>.from(stores);
        _banners  = List<Map<String, dynamic>>.from(banners);
        _services = List<Map<String, dynamic>>.from(services);
        _loading  = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  List<Map<String, dynamic>> get _filteredStores {
    if (_selectedCat == "Todos") return _stores.where((s) => !_isMarket(s["category"])).toList();
    return _stores.where((s) => s["category"] == _selectedCat).toList();
  }

  List<Map<String, dynamic>> get _marketStores =>
    _stores.where((s) => _isMarket(s["category"])).toList();

  bool _isMarket(String? cat) =>
    ["Supermercado","Minimarket","Carnicería","Verdulería","Botillería"].contains(cat);

  String _fmt(num p) => "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: _navIdx, children: [
        _buildHome(cart),
        _buildMarkets(),
        _buildServicios(),
        _buildPedidos(),
        _buildPerfil(),
      ]),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIdx,
        onTap: (i) => setState(() => _navIdx = i),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: "Inicio"),
          const BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), activeIcon: Icon(Icons.storefront), label: "Mercados"),
          const BottomNavigationBarItem(icon: Icon(Icons.miscellaneous_services_outlined), activeIcon: Icon(Icons.miscellaneous_services), label: "Servicios"),
          BottomNavigationBarItem(
            icon: Stack(children: [
              const Icon(Icons.receipt_long_outlined),
            ]),
            activeIcon: const Icon(Icons.receipt_long),
            label: "Pedidos",
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: "Perfil"),
        ],
      ),
    );
  }

  Widget _buildHome(CartProvider cart) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: CustomScrollView(slivers: [
        // AppBar
        SliverAppBar(
          expandedHeight: 120,
          floating: true,
          backgroundColor: AppColors.primary,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.primary, AppColors.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                  const Text("Go Deli", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  Text("¿Qué se te antoja hoy?", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                ])),
                Stack(children: [
                  IconButton(
                    onPressed: () => context.push("/cart"),
                    icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 28),
                  ),
                  if (cart.itemCount > 0) Positioned(
                    right: 6, top: 6,
                    child: Container(
                      width: 18, height: 18,
                      decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                      child: Center(child: Text("${cart.itemCount}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))),
                    ),
                  ),
                ]),
                IconButton(
                  onPressed: () => context.push("/notifications"),
                  icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 28),
                ),
              ]),
            ),
          ),
        ),

        // Busqueda
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () => context.push("/search"),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
              child: Row(children: [
                const Icon(Icons.search, color: AppColors.textLight),
                const SizedBox(width: 10),
                const Text("Buscar tiendas o productos...", style: TextStyle(color: AppColors.textLight, fontSize: 15)),
              ]),
            ),
          ),
        )),

        // Banners
        if (_banners.isNotEmpty) SliverToBoxAdapter(child: _buildBanners()),

        // Categorias
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Text("Categorías", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        )),
        SliverToBoxAdapter(child: SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories.length,
            itemBuilder: (ctx, i) {
              final cat = _categories[i];
              final selected = _selectedCat == cat["name"];
              return GestureDetector(
                onTap: () => setState(() => _selectedCat = cat["name"]!),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2 : 1),
                    boxShadow: selected ? [BoxShadow(color: AppColors.accent.withOpacity(0.3), blurRadius: 8)] : [],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(cat["emoji"]!, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 4),
                    Text(cat["name"]!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.textMedium)),
                  ]),
                ),
              );
            },
          ),
        )),

        // Tiendas
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: _loading
            ? const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.primary))))
            : _filteredStores.isEmpty
              ? const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: Text("Sin tiendas en esta categoría", style: TextStyle(color: AppColors.textLight)))))
              : SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.85, crossAxisSpacing: 12, mainAxisSpacing: 12),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _storeCard(_filteredStores[i]),
                    childCount: _filteredStores.length,
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _buildBanners() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        SizedBox(
          height: 165,
          child: PageView.builder(
            controller: _bannerCtrl,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _bannerPage = i),
            itemBuilder: (ctx, i) {
              final b = _banners[i];
              final hasImg = b["image_url"] != null;
              return Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  image: hasImg ? DecorationImage(image: NetworkImage(b["image_url"]), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.18), BlendMode.darken)) : null,
                  boxShadow: [BoxShadow(color: AppColors.accent.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Stack(children: [
                  if (!hasImg) Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text("🎉", style: TextStyle(fontSize: 42)),
                    const SizedBox(height: 8),
                    Text(b["title"] ?? "", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    if (b["subtitle"] != null) Padding(padding: const EdgeInsets.only(top: 4, left: 16, right: 16), child: Text(b["subtitle"], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13))),
                  ])),
                  if (hasImg) Positioned(bottom: 16, left: 16, right: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (b["title"] != null) Text(b["title"], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
                    if (b["subtitle"] != null) Text(b["subtitle"], style: const TextStyle(color: Colors.white80, fontSize: 13)),
                  ])),
                  if (b["badge"] != null) Positioned(top: 12, right: 12, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
                    child: Text(b["badge"], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  )),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_banners.length, (i) =>
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: _bannerPage == i ? 22 : 6, height: 6,
            decoration: BoxDecoration(
              color: _bannerPage == i ? AppColors.accent : AppColors.border,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        )),
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _buildMarkets() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Mercados"),
        automaticallyImplyLeading: false,
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Categorías", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 1.2, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: _marketCategories.length,
              itemBuilder: (ctx, i) {
                final cat = _marketCategories[i];
                return GestureDetector(
                  onTap: () {
                    if (cat["name"] == "Botillería") {
                      _showAgeVerification(cat["name"]!);
                    } else {
                      _showMarketCategory(cat["name"]!);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(cat["emoji"]!, style: const TextStyle(fontSize: 32)),
                      const SizedBox(height: 6),
                      Text(cat["name"]!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                );
              },
            ),
          ]),
        )),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: const Text("Todas las tiendas", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        )),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.85, crossAxisSpacing: 12, mainAxisSpacing: 12),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _storeCard(_marketStores[i]),
              childCount: _marketStores.length,
            ),
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
      ]),
    );
  }

  void _showAgeVerification(String category) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("🍺 Verificación de edad", style: TextStyle(fontWeight: FontWeight.w800)),
      content: const Text("Esta sección contiene productos con alcohol. ¿Confirmas que eres mayor de 18 años?", style: TextStyle(fontSize: 15, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text("No, soy menor", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
        ),
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); _showMarketCategory(category); },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text("Sí, soy mayor de 18"),
        ),
      ],
    ));
  }

  void _showMarketCategory(String category) {
    final filtered = _marketStores.where((s) => s["category"] == category).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, ctrl) => Column(children: [
          Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          Text(category, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Expanded(child: filtered.isEmpty
            ? const Center(child: Text("Sin tiendas en esta categoría", style: TextStyle(color: AppColors.textLight)))
            : GridView.builder(
                controller: ctrl,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.85, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) => _storeCard(filtered[i]),
              )),
        ]),
      ),
    );
  }

  Widget _buildServicios() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Go Servicios"), automaticallyImplyLeading: false),
      body: _services.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text("🔧", style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            const Text("Próximamente", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text("Empresas de servicios verificadas", style: TextStyle(color: AppColors.textLight)),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _services.length,
            itemBuilder: (ctx, i) {
              final s = _services[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Container(width: 56, height: 56, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: Center(child: Text(s["emoji"] ?? "🔧", style: const TextStyle(fontSize: 28)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(s["category"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                    Text(s["description"] ?? "", style: const TextStyle(color: AppColors.textMedium, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ])),
                  ElevatedButton(
                    onPressed: () => context.push("/servicio/${s["id"]}"),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(80, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: const Text("Ver", style: TextStyle(fontSize: 13)),
                  ),
                ]),
              );
            },
          ),
    );
  }

  Widget _buildPedidos() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Mis Pedidos"), automaticallyImplyLeading: false),
      body: _PedidosTab(),
    );
  }

  Widget _buildPerfil() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Mi Perfil"), automaticallyImplyLeading: false),
      body: _PerfilTab(key: ValueKey(_navIdx)),
    );
  }

  Widget _storeCard(Map<String, dynamic> store) {
    return GestureDetector(
      onTap: () => context.push("/store/${store["id"]}"),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.secondary, AppColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                image: store["cover_url"] != null ? DecorationImage(image: NetworkImage(store["cover_url"]), fit: BoxFit.cover) : null,
              ),
              child: store["cover_url"] == null ? Center(child: Text(store["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 40))) : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(store["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(store["category"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.star, color: AppColors.accent, size: 12),
                Text(" ${store["rating"] ?? "5.0"}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                const Text(" · ", style: TextStyle(color: AppColors.textLight)),
                Text("${store["delivery_time"] ?? "30-45"} min", style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
              ]),
              if (!store["is_open"]) Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: const Text("Cerrado", style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

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
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startBannerTimer());
  }

  void _startBannerTimer() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_banners.isEmpty || !_bannerCtrl.hasClients) return;
      final next = (_bannerPage + 1) % _banners.length;
      _bannerCtrl.animateToPage(next, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() { _bannerTimer?.cancel(); _bannerCtrl.dispose(); super.dispose(); }

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
          final o = _orders[i];
          final status = o["status"] as String? ?? "pending";
          final color = _statusColors[status] ?? AppColors.textLight;
          final items = (o["order_items"] as List?) ?? [];
          final isActive = !["delivered","cancelled"].contains(status);
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
                    Text(items.take(2).map((i) => i["item_name"]).join(", "), style: const TextStyle(color: AppColors.textLight, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_fmt((o["total"] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(_statusLabels[status] ?? status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
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
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 38), padding: const EdgeInsets.symmetric(vertical: 8)),
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

class _PerfilTab extends StatefulWidget {
  const _PerfilTab({super.key});
  @override
  State<_PerfilTab> createState() => _PerfilTabState();
}

class _PerfilTabState extends State<_PerfilTab> {
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;
  bool _showFavs = false;
  final _sb = Supabase.instance.client;

  final _statusLabels = {
    "pending":"⏳ Pendiente","accepted":"✅ Confirmado","preparing":"👨‍🍳 Preparando",
    "ready":"🎉 Listo","assigned":"🛵 Asignado","picked_up":"📦 Recogido",
    "on_the_way":"🚀 En camino","delivered":"🏁 Entregado","cancelled":"❌ Cancelado",
  };
  final _statusColors = {
    "pending":Color(0xFFF59E0B),"accepted":Color(0xFF3B82F6),"preparing":Color(0xFFFF6B35),
    "ready":Color(0xFF22C55E),"assigned":Color(0xFFF59E0B),"picked_up":Color(0xFF3B82F6),
    "on_the_way":Color(0xFFFF6B35),"delivered":Color(0xFF22C55E),"cancelled":Color(0xFFEF4444),
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final authUser = _sb.auth.currentUser;
      if (authUser == null) { setState(() => _loading = false); return; }
      final u = await _sb.from("users").select().eq("auth_id", authUser.id).single();
      final favs = await _sb.from("user_favorites").select("*, stores(id,name,emoji,category,rating,delivery_time,delivery_fee,is_open)").eq("user_id", u["id"]);
      final orders = await _sb.from("orders").select("*, stores(name,emoji), order_items(item_name,quantity)").eq("client_id", u["id"]).order("created_at", ascending: false).limit(20);
      final addrs = await _sb.from("user_addresses").select().eq("user_id", u["id"]).order("is_default", ascending: false);
      if (mounted) setState(() {
        _user = u;
        _favorites = List<Map<String, dynamic>>.from(favs);
        _orders = List<Map<String, dynamic>>.from(orders);
        _addresses = List<Map<String, dynamic>>.from(addrs);
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _logout() async {
    await _sb.auth.signOut();
    if (mounted) context.go("/login");
  }

  String _fmt(num p) {
    return "\$" + p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.");
  }

  void _showOrders() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: AppColors.background,
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
                  final o = _orders[i];
                  final status = o["status"] as String? ?? "pending";
                  final color = _statusColors[status] ?? AppColors.textLight;
                  final isActive = !["delivered","cancelled"].contains(status);
                  final items = (o["order_items"] as List?) ?? [];
                  final total = (o["total"] as num?) ?? 0;
                  return GestureDetector(
                    onTap: () { Navigator.pop(ctx); context.push("/tracking/${o["id"]}"); },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isActive ? color.withOpacity(0.4) : AppColors.border, width: isActive ? 2 : 1)),
                      child: Row(children: [
                        Text(o["stores"]?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 28)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(o["stores"]?["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(items.take(2).map((x) => x["item_name"]).join(", "),
                            style: const TextStyle(color: AppColors.textLight, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(_fmt(total), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
                          const SizedBox(height: 4),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(_statusLabels[status] ?? status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))),
                        ]),
                      ]),
                    ),
                  );
                }),
          ),
        ]),
      ),
    );
  }

  void _showAddresses() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: AppColors.background,
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
                  Text("Sin direcciones guardadas", style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textLight)),
                  SizedBox(height: 4),
                  Text("Agrega una dirección para pedir más rápido", textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textLight, fontSize: 13)),
                ]))
              : ListView.builder(controller: ctrl, padding: const EdgeInsets.all(16),
                  itemCount: _addresses.length,
                  itemBuilder: (ctx, i) {
                    final a = _addresses[i];
                    final isDefault = a["is_default"] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDefault ? AppColors.primary.withOpacity(0.5) : AppColors.border, width: isDefault ? 2 : 1)),
                      child: Row(children: [
                        Container(width: 40, height: 40,
                          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: Icon(_labelIcon(a["label"]), color: AppColors.primary, size: 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(a["label"] ?? "Dirección", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            if (isDefault) ...[const SizedBox(width: 6),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                                child: const Text("Principal", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)))],
                          ]),
                          const SizedBox(height: 2),
                          Text(a["address"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
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
                            const PopupMenuItem(value: "delete", child: Text("Eliminar", style: TextStyle(color: AppColors.error))),
                          ],
                        ),
                      ]),
                    );
                  }),
            ),
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
          decoration: InputDecoration(labelText: "Tipo", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          items: ["Casa","Trabajo","Otro"].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
          onChanged: (v) => setD(() => label = v!),
        ),
        const SizedBox(height: 12),
        TextField(controller: ctrl, maxLines: 2,
          decoration: InputDecoration(labelText: "Dirección completa",
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
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          const Text("Centro de ayuda", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const Text("¿En qué podemos ayudarte?", style: TextStyle(color: AppColors.textLight, fontSize: 14)),
          const SizedBox(height: 20),
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Contacto directo", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: ElevatedButton.icon(onPressed: () {},
                  icon: const Icon(Icons.chat, size: 16), label: const Text("WhatsApp", style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF25D366), foregroundColor: Colors.white, minimumSize: const Size(0, 40)))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton.icon(onPressed: () {},
                  icon: const Icon(Icons.email_outlined, size: 16), label: const Text("Email", style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary, minimumSize: const Size(0, 40)))),
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

  Widget _faqItem(String q, String a) {
    return Theme(
      data: ThemeData().copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(a, style: const TextStyle(color: AppColors.textMedium, fontSize: 13, height: 1.5)))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_user == null) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("Inicia sesión para ver tu perfil", style: TextStyle(color: AppColors.textLight)),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: () => context.go("/login"), child: const Text("Iniciar sesión")),
    ]));

    final delivered = _orders.where((o) => o["status"] == "delivered").length;
    final totalSpent = _orders.where((o) => o["status"] == "delivered").fold(0.0, (s, o) => s + ((o["total"] as num?) ?? 0));

    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(child: Column(children: [
        const SizedBox(height: 16),
        CircleAvatar(radius: 48, backgroundColor: AppColors.primary,
          child: Text((_user!["name"] as String? ?? "U")[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900))),
        const SizedBox(height: 12),
        Text(_user!["name"] ?? "", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        Text(_user!["email"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
        if (_user!["phone"] != null) Text(_user!["phone"], style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
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

      _menuItem(Icons.favorite_border, "Mis favoritos (${_favorites.length})", () => setState(() => _showFavs = !_showFavs)),
      if (_showFavs) ...[
        const SizedBox(height: 8),
        if (_favorites.isEmpty)
          Container(padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: const Center(child: Text("Sin tiendas favoritas aún", style: TextStyle(color: AppColors.textLight))))
        else
          ..._favorites.map((fav) {
            final store = fav["stores"] as Map<String, dynamic>?;
            if (store == null) return const SizedBox();
            return GestureDetector(
              onTap: () => context.push("/store/${store["id"]}"),
              child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
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
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, minimumSize: const Size(double.infinity, 50)),
      ),
      const SizedBox(height: 16),
      const Center(child: Text("Go Deli v1.0.0", style: TextStyle(color: AppColors.textLight, fontSize: 12))),
      const SizedBox(height: 32),
    ]);
  }

  Widget _statCard(String value, String label) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: Column(children: [
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
        const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
      ]),
    ),
  );
}
