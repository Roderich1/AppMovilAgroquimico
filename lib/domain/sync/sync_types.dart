/// Tipos de la proyección colectiva mínima (contrato F06 §2). Sólo estos dos
/// cruzan al sindicato.
enum ProjectionType {
  consumptionTotal('CONSUMPTION_TOTAL'),
  declaredNeed('DECLARED_NEED');

  const ProjectionType(this.code);
  final String code;

  static ProjectionType fromCode(Object? code) =>
      values.firstWhere((type) => type.code == code);
}

/// Acción de dominio de una intención (F06 §6). Una cantidad siempre es un
/// total, nunca un delta.
enum SyncAction {
  publish('PUBLISH'),
  supersede('SUPERSEDE'),
  cancel('CANCEL');

  const SyncAction(this.code);
  final String code;

  bool get carriesValue => this != cancel;

  static SyncAction fromCode(Object? code) =>
      values.firstWhere((action) => action.code == code);
}

/// Naturaleza del antecesor que una intención continúa: un valor vigente o
/// una retirada. Decide qué acción admite Central (contrato F05 §6): tras un
/// valor, SUPERSEDE o CANCEL; tras una retirada, sólo PUBLISH.
enum PredecessorKind {
  value('VALUE'),
  cancel('CANCEL');

  const PredecessorKind(this.code);
  final String code;

  static PredecessorKind? fromCode(Object? code) =>
      code == null ? null : values.firstWhere((kind) => kind.code == code);

  static PredecessorKind of(SyncAction action) =>
      action == SyncAction.cancel ? cancel : value;
}

/// Unidad base de la proyección (F06 §2): mililitros o gramos.
enum BaseUnit {
  ml('ML', 'L'),
  g('G', 'KG');

  const BaseUnit(this.code, this.majorUnit);
  final String code;

  /// Unidad central que le corresponde (L o KG).
  final String majorUnit;

  static BaseUnit? fromCode(Object? code) {
    for (final unit in values) {
      if (unit.code == code) return unit;
    }
    return null;
  }

  /// Unidad base de una unidad central. Sólo L y KG tienen equivalencia
  /// verificada; se ignora la caja del símbolo, como en Central.
  static BaseUnit? forCentralUnit(String unit) => switch (unit.toUpperCase()) {
    'L' => ml,
    'KG' => g,
    _ => null,
  };
}

/// Estado local de una intención en la outbox.
enum OutboxStatus {
  /// Lista para enviarse (o reintentarse con backoff).
  pending('PENDING'),

  /// Marcada antes de enviar; tras un cierre forzado se reenvía igual.
  sending('SENDING'),

  /// Pudo llegar a Central sin respuesta fiable: se reenvía la misma intención.
  outcomeUnknown('OUTCOME_UNKNOWN'),

  /// Central confirmó la aceptación (APPLIED o ALREADY_APPLIED).
  acked('ACKED'),

  /// Central la registró como conflicto: decide el propietario.
  conflict('CONFLICT'),

  /// Central la rechazó; no se reintenta.
  rejected('REJECTED'),

  /// Central no admitió el request (400/413/415); no se reintenta.
  failed('FAILED'),

  /// El contexto de la cuenta fue rechazado (403); espera reautenticar.
  authPaused('AUTH_PAUSED'),

  /// El vínculo de titular ya no es el activo: no se envía bajo otro.
  ownerPaused('OWNER_PAUSED'),

  /// Llegó con una restauración: espera que el titular la libere.
  restorePaused('RESTORE_PAUSED'),

  /// Central no acepta esta versión del contrato (422).
  versionMismatch('VERSION_MISMATCH'),

  /// Nunca salió del teléfono y una decisión posterior la dejó sin objeto.
  discarded('DISCARDED');

  const OutboxStatus(this.code);
  final String code;

  static OutboxStatus fromCode(Object? code) =>
      values.firstWhere((status) => status.code == code);

  /// No cambian el estado central: no cuentan como antecesor.
  bool get isTerminalWithoutEffect =>
      this == rejected || this == failed || this == discarded;

  /// El worker puede enviarla si su antecesor ya fue aceptado.
  bool get isSendable =>
      this == pending || this == sending || this == outcomeUnknown;
}

/// Una fila de la outbox. Contiene sólo los cuatro campos de negocio de la
/// whitelist F06, la causalidad F05 y el estado local: ningún nombre, nota,
/// persona, costo ni credencial.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.operationId,
    required this.ownerBindingId,
    required this.projectionType,
    required this.action,
    required this.campaignRef,
    required this.productRef,
    required this.baseUnit,
    required this.quantityBase,
    required this.predecessorOperationId,
    required this.predecessorKind,
    required this.reconciliationReference,
    required this.status,
    required this.attempts,
    this.nextAttemptAt,
    this.lastCode,
    this.ackReconciliationReference,
    this.serverAcceptedAt,
    this.resolutionHeadOperationId,
    this.resolutionHeadKind,
    this.resolvedAt,
    required this.createdAt,
    this.ackedAt,
  });

  final int id;
  final String operationId;
  final int ownerBindingId;
  final ProjectionType projectionType;
  final SyncAction action;
  final String campaignRef;
  final String productRef;
  final BaseUnit baseUnit;

  /// Decimal exacto en texto; null sólo para CANCEL.
  final String? quantityBase;
  final String? predecessorOperationId;
  final PredecessorKind? predecessorKind;
  final String? reconciliationReference;
  final OutboxStatus status;
  final int attempts;
  final String? nextAttemptAt;
  final String? lastCode;

  /// Explicación, sin identificadores, de un rechazo que requiere
  /// intervención y no se reintenta (RF-03 §2.4); null si no hay.
  String? get interventionMessage => rejectionExplanation(lastCode);

  /// Referencia de reconciliación que devolvió un ACK CONFLICT.
  final String? ackReconciliationReference;
  final String? serverAcceptedAt;

  /// Al resolver un conflicto, el propietario decide sobre el head que mostró
  /// Central: se guarda para que las intenciones siguientes lo continúen.
  final String? resolutionHeadOperationId;
  final PredecessorKind? resolutionHeadKind;
  final String? resolvedAt;
  final String createdAt;
  final String? ackedAt;

  /// Nunca salió del teléfono: todavía puede reescribirse sin riesgo de
  /// IDEMPOTENCY_MISMATCH (el intento se registra antes de enviar).
  bool get isUnsent => status == OutboxStatus.pending && attempts == 0;

  String get contributionKey =>
      contributionKeyOf(projectionType, campaignRef, productRef, baseUnit);

  static OutboxEntry fromRow(Map<String, Object?> row) => OutboxEntry(
    id: row['id']! as int,
    operationId: row['operation_id']! as String,
    ownerBindingId: row['owner_binding_id']! as int,
    projectionType: ProjectionType.fromCode(row['projection_type']),
    action: SyncAction.fromCode(row['action']),
    campaignRef: row['campaign_ref']! as String,
    productRef: row['product_ref']! as String,
    baseUnit: BaseUnit.fromCode(row['base_unit'])!,
    quantityBase: row['quantity_base'] as String?,
    predecessorOperationId: row['predecessor_operation_id'] as String?,
    predecessorKind: PredecessorKind.fromCode(row['predecessor_kind']),
    reconciliationReference: row['reconciliation_reference'] as String?,
    status: OutboxStatus.fromCode(row['status']),
    attempts: row['attempts']! as int,
    nextAttemptAt: row['next_attempt_at'] as String?,
    lastCode: row['last_code'] as String?,
    ackReconciliationReference: row['ack_reconciliation_reference'] as String?,
    serverAcceptedAt: row['server_accepted_at'] as String?,
    resolutionHeadOperationId: row['resolution_head_operation_id'] as String?,
    resolutionHeadKind: PredecessorKind.fromCode(row['resolution_head_kind']),
    resolvedAt: row['resolved_at'] as String?,
    createdAt: row['created_at']! as String,
    ackedAt: row['acked_at'] as String?,
  );
}

/// Clave de la contribución (sin el propietario, que es el vínculo).
String contributionKeyOf(
  ProjectionType type,
  String campaignRef,
  String productRef,
  BaseUnit unit,
) => '${type.code}|$campaignRef|$productRef|${unit.code}';

/// RF-03 §2.4: qué decir ante un rechazo terminal de Central por el estado de
/// la campaña. El registro privado no cambia; nada se reasigna ni se reintenta.
String? rejectionExplanation(String? code) => switch (code) {
  'CAMPAIGN_SEALED' =>
    'Esta campaña está sellada en el sindicato: el histórico colectivo '
        'sellado no se actualiza con correcciones posteriores. Su registro '
        'privado se conserva.',
  'CAMPAIGN_NOT_OPEN' =>
    'La campaña ya no admite publicaciones en el sindicato. Su registro '
        'privado se conserva.',
  _ => null,
};
