import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  ThemeProvider() { _load(); }
  Future<void> _load() async { final p = await SharedPreferences.getInstance(); _themeMode = p.getBool('dark_mode') == true ? ThemeMode.dark : ThemeMode.light; notifyListeners(); }
  Future<void> toggleTheme() async { _themeMode = isDark ? ThemeMode.light : ThemeMode.dark; final p = await SharedPreferences.getInstance(); await p.setBool('dark_mode', isDark); notifyListeners(); }
}
