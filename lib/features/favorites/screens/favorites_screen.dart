import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../home/widgets/store_card.dart";

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;
  final _sb = Supabase.instance.client;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final user = _sb.auth.currentUser;
      if (user == null) { setState(() => _loading = false); return; }
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).single();
      final favs = await _sb.from("user_favorites").select("stores(*)").eq("user_id", u["id"]);
      if (mounted) setState(() {
        _favorites = (favs as List).map((f) => f["stores"] as Map<String, dynamic>).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Mis favoritos"),
        backgroundColor: Colors.transparent,
        flexibleSpace: const GradientFlexibleSpace(),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _favorites.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.favorite_outline, size: 64, color: AppColors.border),
              const SizedBox(height: 16),
              const Text("Aun no tienes favoritos", style: TextStyle(fontSize: 16, color: AppColors.textLight, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text("Explora tiendas y agrega tus favoritas", style: TextStyle(color: AppColors.textLight, fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => context.go("/home"), child: const Text("Explorar tiendas")),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _favorites.length,
              itemBuilder: (ctx, i) => StoreCard(store: _favorites[i], onTap: () => context.push("/store/${_favorites[i]["id"]}")),
            ),
    );
  }
}
