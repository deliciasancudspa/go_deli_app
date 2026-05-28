import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _cur = 0;
  final _pages = [
    {'emoji': 'ðŸ“', 'title': 'Entrega rÃ¡pida', 'desc': 'Recibe tu pedido en minutos directamente en tu puerta', 'color': AppColors.primary},
    {'emoji': 'ðŸ”', 'title': 'Miles de productos', 'desc': 'Restaurantes, supermercados, farmacias y mucho mÃ¡s', 'color': Color(0xFF8B5CF6)},
    {'emoji': 'ðŸ’³', 'title': 'Pago fÃ¡cil', 'desc': 'Paga con tarjeta, efectivo o transferencia de forma segura', 'color': AppColors.success},
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(child: Column(children: [
      Align(alignment: Alignment.topRight, child: TextButton(onPressed: () => context.go('/login'), child: const Text('Omitir', style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w700)))),
      Expanded(child: PageView.builder(
        controller: _ctrl, onPageChanged: (i) => setState(() => _cur = i), itemCount: _pages.length,
        itemBuilder: (ctx, i) {
          final p = _pages[i];
          return Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 160, height: 160, decoration: BoxDecoration(color: (p['color'] as Color).withOpacity(0.1), shape: BoxShape.circle), child: Center(child: Text(p['emoji'] as String, style: const TextStyle(fontSize: 72)))),
            const SizedBox(height: 40),
            Text(p['title'] as String, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.textDark)),
            const SizedBox(height: 16),
            Text(p['desc'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppColors.textLight, height: 1.6)),
          ]));
        },
      )),
      Padding(padding: const EdgeInsets.all(32), child: Column(children: [
        SmoothPageIndicator(controller: _ctrl, count: _pages.length, effect: ExpandingDotsEffect(activeDotColor: AppColors.primary, dotColor: AppColors.border, dotHeight: 8, dotWidth: 8, expansionFactor: 4)),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () { if (_cur < _pages.length - 1) { _ctrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); } else { context.go('/login'); } },
          child: Text(_cur < _pages.length - 1 ? 'Siguiente' : 'Empezar'),
        ),
      ])),
    ])),
  );
}
