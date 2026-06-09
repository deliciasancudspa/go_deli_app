import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";

class CategoryChip extends StatelessWidget {
  final Map<String, dynamic> category;
  final bool isSelected;
  final VoidCallback onTap;
  const CategoryChip({super.key, required this.category, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color iconBg = const Color(0xFFFFF3E8);
    try {
      final hex = (category["color"] as String?)?.replaceAll("#", "");
      if (hex != null && hex.length == 6) iconBg = Color(int.parse("FF$hex", radix: 16));
    } catch (_) {}

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.homePurple.withOpacity(0.08) : Colors.white,
          border: Border.all(
              color: isSelected ? AppColors.homeOrange : AppColors.homeCardBorder,
              width: isSelected ? 2 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(category["emoji"] as String? ?? "🍽️",
                style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(height: 4),
          Text(category["name"] as String? ?? "",
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: isSelected ? AppColors.homeOrange : AppColors.homeDark)),
        ]),
      ),
    );
  }
}
