import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../home/widgets/store_card.dart";

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String _filter = "all";
  final _sb = Supabase.instance.client;

  final _filters = [
    {"id": "all", "label": "Todos"},
    {"id": "open", "label": "Abiertos"},
    {"id": "fast", "label": "Rapido"},
    {"id": "cheap", "label": "Envio barato"},
    {"id": "rated", "label": "Mejor rating"},
  ];

  Future<void> _search(String q) async {
    if (q.isEmpty) { setState(() => _results = []); return; }
    setState(() => _loading = true);
    try {
      var query = _sb.from("stores").select().eq("status", "approved").ilike("name", "%$q%");
      if (_filter == "open") query = query.eq("is_open", true);
      final res = await query;
      var list = List<Map<String, dynamic>>.from(res);
      if (_filter == "rated") list.sort((a, b) => ((b["rating"] ?? 0) as num).compareTo((a["rating"] ?? 0) as num));
      if (_filter == "cheap") list.sort((a, b) => ((a["delivery_fee"] ?? 0) as num).compareTo((b["delivery_fee"] ?? 0) as num));
      if (_filter == "fast") list.sort((a, b) => ((a["delivery_time"] ?? "") as String).compareTo((b["delivery_time"] ?? "") as String));
      if (mounted) setState(() { _results = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: const GradientFlexibleSpace(),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
        title: TextField(
          controller: _ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Buscar tiendas...",
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.70)),
            border: InputBorder.none, filled: false,
          ),
          onChanged: _search,
        ),
      ),
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: AppColors.mainGradient),
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(height: 36, child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filters.length,
            itemBuilder: (ctx, i) {
              final f = _filters[i];
              final selected = _filter == f["id"];
              return GestureDetector(
                onTap: () { setState(() => _filter = f["id"]!); _search(_ctrl.text); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: selected ? AppColors.primary : Colors.white12, borderRadius: BorderRadius.circular(20)),
                  child: Text(f["label"]!, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              );
            },
          )),
        ),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _ctrl.text.isEmpty
              ? const Center(child: Text("Busca tiendas o productos", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)))
              : _results.isEmpty
                ? const Center(child: Text("Sin resultados", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) => StoreCard(store: _results[i], onTap: () => context.push("/store/${_results[i]["id"]}")),
                  ),
        ),
      ]),
    );
  }
}
