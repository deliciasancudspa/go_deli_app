import "package:flutter/material.dart";
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
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stores  = await _sb.from("stores").select().eq("status", "approved").eq("is_active", true);
      final banners = await _sb.from("banners").select().eq("is_active", true).eq("banner_type", "app").order("sort_order").limit(4);
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
                gradient: LinearGradient(colors: [AppColors.primary, Color(0xFF5B21B6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                    color: selected ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
                    boxShadow: selected ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8)] : [],
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
    return SizedBox(
      height: 160,
      child: PageView.builder(
        itemCount: _banners.length,
        itemBuilder: (ctx, i) {
          final b = _banners[i];
          return Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              image: b["image_url"] != null ? DecorationImage(image: NetworkImage(b["image_url"]), fit: BoxFit.cover) : null,
            ),
            child: b["image_url"] == null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("🎉", style: TextStyle(fontSize: 40)),
              Text(b["title"] ?? "", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            ])) : null,
          );
        },
      ),
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
      body: const Center(child: Text("Perfil")),
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
                gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.8), AppColors.accent.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
