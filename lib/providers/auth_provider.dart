import "dart:async";
import "dart:io" show Platform;
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "package:google_sign_in/google_sign_in.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../core/utils/auth_error_translator.dart";
import "../services/notification_service.dart";

class AuthProvider extends ChangeNotifier {
  final _sb = Supabase.instance.client;
  User? _user;
  Map<String, dynamic>? _profile;
  bool _loading = false;
  bool _needsPasswordReset = false;
  StreamSubscription<String>? _fcmTokenSub; // para cancelar en signOut

  User? get user => _user;
  Map<String, dynamic>? get profile => _profile;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;
  bool get needsPasswordReset => _needsPasswordReset;

  StreamSubscription? _authSub;

  AuthProvider() {
    _authSub = _sb.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      if (_user != null) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          // El usuario hizo clic en un enlace de recuperacion de contrasena.
          // Mostrar la pantalla de nueva contrasena en vez de cargar perfil.
          _needsPasswordReset = true;
          notifyListeners();
          return;
        }
        loadProfile();
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _fcmTokenSub?.cancel();
    super.dispose();
  }

  Future<void> loadProfile() async {
    try {
      final res = await _sb.from("users").select().eq("auth_id", _user!.id).maybeSingle();
      _profile = res;
      notifyListeners();
      if (res != null && res["id"] != null) {
        NotificationService().startOrderListener(res["id"] as String);
        NotificationService().startChatListener(res["id"] as String);
        _saveFcmToken(res["id"] as String);
      }
    } catch (e) {
      debugPrint('loadProfile error: $e');
    }
  }

  void _saveFcmToken(String userId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _sb.from("users").update({"fcm_token": token}).eq("id", userId);
      // Guardamos el stream subscription para cancelarlo en signOut
      await _fcmTokenSub?.cancel();
      _fcmTokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _sb.from("users").update({"fcm_token": newToken}).eq("id", userId);
      });
    } catch (_) {}
  }

  Future<String?> signIn(String email, String password) async {
    if (_loading) return null; // Prevent double-tap
    try {
      _loading = true; notifyListeners();
      await _sb.auth.signInWithPassword(email: email, password: password);
      return null;
    } on AuthApiException catch (e) {
      return translateAuthError(e);
    } catch (e) {
      return translateAuthError(e);
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String nationality,
    required String nationalId,
    required String nationalIdType,
    required String region,
    required String city,
  }) async {
    try {
      _loading = true; notifyListeners();

      // Uniqueness check before creating auth user
      final existing = await _sb.from("users").select("id")
          .eq("national_id", nationalId)
          .limit(1)
          .maybeSingle();
      if (existing != null) return "duplicate_national_id";

      final res = await _sb.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: "https://godeli.cl/godeli-confirm",
        data: {
          "name": name,
          "phone": phone,
          "nationality": nationality,
          "national_id": nationalId,
          "national_id_type": nationalIdType,
          "region": region,
          "city": city,
          "role": "client",
        },
      );
      if (res.user != null) {
        if (res.session == null) {
          // Email sin confirmar: el trigger BD creará el perfil automáticamente
          return "revisa_tu_correo";
        }
        try {
          await _sb.from("users").insert({
            "auth_id": res.user!.id,
            "email": email,
            "name": name,
            "phone": phone,
            "nationality": nationality,
            "national_id": nationalId,
            "national_id_type": nationalIdType,
            "region": region,
            "city": city,
            "role": "client",
          });
        } catch (profileError) {
          // Si falla el INSERT (RLS, concurrencia con trigger, etc.), el
          // trigger handle_new_auth_user() lo crea. No hacemos rollback.
        }
      }
      return null;
    } on AuthApiException catch (e) {
      return translateAuthError(e);
    } catch (e) {
      return translateAuthError(e);
    } finally {
      _loading = false; notifyListeners();
    }
  }

  // Returns: null = existing user (go home), "needs_profile_completion" = new user,
  //          "cancelled" = user cancelled, other string = error
  Future<String?> signInWithGoogle() async {
    try {
      _loading = true; notifyListeners();
      // Android: sin clientId explícito — el plugin usa el de google-services.json.
      // Solo se pasa serverClientId (Web Client ID) para obtener idToken → Supabase.
      // iOS: requiere clientId explícito + serverClientId.
      const webClientId = '453209088911-kl6ktv1lo8tiug32g9rfj9rbfhkpen6s.apps.googleusercontent.com';
      const iosClientId = '453209088911-j7jbj8i4hs3mhiumhp6279412gj7sgu6.apps.googleusercontent.com';
      final googleSignIn = Platform.isIOS
          ? GoogleSignIn(clientId: iosClientId, serverClientId: webClientId)
          : GoogleSignIn(serverClientId: webClientId);
      final account = await googleSignIn.signIn();
      if (account == null) return "cancelled";

      final auth = await account.authentication;
      if (auth.idToken == null) return "No se pudo obtener el token de Google";

      final res = await _sb.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: auth.idToken!,
        accessToken: auth.accessToken,
      );

      if (res.user == null) return "Error al autenticar con Google";

      _user = res.user;
      final existing = await _sb.from("users").select("id")
          .eq("auth_id", res.user!.id)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        await loadProfile();
        return null; // already has profile → go home
      }
      return "needs_profile_completion";
    } catch (e) {
      return translateAuthError(e);
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<String?> completeGoogleProfile({
    required String phone,
    required String nationality,
    required String nationalId,
    required String nationalIdType,
    required String region,
    required String city,
  }) async {
    try {
      _loading = true; notifyListeners();
      if (_user == null) return "No hay sesión activa";

      final existing = await _sb.from("users").select("id")
          .eq("national_id", nationalId)
          .limit(1)
          .maybeSingle();
      if (existing != null) return "duplicate_national_id";

      final meta = _user!.userMetadata;
      final name = (meta?["full_name"] ?? meta?["name"] ?? "").toString();
      final email = _user!.email ?? "";

      try {
        await _sb.from("users").insert({
          "auth_id": _user!.id,
          "email": email,
          "name": name,
          "phone": phone,
          "nationality": nationality,
          "national_id": nationalId,
          "national_id_type": nationalIdType,
          "region": region,
          "city": city,
          "role": "client",
        });
      } catch (profileError) {
        await _sb.auth.signOut();
        _user = null;
        return "Error al crear perfil. Intenta de nuevo.";
      }
      await loadProfile();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<void> signOut() async {
    NotificationService().stopOrderListener();
    NotificationService().stopChatListener();
    await _fcmTokenSub?.cancel();
    _fcmTokenSub = null;
    await _sb.auth.signOut();
    _user = null;
    _profile = null;
    _needsPasswordReset = false;
    notifyListeners();
  }

  /// Envia el correo de recuperacion de contrasena.
  /// [redirectTo] permite especificar a que URL redirigir tras hacer clic
  /// en el enlace (ej. 'https://godeli.cl/aliados').
  Future<String?> resetPasswordForEmail(String email, {String? redirectTo}) async {
    try {
      _loading = true; notifyListeners();
      await _sb.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectTo,
      );
      return null;
    } catch (e) {
      return translateAuthError(e);
    } finally {
      _loading = false; notifyListeners();
    }
  }

  /// Cambia la contrasena del usuario actual (requiere sesion activa,
  /// tipicamente tras un enlace de recuperacion).
  Future<String?> updatePassword(String newPassword) async {
    try {
      _loading = true; notifyListeners();
      await _sb.auth.updateUser(UserAttributes(password: newPassword));
      _needsPasswordReset = false;
      await loadProfile();
      return null;
    } catch (e) {
      return translateAuthError(e);
    } finally {
      _loading = false; notifyListeners();
    }
  }

  /// Limpia el flag de recuperacion sin cambiar contrasena.
  void clearPasswordReset() {
    _needsPasswordReset = false;
    notifyListeners();
  }
}
