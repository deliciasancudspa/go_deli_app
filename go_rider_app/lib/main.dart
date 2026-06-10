import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:provider/provider.dart";
import "config/app_config.dart";
import "config/app_routes.dart";
import "core/theme/app_theme.dart";
import "core/services/notification_service.dart";
import "firebase_options.dart";
import "providers/rider_provider.dart";

// Handles FCM messages when app is terminated or in background.
// Must be a top-level function.
@pragma("vm:entry-point")
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.init();
  final n = message.notification;
  if (n != null) {
    await NotificationService.show(
      title: n.title ?? "Go Rider",
      body: n.body ?? "",
      payload: "notifications",
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  await NotificationService.init();

  // Tap en push con la app en segundo plano → abrir diálogo de oferta
  FirebaseMessaging.onMessageOpenedApp.listen((m) {
    if ((m.data["route"] ?? "") == "notifications") NotificationService.openOffers();
  });
  // App abierta DESDE una push (estaba cerrada): navegar tras el splash
  final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMsg != null && (initialMsg.data["route"] ?? "") == "notifications") {
    NotificationService.pendingRoute = "/notifications?open=1";
  }

  runApp(const GoRiderApp());
}

class GoRiderApp extends StatelessWidget {
  const GoRiderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RiderProvider(),
      child: MaterialApp.router(
        title: "Go Rider",
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        routerConfig: appRouter,
      ),
    );
  }
}
