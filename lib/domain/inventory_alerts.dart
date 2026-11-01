/// Avisos de existencias y vencimiento (F04-AV, MOB #168–#171).
///
/// Fuentes de la numeración: RU-22, RN-31, RN-32, RF-42 a RF-44, DAT-22 y
/// CU-22 son los del Cap. III y el Apéndice A de la tesis (v1.22.1). **No**
/// son las RN-31/RN-32 de `docs/15_BUSINESS_RULES.md` de este repositorio,
/// que numeran otras reglas (de transferencias).
///
/// Todo aquí es puro: recibe filas ya leídas y el día de hoy, y no escribe
/// nada. Los avisos se derivan al consultar y no se guardan (DAT-22): no
/// cambian cantidades, movimientos ni el orden de consumo, no bloquean
/// operaciones y no se publican al Sindicato (RN-32).
library;

/// Clasificación del vencimiento de un lote con cantidad remanente (RN-31).
enum ExpiryStatus {
  /// La fecha es anterior a la de hoy en el teléfono.
  expired,

  /// Vence hoy o dentro del plazo de aviso del producto.
  near,

  /// Vence después del plazo: no genera aviso.
  later,

  /// Sin fecha registrada: ni vigente ni vencido.
  unknown,
}

/// `true` si [day] es un día civil `aaaa-mm-dd` válido.
bool isCivilDay(String day) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
  if (match == null) return false;
  final y = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final d = int.parse(match.group(3)!);
  final parsed = DateTime.utc(y, m, d);
  return parsed.year == y && parsed.month == m && parsed.day == d;
}

DateTime _utcDay(String day) => DateTime.utc(
  int.parse(day.substring(0, 4)),
  int.parse(day.substring(5, 7)),
  int.parse(day.substring(8, 10)),
);

/// Días de calendario de [from] a [to] (negativo si [to] es anterior). Se
/// cuentan sobre fechas UTC para que un cambio de horario no reste un día.
int daysBetween(String from, String to) =>
    _utcDay(to).difference(_utcDay(from)).inDays;

/// Clasifica un vencimiento respecto de [today] con el plazo [leadDays].
ExpiryStatus classifyExpiry({
  required String? expiryDay,
  required String today,
  required int leadDays,
}) {
  if (expiryDay == null) return ExpiryStatus.unknown;
  final days = daysBetween(today, expiryDay);
  if (days < 0) return ExpiryStatus.expired;
  if (days <= leadDays) return ExpiryStatus.near;
  return ExpiryStatus.later;
}

/// Un lote con cantidad remanente, tal como lo lee el repositorio.
final class AlertLot {
  const AlertLot({
    required this.lotId,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.ownerPersonId,
    required this.ownerName,
    required this.remainingBase,
    required this.leadDays,
    required this.leadDaysIsDefault,
    this.expiryDay,
    this.lotNumber,
  });

  final int lotId;
  final int productId;
  final String productName;
  final String unit;
  final int ownerPersonId;
  final String ownerName;
  final int remainingBase;
  final String? expiryDay;
  final String? lotNumber;

  /// Plazo de aviso efectivo del producto.
  final int leadDays;

  /// `true` si el producto usa el valor inicial (no lo definió el titular).
  final bool leadDaysIsDefault;
}

/// Aviso de vencimiento de un lote (RF-43).
final class LotExpiryAlert {
  const LotExpiryAlert({
    required this.lot,
    required this.status,
    required this.days,
  });

  final AlertLot lot;
  final ExpiryStatus status;

  /// Días hasta el vencimiento (positivo o 0) o transcurridos desde él
  /// (positivo, si está vencido). Nulo si no hay fecha.
  final int? days;
}

/// Existencia neta de un producto en un ámbito: una persona responsable o el
/// total de la instalación.
final class StockLine {
  const StockLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.netBase,
    this.personId,
    this.personName,
  });

  final int productId;
  final String productName;
  final String unit;
  final int netBase;

  /// Nulo para el total de la instalación.
  final int? personId;
  final String? personName;

  bool get isTotal => personId == null;
}

/// Configuración de avisos de un producto (RF-44).
final class ProductAlertSettings {
  const ProductAlertSettings({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.active,
    this.minStockBase,
    this.leadDays,
  });

  final int productId;
  final String productName;
  final String unit;
  final bool active;

  /// Nulo: sin nivel mínimo definido (distinto de cero).
  final int? minStockBase;

  /// Nulo: usa el valor inicial.
  final int? leadDays;
}

/// Aviso de existencia baja (RN-32): la existencia neta es menor o igual al
/// nivel mínimo.
final class LowStockAlert {
  const LowStockAlert({required this.line, required this.minStockBase});
  final StockLine line;
  final int minStockBase;
}

/// Resultado de una consulta de avisos. Se calcula entero o falla entero:
/// no hay resultados parciales (CU-22 E1).
final class InventoryAlerts {
  const InventoryAlerts({
    required this.today,
    required this.shared,
    required this.expired,
    required this.near,
    required this.unknownDate,
    required this.lowStock,
    required this.productsWithoutLevel,
    required this.defaultLeadDays,
    this.lastMovementDay,
  });

  /// Día del teléfono con que se clasificó.
  final String today;

  /// Modalidad compartida: avisos por responsable y total (CU-22 A3).
  final bool shared;
  final List<LotExpiryAlert> expired;
  final List<LotExpiryAlert> near;
  final List<LotExpiryAlert> unknownDate;
  final List<LowStockAlert> lowStock;

  /// Productos activos sin nivel mínimo: no se avisa su existencia baja,
  /// y se indica que puede definirse (CU-22 A2).
  final List<ProductAlertSettings> productsWithoutLevel;
  final int defaultLeadDays;

  /// Día local del movimiento más reciente, si lo hay.
  final String? lastMovementDay;

  /// CU-22 E2: el último movimiento es de un día posterior a hoy en el
  /// teléfono, así que el reloj puede estar mal y la clasificación depende
  /// de él.
  bool get clockLooksBehind =>
      lastMovementDay != null && daysBetween(today, lastMovementDay!) > 0;
}

/// Rango del selector de fecha de vencimiento: diez años atrás y quince
/// adelante, ampliado para que una fecha ya guardada fuera de ese rango
/// siga siendo válida como fecha inicial.
({DateTime first, DateTime initial, DateTime last}) expiryPickerRange(
  DateTime? current,
  DateTime now,
) {
  var first = DateTime(now.year - 10);
  var last = DateTime(now.year + 15, 12, 31);
  final initial = current ?? DateTime(now.year, now.month, now.day);
  if (initial.isBefore(first)) first = initial;
  if (initial.isAfter(last)) last = initial;
  return (first: first, initial: initial, last: last);
}

/// Plazo de aviso en palabras: «el mismo día», «1 día», «N días».
String leadDaysText(int days) => switch (days) {
  0 => 'el mismo día del vencimiento',
  1 => '1 día antes',
  _ => '$days días antes',
};

/// Calcula los avisos a partir de las filas leídas. [today] es el día local
/// del teléfono (inyectable para las pruebas).
InventoryAlerts computeInventoryAlerts({
  required String today,
  required bool shared,
  required List<AlertLot> lots,
  required List<ProductAlertSettings> products,
  required List<StockLine> stock,
  required int defaultLeadDays,
  String? lastMovementDay,
}) {
  final expired = <LotExpiryAlert>[];
  final near = <LotExpiryAlert>[];
  final unknown = <LotExpiryAlert>[];
  for (final lot in lots) {
    // Un lote agotado no avisa (MOB #171).
    if (lot.remainingBase <= 0) continue;
    final status = classifyExpiry(
      expiryDay: lot.expiryDay,
      today: today,
      leadDays: lot.leadDays,
    );
    final days = lot.expiryDay == null
        ? null
        : daysBetween(today, lot.expiryDay!).abs();
    final alert = LotExpiryAlert(lot: lot, status: status, days: days);
    switch (status) {
      case ExpiryStatus.expired:
        expired.add(alert);
      case ExpiryStatus.near:
        near.add(alert);
      case ExpiryStatus.unknown:
        unknown.add(alert);
      case ExpiryStatus.later:
        break;
    }
  }
  // Más urgente primero: el más vencido, el que vence antes.
  expired.sort((a, b) => b.days!.compareTo(a.days!));
  near.sort((a, b) => a.days!.compareTo(b.days!));
  unknown.sort(
    (a, b) => a.lot.productName.compareTo(b.lot.productName) != 0
        ? a.lot.productName.compareTo(b.lot.productName)
        : a.lot.ownerName.compareTo(b.lot.ownerName),
  );

  final byId = {for (final p in products) p.productId: p};
  final low = <LowStockAlert>[];
  for (final line in stock) {
    final product = byId[line.productId];
    final min = product?.minStockBase;
    if (product == null || !product.active || min == null) continue;
    // En propio sólo hay un ámbito: el total, que es el del titular.
    if (!shared && !line.isTotal) continue;
    if (line.netBase <= min) {
      low.add(LowStockAlert(line: line, minStockBase: min));
    }
  }
  low.sort((a, b) {
    final byName = a.line.productName.compareTo(b.line.productName);
    if (byName != 0) return byName;
    // El total primero, después cada responsable.
    if (a.line.isTotal != b.line.isTotal) return a.line.isTotal ? -1 : 1;
    return (a.line.personName ?? '').compareTo(b.line.personName ?? '');
  });

  return InventoryAlerts(
    today: today,
    shared: shared,
    expired: expired,
    near: near,
    unknownDate: unknown,
    lowStock: low,
    productsWithoutLevel: [
      for (final p in products)
        if (p.active && p.minStockBase == null) p,
    ]..sort((a, b) => a.productName.compareTo(b.productName)),
    defaultLeadDays: defaultLeadDays,
    lastMovementDay: lastMovementDay,
  );
}
