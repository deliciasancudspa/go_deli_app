import "package:flutter/material.dart";
import "../../l10n/app_localizations.dart";
import "../theme/app_theme.dart";

/// Google Play — Prominent Disclosure para ubicación en segundo plano.
///
/// REQUISITO: La app usa ACCESS_BACKGROUND_LOCATION. Google exige mostrar
/// este diálogo ANTES del diálogo nativo de permisos del sistema operativo.
///
/// Muestra al repartidor:
/// - Qué datos se recopilan (ubicación precisa en segundo plano)
/// - Para qué se usan (asignar pedidos cercanos, rastreo de entregas)
/// - Que funciona incluso con la app en segundo plano o cerrada
///
/// Retorna `true` si el usuario acepta, `false` si rechaza.
Future<bool> showLocationDisclosureDialog(BuildContext context) async {
  final loc = AppLocalizations.of(context)!;
  final tc = ThemeColors.of(context);

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.location_on, color: AppColors.accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(loc.locDisclosureTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
      ]),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.locDisclosureBody, style: TextStyle(fontSize: 14, color: tc.textMedium, height: 1.5)),
            const SizedBox(height: 16),
            _bullet(loc.locDisclosureBullet1, tc),
            const SizedBox(height: 10),
            _bullet(loc.locDisclosureBullet2, tc),
            const SizedBox(height: 10),
            _bullet(loc.locDisclosureBullet3, tc),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text(loc.locDisclosureNote, style: const TextStyle(fontSize: 11, color: AppColors.textMedium, height: 1.4))),
              ]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(loc.cancel, style: TextStyle(color: tc.textLight)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(loc.locDisclosureAccept),
        ),
      ],
    ),
  );

  return result ?? false;
}

Widget _bullet(String text, ThemeColors tc) {
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(
      margin: const EdgeInsets.only(top: 4),
      width: 6, height: 6,
      decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
    ),
    const SizedBox(width: 10),
    Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: tc.textMedium, height: 1.4))),
  ]);
}
