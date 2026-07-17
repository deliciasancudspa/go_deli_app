import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});
  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  final _sb = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) return;
    try {
      final result = await _sb.rpc("get_rider_performance", params: {"p_rider_id": rider.riderId});
      final list = result as List;
      if (mounted && list.isNotEmpty) {
        setState(() { _data = list[0]; _loading = false; });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(dynamic n) {
    final d = (n as num?)?.toDouble() ?? 0;
    return "\$${d.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
  }

  Widget _kpiCard(String label, String value, String subtitle, IconData icon, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        ]),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight)),
        Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Mi desempeño"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : _data == null
          ? const Center(child: Text("Sin datos aún", style: TextStyle(color: AppColors.textLight)))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.accent,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // ── Top % ──
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF2d1b69)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(children: [
                    const Text("🏆", style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 8),
                    Text("Top ${_data!["top_percent"] ?? "—"}%",
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text("de riders esta semana",
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── KPIs ──
                Row(children: [
                  _kpiCard("Pedidos entregados", "${_data!["total_deliveries"] ?? 0}",
                      "Total histórico", Icons.delivery_dining, AppColors.accent),
                  const SizedBox(width: 10),
                  _kpiCard("Calificación", "${_data!["avg_rating"] ?? "—"}",
                      "${_data!["rating_count"] ?? 0} calificaciones", Icons.star, Colors.amber),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _kpiCard("Ganancias totales", _fmt(_data!["total_earnings"] ?? 0),
                      "Delivery + propinas", Icons.attach_money, AppColors.success),
                  const SizedBox(width: 10),
                  _kpiCard("Distancia recorrida", "${(_data!["total_distance_km"] ?? 0).toStringAsFixed(0)} km",
                      "Total histórico", Icons.route_outlined, AppColors.info),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("Métricas de calidad", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 12),
                    _progressBar("Entregas sin cancelar",
                      ((_data!["total_deliveries"] ?? 0) as num).toDouble(),
                      ((_data!["total_deliveries"] ?? 0) as num).toDouble() + ((_data!["cancellations"] ?? 0) as num).toDouble(),
                      AppColors.success),
                    const SizedBox(height: 10),
                    _progressBar("Calificación promedio",
                      ((_data!["avg_rating"] ?? 0) as num).toDouble(), 5.0, Colors.amber),
                  ]),
                ),
                const SizedBox(height: 24),
                // ── Tips section ──
                if (((_data!["total_tips"] ?? 0) as num).toDouble() > 0)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.card_giftcard, color: AppColors.warning, size: 22),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text("🎁 Propinas recibidas", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(_fmt(_data!["total_tips"]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.warning)),
                      ]),
                    ]),
                  ),
              ]),
            ),
    );
  }

  Widget _progressBar(String label, double value, double max, Color color) {
    final pct = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMedium)),
        Text("${(pct * 100).toStringAsFixed(0)}%", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: pct, backgroundColor: color.withOpacity(0.12), valueColor: AlwaysStoppedAnimation(color), minHeight: 8),
      ),
    ]);
  }
}
