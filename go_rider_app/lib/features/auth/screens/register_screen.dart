import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _pageCtrl = PageController();
  int _step = 0;
  String? _error;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _rutCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _vehicleType = "Moto";
  final _plateCtrl = TextEditingController();
  String _bankName = "BancoEstado";
  String _accountType = "Cuenta Vista";
  final _accountNumCtrl = TextEditingController();
  final _accountHolderCtrl = TextEditingController();
  final _accountRutCtrl = TextEditingController();
  final _vehicles = ["Moto","Bicicleta","Auto","A pie"];
  final _banks = ["BancoEstado","Banco de Chile","BCI","Banco Santander","Banco Itau","Scotiabank","Banco Falabella","Mercado Pago","MACH","Tenpo","Otro"];
  final _accountTypes = ["Cuenta Vista","Cuenta Corriente","Cuenta de Ahorro"];
  final _steps = ["Datos personales","Vehiculo","Datos bancarios"];

  Future<void> _submit() async {
    if (_accountNumCtrl.text.isEmpty || _accountHolderCtrl.text.isEmpty) {
      setState(() => _error = "Completa todos los campos bancarios");
      return;
    }
    final rider = context.read<RiderProvider>();
    final err = await rider.register(
      name: _nameCtrl.text.trim(), email: _emailCtrl.text.trim(),
      password: _passCtrl.text, phone: _phoneCtrl.text.trim(),
      rut: _rutCtrl.text.trim(), vehicle: _vehicleType,
      plate: _plateCtrl.text.trim(), bankName: _bankName,
      accountType: _accountType, accountNumber: _accountNumCtrl.text.trim(),
      accountHolder: _accountHolderCtrl.text.trim(), accountRut: _accountRutCtrl.text.trim(),
    );
    if (err != null) {
      setState(() => _error = "Error: $err");
    } else if (mounted) {
      context.go("/pending");
    }
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {TextInputType type = TextInputType.text, bool obscure = false}) {
    return TextFormField(
      controller: c, keyboardType: type, obscureText: obscure,
      decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: AppColors.accent)),
    );
  }

  void _next() {
    _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() { _step++; _error = null; });
  }

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<RiderProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_steps[_step]),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 0) {
              _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
              setState(() => _step--);
            } else {
              context.go("/login");
            }
          },
        ),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: List.generate(_steps.length, (i) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= _step ? AppColors.accent : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),
        ),
        Expanded(
          child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // PASO 1: Datos personales
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Text("Cuentanos sobre ti", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 24),
                  _field(_nameCtrl, "Nombre completo", Icons.person_outline),
                  const SizedBox(height: 12),
                  _field(_emailCtrl, "Correo electronico", Icons.email_outlined, type: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _field(_phoneCtrl, "Telefono", Icons.phone_outlined, type: TextInputType.phone),
                  const SizedBox(height: 12),
                  _field(_rutCtrl, "RUT", Icons.badge_outlined),
                  const SizedBox(height: 12),
                  _field(_passCtrl, "Contrasena", Icons.lock_outline, obscure: true),
                  if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.error))],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      if (_nameCtrl.text.isEmpty || _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
                        setState(() => _error = "Completa todos los campos");
                        return;
                      }
                      _next();
                    },
                    child: const Text("Siguiente"),
                  ),
                ]),
              ),
              // PASO 2: Vehiculo
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Tu vehiculo", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 24),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.5,
                    children: _vehicles.map((v) {
                      final icons = {"Moto":"🏍️","Bicicleta":"🚲","Auto":"🚗","A pie":"🚶"};
                      final selected = _vehicleType == v;
                      return GestureDetector(
                        onTap: () => setState(() => _vehicleType = v),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.accent.withOpacity(0.1) : AppColors.surface,
                            border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2 : 1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            Text(icons[v]!, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Text(v, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? AppColors.accent : AppColors.textMedium)),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_vehicleType != "A pie") ...[
                    const SizedBox(height: 20),
                    _field(_plateCtrl, "Patente del vehiculo", Icons.directions_car_outlined),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(onPressed: _next, child: const Text("Siguiente")),
                ]),
              ),
              // PASO 3: Datos bancarios
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Datos para tu pago", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text("Aqui recibiras tus ganancias cada semana", style: TextStyle(color: AppColors.textLight, fontSize: 14)),
                  const SizedBox(height: 24),
                  const Text("Banco *", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textMedium)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _bankName,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.account_balance_outlined, color: AppColors.accent)),
                    items: _banks.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                    onChanged: (v) => setState(() => _bankName = v!),
                  ),
                  const SizedBox(height: 12),
                  const Text("Tipo de cuenta *", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textMedium)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _accountType,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.credit_card_outlined, color: AppColors.accent)),
                    items: _accountTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => _accountType = v!),
                  ),
                  const SizedBox(height: 12),
                  _field(_accountNumCtrl, "Numero de cuenta *", Icons.numbers_outlined, type: TextInputType.number),
                  const SizedBox(height: 12),
                  _field(_accountHolderCtrl, "Nombre del titular *", Icons.person_outline),
                  const SizedBox(height: 12),
                  _field(_accountRutCtrl, "RUT del titular *", Icons.badge_outlined),
                  if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: rider.loading ? null : _submit,
                    child: rider.loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Enviar solicitud"),
                  ),
                  const SizedBox(height: 12),
                  const Text("Tu solicitud sera revisada en 24-48 horas habiles", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textLight, fontSize: 13)),
                ]),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
