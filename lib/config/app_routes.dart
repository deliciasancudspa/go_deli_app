import 'package:go_router/go_router.dart';
import '../features/onboarding/screens/splash_screen.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/home/screens/home_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash',        builder: (c,s) => const SplashScreen()),
    GoRoute(path: '/onboarding',    builder: (c,s) => const OnboardingScreen()),
    GoRoute(path: '/login',         builder: (c,s) => const LoginScreen()),
    GoRoute(path: '/register',      builder: (c,s) => const RegisterScreen()),
    GoRoute(path: '/home',          builder: (c,s) => const HomeScreen()),
  ],
);
