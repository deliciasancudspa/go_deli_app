import "dart:convert";
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/constants/banks.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

// Admin WhatsApp — configurable en go_rider_app/lib/config/app_config.dart
import "../../../config/app_config.dart";

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _supportPhone; // cargado desde config admin

  @override
  void initState() {
    super.initState();
    _loadSupportPhone();
  }

  Future<void> _loadSupportPhone() async {
    try {
      final data = await Supabase.instance.client
          .from("config")
          .select("value")
          .eq("key", "platform_config")
          .maybeSingle();
      if (data != null) {
        final raw = data["value"];
        final map = raw is Map<String, dynamic>
            ? raw
            : raw is String
                ? (jsonDecode(raw) as Map<String, dynamic>?)
                : null;
        final phone = (map?["support_phone"] as String?)?.trim();
        if (phone != null && phone.isNotEmpty && mounted) {
          setState(() => _supportPhone = phone.replaceAll(RegExp(r'[^0-9]'), ''));
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    final bankList = rider.rider?["deliverer_bank_info"];
    final bank = (bankList is List && bankList.isNotEmpty) ? bankList[0] as Map<String, dynamic> : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) context.go("/dashboard"); },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Mi perfil"), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go("/dashboard"))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Column(children: [
          CircleAvatar(radius: 44, backgroundColor: AppColors.accent, child: Text(rider.riderName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900))),
          const SizedBox(height: 12),
          Text(rider.riderName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(rider.user?["email"] ?? "", style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: rider.isApproved ? AppColors.success.withOpacity(0.1) : AppColors.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(rider.isApproved ? "Repartidor aprobado" : "En revision", style: TextStyle(color: rider.isApproved ? AppColors.success : AppColors.warning, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ])),
        const SizedBox(height: 24),
        _card("Mi vehiculo", [
          _row("Tipo", rider.rider?["vehicle_type"] ?? "-"),
          if (rider.rider?["vehicle_plate"] != null) _row("Patente", rider.rider!["vehicle_plate"]),
        ], onEdit: () => _editVehicle(context, rider)),
        const SizedBox(height: 12),
        _card("Datos bancarios", bank != null ? [
          _row("Banco", bank["bank_name"] ?? "-"),
          _row("Tipo cuenta", bank["account_type"] ?? "-"),
          _row("Numero cuenta", bank["account_number"] ?? "-"),
          _row("Titular", bank["account_holder"] ?? "-"),
          _row("RUT", bank["rut"] ?? "-"),
        ] : [const Padding(padding: EdgeInsets.all(8), child: Text("Sin datos bancarios", style: TextStyle(color: AppColors.textLight)))],
          onEdit: () => _editBank(context, rider, bank)),
        const SizedBox(height: 12),
        _card("Contactar Admin", [
          _rowButton(
            label: "Mensaje directo",
            icon: Icons.chat_bubble_outline,
            onTap: () async {
              try {
                final admin = await Supabase.instance.client
                    .from("users")
                    .select("id")
                    .eq("role", "admin")
                    .limit(1)
                    .single();
                if (context.mounted) context.push("/chat-admin/${admin["id"]}");
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No se pudo conectar con el admin"), backgroundColor: AppColors.error),
                  );
                }
              }
            },
          ),
          _rowButton(
            label: "WhatsApp",
            icon: Icons.chat_outlined,
            onTap: () async {
              final phone = _supportPhone ?? AppConfig.adminWhatsApp;
              final uri = Uri.parse("https://wa.me/$phone");
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _changePassword(context, rider),
          icon: const Icon(Icons.lock_outline),
          label: const Text("Cambiar contraseña"),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () async { await rider.signOut(); if (context.mounted) context.go("/login"); },
          icon: const Icon(Icons.logout),
          label: const Text("Cerrar sesion"),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
        ),
        const SizedBox(height: 32),
        const Text("Go Rider v1.0.1", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textLight, fontSize: 12)),
      ]),
      ),
    );
  }

  void _changePassword(BuildContext context, RiderProvider rider) {
    showDialog(
      context: context,
      builder: (ctx) => _ChangePasswordDialog(rider: rider),
    );
  }

  void _editVehicle(BuildContext context, RiderProvider rider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditVehicleSheet(rider: rider),
    );
  }

  void _editBank(BuildContext context, RiderProvider rider, Map<String, dynamic>? bank) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditBankSheet(rider: rider, bank: bank),
    );
  }

  Widget _card(String title, List<Widget> children, {VoidCallback? onEdit}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMedium))),
        if (onEdit != null)
          InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_outlined, size: 15, color: AppColors.accent),
                SizedBox(width: 4),
                Text("Editar", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 12), const Divider(height: 1), const SizedBox(height: 8),
      ...children,
    ]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppColors.textLight, fontSize: 14)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    ]),
  );

  Widget _rowButton({required String label, required IconData icon, required VoidCallback onTap}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, color: AppColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          const Icon(Icons.chevron_right, color: AppColors.textLight, size: 18),
        ]),
      ),
    );
}

// ════════════════════════════════════════════════════════════════════════════
// Edición de vehículo — los cambios se notifican al admin para revisión
// ════════════════════════════════════════════════════════════════════════════
class _EditVehicleSheet extends StatefulWidget {
  final RiderProvider rider;
  const _EditVehicleSheet({required this.rider});
  @override
  State<_EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends State<_EditVehicleSheet> {
  static const _vehicles = ["Moto", "Bicicleta", "Auto"];
  static const _icons = {"Moto": "🏍️", "Bicicleta": "🚲", "Auto": "🚗"};
  late String _type;
  late final TextEditingController _plateCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.rider.rider?["vehicle_type"] as String? ?? "Moto";
    if (!_vehicles.contains(_type)) _type = "Moto";
    _plateCtrl = TextEditingController(text: widget.rider.rider?["vehicle_plate"] as String? ?? "");
  }

  @override
  void dispose() { _plateCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_type != "Bicicleta" && _plateCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("La patente es obligatoria para ${_type == "Auto" ? "autos" : "motos"}"),
          backgroundColor: AppColors.error));
      return;
    }
    setState(() => _saving = true);
    final err = await widget.rider.updateVehicle(_type, _type == "Bicicleta" ? "" : _plateCtrl.text);
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al guardar: $err"), backgroundColor: AppColors.error));
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("📋 Datos guardados. Los cambios se enviaron a revisión y serán verificados por el administrador."),
      duration: Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text("Editar vehículo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text("Los cambios serán revisados por el administrador antes de confirmarse.",
              style: TextStyle(color: AppColors.textLight, fontSize: 13)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: _vehicles.map((v) {
            final sel = _type == v;
            return GestureDetector(
              onTap: () => setState(() => _type = v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? AppColors.accent.withOpacity(0.12) : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? AppColors.accent : AppColors.border, width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_icons[v]!, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(v, style: TextStyle(fontWeight: FontWeight.w700, color: sel ? AppColors.accent : AppColors.textMedium)),
                ]),
              ),
            );
          }).toList()),
          if (_type != "Bicicleta") ...[
            const SizedBox(height: 16),
            TextField(
              controller: _plateCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: "Patente *", hintText: "AB-CD-12"),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("Guardar y enviar a revisión"),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Edición de datos bancarios — los cambios se notifican al admin para revisión
// ════════════════════════════════════════════════════════════════════════════
class _EditBankSheet extends StatefulWidget {
  final RiderProvider rider;
  final Map<String, dynamic>? bank;
  const _EditBankSheet({required this.rider, this.bank});
  @override
  State<_EditBankSheet> createState() => _EditBankSheetState();
}

class _EditBankSheetState extends State<_EditBankSheet> {
  static const _accountTypes = ["Cuenta Corriente", "Cuenta Vista", "Cuenta RUT", "Cuenta de Ahorro"];
  late final TextEditingController _numberCtrl, _holderCtrl, _rutCtrl;
  late String _bankName;
  late String _accountType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bank ?? {};
    _bankName = b["bank_name"] as String? ?? "BancoEstado";
    if (!kBankOptions.contains(_bankName)) _bankName = "BancoEstado";
    _numberCtrl = TextEditingController(text: b["account_number"] as String? ?? "");
    _holderCtrl = TextEditingController(text: b["account_holder"] as String? ?? "");
    _rutCtrl    = TextEditingController(text: b["rut"] as String? ?? "");
    _accountType = b["account_type"] as String? ?? "Cuenta RUT";
    if (!_accountTypes.contains(_accountType)) _accountType = "Cuenta RUT";
  }

  @override
  void dispose() {
    _numberCtrl.dispose(); _holderCtrl.dispose(); _rutCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_numberCtrl.text.trim().isEmpty ||
        _holderCtrl.text.trim().isEmpty || _rutCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Completa todos los campos"), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _saving = true);
    final err = await widget.rider.updateBankInfo(
      bankName: _bankName,
      accountType: _accountType,
      accountNumber: _numberCtrl.text,
      accountHolder: _holderCtrl.text,
      rut: _rutCtrl.text,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al guardar: $err"), backgroundColor: AppColors.error));
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("📋 Datos guardados. Los cambios se enviaron a revisión y serán verificados por el administrador."),
      duration: Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text("Editar datos bancarios", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text("Los cambios serán revisados por el administrador antes de confirmarse. Tus pagos se harán a esta cuenta.",
              style: TextStyle(color: AppColors.textLight, fontSize: 13)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _bankName,
            isExpanded: true,
            decoration: const InputDecoration(labelText: "Banco"),
            items: kBankOptions.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _bankName = v ?? _bankName),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _accountType,
            decoration: const InputDecoration(labelText: "Tipo de cuenta"),
            items: _accountTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _accountType = v ?? _accountType),
          ),
          const SizedBox(height: 12),
          TextField(controller: _numberCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Número de cuenta")),
          const SizedBox(height: 12),
          TextField(controller: _holderCtrl, decoration: const InputDecoration(labelText: "Titular de la cuenta")),
          const SizedBox(height: 12),
          TextField(controller: _rutCtrl, decoration: const InputDecoration(labelText: "RUT del titular", hintText: "12.345.678-9")),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("Guardar y enviar a revisión"),
          ),
        ])),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Diálogo de cambio de contraseña
// ════════════════════════════════════════════════════════════════════════════
class _ChangePasswordDialog extends StatefulWidget {
  final RiderProvider rider;
  const _ChangePasswordDialog({required this.rider});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pwd = _newPassCtrl.text;
    if (pwd.length < 8) {
      setState(() => _error = "Mínimo 8 caracteres");
      return;
    }
    if (pwd != _confirmPassCtrl.text) {
      setState(() => _error = "Las contraseñas no coinciden");
      return;
    }
    setState(() { _saving = true; _error = null; });
    final err = await widget.rider.changePassword(pwd);
    if (!mounted) return;
    if (err != null) {
      setState(() { _saving = false; _error = err; });
    } else {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Contraseña actualizada correctamente")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Cambiar contraseña"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _newPassCtrl,
          obscureText: _obscureNew,
          decoration: InputDecoration(
            hintText: "Nueva contraseña",
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPassCtrl,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            hintText: "Confirmar contraseña",
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancelar"),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text("Guardar"),
        ),
      ],
    );
  }
}
