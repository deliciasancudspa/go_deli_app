import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: const Text("Mis favoritos")), body: const Center(child: Text("Aun no tienes favoritos", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600))));
}