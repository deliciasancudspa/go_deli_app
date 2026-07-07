import "dart:convert";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";
import "../../../core/utils/price_formatter.dart";
class StoreScreen extends StatefulWidget {
  final String storeId;
  const StoreScreen({super.key, required this.storeId});
  @override State<StoreScreen> createState() => _StoreScreenState();
}
class _StoreScreenState extends State<StoreScreen> {
  Map<String, dynamic>? _store;
  List<Map<String, dynamic>> _cats = [], _items = [];
  bool _loading = true;
  String? _error;
  bool _isFav = false;
  String? _userId;
  String? _selCat;
  final _sb = Supabase.instance.client;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
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
      if (mounted) setState(() { _store = s; _cats = List<Map<String, dynamic>>.from(c); _items = List<Map<String, dynamic>>.from(i); _loading = false; _error = null; _updateFiltered(); });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'No pudimos cargar la tienda. Verifica tu conexión.'; });
      debugPrint('StoreScreen _load error: $e');
    }
  }
  Future<void> _toggleFav() async {
    if (_userId == null) { debugPrint("ERROR: _userId es null"); return; }
    try {
      if (_isFav) {
        await _sb.from("user_favorites").delete().eq("user_id", _userId!).eq("store_id", widget.storeId);
      } else {
        await _sb.from("user_favorites").insert({"user_id": _userId, "store_id": widget.storeId});
      }
      if (mounted) setState(() => _isFav = !_isFav);
    } catch(e) { debugPrint("ERROR favorito: $e"); }
  }

  List<Map<String, dynamic>> _cachedFiltered = [];
  List<Map<String, dynamic>> get _filtered => _cachedFiltered;
  void _updateFiltered() {
    _cachedFiltered = _selCat == null
        ? _items
        : _items.where((i) => i["category_id"] == _selCat).toList();
  }
  String _fmt(dynamic p) => "\$${(p as num).toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
  @override Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    if (_error != null) return Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.textLight),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textLight, fontSize: 15)),
        const SizedBox(height: 20),
        ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Reintentar'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white)),
      ]),
    )));
    return Scaffold(backgroundColor: AppColors.background, body: CustomScrollView(slivers: [
      SliverAppBar(expandedHeight: 200, pinned: true, backgroundColor: Colors.transparent, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
        actions: [
          IconButton(
            icon: Icon(_isFav ? Icons.favorite : Icons.favorite_border,
                color: _isFav ? Colors.red : Colors.white),
            onPressed: _toggleFav),
          _cartBadge(cart),
        ],
        flexibleSpace: FlexibleSpaceBar(background: Stack(fit: StackFit.expand, children: [
          _store?["cover_url"] != null
            ? Image.network(_store!["cover_url"], fit: BoxFit.cover)
            : Container(decoration: const BoxDecoration(gradient: AppColors.mainGradient), child: Center(child: Text(_store?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 70)))),
        ]))),
      SliverToBoxAdapter(child: Container(color: AppColors.surface, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Logo de perfil grande, fuera del cover para que nada lo tape
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10)]),
            child: ClipOval(child: _store?["logo_url"] != null
              ? Image.network(_store!["logo_url"], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(_store?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 34))))
              : Center(child: Text(_store?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 34)))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_store?["name"] ?? "", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(_store?["description"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
        ]),
        const SizedBox(height: 12), Row(children: [const Icon(Icons.star, color: Colors.amber, size: 16), const SizedBox(width: 4), Text("${_store?["rating"] ?? 5.0}", style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(width: 12), const Icon(Icons.access_time, size: 16, color: AppColors.textLight), const SizedBox(width: 4), Text("${cleanDeliveryTime(_store?["delivery_time"])}", style: const TextStyle(color: AppColors.textLight)), const SizedBox(width: 12), const Icon(Icons.delivery_dining, size: 16, color: AppColors.textLight), const SizedBox(width: 4), Text(hasOwnDelivery(_store) ? "Delivery propio" : _fmt(_store?["delivery_fee_client"] ?? 2990), style: const TextStyle(color: AppColors.textLight))]),
      ]))),
      if (_cats.isNotEmpty) SliverToBoxAdapter(child: SizedBox(height: 50, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), itemCount: _cats.length, itemBuilder: (ctx, i) { final c = _cats[i]; final sel = _selCat == c["id"]; return GestureDetector(onTap: () => setState(() { _selCat = sel ? null : c["id"]; _updateFiltered(); }), child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), decoration: BoxDecoration(gradient: sel ? AppColors.mainGradient : null, color: sel ? null : AppColors.surface, border: Border.all(color: sel ? Colors.transparent : const Color(0xFFE5E0F0)), borderRadius: BorderRadius.circular(20)), child: Text(c["name"], style: TextStyle(fontWeight: FontWeight.w700, color: sel ? Colors.white : const Color(0xFF333333), fontSize: 13)))); }))),
      SliverList(delegate: SliverChildBuilderDelegate((ctx, i) {
        final item       = _filtered[i];
        final qty        = cart.getStoreQuantity(widget.storeId, item["id"] as String);
        final isRestaurant = (_store?["store_type"] as String?) == "restaurante";
        final basePrice  = (item["price"] as num?)?.toInt() ?? 0;
        final discPct    = (item["discount_pct"] as int?) ?? 0;
        final origPrice  = (item["original_price"] as num?)?.toInt();
        // Variants / variant_groups-aware price label
        String priceLabel = _fmt(basePrice);
        bool hasVariants = false;
        try {
          final vs = item["variants"];
          List? vl;
          if (vs is String && vs.isNotEmpty) vl = jsonDecode(vs) as List;
          else if (vs is List && vs.isNotEmpty) vl = vs;
          if (vl != null && vl.isNotEmpty) {
            hasVariants = true;
            final minP = vl.cast<Map<String, dynamic>>()
                .map((v) => (v["price"] as num?)?.toInt() ?? basePrice)
                .reduce((a, b) => a < b ? a : b);
            priceLabel = "Desde ${_fmt(minP)}";
          }
        } catch (_) {}
        if (!hasVariants) {
          try {
            final vgs = item["variant_groups"];
            List? vgl;
            if (vgs is String && vgs.isNotEmpty) vgl = jsonDecode(vgs) as List;
            else if (vgs is List && vgs.isNotEmpty) vgl = vgs;
            if (vgl != null && vgl.isNotEmpty) {
              hasVariants = true;
              var minP = 2147483647;
              for (final g in vgl.cast<Map<String, dynamic>>()) {
                for (final it in (g["items"] as List? ?? []).cast<Map<String, dynamic>>()) {
                  final p = (it["price"] as num?)?.toInt() ?? basePrice;
                  if (p < minP) minP = p;
                }
              }
              if (minP < 2147483647) priceLabel = "Desde ${_fmt(minP)}";
            }
          } catch (_) {}
        }
        // Opciones y recomendaciones (configuradas en el panel de aliados)
        // también requieren pasar por el detalle del producto.
        bool hasJsonList(dynamic v) {
          try {
            if (v is String && v.isNotEmpty) return (jsonDecode(v) as List).isNotEmpty;
            if (v is List) return v.isNotEmpty;
          } catch (_) {}
          return false;
        }
        final hasExtras = hasVariants || hasJsonList(item["options"]) || hasJsonList(item["recommendations"]);
        final isPopular = item["is_popular"] == true;
        final navigateToDetail = isRestaurant || hasExtras;
        return GestureDetector(
          // Tocar la tarjeta SIEMPRE abre la ficha del producto (laboratorio,
          // marca, formato, etc. en todas las categorías); los botones +/-
          // siguen agregando directo al carrito.
          onTap: () => context.push("/product/${item["id"]}"),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: item["image_url"] != null
                    ? Image.network(item["image_url"], width: 80, height: 80, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80, height: 80,
                          color: AppColors.background,
                          child: Center(child: Text(item["emoji"] ?? "🍽️",
                              style: const TextStyle(fontSize: 36)))))
                    : Container(width: 80, height: 80,
                        color: AppColors.background,
                        child: Center(child: Text(item["emoji"] ?? "🍽️",
                            style: const TextStyle(fontSize: 36)))),
                ),
                if (discPct > 0) Positioned(top: 4, left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                    child: Text("-$discPct%",
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                  )),
              ]),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(item["name"] as String? ?? "",
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (isPopular)
                    const Padding(padding: EdgeInsets.only(left: 4),
                        child: Text("⭐", style: TextStyle(fontSize: 12))),
                  if (hasExtras)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text("+ opciones",
                          style: TextStyle(fontSize: 9, color: AppColors.textLight, fontWeight: FontWeight.w700)),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(item["description"] as String? ?? "",
                    style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(priceLabel,
                          style: const TextStyle(fontWeight: FontWeight.w900,
                              fontSize: 16, color: AppColors.accent)),
                      if (discPct > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                          child: Text("-$discPct%",
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ]),
                    if (discPct > 0 && origPrice != null)
                      Text(_fmt(origPrice), style: const TextStyle(
                          fontSize: 11, color: AppColors.textLight,
                          decoration: TextDecoration.lineThrough)),
                  ]),
                  // ── Stock badge / botones ──────────────────────────────
                  Builder(builder: (_) {
                    final stockVal = item["stock"] as int?;
                    final agotado = (stockVal ?? 0) <= 0;
                    final limite = stockVal != null && stockVal > 0 && qty >= stockVal;
                    if (agotado) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text("Agotado",
                          style: TextStyle(color: Color(0xFF991B1B), fontSize: 11, fontWeight: FontWeight.w800)),
                      );
                    }
                    if (limite) {
                      return Row(children: [
                        GestureDetector(
                          onTap: () => cart.removeItem(item["id"] as String, variant: (item["variant"] as String?)),
                          child: Container(width: 28, height: 28,
                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                              child: const Icon(Icons.remove, color: Colors.white, size: 14))),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text("$qty",
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text("Límite",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                        ),
                      ]);
                    }
                    if (navigateToDetail)
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.accent.withOpacity(0.4))),
                        child: const Text("Ver →",
                            style: TextStyle(color: AppColors.accent,
                                fontSize: 12, fontWeight: FontWeight.w800)),
                      );
                    if (qty > 0)
                      return Row(children: [
                        GestureDetector(
                          onTap: () => cart.removeItem(item["id"] as String, variant: (item["variant"] as String?)),
                          child: Container(width: 28, height: 28,
                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                              child: const Icon(Icons.remove, color: Colors.white, size: 14))),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text("$qty",
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                        GestureDetector(
                          onTap: () => _addToCart(cart, item, basePrice),
                          child: Container(width: 28, height: 28,
                              decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                              child: const Icon(Icons.add, color: Colors.white, size: 14))),
                      ]);
                    return GestureDetector(
                      onTap: () => _addToCart(cart, item, basePrice),
                      child: Container(width: 32, height: 32,
                          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                          child: const Icon(Icons.add, color: Colors.white, size: 18)));
                  }),
                ]),
              ])),
            ]),
          ),
        );
      }, childCount: _filtered.length)),
      SliverToBoxAdapter(child: _ReviewsSection(storeId: widget.storeId, sb: _sb)),
      const SliverToBoxAdapter(child: SizedBox(height: 100)),
    ]),
    bottomNavigationBar: _buildBottomBar(cart),
    );
  }

  Widget _cartBadge(CartProvider cart) {
    final sc = cart.getStoreItemCount(widget.storeId);
    return Stack(children: [
      IconButton(
        icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
        onPressed: () => context.push("/cart"),
      ),
      if (sc > 0)
        Positioned(
          right: 6, top: 6,
          child: Container(
            width: 16, height: 16,
            decoration: const BoxDecoration(
                color: AppColors.accent, shape: BoxShape.circle),
            child: Center(
              child: Text("$sc",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900)),
            ),
          ),
        ),
    ]);
  }

  Widget? _buildBottomBar(CartProvider cart) {
    final sc = cart.getStoreItemCount(widget.storeId);
    if (sc == 0) return null;
    final ss = cart.getStoreSubtotal(widget.storeId);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: ElevatedButton(
        onPressed: () => context.push("/cart"),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text("$sc",
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            const Text("Ver carrito"),
            Text(_fmt(ss),
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  void _addToCart(CartProvider cart, Map<String, dynamic> item, int basePrice) {
    final store = _store;
    if (store == null) return;
    if (store["is_open"] != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Esta tienda está cerrada en este momento"),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    // Validar stock
    final stock = item["stock"] as int?;
    if ((stock ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("❌ ${item["name"]} está agotado"),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    // Validar cantidad disponible
    final itemId = item["id"] as String;
    final storeId2 = store["id"] as String;
    final currentQty = cart.getStoreQuantity(storeId2, itemId);
    if (stock != null && currentQty + 1 > stock) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("⚠️ Solo quedan $stock disponibles de ${item["name"]}"),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    cart.addItem(CartItem(
      id: itemId,
      storeId: storeId2,
      storeName: store["name"] as String? ?? "",
      name: item["name"] as String? ?? "",
      price: basePrice,
      imageUrl: item["image_url"] as String?,
    ));
  }
}

class _ReviewsSection extends StatefulWidget {
  final String storeId;
  final SupabaseClient sb;
  const _ReviewsSection({required this.storeId, required this.sb});
  @override State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  List<Map<String, dynamic>> _reviews = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.sb.from("reviews")
          .select("rating_store, comment, created_at, users(name)")
          .eq("store_id", widget.storeId)
          .not("rating_store", "is", null)
          .order("created_at", ascending: false)
          .limit(10);
      if (mounted) setState(() { _reviews = List<Map<String, dynamic>>.from(res); _loaded = true; });
    } catch (_) { if (mounted) setState(() => _loaded = true); }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _reviews.isEmpty) return const SizedBox.shrink();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Reseñas", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        ..._reviews.map((r) {
          final stars = (r["rating_store"] as num?)?.toInt() ?? 0;
          final comment = r["comment"] as String?;
          final name = (r["users"] as Map<String, dynamic>?)?["name"] as String? ?? "Cliente";
          final date = r["created_at"] as String? ?? "";
          final d = date.isNotEmpty ? DateTime.tryParse(date) : null;
          final dateLabel = d != null ? "${d.day}/${d.month}/${d.year}" : "";
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Row(children: List.generate(5, (i) => Icon(
                  i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: Colors.amber, size: 16))),
                const Spacer(),
                Text(dateLabel, style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
              ]),
              const SizedBox(height: 6),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              if (comment != null && comment.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(comment, style: const TextStyle(color: AppColors.textMedium, fontSize: 13, height: 1.4)),
              ],
            ]),
          );
        }),
      ]),
    );
  }
}