import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";
import "../../../l10n/app_localizations.dart";

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
      if (rider.riderId.isEmpty) { context.go("/register"); }
      else if (rider.isApproved) { context.go("/dashboard"); }
      else { context.go("/pending"); }
    }
  }

  Future<void> _forgotPassword(BuildContext context) async {
    final emailCtrl = TextEditingController();
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Recuperar contraseña"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Ingresa tu correo electrónico y te enviaremos un enlace para restablecer tu contraseña.",
              style: TextStyle(fontSize: 14, color: AppColors.textMedium)),
          const SizedBox(height: 12),
          TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(hintText: AppLocalizations.of(ctx)!.email),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(ctx)!.cancel)),
          ElevatedButton(
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;
              final rider = context.read<RiderProvider>();
              final err = await rider.resetPassword(email);
              if (!ctx.mounted) return;
              Navigator.pop(ctx, true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(err != null
                      ? err
                      : AppLocalizations.of(context)!.loginResetSent),
                  backgroundColor: err != null ? AppColors.error : AppColors.success,
                ),
              );
            },
            child: Text(AppLocalizations.of(ctx)!.loginSendReset),
          ),
        ],
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
    final rider = context.watch<RiderProvider>();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(child: Stack(children: [
        // Mismos detalles decorativos que la pantalla de carga
        Positioned(top: -80, right: -80, child: Container(
          width: 300, height: 300,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFF6B35).withOpacity(0.08)),
        )),
        Positioned(bottom: -60, left: -60, child: Container(
          width: 240, height: 240,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7C3AED).withOpacity(0.08)),
        )),
        Positioned(top: 160, left: -40, child: Container(
          width: 140, height: 140,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7C3AED).withOpacity(0.05)),
        )),
        SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
        const SizedBox(height: 40),
        Image.asset("assets/images/logo.png", width: 190, filterQuality: FilterQuality.high),
        const SizedBox(height: 16),
        Text(AppLocalizations.of(context)!.loginWelcome, style: const TextStyle(color: AppColors.textLight, fontSize: 15)),
        const SizedBox(height: 32),
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 6))]), child: Column(children: [
          TextFormField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: AppColors.textDark),
            decoration: InputDecoration(hintText: AppLocalizations.of(context)!.email, hintStyle: const TextStyle(color: AppColors.textLight), prefixIcon: const Icon(Icons.email_outlined, color: AppColors.accent), filled: true, fillColor: const Color(0xFFF4F5F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)))),
          const SizedBox(height: 12),
          TextFormField(controller: _passCtrl, obscureText: _obscure, style: const TextStyle(color: AppColors.textDark), onFieldSubmitted: (_) => _login(),
            decoration: InputDecoration(hintText: AppLocalizations.of(context)!.password, hintStyle: const TextStyle(color: AppColors.textLight), prefixIcon: const Icon(Icons.lock_outline, color: AppColors.accent), suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: AppColors.textLight), onPressed: () => setState(() => _obscure = !_obscure)), filled: true, fillColor: const Color(0xFFF4F5F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)))),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))],
          const SizedBox(height: 20),
          ElevatedButton(onPressed: rider.loading ? null : _login, child: rider.loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(AppLocalizations.of(context)!.signIn)),
        ])),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(AppLocalizations.of(context)!.loginNoAccount, style: const TextStyle(color: AppColors.textMedium)),
          GestureDetector(onTap: () => context.go("/register"), child: Text(AppLocalizations.of(context)!.loginRegister, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => _forgotPassword(context),
            child: Text(AppLocalizations.of(context)!.loginForgotPassword, style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
          ),
        ),
      ]))),
      ])),
    );
  }
}
