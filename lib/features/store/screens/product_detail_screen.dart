import "dart:convert";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/cart_provider.dart";

const _kOrange = AppColors.homeOrange;
const _kDark   = AppColors.homeDark;
const _kBg     = AppColors.homeBackground;

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _sb = Supabase.instance.client;

  Map<String, dynamic>? _item;
  Map<String, dynamic>? _store;
  bool _loading = true;

  List<Map<String, dynamic>> _variants      = [];
  List<Map<String, dynamic>> _variantGroups = [];
  List<Map<String, dynamic>> _optGroups     = [];
  List<Map<String, dynamic>> _recProducts   = [];

  int _selectedVariantIdx = 0;
  final Map<int, int>    _selectedVGItems  = {};
  final Map<String, int> _selectedSubItems = {};
  final Set<String>      _selectedExtras   = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final item = await _sb.from("menu_items")
          .select()
          .eq("id", widget.productId)
          .single();

      final store = await _sb.from("stores")
          .select("id,name,emoji,store_type")
          .eq("id", item["store_id"] as String)
          .single();

      List<Map<String, dynamic>> variants = [];
      try {
        final vs = item["variants"];
        if (vs != null) {
          final raw = vs is String ? (vs.isNotEmpty ? jsonDecode(vs) as List : []) : vs as List;
          variants = raw.cast<Map<String, dynamic>>();
        }
      } catch (_) {}

      List<Map<String, dynamic>> variantGroups = [];
      try {
        final vgs = item["variant_groups"];
        if (vgs != null) {
          final raw = vgs is String ? (vgs.isNotEmpty ? jsonDecode(vgs) as List : []) : vgs as List;
          variantGroups = raw.cast<Map<String, dynamic>>();
        }
      } catch (_) {}

      List<Map<String, dynamic>> optGroups = [];
      try {
        final os = item["options"];
        if (os != null) {
          final decoded = os is String ? (os.isNotEmpty ? jsonDecode(os) : null) : os;
          if (decoded is List) {
            optGroups = decoded.cast<Map<String, dynamic>>();
          } else if (decoded is Map) {
            optGroups = [decoded.cast<String, dynamic>()];
          }
        }
      } catch (_) {}

      List<Map<String, dynamic>> recProds = [];
      try {
        final rs = item["recommendations"];
        if (rs != null) {
          final rawRecs = rs is String ? (rs.isNotEmpty ? jsonDecode(rs) as List : []) : rs as List;
          final ids = rawRecs
              .cast<Map<String, dynamic>>()
              .map((r) => r["id"] as String?)
              .whereType<String>()
              .take(5)
              .toList();
          if (ids.isNotEmpty) {
            final raw = await _sb.from("menu_items")
                .select()
                .inFilter("id", ids)
                .eq("is_available", true);
            recProds = List<Map<String, dynamic>>.from(raw as List);
          }
        }
      } catch (_) {}

      if (mounted) setState(() {
        _item          = item;
        _store         = store;
        _variants      = variants;
        _variantGroups = variantGroups;
        _optGroups     = optGroups;
        _recProducts   = recProds;
        _loading       = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Base price from variant_groups selections, simple variants, or item price
  int get _basePrice {
    if (_variantGroups.isNotEmpty) {
      var total = 0;
      for (var gi = 0; gi < _variantGroups.length; gi++) {
        final selIdx = _selectedVGItems[gi];
        if (selIdx == null) continue;
        final items = (_variantGroups[gi]["items"] as List? ?? []).cast<Map<String, dynamic>>();
        if (selIdx < items.length) {
          total += (items[selIdx]["price"] as num?)?.toInt() ?? 0;
        }
        final subs = (_variantGroups[gi]["subGroups"] as List? ?? []).cast<Map<String, dynamic>>();
        for (var sgi = 0; sgi < subs.length; sgi++) {
          final subSelIdx = _selectedSubItems["${gi}_${selIdx}_$sgi"];
          if (subSelIdx == null) continue;
          final subItems = (subs[sgi]["items"] as List? ?? []).cast<Map<String, dynamic>>();
          if (subSelIdx < subItems.length) {
            total += (subItems[subSelIdx]["price"] as num?)?.toInt() ?? 0;
          }
        }
      }
      return total;
    }
    if (_variants.isNotEmpty) {
      return ((_variants[_selectedVariantIdx]["price"] as num?)?.toInt()) ??
          ((_item?["price"] as num?)?.toInt() ?? 0);
    }
    return (_item?["price"] as num?)?.toInt() ?? 0;
  }

  int get _extrasTotal {
    var sum = 0;
    for (final g in _optGroups) {
      for (final it in (g["items"] as List? ?? []).cast<Map<String, dynamic>>()) {
        if (_selectedExtras.contains("${g["title"]}::${it["name"]}")) {
          sum += (it["price"] as num?)?.toInt() ?? 0;
        }
      }
    }
    return sum;
  }

  int get _totalPrice => _basePrice + _extrasTotal;

  // Disabled until all required groups have enough selections
  bool get _canAddToCart {
    for (var gi = 0; gi < _variantGroups.length; gi++) {
      if (!_selectedVGItems.containsKey(gi)) return false;
    }
    for (final g in _optGroups) {
      final minSel = (g["min_sel"] as num?)?.toInt() ?? 0;
      if (minSel > 0) {
        final title = g["title"] as String? ?? "";
        final selected = _selectedExtras.where((k) => k.startsWith("$title::")).length;
        if (selected < minSel) return false;
      }
    }
    return true;
  }

  // Minimum price across all variant options (for "Desde $X" display)
  int get _minDisplayPrice {
    if (_variantGroups.isNotEmpty) {
      var min = 2147483647;
      for (final g in _variantGroups) {
        for (final it in (g["items"] as List? ?? []).cast<Map<String, dynamic>>()) {
          final p = (it["price"] as num?)?.toInt() ?? 0;
          if (p < min) min = p;
        }
      }
      return min == 2147483647 ? 0 : min;
    }
    if (_variants.isNotEmpty) {
      return _variants
          .map((v) => (v["price"] as num?)?.toInt() ?? 0)
          .reduce((a, b) => a < b ? a : b);
    }
    return (_item?["price"] as num?)?.toInt() ?? 0;
  }

  String _fmt(int p) => "\$${p.toString().replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  // Composite cart ID encodes all variant_group selections
  String _buildCompositeCartId() {
    final base = _item!["id"] as String;
    if (_variantGroups.isEmpty) return base;
    final parts = <String>[];
    for (var gi = 0; gi < _variantGroups.length; gi++) {
      final selIdx   = _selectedVGItems[gi] ?? -1;
      final subParts = <String>[];
      if (selIdx >= 0) {
        final subs = (_variantGroups[gi]["subGroups"] as List? ?? []).cast<Map<String, dynamic>>();
        for (var sgi = 0; sgi < subs.length; sgi++) {
          subParts.add(_selectedSubItems["${gi}_${selIdx}_$sgi"]?.toString() ?? "x");
        }
      }
      parts.add("${gi}_$selIdx${subParts.isEmpty ? "" : "_${subParts.join("_")}"}");
    }
    return "${base}__vg__${parts.join("|")}";
  }

  String _buildVariantLabel() {
    if (_variantGroups.isEmpty) {
      return _variants.isNotEmpty
          ? (_variants[_selectedVariantIdx]["name"] as String? ?? "")
          : "";
    }
    final parts = <String>[];
    for (var gi = 0; gi < _variantGroups.length; gi++) {
      final selIdx = _selectedVGItems[gi];
      if (selIdx == null) continue;
      final items = (_variantGroups[gi]["items"] as List? ?? []).cast<Map<String, dynamic>>();
      if (selIdx < items.length) parts.add(items[selIdx]["name"] as String? ?? "");
      final subs = (_variantGroups[gi]["subGroups"] as List? ?? []).cast<Map<String, dynamic>>();
      for (var sgi = 0; sgi < subs.length; sgi++) {
        final subSelIdx = _selectedSubItems["${gi}_${selIdx}_$sgi"];
        if (subSelIdx == null) continue;
        final subItems = (subs[sgi]["items"] as List? ?? []).cast<Map<String, dynamic>>();
        if (subSelIdx < subItems.length) parts.add(subItems[subSelIdx]["name"] as String? ?? "");
      }
    }
    return parts.join(" · ");
  }

  void _addToCart() {
    if (_item == null || _store == null || !_canAddToCart) return;
    final cartId  = _buildCompositeCartId();
    final label   = _buildVariantLabel();
    final variant = label.isEmpty ? null : label;
    final extras  = <Map<String, dynamic>>[];
    for (final g in _optGroups) {
      for (final it in (g["items"] as List? ?? []).cast<Map<String, dynamic>>()) {
        final key = "${g["title"]}::${it["name"]}";
        if (_selectedExtras.contains(key)) {
          extras.add({"name": it["name"], "price": (it["price"] as num?)?.toInt() ?? 0});
        }
      }
    }
    context.read<CartProvider>().addItem(CartItem(
      id:        cartId,
      storeId:   _store!["id"] as String,
      storeName: _store!["name"] as String? ?? "",
      name:      _item!["name"] as String? ?? "",
      emoji:     _item!["emoji"] as String? ?? "🍽️",
      imageUrl:  _item!["image_url"] as String?,
      price:     _basePrice,
      variant:   variant,
      extras:    extras,
    ));
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("${_item!["name"]} agregado al carrito"),
      backgroundColor: _kOrange,
      duration: const Duration(seconds: 2),
    ));
  }

  bool _itemHasVariants(Map<String, dynamic> item) {
    try {
      final vs = item["variants"];
      if (vs != null) {
        final raw = vs is String ? (vs.isNotEmpty ? jsonDecode(vs) as List : const []) : vs as List;
        if (raw.isNotEmpty) return true;
      }
    } catch (_) {}
    try {
      final vgs = item["variant_groups"];
      if (vgs != null) {
        final raw = vgs is String ? (vgs.isNotEmpty ? jsonDecode(vgs) as List : const []) : vgs as List;
        if (raw.isNotEmpty) return true;
      }
    } catch (_) {}
    return false;
  }


  // ── Ficha del producto: campos por tipo de negocio ─────────────────────────
  // (farmacia: laboratorio/principio activo/formato · mercado: marca/unidad ·
  //  tienda: marca/SKU/garantía · restaurante: tiempo/calorías/alérgenos)
  Map<String, dynamic> get _extraInfo {
    final raw = _item?["extra_info"];
    try {
      if (raw is Map) return raw.cast<String, dynamic>();
      if (raw is String && raw.isNotEmpty) {
        return (jsonDecode(raw) as Map).cast<String, dynamic>();
      }
    } catch (_) {}
    return const {};
  }

  List<Widget> _productInfoSection() {
    final x = _extraInfo;
    final rows = <List<String>>[];
    void add(String label, dynamic v, [String suffix = ""]) {
      final s = v?.toString().trim() ?? "";
      if (s.isNotEmpty) rows.add([label, "$s$suffix"]);
    }

    add("🏭 Laboratorio", x["laboratorio"]);
    add("💊 Principio activo", _item?["active_ingredient"]);
    add("📦 Formato", x["formato"]);
    add("🏷️ Marca", x["marca"]);
    if ((x["unidad"] ?? "un") != "un") add("⚖️ Se vende por", x["unidad"]);
    add("🔢 Código", x["sku"]);
    add("🛡️ Garantía", x["garantia"]);
    add("⏱️ Preparación", _item?["preparation_time"], " min");
    add("🔥 Calorías", _item?["calories"], " kcal");
    final allergens = _item?["allergens"] as String?;
    if (allergens != null && allergens.trim().isNotEmpty) {
      rows.add(["⚠️ Alérgenos", allergens.split(",").map((a) => a.trim()).join(", ")]);
    }

    final badges = <List<dynamic>>[];
    if (_item?["requires_prescription"] == true) badges.add([const Color(0xFFFEF3C7), const Color(0xFF92400E), "📋 Requiere receta médica"]);
    if (x["refrigerado"] == true)                badges.add([const Color(0xFFE0F2FE), const Color(0xFF075985), "❄️ Refrigerado"]);
    if (x["controlado"] == true)                 badges.add([const Color(0xFFFEE2E2), const Color(0xFF991B1B), "⚠️ Producto controlado"]);
    if (_item?["contains_alcohol"] == true)      badges.add([const Color(0xFFFEE2E2), const Color(0xFF991B1B), "🔞 Contiene alcohol"]);
    final tags = _item?["tags"] as String?;
    if (tags != null) {
      const labels = {"vegano": "🌱 Vegano", "vegetariano": "🥬 Vegetariano", "picante": "🌶️ Picante", "sin_gluten": "🌾 Sin gluten"};
      for (final t in tags.split(",")) {
        final l = labels[t.trim()];
        if (l != null) badges.add([const Color(0xFFF0FDF4), const Color(0xFF166534), l]);
      }
    }

    if (rows.isEmpty && badges.isEmpty) return const [];
    return [
      if (badges.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: badges.map((b) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: b[0] as Color, borderRadius: BorderRadius.circular(20)),
          child: Text(b[2] as String, style: TextStyle(color: b[1] as Color, fontSize: 11, fontWeight: FontWeight.w800)),
        )).toList()),
      ],
      if (rows.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            for (final r in rows) Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r[0], style: const TextStyle(color: AppColors.textLight, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(child: Text(r[1], textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              ]),
            ),
          ]),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: _kOrange)));
    }
    if (_item == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.primary,
            leading: const BackButton(color: Colors.white)),
        body: const Center(child: Text("Producto no encontrado")),
      );
    }

    final imgUrl   = _item!["image_url"] as String?;
    final discPct  = (_item!["discount_pct"] as int?) ?? 0;
    final origPrice = (_item!["original_price"] as num?)?.toInt();
    final showOrig = discPct > 0 && origPrice != null;
    final hasVGOrV = _variantGroups.isNotEmpty || _variants.isNotEmpty;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          // Hero image
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: AppColors.primary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              Consumer<CartProvider>(builder: (_, cart, __) => Stack(children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                  onPressed: () => context.push("/cart"),
                ),
                if (cart.itemCount > 0) Positioned(
                  right: 6, top: 6,
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(color: _kOrange, shape: BoxShape.circle),
                    child: Center(child: Text("${cart.itemCount}",
                        style: const TextStyle(color: Colors.white,
                            fontSize: 9, fontWeight: FontWeight.w900))),
                  ),
                ),
              ])),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: imgUrl != null
                  ? Image.network(imgUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imgPh())
                  : _imgPh(),
            ),
          ),

          SliverToBoxAdapter(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product header
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_item!["name"] as String? ?? "",
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                          color: _kDark)),
                  if (_item!["description"] != null) ...[
                    const SizedBox(height: 6),
                    Text(_item!["description"] as String,
                        style: const TextStyle(color: AppColors.textLight,
                            fontSize: 13, height: 1.4)),
                  ],
                  ..._productInfoSection(),
                  const SizedBox(height: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Text(hasVGOrV ? "Desde ${_fmt(_minDisplayPrice)}" : _fmt(_basePrice),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                              color: _kOrange)),
                      if (discPct > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: _kOrange, borderRadius: BorderRadius.circular(8)),
                          child: Text("-$discPct%",
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 12, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ]),
                    if (showOrig) ...[
                      const SizedBox(height: 4),
                      Text(_fmt(origPrice),
                          style: const TextStyle(fontSize: 13, color: AppColors.textLight,
                              decoration: TextDecoration.lineThrough)),
                    ],
                  ]),
                ]),
              ),

              // Variant groups (radio lists with optional subgroup cascade)
              for (var gi = 0; gi < _variantGroups.length; gi++) ...[
                const SizedBox(height: 10),
                _variantGroupSection(gi),
              ],

              // Simple variants (chips) — only shown when no variant_groups
              if (_variants.isNotEmpty && _variantGroups.isEmpty) ...[
                const SizedBox(height: 10),
                _section("Elige tu opción", required: true,
                  child: Wrap(spacing: 8, runSpacing: 8,
                    children: List.generate(_variants.length, _variantChip))),
              ],

              // Options / adicionales
              for (final group in _optGroups) ...[
                const SizedBox(height: 10),
                _optionGroupSection(group),
              ],

              // Recommendations
              if (_recProducts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("Te recomendamos también",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                            color: _kDark)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recProducts.length,
                        itemBuilder: (_, i) => _recCard(_recProducts[i]),
                      ),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 100),
            ],
          )),
        ]),

        // Sticky add-to-cart button — disabled until required groups are selected
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12, offset: const Offset(0, -4))],
            ),
            child: ElevatedButton(
              onPressed: _canAddToCart ? _addToCart : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                disabledBackgroundColor: _kOrange.withOpacity(0.4),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text(
                _canAddToCart
                    ? "Agregar · ${_fmt(_totalPrice)}"
                    : _variantGroups.isNotEmpty &&
                        List.generate(_variantGroups.length, (i) => i).any((i) => !_selectedVGItems.containsKey(i))
                        ? "Selecciona una opción"
                        : "Selecciona los adicionales requeridos",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _imgPh() => Container(
    color: AppColors.secondary,
    child: Center(child: Text(_item?["emoji"] as String? ?? "🍽️",
        style: const TextStyle(fontSize: 72))),
  );

  Widget _section(String title, {required Widget child, bool required = false}) =>
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                    color: _kDark))),
            if (required)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _kOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text("Requerido",
                    style: TextStyle(fontSize: 10, color: _kOrange,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  // Radio group for a single variant_group; cascades subGroups when item is selected
  Widget _variantGroupSection(int gi) {
    final group     = _variantGroups[gi];
    final title     = group["title"] as String? ?? "Opción ${gi + 1}";
    final items     = (group["items"] as List? ?? []).cast<Map<String, dynamic>>();
    final subGroups = (group["subGroups"] as List? ?? []).cast<Map<String, dynamic>>();
    final selIdx    = _selectedVGItems[gi];

    return _section(title, required: true, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(items.length, (itemIdx) {
          final it       = items[itemIdx];
          final selected = selIdx == itemIdx;
          final price    = (it["price"] as num?)?.toInt() ?? 0;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedVGItems[gi] = itemIdx;
              _selectedSubItems.removeWhere((k, _) => k.startsWith("${gi}_"));
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? _kOrange.withOpacity(0.06) : Colors.transparent,
                border: Border.all(
                  color: selected ? _kOrange : AppColors.homeCardBorder,
                  width: selected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? _kOrange : AppColors.textLight, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(it["name"] as String? ?? "",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                        color: selected ? _kOrange : _kDark))),
                Text(_fmt(price), style: TextStyle(
                    color: selected ? _kOrange : AppColors.textLight,
                    fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
          );
        }),
        // Sub-groups cascade once an item is selected
        if (selIdx != null && subGroups.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...List.generate(subGroups.length, (sgi) {
            final sub      = subGroups[sgi];
            final subTitle = sub["title"] as String? ?? "Sub-opción ${sgi + 1}";
            final subItems = (sub["items"] as List? ?? []).cast<Map<String, dynamic>>();
            final subKey   = "${gi}_${selIdx}_$sgi";
            final subSel   = _selectedSubItems[subKey];
            return Container(
              margin: const EdgeInsets.only(top: 4, bottom: 4, left: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.homeCardBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(subTitle,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: _kDark)),
                const SizedBox(height: 8),
                ...List.generate(subItems.length, (subItemIdx) {
                  final sit  = subItems[subItemIdx];
                  final ssel = subSel == subItemIdx;
                  final subP = (sit["price"] as num?)?.toInt() ?? 0;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedSubItems[subKey] = subItemIdx),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Icon(ssel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: ssel ? _kOrange : AppColors.textLight, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(sit["name"] as String? ?? "",
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: ssel ? _kOrange : _kDark))),
                        if (subP > 0)
                          Text("+${_fmt(subP)}", style: TextStyle(
                              color: ssel ? _kOrange : AppColors.textLight,
                              fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                    ),
                  );
                }),
              ]),
            );
          }),
        ],
      ],
    ));
  }

  Widget _variantChip(int idx) {
    final v        = _variants[idx];
    final selected = _selectedVariantIdx == idx;
    final price    = (v["price"] as num?)?.toInt() ?? 0;
    return GestureDetector(
      onTap: () => setState(() => _selectedVariantIdx = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _kOrange.withOpacity(0.08) : Colors.white,
          border: Border.all(
            color: selected ? _kOrange : AppColors.homeCardBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v["name"] as String? ?? "",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                  color: selected ? _kOrange : _kDark)),
          const SizedBox(height: 2),
          Text(_fmt(price),
              style: TextStyle(fontSize: 12,
                  color: selected ? _kOrange : AppColors.textLight,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _optionGroupSection(Map<String, dynamic> group) {
    final title  = group["title"] as String? ?? "Adicionales";
    final minSel = (group["min_sel"] as num?)?.toInt() ?? 0;
    final maxSel = (group["max_sel"] as num?)?.toInt() ?? 0;
    final selected = _selectedExtras.where((k) => k.startsWith("$title::")).length;

    String? hint;
    if (minSel > 0 && maxSel > 0) hint = "Elige entre $minSel y $maxSel";
    else if (minSel > 0)           hint = "Mínimo $minSel";
    else if (maxSel > 0)           hint = "Máximo $maxSel";

    final isRequired = minSel > 0;
    final isSatisfied = !isRequired || selected >= minSel;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kDark)),
            if (hint != null)
              Text(hint, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
          ])),
          if (maxSel > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: selected >= maxSel ? _kOrange.withOpacity(0.12) : AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text("$selected/$maxSel",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: selected >= maxSel ? _kOrange : AppColors.textLight)),
            )
          else if (isRequired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isSatisfied
                    ? AppColors.success.withOpacity(0.12)
                    : _kOrange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(isSatisfied ? "✓ Listo" : "Requerido",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: isSatisfied ? AppColors.success : _kOrange)),
            ),
        ]),
        const SizedBox(height: 10),
        Column(
          children: (group["items"] as List? ?? [])
              .cast<Map<String, dynamic>>()
              .map((it) => _optionTile(group, it))
              .toList(),
        ),
      ]),
    );
  }

  Widget _optionTile(Map<String, dynamic> group, Map<String, dynamic> it) {
    final title  = group["title"] as String? ?? "";
    final key    = "$title::${it["name"]}";
    final price  = (it["price"] as num?)?.toInt() ?? 0;
    final maxSel = (group["max_sel"] as num?)?.toInt() ?? 0;
    final selected = _selectedExtras.where((k) => k.startsWith("$title::")).length;
    final isSelected = _selectedExtras.contains(key);
    final disabled   = maxSel > 0 && !isSelected && selected >= maxSel;

    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeColor: _kOrange,
      checkColor: Colors.white,
      title: Text(it["name"] as String? ?? "",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
              color: disabled ? AppColors.textLight : _kDark)),
      secondary: price > 0
          ? Text(_fmt(price),
              style: TextStyle(color: disabled ? AppColors.textLight : _kOrange, fontWeight: FontWeight.w700))
          : Text("Gratis",
              style: TextStyle(color: disabled ? AppColors.border : AppColors.textLight, fontSize: 12)),
      value: isSelected,
      onChanged: disabled ? null : (v) => setState(() {
        if (v == true) { _selectedExtras.add(key); }
        else           { _selectedExtras.remove(key); }
      }),
    );
  }

  // Rec card navigates to product detail if the item has variants/variant_groups
  Widget _recCard(Map<String, dynamic> item) {
    final imgUrl  = item["image_url"] as String?;
    final price   = (item["price"] as num?)?.toInt() ?? 0;
    final hasVars = _itemHasVariants(item);
    return GestureDetector(
      onTap: () {
        if (hasVars) {
          context.push("/product/${item["id"]}");
        } else {
          if (_store == null) return;
          context.read<CartProvider>().addItem(CartItem(
            id:        item["id"] as String,
            storeId:   _store!["id"] as String,
            storeName: _store!["name"] as String? ?? "",
            name:      item["name"] as String? ?? "",
            emoji:     item["emoji"] as String? ?? "🍽️",
            imageUrl:  imgUrl,
            price:     price,
          ));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("${item["name"]} agregado"),
            backgroundColor: _kOrange,
            duration: const Duration(seconds: 2),
          ));
        }
      },
      child: Container(
        width: 110,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.homeCardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: SizedBox(
              height: 80, width: double.infinity,
              child: imgUrl != null
                  ? Image.network(imgUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _recPh(item))
                  : _recPh(item),
            ),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(item["name"] as String? ?? "",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kDark),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_fmt(price),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                        color: _kOrange)),
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: hasVars ? Colors.transparent : _kOrange,
                    shape: BoxShape.circle,
                    border: hasVars ? Border.all(color: _kOrange) : null,
                  ),
                  child: Icon(hasVars ? Icons.arrow_forward : Icons.add,
                      color: _kOrange, size: hasVars ? 12 : 13),
                ),
              ]),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _recPh(Map<String, dynamic> item) => Container(
    color: _kBg,
    child: Center(child: Text(item["emoji"] as String? ?? "🍽️",
        style: const TextStyle(fontSize: 28))),
  );
}
