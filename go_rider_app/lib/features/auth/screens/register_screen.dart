import "dart:convert";
import "dart:ui" as ui;
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "../../../core/constants/banks.dart";
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
  final _vehicles = ["Moto","Bicicleta","Auto"];
  final _banks = kBankOptions;
  final _accountTypes = ["Cuenta Vista","Cuenta Corriente","Cuenta de Ahorro"];
  final _steps = ["Datos personales","Vehiculo","Datos bancarios","Terminos"];

  // Paso 4: Consentimientos y firma
  final _signerNameCtrl = TextEditingController();
  final _signerRutCtrl = TextEditingController();
  bool _termContract = false;
  bool _termPrivacy = false;
  bool _termGeo = false;
  final _signatureKey = GlobalKey();
  final List<List<Offset>> _signatureStrokes = [];
  List<Offset> _currentStroke = [];
  bool _signatureDrawn = false;
  bool _showContract = false;

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _currentStroke = [d.localPosition];
      _signatureDrawn = true;
    });
  }
  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _currentStroke.add(d.localPosition));
  }
  void _onPanEnd(DragEndDetails d) {
    setState(() {
      _signatureStrokes.add(List.from(_currentStroke));
      _currentStroke = [];
    });
  }
  void _clearSignature() {
    setState(() {
      _signatureStrokes.clear();
      _currentStroke = [];
      _signatureDrawn = false;
    });
  }

  Future<String?> _captureSignature() async {
    try {
      final boundary = _signatureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return base64Encode(byteData.buffer.asUint8List());
    } catch (_) { return null; }
  }

  Future<void> _submit() async {
    if (_accountNumCtrl.text.isEmpty || _accountHolderCtrl.text.isEmpty) {
      setState(() => _error = "Completa todos los campos bancarios");
      return;
    }
    // Validar consentimientos
    if (!_termContract || !_termPrivacy || !_termGeo) {
      setState(() => _error = "Debes aceptar todos los consentimientos legales");
      return;
    }
    // Validar firma
    if (!_signatureDrawn) {
      setState(() => _error = "Debes dibujar tu firma en el recuadro");
      return;
    }
    final signerName = _signerNameCtrl.text.trim();
    final signerRut = _signerRutCtrl.text.trim();
    if (signerName.isEmpty) {
      setState(() => _error = "Ingresa tu nombre para la firma digital");
      return;
    }
    if (signerRut.isEmpty) {
      setState(() => _error = "Ingresa tu RUT para la firma digital");
      return;
    }
    if (!_isValidRut(signerRut)) {
      setState(() => _error = "El RUT del firmante no es válido");
      return;
    }
    final sigBase64 = await _captureSignature();

    final rider = context.read<RiderProvider>();
    final err = await rider.register(
      name: _nameCtrl.text.trim(), email: _emailCtrl.text.trim(),
      password: _passCtrl.text, phone: _phoneCtrl.text.trim(),
      rut: _rutCtrl.text.trim(), vehicle: _vehicleType,
      plate: _vehicleType == "Bicicleta" ? "" : _plateCtrl.text.trim(), bankName: _bankName,
      accountType: _accountType, accountNumber: _accountNumCtrl.text.trim(),
      accountHolder: _accountHolderCtrl.text.trim(), accountRut: _accountRutCtrl.text.trim(),
      signerName: signerName, signerRut: signerRut,
      signatureImage: sigBase64,
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

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _rutCtrl.dispose();
    _passCtrl.dispose();
    _plateCtrl.dispose();
    _accountNumCtrl.dispose();
    _accountHolderCtrl.dispose();
    _accountRutCtrl.dispose();
    _signerNameCtrl.dispose();
    _signerRutCtrl.dispose();
    super.dispose();
  }

  /// Valida RUT chileno (algoritmo módulo 11)
  bool _isValidRut(String rut) {
    final cleaned = rut.replaceAll(RegExp(r'[.\-\s]'), '').toUpperCase();
    if (cleaned.length < 2) return false;
    final dv = cleaned[cleaned.length - 1];
    final numStr = cleaned.substring(0, cleaned.length - 1);
    final num = int.tryParse(numStr);
    if (num == null) return false;
    int sum = 0;
    int multiplier = 2;
    for (int i = numStr.length - 1; i >= 0; i--) {
      sum += int.parse(numStr[i]) * multiplier;
      multiplier = multiplier == 7 ? 2 : multiplier + 1;
    }
    final expected = 11 - (sum % 11);
    final expectedDv = expected == 11 ? '0' : (expected == 10 ? 'K' : expected.toString());
    return dv == expectedDv;
  }

  void _next() {
    // Validar RUT en paso 1 (datos personales)
    if (_step == 0 && _rutCtrl.text.trim().isNotEmpty) {
      if (!_isValidRut(_rutCtrl.text.trim())) {
        setState(() => _error = "El RUT ingresado no es válido");
        return;
      }
    }
    _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() { _step++; _error = null; });
  }

  // ── Texto resumido del contrato ──
  static const _contractSummary = """
CONTRATO MARCO DE PRESTACIÓN DE SERVICIOS DE REPARTO INDEPENDIENTE — GO DELI

Entre EMPRESAS GO SpA, RUT 78.445.567-K, representada por Derian Osorio ("GO DELI"), y la persona que acepta electrónicamente ("REPARTIDOR").

PRIMERA: DEFINICIONES. Plataforma, Comercio Afiliado, Cliente, Repartidor, Pedido, Aplicación.

SEGUNDA: OBJETO. Intermediación tecnológica entre comercios, repartidores y clientes.

TERCERA: NATURALEZA JURÍDICA. No existe relación laboral, subordinación ni exclusividad. El repartidor organiza libremente su actividad.

CUARTA: REGISTRO. Cédula de identidad, licencia de conducir, SOAP, revisión técnica, cuenta bancaria.

QUINTA: VEHÍCULOS. Moto, automóvil, bicicleta u otros autorizados.

SEXTA: FUNCIONAMIENTO. Conexión y desconexión libre. Aceptación o rechazo libre de pedidos.

SÉPTIMA: TARIFAS. Determinadas unilateralmente por GO DELI según distancia, tiempo, demanda, bonificaciones e incentivos.

OCTAVA: PAGOS. Transferencia bancaria semanal con liquidación detallada.

NOVENA: DOCUMENTACIÓN TRIBUTARIA. Responsabilidad exclusiva del repartidor declarar ingresos y cumplir obligaciones tributarias.

DÉCIMA: TRIBUTACIÓN. Montos brutos. Impuestos de cargo del repartidor.

DÉCIMO PRIMERA: OBLIGACIONES. Cumplir normativa de tránsito, mantener documentación vigente, entregar pedidos adecuadamente, confidencialidad.

DÉCIMO SEGUNDA: PROHIBICIONES. Apropiación indebida, fraude, suplantación, entregas ficticias, manipulación de pedidos, conductas delictivas.

DÉCIMO TERCERA: GEOLOCALIZACIÓN. El repartidor autoriza el tratamiento de su ubicación.

DÉCIMO CUARTA: DATOS PERSONALES. Tratamiento conforme a la Política de Privacidad de GO DELI, disponible en https://godeli.cl/privacidad.

DÉCIMO QUINTA: PROPIEDAD INTELECTUAL. GO DELI es titular exclusivo de todos los derechos.

DÉCIMO SEXTA: LIMITACIÓN DE RESPONSABILIDAD. GO DELI no responde por accidentes, daños, multas ni pérdidas indirectas.

DÉCIMO SÉPTIMA: SEGUROS. Responsabilidad del repartidor.

DÉCIMO OCTAVA: SUSPENSIÓN. Documentación vencida, fraude, incumplimientos, riesgo para clientes.

DÉCIMO NOVENA: CONFIDENCIALIDAD de toda información obtenida mediante la Plataforma.

VIGÉSIMA: MODIFICACIONES. Informadas a través de la Plataforma.

VIGÉSIMO PRIMERA: FIRMA ELECTRÓNICA. Plena validez jurídica conforme a Ley N° 19.799.

VIGÉSIMO SEGUNDA: LEY APLICABLE. Chile, domicilio en Ancud, Región de Los Lagos.

EMPRESAS GO SpA · RUT 78.445.567-K · soporte@godeli.cl · www.godeli.cl
""";

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
                      final icons = {"Moto":"🏍️","Bicicleta":"🚲","Auto":"🚗"};
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
                  if (_vehicleType != "Bicicleta") ...[
                    const SizedBox(height: 20),
                    _field(_plateCtrl, "Patente del vehiculo *", Icons.directions_car_outlined),
                  ],
                  if (_error != null && _step == 1) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      if (_vehicleType != "Bicicleta" && _plateCtrl.text.trim().isEmpty) {
                        setState(() => _error = "La patente es obligatoria para ${_vehicleType == "Auto" ? "autos" : "motos"}");
                        return;
                      }
                      _next();
                    },
                    child: const Text("Siguiente"),
                  ),
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
                  if (_error != null && _step == 2) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      if (_accountNumCtrl.text.isEmpty || _accountHolderCtrl.text.isEmpty) {
                        setState(() => _error = "Completa todos los campos bancarios");
                        return;
                      }
                      _next();
                    },
                    child: const Text("Siguiente"),
                  ),
                ]),
              ),
              // PASO 4: Términos, consentimientos y firma digital
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Terminos y firma", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text("Revisa el contrato, acepta los consentimientos y firma digitalmente", style: TextStyle(color: AppColors.textLight, fontSize: 14)),
                  const SizedBox(height: 16),

                  // Contrato colapsable
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
                    child: Column(children: [
                      InkWell(
                        onTap: () => setState(() => _showContract = !_showContract),
                        borderRadius: BorderRadius.vertical(top: const Radius.circular(12), bottom: _showContract ? Radius.zero : const Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(children: [
                            const Icon(Icons.article_outlined, color: AppColors.accent, size: 20),
                            const SizedBox(width: 10),
                            const Expanded(child: Text("Contrato de Repartidor Independiente", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                            Icon(_showContract ? Icons.expand_less : Icons.expand_more, color: AppColors.textLight),
                          ]),
                        ),
                      ),
                      if (_showContract)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Text(_contractSummary, style: const TextStyle(fontSize: 10, height: 1.5, color: AppColors.textMedium)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Consentimientos
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDDD6FE))),
                    child: Column(children: [
                      const Text("📋 Consentimientos requeridos", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF5B21B6))),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        dense: true, contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.accent,
                        title: const Text("Acepto el Contrato de Repartidor Independiente de Go Deli.", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        value: _termContract,
                        onChanged: (v) => setState(() => _termContract = v ?? false),
                      ),
                      CheckboxListTile(
                        dense: true, contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.accent,
                        title: const Text("Acepto la Política de Privacidad de GO DELI.", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        value: _termPrivacy,
                        onChanged: (v) => setState(() => _termPrivacy = v ?? false),
                      ),
                      CheckboxListTile(
                        dense: true, contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.accent,
                        title: const Text("Autorizo el tratamiento de mis datos personales y geolocalización.", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        value: _termGeo,
                        onChanged: (v) => setState(() => _termGeo = v ?? false),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Firma digital
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, width: 2)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("✍️ Firma digital del Repartidor", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _field(_signerNameCtrl, "Nombre completo *", Icons.person_outline)),
                        const SizedBox(width: 12),
                        Expanded(child: _field(_signerRutCtrl, "RUT *", Icons.badge_outlined)),
                      ]),
                      const SizedBox(height: 12),
                      // Canvas de firma
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppColors.border, width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(children: [
                          RepaintBoundary(
                            key: _signatureKey,
                            child: GestureDetector(
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              child: CustomPaint(
                                painter: _SignaturePainter(_signatureStrokes, _currentStroke),
                                size: const Size(double.infinity, 120),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: AppColors.border)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Dibuja tu firma arriba", style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                                TextButton.icon(
                                  onPressed: _clearSignature,
                                  icon: const Icon(Icons.delete_outline, size: 14),
                                  label: const Text("Limpiar", style: TextStyle(fontSize: 11)),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.textLight, padding: const EdgeInsets.symmetric(horizontal: 8)),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      const Text("🔒 Al firmar se registrará tu IP, dispositivo, email, fecha y hora. La firma electrónica tiene validez legal conforme a la Ley N° 19.799.", style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                    ]),
                  ),

                  if (_error != null && _step == 3) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: rider.loading ? null : _submit,
                    child: rider.loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Firmar y enviar solicitud ✍️"),
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

// ── Signature painter ──
class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  _SignaturePainter(this.strokes, this.currentStroke);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A0033)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (currentStroke.length >= 2) {
      final path = Path()..moveTo(currentStroke.first.dx, currentStroke.first.dy);
      for (int i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }
      canvas.drawPath(path, paint);
    } else if (currentStroke.length == 1) {
      final p = currentStroke.first;
      canvas.drawCircle(p, 1.5, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}
