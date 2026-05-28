import "package:flutter/material.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});
  @override State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}
class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  final _sb = Supabase.instance.client;
  final _labels = {"pending": "Pendiente", "accepted": "Aceptado", "preparing": "Preparando", "ready": "Listo", "on_the_way": "En camino", "delivered": "Entregado", "cancelled": "Cancelado"};
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final user = _sb.auth.currentUser; if (user == null) return;
    final u = await _sb.from("users").select("id").eq("auth_id", user.id).single();
    final o = await _sb.from("orders").select("*, stores(name,emoji)").eq("client_id", u["id"]).order("created_at", ascending: false);
    if (mounted) setState(() { _orders = List<Map<String, dynamic>>.from(o); _loading = false; });
  }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.background, appBar: AppBar(title: const Text("Mis pedidos")),
    body: _loading ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) : _orders.isEmpty ? const Center(child: Text("Aun no tienes pedidos", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600))) :
    ListView.builder(padding: const EdgeInsets.all(16), itemCount: _orders.length, itemBuilder: (ctx, i) {
      final o = _orders[i];
      return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("${o["stores"]?["name"] ?? ""}", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(height: 4), Text("\$${((o["total"] ?? 0) as num).toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))]),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(_labels[o["status"]] ?? o["status"], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary))),
      ]));
    }),
  );
}