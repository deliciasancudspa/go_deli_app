import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";

class CategoryChip extends StatelessWidget {
  final Map<String, dynamic> category;
  final bool isSelected;
  final VoidCallback onTap;
  const CategoryChip({super.key, required this.category, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.secondary : AppColors.surface,
          border: Border.all(color: isSelected ? AppColors.secondary : AppColors.border, width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(category["emoji"] as String, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(category["name"] as String, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isSelected ? AppColors.primary : AppColors.textMedium)),
        ]),
      ),
    );
  }
}
