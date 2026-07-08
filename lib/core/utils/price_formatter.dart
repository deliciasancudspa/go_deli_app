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

/// Retorna true si la tienda usa exclusivamente repartidor propio
/// (no tiene Go Rider habilitado). El campo delivery_methods es JSONB,
/// Supabase lo devuelve como List<dynamic>.
bool hasOwnDelivery(Map<String, dynamic>? store) {
  if (store == null) return false;
  final methods = store['delivery_methods'];
  if (methods is List) {
    // Si el aliado tiene delivery propio habilitado, no se cobra tarifa de
    // envío al cliente (la tienda usa sus propios repartidores).
    return methods.contains('own');
  }
  // Fallback: delivery_priority como string
  final priority = store['delivery_priority'];
  if (priority is String) return priority == 'own';
  return false;
}
