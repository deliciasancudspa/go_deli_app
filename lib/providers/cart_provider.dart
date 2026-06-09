import "package:flutter/material.dart";

class CartItem {
  final String id, storeId, storeName, name, emoji;
  final int price;
  final String? imageUrl, notes, variant;
  final List<Map<String, dynamic>> extras;
  int quantity;

  CartItem({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.name,
    required this.price,
    this.emoji = "X",
    this.imageUrl,
    this.notes,
    this.variant,
    this.extras = const [],
    this.quantity = 1,
  });

  int get totalPrice => ((price + extras.fold(0, (s, e) => s + (e["price"] as int? ?? 0))) * quantity).toInt();
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  String? _currentStoreId;

  List<CartItem> get items => _items;
  String? get currentStoreId => _currentStoreId;
  int get itemCount => _items.fold(0, (s, i) => s + i.quantity);
  int get subtotal => _items.fold(0, (s, i) => s + i.totalPrice);
  bool get isEmpty => _items.isEmpty;

  void addItem(CartItem item) {
    if (_currentStoreId != null && _currentStoreId != item.storeId) clearCart();
    _currentStoreId = item.storeId;
    // Items with variants/extras are always new lines (don't merge)
    final hasCustomization = item.variant != null || item.extras.isNotEmpty;
    if (!hasCustomization) {
      final idx = _items.indexWhere((i) => i.id == item.id && i.variant == null && i.extras.isEmpty);
      if (idx >= 0) { _items[idx].quantity++; notifyListeners(); return; }
    }
    _items.add(item);
    notifyListeners();
  }

  void removeItem(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      if (_items[idx].quantity > 1) {
        _items[idx].quantity--;
      } else {
        _items.removeAt(idx);
      }
    }
    if (_items.isEmpty) _currentStoreId = null;
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _currentStoreId = null;
    notifyListeners();
  }

  int getQuantity(String id) {
    try { return _items.firstWhere((i) => i.id == id).quantity; } catch (_) { return 0; }
  }
}
