import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:shimmer/shimmer.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _vaciarTodosLoading = false;
  Map<String, int> _stockCache = {}; // baseItemId -> stock

  @override
  void initState() { super.initState(); _loadStock(); }

  Future<void> _loadStock() async {
    try {
      final cart = context.read<CartProvider>();
      final allIds = <String>{};
      for (final storeId in cart.storeIds) {
        for (final item in cart.getItemsForStore(storeId)) {
          allIds.add(item.id.split("__").first);
        }
      }
      if (allIds.isEmpty) return;
      final data = await Supabase.instance.client
          .from("menu_items")
          .select("id,stock")
          .inFilter("id", allIds.toList());
      final map = <String, int>{};
      for (final row in List<Map<String, dynamic>>.from(data)) {
        final s = row["stock"] as int?;
        if (s != null) map[row["id"] as String] = s;
      }
      if (mounted) setState(() => _stockCache = map);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final storeIds = cart.storeIds;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(cart.isEmpty
            ? "Tu carrito"
            : "Mis carritos (${storeIds.length})"),
        backgroundColor: Colors.transparent,
        flexibleSpace: const GradientFlexibleSpace(),
        actions: [
          if (!cart.isEmpty)
            TextButton(
              onPressed: _vaciarTodosLoading ? null : () => _confirmClearAll(cart),
              child: _vaciarTodosLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white70, strokeWidth: 2))
                  : const Text("Vaciar todo",
                      style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: cart.isEmpty
          ? Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  const Text("Carrito vacío",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textLight)),
                  const SizedBox(height: 8),
                  const Text("Agrega productos desde las tiendas",
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textLight)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go("/home"),
                    child: const Text("Explorar tiendas"),
                  ),
                ]))
          : Column(children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: storeIds.length,
                  itemBuilder: (ctx, i) {
                    final storeId = storeIds[i];
                    return _buildStoreGroup(cart, storeId);
                  },
                ),
              ),
              // Resumen total
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, -4))
                  ],
                ),
                child: Column(children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            "${cart.itemCount} producto${cart.itemCount != 1 ? "s" : ""} en ${storeIds.length} tienda${storeIds.length != 1 ? "s" : ""}",
                            style: const TextStyle(
                                color: AppColors.textLight,
                                fontWeight: FontWeight.w600)),
                      ]),
                ]),
              ),
            ]),
    );
  }

  Widget _buildStoreGroup(CartProvider cart, String storeId) {
    final items = cart.getItemsForStore(storeId);
    final storeName = cart.getStoreName(storeId) ?? "Tienda";
    final emoji = items.isNotEmpty ? items.first.emoji : "🛒";
    final count = cart.getStoreItemCount(storeId);
    final sub = cart.getStoreSubtotal(storeId);

    return Dismissible(
      key: Key(storeId),
      direction: DismissDirection.horizontal,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("¿Eliminar carrito?"),
                content:
                    Text("Se eliminarán los $count productos de $storeName."),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Cancelar")),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text("Eliminar",
                          style: TextStyle(color: AppColors.error))),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => cart.clearStoreCart(storeId),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child:
            const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header de tienda
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(storeName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        Text("$count producto${count != 1 ? "s" : ""}",
                            style: const TextStyle(
                                color: AppColors.textLight, fontSize: 12)),
                      ]),
                ),
                Text(
                  _fmt(sub),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.accent),
                ),
              ]),
            ),
            // Items
            ...items.map((item) => _buildItemRow(cart, storeId, item)),
            const SizedBox(height: 8),
            // Botón Pagar
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    cart.activeStoreId = storeId;
                    context.push("/checkout/$storeId");
                  },
                  child: Text("Pagar · ${_fmt(sub)}"),
                ),
              ),
            ),
            // Separador
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Divider(height: 1, thickness: 1),
            ),
            // Recomendaciones de la misma tienda (debajo de pagar)
            _StoreRecs(
              storeId: storeId,
              storeName: storeName,
              cart: cart,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(
      CartProvider cart, String storeId, CartItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(children: [
        // Imagen
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: item.imageUrl != null
                ? Image.network(item.imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _itemPlaceholder(item))
                : _itemPlaceholder(item),
          ),
        ),
        const SizedBox(width: 12),
        // Nombre + variante
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                if (item.variant != null)
                  Text(item.variant!,
                      style: const TextStyle(
                          color: AppColors.textLight, fontSize: 11)),
                Text(_fmt(item.totalPrice),
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ]),
        ),
        // Controles +/-
        Row(children: [
          GestureDetector(
            onTap: () {
              cart.activeStoreId = storeId;
              cart.removeItem(item.id, variant: item.variant);
            },
            child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.remove,
                    color: Colors.white, size: 16)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text("${item.quantity}",
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          GestureDetector(
            onTap: () {
              cart.activeStoreId = storeId;
              final baseId = item.id.split("__").first;
              final stock = _stockCache[baseId];
              if (stock != null && stock <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("❌ ${item.name} está agotado"),
                  backgroundColor: Colors.red,
                ));
                return;
              }
              if (stock != null && item.quantity >= stock) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text("⚠️ Solo quedan $stock disponibles de ${item.name}"),
                  backgroundColor: Colors.red,
                ));
                return;
              }
              cart.addItem(item);
            },
            child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.add,
                    color: Colors.white, size: 16)),
          ),
        ]),
      ]),
    );
  }

  Widget _itemPlaceholder(CartItem item) => Container(
        color: AppColors.homeBackground,
        child: Center(
            child: Text(item.emoji, style: const TextStyle(fontSize: 22))),
      );

  Future<void> _confirmClearAll(CartProvider cart) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("¿Vaciar todos los carritos?"),
            content: const Text(
                "Se eliminarán todos los productos de todas las tiendas."),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancelar")),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Vaciar todo",
                      style: TextStyle(color: AppColors.error))),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      setState(() => _vaciarTodosLoading = true);
      cart.clearCart();
      if (mounted) {
        setState(() => _vaciarTodosLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Todos los carritos fueron vaciados")),
        );
      }
    }
  }

  String _fmt(int p) =>
      "\$${p.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
}

// ══════════════════════════════════════════════════════════════════════════════
// Recomendaciones de productos de la misma tienda
// ══════════════════════════════════════════════════════════════════════════════
class _StoreRecs extends StatefulWidget {
  final String storeId;
  final String storeName;
  final CartProvider cart;
  const _StoreRecs({
    required this.storeId,
    required this.storeName,
    required this.cart,
  });
  @override
  State<_StoreRecs> createState() => _StoreRecsState();
}

class _StoreRecsState extends State<_StoreRecs> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _recs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _sb
          .from("menu_items")
          .select("id, name, price, emoji, image_url, is_available")
          .eq("store_id", widget.storeId)
          .eq("is_available", true)
          .eq("is_popular", true)
          .order("sort_order")
          .limit(8);
      if (mounted) {
        setState(() {
          _recs = List<Map<String, dynamic>>.from(raw as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: SizedBox(
          height: 100,
          child: Shimmer.fromColors(
            baseColor: const Color(0xFFDDD0F0),
            highlightColor: const Color(0xFFF5F0FF),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              itemBuilder: (_, __) => Container(
                width: 120,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_recs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            const Text("Para agregar a tu pedido",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMedium)),
            const Spacer(),
            GestureDetector(
              onTap: () => context.push("/store/${widget.storeId}"),
              child: const Text("Ver más",
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _recs.length,
              itemBuilder: (_, i) => _recCard(_recs[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recCard(Map<String, dynamic> item) {
    final price = (item["price"] as num?)?.toInt() ?? 0;
    final name = item["name"] as String? ?? "";
    final imgUrl = item["image_url"] as String?;
    final emoji = item["emoji"] as String? ?? "🍽️";
    final hasVariants = _itemHasVariants(item);

    return GestureDetector(
      onTap: () {
        if (hasVariants) {
          context.push("/product/${item["id"]}");
        } else {
          widget.cart.addItem(CartItem(
            id: item["id"] as String,
            storeId: widget.storeId,
            storeName: widget.storeName,
            name: name,
            price: price,
            emoji: emoji,
            imageUrl: imgUrl,
          ));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$name agregado"),
              backgroundColor: AppColors.homeOrange,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: imgUrl != null
                    ? Image.network(imgUrl, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) =>
                            Center(child: Text(emoji, style: const TextStyle(fontSize: 22))))
                    : Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 22))),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            "\$${price.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}",
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.accent),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: hasVariants
                                ? Colors.transparent
                                : AppColors.accent,
                            shape: BoxShape.circle,
                            border: hasVariants
                                ? Border.all(color: AppColors.accent)
                                : null,
                          ),
                          child: Icon(
                            hasVariants ? Icons.arrow_forward : Icons.add,
                            color: hasVariants
                                ? AppColors.accent
                                : Colors.white,
                            size: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _itemHasVariants(Map<String, dynamic> item) {
    try {
      final vs = item["variants"];
      if (vs != null) {
        if (vs is String && vs.isNotEmpty) return true;
        if (vs is List && vs.isNotEmpty) return true;
      }
      final vgs = item["variant_groups"];
      if (vgs != null) {
        if (vgs is String && vgs.isNotEmpty) return true;
        if (vgs is List && vgs.isNotEmpty) return true;
      }
    } catch (_) {}
    return false;
  }
}
