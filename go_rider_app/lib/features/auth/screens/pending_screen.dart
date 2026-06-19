import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _subscribeApproval();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeApproval() {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) return;
    _channel = Supabase.instance.client
        .channel("rider_approval_${rider.riderId}")
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: "public",
          table: "deliverers",
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: "id",
            value: rider.riderId,
          ),
          callback: (payload) {
            final status = payload.newRecord["status"] as String?;
            if (status == "approved" && mounted) {
              // Recargar perfil para obtener el nuevo estado
              rider.reloadProfile();
            }
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    // Si fue aprobado, navegar al dashboard
    if (rider.isApproved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go("/dashboard");
      });
    }
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 100, height: 100, decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.2), shape: BoxShape.circle), child: const Center(child: Text("⏳", style: TextStyle(fontSize: 48)))),
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
              _step(rider.isApproved ? "✓" : "⏳", "Revision de documentos", rider.isApproved),
              _step(rider.isApproved ? "✓" : "○", "Aprobacion", rider.isApproved),
              _step(rider.isApproved ? "✓" : "○", "Listo para trabajar", rider.isApproved),
            ]),
          ),
          const SizedBox(height: 32),
          TextButton(onPressed: () => rider.signOut(), child: const Text("Cerrar sesion", style: TextStyle(color: Colors.white60))),
        ]),
      ))),
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
