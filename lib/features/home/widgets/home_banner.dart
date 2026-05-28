import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";

class HomeBanner extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  const HomeBanner({super.key, required this.banners});
  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends State<HomeBanner> {
  int _cur = 0;
  final _ctrl = PageController(viewportFraction: 0.9);

  Widget _defaultBanner() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Padding(
      padding: EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text("Oferta especial", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text("30% OFF hoy", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        SizedBox(height: 6),
        Text("Codigo: BIENVENIDO", style: TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final count = widget.banners.isEmpty ? 1 : widget.banners.length;
    return Column(children: [
      SizedBox(
        height: 150,
        child: PageView.builder(
          controller: _ctrl,
          onPageChanged: (i) => setState(() => _cur = i),
          itemCount: count,
          itemBuilder: (ctx, i) {
            if (widget.banners.isEmpty) return _defaultBanner();
            final b = widget.banners[i];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: b["image_url"] != null
                  ? Image.network(b["image_url"], fit: BoxFit.cover, width: double.infinity)
                  : _defaultBanner(),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: _cur == i ? 20 : 6, height: 6,
          decoration: BoxDecoration(
            color: _cur == i ? AppColors.primary : AppColors.border,
            borderRadius: BorderRadius.circular(3),
          ),
        )),
      ),
    ]);
  }
}
