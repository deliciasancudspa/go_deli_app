import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";
class StoreScreen extends StatefulWidget {
  final String storeId;
  const StoreScreen({super.key, required this.storeId});
  @override State<StoreScreen> createState() => _StoreScreenState();
}
class _StoreScreenState extends State<StoreScreen> {
  Map<String, dynamic>? _store;
  List<Map<String, dynamic>> _cats = [], _items = [];
  bool _loading = true;
  bool _isFav = false;
  String? _userId;
  String? _selCat;
  final _sb = Supabase.instance.client;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final s = await _sb.from("stores").select().eq("id", widget.storeId).single();
    final c = await _sb.from("menu_categories").select().eq("store_id", widget.storeId).eq("is_visible", true).order("sort_order");
    final i = await _sb.from("menu_items").select().eq("store_id", widget.storeId).eq("is_available", true).order("sort_order");
    try {
      final user = _sb.auth.currentUser;
      if (user != null) {
        final u = await _sb.from("users").select("id").eq("auth_id", user.id).maybeSingle();
        if (u != null) {
          _userId = u["id"] as String;
          final fav = await _sb.from("user_favorites").select().eq("user_id", _userId!).eq("store_id", widget.storeId).maybeSingle();
          if (mounted) setState(() => _isFav = fav != null);
        }
      }
    } catch (e) { debugPrint("Error favorito: $e"); }
    if (mounted) setState(() { _store = s; _cats = List<Map<String, dynamic>>.from(c); _items = List<Map<String, dynamic>>.from(i); _loading = false; });
  }
  Future<void> _toggleFav() async {
    if (_userId == null) { print("ERROR: _userId es null"); return; }
    try {
      if (_isFav) {
        await _sb.from("user_favorites").delete().eq("user_id", _userId!).eq("store_id", widget.storeId);
      } else {
        await _sb.from("user_favorites").insert({"user_id": _userId, "store_id": widget.storeId});
      }
      setState(() => _isFav = !_isFav);
      print("Favorito actualizado: _isFav=\${_isFav}");
    } catch(e) { print("ERROR favorito: \$e"); }
  }

  List<Map<String, dynamic>> get _filtered => _selCat == null ? _items : _items.where((i) => i["category_id"] == _selCat).toList();
  String _fmt(dynamic p) => "\$${(p as num).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
  @override Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    return Scaffold(backgroundColor: AppColors.background, body: CustomScrollView(slivers: [
      SliverAppBar(expandedHeight: 200, pinned: true, backgroundColor: AppColors.secondary, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
        actions: [IconButton(icon: Icon(_isFav ? Icons.favorite : Icons.favorite_border, color: _isFav ? Colors.red : Colors.white), onPressed: _toggleFav), Stack(children: [IconButton(icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white), onPressed: () => context.push("/cart")), if (cart.itemCount > 0) Positioned(right: 6, top: 6, child: Container(width: 16, height: 16, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle), child: Center(child: Text("${cart.itemCount}", style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)))))])],
        flexibleSpace: FlexibleSpaceBar(background: _store?["cover_url"] != null ? Image.network(_store!["cover_url"], fit: BoxFit.cover) : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight)), child: Center(child: Text(_store?["emoji"] ?? "X", style: const TextStyle(fontSize: 70)))))),
      SliverToBoxAdapter(child: Container(color: AppColors.surface, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_store?["name"] ?? "", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4), Text(_store?["description"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
        const SizedBox(height: 12), Row(children: [const Icon(Icons.star, color: Colors.amber, size: 16), const SizedBox(width: 4), Text("${_store?["rating"] ?? 5.0}", style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(width: 12), const Icon(Icons.access_time, size: 16, color: AppColors.textLight), const SizedBox(width: 4), Text("${_store?["delivery_time"] ?? "30-45"} min", style: const TextStyle(color: AppColors.textLight)), const SizedBox(width: 12), const Icon(Icons.delivery_dining, size: 16, color: AppColors.textLight), const SizedBox(width: 4), Text(_fmt(_store?["delivery_fee"] ?? 2990), style: const TextStyle(color: AppColors.textLight))]),
      ]))),
      if (_cats.isNotEmpty) SliverToBoxAdapter(child: SizedBox(height: 50, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), itemCount: _cats.length, itemBuilder: (ctx, i) { final c = _cats[i]; final sel = _selCat == c["id"]; return GestureDetector(onTap: () => setState(() => _selCat = sel ? null : c["id"]), child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(color: sel ? AppColors.primary : AppColors.surface, border: Border.all(color: sel ? AppColors.primary : AppColors.border), borderRadius: BorderRadius.circular(20)), child: Text(c["name"], style: TextStyle(fontWeight: FontWeight.w700, color: sel ? Colors.white : AppColors.textMedium, fontSize: 13)))); }))),
      SliverList(delegate: SliverChildBuilderDelegate((ctx, i) {
        final item = _filtered[i]; final qty = cart.getQuantity(item["id"]);
        return Container(margin: const EdgeInsets.fromLTRB(16, 0, 16, 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: Row(children: [
          item["image_url"] != null ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(item["image_url"], width: 80, height: 80, fit: BoxFit.cover)) : Container(width: 80, height: 80, decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)), child: Center(child: Text(item["emoji"] ?? "X", style: const TextStyle(fontSize: 36)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item["name"], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 4), Text(item["description"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_fmt(item["price"]), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.accent)),
              qty > 0 ? Row(children: [
                GestureDetector(onTap: () => cart.removeItem(item["id"]), child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle), child: const Icon(Icons.remove, color: Colors.white, size: 14))),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text("$qty", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                GestureDetector(onTap: () => cart.addItem(CartItem(id: item["id"], storeId: _store!["id"], storeName: _store!["name"], name: item["name"], price: (item["price"] as num).toInt(), imageUrl: item["image_url"])), child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 14))),
              ]) : GestureDetector(onTap: () => cart.addItem(CartItem(id: item["id"], storeId: _store!["id"], storeName: _store!["name"], name: item["name"], price: (item["price"] as num).toInt(), imageUrl: item["image_url"])), child: Container(width: 32, height: 32, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 18))),
            ]),
          ])),
        ]));
      }, childCount: _filtered.length)),
      const SliverToBoxAdapter(child: SizedBox(height: 100)),
    ]),
    bottomNavigationBar: cart.isEmpty ? null : Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -4))]), child: ElevatedButton(onPressed: () => context.push("/cart"), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Text("${cart.itemCount}", style: const TextStyle(fontWeight: FontWeight.w900))), const Text("Ver carrito"), Text(_fmt(cart.subtotal), style: const TextStyle(fontWeight: FontWeight.w900))]))));
  }
}