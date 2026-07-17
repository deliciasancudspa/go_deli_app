import "package:go_router/go_router.dart";
import "../features/auth/screens/splash_screen.dart";
import "../features/auth/screens/login_screen.dart";
import "../features/auth/screens/register_screen.dart";
import "../features/auth/screens/pending_screen.dart";
import "../features/dashboard/screens/dashboard_screen.dart";
import "../features/orders/screens/orders_screen.dart";
import "../features/orders/screens/order_detail_screen.dart";
import "../features/earnings/screens/earnings_screen.dart";
import "../features/profile/screens/profile_screen.dart";
import "../features/performance/screens/performance_screen.dart";
import "../features/notifications/screens/notifications_screen.dart";
import "../features/chat/screens/chat_screen.dart";
import "../features/profile/screens/admin_chat_screen.dart";
import "../core/widgets/main_shell.dart";

final GoRouter appRouter = GoRouter(
  initialLocation: "/splash",
  routes: [
    GoRoute(path: "/splash",    builder: (c,s) => const SplashScreen()),
    GoRoute(path: "/login",     builder: (c,s) => const LoginScreen()),
    GoRoute(path: "/register",  builder: (c,s) => const RegisterScreen()),
    GoRoute(path: "/pending",   builder: (c,s) => const PendingScreen()),

    // Pantallas de detalle — sin bottom nav
    GoRoute(path: "/order/:id",          builder: (c,s) => OrderDetailScreen(orderId: s.pathParameters["id"]!)),
    GoRoute(path: "/chat/:orderId",      builder: (c,s) => RiderChatScreen(orderId: s.pathParameters["orderId"]!)),
    GoRoute(path: "/chat-admin/:adminId",builder: (c,s) => AdminChatScreen(adminId: s.pathParameters["adminId"]!)),
    GoRoute(path: "/performance",  builder: (c,s) => const PerformanceScreen()),
    GoRoute(path: "/notifications",      builder: (c,s) => NotificationsScreen(
      autoOpen: s.uri.queryParameters["open"] == "1",
      directOrderId: s.uri.queryParameters["order_id"],
    )),

    // Pantallas principales — con bottom nav persistente
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: "/dashboard", builder: (c,s) => const DashboardScreen()),
        GoRoute(path: "/orders",    builder: (c,s) => const OrdersScreen()),
        GoRoute(path: "/earnings",  builder: (c,s) => const EarningsScreen()),
        GoRoute(path: "/profile",   builder: (c,s) => const ProfileScreen()),
      ],
    ),
  ],
);
