import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/auth_provider.dart";

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final pw1 = _newPassCtrl.text;
    final pw2 = _confirmPassCtrl.text;

    if (pw1.length < 8) {
      setState(() => _error = "La contrasena debe tener al menos 8 caracteres.");
      return;
    }
    if (pw1 != pw2) {
      setState(() => _error = "Las contrasenas no coinciden.");
      return;
    }

    final auth = context.read<AuthProvider>();
    final err = await auth.updatePassword(pw1);
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = "Error al cambiar la contrasena. Intenta de nuevo.");
    } else {
      context.go("/home");
    }
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
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  auth.clearPasswordReset();
                  context.go("/login");
                },
              ),
              const Text(
                "Nueva contrasena",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ]),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2636),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text(
                  "Crea una nueva contrasena para tu cuenta.",
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _newPassCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Nueva contrasena",
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.accent),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0F1923),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPassCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: Colors.white),
                  onFieldSubmitted: (_) => _updatePassword(),
                  decoration: InputDecoration(
                    hintText: "Confirmar contrasena",
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.accent),
                    filled: true,
                    fillColor: const Color(0xFF0F1923),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                Container(
                  width: double.infinity, height: 52,
                  decoration: BoxDecoration(
                    gradient: auth.loading ? null : AppColors.mainGradient,
                    color: auth.loading ? AppColors.border : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: auth.loading ? null : _updatePassword,
                      borderRadius: BorderRadius.circular(14),
                      child: Center(
                        child: auth.loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text("Cambiar contrasena", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
