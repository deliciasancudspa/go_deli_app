import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() { super.initState(); context.read<RiderProvider>().loadOrderHistory(); }

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    final STATUS = {"pending":"Pendiente","accepted":"Aceptado","preparing":"Preparando","ready":"Listo","assigned":"Asignado","picked_up":"Recogido","on_the_way":"En camino","delivered":"Entregado","cancelled":"Cancelado"};
    final COLORS = {"assigned":AppColors.warning,"picked_up":AppColors.info,"on_the_way":AppColors.accent,"delivered":AppColors.success,"cancelled":AppColors.error};
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Mis pedidos"), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go("/dashboard"))),
      body: RefreshIndicator(
        onRefresh: rider.loadOrderHistory,
        color: AppColors.accent,
        child: rider.orderHistory.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text("🛵", style: TextStyle(fontSize: 64)), SizedBox(height: 16), Text("Sin pedidos aun", style: TextStyle(fontSize: 16, color: AppColors.textLight, fontWeight: FontWeight.w600))]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rider.orderHistory.length,
              itemBuilder: (ctx, i) {
                final o = rider.orderHistory[i];
                final color = COLORS[o["status"]] ?? AppColors.textLight;
                return GestureDetector(
                  onTap: () { if (["assigned","picked_up","on_the_way"].contains(o["status"])) context.go("/order/${o["id"]}"); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      Text(o["stores"]?["emoji"] ?? "🍽️", style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o["stores"]?["name"] ?? "", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text("Total: \$${((o["total"] as num?)??0).toStringAsFixed(0)}", style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                      ])),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(STATUS[o["status"]]??o["status"], style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800))),
                    ]),
                  ),
                );
              },
            ),
      ),
    );
  }
}
