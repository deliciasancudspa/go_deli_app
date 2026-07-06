import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "config/app_config.dart";
import "config/app_routes.dart";
import "core/theme/app_theme.dart";
import "firebase_options.dart";
import "providers/auth_provider.dart";
import "providers/cart_provider.dart";
import "providers/language_provider.dart";
import "providers/theme_provider.dart";
import "services/notification_service.dart";

// NOTA: no se registra onBackgroundMessage. Los push llevan payload
// "notification", así que Android los muestra automáticamente cuando la app
// está en segundo plano o cerrada — mostrarlos también manualmente generaba
// notificaciones duplicadas/en blanco.
//
// Sí manejamos el TAP en la notificación para redirigir según el data payload.

void _handleFcmData(Map<String, dynamic> data) {
  final route = data["route"] ?? "";
  final storeId = data["store_id"] ?? "";
  final productId = data["product_id"] ?? "";
  final url = data["url"] ?? "";

  if (route == "store" && storeId.isNotEmpty) {
    appRouter.push("/store/$storeId");
  } else if (route == "product" && productId.isNotEmpty) {
    appRouter.push("/product/$productId");
  } else if (route == "url" && url.isNotEmpty) {
    appRouter.push("/home");  // url externa: abrir home; el navegador se abre desde la notificación
  } else if (route == "home") {
    appRouter.push("/home");
  }
  // "orders" y otros: no redirigir, la app ya tiene listeners
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('⚠️ Firebase no disponible: $e — notificaciones push deshabilitadas');
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  await NotificationService().init();

  // Al tocar una notificación con la app en segundo plano → redirigir
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    _handleFcmData(message.data);
  });

  // App abierta desde una notificación estando cerrada → redirigir tras splash
  final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMsg != null) {
    // Guardar para ejecutar después del login/splash
    NotificationService.pendingFcmData = initialMsg.data;
  }

  runApp(const GoDeliApp());
  // Restaurar carritos guardados tras iniciar la app
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // CartProvider se accede a través del context del widget tree.
    // Usamos un builder en GoDeliApp para capturarlo.
  });
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
          // loadSavedCarts() debe ejecutarse DESDE UN WIDGET HIJO de
          // MultiProvider, porque GoDeliApp.context no ve providers que
          // él mismo crea (solo ancestros). Usamos addPostFrameCallback
          // dentro del builder del Consumer, que SÍ tiene acceso.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              context.read<CartProvider>().loadSavedCarts();
            } catch (_) {}
          });
          return MaterialApp.router(
            title: "Go Deli",
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.themeMode,
            routerConfig: appRouter,
            locale: Locale(lang.language),
            supportedLocales: const [Locale("es"), Locale("en")],
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
