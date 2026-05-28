# GO DELI - Script 2: Crea todos los archivos Dart
# Ejecutar desde: C:\proyectos\go_deli
# Comando: .\godeli_archivos.ps1

Write-Host "Creando archivos Dart de Go Deli..." -ForegroundColor Cyan

# =========================================================
# main.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'config/app_config.dart';
import 'config/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/language_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  runApp(const GoDeliApp());
}

class GoDeliApp extends StatelessWidget {
  const GoDeliApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, theme, lang, _) {
          return MaterialApp.router(
            title: 'Go Deli',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.themeMode,
            routerConfig: appRouter,
            locale: Locale(lang.language),
            supportedLocales: const [Locale('es'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          );
        },
      ),
    );
  }
}
'@ | Set-Content -Path "lib/main.dart" -Encoding UTF8
Write-Host "  [OK] main.dart" -ForegroundColor Green

# =========================================================
# config/app_config.dart
# =========================================================
@'
class AppConfig {
  static const String supabaseUrl     = 'https://yxseolcaububyifhksud.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_wc8oyi80Iu2RPgJr-9zS4g_DJ3l-3nV';
  static const String googleMapsApiKey = 'AIzaSyB2MmFbdc9HsUxuGWgPXA0rwZqGvynrevM';
  static const String appName = 'Go Deli';
  static const String defaultCurrency = 'CLP';
  static const double platformCommissionPct = 7.0;
  static const double platformFixedFee = 3000;
}
'@ | Set-Content -Path "lib/config/app_config.dart" -Encoding UTF8
Write-Host "  [OK] app_config.dart" -ForegroundColor Green

# =========================================================
# config/app_routes.dart
# =========================================================
@'
import 'package:go_router/go_router.dart';
import '../features/onboarding/screens/splash_screen.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/search/screens/search_screen.dart';
import '../features/store/screens/store_screen.dart';
import '../features/store/screens/product_detail_screen.dart';
import '../features/cart/screens/cart_screen.dart';
import '../features/checkout/screens/checkout_screen.dart';
import '../features/order/screens/order_success_screen.dart';
import '../features/tracking/screens/tracking_screen.dart';
import '../features/order/screens/order_history_screen.dart';
import '../features/favorites/screens/favorites_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/notifications/screens/notifications_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash',        builder: (c,s) => const SplashScreen()),
    GoRoute(path: '/onboarding',    builder: (c,s) => const OnboardingScreen()),
    GoRoute(path: '/login',         builder: (c,s) => const LoginScreen()),
    GoRoute(path: '/register',      builder: (c,s) => const RegisterScreen()),
    GoRoute(path: '/home',          builder: (c,s) => const HomeScreen()),
    GoRoute(path: '/search',        builder: (c,s) => const SearchScreen()),
    GoRoute(path: '/store/:id',     builder: (c,s) => StoreScreen(storeId: s.pathParameters['id']!)),
    GoRoute(path: '/product/:id',   builder: (c,s) => ProductDetailScreen(productId: s.pathParameters['id']!)),
    GoRoute(path: '/cart',          builder: (c,s) => const CartScreen()),
    GoRoute(path: '/checkout',      builder: (c,s) => const CheckoutScreen()),
    GoRoute(path: '/order-success', builder: (c,s) => const OrderSuccessScreen()),
    GoRoute(path: '/tracking/:id',  builder: (c,s) => TrackingScreen(orderId: s.pathParameters['id']!)),
    GoRoute(path: '/orders',        builder: (c,s) => const OrderHistoryScreen()),
    GoRoute(path: '/favorites',     builder: (c,s) => const FavoritesScreen()),
    GoRoute(path: '/profile',       builder: (c,s) => const ProfileScreen()),
    GoRoute(path: '/chat/:orderId', builder: (c,s) => ChatScreen(orderId: s.pathParameters['orderId']!)),
    GoRoute(path: '/notifications', builder: (c,s) => const NotificationsScreen()),
  ],
);
'@ | Set-Content -Path "lib/config/app_routes.dart" -Encoding UTF8
Write-Host "  [OK] app_routes.dart" -ForegroundColor Green

# =========================================================
# core/theme/app_theme.dart
# =========================================================
@'
import 'package:flutter/material.dart';

class AppColors {
  static const Color primary    = Color(0xFFFF6B35);
  static const Color secondary  = Color(0xFF1A1A2E);
  static const Color accent     = Color(0xFFFFB800);
  static const Color success    = Color(0xFF22C55E);
  static const Color error      = Color(0xFFEF4444);
  static const Color warning    = Color(0xFFF59E0B);
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface    = Color(0xFFFFFFFF);
  static const Color textDark   = Color(0xFF1A1A2E);
  static const Color textMedium = Color(0xFF374151);
  static const Color textLight  = Color(0xFF9CA3AF);
  static const Color border     = Color(0xFFE5E7EB);
  static const Color divider    = Color(0xFFF3F4F6);
  static const Color darkBg     = Color(0xFF0F1923);
  static const Color darkSurface= Color(0xFF1A2636);
}

class AppTheme {
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Nunito',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textDark,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textLight, fontFamily: 'Nunito'),
    ),
    cardTheme: CardTheme(
      color: AppColors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Nunito',
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.darkSurface,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.darkBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
'@ | Set-Content -Path "lib/core/theme/app_theme.dart" -Encoding UTF8
Write-Host "  [OK] app_theme.dart" -ForegroundColor Green

# =========================================================
# providers/auth_provider.dart
# =========================================================
@'
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
    _profile = res;
    notifyListeners();
  }

  Future<String?> signIn(String email, String password) async {
    try {
      _loading = true; notifyListeners();
      await _sb.auth.signInWithPassword(email: email, password: password);
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<String?> signUp(String email, String password, String name, String phone) async {
    try {
      _loading = true; notifyListeners();
      final res = await _sb.auth.signUp(email: email, password: password);
      if (res.user != null) {
        await _sb.from('users').insert({
          'auth_id': res.user!.id,
          'email': email,
          'name': name,
          'phone': phone,
          'role': 'client',
        });
      }
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _sb.auth.signOut();
    _user = null;
    _profile = null;
    notifyListeners();
  }
}
'@ | Set-Content -Path "lib/providers/auth_provider.dart" -Encoding UTF8
Write-Host "  [OK] auth_provider.dart" -ForegroundColor Green

# =========================================================
# providers/cart_provider.dart
# =========================================================
@'
import 'package:flutter/material.dart';

class CartItem {
  final String id, storeId, storeName, name, emoji;
  final int price;
  final String? imageUrl, notes;
  final List<Map<String, dynamic>> extras;
  int quantity;

  CartItem({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.name,
    required this.price,
    this.emoji = '🍽️',
    this.imageUrl,
    this.notes,
    this.extras = const [],
    this.quantity = 1,
  });

  int get totalPrice => (price + extras.fold(0, (s, e) => s + (e['price'] as int? ?? 0))) * quantity;
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
    if (idx >= 0) {
      _items[idx].quantity++;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  void removeItem(String id) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx >= 0) {
      if (_items[idx].quantity > 1) {
        _items[idx].quantity--;
      } else {
        _items.removeAt(idx);
      }
    }
    if (_items.isEmpty) _currentStoreId = null;
    notifyListeners();
  }

  void deleteItem(String id) {
    _items.removeWhere((i) => i.id == id);
    if (_items.isEmpty) _currentStoreId = null;
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _currentStoreId = null;
    notifyListeners();
  }

  int getQuantity(String id) {
    try { return _items.firstWhere((i) => i.id == id).quantity; } catch (_) { return 0; }
  }
}
'@ | Set-Content -Path "lib/providers/cart_provider.dart" -Encoding UTF8
Write-Host "  [OK] cart_provider.dart" -ForegroundColor Green

# =========================================================
# providers/theme_provider.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  ThemeProvider() { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _themeMode = p.getBool('dark_mode') == true ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    final p = await SharedPreferences.getInstance();
    await p.setBool('dark_mode', isDark);
    notifyListeners();
  }
}
'@ | Set-Content -Path "lib/providers/theme_provider.dart" -Encoding UTF8
Write-Host "  [OK] theme_provider.dart" -ForegroundColor Green

# =========================================================
# providers/language_provider.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  String _lang = 'es';
  String get language => _lang;

  LanguageProvider() { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _lang = p.getString('language') ?? 'es';
    notifyListeners();
  }

  Future<void> setLanguage(String l) async {
    _lang = l;
    final p = await SharedPreferences.getInstance();
    await p.setString('language', l);
    notifyListeners();
  }
}
'@ | Set-Content -Path "lib/providers/language_provider.dart" -Encoding UTF8
Write-Host "  [OK] language_provider.dart" -ForegroundColor Green

# =========================================================
# features/onboarding/screens/splash_screen.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _fade  = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _scale = Tween<double>(begin: 0.8, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    final session = Supabase.instance.client.auth.currentSession;
    context.go(session != null ? '/home' : '/onboarding');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 30, spreadRadius: 5)],
                  ),
                  child: const Center(child: Text('🛵', style: TextStyle(fontSize: 48))),
                ),
                const SizedBox(height: 24),
                const Text('Go Deli', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, fontFamily: 'Nunito')),
                const SizedBox(height: 8),
                Text('Pide lo que quieras', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
'@ | Set-Content -Path "lib/features/onboarding/screens/splash_screen.dart" -Encoding UTF8
Write-Host "  [OK] splash_screen.dart" -ForegroundColor Green

# =========================================================
# features/onboarding/screens/onboarding_screen.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _cur = 0;

  final _pages = [
    {'emoji': '📍', 'title': 'Entrega rapida', 'desc': 'Recibe tu pedido en minutos directamente en tu puerta', 'color': AppColors.primary},
    {'emoji': '🍔', 'title': 'Miles de productos', 'desc': 'Restaurantes, supermercados, farmacias y mucho mas', 'color': Color(0xFF8B5CF6)},
    {'emoji': '💳', 'title': 'Pago facil', 'desc': 'Paga con tarjeta, efectivo o transferencia de forma segura', 'color': AppColors.success},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: Column(children: [
        Align(
          alignment: Alignment.topRight,
          child: TextButton(onPressed: () => context.go('/login'), child: const Text('Omitir', style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w700))),
        ),
        Expanded(
          child: PageView.builder(
            controller: _ctrl,
            onPageChanged: (i) => setState(() => _cur = i),
            itemCount: _pages.length,
            itemBuilder: (ctx, i) {
              final p = _pages[i];
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 160, height: 160,
                    decoration: BoxDecoration(color: (p['color'] as Color).withOpacity(0.1), shape: BoxShape.circle),
                    child: Center(child: Text(p['emoji'] as String, style: const TextStyle(fontSize: 72))),
                  ),
                  const SizedBox(height: 40),
                  Text(p['title'] as String, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textDark)),
                  const SizedBox(height: 16),
                  Text(p['desc'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppColors.textLight, height: 1.6)),
                ]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            SmoothPageIndicator(
              controller: _ctrl, count: _pages.length,
              effect: ExpandingDotsEffect(activeDotColor: AppColors.primary, dotColor: AppColors.border, dotHeight: 8, dotWidth: 8, expansionFactor: 4),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                if (_cur < _pages.length - 1) {
                  _ctrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                } else {
                  context.go('/login');
                }
              },
              child: Text(_cur < _pages.length - 1 ? 'Siguiente' : 'Empezar'),
            ),
          ]),
        ),
      ])),
    );
  }
}
'@ | Set-Content -Path "lib/features/onboarding/screens/onboarding_screen.dart" -Encoding UTF8
Write-Host "  [OK] onboarding_screen.dart" -ForegroundColor Green

# =========================================================
# features/auth/screens/login_screen.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;
  String? _error;

  Future<void> _login() async {
    final auth = context.read<AuthProvider>();
    final err = await auth.signIn(_emailCtrl.text.trim(), _passCtrl.text);
    if (err != null) {
      setState(() => _error = 'Email o contrasena incorrectos');
    } else if (mounted) {
      context.go('/home');
    }
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
    prefixIcon: Icon(icon, color: AppColors.primary),
    filled: true,
    fillColor: const Color(0xFF0F1923),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
  );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 40),
            Column(children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                child: const Center(child: Text('🛵', style: TextStyle(fontSize: 36))),
              ),
              const SizedBox(height: 16),
              const Text('Go Deli', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Bienvenido de vuelta', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15)),
            ]),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFF1A2636), borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Iniciar sesion', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),
                TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: Colors.white), decoration: _dec('Correo electronico', Icons.email_outlined)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl, obscureText: _obscure, style: const TextStyle(color: Colors.white),
                  decoration: _dec('Contrasena', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38), onPressed: () => setState(() => _obscure = !_obscure)),
                  ),
                  onFieldSubmitted: (_) => _login(),
                ),
                if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () {}, child: const Text('Olvidaste tu contrasena?', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))),
                ),
                ElevatedButton(
                  onPressed: auth.loading ? null : _login,
                  child: auth.loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Entrar'),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('No tienes cuenta? ', style: TextStyle(color: Colors.white60)),
              GestureDetector(onTap: () => context.go('/register'), child: const Text('Registrate', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800))),
            ]),
          ]),
        ),
      ),
    );
  }
}
'@ | Set-Content -Path "lib/features/auth/screens/login_screen.dart" -Encoding UTF8
Write-Host "  [OK] login_screen.dart" -ForegroundColor Green

# =========================================================
# features/auth/screens/register_screen.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;
  String? _error;

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Completa todos los campos');
      return;
    }
    final err = await context.read<AuthProvider>().signUp(_emailCtrl.text.trim(), _passCtrl.text, _nameCtrl.text.trim(), _phoneCtrl.text.trim());
    if (err != null) {
      setState(() => _error = 'Error al registrarse. Intenta con otro email.');
    } else if (mounted) {
      context.go('/home');
    }
  }

  Widget _field(TextEditingController c, String hint, IconData icon, {TextInputType type = TextInputType.text}) {
    return TextFormField(
      controller: c, keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true, fillColor: const Color(0xFF0F1923),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 20),
            Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.go('/login')),
              const Text('Crear cuenta', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFF1A2636), borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                _field(_nameCtrl, 'Nombre completo', Icons.person_outline),
                const SizedBox(height: 12),
                _field(_emailCtrl, 'Correo electronico', Icons.email_outlined, type: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _field(_phoneCtrl, 'Telefono (opcional)', Icons.phone_outlined, type: TextInputType.phone),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl, obscureText: _obscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Contrasena',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
                    suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38), onPressed: () => setState(() => _obscure = !_obscure)),
                    filled: true, fillColor: const Color(0xFF0F1923),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                  ),
                ),
                if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: auth.loading ? null : _register,
                  child: auth.loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Crear cuenta'),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Ya tienes cuenta? ', style: TextStyle(color: Colors.white60)),
              GestureDetector(onTap: () => context.go('/login'), child: const Text('Inicia sesion', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800))),
            ]),
          ]),
        ),
      ),
    );
  }
}
'@ | Set-Content -Path "lib/features/auth/screens/register_screen.dart" -Encoding UTF8
Write-Host "  [OK] register_screen.dart" -ForegroundColor Green

# =========================================================
# features/home/widgets/store_card.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';

class StoreCard extends StatelessWidget {
  final Map<String, dynamic> store;
  final VoidCallback onTap;
  const StoreCard({super.key, required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Stack(children: [
              store['cover_url'] != null
                ? CachedNetworkImage(imageUrl: store['cover_url'], height: 130, width: double.infinity, fit: BoxFit.cover)
                : Container(
                    height: 130, width: double.infinity,
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                    child: Center(child: Text(store['emoji'] ?? '🍽️', style: const TextStyle(fontSize: 50))),
                  ),
              if (store['badge'] != null)
                Positioned(top: 10, left: 10, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                  child: Text(store['badge'], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                )),
              if (!(store['is_open'] ?? true))
                Container(height: 130, width: double.infinity, color: Colors.black54,
                  child: const Center(child: Text('CERRADO', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 4)))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(store['name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 4),
              Text(store['category'] ?? '', style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.star, color: Colors.amber, size: 14), const SizedBox(width: 3),
                Text('${store['rating'] ?? 5.0}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(width: 6), Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.border, shape: BoxShape.circle)), const SizedBox(width: 6),
                const Icon(Icons.access_time, size: 14, color: AppColors.textLight), const SizedBox(width: 3),
                Text('${store['delivery_time'] ?? '30-45'} min', style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
                const SizedBox(width: 6), Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.border, shape: BoxShape.circle)), const SizedBox(width: 6),
                const Icon(Icons.delivery_dining, size: 14, color: AppColors.textLight), const SizedBox(width: 3),
                Text('\$${((store['delivery_fee'] ?? 2990) as num).toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
'@ | Set-Content -Path "lib/features/home/widgets/store_card.dart" -Encoding UTF8
Write-Host "  [OK] store_card.dart" -ForegroundColor Green

# =========================================================
# features/home/widgets/category_chip.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class CategoryChip extends StatelessWidget {
  final Map<String, dynamic> category;
  final bool isSelected;
  final VoidCallback onTap;
  const CategoryChip({super.key, required this.category, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.secondary : AppColors.surface,
          border: Border.all(color: isSelected ? AppColors.secondary : AppColors.border, width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(category['emoji'] as String, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(category['name'] as String, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isSelected ? AppColors.primary : AppColors.textMedium)),
        ]),
      ),
    );
  }
}
'@ | Set-Content -Path "lib/features/home/widgets/category_chip.dart" -Encoding UTF8
Write-Host "  [OK] category_chip.dart" -ForegroundColor Green

# =========================================================
# features/home/widgets/home_banner.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';

class HomeBanner extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  const HomeBanner({super.key, required this.banners});
  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends State<HomeBanner> {
  int _cur = 0;

  Widget _default() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(children: [
      const Expanded(child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Oferta especial', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('30% OFF\nhoy', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.2)),
          SizedBox(height: 6),
          Text('Codigo: BIENVENIDO', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      )),
      const Text('🛵', style: TextStyle(fontSize: 60)),
      const SizedBox(width: 16),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      CarouselSlider(
        options: CarouselOptions(
          height: 150, autoPlay: true,
          autoPlayInterval: const Duration(seconds: 4),
          enlargeCenterPage: true, viewportFraction: 0.9,
          onPageChanged: (i, _) => setState(() => _cur = i),
        ),
        items: widget.banners.isEmpty
          ? [_default()]
          : widget.banners.map((b) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: b['image_url'] != null
                  ? CachedNetworkImage(imageUrl: b['image_url'], fit: BoxFit.cover, width: double.infinity)
                  : _default(),
              ),
            )).toList(),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          widget.banners.isEmpty ? 1 : widget.banners.length,
          (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: _cur == i ? 20 : 6, height: 6,
            decoration: BoxDecoration(color: _cur == i ? AppColors.primary : AppColors.border, borderRadius: BorderRadius.circular(3)),
          ),
        ),
      ),
    ]);
  }
}
'@ | Set-Content -Path "lib/features/home/widgets/home_banner.dart" -Encoding UTF8
Write-Host "  [OK] home_banner.dart" -ForegroundColor Green

# =========================================================
# features/home/screens/home_screen.dart
# =========================================================
@'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/cart_provider.dart';
import '../../../providers/auth_provider.dart';
import '../widgets/store_card.dart';
import '../widgets/category_chip.dart';
import '../widgets/home_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIdx = 0;
  List<Map<String, dynamic>> _stores = [], _banners = [];
  bool _loading = true;
  String _cat = 'Todos';
  final _sb = Supabase.instance.client;

  final _cats = [
    {'name': 'Todos', 'emoji': '🌟'},
    {'name': 'Hamburguesas', 'emoji': '🍔'},
    {'name': 'Sushi', 'emoji': '🍣'},
    {'name': 'Pizza', 'emoji': '🍕'},
    {'name': 'Carnes', 'emoji': '🥩'},
    {'name': 'Bebidas', 'emoji': '🥤'},
    {'name': 'Postres', 'emoji': '🍰'},
    {'name': 'Supermercado', 'emoji': '🛒'},
    {'name': 'Farmacia', 'emoji': '💊'},
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final stores  = await _sb.from('stores').select().eq('status', 'approved').eq('is_active', true);
    final banners = await _sb.from('banners').select().eq('is_active', true).order('sort_order');
    if (mounted) setState(() {
      _stores  = List<Map<String, dynamic>>.from(stores);
      _banners = List<Map<String, dynamic>>.from(banners);
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered =>
    _cat == 'Todos' ? _stores : _stores.where((s) => s['category'] == _cat).toList();

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: Column(children: [
        Container(
          color: AppColors.secondary,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Entregar en', style: TextStyle(color: Colors.white60, fontSize: 12)),
                Row(children: [
                  const Icon(Icons.location_on, color: AppColors.primary, size: 16),
                  const SizedBox(width: 4),
                  Text(auth.profile?['address'] ?? 'Agregar direccion', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
              ])),
              Stack(children: [
                IconButton(icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white), onPressed: () => context.push('/cart')),
                if (cart.itemCount > 0)
                  Positioned(right: 6, top: 6, child: Container(
                    width: 18, height: 18,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: Center(child: Text('${cart.itemCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))),
                  )),
              ]),
            ]),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => context.push('/search'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFF1A2636), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.search, color: Colors.white38, size: 20),
                  const SizedBox(width: 10),
                  Text('Buscar productos, tiendas...', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14)),
                ]),
              ),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.primary,
            child: ListView(children: [
              if (_banners.isNotEmpty) HomeBanner(banners: _banners),
              const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 12), child: Text('Categorias', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark))),
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _cats.length,
                  itemBuilder: (ctx, i) => CategoryChip(
                    category: _cats[i],
                    isSelected: _cat == _cats[i]['name'],
                    onTap: () => setState(() => _cat = _cats[i]['name'] as String),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Tiendas cerca de ti', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  Text('(${_filtered.length})', style: const TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                ]),
              ),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.primary)))
              else if (_filtered.isEmpty)
                const Center(child: Padding(padding: EdgeInsets.all(40), child: Column(children: [
                  Text('🔍', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text('Sin restaurantes disponibles', style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                ])))
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filtered.length,
                  itemBuilder: (ctx, i) => StoreCard(
                    store: _filtered[i],
                    onTap: () => context.push('/store/${_filtered[i]['id']}'),
                  ),
                ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIdx,
        onDestinationSelected: (i) {
          setState(() => _navIdx = i);
          switch (i) {
            case 1: context.push('/search'); break;
            case 2: context.push('/orders'); break;
            case 3: context.push('/favorites'); break;
            case 4: context.push('/profile'); break;
          }
        },
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withOpacity(0.1),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.primary), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search, color: AppColors.primary), label: 'Buscar'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long, color: AppColors.primary), label: 'Pedidos'),
          NavigationDestination(icon: Icon(Icons.favorite_outline), selectedIcon: Icon(Icons.favorite, color: AppColors.primary), label: 'Favoritos'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: AppColors.primary), label: 'Perfil'),
        ],
      ),
    );
  }
}
'@ | Set-Content -Path "lib/features/home/screens/home_screen.dart" -Encoding UTF8
Write-Host "  [OK] home_screen.dart" -ForegroundColor Green

# =========================================================
# Pantallas simples (search, cart, orders, etc.)
# =========================================================

@'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/widgets/store_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  final _sb = Supabase.instance.client;

  Future<void> _search(String q) async {
    if (q.isEmpty) { setState(() => _results = []); return; }
    setState(() => _loading = true);
    final res = await _sb.from('stores').select().eq('status', 'approved').ilike('name', '%$q%');
    if (mounted) setState(() { _results = List<Map<String, dynamic>>.from(res); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.secondary,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
        title: TextField(
          controller: _ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Buscar productos, tiendas...', hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none, filled: false),
          onChanged: _search,
        ),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _results.isEmpty && _ctrl.text.isNotEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('🔍', style: TextStyle(fontSize: 48)), SizedBox(height: 12), Text('Sin resultados', style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600))]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _results.length,
              itemBuilder: (ctx, i) => StoreCard(store: _results[i], onTap: () => context.push('/store/${_results[i]['id']}')),
            ),
    );
  }
}
'@ | Set-Content -Path "lib/features/search/screens/search_screen.dart" -Encoding UTF8
Write-Host "  [OK] search_screen.dart" -ForegroundColor Green

@'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/cart_provider.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  String _fmt(int p) => '\$${p.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Tu carrito'),
        actions: [if (!cart.isEmpty) TextButton(onPressed: cart.clearCart, child: const Text('Vaciar', style: TextStyle(color: AppColors.error)))],
      ),
      body: cart.isEmpty
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('🛒', style: TextStyle(fontSize: 64)), SizedBox(height: 16),
            Text('Tu carrito esta vacio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textLight)),
          ]))
        : Column(children: [
            Expanded(child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cart.items.length,
              itemBuilder: (ctx, i) {
                final item = cart.items[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
                  child: Row(children: [
                    Text(item.emoji, style: const TextStyle(fontSize: 32)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      Text(_fmt(item.totalPrice), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ])),
                    Row(children: [
                      GestureDetector(onTap: () => cart.removeItem(item.id), child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle), child: const Icon(Icons.remove, color: Colors.white, size: 16))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                      GestureDetector(onTap: () => cart.addItem(item), child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 16))),
                    ]),
                  ]),
                );
              },
            )),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.surface, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -4))]),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Subtotal', style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                  Text(_fmt(cart.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () => context.push('/checkout'), child: Text('Ir a pagar · ${_fmt(cart.subtotal)}')),
              ]),
            ),
          ]),
    );
  }
}
'@ | Set-Content -Path "lib/features/cart/screens/cart_screen.dart" -Encoding UTF8
Write-Host "  [OK] cart_screen.dart" -ForegroundColor Green

@'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/cart_provider.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _addrCtrl = TextEditingController();
  String _pay = 'cash';
  bool _loading = false;
  final _sb = Supabase.instance.client;

  String _fmt(int p) => '\$${p.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

  Future<void> _place() async {
    if (_addrCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingresa tu direccion')));
      return;
    }
    setState(() => _loading = true);
    try {
      final cart = context.read<CartProvider>();
      final user = _sb.auth.currentUser!;
      final u = await _sb.from('users').select('id').eq('auth_id', user.id).single();
      final s = await _sb.from('stores').select('delivery_fee,fixed_fee,commission_pct').eq('id', cart.currentStoreId!).single();
      final fee    = (s['delivery_fee'] as num).toInt();
      final fix    = (s['fixed_fee'] as num).toInt();
      final pct    = (s['commission_pct'] as num).toDouble();
      final platFee = (cart.subtotal * pct / 100).toInt();
      final total   = cart.subtotal + fee;
      final order = await _sb.from('orders').insert({
        'client_id': u['id'], 'store_id': cart.currentStoreId,
        'subtotal': cart.subtotal, 'delivery_fee': fee,
        'platform_fee': platFee, 'fixed_fee': fix,
        'total': total, 'delivery_address': _addrCtrl.text,
        'payment_method': _pay, 'status': 'pending',
      }).select().single();
      await _sb.from('order_items').insert(cart.items.map((i) => {
        'order_id': order['id'], 'menu_item_id': i.id,
        'item_name': i.name, 'item_price': i.price,
        'quantity': i.quantity, 'subtotal': i.totalPrice,
      }).toList());
      cart.clearCart();
      if (mounted) context.go('/order-success');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final methods = [
      {'id': 'cash', 'label': 'Efectivo', 'emoji': '💵'},
      {'id': 'card', 'label': 'Tarjeta', 'emoji': '💳'},
      {'id': 'transfer', 'label': 'Transferencia', 'emoji': '📱'},
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Confirmar pedido')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Direccion de entrega', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        TextFormField(controller: _addrCtrl, decoration: const InputDecoration(hintText: 'Ej: Calle Principal 123', prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.primary))),
        const SizedBox(height: 24),
        const Text('Metodo de pago', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 12),
        Row(children: methods.map((m) => Expanded(child: GestureDetector(
          onTap: () => setState(() => _pay = m['id']!),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _pay == m['id'] ? AppColors.primary.withOpacity(0.1) : AppColors.surface,
              border: Border.all(color: _pay == m['id'] ? AppColors.primary : AppColors.border, width: _pay == m['id'] ? 2 : 1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Text(m['emoji']!, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(m['label']!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _pay == m['id'] ? AppColors.primary : AppColors.textMedium)),
            ]),
          ),
        ))).toList()),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            const Text('Resumen', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            ...cart.items.map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${i.quantity}x ${i.name}', style: const TextStyle(color: AppColors.textMedium, fontWeight: FontWeight.w600)),
                Text(_fmt(i.totalPrice), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            )),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              Text(_fmt(cart.subtotal), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.primary)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _loading ? null : _place,
          child: _loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text('Confirmar pedido · ${_fmt(cart.subtotal)}'),
        ),
      ),
    );
  }
}
'@ | Set-Content -Path "lib/features/checkout/screens/checkout_screen.dart" -Encoding UTF8
Write-Host "  [OK] checkout_screen.dart" -ForegroundColor Green

# Pantallas placeholder simples
@'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 120, height: 120, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Center(child: Text('✅', style: TextStyle(fontSize: 56)))),
          const SizedBox(height: 32),
          const Text('Pedido c