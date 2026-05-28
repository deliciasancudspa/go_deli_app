import "package:go_router/go_router.dart";
import "../features/onboarding/screens/splash_screen.dart";
import "../features/onboarding/screens/onboarding_screen.dart";
import "../features/auth/screens/login_screen.dart";
import "../features/auth/screens/register_screen.dart";
import "../features/home/screens/home_screen.dart";
import "../features/search/screens/search_screen.dart";
import "../features/store/screens/store_screen.dart";
import "../features/store/screens/product_detail_screen.dart";
import "../features/cart/screens/cart_screen.dart";
import "../features/checkout/screens/checkout_screen.dart";
import "../features/order/screens/order_success_screen.dart";
import "../features/tracking/screens/tracking_screen.dart";
import "../features/order/screens/order_history_screen.dart";
import "../features/favorites/screens/favorites_screen.dart";
import "../features/profile/screens/profile_screen.dart";
import "../features/chat/screens/chat_screen.dart";
import "../features/notifications/screens/notifications_screen.dart";

final GoRouter appRouter = GoRouter(
  initialLocation: "/splash",
  routes: [
    GoRoute(path: "/splash",        builder: (c,s) => const SplashScreen()),
    GoRoute(path: "/onboarding",    builder: (c,s) => const OnboardingScreen()),
    GoRoute(path: "/login",         builder: (c,s) => const LoginScreen()),
    GoRoute(path: "/register",      builder: (c,s) => const RegisterScreen()),
    GoRoute(path: "/home",          builder: (c,s) => const HomeScreen()),
    GoRoute(path: "/search",        builder: (c,s) => const SearchScreen()),
    GoRoute(path: "/store/:id",     builder: (c,s) => StoreScreen(storeId: s.pathParameters["id"]!)),
    GoRoute(path: "/product/:id",   builder: (c,s) => ProductDetailScreen(productId: s.pathParameters["id"]!)),
    GoRoute(path: "/cart",          builder: (c,s) => const CartScreen()),
    GoRoute(path: "/checkout",      builder: (c,s) => const CheckoutScreen()),
    GoRoute(path: "/order-success", builder: (c,s) => const OrderSuccessScreen()),
    GoRoute(path: "/tracking/:id",  builder: (c,s) => TrackingScreen(orderId: s.pathParameters["id"]!)),
    GoRoute(path: "/orders",        builder: (c,s) => const OrderHistoryScreen()),
    GoRoute(path: "/favorites",     builder: (c,s) => const FavoritesScreen()),
    GoRoute(path: "/profile",       builder: (c,s) => const ProfileScreen()),
    GoRoute(path: "/chat/:orderId", builder: (c,s) => ChatScreen(orderId: s.pathParameters["orderId"]!)),
    GoRoute(path: "/notifications", builder: (c,s) => const NotificationsScreen()),
  ],
);
