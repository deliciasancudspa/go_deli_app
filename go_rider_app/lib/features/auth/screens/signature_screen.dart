import "dart:convert";
import "dart:ui" as ui;
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "../../../core/theme/app_theme.dart";

/// Pantalla dedicada para la firma digital del repartidor.
///
/// Se abre desde el paso 4 del registro. La firma ocupa toda la pantalla,
/// sin competencia de scroll. Al confirmar, devuelve la imagen en base64.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final _signatureKey = GlobalKey<_SignaturePadState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Firma digital"),
        actions: [
          TextButton(
            onPressed: () async {
              if (!_signatureKey.currentState!.isDrawn) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Debes dibujar tu firma antes de confirmar"),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              final sigBase64 = await _signatureKey.currentState!.capture();
              if (mounted) Navigator.pop(context, sigBase64);
            },
            child: const Text("Confirmar", style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _SignaturePad(key: _signatureKey),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Text(
            "🔒 Al firmar se registrará tu IP, dispositivo, email, fecha y hora. "
            "La firma electrónica tiene validez legal conforme a la Ley N° 19.799.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: AppColors.textLight.withOpacity(0.8)),
          ),
        ),
      ]),
    );
  }
}

// ── Signature pad widget ──
class _SignaturePad extends StatefulWidget {
  const _SignaturePad({super.key});

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  bool _drawn = false;
  final GlobalKey _repaintKey = GlobalKey();

  bool get isDrawn => _drawn;

  void _onPanStart(DragStartDetails d) {
    _currentStroke = [d.localPosition];
    _drawn = true;
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _currentStroke.add(d.localPosition);
    setState(() {});
  }

  void _onPanEnd(DragEndDetails d) {
    if (_currentStroke.length > 1) {
      _strokes.add(List.from(_currentStroke));
    }
    _currentStroke = [];
    setState(() {});
  }

  void _clear() {
    _strokes.clear();
    _currentStroke = [];
    _drawn = false;
    setState(() {});
  }

  Future<String?> capture() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return base64Encode(byteData.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _drawn ? AppColors.accent : AppColors.border, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Expanded(
          child: ClipRect(
            child: RepaintBoundary(
              key: _repaintKey,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: CustomPaint(
                  painter: _SignaturePainter(_strokes, _currentStroke),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _drawn ? "✅ Firma capturada" : "Dibuja tu firma en el recuadro",
                style: TextStyle(
                  fontSize: 12,
                  color: _drawn ? AppColors.success : AppColors.textLight,
                  fontWeight: _drawn ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              TextButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text("Limpiar", style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textLight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
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
    // Línea guía punteada
    final guidePaint = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dashW = 6.0, gapW = 4.0;
    var x = 0.0;
    final guideY = size.height * 0.55;
    while (x < size.width) {
      canvas.drawLine(Offset(x, guideY), Offset(x + dashW, guideY), guidePaint);
      x += dashW + gapW;
    }

    // Trazo suavizado con curvas Bezier
    final paint = Paint()
      ..color = const Color(0xFF1A0033)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        final prev = stroke[i - 1];
        final curr = stroke[i];
        final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
        path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
      }
      canvas.drawPath(path, paint);
    }

    if (currentStroke.length >= 2) {
      final path = Path()..moveTo(currentStroke.first.dx, currentStroke.first.dy);
      for (int i = 1; i < currentStroke.length; i++) {
        final prev = currentStroke[i - 1];
        final curr = currentStroke[i];
        final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
        path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
      }
      canvas.drawPath(path, paint);
    } else if (currentStroke.length == 1) {
      final p = currentStroke.first;
      canvas.drawCircle(p, 2, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}
