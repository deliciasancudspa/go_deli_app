import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";
import "../../../l10n/app_localizations.dart";

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static Widget _storeAvatar(String? logoUrl, String? emoji, {double size = 40}) {
    final fallback = Text(emoji ?? "🍽️", style: TextStyle(fontSize: size * 0.55));
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(logoUrl, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    }
    return SizedBox(width: size, height: size, child: Center(child: fallback));
  }

  @override
  void initState() { super.initState(); context.read<RiderProvider>().loadOrderHistory(); }

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    final STATUS = {"pending":AppLocalizations.of(context)!.ordersStatusPending,"accepted":AppLocalizations.of(context)!.ordersStatusAccepted,"preparing":AppLocalizations.of(context)!.ordersStatusPreparing,"ready":AppLocalizations.of(context)!.ordersStatusReady,"assigned":AppLocalizations.of(context)!.ordersStatusAssigned,"picked_up":AppLocalizations.of(context)!.orderPickedUp,"on_the_way":AppLocalizations.of(context)!.orderOnTheWay,"delivered":AppLocalizations.of(context)!.orderDelivered,"cancelled":AppLocalizations.of(context)!.orderCancelled,"returned":AppLocalizations.of(context)!.orderReturned};
    final COLORS = {"assigned":AppColors.warning,"picked_up":AppColors.info,"on_the_way":AppColors.accent,"delivered":AppColors.success,"cancelled":AppColors.error,"returned":AppColors.warning};
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go("/dashboard");
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.ordersTitle), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go("/dashboard"))),
      body: RefreshIndicator(
        onRefresh: rider.loadOrderHistory,
        color: AppColors.accent,
        child: rider.orderHistory.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Text("🛵", style: TextStyle(fontSize: 64)), const SizedBox(height: 16), Text(AppLocalizations.of(context)!.ordersEmpty, style: const TextStyle(fontSize: 16, color: AppColors.textLight, fontWeight: FontWeight.w600))]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rider.orderHistory.length,
              itemBuilder: (ctx, i) {
                final o = rider.orderHistory[i];
                final color = COLORS[o["status"]] ?? AppColors.textLight;
                return GestureDetector(
                  onTap: () { if (["assigned","picked_up","on_the_way"].contains(o["status"])) context.push("/order/${o["id"]}"); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      _storeAvatar(o["stores"]?["logo_url"] as String?, o["stores"]?["emoji"] as String?, size: 42),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o["stores"]?["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text("Total: \$${((o["total"] as num?)??0).toStringAsFixed(0)}", style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                        () {
                          final createdAt = DateTime.tryParse(o["created_at"] as String? ?? "");
                          if (createdAt == null) return const SizedBox.shrink();
                          final time = "${createdAt.hour.toString().padLeft(2, "0")}:${createdAt.minute.toString().padLeft(2, "0")}";
                          final date = "${createdAt.day.toString().padLeft(2, "0")}/${createdAt.month.toString().padLeft(2, "0")}/${createdAt.year}";
                          return Text("$time · $date", style: const TextStyle(color: AppColors.textLight, fontSize: 11));
                        }(),
                      ])),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(STATUS[o["status"]]??o["status"], style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800))),
                    ]),
                  ),
                );
              },
            ),
        ),
      ),
    );
  }
}
