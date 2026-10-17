/// Calendario de campañas por fecha efectiva (RN-15, RN-16, RF-03).
///
/// Una campaña cubre `[inicio, fin]` en **días locales**, los dos inclusivos;
/// sin fin, queda abierta. Es la misma lectura que usa F05 para las
/// necesidades declaradas (`DeclaredNeedStore.campaignForDate`): las fechas
/// se guardan como instantes UTC y el día se toma en la zona local, de modo
/// que una operación a las 22:00 en La Paz cuenta en su día y no en el UTC
/// siguiente.
///
/// Todo aquí es puro: el repositorio lee las filas y decide dentro de su
/// transacción.
library;

/// Día local `aaaa-mm-dd` de un instante.
String localDay(DateTime instant) {
  final local = instant.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// Día local de una fecha guardada (instante ISO-8601). Un texto que no se
/// puede leer como instante se toma por sus diez primeros caracteres, como
/// en F05.
String storedLocalDay(String stored) {
  final parsed = DateTime.tryParse(stored);
  if (parsed != null) return localDay(parsed);
  return stored.length < 10 ? stored : stored.substring(0, 10);
}

DateTime _localMidnight(String day) => DateTime(
  int.parse(day.substring(0, 4)),
  int.parse(day.substring(5, 7)),
  int.parse(day.substring(8, 10)),
);

/// Medianoche local del día: el instante que se guarda como fin de campaña,
/// para que [storedLocalDay] devuelva exactamente ese día.
DateTime startOfLocalDay(String day) => _localMidnight(day);

/// Día local anterior (los cambios de horario no lo alteran: se opera sobre
/// la fecha, no sobre horas).
String previousLocalDay(String day) {
  final d = _localMidnight(day);
  return localDay(DateTime(d.year, d.month, d.day - 1));
}

/// Día local siguiente.
String nextLocalDay(String day) {
  final d = _localMidnight(day);
  return localDay(DateTime(d.year, d.month, d.day + 1));
}

/// `dd/mm/aaaa` para los mensajes.
String displayDay(String day) =>
    '${day.substring(8, 10)}/${day.substring(5, 7)}/${day.substring(0, 4)}';

/// Período de una campaña leído de su fila.
final class CampaignPeriod {
  const CampaignPeriod({
    required this.id,
    required this.name,
    required this.status,
    required this.startDay,
    this.endDay,
  });

  factory CampaignPeriod.fromRow(Map<String, Object?> row) {
    final end = row['end_date'] as String?;
    return CampaignPeriod(
      id: row['id']! as int,
      name: row['name']! as String,
      status: row['status']! as String,
      startDay: storedLocalDay(row['start_date']! as String),
      endDay: end == null ? null : storedLocalDay(end),
    );
  }

  final int id;
  final String name;
  final String status;
  final String startDay;

  /// `null`: abierta.
  final String? endDay;

  bool contains(String day) =>
      startDay.compareTo(day) <= 0 &&
      (endDay == null || endDay!.compareTo(day) >= 0);

  bool overlaps(CampaignPeriod other) =>
      (endDay == null || other.startDay.compareTo(endDay!) <= 0) &&
      (other.endDay == null || startDay.compareTo(other.endDay!) <= 0);

  CampaignPeriod withEnd(String? day) => CampaignPeriod(
    id: id,
    name: name,
    status: status,
    startDay: startDay,
    endDay: day,
  );

  /// «desde dd/mm/aaaa» o «del dd/mm/aaaa al dd/mm/aaaa».
  String get describe => endDay == null
      ? 'desde el ${displayDay(startDay)}'
      : 'del ${displayDay(startDay)} al ${displayDay(endDay!)}';
}

/// Campañas cuyo período contiene el día.
List<CampaignPeriod> campaignsContaining(
  Iterable<CampaignPeriod> periods,
  String day,
) => [
  for (final period in periods)
    if (period.contains(day)) period,
];
