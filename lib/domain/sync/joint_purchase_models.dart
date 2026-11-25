import 'dart:convert';

import '../installation_access.dart' show OwnerScope;
import '../repository_exceptions.dart' show BusinessRuleException;
import 'joint_purchase_call_view.dart';

abstract final class JointPurchaseOpStatus {
  static const pendingSend = 'PENDING_SEND';
  static const received = 'RECEIVED';
  static const rejected = 'REJECTED';
  static const outOfTime = 'OUT_OF_TIME';
  static const superseded = 'SUPERSEDED';
  static const authPaused = 'AUTH_PAUSED';

  /// Ya no se envían nunca.
  static const terminal = {received, rejected, outOfTime, superseded};

  /// Siguen por enviar.
  static const awaiting = {pendingSend, authPaused};
}

abstract final class JointPurchaseOpKind {
  static const confirm = 'CONFIRM';
  static const withdraw = 'WITHDRAW';
}

/// `last_code` locales para `409 CALL_NOT_OPEN` según su `reason` (E2-D11).
abstract final class JointPurchaseCodes {
  static const deadlinePassed = 'DEADLINE_PASSED';
  static const callClosed = 'CALL_CLOSED';
  static const callCancelled = 'CALL_CANCELLED';
  static const callDraft = 'CALL_DRAFT';
  static const staleSequence = 'STALE_SEQUENCE';

  /// E4 §7.2: el sindicato contestó `ACCEPTED` (2xx), pero con una forma que
  /// este teléfono no puede leer de manera determinista (otra versión del
  /// contrato, por ejemplo). La operación llegó: queda `RECEIVED` con este
  /// código, sin adoptar nada de esa respuesta; lo vigente se lee después
  /// en la lista (o la lista dice «Actualice la aplicación»).
  static const responseUnreadable = 'RESPONSE_UNREADABLE';
}

class JointPurchaseException extends BusinessRuleException {
  JointPurchaseException(super.message);
}

/// Una confirmación o un retiro preparado en el teléfono.
class JointPurchaseOp {
  const JointPurchaseOp({
    required this.operationId,
    required this.callId,
    required this.tenantId,
    required this.memberId,
    required this.sequence,
    required this.kind,
    required this.lines,
    required this.consentVersion,
    required this.consentAcceptedAt,
    required this.sendStatus,
    required this.attempts,
    required this.nextAttemptAt,
    required this.lastCode,
    required this.createdAt,
    required this.updatedAt,
    this.responsibleVersion,
  });

  final String operationId;
  final String callId;
  final String tenantId;
  final String memberId;
  final int sequence;
  final String kind;

  /// P-A C1: la versión de la responsabilidad que mostraba el teléfono al
  /// aceptar el consentimiento (sólo una primera confirmación la lleva).
  final int? responsibleVersion;

  /// product_ref → cantidad en unidad base, en el orden en que se envía.
  final Map<String, int> lines;
  final String? consentVersion;
  final String? consentAcceptedAt;
  final String sendStatus;
  final int attempts;
  final String? nextAttemptAt;
  final String? lastCode;
  final String createdAt;
  final String updatedAt;

  OwnerScope get scope => OwnerScope(memberId: memberId, tenantId: tenantId);
  bool get isTerminal => JointPurchaseOpStatus.terminal.contains(sendStatus);
  bool get isAwaitingSend =>
      JointPurchaseOpStatus.awaiting.contains(sendStatus);

  /// Pendiente tras un fallo transitorio: se reintentará sola.
  bool get isRetryScheduled =>
      sendStatus == JointPurchaseOpStatus.pendingSend && lastCode != null;

  bool get isWithdraw => kind == JointPurchaseOpKind.withdraw;

  /// Las líneas tal como viajan (`quantity_base` como cadena decimal).
  List<Map<String, Object?>> get wireLines => [
    for (final entry in lines.entries)
      {'product_ref': entry.key, 'quantity_base': '${entry.value}'},
  ];

  static JointPurchaseOp fromRow(Map<String, Object?> row) => JointPurchaseOp(
    operationId: row['operation_id']! as String,
    callId: row['call_id']! as String,
    tenantId: row['tenant_id']! as String,
    memberId: row['member_id']! as String,
    sequence: row['sequence']! as int,
    kind: row['kind']! as String,
    lines: _decodeLines(row['lines_json'] as String?),
    consentVersion: row['consent_version'] as String?,
    consentAcceptedAt: row['consent_accepted_at'] as String?,
    sendStatus: row['send_status']! as String,
    attempts: row['attempts']! as int,
    nextAttemptAt: row['next_attempt_at'] as String?,
    lastCode: row['last_code'] as String?,
    createdAt: row['created_at']! as String,
    updatedAt: row['updated_at']! as String,
    responsibleVersion: row['responsible_version'] as int?,
  );

  static Map<String, int> _decodeLines(String? stored) {
    if (stored == null) return const {};
    return {
      for (final line in jsonDecode(stored) as List<dynamic>)
        (line as Map<String, dynamic>)['product_ref'] as String: int.parse(
          line['quantity_base'] as String,
        ),
    };
  }
}

/// Una decisión sobre quién ve el nombre y las cantidades, preparada en el
/// teléfono, en una cola propia separada de las cantidades.
///
/// - Desde E4 (§4.2, esquema v20, `joint_purchase_access_ops`):
///   `ADMINISTRATION` («Revisar quién puede ver mi participación», con
///   `CONV-4`) o `TOTALS_ONLY` («Retirar la autorización»).
/// - Antes de E4 (E2 §10.6 y P-A, esquema v18/v19,
///   `joint_purchase_consent_ops`, [legacy]): `COLLABORATORS` (ampliar) o
///   `RESPONSIBLE_ONLY` (reducir), con o sin autorizar a la responsable. Ya
///   no se preparan; las guardadas se conservan y se envían tal cual (E4
///   §7.2): el sindicato acepta una reducción y rechaza para siempre una
///   ampliación o una autorización (`409 CONSENT_VERSION_RETIRED`).
///
/// El orden ([sequence]) es uno solo por convocatoria y titular entre las
/// dos colas.
class JointPurchaseConsentOp {
  const JointPurchaseConsentOp({
    required this.operationId,
    required this.callId,
    required this.tenantId,
    required this.memberId,
    required this.sequence,
    required this.scope,
    required this.consentVersion,
    required this.decidedAt,
    required this.sendStatus,
    required this.attempts,
    required this.nextAttemptAt,
    required this.lastCode,
    required this.createdAt,
    required this.updatedAt,
    this.responsibleVersion,
    this.authorizeResponsible = false,
    this.legacy = false,
  });

  final String operationId;
  final String callId;
  final String tenantId;
  final String memberId;

  /// P-A C1 (sólo decisiones anteriores a E4): la versión de la
  /// responsabilidad que mostraba el teléfono al decidir.
  final int? responsibleVersion;

  /// P-A C1 (sólo decisiones anteriores a E4): autorizaba a la responsable.
  final bool authorizeResponsible;

  /// Guardada antes de E4 en la cola v18 (`joint_purchase_consent_ops`).
  final bool legacy;

  /// Orden propio de las decisiones de esta convocatoria y titular, único
  /// entre las dos colas.
  final int sequence;

  /// `ADMINISTRATION` o `TOTALS_ONLY` (E4); `COLLABORATORS` o
  /// `RESPONSIBLE_ONLY` en las anteriores ([legacy]).
  final String scope;
  final String consentVersion;
  final String decidedAt;
  final String sendStatus;
  final int attempts;
  final String? nextAttemptAt;
  final String? lastCode;
  final String createdAt;
  final String updatedAt;

  OwnerScope get owner => OwnerScope(memberId: memberId, tenantId: tenantId);
  bool get isAwaitingSend =>
      JointPurchaseOpStatus.awaiting.contains(sendStatus);
  bool get isWidening => scope == JointPurchaseConsentScope.collaborators;

  /// Anterior a E4 y una ampliación o una autorización de la responsable:
  /// opción retirada (el sindicato la rechaza con `CONSENT_VERSION_RETIRED`).
  bool get isRetiredOption => legacy && (isWidening || authorizeResponsible);

  /// El cuerpo tal como se guardó: las decisiones anteriores a E4 viajan con
  /// sus campos de entonces, sin reinterpretarlas (E4 §7.2).
  Map<String, Object?> get wireBody => {
    'operation_id': operationId,
    'sequence': sequence,
    'scope': scope,
    'consent': {'version': consentVersion, 'decided_at': decidedAt},
    if (responsibleVersion != null) 'responsible_version': responsibleVersion,
    if (authorizeResponsible) 'authorize_responsible': true,
  };

  /// [row] de cualquiera de las dos colas; [legacy] dice de cuál (o la
  /// columna `legacy` de una consulta que las une).
  static JointPurchaseConsentOp fromRow(
    Map<String, Object?> row, {
    bool? legacy,
  }) => JointPurchaseConsentOp(
    operationId: row['operation_id']! as String,
    callId: row['call_id']! as String,
    tenantId: row['tenant_id']! as String,
    memberId: row['member_id']! as String,
    sequence: row['sequence']! as int,
    scope: row['scope']! as String,
    consentVersion: row['consent_version']! as String,
    decidedAt: row['decided_at']! as String,
    sendStatus: row['send_status']! as String,
    attempts: row['attempts']! as int,
    nextAttemptAt: row['next_attempt_at'] as String?,
    lastCode: row['last_code'] as String?,
    createdAt: row['created_at']! as String,
    updatedAt: row['updated_at']! as String,
    responsibleVersion: row['responsible_version'] as int?,
    authorizeResponsible: (row['authorize_responsible'] as int? ?? 0) == 1,
    legacy: legacy ?? (row['legacy'] as int? ?? 1) == 1,
  );
}

/// Copia local de una convocatoria con su última operación propia.
class JointPurchaseCall {
  const JointPurchaseCall({
    required this.callId,
    required this.tenantId,
    required this.memberId,
    required this.name,
    required this.campaignRef,
    required this.campaignName,
    required this.status,
    required this.openedAt,
    required this.deadlineAt,
    required this.responsibleName,
    required this.products,
    required this.serverParticipation,
    required this.fetchedAt,
    required this.serverTimeAtFetch,
    required this.seenAt,
    required this.latestOp,
    this.finishedAt,
    this.latestConsentOp,
  });

  final String callId;
  final String tenantId;
  final String memberId;
  final String name;
  final String? campaignRef;
  final String? campaignName;
  final String status;
  final String? openedAt;
  final String deadlineAt;
  final String? responsibleName;
  final List<JointPurchaseProduct> products;

  /// Lo último que el servidor aceptó (E2 §5): nunca lo que sólo existe en
  /// el teléfono.
  final JointPurchaseParticipation? serverParticipation;
  final String fetchedAt;
  final String serverTimeAtFetch;
  final String? seenAt;

  /// La operación propia de mayor `sequence` (de cualquier estado), si hay.
  final JointPurchaseOp? latestOp;

  /// E2 §10.6: la última decisión sobre el consentimiento preparada en el
  /// teléfono (de cualquier estado y de las dos colas), si hay.
  final JointPurchaseConsentOp? latestConsentOp;

  /// Una decisión sobre el consentimiento que todavía no llegó: lo vigente
  /// sigue siendo lo que dice [serverParticipation].
  JointPurchaseConsentOp? get pendingConsentOp =>
      latestConsentOp?.isAwaitingSend == true ? latestConsentOp : null;

  // --- Quién ve sus datos (E4 §4) -----------------------------------------

  /// Alcance **aplicado** en el sindicato (lo último que aceptó), o null si
  /// no tiene participación de este titular.
  String? get appliedScope => serverParticipation?.consentScope;

  /// La primera confirmación que todavía no llegó (el sindicato aún no
  /// tiene participación): el alcance con que la creará según el texto que
  /// lleva (`CONV-4` → `ADMINISTRATION`; uno anterior guardado antes de
  /// actualizar → su alcance, nunca `CONV-4`, E4 §7.2). Null si no aplica.
  String? get pendingInitialScope {
    final op = pendingOp;
    if (serverParticipation != null ||
        op == null ||
        op.isWithdraw ||
        op.consentVersion == null) {
      return null;
    }
    return initialConsentScope(op.consentVersion!);
  }

  /// Lo que regirá cuando llegue lo pendiente: la decisión pendiente, si la
  /// hay; si no, lo aplicado; si no, lo de la primera confirmación
  /// pendiente. Sólo para elegir qué acción ofrecer: lo que se anuncia como
  /// vigente es siempre [appliedScope].
  String? get expectedScope =>
      pendingConsentOp?.scope ?? appliedScope ?? pendingInitialScope;

  /// Hay una participación sobre la que decidir: la activa del sindicato,
  /// la primera que está pendiente de envío o una retirada a la que vuelve
  /// con una confirmación pendiente.
  bool get hasDecidableParticipation =>
      serverParticipation?.isActive == true ||
      pendingInitialScope != null ||
      (serverParticipation != null && pendingOp?.isWithdraw == false);

  /// Nunca en una cancelada (E4 §4.2: ahí no cambia nada).
  bool get _canDecideAccess =>
      status != JointPurchaseCallStatus.cancelled && hasDecidableParticipation;

  /// «Revisar quién puede ver mi participación» (E4 §4.2): en `OPEN` y
  /// `CLOSED`, sin depender del plazo, cuando lo que regirá no es ya
  /// `ADMINISTRATION` (un alcance anterior, o la autorización retirada).
  bool get canReviewAccess =>
      _canDecideAccess &&
      expectedScope != JointPurchaseConsentScope.administration;

  /// «Retirar la autorización» (D-05): cuando lo que regirá es
  /// `ADMINISTRATION`. La participación y las cantidades no cambian.
  bool get canRetractAccess =>
      _canDecideAccess &&
      expectedScope == JointPurchaseConsentScope.administration;

  /// Transición (E4 §4.4): una participación con un alcance anterior a E4
  /// (también en una cerrada) que el agricultor todavía no revisó. Etiqueta
  /// «Revisar autorización» en la lista.
  bool get needsAccessReview =>
      canReviewAccess &&
      JointPurchaseConsentScope.legacy.contains(expectedScope);

  /// Fecha de término según el sindicato (UTC), o null (abierta, o copia
  /// anterior a v17 todavía sin actualizar).
  final String? finishedAt;

  bool get isOpen => status == JointPurchaseCallStatus.open;

  /// Terminada antes de [cutoff] según el sindicato: va a «Historial» (E2
  /// §10.1 a). Sin fecha de término conocida se trata como reciente.
  bool finishedBefore(DateTime cutoff) {
    if (isOpen || finishedAt == null) return false;
    final at = DateTime.tryParse(finishedAt!);
    return at != null && at.isBefore(cutoff);
  }

  bool get isNew => isOpen && seenAt == null;

  /// La participación que el sindicato tiene vigente (activa), si la hay.
  JointPurchaseParticipation? get acceptedActive =>
      serverParticipation?.isActive == true ? serverParticipation : null;

  /// Un cambio preparado en el teléfono que todavía no llegó.
  JointPurchaseOp? get pendingOp =>
      latestOp?.isAwaitingSend == true ? latestOp : null;

  JointPurchaseProduct? product(String ref) =>
      products.where((p) => p.productRef == ref).firstOrNull;

  static JointPurchaseCall fromRow(
    Map<String, Object?> row,
    JointPurchaseOp? latestOp, {
    JointPurchaseConsentOp? latestConsentOp,
  }) => JointPurchaseCall(
    callId: row['call_id']! as String,
    tenantId: row['tenant_id']! as String,
    memberId: row['member_id']! as String,
    name: row['name']! as String,
    campaignRef: row['campaign_ref'] as String?,
    campaignName: row['campaign_name'] as String?,
    status: row['status']! as String,
    openedAt: row['opened_at'] as String?,
    deadlineAt: row['deadline_at']! as String,
    responsibleName: row['responsible_name'] as String?,
    products: JointPurchaseProduct.listFromJson(
      jsonDecode(row['products_json']! as String),
    ),
    serverParticipation: JointPurchaseParticipation.decode(
      row['server_participation_json'] as String?,
    ),
    fetchedAt: row['fetched_at']! as String,
    serverTimeAtFetch: row['server_time_at_fetch']! as String,
    seenAt: row['seen_at'] as String?,
    latestOp: latestOp,
    finishedAt: row['finished_at'] as String?,
    latestConsentOp: latestConsentOp,
  );
}

/// Lo que muestra «Compras conjuntas» (E2 §10.1): la vista por defecto
/// (abiertas y terminadas recientes) y las anteriores guardadas en el
/// teléfono, con lo que el sindicato dijo que hay.
class JointPurchaseOverview {
  const JointPurchaseOverview({
    required this.recent,
    required this.older,
    required this.olderCount,
    required this.missingOlder,
  });

  /// Abiertas (por fecha límite) y terminadas en los últimos
  /// [jointPurchaseRecentFinishedDays] días.
  final List<JointPurchaseCall> recent;

  /// Terminadas antes, guardadas en el teléfono: de la más reciente a la
  /// más antigua.
  final List<JointPurchaseCall> older;

  /// `history.older_count` de la última actualización, o null si nunca se
  /// actualizó con esta versión.
  final int? olderCount;

  /// Cuántas anteriores dice el sindicato que hay y no están en el teléfono
  /// (nunca negativo).
  final int missingOlder;

  bool get isEmpty => recent.isEmpty && older.isEmpty;
}

/// Aviso de Inicio: la convocatoria abierta no vista que cierra antes y
/// cuántas hay en total.
class JointPurchaseNotice {
  const JointPurchaseNotice({
    required this.callId,
    required this.name,
    required this.deadlineAt,
    required this.total,
  });

  final String callId;
  final String name;
  final String deadlineAt;
  final int total;
}

/// Contrato de compras conjuntas para la presentación.
abstract interface class JointPurchaseGateway {
  Future<JointPurchaseOverview> overviewForActiveOwner();
  Future<JointPurchaseCall?> call(String callId);
  Future<int> awaitingSendForActiveOwner();
  Future<Map<String, int>> declaredNeedsFor(String? campaignRef);
  Future<bool> markSeen(String callId);
  Future<JointPurchaseOp> confirm({
    required String callId,
    required Map<String, int> lines,
    String? consentVersion,
    DateTime? consentAcceptedAt,
  });
  Future<JointPurchaseOp?> withdraw(String callId);
  Future<JointPurchaseConsentOp?> decideAccess({
    required String callId,
    required String scope,
    required DateTime decidedAt,
  });
}
