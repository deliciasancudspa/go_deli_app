import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";

class RiderProvider extends ChangeNotifier {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _rider;
  bool _isOnline = false;
  bool _loading = false;
  bool _profileLoaded = false;
  List<Map<String, dynamic>> _activeOrders = [];
  List<Map<String, dynamic>> _orderHistory = [];

  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get rider => _rider;
  bool get isOnline => _isOnline;
  bool get loading => _loading;
  // True only after BOTH users and deliverers queries have completed
  bool get profileLoaded => _profileLoaded;
  bool get isLoggedIn => _user != null;
  bool get isApproved => _rider?["status"] == "approved";
  List<Map<String, dynamic>> get activeOrders => _activeOrders;
  List<Map<String, dynamic>> get orderHistory => _orderHistory;
  String get riderName => _user?["name"] ?? "Repartidor";
  String get riderId => _rider?["id"] ?? "";

  RiderProvider() {
    _sb.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        _loadProfile(data.session!.user.id);
      } else {
        _user = null; _rider = null; _isOnline = false;
        _profileLoaded = false;
        _activeOrders = []; _orderHistory = [];
        notifyListeners();
      }
    });
  }

  Future<void> _loadProfile(String authId) async {
    _profileLoaded = false;
    try {
      final user = await _sb.from("users").select().eq("auth_id", authId).single();
      _user = user;
      final rider = await _sb.from("deliverers").select("*, deliverer_bank_info(*)").eq("user_id", user["id"]).maybeSingle();
      _rider = rider;
      if (rider != null) {
        _isOnline = rider["is_online"] ?? false;
        await loadActiveOrders();
        _saveFcmToken(rider["id"] as String);
      }
      notifyListeners();
    } catch (e) {
      notifyListeners();
    } finally {
      _profileLoaded = true;
      notifyListeners();
    }
  }

  // Saves the FCM token to Supabase so the backend can send push notifications
  void _saveFcmToken(String riderId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _sb.from("deliverers").update({"fcm_token": token}).eq("id", riderId);
      // Refresh token if it rotates
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _sb.from("deliverers").update({"fcm_token": newToken}).eq("id", riderId);
      });
    } catch (_) {}
  }

  Future<String?> signIn(String email, String password) async {
    try {
      _loading = true; notifyListeners();
      final res = await _sb.auth.signInWithPassword(email: email, password: password);
      await _loadProfile(res.user!.id);
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<String?> register({required String name, required String email, required String password, required String phone, required String rut, required String vehicle, required String plate, required String bankName, required String accountType, required String accountNumber, required String accountHolder, required String accountRut}) async {
    try {
      _loading = true; notifyListeners();
      final res = await _sb.auth.signUp(email: email, password: password);
      if (res.user == null) throw Exception("Error al crear cuenta");
      final user = await _sb.from("users").insert({"auth_id": res.user!.id, "email": email, "name": name, "phone": phone, "role": "deliverer"}).select().single();
      final rider = await _sb.from("deliverers").insert({"user_id": user["id"], "vehicle_type": vehicle, "vehicle_plate": plate, "status": "pending", "is_online": false, "is_available": false}).select().single();
      await _sb.from("deliverer_bank_info").insert({"deliverer_id": rider["id"], "bank_name": bankName, "account_type": accountType, "account_number": accountNumber, "account_holder": accountHolder, "rut": accountRut});
      _user = user; _rider = rider;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<void> toggleOnline() async {
    if (_rider == null) return;
    final newVal = !_isOnline;
    await _sb.from("deliverers").update({"is_online": newVal, "is_available": newVal}).eq("id", _rider!["id"]);
    _isOnline = newVal;
    notifyListeners();
  }

  Future<void> loadActiveOrders() async {
    if (_rider == null) return;
    try {
      final orders = await _sb.from("orders").select("*, stores(name,emoji,address,phone), users!client_id(name,phone), order_items(item_name,quantity)").eq("deliverer_id", _rider!["id"]).inFilter("status", ["assigned", "picked_up", "on_the_way"]).order("created_at", ascending: false);
      _activeOrders = List<Map<String, dynamic>>.from(orders);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadOrderHistory() async {
    if (_rider == null) return;
    try {
      final orders = await _sb.from("orders").select("*, stores(name,emoji)").eq("deliverer_id", _rider!["id"]).order("created_at", ascending: false).limit(50);
      _orderHistory = List<Map<String, dynamic>>.from(orders);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    await _sb.from("orders").update({"status": status}).eq("id", orderId);
    await loadActiveOrders();
  }

  // Envía la ubicación GPS del repartidor a Supabase
  Future<void> sendLocation(double lat, double lng) async {
    if (_rider == null || riderId.isEmpty) return;
    try {
      await _sb.from("deliverers").update({
        "current_lat": lat,
        "current_lng": lng,
      }).eq("id", riderId);
    } catch (_) {}
  }

  Future<void> reloadProfile() async {
    final authId = _sb.auth.currentUser?.id;
    if (authId != null) await _loadProfile(authId);
  }

  // ── Edición de datos del rider (quedan sujetos a revisión del admin) ──

  Future<String?> updateVehicle(String vehicleType, String plate) async {
    if (_rider == null) return "Perfil no cargado";
    try {
      final cleanPlate = plate.trim().toUpperCase();
      await _sb.from("deliverers").update({
        "vehicle_type": vehicleType,
        "vehicle_plate": cleanPlate.isEmpty ? null : cleanPlate,
      }).eq("id", riderId);
      await _notifyAdminDataChange("vehículo",
          "Tipo: $vehicleType · Patente: ${cleanPlate.isEmpty ? "-" : cleanPlate}");
      await reloadProfile();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> updateBankInfo({
    required String bankName,
    required String accountType,
    required String accountNumber,
    required String accountHolder,
    required String rut,
  }) async {
    if (_rider == null) return "Perfil no cargado";
    try {
      final data = {
        "bank_name": bankName.trim(),
        "account_type": accountType.trim(),
        "account_number": accountNumber.trim(),
        "account_holder": accountHolder.trim(),
        "rut": rut.trim(),
      };
      final existing = await _sb.from("deliverer_bank_info")
          .select("id").eq("deliverer_id", riderId).maybeSingle();
      if (existing != null) {
        await _sb.from("deliverer_bank_info").update(data).eq("id", existing["id"]);
      } else {
        await _sb.from("deliverer_bank_info").insert({...data, "deliverer_id": riderId});
      }
      await _notifyAdminDataChange("datos bancarios",
          "${data["bank_name"]} · ${data["account_type"]} · cta. ${data["account_number"]}");
      await reloadProfile();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // Aviso al admin para que verifique los datos modificados
  Future<void> _notifyAdminDataChange(String what, String detail) async {
    try {
      await _sb.from("notifications").insert({
        "target": "admin",
        "title": "🛵 Rider modificó sus datos",
        "message": "$riderName actualizó sus datos de $what. $detail. Verifica la información en el panel.",
        "type": "rider_data_change",
        "emoji": "🛵",
      });
    } catch (_) {}
  }

  Future<void> signOut() async {
    await _sb.auth.signOut();
    _user = null; _rider = null; _isOnline = false;
    _activeOrders = []; _orderHistory = [];
    notifyListeners();
  }
}
