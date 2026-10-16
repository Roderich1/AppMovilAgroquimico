import 'operation_id.dart';
import 'sync_types.dart';

/// Envelope v1 exacto (contrato F05 §4): seis claves, la whitelist F06 de
/// cada acción y nada más. CANCEL no lleva `quantity_base`.
Map<String, Object?> envelopeOf(OutboxEntry entry) => {
  'contractVersion': 1,
  'operationId': entry.operationId,
  'projectionType': entry.projectionType.code,
  'action': entry.action.code,
  'causal': {
    'predecessorOperationId': entry.predecessorOperationId,
    'reconciliationReference': entry.reconciliationReference,
  },
  'payload': {
    'campaign_ref': entry.campaignRef,
    'product_ref': entry.productRef,
    'base_unit': entry.baseUnit.code,
    if (entry.action.carriesValue) 'quantity_base': entry.quantityBase,
  },
};

enum AckOutcome {
  applied('APPLIED', 'RETIRE_FROM_OUTBOX', {'OK'}),
  alreadyApplied('ALREADY_APPLIED', 'RETIRE_FROM_OUTBOX', {'OK'}),
  conflict('CONFLICT', 'KEEP_FOR_RECONCILIATION', {
    'CAUSAL_FORK',
    'STALE_PREDECESSOR',
    'CANCELLED_PREDECESSOR',
    'RECONCILIATION_STALE',
  }),
  rejected('REJECTED', 'MOVE_TO_TERMINAL_FAILURE', {
    'IDEMPOTENCY_MISMATCH',
    'CAMPAIGN_NOT_OPEN',
    'REFERENCE_UNAVAILABLE',
    'UNIT_INCOMPATIBLE',
    'QUANTITY_INVALID',
    'INVALID_PREDECESSOR',
    'INVALID_TRANSITION',
    'OWNERSHIP_NOT_PROVEN',
    'PURPOSE_NOT_AUTHORIZED',
    'CAUSAL_FENCED',
  }),
  retryable('RETRYABLE', 'KEEP_FOR_RETRY', {
    'OPERATION_IN_PROGRESS',
    'DEPENDENCY_PENDING',
    'TRANSIENT_UNAVAILABLE',
  });

  const AckOutcome(this.code, this.disposition, this.codes);
  final String code;

  /// Disposition obligatoria para este outcome (§7).
  final String disposition;

  /// Códigos admitidos para este outcome (§8).
  final Set<String> codes;

  bool get isAccepted => this == applied || this == alreadyApplied;
}

/// ACK validado. Sólo se construye si el cuerpo es exactamente el de §7 para
/// la intención enviada; cualquier otra cosa es OUTCOME_UNKNOWN local.
class SyncAck {
  const SyncAck({
    required this.operationId,
    required this.outcome,
    required this.code,
    required this.serverAcceptedAt,
    required this.reconciliationReference,
  });

  final String operationId;
  final AckOutcome outcome;
  final String code;
  final String? serverAcceptedAt;
  final String? reconciliationReference;

  static const _keys = {
    'contractVersion',
    'operationId',
    'outcome',
    'disposition',
    'serverAcceptedAt',
    'code',
    'reconciliationReference',
  };

  static final RegExp _timestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  );

  /// null si [json] no es un ACK coherente para [expectedOperationId]: claves
  /// distintas de las siete, otra intención, disposition contradictoria,
  /// código ajeno al outcome, hora ausente en una aceptación o referencia
  /// ausente en un conflicto.
  static SyncAck? validate(Object? json, String expectedOperationId) {
    if (json is! Map<String, dynamic>) return null;
    if (json.length != _keys.length || !_keys.containsAll(json.keys)) {
      return null;
    }
    final version = json['contractVersion'];
    if (version is! int || version != 1) return null;
    if (json['operationId'] != expectedOperationId) return null;
    AckOutcome? outcome;
    for (final candidate in AckOutcome.values) {
      if (candidate.code == json['outcome']) outcome = candidate;
    }
    if (outcome == null) return null;
    if (json['disposition'] != outcome.disposition) return null;
    final code = json['code'];
    if (code is! String || !outcome.codes.contains(code)) return null;
    final acceptedAt = json['serverAcceptedAt'];
    if (outcome.isAccepted) {
      if (acceptedAt is! String || !_timestamp.hasMatch(acceptedAt)) {
        return null;
      }
      if (DateTime.tryParse(acceptedAt) == null) return null;
    } else if (acceptedAt != null) {
      return null;
    }
    final reference = json['reconciliationReference'];
    if (outcome == AckOutcome.conflict) {
      if (reference is! String || !uuidV4Lowercase.hasMatch(reference)) {
        return null;
      }
    } else if (reference != null) {
      return null;
    }
    return SyncAck(
      operationId: expectedOperationId,
      outcome: outcome,
      code: code,
      serverAcceptedAt: acceptedAt as String?,
      reconciliationReference: reference as String?,
    );
  }
}

/// Cuerpo de error cerrado de §9 (cuatro claves, operationId null).
class SyncRequestError {
  const SyncRequestError(this.errorCode, this.disposition);

  final String errorCode;
  final String disposition;

  static const _keys = {
    'contractVersion',
    'operationId',
    'errorCode',
    'disposition',
  };

  static const _dispositions = <String, String>{
    'INVALID_REQUEST': 'MOVE_TO_TERMINAL_FAILURE',
    'FIELD_NOT_ALLOWED': 'MOVE_TO_TERMINAL_FAILURE',
    'UNSUPPORTED_MEDIA_TYPE': 'MOVE_TO_TERMINAL_FAILURE',
    'REQUEST_TOO_LARGE': 'MOVE_TO_TERMINAL_FAILURE',
    'AUTH_REQUIRED': 'KEEP_FOR_RETRY',
    'RATE_LIMITED': 'KEEP_FOR_RETRY',
    'TEMPORARILY_UNAVAILABLE': 'KEEP_FOR_RETRY',
    'OPERATION_NOT_FOUND': 'KEEP_FOR_RETRY',
    'CONTRACT_VERSION_MISMATCH': 'KEEP_FOR_RECONCILIATION',
    'AUTH_CONTEXT_FORBIDDEN': 'KEEP_FOR_RECONCILIATION',
  };

  static SyncRequestError? validate(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    if (json.length != _keys.length || !_keys.containsAll(json.keys)) {
      return null;
    }
    if (json['contractVersion'] != 1 || json['operationId'] != null) {
      return null;
    }
    final code = json['errorCode'];
    if (code is! String) return null;
    final disposition = _dispositions[code];
    if (disposition == null || json['disposition'] != disposition) return null;
    return SyncRequestError(code, disposition);
  }
}

/// Estado causal actual de la contribución, según `GET /operations/{id}`.
class ContributionView {
  const ContributionView({
    required this.status,
    required this.headOperationId,
    required this.reconciliationReference,
  });

  /// NEVER_PUBLISHED, ACTIVE, CANCELLED o CONTESTED.
  final String status;
  final String? headOperationId;
  final String? reconciliationReference;

  /// Naturaleza del head: una retirada o un valor.
  PredecessorKind get headKind =>
      status == 'CANCELLED' ? PredecessorKind.cancel : PredecessorKind.value;
}

class OperationView {
  const OperationView(this.ack, this.contribution);

  final SyncAck ack;
  final ContributionView? contribution;

  static const _statuses = {
    'NEVER_PUBLISHED',
    'ACTIVE',
    'CANCELLED',
    'CONTESTED',
  };

  /// Exactamente `{ack, contribution}`; contribution con sus tres claves o
  /// null. Sin cantidades.
  static OperationView? validate(Object? json, String operationId) {
    if (json is! Map<String, dynamic>) return null;
    if (json.length != 2 ||
        !json.containsKey('ack') ||
        !json.containsKey('contribution')) {
      return null;
    }
    final ack = SyncAck.validate(json['ack'], operationId);
    if (ack == null) return null;
    final raw = json['contribution'];
    if (raw == null) return OperationView(ack, null);
    if (raw is! Map<String, dynamic> ||
        raw.length != 3 ||
        !raw.containsKey('status') ||
        !raw.containsKey('headOperationId') ||
        !raw.containsKey('reconciliationReference')) {
      return null;
    }
    final status = raw['status'];
    final head = raw['headOperationId'];
    final reference = raw['reconciliationReference'];
    if (status is! String || !_statuses.contains(status)) return null;
    if (head != null && (head is! String || !uuidV4Lowercase.hasMatch(head))) {
      return null;
    }
    if (reference != null &&
        (reference is! String || !uuidV4Lowercase.hasMatch(reference))) {
      return null;
    }
    return OperationView(
      ack,
      ContributionView(
        status: status,
        headOperationId: head as String?,
        reconciliationReference: reference as String?,
      ),
    );
  }
}

/// `Retry-After` en segundos o como fecha HTTP (RFC 9110 §10.2.3). Ilegible
/// o negativo → null: no habilita un reintento inmediato, sólo deja el
/// backoff propio.
Duration? parseRetryAfter(String? value, DateTime now) {
  if (value == null) return null;
  final text = value.trim();
  if (RegExp(r'^\d+$').hasMatch(text)) {
    final seconds = int.tryParse(text);
    return seconds == null ? null : Duration(seconds: seconds);
  }
  final date = _parseHttpDate(text);
  if (date == null) return null;
  final delay = date.difference(now.toUtc());
  return delay.isNegative ? Duration.zero : delay;
}

const _months = {
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};

/// IMF-fixdate: `Sun, 06 Nov 1994 08:49:37 GMT`.
DateTime? _parseHttpDate(String text) {
  final match = RegExp(
    r'^[A-Z][a-z]{2}, (\d{2}) ([A-Z][a-z]{2}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(text);
  if (match == null) return null;
  final month = _months[match.group(2)];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}
