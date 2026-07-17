/// Helper para fechas en zona horaria de Chile (America/Santiago).
///
/// Chile usa:
/// - CLST (UTC-3): horario de verano (primer sábado de septiembre → primer sábado de abril)
/// - CLT  (UTC-4): horario de invierno (primer sábado de abril → primer sábado de septiembre)
///
/// Los cambios ocurren a las 00:00 hora local (03:00/04:00 UTC según temporada).
class ChileTime {
  ChileTime._();

  /// Devuelve la fecha/hora actual en zona horaria de Chile.
  static DateTime now() {
    final utc = DateTime.now().toUtc();
    final offset = _chileOffsetHours(utc);
    return utc.add(Duration(hours: offset));
  }

  /// Devuelve "YYYY-MM-DD" de hoy en Chile.
  static String todayString() {
    final n = now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Calcula el offset de Chile respecto a UTC para una fecha UTC dada.
  /// Retorna -4 (CLT/invierno) o -3 (CLST/verano).
  static int _chileOffsetHours(DateTime utc) {
    final aprilFirstSat = _firstSaturday(utc.year, 4);
    final septFirstSat = _firstSaturday(utc.year, 9);

    // Construir fechas de cambio. En Chile el cambio es a medianoche hora local,
    // lo que equivale a 03:00 UTC en invierno (cuando se pasa a verano)
    // y 04:00 UTC en verano (cuando se pasa a invierno). Usamos 03:30 como
    // punto medio seguro para cualquier año.
    final aprilChange = DateTime.utc(utc.year, 4, aprilFirstSat, 3, 30);
    final septChange = DateTime.utc(utc.year, 9, septFirstSat, 3, 30);

    // Entre abril y septiembre → invierno (UTC-4)
    if (utc.isAfter(aprilChange) && utc.isBefore(septChange)) {
      return -4; // CLT
    }
    return -3; // CLST (verano)
  }

  /// Devuelve el día del mes del primer sábado del mes/año dados.
  static int _firstSaturday(int year, int month) {
    final first = DateTime.utc(year, month, 1);
    // weekday: Monday=1 … Sunday=7. Saturday=6.
    final daysUntilSat = (6 - first.weekday + 7) % 7;
    return 1 + daysUntilSat;
  }
}
