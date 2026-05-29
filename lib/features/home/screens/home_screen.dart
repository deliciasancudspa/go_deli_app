import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";
import "../../../providers/auth_provider.dart";
import "../widgets/store_card.dart";
import "../widgets/category_chip.dart";
import "../widgets/home_banner.dart";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIdx = 0;
  List<Map<String, dynamic>> _stores = [], _banners = [];
  bool _loading = true;
  String _cat = "Todos";
  final _sb = Supabase.instance.client;

  final _cats = [
    {"name": "Todos", "emoji": "⭐"},
    {"name": "Hamburguesas", "emoji": "🍔"},
    {"name": "Sushi", "emoji": "🍣"},
    {"name": "Pizza", "emoji": "🍕"},
    {"name": "Carnes", "emoji": "🥩"},
    {"name": "Bebidas", "emoji": "🥤"},
    {"name": "Postres", "emoji": "🍰"},
    {"name": "Supermercado", "emoji": "🛒"},
    {"name": "Farmacia", "emoji": "💊"},
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final stores  = await _sb.from("stores").select().eq("status", "approved").eq("is_active", true);
    final banners = await _sb.from("banners").select().eq("is_active", true).order("sort_order");
    if (mounted) setState(() {
      _stores  = List<Map<String, dynamic>>.from(stores);
      _banners = List<Map<String, dynamic>>.from(banners);
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered =>
    _cat == "Todos" ? _stores : _stores.where((s) => s["category"] == _cat).toList();

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: Column(children: [
        Container(
          color: AppColors.secondary, padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Entregar en", style: TextStyle(color: Colors.white60, fontSize: 12)),
                Row(children: [
                  const Icon(Icons.location_on, color: AppColors.primary, size: 16),
                  const SizedBox(width: 4),
                  Text(auth.profile?["address"] ?? "Agregar direccion", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
              ])),
              Stack(children: [
                IconButton(icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white), onPressed: () => context.push("/cart")),
                if (cart.itemCount > 0) Positioned(right: 6, top: 6, child: Container(
                  width: 18, height: 18, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: Center(child: Text("${cart.itemCount}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))),
                )),
              ]),
            ]),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => context.push("/search"),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFF1A2636), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.search, color: Colors.white38, size: 20),
                  const SizedBox(width: 10),
                  Text("Buscar productos, tiendas...", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
                ]),
              ),
            ),
          ]),
        ),
        Expanded(child: RefreshIndicator(
          onRefresh: _load, color: AppColors.primary,
          child: ListView(children: [
            if (_banners.isNotEmpty) HomeBanner(banners: _banners),
            const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 12), child: Text("Categorias", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark))),
            SizedBox(height: 44, child: ListView.builder(
              scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _cats.length,
              itemBuilder: (ctx, i) => CategoryChip(category: _cats[i], isSelected: _cat == _cats[i]["name"], onTap: () => setState(() => _cat = _cats[i]["name"] as String)),
            )),
            Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Tiendas cerca de ti", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              Text("(${_filtered.length})", style: const TextStyle(color: AppColors.textLight)),
            ])),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.primary)))
            else if (_filtered.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: Column(children: [
                Text("Sin restaurantes", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
              ])))
            else
              ListView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) => StoreCard(store: _filtered[i], onTap: () => context.push("/store/${_filtered[i]["id"]}")),
              ),
            const SizedBox(height: 20),
          ]),
        )),
      ])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIdx,
        onDestinationSelected: (i) {
          setState(() => _navIdx = i);
          switch (i) {
            case 1: context.push("/search"); break;
            case 2: context.push("/orders"); break;
            case 3: context.push("/favorites"); break;
            case 4: context.push("/profile"); break;
          }
        },
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withOpacity(0.1),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.primary), label: "Inicio"),
          NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search, color: AppColors.primary), label: "Buscar"),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long, color: AppColors.primary), label: "Pedidos"),
          NavigationDestination(icon: Icon(Icons.favorite_outline), selectedIcon: Icon(Icons.favorite, color: AppColors.primary), label: "Favoritos"),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: AppColors.primary), label: "Perfil"),
        ],
      ),
    );
  }
}
