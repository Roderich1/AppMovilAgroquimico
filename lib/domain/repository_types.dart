import 'inventory_alerts.dart' show isCivilDay;
import 'operation_mode.dart';
import 'repository_exceptions.dart';

/// Resultado de corregir vencimiento o número de lote (F04-AV): cuántos
/// lotes cambiaron y cuántos de la línea quedaron sin tocar por no tener la
/// procedencia demostrada.
class LotDataCorrectionResult {
  const LotDataCorrectionResult({
    required this.correctionId,
    required this.correctedLots,
    required this.unprovenLots,
  });
  final int correctionId;
  final int correctedLots;
  final int unprovenLots;
}

/// Modalidad y titular vigentes, leídos dentro de la transacción que escribe.
typedef WriteContext = ({OperationMode mode, int? ownerPersonId});

/// RF-13: responsable y fecha efectiva de la operación revertida, tal como
/// estaban (la operación original no se reasigna).
typedef OriginalOperation = ({int? personId, String? effectiveDate});

/// Filas guardadas de una compra, sin calcular nada (ver `purchaseDetail`).
typedef PurchaseDetailRead = ({
  Map<String, Object?> purchase,
  List<Map<String, Object?>> items,
  List<Map<String, Object?>> allocations,
  List<Map<String, Object?>> payments,
});

/// Una porción de la asignación FIFO de una aplicación: de qué lote y cuánto.
typedef FifoTake = ({Map<String, Object?> lot, int take});

/// Lote que una aplicación consumiría, según la previsión de sólo lectura.
typedef ApplicationLotPreview = ({
  int lotId,
  int quantityBase,
  String? expiryDay,
  String? lotNumber,
});

/// Reparto FIFO de [quantityBase] sobre [lots], ya ordenados del más antiguo
/// al más nuevo y con su cupo en `available`.
List<FifoTake> fifoTakes(List<Map<String, Object?>> lots, int quantityBase) {
  final takes = <FifoTake>[];
  var remaining = quantityBase;
  for (final lot in lots) {
    if (remaining <= 0) break;
    final lotAvailable = lot['available']! as int;
    final take = remaining < lotAvailable ? remaining : lotAvailable;
    takes.add((lot: lot, take: take));
    remaining -= take;
  }
  return takes;
}

/// RF-03: resultado de confirmar o rechazar un borrador tardío.
enum LateResolutionOutcome { confirmed, rejected, conflict }

/// Códigos de conflicto de una confirmación tardía que no se aplicó.
abstract final class LateConflict {
  /// El cupo temporal de los lotes no alcanza (§2.3).
  static const stockUnavailable = 'LATE_STOCK_UNAVAILABLE';

  /// La fecha ya no clasifica en la campaña capturada (§2.3, I4 de B).
  static const campaignChanged = 'LATE_CAMPAIGN_CHANGED';
}

class LateResolution {
  const LateResolution(
    this.outcome, {
    this.operationId,
    this.conflictCode,
    this.message,
  });

  final LateResolutionOutcome outcome;
  final int? operationId;
  final String? conflictCode;
  final String? message;
}

/// Estados en los que un plan todavía **no se ha consumido**.
const List<String> pendingPlanStatuses = ['DRAFT', 'PLANNED'];

/// Estado de un plan ya consumido por su aplicación.
const String appliedPlanStatus = 'APPLIED';

/// Largo máximo del número de lote (decisión del autor del 2026-11-01),
/// en caracteres Unicode, como los cuenta `length()` de SQLite.
const int repositoryMaxLotNumberLength = 100;

/// Plazo de aviso admitido, en días (F04-AV).
const int repositoryMaxAlertLeadDays = 365;

/// Referencia que firma la autorización de una corrección de lote.
String lotDataSubjectRef(int purchaseItemId) => 'purchase_item:$purchaseItemId';

/// Número de lote sin espacios a los lados; vacío es «sin dato» (null).
String? normalizeRepositoryLotNumber(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final error = repositoryLotNumberLengthError(trimmed);
  if (error != null) throw BusinessRuleException(error);
  return trimmed;
}

/// Mensaje si [text] (sin los espacios de los lados) pasa del largo máximo.
String? repositoryLotNumberLengthError(String text) {
  final length = text.trim().runes.length;
  if (length <= repositoryMaxLotNumberLength) return null;
  return 'El número de lote admite hasta $repositoryMaxLotNumberLength caracteres; '
      'tiene $length. Revise lo escrito: no se recorta.';
}

/// Valida el formato de fecha civil de vencimiento (`aaaa-mm-dd`) si no es nulo.
void checkRepositoryExpiryDay(String? day) {
  if (day != null && !isCivilDay(day)) {
    throw BusinessRuleException(
      'La fecha de vencimiento no es válida (aaaa-mm-dd).',
    );
  }
}
