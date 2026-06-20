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

// NOTA: no se registra onBackgroundMessage. Los push llevan payload
// "notification", así que Android los muestra automáticamente cuando la app
// está en segundo plano o cerrada — duplicarlos manualmente generaba
// notificaciones en blanco.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  await NotificationService.init();

  // Tap en push con la app en segundo plano → abrir diálogo de oferta
  FirebaseMessaging.onMessageOpenedApp.listen((m) {
    final route = m.data["route"] ?? "";
    final orderId = m.data["order_id"] ?? "";
    if (route == "notifications") {
      if (orderId.isNotEmpty) {
        NotificationService.openOffer(orderId, m.data);
      } else {
        NotificationService.openOffers();
      }
    }
  });
  // App abierta DESDE una push (estaba cerrada): navegar tras el splash
  final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMsg != null && (initialMsg.data["route"] ?? "") == "notifications") {
    final oid = initialMsg.data["order_id"] ?? "";
    NotificationService.pendingRoute = oid.isNotEmpty
        ? "/notifications?open=1&order_id=$oid"
        : "/notifications?open=1";
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
