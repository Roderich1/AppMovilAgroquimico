import 'package:flutter/material.dart';

import '../../data/agro_repository.dart' show ApplicationLotPreview;
import '../../domain/campaign_calendar.dart' show displayDay;
import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart' show formatQuantity;

/// Aviso de lote vencido en una aplicación (RN-31, RN-32; decisión de
/// presentación del 2026-11-05).
///
/// Las compras admiten vencimientos pasados, y la aplicación consume en FIFO
/// sin mirar el vencimiento (la regla no cambia). Antes de confirmar, el
/// formulario muestra qué lotes usaría la asignación prevista
/// (`AgroRepository.previewApplicationLots`) y avisa si alguno vence antes
/// de la **fecha efectiva de la aplicación** —no de hoy—, para que una
/// aplicación histórica no se marque por un vencimiento posterior a ella.
///
/// Se clasifica con la misma regla de `classifyExpiry` (F04-AV) tomando como
/// «hoy» el día de la aplicación y plazo 0:
///   - vencido: vence **antes** del día de la aplicación;
///   - vence ese día: vence **el mismo** día de la aplicación. No es vencido
///     (el producto todavía vale ese día, como en Inventario, decisión del
///     autor del 2026-11-01), pero se indica aparte;
///   - sin fecha registrada o posterior: no se dice nada.
/// Sólo informa: no bloquea ni cambia la asignación.
enum ApplicationLotExpiry {
  /// Vence antes del día de la aplicación.
  expired,

  /// Vence el mismo día de la aplicación.
  sameDay,
}

/// Uso previsto de un lote que vence antes o el mismo día de la aplicación.
final class ExpiringLotUse {
  const ExpiringLotUse({
    required this.productName,
    required this.unit,
    required this.quantityBase,
    required this.expiryDay,
    required this.lotNumber,
    required this.status,
  });

  final String productName;
  final String unit;
  final int quantityBase;
  final String expiryDay;
  final String? lotNumber;
  final ApplicationLotExpiry status;
}

/// Clasifica el vencimiento de un lote respecto de [applicationDay]
/// (`aaaa-mm-dd`). Nulo si no hay que avisar.
ApplicationLotExpiry? expiryAtApplication({
  required String? expiryDay,
  required String applicationDay,
}) => switch (classifyExpiry(
  expiryDay: expiryDay,
  today: applicationDay,
  leadDays: 0,
)) {
  ExpiryStatus.expired => ApplicationLotExpiry.expired,
  ExpiryStatus.today => ApplicationLotExpiry.sameDay,
  _ => null,
};

/// Los lotes previstos de cada línea que vencen antes o el mismo día de la
/// aplicación, en el orden de la mezcla y del FIFO.
List<ExpiringLotUse> expiringLotUses({
  required String applicationDay,
  required Iterable<
    ({String productName, String unit, List<ApplicationLotPreview> lots})
  >
  lines,
}) => [
  for (final line in lines)
    for (final lot in line.lots)
      if (expiryAtApplication(
            expiryDay: lot.expiryDay,
            applicationDay: applicationDay,
          )
          case final status?)
        ExpiringLotUse(
          productName: line.productName,
          unit: line.unit,
          quantityBase: lot.quantityBase,
          expiryDay: lot.expiryDay!,
          lotNumber: lot.lotNumber,
          status: status,
        ),
];

/// Tarjeta del resumen de la aplicación con los lotes vencidos (en color de
/// error) y los que vencen el mismo día (aparte). No se muestra si no hay
/// ninguno.
class ApplicationExpiryNotice extends StatelessWidget {
  const ApplicationExpiryNotice({
    super.key,
    required this.uses,
    required this.applicationDay,
    required this.isToday,
  });

  final List<ExpiringLotUse> uses;
  final String applicationDay;

  /// Si la aplicación es de hoy, para decir «hoy» en vez de la fecha.
  final bool isToday;

  /// «del lote L-1», o «de un lote» si la compra no registró su número.
  String _fromLot(ExpiringLotUse use) =>
      use.lotNumber == null ? 'de un lote' : 'del lote ${use.lotNumber}';

  @override
  Widget build(BuildContext context) {
    if (uses.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final expired = [
      for (final use in uses)
        if (use.status == ApplicationLotExpiry.expired) use,
    ];
    final sameDay = [
      for (final use in uses)
        if (use.status == ApplicationLotExpiry.sameDay) use,
    ];
    final when = isToday ? 'hoy' : 'el ${displayDay(applicationDay)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expired.isNotEmpty)
          Card(
            key: const Key('application-expiry-expired'),
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Se usará producto vencido',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final use in expired)
                    Text(
                      '${use.productName}: '
                      '${formatQuantity(use.quantityBase, use.unit)} '
                      '${_fromLot(use)}, vencido el ${displayDay(use.expiryDay)}, '
                      'antes de la fecha de la aplicación ($when).',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Se usan primero las compras más antiguas. Revisa el '
                    'producto antes de aplicarlo; si confirmas, la aplicación '
                    'se registra igual.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (sameDay.isNotEmpty)
          Card(
            key: const Key('application-expiry-same-day'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.event_busy_outlined,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isToday
                              ? 'Vence hoy'
                              : 'Vence el día de la aplicación',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final use in sameDay)
                    Text(
                      '${use.productName}: '
                      '${formatQuantity(use.quantityBase, use.unit)} '
                      '${_fromLot(use)}, que vence $when. '
                      '${isToday ? 'Hoy' : 'Ese día'} todavía no está vencido.',
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
