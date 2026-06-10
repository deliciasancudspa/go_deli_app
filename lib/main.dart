import "package:firebase_core/firebase_core.dart";
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  await NotificationService().init();
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
