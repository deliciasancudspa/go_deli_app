import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;
  String? _error;

  Future<void> _login() async {
    final auth = context.read<AuthProvider>();
    final err = await auth.signIn(_emailCtrl.text.trim(), _passCtrl.text);
    if (err != null) setState(() => _error = 'Email o contraseÃ±a incorrectos');
    else if (mounted) context.go('/home');
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
    prefixIcon: Icon(icon, color: AppColors.primary),
    filled: true, fillColor: const Color(0xFF0F1923),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
        const SizedBox(height: 40),
        Column(children: [
          Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)), child: const Center(child: Text('ðŸ›µ', style: TextStyle(fontSize: 36)))),
          const SizedBox(height: 16),
          const Text('Go Deli', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Bienvenido de vuelta', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15)),
        ]),
        const SizedBox(height: 40),
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF1A2636), borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Iniciar sesiÃ³n', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: Colors.white), decoration: _dec('Correo electrÃ³nico', Icons.email_outlined)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passCtrl, obscureText: _obscure, style: const TextStyle(color: Colors.white),
            decoration: _dec('ContraseÃ±a', Icons.lock_outline).copyWith(suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38), onPressed: () => setState(() => _obscure = !_obscure))),
            onFieldSubmitted: (_) => _login(),
          ),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))],
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () {}, child: const Text('Â¿Olvidaste tu contraseÃ±a?', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)))),
          ElevatedButton(onPressed: auth.loading ? null : _login, child: auth.loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Entrar')),
        ])),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Â¿No tienes cuenta? ', style: TextStyle(color: Colors.white60)),
          GestureDetector(onTap: () => context.go('/register'), child: const Text('RegÃ­strate', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800))),
        ]),
      ]))),
    );
  }
}
