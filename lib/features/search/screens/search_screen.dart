import "dart:async";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/services/location_service.dart";
import "../../home/widgets/store_card.dart";

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _storeResults = [];
  List<Map<String, dynamic>> _productResults = [];
  bool _loading = false;
  String _filter = "all";
  final _sb = Supabase.instance.client;
  String? _communeId;
  Timer? _debounce;

  final _filters = [
    {"id": "all",   "label": "Todos"},
    {"id": "open",  "label": "Abiertos"},
    {"id": "fast",  "label": "Rapido"},
    {"id": "cheap", "label": "Envio barato"},
    {"id": "rated", "label": "Mejor rating"},
  ];

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() { _storeResults = []; _productResults = []; });
      return;
    }
    setState(() => _loading = true);
    try {
      // Cargar comuna guardada para filtrar
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

      // Run both queries in parallel
      var storesQuery = _sb.from("stores").select().eq("status", "approved")
          .or("name.ilike.%$q%,category.ilike.%$q%");
      if (_communeId != null) storesQuery = storesQuery.eq("commune_id", _communeId!);

      final futures = await Future.wait([
        storesQuery,
        _sb.from("menu_items")
            .select("id,name,price,emoji,image_url,store_id,stores(id,name,emoji,is_open,status,delivery_fee,delivery_time,rating)")
            .ilike("name", "%$q%")
            .eq("is_available", true)
            .limit(30),
      ]);

      var stores = List<Map<String, dynamic>>.from(futures[0] as List);
      final products = (futures[1] as List)
          .cast<Map<String, dynamic>>()
          .where((p) => (p["stores"] as Map?)?["status"] == "approved")
          .toList();

      if (_filter == "open")  stores = stores.where((s) => s["is_open"] == true).toList();
      if (_filter == "rated") stores.sort((a, b) => ((b["rating"] ?? 0) as num).compareTo((a["rating"] ?? 0) as num));
      if (_filter == "cheap") stores.sort((a, b) => ((a["delivery_fee"] ?? 0) as num).compareTo((b["delivery_fee"] ?? 0) as num));
      if (_filter == "fast")  stores.sort((a, b) {
        final pa = int.tryParse(((a["delivery_time"] ?? "999") as String).split("-").first) ?? 999;
        final pb = int.tryParse(((b["delivery_time"] ?? "999") as String).split("-").first) ?? 999;
        return pa.compareTo(pb);
      });

      if (mounted) setState(() {
        _storeResults  = stores;
        _productResults = products;
        _loading       = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _storeResults.isNotEmpty || _productResults.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: const GradientFlexibleSpace(),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
        title: TextField(
          controller: _ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Buscar tiendas o productos...",
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.70)),
            border: InputBorder.none, filled: false,
          ),
          onChanged: _onSearchChanged,
        ),
      ),
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: AppColors.mainGradient),
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(height: 36, child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filters.length,
            itemBuilder: (ctx, i) {
              final f = _filters[i];
              final selected = _filter == f["id"];
              return GestureDetector(
                onTap: () { setState(() => _filter = f["id"]!); _search(_ctrl.text); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: selected ? AppColors.primary : Colors.white12, borderRadius: BorderRadius.circular(20)),
                  child: Text(f["label"]!, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              );
            },
          )),
        ),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _ctrl.text.isEmpty
              ? const Center(child: Text("Busca tiendas o productos", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)))
              : !hasResults
                ? const Center(child: Text("Sin resultados", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_storeResults.isNotEmpty) ...[
                        const Text("Tiendas", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMedium)),
                        const SizedBox(height: 8),
                        ..._storeResults.map((s) => StoreCard(store: s, onTap: () => context.push("/store/${s["id"]}"))),
                        const SizedBox(height: 16),
                      ],
                      if (_productResults.isNotEmpty) ...[
                        const Text("Productos", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMedium)),
                        const SizedBox(height: 8),
                        ..._productResults.map((p) => _ProductResultCard(product: p)),
                      ],
                    ],
                  ),
        ),
      ]),
    );
  }
}

class _ProductResultCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _ProductResultCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final store  = product["stores"] as Map? ?? {};
    final imgUrl = product["image_url"] as String?;
    final price  = (product["price"] as num?)?.toInt() ?? 0;
    final priceStr = "\$${price.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

    return GestureDetector(
      onTap: () => context.push("/product/${product["id"]}"),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imgUrl != null
              ? Image.network(imgUrl, width: 56, height: 56, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _emoji())
              : _emoji(),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product["name"] as String? ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 2),
            Row(children: [
              Text(store["emoji"] as String? ?? "🍽️", style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Flexible(child: Text(store["name"] as String? ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(priceStr, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.accent, fontSize: 15)),
            if (store["is_open"] != true)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: const Text("Cerrada", style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _emoji() => Container(
    width: 56, height: 56,
    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
    child: Center(child: Text(product["emoji"] as String? ?? "🍽️", style: const TextStyle(fontSize: 28))),
  );
}
