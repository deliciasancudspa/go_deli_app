import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  String _lang = "es";
  String get language => _lang;
  Locale get locale => Locale(_lang);

  LanguageProvider() { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _lang = p.getString("language") ?? "es";
    notifyListeners();
  }

  Future<void> setLanguage(String l) async {
    _lang = l;
    final p = await SharedPreferences.getInstance();
    await p.setString("language", l);
    notifyListeners();
  }
}
