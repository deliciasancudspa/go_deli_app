import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  String _period = "week";
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  final _sb = Supabase.instance.client;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) { setState(() => _loading = false); return; }
    setState(() => _loading = true);
    try {
      final from = _getFromDate();
      final orders = await _sb.from("orders")
          .select("id, total, payment_method, status, created_at, rider_fee, delivery_distance, stores(name, emoji)")
          .eq("deliverer_id", rider.riderId)
          .eq("status", "delivered")
          .gte("created_at", from.toIso8601String());
      final payments = await _sb.from("rider_payments")
          .select("*")
          .eq("deliverer_id", rider.riderId)
          .order("paid_at", ascending: false)
          .limit(10);
      if (mounted) setState(() {
        _orders   = List<Map<String, dynamic>>.from(orders);
        _payments = List<Map<String, dynamic>>.from(payments);
        _loading  = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  DateTime _getFromDate() {
    final now = DateTime.now();
    if (_period == "day")   return DateTime(now.year, now.month, now.day);
    if (_period == "week")  return now.subtract(const Duration(days: 7));
    return now.subtract(const Duration(days: 30));
  }

  // Use rider_fee if available, otherwise fall back to 15% of total
  double _orderEarning(Map<String, dynamic> o) {
    final rf = (o["rider_fee"] as num?)?.toDouble();
    if (rf != null && rf > 0) return rf;
    return ((o["total"] as num) * 0.15);
  }

  String _fmt(double n) => "\$${n.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  @override
  Widget build(BuildContext context) {
    final totalEarned  = _orders.fold(0.0, (s, o) => s + _orderEarning(o));
    final cashReceived = _orders.where((o) => o["payment_method"] == "cash")
        .fold(0.0, (s, o) => s + ((o["total"] as num).toDouble()));
    final toDeposit    = totalEarned - cashReceived;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) context.go("/dashboard"); },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text("Mis ganancias"),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go("/dashboard")),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.accent,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  // Period selector
                  Container(
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      _periodBtn("Hoy", "day"), _periodBtn("Semana", "week"), _periodBtn("Mes", "month"),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Total earned KPI
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF2d1b69)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(children: [
                      const Text("Total ganado", style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(_fmt(totalEarned), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text("${_orders.length} pedidos completados",
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  Row(children: [
                    Expanded(child: _statCard("Efectivo recibido", _fmt(cashReceived), AppColors.warning, "Descontado de tu pago")),
                    const SizedBox(width: 12),
                    Expanded(child: _statCard("A depositar", _fmt(toDeposit.abs()), AppColors.success, "Transferencia pendiente")),
                  ]),
                  const SizedBox(height: 24),

                  // Per-order history
                  if (_orders.isNotEmpty) ...[
                    const Text("Pedidos entregados", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    ..._orders.map((o) => _orderRow(o)),
                    const SizedBox(height: 8),
                  ],

                  // Payments received
                  const Text("Pagos recibidos", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  if (_payments.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                      child: const Column(children: [
                        Text("💰", style: TextStyle(fontSize: 40)),
                        SizedBox(height: 12),
                        Text("Sin pagos registrados aun", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                      ]),
                    )
                  else
                    ..._payments.map((p) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                      child: Row(children: [
                        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.check_circle, color: AppColors.success, size: 22)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text("Pago recibido", style: TextStyle(fontWeight: FontWeight.w700)),
                          if (p["reference"] != null) Text("Ref: ${p["reference"]}", style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                        ])),
                        Text(_fmt((p["amount"] as num?)?.toDouble() ?? 0), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.success)),
                      ]),
                    )),
                ]),
              ),
      ),
    );
  }

  Widget _orderRow(Map<String, dynamic> o) {
    final store       = (o["stores"] as Map<String, dynamic>?) ?? {};
    final storeEmoji  = store["emoji"] as String? ?? "🍽️";
    final storeName   = store["name"] as String? ?? "Pedido";
    final earning     = _orderEarning(o);
    final distMeters  = (o["delivery_distance"] as num?)?.toInt();
    final distLabel   = distMeters != null ? "${(distMeters / 1000).toStringAsFixed(1)} km" : null;
    final payMethod   = o["payment_method"] as String?;
    final createdAt   = DateTime.tryParse(o["created_at"] as String? ?? "");
    final timeLabel   = createdAt != null
        ? "${createdAt.hour.toString().padLeft(2, "0")}:${createdAt.minute.toString().padLeft(2, "0")}"
        : "";

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Text(storeEmoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(storeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 3),
          Row(children: [
            if (distLabel != null) ...[
              const Icon(Icons.route_outlined, size: 13, color: AppColors.textLight),
              const SizedBox(width: 3),
              Text(distLabel, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
              const SizedBox(width: 10),
            ],
            if (payMethod == "cash")
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
                child: const Text("Efectivo", style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            if (timeLabel.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(timeLabel, style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
            ],
          ]),
        ])),
        Text(_fmt(earning), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.success)),
      ]),
    );
  }

  Widget _periodBtn(String label, String value) => Expanded(
    child: GestureDetector(
      onTap: () { setState(() => _period = value); _load(); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: _period == value ? AppColors.accent : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, color: _period == value ? Colors.white : AppColors.textMedium, fontSize: 14)),
      ),
    ),
  );

  Widget _statCard(String label, String value, Color color, String sub) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
      const SizedBox(height: 4),
      Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
    ]),
  );
}
