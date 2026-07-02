import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  String _fmt(int p) =>
      "\$${p.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _vaciarTodosLoading = false;

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
                  _fmt(widget, sub),
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
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    cart.activeStoreId = storeId;
                    context.push("/checkout/$storeId");
                  },
                  child: Text("Pagar · ${_fmt(widget, sub)}"),
                ),
              ),
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
                Text(_fmt(widget, item.totalPrice),
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
      cart.clearAllCarts();
      if (mounted) {
        setState(() => _vaciarTodosLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Todos los carritos fueron vaciados")),
        );
      }
    }
  }

  String _fmt(Widget widget, int p) =>
      "\$${p.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
}
