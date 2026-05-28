import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../home/widgets/store_card.dart";

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override State<SearchScreen> createState() => _SearchScreenState();
}
class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  final _sb = Supabase.instance.client;
  Future<void> _search(String q) async {
    if (q.isEmpty) { setState(() => _results = []); return; }
    setState(() => _loading = true);
    final res = await _sb.from("stores").select().eq("status", "approved").ilike("name", "%$q%");
    if (mounted) setState(() { _results = List<Map<String, dynamic>>.from(res); _loading = false; });
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(backgroundColor: AppColors.secondary, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
      title: TextField(controller: _ctrl, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Buscar...", hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none, filled: false), onChanged: _search)),
    body: _loading ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) :
      _results.isEmpty && _ctrl.text.isNotEmpty ? const Center(child: Text("Sin resultados", style: TextStyle(color: AppColors.textLight))) :
      ListView.builder(padding: const EdgeInsets.all(16), itemCount: _results.length, itemBuilder: (ctx, i) => StoreCard(store: _results[i], onTap: () => context.push("/store/${_results[i]["id"]}"))),
  );
}
