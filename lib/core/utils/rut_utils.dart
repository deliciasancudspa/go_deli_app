import "package:flutter/services.dart";

class RutInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    final raw = next.text.replaceAll(RegExp(r'[^0-9Kk]'), '').toUpperCase();
    if (raw.length <= 1) {
      return next.copyWith(text: raw, selection: TextSelection.collapsed(offset: raw.length));
    }
    final body = raw.substring(0, raw.length - 1);
    final dv   = raw[raw.length - 1];
    final buf  = StringBuffer();
    for (int i = 0; i < body.length; i++) {
      if (i > 0 && (body.length - i) % 3 == 0) buf.write('.');
      buf.write(body[i]);
    }
    final result = '${buf.toString()}-$dv';
    return next.copyWith(text: result, selection: TextSelection.collapsed(offset: result.length));
  }
}

bool validateRut(String rut) {
  final clean = rut.replaceAll('.', '').replaceAll('-', '').toUpperCase();
  if (clean.length < 2) return false;
  final body = clean.substring(0, clean.length - 1);
  final dv   = clean[clean.length - 1];
  if (int.tryParse(body) == null) return false;
  int sum = 0, m = 2;
  for (int i = body.length - 1; i >= 0; i--) {
    sum += int.parse(body[i]) * m;
    m = m == 7 ? 2 : m + 1;
  }
  final r = 11 - (sum % 11);
  final expected = r == 11 ? '0' : r == 10 ? 'K' : r.toString();
  return dv == expected;
}
