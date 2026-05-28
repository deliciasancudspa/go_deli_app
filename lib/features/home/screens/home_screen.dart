import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String,dynamic>> _stores = [];
  bool _loading = true;
  final _sb = Supabase.instance.client;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final stores = await _sb.from('stores').select().eq('status','approved').eq('is_active',true);
    if (mounted) setState(() { _stores = List<Map<String,dynamic>>.from(stores); _loading = false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Go Deli')),
    body: _loading ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) :
      _stores.isEmpty ? const Center(child: Text('No hay restaurantes')) :
      ListView.builder(itemCount: _stores.length, itemBuilder: (_,i) => Card(child: ListTile(title: Text(_stores[i]['name'] ?? ''), subtitle: Text(_stores[i]['category'] ?? ''), onTap: () => context.push('/store/'))))
  );
}
