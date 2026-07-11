import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/constants/chile_data.dart";
import "../../../core/utils/rut_utils.dart";
import "../../../providers/auth_provider.dart";

// ─── Screen ──────────────────────────────────────────────────────────────────

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _rutCtrl   = TextEditingController();
  final _docCtrl   = TextEditingController();

  bool _obscure      = true;
  String _nationality = 'chilena';
  String _docType     = 'dni';
  bool?  _rutValid;
  String? _region;
  String? _city;
  bool   _acceptTerms = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passCtrl.dispose();
    _phoneCtrl.dispose(); _rutCtrl.dispose(); _docCtrl.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_emailCtrl.text.trim().isEmpty) return false;
    if (_passCtrl.text.isEmpty) return false;
    if (_phoneCtrl.text.trim().isEmpty) return false;
    if (_nationality == 'chilena') {
      if (_rutValid != true) return false;
    } else {
      if (_docCtrl.text.trim().length < 5) return false;
    }
    if (_region == null || _city == null) return false;
    if (!_acceptTerms) return false;
    return true;
  }

  Future<void> _register() async {
    if (!_isFormValid) {
      setState(() => _error = "Completa todos los campos requeridos");
      return;
    }
    final nationalId     = _nationality == 'chilena' ? _rutCtrl.text.trim() : _docCtrl.text.trim();
    final nationalIdType = _nationality == 'chilena' ? 'rut' : _docType;

    final err = await context.read<AuthProvider>().signUp(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      nationality: _nationality,
      nationalId: nationalId,
      nationalIdType: nationalIdType,
      region: _region!,
      city: _city!,
    );

    if (!mounted) return;
    if (err == "duplicate_national_id") {
      _showDuplicateDialog();
    } else if (err == "revisa_tu_correo") {
      setState(() => _error = "Revisa tu correo y confirma tu cuenta para continuar.");
    } else if (err != null) {
      setState(() => _error = err);
    } else {
      context.go("/home");
    }
  }

  Future<void> _googleSignIn() async {
    final err = await context.read<AuthProvider>().signInWithGoogle();
    if (!mounted) return;
    if (err == null) {
      context.go("/home");
    } else if (err == "needs_profile_completion") {
      context.go("/complete-profile");
    } else if (err != "cancelled") {
      setState(() => _error = "Intenta registrarte con email");
    }
  }

  void _showDuplicateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2636),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Identificación ya registrada",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: const Text(
          "Este número de identificación ya está registrado.\n\n"
          "Si olvidaste tu contraseña, puedes recuperarla. Si necesitas ayuda, contáctanos a soporte@godeli.cl",
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go("/login");
            },
            child: const Text("Recuperar contraseña", style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse("mailto:soporte@godeli.cl");
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
            child: const Text("Contactar soporte", style: TextStyle(color: Colors.white60)),
          ),
        ],
      ),
    );
  }

  // ─── UI helpers ────────────────────────────────────────────────────────────

  static const _fillColor = Color(0xFF0F1923);
  static const _cardColor = Color(0xFF1A2636);

  InputDecoration _dec(String hint, IconData icon, {Widget? suffix, String? errorText}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
    prefixIcon: Icon(icon, color: AppColors.accent),
    suffixIcon: suffix,
    errorText: errorText,
    errorStyle: const TextStyle(color: AppColors.error, fontSize: 11),
    filled: true, fillColor: _fillColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: errorText != null ? const BorderSide(color: AppColors.error, width: 1.5) : BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: errorText != null ? AppColors.error : AppColors.accent, width: 2),
    ),
  );

  Widget _field(TextEditingController c, String hint, IconData icon, {
    TextInputType type = TextInputType.text,
    List<TextInputFormatter>? formatters,
    bool obscure = false,
    Widget? suffix,
  }) =>
    TextFormField(
      controller: c, keyboardType: type, inputFormatters: formatters,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: _dec(hint, icon, suffix: suffix),
    );

  Widget _rutField() => TextFormField(
    controller: _rutCtrl,
    keyboardType: TextInputType.text,
    textCapitalization: TextCapitalization.characters,
    inputFormatters: [RutInputFormatter()],
    style: const TextStyle(color: Colors.white),
    onChanged: (v) {
      final clean = v.replaceAll('.', '').replaceAll('-', '');
      setState(() => _rutValid = clean.length >= 2 ? validateRut(v) : null);
    },
    decoration: _dec(
      "12.345.678-9",
      Icons.badge_outlined,
      suffix: _rutValid == null
          ? null
          : Icon(_rutValid! ? Icons.check_circle : Icons.cancel,
              color: _rutValid! ? AppColors.success : AppColors.error),
      errorText: _rutValid == false ? "RUT inválido" : null,
    ),
  );

  Widget _dropdown<T extends Object>({
    required String hint,
    required T? value,
    required List<T> items,
    required ValueChanged<T?>? onChanged,
    String Function(T)? labelOf,
  }) =>
    DropdownButtonFormField<T>(
      value: value,
      onChanged: onChanged,
      isExpanded: true,
      dropdownColor: _cardColor,
      style: const TextStyle(color: Colors.white, fontFamily: 'Nunito', fontSize: 14),
      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white38),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        filled: true, fillColor: _fillColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
      ),
      items: items.map((item) => DropdownMenuItem<T>(
        value: item,
        child: Text(labelOf != null ? labelOf(item) : item.toString(), style: const TextStyle(color: Colors.white)),
      )).toList(),
    );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
  );

  Widget _nationalityBtn(String label, String value) => Expanded(
    child: GestureDetector(
      onTap: () => setState(() {
        _nationality = value;
        _rutValid = null;
        _rutCtrl.clear();
        _docCtrl.clear();
        _docType = 'dni';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _nationality == value ? AppColors.accent.withOpacity(0.15) : _fillColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _nationality == value ? AppColors.accent : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: _nationality == value ? AppColors.accent : Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _googleButton(bool loading) => OutlinedButton(
    onPressed: loading ? null : _googleSignIn,
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
  );

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<AuthProvider>();
    final cities = _region != null ? (chileRegionCiudades[_region!] ?? <String>[]) : <String>[];

    const docTypeLabels = {
      'dni'              : 'DNI',
      'pasaporte'        : 'Pasaporte',
      'cedula_extranjera': 'Cédula de identidad extranjera',
    };

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
                onPressed: () => context.go("/login"),
              ),
              const Text(
                "Crear cuenta",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ]),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // 1. Nombre
                _field(_nameCtrl, "Nombre completo", Icons.person_outline),
                const SizedBox(height: 12),

                // 2. Correo
                _field(_emailCtrl, "Correo electrónico", Icons.email_outlined, type: TextInputType.emailAddress),
                const SizedBox(height: 12),

                // 3. Contraseña
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dec(
                    "Contraseña",
                    Icons.lock_outline,
                    suffix: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 4. Teléfono
                _field(_phoneCtrl, "Teléfono", Icons.phone_outlined, type: TextInputType.phone),
                const SizedBox(height: 16),

                // 5. Nacionalidad
                _label("Nacionalidad"),
                Row(children: [
                  _nationalityBtn("Chileno/a", "chilena"),
                  const SizedBox(width: 12),
                  _nationalityBtn("Extranjero/a", "extranjera"),
                ]),
                const SizedBox(height: 14),

                // 6. Documento
                if (_nationality == 'chilena') ...[
                  _label("RUT"),
                  _rutField(),
                ] else ...[
                  _label("Tipo de documento"),
                  _dropdown<String>(
                    hint: "Seleccionar tipo",
                    value: docTypeLabels.containsKey(_docType) ? _docType : null,
                    items: docTypeLabels.keys.toList(),
                    onChanged: (v) => setState(() => _docType = v ?? 'dni'),
                    labelOf: (k) => docTypeLabels[k] ?? k,
                  ),
                  const SizedBox(height: 12),
                  _label("Número de documento"),
                  _field(_docCtrl, "Mínimo 5 caracteres", Icons.credit_card_outlined),
                ],
                const SizedBox(height: 16),

                // 7. Región
                _label("Región"),
                _dropdown<String>(
                  hint: "Seleccionar región",
                  value: _region,
                  items: chileRegiones,
                  onChanged: (v) => setState(() { _region = v; _city = null; }),
                ),
                const SizedBox(height: 12),

                // 8. Ciudad
                _label("Ciudad"),
                _dropdown<String>(
                  hint: _region == null ? "Selecciona una región primero" : "Seleccionar ciudad",
                  value: _city,
                  items: cities,
                  onChanged: _region == null ? null : (v) => setState(() => _city = v),
                ),
                const SizedBox(height: 16),

                // 9. Términos
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  SizedBox(
                    width: 24, height: 24,
                    child: Checkbox(
                      value: _acceptTerms,
                      onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                      activeColor: AppColors.accent,
                      checkColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                        children: [
                          TextSpan(text: "Acepto los "),
                          TextSpan(
                            text: "Términos y Condiciones",
                            style: TextStyle(
                              color: AppColors.accent,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
                const SizedBox(height: 20),

                // 10. Botón crear cuenta
                ElevatedButton(
                  onPressed: (auth.loading || !_isFormValid) ? null : _register,
                  child: auth.loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Crear cuenta"),
                ),

                // Separador
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(children: [
                    const Expanded(child: Divider(color: Colors.white24)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text("o", style: TextStyle(color: Colors.white.withOpacity(0.5))),
                    ),
                    const Expanded(child: Divider(color: Colors.white24)),
                  ]),
                ),

                // 11. Google
                _googleButton(auth.loading),
              ]),
            ),

            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("¿Ya tienes cuenta? ", style: TextStyle(color: Colors.white60)),
              GestureDetector(
                onTap: () => context.go("/login"),
                child: const Text("Inicia sesión", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
