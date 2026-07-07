import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/utils/price_formatter.dart";

class StoreCard extends StatelessWidget {
  final Map<String, dynamic> store;
  final VoidCallback onTap;
  // 'cover' | 'logo' | 'product'
  final String displayMode;

  const StoreCard({
    super.key,
    required this.store,
    required this.onTap,
    this.displayMode = 'cover',
  });

  String _fmt(num p) => "\$${p.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  @override
  Widget build(BuildContext context) {
    if (displayMode == 'logo') return _buildLogoCard();
    if (displayMode == 'product') return _buildProductCard();
    return _buildCoverCard();
  }

  // ── COVER mode ─────────────────────────────────────────────────────────────
  Widget _buildCoverCard() {
    final logoUrl  = store["logo_url"]  as String?;
    final coverUrl = store["cover_url"] as String?;
    final fee      = (store["delivery_fee_client"] as num?)?.toInt() ?? 0;
    final isOpen   = store["is_open"] as bool? ?? true;
    final sponsored = store["sponsored"] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildCoverImage(coverUrl, logoUrl),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.border,
                    backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                    child: logoUrl == null
                        ? Text(store["emoji"] as String? ?? "🍽️", style: const TextStyle(fontSize: 14))
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(store["name"] as String? ?? "",
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.homeDark),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const Icon(Icons.star_rounded, color: AppColors.homeOrange, size: 13),
                  Text(" ${store["rating"] ?? "5.0"}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 4),
                Text(
                  "${cleanDeliveryTime(store["delivery_time"])} · "
                  "${hasOwnDelivery(store) ? "🚗 Delivery propio" : (fee == 0 ? "🛵 Gratis" : "🛵 ${_fmt(fee)}")}",
                  style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                ),
                if (!isOpen || sponsored) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    if (sponsored) _badge("Destacado", AppColors.homeOrange),
                    if (!isOpen) _badge("Cerrado", AppColors.error, textColor: AppColors.error, bg: true),
                  ]),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── LOGO mode ──────────────────────────────────────────────────────────────
  Widget _buildLogoCard() {
    final logoUrl = store["logo_url"] as String?;
    final emoji   = store["emoji"]    as String? ?? "🍽️";
    final name    = store["name"]     as String? ?? "";

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 38,
              backgroundColor: AppColors.border,
              backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
              child: logoUrl == null
                  ? Text(emoji, style: const TextStyle(fontSize: 38))
                  : null,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.homeDark),
                  maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  // ── PRODUCT mode ───────────────────────────────────────────────────────────
  Widget _buildProductCard() {
    final logoUrl = store["logo_url"] as String?;
    final emoji   = store["emoji"]    as String? ?? "🍽️";
    final storeName = store["name"]   as String? ?? "";
    final product = store["product_data"] as Map<String, dynamic>?;
    final productName  = product?["name"]      as String? ?? "";
    final productPrice = (product?["price"]    as num?)?.toInt();
    final productImg   = product?["image_url"] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen del producto
            AspectRatio(
              aspectRatio: 1,
              child: productImg != null
                  ? Image.network(productImg, fit: BoxFit.cover, width: double.infinity,
                      errorBuilder: (_, __, ___) => _gradientPlaceholder(emoji))
                  : _gradientPlaceholder(emoji),
            ),
            // Info del producto
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Logo chico + nombre de la tienda
                Row(children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: AppColors.border,
                    backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                    child: logoUrl == null
                        ? Text(emoji, style: const TextStyle(fontSize: 10))
                        : null,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(storeName,
                        style: const TextStyle(fontSize: 10, color: AppColors.textLight),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 5),
                Text(productName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.homeDark),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                if (productPrice != null) ...[
                  const SizedBox(height: 3),
                  Text(_fmt(productPrice),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.homeOrange)),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage(String? coverUrl, String? logoUrl) {
    if (coverUrl != null) return Image.network(coverUrl, fit: BoxFit.cover, width: double.infinity,
        errorBuilder: (_, __, ___) => _gradientPlaceholder(store["emoji"] as String?));
    if (logoUrl != null) return Image.network(logoUrl, fit: BoxFit.cover, width: double.infinity,
        errorBuilder: (_, __, ___) => _gradientPlaceholder(store["emoji"] as String?));
    return _gradientPlaceholder(store["emoji"] as String?);
  }

  Widget _gradientPlaceholder(String? emoji) => Container(
    decoration: const BoxDecoration(gradient: AppColors.darkGradient),
    child: Center(child: Text(emoji ?? "🍽️", style: const TextStyle(fontSize: 40))),
  );

  Widget _badge(String text, Color color, {Color? textColor, bool bg = false}) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bg ? color.withOpacity(0.1) : color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(color: textColor ?? Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
  );
}
