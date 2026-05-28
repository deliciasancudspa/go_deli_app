import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProvider extends ChangeNotifier {
  final _sb = Supabase.instance.client;
  User? _user;
  Map<String, dynamic>? _profile;
  bool _loading = false;
  User? get user => _user;
  Map<String, dynamic>? get profile => _profile;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;

  AuthProvider() {
    _sb.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      if (_user != null) loadProfile();
      notifyListeners();
    });
  }

  Future<void> loadProfile() async {
    final res = await _sb.from('users').select().eq('auth_id', _user!.id).maybeSingle();
    _profile = res; notifyListeners();
  }

  Future<String?> signIn(String email, String password) async {
    try { _loading = true; notifyListeners(); await _sb.auth.signInWithPassword(email: email, password: password); return null; }
    catch (e) { return e.toString(); } finally { _loading = false; notifyListeners(); }
  }

  Future<String?> signUp(String email, String password, String name, String phone) async {
    try {
      _loading = true; notifyListeners();
      final res = await _sb.auth.signUp(email: email, password: password);
      if (res.user != null) await _sb.from('users').insert({'auth_id': res.user!.id, 'email': email, 'name': name, 'phone': phone, 'role': 'client'});
      return null;
    } catch (e) { return e.toString(); } finally { _loading = false; notifyListeners(); }
  }

  Future<void> signOut() async { await _sb.auth.signOut(); _user = null; _profile = null; notifyListeners(); }
}
