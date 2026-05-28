import "package:flutter/material.dart";
import "../../../core/theme/app_theme.dart";
class ChatScreen extends StatelessWidget {
  final String orderId;
  const ChatScreen({super.key, required this.orderId});
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: const Text("Chat")), body: const Center(child: Text("Chat proximamente")));
}