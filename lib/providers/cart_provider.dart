import 'package:flutter/material.dart';

class CartItem {
  final String id, storeId, storeName, name, emoji;
  final int price;
  final String? imageUrl, notes;
  final List<Map<String, dynamic>> extras;
  int quantity;
  CartItem({required this.id, required this.storeId, required this.storeName, required this.name, required this.price, this.emoji = '🍽️', this.imageUrl, this.notes, this.extras = const [], this.quantity = 1});
  int get totalPrice {
    int extrasTotal = extras.fold(0, (int s, e) => s + (e['price'] as int? ?? 0));
    return (price + extrasTotal) * quantity;
  }
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
    final idx = _items.indexWhere((i) => i.id == item.id);
    if (idx >= 0) { _items[idx].quantity++; } else { _items.add(item); }
    notifyListeners();
  }

  void removeItem(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) { if (_items[idx].quantity > 1) { _items[idx].quantity--; } else { _items.removeAt(idx); } }
    if (_items.isEmpty) _currentStoreId = null;
    notifyListeners();
  }

  void deleteItem(String id) { _items.removeWhere((i) => i.id == id); if (_items.isEmpty) _currentStoreId = null; notifyListeners(); }
  void clearCart() { _items.clear(); _currentStoreId = null; notifyListeners(); }
  int getQuantity(String id) { try { return _items.firstWhere((i) => i.id == id).quantity; } catch (_) { return 0; } }
}