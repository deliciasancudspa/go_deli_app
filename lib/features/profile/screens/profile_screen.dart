import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/auth_provider.dart";
import "../../../providers/theme_provider.dart";
import "../../../providers/language_provider.dart";
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  Widget _tile(IconData icon, String label, VoidCallback onTap) => ListTile(leading: Icon(icon, color: AppColors.primary), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)), trailing: const Icon(Icons.chevron_right, color: AppColors.textLight), onTap: onTap);
  @override Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>(); final theme = context.watch<ThemeProvider>(); final lang = context.watch<LanguageProvider>(); final p = auth.profile;
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: const Text("Mi perfil")), body: ListView(padding: const EdgeInsets.all(16), children: [
      Center(child: Column(children: [CircleAvatar(radius: 40, backgroundColor: AppColors.primary, child: Text((p?["name"] ?? "U")[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900))), const SizedBox(height: 12), Text(p?["name"] ?? "", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), Text(p?["email"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 14))])),
      const SizedBox(height: 24),
      _tile(Icons.receipt_long_outlined, "Mis pedidos", () => context.push("/orders")),
      _tile(Icons.location_on_outlined, "Mis direcciones", () {}),
      _tile(Icons.credit_card_outlined, "Metodos de pago", () {}),
      const Divider(),
      ListTile(leading: const Icon(Icons.dark_mode_outlined), title: const Text("Modo oscuro", style: TextStyle(fontWeight: FontWeight.w700)), trailing: Switch(value: theme.isDark, onChanged: (_) => theme.toggleTheme(), activeColor: AppColors.primary)),
      ListTile(leading: const Icon(Icons.language_outlined), title: const Text("Idioma", style: TextStyle(fontWeight: FontWeight.w700)), trailing: DropdownButton<String>(value: lang.language, underline: const SizedBox(), items: const [DropdownMenuItem(value: "es", child: Text("Espanol")), DropdownMenuItem(value: "en", child: Text("English"))], onChanged: (v) => lang.setLanguage(v!))),
      const Divider(),
      ListTile(leading: const Icon(Icons.logout, color: AppColors.error), title: const Text("Cerrar sesion", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)), onTap: () async { await auth.signOut(); if (context.mounted) context.go("/login"); }),
    ]));
  }
}