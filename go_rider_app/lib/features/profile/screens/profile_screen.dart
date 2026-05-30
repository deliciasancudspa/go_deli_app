import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    final bankList = rider.rider?["deliverer_bank_info"];
    final bank = (bankList is List && bankList.isNotEmpty) ? bankList[0] as Map<String, dynamic> : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Mi perfil"), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go("/dashboard"))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Column(children: [
          CircleAvatar(radius: 44, backgroundColor: AppColors.accent, child: Text(rider.riderName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900))),
          const SizedBox(height: 12),
          Text(rider.riderName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(rider.user?["email"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: rider.isApproved ? AppColors.success.withOpacity(0.1) : AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(rider.isApproved ? "Repartidor aprobado" : "En revision", style: TextStyle(color: rider.isApproved ? AppColors.success : AppColors.warning, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ])),
        const SizedBox(height: 24),
        _card("Mi vehiculo", [
          _row("Tipo", rider.rider?["vehicle_type"] ?? "-"),
          if (rider.rider?["vehicle_plate"] != null) _row("Patente", rider.rider!["vehicle_plate"]),
        ]),
        const SizedBox(height: 12),
        _card("Datos bancarios", bank != null ? [
          _row("Banco", bank["bank_name"] ?? "-"),
          _row("Tipo cuenta", bank["account_type"] ?? "-"),
          _row("Numero cuenta", bank["account_number"] ?? "-"),
          _row("Titular", bank["account_holder"] ?? "-"),
          _row("RUT", bank["rut"] ?? "-"),
        ] : [const Padding(padding: EdgeInsets.all(8), child: Text("Sin datos bancarios", style: TextStyle(color: AppColors.textLight)))]),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () async { await rider.signOut(); if (context.mounted) context.go("/login"); },
          icon: const Icon(Icons.logout),
          label: const Text("Cerrar sesion"),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
        ),
        const SizedBox(height: 32),
        const Text("Go Rider v1.0.0", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textLight, fontSize: 12)),
      ]),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMedium)),
      const SizedBox(height: 12), const Divider(height: 1), const SizedBox(height: 8),
      ...children,
    ]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    ]),
  );
}
