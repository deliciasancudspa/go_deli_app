import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/auth_provider.dart";
import "../../../providers/theme_provider.dart";
import "../../../providers/language_provider.dart";

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Widget _tile(IconData icon, String label, VoidCallback onTap, {String? trailing}) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (trailing != null) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)), child: Text(trailing, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: AppColors.textLight, size: 18),
      ]),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth  = context.watch<AuthProvider>();
    final theme = context.watch<ThemeProvider>();
    final lang  = context.watch<LanguageProvider>();
    final p = auth.profile;
    final name = p?["name"] ?? "Usuario";
    final email = p?["email"] ?? "";
    final phone = p?["phone"] ?? "";

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: AppColors.secondary,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.go("/home")),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(color: AppColors.secondary),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(height: 40),
                CircleAvatar(
                  radius: 44,
                  backgroundColor: AppColors.primary,
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : "U",
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 12),
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                if (email.isNotEmpty) Text(email, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                if (phone.isNotEmpty) Text(phone, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ]),
            ),
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            // Stats row
            Row(children: [
              Expanded(child: _statCard("0", "Pedidos")),
              const SizedBox(width: 12),
              Expanded(child: _statCard("0", "Favoritos")),
              const SizedBox(width: 12),
              Expanded(child: _statCard("\$0", "Ahorrado")),
            ]),
            const SizedBox(height: 20),

            // Seccion pedidos
            _sectionHeader("Mi cuenta"),
            Container(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: Column(children: [
                _tile(Icons.receipt_long_outlined, "Mis pedidos", () => context.push("/orders")),
                _divider(),
                _tile(Icons.favorite_outline, "Mis favoritos", () => context.push("/favorites")),
                _divider(),
                _tile(Icons.location_on_outlined, "Mis direcciones", () => _showAddresses(context, p)),
                _divider(),
                _tile(Icons.credit_card_outlined, "Metodos de pago", () => _showPayments(context)),
                _divider(),
                _tile(Icons.local_offer_outlined, "Mis cupones", () => _showCoupons(context), trailing: "0"),
              ]),
            ),
            const SizedBox(height: 16),

            // Seccion ajustes
            _sectionHeader("Ajustes"),
            Container(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: Column(children: [
                ListTile(
                  leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.dark_mode_outlined, color: AppColors.primary, size: 18)),
                  title: const Text("Modo oscuro", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  trailing: Switch(value: theme.isDark, onChanged: (_) => theme.toggleTheme(), activeColor: AppColors.primary),
                ),
                _divider(),
                ListTile(
                  leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.language_outlined, color: AppColors.primary, size: 18)),
                  title: const Text("Idioma", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  trailing: DropdownButton<String>(
                    value: lang.language, underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: "es", child: Text("Espanol")),
                      DropdownMenuItem(value: "en", child: Text("English")),
                    ],
                    onChanged: (v) => lang.setLanguage(v!),
                  ),
                ),
                _divider(),
                _tile(Icons.headset_mic_outlined, "Soporte", () => _showSupport(context)),
                _divider(),
                _tile(Icons.info_outline, "Acerca de Go Deli", () => _showAbout(context)),
              ]),
            ),
            const SizedBox(height: 16),

            // Cerrar sesion
            Container(
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: ListTile(
                leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.logout, color: AppColors.error, size: 18)),
                title: const Text("Cerrar sesion", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 14)),
                onTap: () async {
                  final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                    title: const Text("Cerrar sesion"),
                    content: const Text("Esta seguro que deseas cerrar sesion?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Salir", style: TextStyle(color: AppColors.error))),
                    ],
                  ));
                  if (confirm == true) {
                    await auth.signOut();
                    if (context.mounted) context.go("/login");
                  }
                },
              ),
            ),
            const SizedBox(height: 32),
            Text("Go Deli v1.0.0", style: TextStyle(color: AppColors.textLight, fontSize: 12)),
            const SizedBox(height: 8),
          ]),
        )),
      ]),
    );
  }

  Widget _statCard(String value, String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primary)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textLight, letterSpacing: 0.5))),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 16, endIndent: 16);

  void _showAddresses(BuildContext context, Map<String, dynamic>? profile) {
    showModalBottomSheet(context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Mis direcciones", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        if (profile?["address"] != null)
          ListTile(leading: const Icon(Icons.home_outlined, color: AppColors.primary), title: Text(profile!["address"]), subtitle: const Text("Casa"))
        else
          const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Sin direcciones guardadas", style: TextStyle(color: AppColors.textLight)))),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
      ]),
    ));
  }

  void _showPayments(BuildContext context) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Metodos de pago", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _paymentTile("Efectivo", Icons.payments_outlined),
        _paymentTile("Tarjeta de credito/debito", Icons.credit_card),
        _paymentTile("Transferencia bancaria", Icons.account_balance_outlined),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
      ]),
    ));
  }

  Widget _paymentTile(String label, IconData icon) {
    return ListTile(leading: Icon(icon, color: AppColors.primary), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)));
  }

  void _showCoupons(BuildContext context) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Mis cupones", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        const Icon(Icons.local_offer_outlined, size: 48, color: AppColors.textLight),
        const SizedBox(height: 12),
        const Text("Sin cupones disponibles", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
      ]),
    ));
  }

  void _showSupport(BuildContext context) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Centro de ayuda", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        ListTile(leading: const Icon(Icons.chat_outlined, color: AppColors.primary), title: const Text("Chat con soporte"), subtitle: const Text("Respuesta en minutos")),
        ListTile(leading: const Icon(Icons.email_outlined, color: AppColors.primary), title: const Text("soporte@godeli.cl")),
        ListTile(leading: const Icon(Icons.phone_outlined, color: AppColors.primary), title: const Text("+56 9 xxxx xxxx")),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cerrar")),
      ]),
    ));
  }

  void _showAbout(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Go Deli v1.0.0"),
      content: const Text("Plataforma de delivery conectando clientes con los mejores restaurantes y tiendas locales."),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
    ));
  }
}
