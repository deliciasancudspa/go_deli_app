import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/auth_provider.dart";

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;
  String? _error;

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = "Completa todos los campos");
      return;
    }
    final err = await context.read<AuthProvider>().signUp(
      _emailCtrl.text.trim(), _passCtrl.text, _nameCtrl.text.trim(), _phoneCtrl.text.trim(),
    );
    if (err != null) {
      setState(() => _error = "Error al registrarse. Intenta con otro email.");
    } else if (mounted) {
      context.go("/home");
    }
  }

  Widget _field(TextEditingController c, String hint, IconData icon, {TextInputType type = TextInputType.text}) {
    return TextFormField(
      controller: c, keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true, fillColor: const Color(0xFF0F1923),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.secondary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 20),
            Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.go("/login")),
              const Text("Crear cuenta", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: const Color(0xFF1A2636), borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                _field(_nameCtrl, "Nombre completo", Icons.person_outline),
                const SizedBox(height: 12),
                _field(_emailCtrl, "Correo electronico", Icons.email_outlined, type: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _field(_phoneCtrl, "Telefono (opcional)", Icons.phone_outlined, type: TextInputType.phone),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl, obscureText: _obscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Contrasena",
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
                    suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38), onPressed: () => setState(() => _obscure = !_obscure)),
                    filled: true, fillColor: const Color(0xFF0F1923),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                  ),
                ),
                if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: auth.loading ? null : _register,
                  child: auth.loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Crear cuenta"),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("Ya tienes cuenta? ", style: TextStyle(color: Colors.white60)),
              GestureDetector(onTap: () => context.go("/login"), child: const Text("Inicia sesion", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800))),
            ]),
          ]),
        ),
      ),
    );
  }
}
