import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "../theme/app_theme.dart";

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _tabIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith("/orders"))   return 1;
    if (path.startsWith("/earnings")) return 2;
    if (path.startsWith("/profile"))  return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _tabIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: idx,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textLight,
        backgroundColor: AppColors.surface,
        elevation: 8,
        onTap: (i) {
          switch (i) {
            case 0: context.go("/dashboard");  break;
            case 1: context.go("/orders");     break;
            case 2: context.go("/earnings");   break;
            case 3: context.go("/profile");    break;
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined),                    activeIcon: Icon(Icons.home),                    label: "Inicio"),
          BottomNavigationBarItem(icon: Icon(Icons.delivery_dining_outlined),          activeIcon: Icon(Icons.delivery_dining),          label: "Pedidos"),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined),   activeIcon: Icon(Icons.account_balance_wallet),   label: "Ganancias"),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline),                    activeIcon: Icon(Icons.person),                  label: "Perfil"),
        ],
      ),
    );
  }
}
