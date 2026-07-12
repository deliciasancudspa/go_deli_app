import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/auth_provider.dart";

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

  Future<void> _googleSignIn() async {
    final err = await context.read<AuthProvider>().signInWithGoogle();
    if (!mounted) return;
    if (err == null) {
      context.go("/home");
    } else if (err == "needs_profile_completion") {
      context.go("/complete-profile");
    } else if (err != "cancelled") {
      setState(() => _error = err);
    }
  }

  Future<void> _login() async {
    final auth = context.read<AuthProvider>();
    final err = await auth.signIn(_emailCtrl.text.trim(), _passCtrl.text);
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = "Email o contrasena incorrectos");
    } else {
      context.go("/home");
    }
  }

  void _showForgotPasswordDialog() {
    final forgotEmailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          bool loading = false;
          String msg = "";
          return AlertDialog(
            backgroundColor: const Color(0xFF1A2636),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              "Recuperar contrasena",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Ingresa tu correo y te enviaremos un enlace para restablecer tu contrasena.",
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: forgotEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "tu@correo.com",
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF0F1923),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
                  ),
                ),
                if (msg.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(msg, style: const TextStyle(fontSize: 13)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () { if (!loading) Navigator.pop(ctx); },
                child: const Text("Cancelar", style: TextStyle(color: Colors.white60)),
              ),
              TextButton(
                onPressed: () async {
                  if (loading) return;
                  final email = forgotEmailCtrl.text.trim();
                  if (email.isEmpty) {
                    setDialogState(() => msg = "Ingresa tu correo electronico.");
                    return;
                  }
                  setDialogState(() { loading = true; msg = ""; });
                  final err = await context.read<AuthProvider>().resetPasswordForEmail(
                    email,
                    redirectTo: 'https://godeli.cl/aliados',
                  );
                  setDialogState(() { loading = false; });
                  if (err != null) {
                    setDialogState(() => msg = "Error al enviar. Intenta de nuevo.");
                  } else {
                    setDialogState(() => msg = "✅ Enlace enviado. Revisa tu correo.");
                    Future.delayed(const Duration(seconds: 2), () {
                      if (ctx.mounted) Navigator.pop(ctx);
                    });
                  }
                },
                child: Builder(
                  // loading is mutated via setDialogState — analyzer can't track it
                  builder: (_) => loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                      : const Text("Enviar", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        // Detalles decorativos con nueva paleta sobre fondo oscuro
        Positioned(top: -80, right: -80, child: Container(
          width: 320, height: 320,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFF6B00).withOpacity(0.15)),
        )),
        Positioned(bottom: -60, left: -60, child: Container(
          width: 260, height: 260,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF9E00FF).withOpacity(0.18)),
        )),
        Positioned(top: 180, left: -40, child: Container(
          width: 160, height: 160,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFF6B00).withOpacity(0.08)),
        )),
        SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 40),
            Column(children: [
              Image.asset(
                "assets/images/logo.png",
                width: 160,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(height: 12),
              const Text("Bienvenido de vuelta", style: TextStyle(color: AppColors.textLight, fontSize: 15)),
            ]),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: [BoxShadow(color: const Color(0xFF9E00FF).withOpacity(0.10), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("Iniciar sesion", style: TextStyle(color: AppColors.textDark, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppColors.textDark),
                  decoration: InputDecoration(
                    hintText: "Correo electronico",
                    hintStyle: const TextStyle(color: AppColors.textLight),
                    prefixIcon: const Icon(Icons.email_outlined, color: AppColors.accent),
                    filled: true, fillColor: const Color(0xFFF4F5F7),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: AppColors.textDark),
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    hintText: "Contrasena",
                    hintStyle: const TextStyle(color: AppColors.textLight),
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.accent),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.textLight),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    filled: true, fillColor: const Color(0xFFF4F5F7),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
                  ),
                ),
                if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: auth.loading ? null : () => _showForgotPasswordDialog(),
                    child: const Text("Olvidaste tu contrasena?", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                  ),
                ),
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
                      onTap: auth.loading ? null : _login,
                      borderRadius: BorderRadius.circular(14),
                      child: Center(child: auth.loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Entrar", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, fontFamily: "Nunito"))),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            // Google sign-in separator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              child: Row(children: [
                const Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: const Text("o", style: TextStyle(color: AppColors.textLight)),
                ),
                const Expanded(child: Divider(color: AppColors.border)),
              ]),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: auth.loading ? null : _googleSignIn,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFDEDEDE)),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SvgPicture.asset("assets/icons/google_logo.svg", width: 20, height: 20),
                const SizedBox(width: 12),
                const Text(
                  "Continuar con Google",
                  style: TextStyle(color: Color(0xFF3C4043), fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("No tienes cuenta? ", style: TextStyle(color: AppColors.textMedium)),
              GestureDetector(onTap: () => context.go("/register"), child: const Text("Registrate", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800))),
            ]),
          ]),
        ),
        ),
      ]),
    );
  }
}
