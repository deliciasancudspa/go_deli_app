import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:image_picker/image_picker.dart";
import "package:geolocator/geolocator.dart";
import "dart:typed_data";
import "dart:math";
import "dart:convert";
import "../../../core/theme/app_theme.dart";
import "../../../core/services/location_service.dart";
import "../../../providers/cart_provider.dart";
import "../../../providers/auth_provider.dart";
import "address_picker_screen.dart";
import "webpay_screen.dart";

// Valores por defecto del fee de delivery. Son configurables desde el panel
// admin (tabla `config`, key `delivery_fees`) y se aplican a toda la plataforma.
// La tarifa base se cobra desde 0 km y suma por cada 0.1 km (100 m).
const _kDefBaseFee   = 1500.0; // tarifa base al rider (desde 0 km)
const _kDefPer100m   = 35.0;   // pesos por cada 0.1 km (100 m)
const _kDefMaxDistKm = 8.0;    // distancia máxima permitida (km)
const _kMaxClient    = 3500.0; // tope que paga el cliente (no configurable aquí)

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _addressCtrl = TextEditingController();
  final _refCtrl     = TextEditingController();
  final _couponCtrl  = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _notesCtrl   = TextEditingController();
  String _deliveryType = "delivery";
  String _payMethod    = "cash";
  double _discount     = 0;
  String _couponCode   = "";
  String? _couponMsg;
  bool _couponValid    = false;
  bool _loading        = false;
  double? _deliveryLat;
  double? _deliveryLng;
  double? _distanceMeters;
  // Parámetros de tarifa de delivery (cargados desde config; defaults abajo)
  double _baseFee  = _kDefBaseFee;
  double _per100m  = _kDefPer100m;
  double _maxDistM = _kDefMaxDistKm * 1000;
  // Tramos de tarifa de servicio (configurables desde admin; defaults abajo)
  Map<String, int> _serviceTiers = {
    "upto3": 0, "upto4": 480, "upto5": 880, "upto6": 990, "upto7": 1250, "upto8": 1490,
  };
  Map<String, dynamic>? _storeData;
  bool _needsPrescription = false;
  Uint8List? _prescriptionBytes;
  String _prescriptionFileName = "";
  final _sb = Supabase.instance.client;
  final _imagePicker = ImagePicker();

  @override
  void initState() { super.initState(); _loadStore(); _loadPhone(); _loadDeliveryConfig(); }

  // Carga los parámetros de tarifa de delivery configurados desde el admin.
  // Si no existen aún, se usan los valores por defecto (base 1500, 35/0.1km, 6km).
  Future<void> _loadDeliveryConfig() async {
    try {
      final row = await _sb.from("config").select("value").eq("key", "delivery_fees").maybeSingle();
      final raw = row?["value"];
      if (raw == null) return;
      final cfg = raw is String ? jsonDecode(raw) : raw;
      if (!mounted) return;
      setState(() {
        _baseFee = (cfg["base_fee"] as num?)?.toDouble() ?? _baseFee;
        _per100m = (cfg["fee_per_100m"] as num?)?.toDouble() ?? _per100m;
        final maxKm = (cfg["max_distance_km"] as num?)?.toDouble();
        if (maxKm != null && maxKm > 0) _maxDistM = maxKm * 1000;
        final sf = cfg["service_fees"];
        if (sf is Map) {
          for (final k in _serviceTiers.keys) {
            final v = (sf[k] as num?)?.toInt();
            if (v != null) _serviceTiers[k] = v;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _loadPhone() async {
    try {
      final user = _sb.auth.currentUser;
      if (user == null) return;
      final u = await _sb.from("users").select("phone").eq("auth_id", user.id).maybeSingle();
      final phone = u?["phone"] as String? ?? "";
      if (phone.isNotEmpty && mounted) _phoneCtrl.text = phone;
    } catch (_) {}
  }

  Future<void> _loadStore() async {
    final cart = context.read<CartProvider>();
    if (cart.currentStoreId == null) return;
    final store = await _sb.from("stores")
        .select("*, lat, lng, delivery_fee_mode, delivery_fee_store, delivery_fee_client")
        .eq("id", cart.currentStoreId!)
        .single();
    // La receta se exige por PRODUCTO (requires_prescription), sin depender
    // del nombre de categoría de la tienda — las farmacias suelen tener
    // categorías múltiples ("Medicamentos,Vitaminas y Suplementos,…").
    bool needsRx = false;
    if (cart.items.isNotEmpty) {
      // los ids del carrito pueden ser compuestos (id__variante)
      final ids = cart.items.map((i) => i.id.split("__").first).toSet().toList();
      final menuItems = await _sb.from("menu_items")
        .select("id, requires_prescription")
        .inFilter("id", ids);
      needsRx = List<Map<String, dynamic>>.from(menuItems)
        .any((m) => m["requires_prescription"] == true);
    }
    if (mounted) setState(() { _storeData = store; _needsPrescription = needsRx; });
    _updateDistance();
  }

  void _updateDistance() {
    if (_deliveryLat == null || _deliveryLng == null || _storeData == null) return;
    final storeLat = (_storeData!["lat"] as num?)?.toDouble();
    final storeLng = (_storeData!["lng"] as num?)?.toDouble();
    if (storeLat == null || storeLng == null) return;
    setState(() {
      _distanceMeters = Geolocator.distanceBetween(storeLat, storeLng, _deliveryLat!, _deliveryLng!);
    });
  }

  double _calcRiderFee(double distMeters) {
    // Tarifa base desde 0 km + monto por cada 0.1 km (100 m) de distancia.
    final units = (distMeters / 100).ceil();
    return _baseFee + units * _per100m;
  }

  ({int client, int rider, int storeAbsorbs, int platform}) _calcAllFees(double distMeters) {
    final rider        = _calcRiderFee(distMeters).toInt();
    final clientRaw    = (_storeData?["delivery_fee_client"] as num?)?.toDouble() ?? 0;
    final client       = min(clientRaw, _kMaxClient).toInt();
    final storeAbsorbs = ((_storeData?["delivery_fee_store"] as num?)?.toDouble() ?? 0).toInt();
    final platform     = max(0.0, rider - (storeAbsorbs + client)).toInt();
    return (client: client, rider: rider, storeAbsorbs: storeAbsorbs, platform: platform);
  }

  // Tarifa de servicio Go Deli por tramos de distancia (interna: el cliente y
  // el rider la ven en el total, pero el aliado NO la ve en su ticket/reportes).
  //   0–3 km: $0 · 3–4: $480 · 4–5: $880 · 5–6: $990 · 6–7: $1250 · 7–8: $1490
  int _calcServiceFee(double distMeters) {
    final km = distMeters / 1000;
    if (km <= 3) return _serviceTiers["upto3"]!;
    if (km <= 4) return _serviceTiers["upto4"]!;
    if (km <= 5) return _serviceTiers["upto5"]!;
    if (km <= 6) return _serviceTiers["upto6"]!;
    if (km <= 7) return _serviceTiers["upto7"]!;
    return _serviceTiers["upto8"]!; // 7–8 km
  }

  String _generateCode() => (1000 + Random().nextInt(9000)).toString();

  String _fmt(num p) => "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  bool get _allowPickup => _storeData?["allow_pickup"] == true;

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    try {
      // Consultar cupón en la base de datos
      final res = await _sb.from("coupons").select("*")
          .eq("code", code).eq("is_active", true).maybeSingle();
      if (res == null) {
        setState(() { _discount = 0; _couponCode = ""; _couponValid = false; _couponMsg = "❌ Cupón no válido"; });
        return;
      }
      // Validar vigencia
      if (res["expires_at"] != null) {
        final exp = DateTime.tryParse(res["expires_at"] as String);
        if (exp != null && exp.isBefore(DateTime.now())) {
          setState(() { _discount = 0; _couponCode = ""; _couponValid = false; _couponMsg = "❌ Cupón expirado"; });
          return;
        }
      }
      // Validar uso máximo
      final maxUses = res["max_uses"] as int?;
      final curUses = res["current_uses"] as int?;
      if (maxUses != null && curUses != null && curUses >= maxUses) {
        setState(() { _discount = 0; _couponCode = ""; _couponValid = false; _couponMsg = "❌ Cupón agotado"; });
        return;
      }
      final pct = (res["discount_percent"] as num?)?.toDouble() ?? 0;
      if (pct <= 0) {
        setState(() { _discount = 0; _couponCode = ""; _couponValid = false; _couponMsg = "❌ Cupón no válido"; });
        return;
      }
      setState(() {
        _discount = pct / 100;
        _couponCode = code;
        _couponValid = true;
        _couponMsg = "✅ ${pct.toStringAsFixed(0)}% de descuento aplicado";
      });
    } catch (_) {
      setState(() { _discount = 0; _couponCode = ""; _couponValid = false; _couponMsg = "❌ Error al validar cupón"; });
    }
  }

  Future<void> _pickPrescription(ImageSource source) async {
    try {
      final xfile = await _imagePicker.pickImage(source: source, imageQuality: 85, maxWidth: 1920);
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      setState(() {
        _prescriptionBytes = bytes;
        _prescriptionFileName = xfile.name;
      });
    } catch (_) {}
  }

  Future<void> _placeOrder() async {
    if (_deliveryType == "delivery" && _addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingresa tu dirección de entrega"), backgroundColor: AppColors.error));
      return;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingresa tu número de teléfono de contacto"), backgroundColor: AppColors.error));
      return;
    }
    if (_needsPrescription && _prescriptionBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Debes subir la receta médica para continuar"), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _loading = true);
    try {
      final cart   = context.read<CartProvider>();
      final auth   = context.read<AuthProvider>();
      final phone      = _phoneCtrl.text.trim();
      final subtotal   = cart.subtotal;
      final discAmt    = (subtotal * _discount).round();
      final finalSub   = subtotal - discAmt;
      final platformFee = (finalSub * ((_storeData?["commission_pct"] ?? 7) as num) / 100).round();
      final fixedFee   = (_storeData?["fixed_fee"] ?? 3000) as num;
      int delivFee = 0, riderFee = 0, storeDelivFee = 0, platformDelivFee = 0, serviceFee = 0;
      if (_deliveryType == "delivery") {
        final dist = _distanceMeters ?? 0.0;
        final fees = _calcAllFees(dist);
        delivFee       = fees.client;
        riderFee       = fees.rider;
        storeDelivFee  = fees.storeAbsorbs;
        platformDelivFee = fees.platform;
        serviceFee     = _calcServiceFee(dist);
      }
      // El total (lo que paga el cliente y cobra el rider) incluye la tarifa de
      // servicio. El aliado NO la ve: su total = finalSub + delivFee.
      final total = finalSub + delivFee + serviceFee;
      // retiro: cliente muestra pickup_code a la tienda
      // delivery: delivery_code lo da el cliente al rider; pickup_code lo genera el sistema al asignar rider
      final pickupCode = _deliveryType == "pickup" ? _generateCode() : null;
      final delivCode  = _deliveryType == "delivery" ? _generateCode() : null;

      final u = await _sb.from("users").select("id,phone").eq("auth_id", auth.user!.id).single();

      // Save phone to user profile if it was new
      if ((u["phone"] as String? ?? "").isEmpty && phone.isNotEmpty) {
        await _sb.from("users").update({"phone": phone}).eq("id", u["id"]);
      }

      String? prescriptionUrl;
      if (_prescriptionBytes != null) {
        final ext = _prescriptionFileName.contains(".") ? _prescriptionFileName.split(".").last : "jpg";
        final path = "${u["id"]}/${DateTime.now().millisecondsSinceEpoch}.$ext";
        await _sb.storage.from("prescriptions").uploadBinary(path, _prescriptionBytes!,
          fileOptions: FileOptions(contentType: "image/$ext", upsert: false));
        prescriptionUrl = _sb.storage.from("prescriptions").getPublicUrl(path);
      }

      // Obtener commune_id de SharedPreferences, con fallback al de la tienda
      final savedCommune = await LocationService.loadSavedCommune();
      var communeId = savedCommune?['commune_id'];
      if (communeId == null && cart.currentStoreId != null) {
        // Fallback: usar el commune_id de la tienda
        final store = await _sb.from("stores").select("commune_id")
            .eq("id", cart.currentStoreId!).maybeSingle();
        communeId = store?['commune_id'] as String?;
      }

      final order = await _sb.from("orders").insert({
        "client_id": u["id"],
        "store_id": cart.currentStoreId,
        "commune_id": communeId,
        "subtotal": finalSub,
        "delivery_fee": delivFee,
        "rider_fee": riderFee > 0 ? riderFee : null,
        "store_delivery_fee": storeDelivFee > 0 ? storeDelivFee : null,
        "platform_delivery_fee": platformDelivFee > 0 ? platformDelivFee : null,
        "delivery_distance": _distanceMeters != null ? _distanceMeters!.round() : null,
        "platform_fee": platformFee,
        "fixed_fee": fixedFee,
        "service_fee": serviceFee,
        "total": total,
        "delivery_address": _deliveryType == "delivery" ? _addressCtrl.text.trim() : null,
        "delivery_lat": _deliveryType == "delivery" ? _deliveryLat : null,
        "delivery_lng": _deliveryType == "delivery" ? _deliveryLng : null,
        "delivery_reference": _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        "payment_method": _payMethod,
        "order_type": _deliveryType,
        "status": "pending",
        "coupon_code": _couponCode.isEmpty ? null : _couponCode,
        "discount": discAmt,
        "pickup_code": pickupCode,
        "delivery_code": delivCode,
        "prescription_url": prescriptionUrl,
        "contact_phone": phone,
        "notes": _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      }).select().single();

      await _sb.from("order_items").insert(cart.items.map((item) => {
        "order_id": order["id"],
        "menu_item_id": item.id,
        "item_name": item.name,
        "item_price": item.price,
        "quantity": item.quantity,
        "subtotal": item.price * item.quantity,
      }).toList());

      if (_payMethod == "webpay") {
        await _launchWebpay(order["id"] as String);
      } else if (_payMethod == "khipu") {
        await _launchKhipu(order["id"] as String);
      } else {
        cart.clearCart();
        if (mounted) context.go("/order-success/${order["id"]}");
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _launchWebpay(String orderId) async {
    try {
      final res = await _sb.functions.invoke("webpay-create", body: {"order_id": orderId});
      if (res.data == null || res.data["token"] == null) {
        throw Exception(res.data?["error"] ?? "Error al iniciar WebPay");
      }
      final token = res.data["token"] as String;
      final url   = res.data["url"]   as String;

      if (!mounted) return;
      final cart = context.read<CartProvider>();
      // Navegar al WebView; el carrito se limpia solo si el pago es aprobado
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebpayScreen(
          webpayUrl:   url,
          webpayToken: token,
          orderId:     orderId,
        ),
      ));
      // El carrito se limpia dentro de WebpayScreen solo si el pago es aprobado
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error WebPay: $e"), backgroundColor: AppColors.error));
    }
  }

  Future<void> _launchKhipu(String orderId) async {
    try {
      final res = await _sb.functions.invoke("khipu-create", body: {"order_id": orderId});
      if (res.data == null || res.data["payment_url"] == null) {
        throw Exception(res.data?["error"] ?? "Error al iniciar Khipu");
      }
      final url = res.data["payment_url"] as String;

      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WebpayScreen(
          webpayUrl:   url,
          webpayToken: "",   // Khipu no usa token en la URL — ya viene incluido en payment_url
          orderId:     orderId,
        ),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error Khipu: $e"), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final subtotal  = cart.subtotal;
    final discAmt   = (subtotal * _discount).round();
    final finalSub  = subtotal - discAmt;
    final bool outOfRange = _deliveryType == "delivery" && _distanceMeters != null && _distanceMeters! > _maxDistM;
    int delivFee = 0;
    int serviceFee = 0;
    String? delivLabel;
    if (_deliveryType == "delivery") {
      if (_distanceMeters != null) {
        delivFee  = _calcAllFees(_distanceMeters!).client;
        serviceFee = _calcServiceFee(_distanceMeters!);
        delivLabel = "🛵 Envío";
      } else {
        final clientFee = (_storeData?["delivery_fee_client"] as num?)?.toInt() ?? 0;
        delivFee  = min(clientFee, _kMaxClient.toInt());
        delivLabel = "🛵 Envío";
      }
    }
    final total = finalSub + delivFee + serviceFee;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Confirmar pedido"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Tipo de entrega
        const Text("Tipo de entrega", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _typeBtn("delivery", "🛵 Delivery", "Entrega a domicilio")),
          const SizedBox(width: 12),
          if (_allowPickup) Expanded(child: _typeBtn("pickup", "🏪 Retiro", "Retira en tienda")),
        ]),
        const SizedBox(height: 20),

        // Direccion (solo delivery)
        if (_deliveryType == "delivery") ...[
          const Text("Dirección de entrega", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (_) => const AddressPickerScreen()));
              if (result != null && (result["address"] as String).isNotEmpty) {
                setState(() {
                  _addressCtrl.text = result["address"] as String;
                  _deliveryLat = result["lat"] as double?;
                  _deliveryLng = result["lng"] as double?;
                });
                _updateDistance();
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _addressCtrl.text.isEmpty ? AppColors.border : AppColors.primary,
                  width: _addressCtrl.text.isEmpty ? 1 : 2,
                ),
              ),
              child: Row(children: [
                Icon(
                  _addressCtrl.text.isEmpty ? Icons.add_location_alt_outlined : Icons.location_on,
                  color: _addressCtrl.text.isEmpty ? AppColors.textLight : AppColors.accent,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _addressCtrl.text.isEmpty
                    ? const Text("Toca para seleccionar tu dirección", style: TextStyle(color: AppColors.textLight, fontSize: 14))
                    : Text(_addressCtrl.text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                Icon(
                  Icons.map_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _refCtrl,
            decoration: const InputDecoration(hintText: "Referencia (opcional): depto, piso, portón color...", prefixIcon: Icon(Icons.info_outline, color: AppColors.accent)),
          ),
          const SizedBox(height: 20),
        ],

        // Metodo de pago
        const Text("Método de pago", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (_deliveryType == "pickup")
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withOpacity(0.3))),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppColors.accent, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text("El retiro en tienda requiere pago con tarjeta o transferencia", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 13))),
            ]),
          )
        else
          _payMethodCard("cash", "💵", "Efectivo", "Paga al recibir"),
        const SizedBox(height: 8),
        _payMethodCard("webpay", "💳", "WebPay", "Débito o crédito online"),
        const SizedBox(height: 8),
        _payMethodCard("khipu", "🏦", "Transferencia", "Desde tu banco — Khipu"),
        const SizedBox(height: 20),

        // Cupon
        const Text("Cupón de descuento", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(
            controller: _couponCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: "Ej: BIENVENIDO", prefixIcon: Icon(Icons.local_offer_outlined, color: AppColors.accent)),
          )),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _applyCoupon,
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 52)),
            child: const Text("Aplicar"),
          ),
        ]),
        if (_couponMsg != null) ...[
          const SizedBox(height: 8),
          Text(_couponMsg!, style: TextStyle(color: _couponValid ? AppColors.success : AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 20),

        // Teléfono de contacto
        const Text("📱 Teléfono de contacto", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text("Obligatorio *", style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: "+56 9 XXXX XXXX",
            prefixIcon: Icon(Icons.phone_outlined, color: AppColors.accent),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "El repartidor y la tienda usarán este número para contactarte si es necesario",
          style: TextStyle(fontSize: 11, color: AppColors.textLight, height: 1.4),
        ),
        const SizedBox(height: 20),

        // Notas del pedido
        const Text("📝 Notas del pedido", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text("Opcional", style: TextStyle(fontSize: 12, color: AppColors.textLight)),
        const SizedBox(height: 10),
        TextFormField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: "Sin picante, sin cebolla, toca el portón... (opcional)",
            prefixIcon: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.notes_outlined, color: AppColors.accent)),
          ),
        ),
        const SizedBox(height: 20),

        // Resumen
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            ...cart.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text("${item.quantity}x ${item.name}", style: const TextStyle(fontSize: 13))),
                Text(_fmt(item.price * item.quantity), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            )),
            const Divider(),
            _summaryRow("Subtotal", _fmt(subtotal)),
            if (discAmt > 0) _summaryRow("Descuento", "-${_fmt(discAmt)}", color: AppColors.success),
            if (_deliveryType == "delivery")
              _summaryRow(
                delivLabel ?? "🛵 Envío",
                outOfRange ? "Fuera de cobertura" : delivFee == 0 ? "Gratis" : _fmt(delivFee),
                color: outOfRange ? AppColors.error : delivFee == 0 ? AppColors.success : null,
              ),
            if (_deliveryType == "delivery" && !outOfRange && serviceFee > 0)
              _summaryRow("Tarifa de servicio", _fmt(serviceFee)),
            const Divider(thickness: 2),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Total", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              Text(_fmt(total), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.accent)),
            ]),
          ]),
        ),
        // Receta médica (solo farmacias con productos que lo requieren)
        if (_needsPrescription) ...[
          const SizedBox(height: 20),
          const Text("Receta médica", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.warning.withOpacity(0.4))),
            child: Row(children: [
              const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text("Este pedido incluye productos que requieren receta médica.", style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 12),
          if (_prescriptionBytes != null) ...[
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.success, width: 2),
                image: DecorationImage(image: MemoryImage(_prescriptionBytes!), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(_prescriptionFileName, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: () => setState(() { _prescriptionBytes = null; _prescriptionFileName = ""; }), child: const Text("Cambiar")),
            ]),
          ] else ...[
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _pickPrescription(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text("Tomar foto"),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent, side: const BorderSide(color: AppColors.accent)),
              )),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _pickPrescription(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text("Galería"),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent, side: const BorderSide(color: AppColors.accent)),
              )),
            ]),
          ],
        ],

        const SizedBox(height: 24),

        if (outOfRange)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withOpacity(0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text("Dirección fuera de cobertura (máx. 8 km desde la tienda)", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13))),
            ]),
          ),

        ElevatedButton(
          onPressed: (_loading || outOfRange) ? null : _placeOrder,
          child: _loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text("Confirmar pedido · ${_fmt(total)}"),
        ),
        const SizedBox(height: 32),
      ])),
    );
  }

  Widget _typeBtn(String type, String label, String sub) {
    final selected = _deliveryType == type;
    return GestureDetector(
      onTap: () => setState(() {
        _deliveryType = type;
        if (type == "pickup") _payMethod = "card";
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Column(children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: selected ? AppColors.primary : AppColors.textDark)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
        ]),
      ),
    );
  }

  Widget _payMethodCard(String method, String emoji, String label, String sub) {
    final selected = _payMethod == method;
    final disabled = _deliveryType == "pickup" && method == "cash";
    return GestureDetector(
      onTap: disabled ? null : () => setState(() => _payMethod = method),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: disabled ? AppColors.background : selected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected && !disabled ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: disabled ? AppColors.textLight : AppColors.textDark)),
            Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
          ]),
          const Spacer(),
          if (selected && !disabled) const Icon(Icons.check_circle, color: AppColors.accent),
        ]),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textMedium)),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color ?? AppColors.textDark)),
    ]),
  );
}
