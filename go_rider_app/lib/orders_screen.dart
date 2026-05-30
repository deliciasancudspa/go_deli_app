import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.2), shape: BoxShape.circle),
                child: const Center(child: Text("⏳", style: TextStyle(fontSize: 48))),
              ),
              const SizedBox(height: 24),
              const Text("Solicitud en revision", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text("Hola ${rider.riderName}! Estamos revisando tu solicitud. Te notificaremos cuando sea aprobada.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15, height: 1.6)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  _step("✓", "Solicitud enviada", true),
                  _step("⏳", "Revision de documentos", false),
                  _step("○", "Aprobacion", false),
                  _step("○", "Listo para trabajar", false),
                ]),
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () => rider.signOut(),
                child: const Text("Cerrar sesion", style: TextStyle(color: Colors.white60)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _step(String icon, String label, bool done) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: done ? Colors.white : Colors.white38, fontWeight: done ? FontWeight.w700 : FontWeight.w400, fontSize: 14)),
    ]),
  );
}
