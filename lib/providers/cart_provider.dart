import "dart:convert";
import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

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
    this.emoji = "🍽️",
    this.imageUrl,
    this.notes,
    this.variant,
    this.extras = const [],
    this.quantity = 1,
  });

  int get totalPrice =>
      ((price + extras.fold(0, (s, e) => s + (e["price"] as int? ?? 0))) * quantity).toInt();

  Map<String, dynamic> toJson() => {
        "id": id,
        "storeId": storeId,
        "storeName": storeName,
        "name": name,
        "price": price,
        "emoji": emoji,
        "imageUrl": imageUrl,
        "notes": notes,
        "variant": variant,
        "extras": extras,
        "quantity": quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        id: j["id"] as String,
        storeId: j["storeId"] as String,
        storeName: j["storeName"] as String,
        name: j["name"] as String,
        price: j["price"] as int,
        emoji: j["emoji"] as String? ?? "🍽️",
        imageUrl: j["imageUrl"] as String?,
        notes: j["notes"] as String?,
        variant: j["variant"] as String?,
        extras: (j["extras"] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
        quantity: j["quantity"] as int? ?? 1,
      );
}

class CartProvider extends ChangeNotifier {
  // ── Multi-store state ─────────────────────────────────────────────────────
  // storeId → List<CartItem>
  final Map<String, List<CartItem>> _carts = {};
  String? _activeStoreId;
  bool _loaded = false;

  static const _prefsCartsKey = "carts_v2";
  static const _prefsActiveKey = "active_store_id";

  // ── Backward-compat getters ───────────────────────────────────────────────

  /// Items de la tienda activa (backward compat).
  List<CartItem> get items {
    if (_activeStoreId == null) return [];
    return _carts[_activeStoreId] ?? [];
  }

  /// Total de items en TODOS los carritos combinados (backward compat).
  int get itemCount =>
      _carts.values.fold(0, (s, list) => s + list.fold(0, (ss, i) => ss + i.quantity));

  /// Subtotal de la tienda activa (backward compat).
  int get subtotal {
    if (_activeStoreId == null) return 0;
    return (_carts[_activeStoreId] ?? [])
        .fold(0, (s, i) => s + i.totalPrice);
  }

  /// true si NO hay items en ningún carrito.
  bool get isEmpty => _carts.values.every((list) => list.isEmpty);

  /// ID de la tienda activa.
  String? get activeStoreId => _activeStoreId;

  /// Setter: cambia la tienda activa (para navegación multi-carrito).
  set activeStoreId(String? v) {
    _activeStoreId = v;
    notifyListeners();
  }

  // ── Multi-store specific ──────────────────────────────────────────────────

  /// Cuántos carritos hay (tiendas distintas con items).
  int get storeCount => _carts.length;

  /// IDs de todas las tiendas con carrito.
  List<String> get storeIds => _carts.keys.toList();

  /// Items de un store específico (inmutables).
  List<CartItem> getItemsForStore(String storeId) =>
      List.unmodifiable(_carts[storeId] ?? []);

  /// Cantidad total de items en el carrito de una tienda.
  int getStoreItemCount(String storeId) {
    final list = _carts[storeId];
    if (list == null) return 0;
    return list.fold(0, (s, i) => s + i.quantity);
  }

  /// Subtotal del carrito de una tienda.
  int getStoreSubtotal(String storeId) {
    final list = _carts[storeId];
    if (list == null) return 0;
    return list.fold(0, (s, i) => s + i.totalPrice);
  }

  /// Nombre de la tienda (del primer item del carrito activo).
  String? get activeStoreName {
    final list = _carts[_activeStoreId];
    if (list == null || list.isEmpty) return null;
    return list.first.storeName;
  }

  /// Nombre de una tienda específica.
  String? getStoreName(String storeId) {
    final list = _carts[storeId];
    if (list == null || list.isEmpty) return null;
    return list.first.storeName;
  }

  // ── Core operations ───────────────────────────────────────────────────────

  /// Agrega un item al carrito de su tienda.
  /// NUNCA borra otros carritos. Si es una tienda nueva, crea su carrito.
  void addItem(CartItem item) {
    _carts.putIfAbsent(item.storeId, () => []);
    _activeStoreId = item.storeId;

    final list = _carts[item.storeId]!;
    // Buscar coincidencia exacta (mismo id + variante + extras)
    final idx = list.indexWhere((i) =>
        i.id == item.id &&
        i.variant == item.variant &&
        _extrasMatch(i.extras, item.extras));

    if (idx >= 0) {
      list[idx].quantity++;
    } else {
      list.add(item);
    }

    _save();
    notifyListeners();
  }

  /// Elimina un item del carrito activo (backward compat).
  /// Si la cantidad llega a 0, elimina el item. Si el store queda vacío, lo elimina.
  void removeItem(String id, {String? variant, List<Map<String, dynamic>>? extras}) {
    if (_activeStoreId == null) return;
    final list = _carts[_activeStoreId];
    if (list == null) return;

    final idx = list.indexWhere(
        (i) => i.id == id && (variant == null || i.variant == variant) && (extras == null || _extrasMatch(i.extras, extras)));
    if (idx < 0) return;

    if (list[idx].quantity > 1) {
      list[idx].quantity--;
    } else {
      list.removeAt(idx);
    }

    if (list.isEmpty) {
      _carts.remove(_activeStoreId);
      _activeStoreId = _carts.keys.firstOrNull;
    }

    _save();
    notifyListeners();
  }

  /// Cantidad de un item en el carrito activo (backward compat).
  int getQuantity(String id, {String? variant, List<Map<String, dynamic>>? extras}) {
    if (_activeStoreId == null) return 0;
    final list = _carts[_activeStoreId];
    if (list == null) return 0;
    try {
      return list.firstWhere((i) => i.id == id && (variant == null || i.variant == variant) && (extras == null || _extrasMatch(i.extras, extras))).quantity;
    } catch (_) {
      return 0;
    }
  }

  /// Cantidad de un item en el carrito de una tienda específica.
  int getStoreQuantity(String storeId, String itemId, {String? variant, List<Map<String, dynamic>>? extras}) {
    final list = _carts[storeId];
    if (list == null) return 0;
    try {
      return list.firstWhere((i) => i.id == itemId && (variant == null || i.variant == variant) && (extras == null || _extrasMatch(i.extras, extras))).quantity;
    } catch (_) {
      return 0;
    }
  }

  // ── Clear operations ──────────────────────────────────────────────────────

  /// Vacía solo el carrito de la tienda activa.
  void clearActiveCart() {
    if (_activeStoreId == null) return;
    clearStoreCart(_activeStoreId!);
  }

  /// Vacía el carrito de una tienda específica.
  void clearStoreCart(String storeId) {
    _carts.remove(storeId);
    if (_activeStoreId == storeId) {
      _activeStoreId = _carts.keys.firstOrNull;
    }
    _save();
    notifyListeners();
  }

  /// Vacía TODOS los carritos (backward compat).
  void clearCart() {
    _carts.clear();
    _activeStoreId = null;
    _save();
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _extrasMatch(
      List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]["name"] != b[i]["name"] || a[i]["price"] != b[i]["price"]) {
        return false;
      }
    }
    return true;
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Carga los carritos guardados desde SharedPreferences.
  /// Se llama una sola vez al iniciar la app.
  Future<void> loadSavedCarts() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsCartsKey);
      if (raw == null || raw.isEmpty) return;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in data.entries) {
        final storeData = entry.value as Map<String, dynamic>;
        final items = (storeData["items"] as List<dynamic>)
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList();
        if (items.isNotEmpty) {
          _carts[entry.key] = items;
        }
      }

      final savedActive = prefs.getString(_prefsActiveKey);
      if (savedActive != null && _carts.containsKey(savedActive)) {
        _activeStoreId = savedActive;
      } else if (_carts.isNotEmpty) {
        _activeStoreId = _carts.keys.first;
      }
      notifyListeners();
    } catch (_) {
      // Si falla la carga, empezar limpio.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{};
      for (final entry in _carts.entries) {
        if (entry.value.isEmpty) continue;
        data[entry.key] = {
          "items": entry.value.map((i) => i.toJson()).toList(),
        };
      }
      await prefs.setString(_prefsCartsKey, jsonEncode(data));
      if (_activeStoreId != null) {
        await prefs.setString(_prefsActiveKey, _activeStoreId!);
      }
    } catch (_) {
      // Persistencia es best-effort, no bloquea la UI.
    }
  }
}
