import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "../theme/app_theme.dart";
import "../../l10n/app_localizations.dart";

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
    final tc = ThemeColors.of(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: Builder(builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return BottomNavigationBar(
          currentIndex: idx,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: tc.textLight,
          backgroundColor: tc.surface,
          elevation: 8,
          onTap: (i) {
            switch (i) {
              case 0: context.go("/dashboard");  break;
              case 1: context.go("/orders");     break;
              case 2: context.go("/earnings");   break;
              case 3: context.go("/profile");    break;
            }
          },
          items: [
            BottomNavigationBarItem(icon: const Icon(Icons.home_outlined),                    activeIcon: const Icon(Icons.home),                    label: l10n.bottomNavHome),
            BottomNavigationBarItem(icon: const Icon(Icons.delivery_dining_outlined),          activeIcon: const Icon(Icons.delivery_dining),          label: l10n.bottomNavOrders),
            BottomNavigationBarItem(icon: const Icon(Icons.account_balance_wallet_outlined),   activeIcon: const Icon(Icons.account_balance_wallet),   label: l10n.bottomNavEarnings),
            BottomNavigationBarItem(icon: const Icon(Icons.person_outline),                    activeIcon: const Icon(Icons.person),                  label: l10n.bottomNavProfile),
          ],
        );
      }),
    );
  }
}
