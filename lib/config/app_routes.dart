import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../providers/auth_provider.dart";
import "../providers/cart_provider.dart";
import "../features/onboarding/screens/splash_screen.dart";
import "../features/onboarding/screens/onboarding_screen.dart";
import "../features/onboarding/screens/location_permission_screen.dart";
import "../features/auth/screens/login_screen.dart";
import "../features/auth/screens/register_screen.dart";
import "../features/auth/screens/complete_profile_screen.dart";
import "../features/home/screens/home_screen.dart";
import "../features/search/screens/search_screen.dart";
import "../features/store/screens/store_screen.dart";
import "../features/store/screens/product_detail_screen.dart";
import "../features/cart/screens/cart_screen.dart";
import "../features/checkout/screens/checkout_screen.dart";
import "../features/order/screens/order_success_screen.dart";
import "../features/tracking/screens/tracking_screen.dart";
import "../features/order/screens/order_history_screen.dart";
import "../features/notifications/screens/notifications_screen.dart";
import "../features/chat/screens/chat_screen.dart";
import "../features/map/screens/map_screen.dart";

final GoRouter appRouter = GoRouter(
  initialLocation: "/splash",
  redirect: (context, state) {
    final auth = context.read<AuthProvider>();
    final loggedIn = auth.isLoggedIn;
    final onAuth = ["/login", "/register", "/splash", "/onboarding", "/location", "/complete-profile"].contains(state.matchedLocation);
    if (!loggedIn && !onAuth) return "/login";
    return null;
  },
  routes: [
    GoRoute(path: "/splash",       builder: (c,s) => const SplashScreen()),
    GoRoute(path: "/onboarding",   builder: (c,s) => const OnboardingScreen()),
    GoRoute(path: "/location",     builder: (c,s) => const LocationPermissionScreen()),
    GoRoute(path: "/login",        builder: (c,s) => const LoginScreen()),
    GoRoute(path: "/register",          builder: (c,s) => const RegisterScreen()),
    GoRoute(path: "/complete-profile",  builder: (c,s) => const CompleteProfileScreen()),
    GoRoute(path: "/",             builder: (c,s) => const HomeScreen()),
    GoRoute(path: "/home",         builder: (c,s) => const HomeScreen()),
    GoRoute(path: "/search",       builder: (c,s) => const SearchScreen()),
    GoRoute(path: "/store/:id",    builder: (c,s) => StoreScreen(storeId: s.pathParameters["id"]!)),
    GoRoute(path: "/product/:id",  builder: (c,s) => ProductDetailScreen(productId: s.pathParameters["id"]!)),
    GoRoute(path: "/cart",         builder: (c,s) => const CartScreen()),
    GoRoute(
      path: "/checkout",
      redirect: (context, state) {
        final cart = context.read<CartProvider>();
        final storeId = cart.activeStoreId;
        if (storeId != null) return "/checkout/$storeId";
        return "/cart"; // fallback: sin tienda activa, volver al carrito
      },
    ),
    GoRoute(
      path: "/checkout/:storeId",
      builder: (c, s) => CheckoutScreen(storeId: s.pathParameters["storeId"]!),
    ),
    GoRoute(path: "/order-success/:id", builder: (c,s) => OrderSuccessScreen(orderId: s.pathParameters["id"]!)),
    GoRoute(path: "/tracking/:id", builder: (c,s) => TrackingScreen(orderId: s.pathParameters["id"]!)),
    GoRoute(path: "/orders",       builder: (c,s) => const OrderHistoryScreen()),
    GoRoute(path: "/notifications",builder: (c,s) => const NotificationsScreen()),
    GoRoute(path: "/chat/:orderId",builder: (c,s) => ChatScreen(orderId: s.pathParameters["orderId"]!)),
    GoRoute(path: "/map/:orderId",  builder: (c,s) => MapScreen(orderId: s.pathParameters["orderId"]!)),

    // Deep link godeli-webpay://done → manejar retorno de pago Webpay/Khipu.
    // Transbank redirige a esta URL al finalizar el pago. Sin esta ruta,
    // GoRouter no reconoce el path y la app abre en /splash perdiendo el
    // estado del checkout. Redirigimos según el status del query param.
    GoRoute(
      path: "/done",
      redirect: (context, state) {
        final status  = state.uri.queryParameters["status"]  ?? "";
        final orderId = state.uri.queryParameters["order_id"] ?? "";
        if (status == "approved" && orderId.isNotEmpty) {
          return "/order-success/$orderId";
        }
        // rejected, cancelled o desconocido: volver al checkout
        // donde _checkPendingWebpay recuperará la orden pendiente
        return "/checkout";
      },
    ),
  ],
);
