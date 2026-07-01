/// Formatea un número entero (CLP sin decimales) con separadores de miles.
/// Ejemplo: fmtCLP(4500) → "$4.500"
String fmtCLP(int? n) {
  if (n == null) return "\$0";
  return "\$${n.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";
}

/// Formatea un double con decimales y separadores de miles.
/// Ejemplo: fmtDecimal(4500.50) → "$4.500,50"
String fmtDecimal(double? n, {int decimals = 0}) {
  if (n == null) return "\$0";
  final parts = n.toStringAsFixed(decimals).split(".");
  parts[0] = parts[0].replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.");
  return "\$${parts.join(",")}";
}

/// Limpia y formatea el delivery_time de la BD para evitar duplicar "min".
/// Ejemplo: "30-45 min" → "30-45 min", "30-45" → "30-45 min"
String cleanDeliveryTime(dynamic raw) {
  final s = (raw?.toString() ?? "30-45").replaceAll(RegExp(r'\s*min', caseSensitive: false), "").trim();
  return "$s min";
}
