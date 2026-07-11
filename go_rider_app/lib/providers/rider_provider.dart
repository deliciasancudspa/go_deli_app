import "dart:async";
import "dart:convert";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:http/http.dart" as http;
import "../config/app_config.dart";

class RiderProvider extends ChangeNotifier {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _rider;
  bool _isOnline = false;
  bool _loading = false;
  bool _profileLoaded = false;
  List<Map<String, dynamic>> _activeOrders = [];
  StreamSubscription<String>? _fcmTokenSub;
  List<Map<String, dynamic>> _orderHistory = [];
  DateTime? _lastCommuneUpdate;

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
      // Cancelar suscripción anterior y guardar la nueva
      await _fcmTokenSub?.cancel();
      _fcmTokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _sb.from("deliverers").update({"fcm_token": newToken}).eq("id", riderId);
      });
    } catch (_) {}
  }

  Future<String?> signIn(String email, String password) async {
    try {
      _loading = true; notifyListeners();
      // Mismo sufijo +gorider que en register — transparente para el usuario
      final riderEmail = email.replaceFirst("@", "+gorider@");
      final res = await _sb.auth.signInWithPassword(email: riderEmail, password: password);
      await _loadProfile(res.user!.id);
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<String?> register({required String name, required String email, required String password, required String phone, required String rut, required String vehicle, required String plate, required String bankName, required String accountType, required String accountNumber, required String accountHolder, required String accountRut, String? communeId, String? signerName, String? signerRut, String? signatureImage}) async {
    String? authUid;
    try {
      _loading = true; notifyListeners();

      // Si el usuario ya está autenticado (confirmó su email y volvió),
      // solo falta crear su perfil de repartidor — no hacer signUp de nuevo.
      final session = _sb.auth.currentSession;
      if (session != null) {
        return await _completeRiderProfile(
          authUid: session.user.id,
          name: name, email: email, phone: phone, rut: rut,
          vehicle: vehicle, plate: plate, bankName: bankName,
          accountType: accountType, accountNumber: accountNumber,
          accountHolder: accountHolder, accountRut: accountRut,
          communeId: communeId, signerName: signerName,
          signerRut: signerRut, signatureImage: signatureImage,
        );
      }

      // Sufijo +gorider: separa el auth de GoDeli. ana@gmail.com y
      // ana+gorider@gmail.com son usuarios distintos en Supabase Auth,
      // pero los correos llegan al mismo inbox (Gmail, Outlook, Yahoo, etc.)
      final riderEmail = email.replaceFirst("@", "+gorider@");
      final res = await _sb.auth.signUp(
        email: riderEmail,
        password: password,
        data: {
          "name": name,
          "phone": phone,
          "role": "deliverer",
        },
      );
      if (res.user == null) throw Exception("Error al crear cuenta");
      authUid = res.user!.id;

      // Si no hay sesión (email sin confirmar), el trigger BD crea el perfil.
      // El repartidor deberá confirmar su email y luego iniciar sesión.
      if (res.session == null) {
        return "revisa_tu_correo";
      }

      final user = await _sb.from("users").insert({"auth_id": authUid, "email": email, "name": name, "phone": phone, "role": "deliverer"}).select().single();
      Map<String, dynamic> rider;
      try {
        rider = await _sb.from("deliverers").insert({"user_id": user["id"], "vehicle_type": vehicle, "vehicle_plate": plate, "status": "pending", "is_online": false, "is_available": false, "commune_id": communeId}).select().single();
        await _sb.from("deliverer_bank_info").insert({"deliverer_id": rider["id"], "bank_name": bankName, "account_type": accountType, "account_number": accountNumber, "account_holder": accountHolder, "rut": accountRut});
      } catch (insertError) {
        // Rollback: borrar usuario y auth user si falla inserción de rider/bank
        await _sb.from("users").delete().eq("id", user["id"]);
        try {
          await _sb.functions.invoke('admin-delete-user', body: {'user_id': authUid});
        } catch (_) {}
        throw Exception("Error al crear perfil de repartidor. Intenta de nuevo.");
      }

      // ── Guardar contrato y consentimientos en notificación admin ──
      final signedAt = DateTime.now().toIso8601String();
      try {
        await _sb.from("notifications").insert({
          "type": "alert", "emoji": "🛵", "target": "admin", "is_read": false,
          "title": "🛵 Nuevo repartidor registrado",
          "message": "$name · $vehicle · $email",
          "data": {
            "name": name, "rut": rut, "phone": phone, "email": email,
            "vehicle": vehicle, "plate": plate,
            "contract_accepted": true,
            "privacy_accepted": true,
            "geolocation_authorized": true,
            "accepted_at": signedAt,
            "contract_version": "1.0",
            "signer_name": signerName,
            "signer_rut": signerRut,
            "signed_at": signedAt,
            "signature_image": signatureImage,
          }
        });
      } catch (_) { /* non-blocking */ }

      _user = user; _rider = rider;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  /// Completa el perfil de repartidor para un usuario que ya confirmó su email.
  /// Solo se usa cuando el auth ya existe (sesión activa) pero falta la fila en deliverers.
  Future<String?> _completeRiderProfile({
    required String authUid,
    required String name, required String email, required String phone,
    required String rut, required String vehicle, required String plate,
    required String bankName, required String accountType,
    required String accountNumber, required String accountHolder,
    required String accountRut, String? communeId,
    String? signerName, String? signerRut, String? signatureImage,
  }) async {
    try {
      // Buscar o crear la fila en users
      var user = await _sb.from("users").select().eq("auth_id", authUid).maybeSingle();
      user ??= await _sb.from("users").insert({
        "auth_id": authUid, "email": email, "name": name,
        "phone": phone, "role": "deliverer",
      }).select().single();

      // Verificar que no exista ya un deliverer
      final existingRider = await _sb.from("deliverers").select().eq("user_id", user["id"]).maybeSingle();
      if (existingRider != null) {
        await _loadProfile(authUid);
        return null; // Ya tiene perfil, cargar y seguir
      }

      // Crear perfil de repartidor
      final rider = await _sb.from("deliverers").insert({
        "user_id": user["id"],
        "vehicle_type": vehicle,
        "vehicle_plate": plate,
        "status": "pending",
        "is_online": false,
        "is_available": false,
        "commune_id": communeId,
      }).select().single();
      await _sb.from("deliverer_bank_info").insert({
        "deliverer_id": rider["id"],
        "bank_name": bankName, "account_type": accountType,
        "account_number": accountNumber, "account_holder": accountHolder,
        "rut": accountRut,
      });

      // Notificar al admin
      final signedAt = DateTime.now().toIso8601String();
      try {
        await _sb.from("notifications").insert({
          "type": "alert", "emoji": "🛵", "target": "admin", "is_read": false,
          "title": "🛵 Nuevo repartidor (confirmó email)",
          "message": "$name · $vehicle · $email",
          "data": {
            "name": name, "rut": rut, "phone": phone, "email": email,
            "vehicle": vehicle, "plate": plate,
            "contract_accepted": true,
            "privacy_accepted": true,
            "geolocation_authorized": true,
            "accepted_at": signedAt,
            "contract_version": "1.0",
            "signer_name": signerName,
            "signer_rut": signerRut,
            "signed_at": signedAt,
            "signature_image": signatureImage,
            "post_confirmation": true,
          }
        });
      } catch (_) { /* non-blocking */ }

      await _loadProfile(authUid);
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
      final orders = await _sb.from("orders").select("*, stores(name,emoji,logo_url,address,phone), users!client_id(name,phone), order_items(item_name,quantity)").eq("deliverer_id", _rider!["id"]).inFilter("status", ["assigned", "picked_up", "on_the_way"]).order("created_at", ascending: false);
      _activeOrders = List<Map<String, dynamic>>.from(orders);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadOrderHistory() async {
    if (_rider == null) return;
    try {
      final orders = await _sb.from("orders").select("*, stores(name,emoji,logo_url)").eq("deliverer_id", _rider!["id"]).order("created_at", ascending: false).limit(50);
      _orderHistory = List<Map<String, dynamic>>.from(orders);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    await _sb.from("orders").update({"status": status}).eq("id", orderId);
    await loadActiveOrders();
  }

  // Envía la ubicación GPS del repartidor a Supabase.
  // Además detecta y actualiza la comuna cada vez que la ubicación cambia
  // significativamente (para mantener commune_id actualizado en el despacho).
  Future<void> sendLocation(double lat, double lng) async {
    if (_rider == null || riderId.isEmpty) return;
    try {
      await _sb.from("deliverers").update({
        "current_lat": lat,
        "current_lng": lng,
      }).eq("id", riderId);

      // Detectar comuna si el rider aún no tiene una o cambió su ubicación
      await _maybeUpdateCommune(lat, lng);
    } catch (_) {}
  }

  /// Detecta la comuna desde coordenadas y actualiza el registro del rider
  /// si la comuna cambió o no está seteada.
  Future<void> _maybeUpdateCommune(double lat, double lng) async {
    try {
      // Solo actualizar si han pasado al menos 5 min desde la última detección
      // o si el rider no tiene commune_id
      final currentCommuneId = _rider?['commune_id'] as String?;
      if (currentCommuneId != null && _lastCommuneUpdate != null) {
        if (DateTime.now().difference(_lastCommuneUpdate!).inMinutes < 5) return;
      }

      // Usar Google Geocoding API para obtener la comuna
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
        '&key=${AppConfig.googleMapsApiKey}'
        '&language=es',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;

      final data = jsonDecode(resp.body);
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return;

      String? communeName;
      String? regionName;
      for (final r in results.cast<Map<String, dynamic>>()) {
        final components = r['address_components'] as List? ?? [];
        for (final comp in components.cast<Map<String, dynamic>>()) {
          final types = List<String>.from(comp['types'] ?? []);
          final longName = comp['long_name'] as String? ?? '';
          if (types.contains('administrative_area_level_3') && communeName == null) {
            communeName = longName;
          }
          if (types.contains('administrative_area_level_2') && regionName == null) {
            regionName = longName;
          }
        }
        if (communeName != null) break;
      }
      if (communeName == null) return;

      // Buscar la comuna en nuestra BD
      final communeResult = await _sb.rpc('find_commune', params: {
        'p_name': communeName,
        'p_region': regionName,
      });
      final newCommuneId = communeResult as String?;
      if (newCommuneId == null || newCommuneId.isEmpty) return;
      if (newCommuneId == currentCommuneId) return; // no cambió

      // Actualizar la BD y la caché local
      await _sb.from("deliverers").update({
        "commune_id": newCommuneId,
      }).eq("id", riderId);

      _rider!['commune_id'] = newCommuneId;
      _lastCommuneUpdate = DateTime.now();
      notifyListeners();
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

  @override
  void dispose() {
    _fcmTokenSub?.cancel();
    super.dispose();
  }

  Future<void> signOut() async {
    await _fcmTokenSub?.cancel();
    _fcmTokenSub = null;
    await _sb.auth.signOut();
    _user = null; _rider = null; _isOnline = false;
    _activeOrders = []; _orderHistory = [];
    notifyListeners();
  }
}
