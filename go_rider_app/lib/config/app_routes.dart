import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../providers/rider_provider.dart";
import "../features/auth/screens/splash_screen.dart";
import "../features/auth/screens/login_screen.dart";
import "../features/auth/screens/register_screen.dart";
import "../features/auth/screens/pending_screen.dart";
import "../features/dashboard/screens/dashboard_screen.dart";
import "../features/orders/screens/orders_screen.dart";
import "../features/orders/screens/order_detail_screen.dart";
import "../features/earnings/screens/earnings_screen.dart";
import "../features/profile/screens/profile_screen.dart";

final GoRouter appRouter = GoRouter(
  initialLocation: "/splash",
  routes: [
    GoRoute(path: "/splash",    builder: (c,s) => const SplashScreen()),
    GoRoute(path: "/login",     builder: (c,s) => const LoginScreen()),
    GoRoute(path: "/register",  builder: (c,s) => const RegisterScreen()),
    GoRoute(path: "/pending",   builder: (c,s) => const PendingScreen()),
    GoRoute(path: "/dashboard", builder: (c,s) => const DashboardScreen()),
    GoRoute(path: "/orders",    builder: (c,s) => const OrdersScreen()),
    GoRoute(path: "/order/:id", builder: (c,s) => OrderDetailScreen(orderId: s.pathParameters["id"]!)),
    GoRoute(path: "/earnings",  builder: (c,s) => const EarningsScreen()),
    GoRoute(path: "/profile",   builder: (c,s) => const ProfileScreen()),
  ],
);
