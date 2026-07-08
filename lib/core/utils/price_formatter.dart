import "dart:convert";

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

/// Retorna true si la tienda tiene delivery propio habilitado.
/// El campo delivery_methods puede venir como List (PostgREST JSONB nativo)
/// o como String JSON (guardado con JSON.stringify desde el panel admin).
bool hasOwnDelivery(Map<String, dynamic>? store) {
  if (store == null) return false;
  final methods = store['delivery_methods'];

  // Caso 1: PostgREST devuelve JSONB como List nativa
  if (methods is List) {
    return methods.contains('own');
  }

  // Caso 2: el admin guarda delivery_methods con JSON.stringify → string JSON
  if (methods is String && methods.isNotEmpty) {
    try {
      final decoded = jsonDecode(methods);
      if (decoded is List) return decoded.contains('own');
    } catch (_) {}
  }

  // Si delivery_methods existe (en cualquier formato) pero no contiene 'own',
  // NO debe caer al fallback de delivery_priority. Este fallback solo aplica
  // cuando delivery_methods es null/ausente.
  if (methods != null) return false;

  // Fallback: delivery_priority como string ('own' | 'go_rider' | 'both')
  // Solo se usa si no hay delivery_methods configurado.
  final priority = store['delivery_priority'];
  if (priority is String) return priority == 'own';

  return false;
}
