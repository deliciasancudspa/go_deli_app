import "package:flutter/material.dart";

/// Parsea un string hex (ej. "#FF6B00" o "FF6B00") a un Color.
/// Retorna [fallback] si el string es inválido (por defecto Colors.grey).
Color parseHexColor(String? hex, {Color fallback = Colors.grey}) {
  if (hex == null || hex.isEmpty) return fallback;
  try {
    final h = hex.startsWith("#") ? hex.substring(1) : hex;
    if (h.length == 6) {
      return Color(int.parse("FF$h", radix: 16));
    }
    if (h.length == 8) {
      return Color(int.parse(h, radix: 16));
    }
    return fallback;
  } catch (_) {
    return fallback;
  }
}
