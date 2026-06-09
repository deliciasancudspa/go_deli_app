import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";

class StoreCard extends StatelessWidget {
  final Map<String, dynamic> store;
  final VoidCallback onTap;
  const StoreCard({super.key, required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final logoUrl   = store["logo_url"]   as String?;
    final sponsored = store["sponsored"] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.homeCardBorder),
          boxShadow: [BoxShadow(color: AppColors.homePurple.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: SizedBox(
              width: 96, height: 96,
              child: logoUrl != null
                  ? Image.network(logoUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(store["name"] ?? "",
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.homeDark),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (sponsored) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.homeOrange, borderRadius: BorderRadius.circular(6)),
                    child: const Text("Destacado",
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                  if (!(store["is_open"] ?? true)) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Text("Cerrado",
                        style: TextStyle(color: AppColors.error, fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(store["category"] ?? "",
                    style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.star_rounded, color: AppColors.homeOrange, size: 14),
                  Text(" ${store["rating"] ?? "5.0"}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Text("·", style: TextStyle(color: AppColors.textLight)),
                  ),
                  const Icon(Icons.access_time_rounded, size: 13, color: AppColors.textLight),
                  Text(" ${store["delivery_time"] ?? "30-45"} min",
                      style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.delivery_dining, size: 13, color: AppColors.textLight),
                  Builder(builder: (_) {
                    final clientFee = (store["delivery_fee_client"] as num?)?.toInt() ?? 0;
                    return Text(
                      clientFee == 0 ? "  Gratis" : "  \$$clientFee",
                      style: TextStyle(fontSize: 12, color: clientFee == 0 ? AppColors.primary : AppColors.textLight, fontWeight: clientFee == 0 ? FontWeight.w700 : FontWeight.normal),
                    );
                  }),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.homeDark,
    child: Center(child: Text(store["emoji"] ?? "🍽️",
        style: const TextStyle(fontSize: 32))),
  );
}
