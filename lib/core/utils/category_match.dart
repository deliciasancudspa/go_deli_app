/// ¿La tienda pertenece a la categoría seleccionada?
///
/// Tolerante a diferencias entre el nombre guardado por el aliado y el de la
/// categoría del admin: ignora mayúsculas/acentos, acepta listas separadas
/// por coma ("Medicamentos,Vitaminas y Suplementos") y coincidencias
/// parciales ("Ropa y Moda" ↔ chip "Ropa", "Supermercado" ↔ chip "Mercado").
bool storeMatchesCategory(Map<String, dynamic> store, String? cat) {
  if (cat == null || cat == "Todos" || cat == "Todas") return true;
  final c = _norm(cat);
  if (c.isEmpty) return true;
  final raw = store["category"] as String? ?? "";
  return raw.split(",").any((tok) {
    final t = _norm(tok);
    return t.isNotEmpty && (t == c || t.contains(c) || c.contains(t));
  });
}

String _norm(String s) {
  var out = s.toLowerCase().trim();
  const accents = {
    "á": "a", "à": "a", "ä": "a", "â": "a",
    "é": "e", "è": "e", "ë": "e", "ê": "e",
    "í": "i", "ì": "i", "ï": "i", "î": "i",
    "ó": "o", "ò": "o", "ö": "o", "ô": "o",
    "ú": "u", "ù": "u", "ü": "u", "û": "u",
    "ñ": "n",
  };
  accents.forEach((k, v) => out = out.replaceAll(k, v));
  return out;
}
