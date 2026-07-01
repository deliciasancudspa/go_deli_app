import "dart:async";
import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/utils/color_utils.dart";

class HomeBanner extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  const HomeBanner({super.key, required this.banners});
  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends State<HomeBanner> {
  int    _cur  = 0;
  final  _ctrl = PageController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.banners.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!_ctrl.hasClients) return;
        final next = (_cur + 1) % widget.banners.length;
        _ctrl.animateToPage(next,
            duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() { _timer?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return _defaultBanner();
    return Column(children: [
      AspectRatio(
        aspectRatio: 2,
        child: PageView.builder(
          controller: _ctrl,
          itemCount: widget.banners.length,
          onPageChanged: (i) => setState(() => _cur = i),
          itemBuilder: (_, i) {
            final b      = widget.banners[i];
            final imgUrl = b["image_url"] as String?;
            final bg = parseHexColor(b["bg_color"] as String?, fallback: AppColors.homeOrange);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: bg,
                image: imgUrl != null
                    ? DecorationImage(
                        image: NetworkImage(imgUrl),
                        fit: BoxFit.cover)
                    : null,
                boxShadow: [BoxShadow(
                    color: bg.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
              ),
              child: imgUrl == null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (b["title"] != null)
                            Text(b["title"],
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 22,
                                    fontWeight: FontWeight.w900, fontFamily: "Nunito")),
                          if (b["subtitle"] != null) ...[
                            const SizedBox(height: 6),
                            Text(b["subtitle"],
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 14, fontFamily: "Nunito")),
                          ],
                        ],
                      ),
                    )
                  : Stack(children: [
                      if (b["title"] != null)
                        Positioned(
                          bottom: 20, left: 20, right: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(b["title"],
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 20,
                                      fontWeight: FontWeight.w900, fontFamily: "Nunito",
                                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
                              if (b["subtitle"] != null)
                                Text(b["subtitle"],
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.85),
                                        fontSize: 13, fontFamily: "Nunito")),
                            ],
                          ),
                        ),
                    ]),
            );
          },
        ),
      ),
      if (widget.banners.length > 1) ...[
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.banners.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: _cur == i ? 20 : 6, height: 6,
            decoration: BoxDecoration(
              color: _cur == i ? AppColors.homeOrange : AppColors.homeCardBorder,
              borderRadius: BorderRadius.circular(3),
            ),
          )),
        ),
      ],
    ]);
  }

  Widget _defaultBanner() => AspectRatio(
    aspectRatio: 2,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.homeDark, Color(0xFF3D0080)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text("Oferta especial", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text("Descubre Go Deli", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          SizedBox(height: 6),
          Text("Los mejores locales cerca de ti", style: TextStyle(color: Colors.white60, fontSize: 13)),
        ]),
      ),
    ),
  );
}
