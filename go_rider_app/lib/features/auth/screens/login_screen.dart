import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;
  String? _error;

  Future<void> _login() async {
    final rider = context.read<RiderProvider>();
    final err = await rider.signIn(_emailCtrl.text.trim(), _passCtrl.text);
    if (err != null) {
      setState(() => _error = "Email o contrasena incorrectos");
    } else if (mounted) {
      if (rider.isApproved) { context.go("/dashboard"); } else { context.go("/pending"); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
        const SizedBox(height: 40),
        Container(width: 80, height: 80, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(22)), child: const Center(child: Text("🛵", style: TextStyle(fontSize: 40)))),
        const SizedBox(height: 16),
        const Text("Go Rider", style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text("Bienvenido de vuelta", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 15)),
        const SizedBox(height: 40),
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF1A2636), borderRadius: BorderRadius.circular(20)), child: Column(children: [
          TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: "Correo electronico", hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)), prefixIcon: const Icon(Icons.email_outlined, color: AppColors.accent), filled: true, fillColor: const Color(0xFF0F1923), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)))),
          const SizedBox(height: 12),
          TextFormField(controller: _passCtrl, obscureText: _obscure, style: const TextStyle(color: Colors.white), onFieldSubmitted: (_) => _login(),
            decoration: InputDecoration(hintText: "Contrasena", hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)), prefixIcon: const Icon(Icons.lock_outline, color: AppColors.accent), suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38), onPressed: () => setState(() => _obscure = !_obscure)), filled: true, fillColor: const Color(0xFF0F1923), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)))),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))],
          const SizedBox(height: 20),
          ElevatedButton(onPressed: rider.loading ? null : _login, child: rider.loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("Entrar")),
        ])),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text("No tienes cuenta? ", style: TextStyle(color: Colors.white60)),
          GestureDetector(onTap: () => context.go("/register"), child: const Text("Registrate", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800))),
        ]),
      ]))),
    );
  }
}
