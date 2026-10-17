/// Compatibilidad temporal entre una campaña local y la campaña central con
/// la que se vincula (D-F04-C2; RN-15, RN-16).
///
/// Regla: el período local tiene que estar **contenido** en el central, con
/// los extremos inclusivos. Un fin local abierto no demuestra contención
/// frente a un central con fin: hay que fijar un fin local explícito que
/// quepa. Período y estado son cosas distintas: fijar el fin no cierra la
/// campaña.
///
/// **Fecha civil frente a instante.** `GET /sync/v1/references` publica
/// `start_date` y `end_date` como `date-time` ISO-8601 en UTC. Central guarda
/// el día civil que la Web eligió («2026-09-01») como medianoche UTC
/// («2026-09-01T00:00:00.000Z»); por eso el día central es la **parte de
/// fecha en UTC** del valor, sin pasarlo a hora local: en La Paz (−04:00) esa
/// conversión lo movería al 31/08. Las fechas locales, en cambio, son
/// instantes guardados por este teléfono y siguen la regla de día local de
/// `campaign_calendar.dart`.
///
/// Todo aquí es puro.
library;

import '../campaign_calendar.dart';
import 'central_references.dart';

/// Día civil `aaaa-mm-dd` de una fecha central del contrato.
String centralCivilDay(String isoDateTime) {
  final parsed = DateTime.tryParse(isoDateTime);
  if (parsed == null) {
    throw FormatException('Fecha central ilegible', isoDateTime);
  }
  final utc = parsed.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

/// Período de una campaña central, en días civiles.
final class CentralPeriod {
  const CentralPeriod({required this.startDay, this.endDay});

  factory CentralPeriod.of(CentralCampaign campaign) => CentralPeriod(
    startDay: centralCivilDay(campaign.startDate),
    endDay: campaign.endDate == null
        ? null
        : centralCivilDay(campaign.endDate!),
  );

  final String startDay;

  /// `null`: sin fin previsto ni cierre.
  final String? endDay;

  /// «desde dd/mm/aaaa» o «del dd/mm/aaaa al dd/mm/aaaa».
  String get describe => endDay == null
      ? 'desde el ${displayDay(startDay)}'
      : 'del ${displayDay(startDay)} al ${displayDay(endDay!)}';
}

/// Por qué el período local no cabe en el central.
enum PeriodMismatch {
  /// La campaña local empieza antes que la central.
  startsBefore,

  /// La campaña local termina después que la central.
  endsAfter,

  /// La local no tiene fin y la central sí: falta fijar un fin compatible.
  openEndRequired,
}

/// `null` si [local] está contenido en [central] (extremos inclusivos).
PeriodMismatch? periodMismatch(CampaignPeriod local, CentralPeriod central) {
  if (local.startDay.compareTo(central.startDay) < 0) {
    return PeriodMismatch.startsBefore;
  }
  final centralEnd = central.endDay;
  if (centralEnd == null) return null;
  final localEnd = local.endDay;
  if (localEnd == null) return PeriodMismatch.openEndRequired;
  if (localEnd.compareTo(centralEnd) > 0) return PeriodMismatch.endsAfter;
  return null;
}

/// Mensaje para el agricultor con **los dos** períodos y qué hacer.
String periodMismatchMessage({
  required String localName,
  required CampaignPeriod local,
  required String centralName,
  required CentralPeriod central,
  required PeriodMismatch mismatch,
}) {
  final periods =
      '«$localName» va ${local.describe}; «$centralName» del sindicato va '
      '${central.describe}.';
  return switch (mismatch) {
    PeriodMismatch.startsBefore =>
      '$periods La campaña local empieza antes que la del sindicato: su '
          'período tiene que estar dentro del central.',
    PeriodMismatch.endsAfter =>
      '$periods La campaña local termina después que la del sindicato: su '
          'período tiene que estar dentro del central.',
    PeriodMismatch.openEndRequired =>
      '$periods La campaña local no tiene fin y la del sindicato sí: fije un '
          'fin previsto hasta el ${displayDay(central.endDay!)} como máximo '
          '(no hace falta cerrarla).',
  };
}
