import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";
class ProductDetailScreen extends StatelessWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: const Text("Producto")), body: const Center(child: Text("Proximamente")));
}