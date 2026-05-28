import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";

class StoreCard extends StatelessWidget {
  final Map<String, dynamic> store;
  final VoidCallback onTap;
  const StoreCard({super.key, required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Stack(children: [
              store["cover_url"] != null
                ? Image.network(store["cover_url"], height: 130, width: double.infinity, fit: BoxFit.cover)
                : Container(
                    height: 130, width: double.infinity,
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                    child: Center(child: Text(store["emoji"] ?? "X", style: const TextStyle(fontSize: 50))),
                  ),
              if (!(store["is_open"] ?? true))
                Container(height: 130, width: double.infinity, color: Colors.black54,
                  child: const Center(child: Text("CERRADO", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 4)))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(store["name"] ?? "", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 4),
              Text(store["category"] ?? "", style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.star, color: Colors.amber, size: 14), const SizedBox(width: 3),
                Text("${store["rating"] ?? 5.0}", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                const Icon(Icons.access_time, size: 14, color: AppColors.textLight), const SizedBox(width: 3),
                Text("${store["delivery_time"] ?? "30-45"} min", style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
                const SizedBox(width: 12),
                const Icon(Icons.delivery_dining, size: 14, color: AppColors.textLight), const SizedBox(width: 3),
                Text("\$${((store["delivery_fee"] ?? 2990) as num).toStringAsFixed(0)}", style: const TextStyle(fontSize: 13, color: AppColors.textLight)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
