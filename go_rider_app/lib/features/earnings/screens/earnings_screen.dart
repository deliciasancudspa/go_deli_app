import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/utils/chile_time.dart";
import "../../../providers/rider_provider.dart";
import "../../../l10n/app_localizations.dart";

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  late DateTime _semanaStart; // Lunes 00:00 de la semana mostrada
  List<Map<String, dynamic>> _orders = [];
  String? _semanaStatus; // null=pendiente, "depositada", "rendida"
  bool _loading = true;
  bool _requestingPayment = false;
  final _sb = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _semanaStart = _getLunes(ChileTime.now());
    _load();
    _loadPaymentInfo();
  }

  Future<void> _loadPaymentInfo() async {
    final rider = context.read<RiderProvider>();
    await rider.loadPaymentRequests();
  }

  // ── Lógica de semana (lunes→domingo, igual que admin.html getLunes) ──
  DateTime _getLunes(DateTime date) {
    final d = date.weekday; // Monday=1 … Sunday=7
    final diff = date.day - d + 1;
    return DateTime(date.year, date.month, diff);
  }

  DateTime get _semanaEnd {
    final end = DateTime(_semanaStart.year, _semanaStart.month, _semanaStart.day + 6);
    return DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
  }

  String _semanaLabel() {
    String fmt(DateTime d) =>
        "${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}";
    return "${fmt(_semanaStart)} – ${fmt(_semanaEnd)}";
  }

  bool get _isCurrentWeek => _getLunes(ChileTime.now()) == _semanaStart;

  Future<void> _load() async {
    final rider = context.read<RiderProvider>();
    if (rider.riderId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      // Pedidos entregados de la semana
      final orders = await _sb.from("orders")
          .select("id, total, payment_method, status, created_at, rider_fee, delivery_distance, stores(name, emoji, logo_url)")
          .eq("deliverer_id", rider.riderId)
          .eq("status", "delivered")
          .gte("created_at", _semanaStart.toIso8601String())
          .lte("created_at", _semanaEnd.toIso8601String());

      // ¿Admin ya pagó/liquidó esta semana?
      String? status;
      try {
        final payments = await _sb.from("rider_payments")
            .select("amount")
            .eq("deliverer_id", rider.riderId)
            .gte("created_at", _semanaStart.toIso8601String())
            .lte("created_at", _semanaEnd.toIso8601String())
            .limit(1);
        final list = payments as List;
        if (list.isNotEmpty) {
          final amount = (list[0]["amount"] as num?)?.toDouble() ?? 0;
          status = amount >= 0 ? "depositada" : "rendida";
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(orders);
          _semanaStatus = status;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _semanaAnterior() {
    setState(() {
      _semanaStart = DateTime(_semanaStart.year, _semanaStart.month, _semanaStart.day - 7);
    });
    _load();
  }

  void _semanaSiguiente() {
    // No permitir ir a semanas futuras
    if (_isCurrentWeek) return;
    setState(() {
      _semanaStart = DateTime(_semanaStart.year, _semanaStart.month, _semanaStart.day + 7);
    });
    _load();
  }

  // rider_fee es calculado al crear la orden (checkout) y garantizado por el
  // trigger calculate_order_fees(). Solo puede ser null/0 en delivery propio.
  double _orderEarning(Map<String, dynamic> o) {
    return (o["rider_fee"] as num?)?.toDouble() ?? 0;
  }

  String _fmt(double n) => "\$${n.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  @override
  Widget build(BuildContext context) {
    final totalEarned = _orders.fold(0.0, (s, o) => s + _orderEarning(o) + ((o["tip_amount"] as num?)?.toDouble() ?? 0));

    // Propinas totales
    final totalTips = _orders.fold(0.0, (s, o) => s + ((o["tip_amount"] as num?)?.toDouble() ?? 0));

    // Ganancias de pedidos en efectivo: el rider ya las tiene en su bolsillo
    final cashEarnings = _orders
        .where((o) => o["payment_method"] == "cash")
        .fold(0.0, (s, o) => s + _orderEarning(o));

    // Ganancias de pedidos con tarjeta (plataforma debe transferir)
    final cardEarnings = totalEarned - cashEarnings - totalTips;

    // Total de efectivo que el rider cobró a clientes
    final cashHandled = _orders
        .where((o) => o["payment_method"] == "cash")
        .fold(0.0, (s, o) => s + ((o["total"] as num?)?.toDouble() ?? 0));

    // Lo que el rider debe rendir a la plataforma del efectivo cobrado
    final cashToRemit = cashHandled - cashEarnings;

    // Balance neto: positivo = plataforma le debe al rider, negativo = rider debe a plataforma
    final netBalance = cardEarnings - cashToRemit;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go("/dashboard");
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.earningsTitle),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go("/dashboard")),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.accent))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.accent,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Navegación semanal ──
                    _weekNav(),
                    const SizedBox(height: 16),

                    // ── Total ganado KPI ──
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.primary, Color(0xFF2d1b69)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(children: [
                        Text(AppLocalizations.of(context)!.earningsTotal,
                            style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(_fmt(totalEarned),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text("${_orders.length} ${AppLocalizations.of(context)!.earningsCompleted}",
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 13)),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // ── Balance neto: A recibir o A rendir ──
                    _balanceCard(netBalance),
                    const SizedBox(height: 16),

                    // ── Pago instantáneo ──
                    if (totalEarned > 0) _paymentRequestSection(rider, totalEarned),
                    const SizedBox(height: 24),

                    // ── Pedidos entregados ──
                    if (_orders.isNotEmpty) ...[
                      const Text("Pedidos entregados",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      ..._orders.map((o) => _orderRow(o)),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border)),
                        child: const Column(children: [
                          Text("🛵", style: TextStyle(fontSize: 40)),
                          SizedBox(height: 12),
                          Text("Sin entregas esta semana",
                              style: TextStyle(
                                  color: AppColors.textLight,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  // ── Navegación de semana: ← | fecha | → ──
  Widget _weekNav() {
    return Container(
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.accent),
          onPressed: _semanaAnterior,
          tooltip: "Semana anterior",
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              // Volver a la semana actual
              final current = _getLunes(ChileTime.now());
              if (_semanaStart != current) {
                setState(() => _semanaStart = current);
                _load();
              }
            },
            child: Text(
              _isCurrentWeek ? "Esta semana" : _semanaLabel(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.textDark),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right,
              color: _isCurrentWeek
                  ? AppColors.border
                  : AppColors.accent),
          onPressed: _isCurrentWeek ? null : _semanaSiguiente,
          tooltip: "Semana siguiente",
        ),
      ]),
    );
  }

  // ── Tarjeta de balance: "A recibir" (verde, positivo) o "A rendir" (naranja, negativo) ──
  Widget _balanceCard(double netBalance) {
    final bool positive = netBalance >= 0;
    final String label = positive ? AppLocalizations.of(context)!.earningsToReceive : AppLocalizations.of(context)!.earningsToRemit;
    final Color color = positive ? AppColors.success : AppColors.warning;
    final IconData icon =
        positive ? Icons.account_balance_wallet_outlined : Icons.swap_horiz;

    // Subtítulo según estado de la semana
    String subtitle;
    if (_semanaStatus == "depositada") {
      subtitle = "✅ Semana depositada";
    } else if (_semanaStatus == "rendida") {
      subtitle = "📋 Semana rendida";
    } else if (_isCurrentWeek) {
      subtitle = positive
          ? "Transferencia pendiente de la plataforma"
          : "Efectivo a devolver a la plataforma";
    } else {
      subtitle = "⏳ Pendiente de liquidación";
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_fmt(netBalance.abs()),
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: color)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textLight)),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Fila de pedido individual ──
  Widget _orderRow(Map<String, dynamic> o) {
    final store = (o["stores"] as Map<String, dynamic>?) ?? {};
    final storeLogo = store["logo_url"] as String?;
    final storeEmoji = store["emoji"] as String? ?? "🍽️";
    final storeName = store["name"] as String? ?? "Pedido";
    final earning = _orderEarning(o);
    final distMeters = (o["delivery_distance"] as num?)?.toInt();
    final distLabel = distMeters != null
        ? "${(distMeters / 1000).toStringAsFixed(1)} km"
        : null;
    final payMethod = o["payment_method"] as String?;
    final createdAt = DateTime.tryParse(o["created_at"] as String? ?? "");
    final timeLabel = createdAt != null
        ? "${createdAt.hour.toString().padLeft(2, "0")}:${createdAt.minute.toString().padLeft(2, "0")}"
        : "";

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        _storeAvatar(storeLogo, storeEmoji, size: 40),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(storeName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 3),
              Row(children: [
                if (distLabel != null) ...[
                  const Icon(Icons.route_outlined,
                      size: 13, color: AppColors.textLight),
                  const SizedBox(width: 3),
                  Text(distLabel,
                      style: const TextStyle(
                          color: AppColors.textLight, fontSize: 12)),
                  const SizedBox(width: 10),
                ],
                if (payMethod == "cash")
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(5)),
                    child: const Text("Efectivo",
                        style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                if (timeLabel.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(timeLabel,
                      style: const TextStyle(
                          color: AppColors.textLight, fontSize: 11)),
                ],
              ]),
            ])),
        Text(_fmt(earning),
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppColors.success)),
      ]),
    );
  }

  // ── Sección de pago instantáneo ──
  Widget _paymentRequestSection(RiderProvider rider, double totalEarned) {
    final canRequest = !rider.hasRequestedToday && (totalEarned > 2000);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.payments_outlined, color: AppColors.accent, size: 22),
          SizedBox(width: 8),
          Text("Retirar ganancias", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.accent)),
        ]),
        const SizedBox(height: 8),
        Text(
          canRequest ? "1 retiro disponible hoy" : "Ya retiraste hoy — disponible mañana",
          style: TextStyle(color: canRequest ? AppColors.textMedium : AppColors.textLight, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        if (canRequest) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _requestingPayment ? null : () => _showPaymentDialog(rider, totalEarned),
              icon: const Icon(Icons.account_balance_wallet, size: 18),
              label: const Text("Retirar ahora", style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                minimumSize: const Size(0, 46),
              ),
            ),
          ),
        ],
        // Historial de retiros
        if (rider.paymentRequests.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 8),
          const Text("Historial de retiros", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textLight)),
          const SizedBox(height: 8),
          ...rider.paymentRequests.take(5).map((r) {
            final status = r["status"] as String? ?? "pending";
            final statusColors = {"pending": AppColors.warning, "approved": AppColors.info, "completed": AppColors.success, "rejected": AppColors.error};
            final statusLabels = {"pending": "Pendiente", "approved": "Aprobado", "completed": "Transferido", "rejected": "Rechazado"};
            final date = DateTime.tryParse(r["requested_at"] as String? ?? "");
            final dateLabel = date != null ? "${date.day}/${date.month}" : "";
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Text(dateLabel, style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                const SizedBox(width: 8),
                Text("\$${((r["net_amount"] as num?) ?? 0).toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: (statusColors[status] ?? AppColors.textLight).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(statusLabels[status] ?? status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColors[status])),
                ),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Future<void> _showPaymentDialog(RiderProvider rider, double totalEarned) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.payments_outlined, color: AppColors.accent, size: 24),
          SizedBox(width: 10),
          Text("Retirar ganancias", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Ingresa el monto que deseas retirar:", style: TextStyle(color: AppColors.textMedium, fontSize: 13)),
            const SizedBox(height: 8),
            TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: "\$ ",
                hintText: "Ej: 15000",
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = int.tryParse(v ?? "");
                if (n == null || n < 2000) return "Mínimo \$2.000";
                if (n > totalEarned.toInt()) return "No puedes retirar más de lo ganado (\$${totalEarned.toStringAsFixed(0)})";
                return null;
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                SizedBox(width: 8),
                Expanded(child: Text("Comisión: \$990 por retiro. La transferencia la realiza el administrador.", style: TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w600))),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text("Solicitar retiro"),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final amount = int.tryParse(controller.text.trim()) ?? 0;
      if (amount < 2000) return;
      setState(() => _requestingPayment = true);
      final err = await rider.requestPayment(amount);
      if (mounted) {
        setState(() => _requestingPayment = false);
        if (err != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: AppColors.error));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Solicitud enviada. El administrador revisará tu retiro."), backgroundColor: AppColors.success));
        }
      }
    }

    controller.dispose();
  }

  // ── Avatar de tienda: logo_url con fallback a emoji ──
  static Widget _storeAvatar(String? logoUrl, String? emoji,
      {double size = 40}) {
    final fallback = Text(emoji ?? "🍽️",
        style: TextStyle(fontSize: size * 0.55));
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          logoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    }
    return SizedBox(width: size, height: size, child: Center(child: fallback));
  }
}
