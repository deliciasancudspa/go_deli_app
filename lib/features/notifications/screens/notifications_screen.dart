import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: const Text("Notificaciones")), body: const Center(child: Text("Notificaciones proximamente")));
}