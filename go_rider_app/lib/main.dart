import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:provider/provider.dart";
import "config/app_config.dart";
import "config/app_routes.dart";
import "core/theme/app_theme.dart";
import "core/services/notification_service.dart";
import "providers/rider_provider.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  await NotificationService.init();
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
