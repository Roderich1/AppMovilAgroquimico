import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart'
    show ConflictAlgorithm, DatabaseExecutor, Transaction;

import '../../domain/installation_access.dart' show OwnerScope;
import '../../domain/numeric_input.dart' show maxBaseQuantity;
import '../../domain/sync/joint_purchase_call_view.dart';
import '../../domain/sync/operation_id.dart' show newOperationId;
import '../agro_repository.dart' show BusinessRuleException;
import '../app_database.dart';
import '../farmer_operation_gate.dart';

/// Estados de envío de una operación de participación (E2 §5).
///
/// Lo **terminal** y lo **reintentable** se distinguen sólo por el estado,
/// nunca por una fecha nula (lección de E1, 8a45484): `PENDING_SEND` siempre
/// se reintenta (`next_attempt_at` nula o pasada = vence ya); `AUTH_PAUSED`
/// espera un envío pedido por el agricultor; el resto es terminal.
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

/// Convocatorias de compra conjunta y cola propia de participación
/// (contrato E2 §5).
///
/// Canal propio, aparte de Sync v1 y de `sync_outbox` (E2 §1): no escribe
/// en compras, aplicaciones, inventario, cuentas ni necesidad declarada
/// (E2-D14). Cada operación queda atada al titular (`tenant_id`,
/// `member_id`) que la preparó (E2-D16).
class JointPurchaseStore {
  JointPurchaseStore(
    this._database, {
    FarmerOperationGate gate = const FarmerOperationGate.unrestricted(),
    DateTime Function()? clock,
    Random? random,
  }) : _gate = gate,
       _clock = clock ?? DateTime.now,
       _random = random;

  final AppDatabase _database;
  final FarmerOperationGate _gate;
  final DateTime Function() _clock;
  final Random? _random;

  static const callsTable = 'joint_purchase_calls';
  static const opsTable = 'joint_purchase_participation_ops';
  static const historyStateTable = 'joint_purchase_history_state';

  /// Decisiones anteriores a E4 (v18/v19): sólo se envían y se conservan.
  static const consentOpsTable = 'joint_purchase_consent_ops';

  /// Decisiones de E4 (v20): `ADMINISTRATION` y `TOTALS_ONLY`.
  static const accessOpsTable = 'joint_purchase_access_ops';

  /// Las dos colas de decisiones en una sola consulta, con las mismas
  /// columnas y `legacy` = 1 para la anterior a E4.
  static const _decisionsUnion =
      'SELECT operation_id, call_id, tenant_id, member_id, sequence, scope, '
      'consent_version, decided_at, send_status, attempts, next_attempt_at, '
      'last_code, created_at, updated_at, responsible_version, '
      'authorize_responsible, 1 AS legacy FROM $consentOpsTable '
      'UNION ALL SELECT operation_id, call_id, tenant_id, member_id, sequence, '
      'scope, consent_version, decided_at, send_status, attempts, '
      'next_attempt_at, last_code, created_at, updated_at, NULL, 0, 0 '
      'FROM $accessOpsTable';

  String _now() => _clock().toUtc().toIso8601String();

  Future<T> _write<T>(Future<T> Function(Transaction txn) body) =>
      _database.replacement.write(() async {
        _gate.ensureAllowed();
        return (await _database.database).transaction(body);
      });

  static Future<OwnerScope?> _activeOwner(DatabaseExecutor db) async {
    final rows = await db.query(
      'owner_bindings',
      columns: ['tenant_id', 'member_id'],
      where: 'ended_at IS NULL',
    );
    if (rows.isEmpty) return null;
    return OwnerScope(
      memberId: rows.single['member_id']! as String,
      tenantId: rows.single['tenant_id']! as String,
    );
  }

  // --- Lo que sirvió el sindicato ---------------------------------------

  /// Guarda la vista por defecto que el sindicato sirvió a [scope] (E2
  /// §10.1 b): reemplaza cada convocatoria (conservando `seen_at` del mismo
  /// titular), guarda `history.older_count` y quita **sólo** las ausentes
  /// que siguen abiertas en la copia local, sin participación propia
  /// guardada y sin ninguna operación local (por ejemplo, una abierta que se
  /// canceló sin que el agricultor participara). Una terminada nunca se
  /// quita: el sindicato sólo sirve terminadas a quien tiene participación
  /// (E2-R14), aunque no entrara al consolidado y no haya aquí copia de lo
  /// aceptado; deja de llegar al salir de la ventana de recientes, no porque
  /// deje de existir. La participación aceptada sólo avanza: una copia con
  /// `last_sequence` menor que la guardada no la sustituye (E2-D10).
  Future<void> saveFetched(
    OwnerScope scope,
    JointPurchaseCallList list,
  ) => _write((txn) async {
    final now = _now();
    for (final view in list.calls) {
      await _upsert(txn, scope, view, now);
    }
    await txn.insert(historyStateTable, {
      'tenant_id': scope.tenantId,
      'member_id': scope.memberId,
      'older_count': list.olderCount,
      'server_time': list.serverTime,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final ids = [for (final view in list.calls) view.callId];
    await txn.rawDelete(
      'DELETE FROM $callsTable WHERE tenant_id=? AND member_id=? '
      "AND status = 'OPEN' AND server_participation_json IS NULL "
      '${ids.isEmpty ? '' : 'AND call_id NOT IN (${List.filled(ids.length, '?').join(',')}) '}'
      'AND NOT EXISTS (SELECT 1 FROM $opsTable o WHERE o.call_id = '
      '$callsTable.call_id AND o.member_id = $callsTable.member_id)',
      [scope.tenantId, scope.memberId, ...ids],
    );
  });

  /// Guarda una página de «Historial» (`GET …/history`) para [scope]: inserta
  /// o actualiza cada convocatoria como [saveFetched], **sin borrar nada**
  /// (E2 §10.1 b).
  Future<void> saveHistory(
    OwnerScope scope,
    List<JointPurchaseCallView> calls,
  ) => _write((txn) async {
    final now = _now();
    for (final view in calls) {
      await _upsert(txn, scope, view, now);
    }
  });

  Future<void> _upsert(
    Transaction txn,
    OwnerScope scope,
    JointPurchaseCallView view,
    String now,
  ) async {
    final existing = await txn.query(
      callsTable,
      columns: [
        'tenant_id',
        'member_id',
        'seen_at',
        'server_participation_json',
        'responsible_version',
      ],
      where: 'call_id=?',
      whereArgs: [view.callId],
    );
    final sameOwner =
        existing.isNotEmpty &&
        existing.single['tenant_id'] == scope.tenantId &&
        existing.single['member_id'] == scope.memberId;
    var participation = view.acceptedForDisplay;
    if (sameOwner && participation != null) {
      final stored = JointPurchaseParticipation.decode(
        existing.single['server_participation_json'] as String?,
      );
      if (stored != null) participation = _merge(stored, participation);
    }
    await txn.insert(callsTable, {
      'call_id': view.callId,
      'tenant_id': scope.tenantId,
      'member_id': scope.memberId,
      'name': view.name,
      'campaign_ref': view.campaignRef,
      'campaign_name': view.campaignName,
      'status': view.status,
      'opened_at': view.openedAt,
      'deadline_at': view.deadlineAt,
      'responsible_name': view.responsibleName,
      'products_json': JointPurchaseProduct.encodeList(view.products),
      'server_participation_json': participation?.encode(),
      'fetched_at': now,
      'server_time_at_fetch': view.serverTime,
      'seen_at': sameOwner ? existing.single['seen_at'] : null,
      'finished_at': view.finishedAt,
      // P-A (v19), sólo historia: el contrato 4 ya no envía la versión de la
      // responsabilidad; se conserva la guardada del mismo titular.
      'responsible_version': sameOwner
          ? existing.single['responsible_version']
          : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- Lecturas ---------------------------------------------------------

  /// Convocatorias del titular activo: abiertas primero (por fecha límite),
  /// luego las demás. Tres consultas.
  Future<List<JointPurchaseCall>> callsForActiveOwner() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT c.* FROM $callsTable c JOIN owner_bindings o '
      'ON o.ended_at IS NULL AND o.tenant_id = c.tenant_id '
      'AND o.member_id = c.member_id '
      "ORDER BY CASE c.status WHEN 'OPEN' THEN 0 ELSE 1 END, "
      'c.deadline_at, c.call_id',
    );
    if (rows.isEmpty) return const [];
    final ids = [for (final row in rows) row['call_id']! as String];
    final memberId = rows.first['member_id']! as String;
    final latest = await _latestOps(db, ids, memberId);
    // E4: la última decisión de las dos colas, para no anunciar en la lista
    // «Revisar autorización» cuando ya hay una pendiente (una consulta).
    final decisions = await db.rawQuery(
      'SELECT d.* FROM ($_decisionsUnion) d WHERE d.member_id = ? AND '
      'd.call_id IN (${List.filled(ids.length, '?').join(',')}) AND '
      'd.sequence = (SELECT MAX(x.sequence) FROM ($_decisionsUnion) x '
      'WHERE x.call_id = d.call_id AND x.member_id = d.member_id)',
      [memberId, ...ids],
    );
    final latestDecision = {
      for (final row in decisions)
        row['call_id']! as String: JointPurchaseConsentOp.fromRow(row),
    };
    return [
      for (final row in rows)
        JointPurchaseCall.fromRow(
          row,
          latest[row['call_id']],
          latestConsentOp: latestDecision[row['call_id']],
        ),
    ];
  }

  /// Una convocatoria del titular activo, o null.
  Future<JointPurchaseCall?> call(String callId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT c.* FROM $callsTable c JOIN owner_bindings o '
      'ON o.ended_at IS NULL AND o.tenant_id = c.tenant_id '
      'AND o.member_id = c.member_id WHERE c.call_id = ?',
      [callId],
    );
    if (rows.isEmpty) return null;
    final memberId = rows.single['member_id']! as String;
    final latest = await _latestOps(db, [callId], memberId);
    // La última decisión de las dos colas, en una sola consulta.
    final consent = await db.rawQuery(
      'SELECT * FROM ($_decisionsUnion) WHERE call_id=? AND member_id=? '
      'ORDER BY sequence DESC LIMIT 1',
      [callId, memberId],
    );
    return JointPurchaseCall.fromRow(
      rows.single,
      latest[callId],
      latestConsentOp: consent.isEmpty
          ? null
          : JointPurchaseConsentOp.fromRow(consent.single),
    );
  }

  /// «Compras conjuntas» del titular activo (E2 §10.1): las mismas tres
  /// consultas de [callsForActiveOwner] y una más para el recuento del
  /// sindicato. El corte de recientes es el reloj del teléfono (también sin
  /// conexión); las que faltan se cuentan con el corte de la hora del
  /// servidor de esa respuesta, como las contó él.
  Future<JointPurchaseOverview> overviewForActiveOwner() async {
    final calls = await callsForActiveOwner();
    final db = await _database.database;
    final state = await db.rawQuery(
      'SELECT h.older_count, h.server_time FROM $historyStateTable h '
      'JOIN owner_bindings o ON o.ended_at IS NULL '
      'AND o.tenant_id = h.tenant_id AND o.member_id = h.member_id',
    );
    const window = Duration(days: jointPurchaseRecentFinishedDays);
    final cutoff = _clock().toUtc().subtract(window);
    final recent = <JointPurchaseCall>[];
    final older = <JointPurchaseCall>[];
    for (final call in calls) {
      (call.finishedBefore(cutoff) ? older : recent).add(call);
    }
    older.sort((a, b) {
      final byDate = b.finishedAt!.compareTo(a.finishedAt!);
      return byDate != 0 ? byDate : a.callId.compareTo(b.callId);
    });
    int? olderCount;
    var missing = 0;
    if (state.isNotEmpty) {
      olderCount = state.single['older_count']! as int;
      final serverTime = DateTime.tryParse(
        state.single['server_time']! as String,
      );
      final serverCutoff = (serverTime ?? _clock().toUtc()).subtract(window);
      final stored = calls.where((c) => c.finishedBefore(serverCutoff)).length;
      missing = max(0, olderCount - stored);
    }
    return JointPurchaseOverview(
      recent: recent,
      older: older,
      olderCount: olderCount,
      missingOlder: missing,
    );
  }

  Future<Map<String, JointPurchaseOp>> _latestOps(
    DatabaseExecutor db,
    List<String> callIds,
    String memberId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT o.* FROM $opsTable o WHERE o.member_id = ? AND o.call_id IN '
      '(${List.filled(callIds.length, '?').join(',')}) AND o.sequence = '
      '(SELECT MAX(x.sequence) FROM $opsTable x WHERE x.call_id = o.call_id '
      'AND x.member_id = o.member_id)',
      [memberId, ...callIds],
    );
    return {
      for (final row in rows)
        row['call_id']! as String: JointPurchaseOp.fromRow(row),
    };
  }

  /// Todas las operaciones de una convocatoria (pruebas y diagnóstico).
  Future<List<JointPurchaseOp>> ops(String callId) async =>
      (await (await _database.database).query(
        opsTable,
        where: 'call_id=?',
        whereArgs: [callId],
        orderBy: 'sequence',
      )).map(JointPurchaseOp.fromRow).toList();

  Future<JointPurchaseOp?> op(String operationId) async {
    final rows = await (await _database.database).query(
      opsTable,
      where: 'operation_id=?',
      whereArgs: [operationId],
    );
    return rows.isEmpty ? null : JointPurchaseOp.fromRow(rows.single);
  }

  /// Cuántas operaciones de convocatoria del titular vigente siguen por
  /// enviar (`PENDING_SEND` o `AUTH_PAUSED`): participación y cantidades,
  /// y las decisiones de quién ve los datos de las dos colas (v18 y E4).
  /// **Una sola consulta** y sólo lectura: el aviso informativo del cambio
  /// de modo (H1) la hace al confirmar, no al pintar. Sin titular, 0.
  Future<int> awaitingSendForActiveOwner() async {
    final rows = await (await _database.database).rawQuery(
      'SELECT COUNT(*) AS n FROM ('
      'SELECT tenant_id, member_id, send_status FROM $opsTable '
      'UNION ALL SELECT tenant_id, member_id, send_status '
      'FROM $consentOpsTable '
      'UNION ALL SELECT tenant_id, member_id, send_status '
      'FROM $accessOpsTable) o '
      'JOIN owner_bindings b ON b.ended_at IS NULL '
      'AND b.tenant_id = o.tenant_id AND b.member_id = o.member_id '
      'WHERE o.send_status IN (?,?)',
      [JointPurchaseOpStatus.pendingSend, JointPurchaseOpStatus.authPaused],
    );
    return rows.single['n']! as int;
  }

  /// Aviso «Nueva convocatoria» de Inicio en **una sola consulta** indexada:
  /// la abierta, no vista y con plazo por delante (según este teléfono) que
  /// cierra antes, y cuántas hay. Null si no hay ninguna.
  Future<JointPurchaseNotice?> unseenNotice() async {
    final now = _now();
    final rows = await (await _database.database).rawQuery(
      'SELECT c.call_id, c.name, c.deadline_at, '
      '(SELECT COUNT(*) FROM $callsTable x WHERE x.tenant_id = c.tenant_id '
      "AND x.member_id = c.member_id AND x.status = 'OPEN' "
      'AND x.seen_at IS NULL AND x.deadline_at > ?) AS total '
      'FROM $callsTable c JOIN owner_bindings o ON o.ended_at IS NULL '
      'AND o.tenant_id = c.tenant_id AND o.member_id = c.member_id '
      "WHERE c.status = 'OPEN' AND c.seen_at IS NULL AND c.deadline_at > ? "
      'ORDER BY c.deadline_at, c.call_id LIMIT 1',
      [now, now],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return JointPurchaseNotice(
      callId: row['call_id']! as String,
      name: row['name']! as String,
      deadlineAt: row['deadline_at']! as String,
      total: row['total']! as int,
    );
  }

  /// Necesidad declarada **activa** del titular para la campaña central
  /// [campaignRef], por `product_ref` (unidad base). Sólo lectura y sólo
  /// como referencia: nunca se suma a la participación (E2-D14).
  Future<Map<String, int>> declaredNeedsFor(String? campaignRef) async {
    if (campaignRef == null) return const {};
    final rows = await (await _database.database).rawQuery(
      'SELECT pb.product_ref, n.quantity_base FROM declared_needs n '
      'JOIN owner_bindings o ON o.id = n.owner_binding_id AND o.ended_at IS NULL '
      'JOIN campaign_bindings cb ON cb.campaign_id = n.campaign_id '
      'AND cb.tenant_id = o.tenant_id '
      'JOIN product_bindings pb ON pb.product_id = n.product_id '
      'AND pb.tenant_id = o.tenant_id '
      "WHERE cb.campaign_ref = ? AND n.status = 'ACTIVE'",
      [campaignRef],
    );
    return {
      for (final row in rows)
        row['product_ref']! as String: row['quantity_base']! as int,
    };
  }

  /// Marca la convocatoria como vista: el aviso de Inicio desaparece. Sólo
  /// en el teléfono; el servidor no registra lecturas (E2-D15).
  Future<bool> markSeen(String callId) => _write(
    (txn) async =>
        await txn.update(
          callsTable,
          {'seen_at': _now()},
          where: 'call_id=? AND seen_at IS NULL',
          whereArgs: [callId],
        ) >
        0,
  );

  // --- Preparar en el teléfono ------------------------------------------

  /// «Participar» o «Modificar»: guarda la confirmación con [lines]
  /// (product_ref → cantidad base > 0). Queda `PENDING_SEND`; la anterior
  /// pendiente de esta convocatoria pasa a `SUPERSEDED` en la misma
  /// transacción. Un segundo toque con el mismo contenido no crea otra
  /// operación.
  ///
  /// E2 §10.6: el consentimiento ([consentVersion] aceptado en
  /// [consentAcceptedAt]) sólo se pide y se envía cuando el sindicato todavía
  /// no tiene participación de este titular. Modificar cantidades conserva lo
  /// aceptado: no lleva consentimiento y nunca lo amplía ni lo reduce.
  Future<JointPurchaseOp> confirm({
    required String callId,
    required Map<String, int> lines,
    String? consentVersion,
    DateTime? consentAcceptedAt,
  }) async {
    if (consentVersion != null &&
        consentVersion != jointPurchaseConsentVersion) {
      throw JointPurchaseException(
        'Debe aceptar el texto de consentimiento vigente para participar.',
      );
    }
    final id = await _write(
      (txn) => _enqueue(
        txn,
        callId,
        JointPurchaseOpKind.confirm,
        lines: lines,
        consentAcceptedAt: consentVersion == null
            ? null
            : consentAcceptedAt?.toUtc().toIso8601String(),
      ),
    );
    return (await op(id!))!;
  }

  /// Si [callId] necesita el consentimiento al confirmar: el sindicato no
  /// tiene todavía una participación de este titular.
  Future<bool> needsConsent(String callId) async =>
      (await call(callId))?.serverParticipation == null;

  /// «Retirar participación». Si el sindicato nunca pudo recibir nada de
  /// esta convocatoria, sólo deja sin efecto lo pendiente y devuelve null;
  /// si no, guarda un retiro `PENDING_SEND`.
  Future<JointPurchaseOp?> withdraw(String callId) async {
    final id = await _write(
      (txn) => _enqueue(txn, callId, JointPurchaseOpKind.withdraw),
    );
    return id == null ? null : op(id);
  }

  Future<String?> _enqueue(
    Transaction txn,
    String callId,
    String kind, {
    Map<String, int> lines = const {},
    String? consentAcceptedAt,
  }) async {
    final owner = await _activeOwner(txn);
    if (owner == null) {
      throw JointPurchaseException(
        'Elija primero el titular de estos datos para participar.',
      );
    }
    final rows = await txn.query(
      callsTable,
      where: 'call_id=? AND tenant_id=? AND member_id=?',
      whereArgs: [callId, owner.tenantId, owner.memberId],
    );
    if (rows.isEmpty) {
      throw JointPurchaseException(
        'La convocatoria no está en este teléfono para el titular actual.',
      );
    }
    final call = JointPurchaseCall.fromRow(rows.single, null);
    if (!call.isOpen) {
      throw JointPurchaseException(
        'La convocatoria ya no está abierta según la última consulta al '
        'sindicato.',
      );
    }
    // E2 §10.6: sin participación en el sindicato, la confirmación lleva el
    // consentimiento aceptado; con ella, nunca.
    final carriesConsent =
        kind == JointPurchaseOpKind.confirm && call.serverParticipation == null;
    if (carriesConsent && consentAcceptedAt == null) {
      throw JointPurchaseException(
        'Debe aceptar el texto de consentimiento vigente para participar.',
      );
    }
    if (kind == JointPurchaseOpKind.confirm) {
      if (lines.isEmpty) {
        throw JointPurchaseException(
          'Indique la cantidad de al menos un producto. Para no participar, '
          'use «Retirar participación».',
        );
      }
      for (final entry in lines.entries) {
        if (call.product(entry.key) == null) {
          throw JointPurchaseException(
            'Un producto no pertenece a esta convocatoria.',
          );
        }
        if (entry.value <= 0 || entry.value > maxBaseQuantity) {
          throw JointPurchaseException(
            'Cada cantidad debe ser mayor que cero.',
          );
        }
      }
    }
    // Orden de envío: el de los productos de la convocatoria.
    final ordered = <String, int>{
      for (final product in call.products)
        if (lines.containsKey(product.productRef))
          product.productRef: lines[product.productRef]!,
    };
    final opRows = await txn.query(
      opsTable,
      where: 'call_id=? AND member_id=?',
      whereArgs: [callId, owner.memberId],
      orderBy: 'sequence DESC',
    );
    final existing = opRows.map(JointPurchaseOp.fromRow).toList();
    final pending = existing.where((op) => op.isAwaitingSend).toList();
    // Doble toque: lo mismo que ya está pendiente no crea otra operación.
    // Una confirmación pendiente con otro consentimiento (guardada antes de
    // actualizar) no es «lo mismo»: la nueva la sustituye.
    if (pending.isNotEmpty &&
        pending.first.kind == kind &&
        _sameLines(pending.first.lines, ordered) &&
        (!carriesConsent ||
            pending.first.consentVersion == jointPurchaseConsentVersion)) {
      return pending.first.operationId;
    }
    final now = _now();
    Future<void> supersedePending() => txn.rawUpdate(
      'UPDATE $opsTable SET send_status=?, next_attempt_at=NULL, updated_at=? '
      'WHERE call_id=? AND member_id=? AND send_status IN (?,?)',
      [
        JointPurchaseOpStatus.superseded,
        now,
        callId,
        owner.memberId,
        JointPurchaseOpStatus.pendingSend,
        JointPurchaseOpStatus.authPaused,
      ],
    );
    if (kind == JointPurchaseOpKind.withdraw) {
      // ¿Pudo llegar algo al sindicato? Lo aceptado, o una confirmación que
      // salió del teléfono sin respuesta clara (sigue pendiente con
      // intentos).
      final mayBeOnServer =
          call.acceptedActive != null ||
          existing.any(
            (op) =>
                op.kind == JointPurchaseOpKind.confirm &&
                op.sendStatus == JointPurchaseOpStatus.pendingSend &&
                op.attempts > 0,
          );
      if (!mayBeOnServer) {
        if (pending.isEmpty) {
          throw JointPurchaseException(
            'No hay ninguna participación que retirar.',
          );
        }
        await supersedePending();
        return null;
      }
    }
    final sequence =
        max(
          existing.isEmpty ? 0 : existing.first.sequence,
          call.serverParticipation?.lastSequence ?? 0,
        ) +
        1;
    await supersedePending();
    final operationId = newOperationId(_random);
    await txn.insert(opsTable, {
      'operation_id': operationId,
      'call_id': callId,
      'tenant_id': owner.tenantId,
      'member_id': owner.memberId,
      'sequence': sequence,
      'kind': kind,
      'lines_json': kind == JointPurchaseOpKind.confirm
          ? jsonEncode([
              for (final entry in ordered.entries)
                {'product_ref': entry.key, 'quantity_base': '${entry.value}'},
            ])
          : null,
      'consent_version': carriesConsent ? jointPurchaseConsentVersion : null,
      'consent_accepted_at': carriesConsent ? consentAcceptedAt : null,
      // E4 §6.3: `CONV-4` no autoriza a una responsable; la columna de P-A
      // queda sin dato en las confirmaciones nuevas.
      'responsible_version': null,
      'send_status': JointPurchaseOpStatus.pendingSend,
      'attempts': 0,
      'created_at': now,
      'updated_at': now,
    });
    return operationId;
  }

  static bool _sameLines(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length &&
      a.entries.every((entry) => b[entry.key] == entry.value);

  // --- Decisiones sobre quién ve sus datos (E4 §4.2) ----------------------

  /// «Revisar quién puede ver mi participación» ([scope] = `ADMINISTRATION`,
  /// con el texto `CONV-4` mostrado y aceptado en [decidedAt]) o «Retirar la
  /// autorización» (`TOTALS_ONLY`, D-05). Queda `PENDING_SEND` en su propia
  /// cola (v20), con un orden único entre las dos colas de decisiones; hasta
  /// que el sindicato la acepte, lo vigente sigue siendo lo que él dijo.
  ///
  /// - Nunca toca cantidades ni la participación: sólo quién ve el detalle.
  /// - Vale en `OPEN` y `CLOSED`, sin depender del plazo, y nunca en
  ///   `CANCELLED` (E4 §4.2).
  /// - Una decisión pendiente anterior (de cualquiera de las dos colas) queda
  ///   `SUPERSEDED`; repetir la misma pendiente no crea otra.
  /// - Devuelve null si no hay nada que enviar: [scope] ya es lo que rige
  ///   en el sindicato (o lo que creará la primera confirmación pendiente),
  ///   o se retira una autorización que todavía no había salido del
  ///   teléfono (sólo queda sin efecto; rige lo anterior).
  Future<JointPurchaseConsentOp?> decideAccess({
    required String callId,
    required String scope,
    required DateTime decidedAt,
  }) async {
    if (!JointPurchaseConsentScope.decisions.contains(scope)) {
      throw JointPurchaseException('Decisión no reconocida.');
    }
    final id = await _write((txn) async {
      final owner = await _activeOwner(txn);
      if (owner == null) {
        throw JointPurchaseException(
          'Elija primero el titular de estos datos.',
        );
      }
      final rows = await txn.query(
        callsTable,
        where: 'call_id=? AND tenant_id=? AND member_id=?',
        whereArgs: [callId, owner.tenantId, owner.memberId],
      );
      if (rows.isEmpty) {
        throw JointPurchaseException(
          'La convocatoria no está en este teléfono para el titular actual.',
        );
      }
      final quantityOps = (await txn.query(
        opsTable,
        where: 'call_id=? AND member_id=?',
        whereArgs: [callId, owner.memberId],
        orderBy: 'sequence DESC',
        limit: 1,
      )).map(JointPurchaseOp.fromRow);
      final call = JointPurchaseCall.fromRow(
        rows.single,
        quantityOps.firstOrNull,
      );
      if (call.status == JointPurchaseCallStatus.cancelled) {
        throw JointPurchaseException(
          'La convocatoria está cancelada: no cambia quién ve sus datos.',
        );
      }
      final server = call.serverParticipation;
      final initial = call.pendingInitialScope;
      if (!call.hasDecidableParticipation) {
        throw JointPurchaseException(
          server == null
              ? 'Primero participe en la convocatoria: quién ve sus datos se '
                    'decide sobre una participación.'
              : 'Su participación está retirada: no hay datos que mostrar a '
                    'nadie.',
        );
      }
      final existing = (await txn.rawQuery(
        'SELECT * FROM ($_decisionsUnion) WHERE call_id=? AND member_id=? '
        'ORDER BY sequence DESC',
        [callId, owner.memberId],
      )).map(JointPurchaseConsentOp.fromRow).toList();
      final pending = existing.where((op) => op.isAwaitingSend).toList();
      // Doble toque: la misma decisión pendiente no crea otra.
      if (pending.isNotEmpty &&
          !pending.first.legacy &&
          pending.first.scope == scope) {
        return pending.first.operationId;
      }
      final now = _now();
      for (final table in [consentOpsTable, accessOpsTable]) {
        await txn.rawUpdate(
          'UPDATE $table SET send_status=?, next_attempt_at=NULL, '
          'updated_at=? WHERE call_id=? AND member_id=? '
          'AND send_status IN (?,?)',
          [
            JointPurchaseOpStatus.superseded,
            now,
            callId,
            owner.memberId,
            JointPurchaseOpStatus.pendingSend,
            JointPurchaseOpStatus.authPaused,
          ],
        );
      }
      // Lo que ya rige en el sindicato (o lo que creará la primera
      // confirmación pendiente) no se vuelve a enviar; una decisión
      // contraria pendiente sólo queda sin efecto.
      final base = server?.consentScope ?? initial;
      if (base == scope) return null;
      if (scope == JointPurchaseConsentScope.totalsOnly &&
          base != JointPurchaseConsentScope.administration) {
        // Retirar una autorización que nunca llegó al sindicato: basta con
        // dejarla sin efecto. Sin ninguna pendiente, no hay nada que retirar.
        if (pending.any(
          (op) => op.scope == JointPurchaseConsentScope.administration,
        )) {
          return null;
        }
        throw JointPurchaseException(
          'No hay ninguna autorización que retirar en esta convocatoria.',
        );
      }
      final sequence =
          max(
            existing.isEmpty ? 0 : existing.first.sequence,
            server?.consentScopeSequence ?? 0,
          ) +
          1;
      final operationId = newOperationId(_random);
      await txn.insert(accessOpsTable, {
        'operation_id': operationId,
        'call_id': callId,
        'tenant_id': owner.tenantId,
        'member_id': owner.memberId,
        'sequence': sequence,
        'scope': scope,
        'consent_version': jointPurchaseConsentVersion,
        'decided_at': decidedAt.toUtc().toIso8601String(),
        'send_status': JointPurchaseOpStatus.pendingSend,
        'attempts': 0,
        'created_at': now,
        'updated_at': now,
      });
      return operationId;
    });
    return id == null ? null : consentOp(id);
  }

  /// Una decisión de cualquiera de las dos colas, o null.
  Future<JointPurchaseConsentOp?> consentOp(String operationId) async {
    final rows = await (await _database.database).rawQuery(
      'SELECT * FROM ($_decisionsUnion) WHERE operation_id=?',
      [operationId],
    );
    return rows.isEmpty ? null : JointPurchaseConsentOp.fromRow(rows.first);
  }

  /// Todas las decisiones de una convocatoria, de las dos colas, en orden
  /// (pruebas y diagnóstico).
  Future<List<JointPurchaseConsentOp>> consentOps(String callId) async =>
      (await (await _database.database).rawQuery(
        'SELECT * FROM ($_decisionsUnion) WHERE call_id=? ORDER BY sequence',
        [callId],
      )).map(JointPurchaseConsentOp.fromRow).toList();

  /// Decisiones que hay que enviar por [scope]: por convocatoria, la
  /// pendiente más nueva de las dos colas, en orden de `sequence`.
  Future<List<JointPurchaseConsentOp>> sendableConsent(
    OwnerScope scope, {
    required bool includePaused,
  }) async {
    final rows = await (await _database.database).rawQuery(
      'SELECT * FROM ($_decisionsUnion) WHERE tenant_id=? AND member_id=? '
      'AND (send_status=? OR (send_status=? AND ?=1)) '
      'ORDER BY call_id, sequence DESC',
      [
        scope.tenantId,
        scope.memberId,
        JointPurchaseOpStatus.pendingSend,
        JointPurchaseOpStatus.authPaused,
        includePaused ? 1 : 0,
      ],
    );
    final newest = <String, JointPurchaseConsentOp>{};
    for (final op in rows.map(JointPurchaseConsentOp.fromRow)) {
      newest.putIfAbsent(op.callId, () => op);
    }
    return newest.values.toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
  }

  /// `PARTICIPATION_REQUIRED` sólo se reintenta mientras la primera
  /// confirmación de esa convocatoria siga por enviar (o enviada sin
  /// respuesta clara); si no, el sindicato nunca tendrá la participación y
  /// la decisión no puede aplicarse (sin reintento infinito).
  Future<bool> confirmAwaitingSend(String callId, String memberId) async {
    final rows = await (await _database.database).query(
      opsTable,
      columns: ['operation_id'],
      where: 'call_id=? AND member_id=? AND kind=? AND send_status IN (?,?)',
      whereArgs: [
        callId,
        memberId,
        JointPurchaseOpKind.confirm,
        JointPurchaseOpStatus.pendingSend,
        JointPurchaseOpStatus.authPaused,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// El sindicato aceptó la decisión: se adopta la participación devuelta
  /// (su alcance sólo avanza; sus cantidades, también). Sin participación
  /// legible ([JointPurchaseCodes.responseUnreadable]), sólo se registra que
  /// llegó.
  Future<void> markConsentReceived(
    JointPurchaseConsentOp op,
    JointPurchaseParticipation? participation, {
    String? code,
  }) => _write((txn) async {
    if (!await _transitionConsent(
      txn,
      op,
      JointPurchaseOpStatus.received,
      code: code,
    )) {
      return;
    }
    if (participation != null) {
      await _adoptFor(txn, op.callId, op.memberId, participation);
    }
  });

  /// `STALE_SEQUENCE`: una decisión posterior ya rige; se adopta la vigente.
  Future<void> markConsentStale(
    JointPurchaseConsentOp op,
    JointPurchaseParticipation? participation,
  ) => _write((txn) async {
    if (!await _transitionConsent(
      txn,
      op,
      JointPurchaseOpStatus.superseded,
      code: JointPurchaseCodes.staleSequence,
    )) {
      return;
    }
    if (participation != null) {
      await _adoptFor(txn, op.callId, op.memberId, participation);
    }
  });

  /// Rechazo definitivo con [code] (la decisión no se borra: queda
  /// `REJECTED`). Si el sindicato devolvió la participación vigente, se
  /// adopta como cualquier respuesta: sólo lo más nuevo.
  Future<void> markConsentRejected(
    JointPurchaseConsentOp op,
    String code, {
    JointPurchaseParticipation? participation,
  }) => _write((txn) async {
    if (!await _transitionConsent(
      txn,
      op,
      JointPurchaseOpStatus.rejected,
      code: code,
    )) {
      return;
    }
    if (participation != null) {
      await _adoptFor(txn, op.callId, op.memberId, participation);
    }
  });

  Future<void> markConsentAuthPaused(JointPurchaseConsentOp op, String code) =>
      _write(
        (txn) => _transitionConsent(
          txn,
          op,
          JointPurchaseOpStatus.authPaused,
          code: code,
        ),
      );

  /// Fallo transitorio (o la participación aún no llegó al sindicato):
  /// sigue `PENDING_SEND` con el mismo `operation_id`, `sequence` y contenido.
  Future<void> scheduleConsentRetry(
    JointPurchaseConsentOp op,
    String code,
    DateTime retryAt,
  ) => _write(
    (txn) => _transitionConsent(
      txn,
      op,
      JointPurchaseOpStatus.pendingSend,
      code: code,
      nextAttemptAt: retryAt.toUtc().toIso8601String(),
    ),
  );

  Future<bool> _transitionConsent(
    Transaction txn,
    JointPurchaseConsentOp op,
    String status, {
    String? code,
    String? nextAttemptAt,
  }) async =>
      await txn.rawUpdate(
        'UPDATE ${op.legacy ? consentOpsTable : accessOpsTable} '
        'SET send_status=?, last_code=?, next_attempt_at=?, '
        'attempts=attempts+1, updated_at=? '
        'WHERE operation_id=? AND send_status IN (?,?)',
        [
          status,
          code,
          nextAttemptAt,
          _now(),
          op.operationId,
          JointPurchaseOpStatus.pendingSend,
          JointPurchaseOpStatus.authPaused,
        ],
      ) >
      0;

  // --- Cola del emisor --------------------------------------------------

  /// Lo que hay que enviar por [scope]: por convocatoria, sólo la operación
  /// pendiente más nueva (`PENDING_SEND`, y `AUTH_PAUSED` si
  /// [includePaused]), en orden de convocatoria y `sequence`. La fecha de
  /// reintento la decide el emisor.
  Future<List<JointPurchaseOp>> sendable(
    OwnerScope scope, {
    required bool includePaused,
  }) async {
    final rows = await (await _database.database).query(
      opsTable,
      where:
          'tenant_id=? AND member_id=? AND (send_status=? OR '
          '(send_status=? AND ?=1))',
      whereArgs: [
        scope.tenantId,
        scope.memberId,
        JointPurchaseOpStatus.pendingSend,
        JointPurchaseOpStatus.authPaused,
        includePaused ? 1 : 0,
      ],
      orderBy: 'call_id, sequence DESC',
    );
    final newest = <String, JointPurchaseOp>{};
    for (final op in rows.map(JointPurchaseOp.fromRow)) {
      newest.putIfAbsent(op.callId, () => op);
    }
    return newest.values.toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
  }

  /// Productos de la convocatoria con su unidad base (para validar
  /// respuestas).
  Future<Map<String, String>> productBaseUnits(String callId) async {
    final rows = await (await _database.database).query(
      callsTable,
      columns: ['products_json'],
      where: 'call_id=?',
      whereArgs: [callId],
    );
    if (rows.isEmpty) return const {};
    return {
      for (final product in JointPurchaseProduct.listFromJson(
        jsonDecode(rows.single['products_json']! as String),
      ))
        product.productRef: product.baseUnit,
    };
  }

  /// «Enviar ahora»: lo pendiente de [callId] vence en este momento y lo
  /// pausado por autorización vuelve a la cola. Nunca convierte nada en
  /// terminal: un rechazo sigue siendo rechazo y un reintento sigue siendo
  /// reintento (con fecha de ahora, no nula).
  Future<void> sendNow(String callId) => _write((txn) async {
    final now = _now();
    for (final table in [opsTable, consentOpsTable, accessOpsTable]) {
      await txn.rawUpdate(
        'UPDATE $table SET send_status=?, next_attempt_at=?, updated_at=? '
        'WHERE call_id=? AND send_status IN (?,?)',
        [
          JointPurchaseOpStatus.pendingSend,
          now,
          now,
          callId,
          JointPurchaseOpStatus.pendingSend,
          JointPurchaseOpStatus.authPaused,
        ],
      );
    }
  });

  // --- Transiciones (sólo desde PENDING_SEND o AUTH_PAUSED) -------------

  /// El servidor aceptó la operación (`outcome: ACCEPTED`). [participation]
  /// es la que devolvió; sólo sustituye a la guardada si no es más vieja.
  Future<void> markReceived(
    JointPurchaseOp op,
    JointPurchaseParticipation? participation,
  ) => _write((txn) async {
    if (!await _transition(txn, op, JointPurchaseOpStatus.received)) return;
    await _adopt(txn, op, participation, sequenceIfNull: op.sequence);
  });

  /// E4 §7.2: el sindicato contestó `ACCEPTED`, pero en una forma que este
  /// teléfono no puede leer y que se repetiría igual en cada reenvío. La
  /// operación llegó, así que queda `RECEIVED` con
  /// [JointPurchaseCodes.responseUnreadable], **sin** tocar la copia de lo
  /// aceptado (no se inventa ni se borra nada); la lista la pone al día.
  Future<void> markReceivedUnreadable(JointPurchaseOp op) => _write(
    (txn) => _transition(
      txn,
      op,
      JointPurchaseOpStatus.received,
      code: JointPurchaseCodes.responseUnreadable,
    ),
  );

  /// Rechazo definitivo con [code]. [callStatus] (`CLOSED`/`CANCELLED`)
  /// actualiza la copia local cuando el servidor lo dijo.
  Future<void> markRejected(
    JointPurchaseOp op,
    String code, {
    String? callStatus,
  }) => _write((txn) async {
    if (!await _transition(
      txn,
      op,
      JointPurchaseOpStatus.rejected,
      code: code,
    )) {
      return;
    }
    if (callStatus != null) {
      await txn.update(
        callsTable,
        {'status': callStatus},
        where: 'call_id=? AND member_id=?',
        whereArgs: [op.callId, op.memberId],
      );
    }
  });

  /// `CALL_NOT_OPEN` con `DEADLINE_PASSED`: «Fuera de plazo».
  Future<void> markOutOfTime(JointPurchaseOp op) => _write(
    (txn) => _transition(
      txn,
      op,
      JointPurchaseOpStatus.outOfTime,
      code: JointPurchaseCodes.deadlinePassed,
    ),
  );

  /// `STALE_SEQUENCE`: la operación queda sin efecto y se adopta la
  /// participación vigente que devolvió el servidor (E2 §5.5).
  Future<void> markStale(
    JointPurchaseOp op,
    JointPurchaseParticipation? participation,
  ) => _write((txn) async {
    if (!await _transition(
      txn,
      op,
      JointPurchaseOpStatus.superseded,
      code: JointPurchaseCodes.staleSequence,
    )) {
      return;
    }
    if (participation != null) await _adopt(txn, op, participation);
  });

  /// 401/403: queda pausada hasta un envío pedido por el agricultor.
  Future<void> markAuthPaused(JointPurchaseOp op, String code) => _write(
    (txn) => _transition(txn, op, JointPurchaseOpStatus.authPaused, code: code),
  );

  /// Fallo transitorio: **sigue** `PENDING_SEND` y se reintenta en
  /// [retryAt] con el mismo `operation_id`, `sequence` y contenido.
  Future<void> scheduleRetry(
    JointPurchaseOp op,
    String code,
    DateTime retryAt,
  ) => _write(
    (txn) => _transition(
      txn,
      op,
      JointPurchaseOpStatus.pendingSend,
      code: code,
      nextAttemptAt: retryAt.toUtc().toIso8601String(),
    ),
  );

  Future<bool> _transition(
    Transaction txn,
    JointPurchaseOp op,
    String status, {
    String? code,
    String? nextAttemptAt,
  }) async =>
      await txn.rawUpdate(
        'UPDATE $opsTable SET send_status=?, last_code=?, next_attempt_at=?, '
        'attempts=attempts+1, updated_at=? '
        'WHERE operation_id=? AND send_status IN (?,?)',
        [
          status,
          code,
          nextAttemptAt,
          _now(),
          op.operationId,
          JointPurchaseOpStatus.pendingSend,
          JointPurchaseOpStatus.authPaused,
        ],
      ) >
      0;

  /// Guarda [participation] como lo último aceptado, salvo que lo guardado
  /// sea más nuevo: una respuesta atrasada nunca restaura cantidades
  /// anteriores (E2-D10). Sin participación (retiro sin datos), se toma
  /// [sequenceIfNull] para comparar.
  Future<void> _adopt(
    Transaction txn,
    JointPurchaseOp op,
    JointPurchaseParticipation? participation, {
    int? sequenceIfNull,
  }) async {
    final rows = await txn.query(
      callsTable,
      columns: ['server_participation_json'],
      where: 'call_id=? AND member_id=?',
      whereArgs: [op.callId, op.memberId],
    );
    if (rows.isEmpty) return;
    final stored = JointPurchaseParticipation.decode(
      rows.single['server_participation_json'] as String?,
    );
    final incoming = participation?.lastSequence ?? sequenceIfNull ?? 0;
    if (stored != null && stored.lastSequence > incoming) {
      // Cantidades más nuevas guardadas; el alcance, el más nuevo de los dos.
      if (participation != null) {
        await _adoptFor(txn, op.callId, op.memberId, participation);
      }
      return;
    }
    await txn.update(
      callsTable,
      {
        'server_participation_json': participation == null
            ? null
            : (stored == null ? participation : _merge(stored, participation))
                  .encode(),
      },
      where: 'call_id=? AND member_id=?',
      whereArgs: [op.callId, op.memberId],
    );
  }

  /// Guarda lo más nuevo de [incoming] y lo guardado: las cantidades por
  /// `last_sequence` y el alcance del consentimiento por su propio orden
  /// (E2 §10.6). Una respuesta atrasada nunca restaura ni una cantidad ni
  /// una autorización anteriores.
  Future<void> _adoptFor(
    Transaction txn,
    String callId,
    String memberId,
    JointPurchaseParticipation incoming,
  ) async {
    final rows = await txn.query(
      callsTable,
      columns: ['server_participation_json'],
      where: 'call_id=? AND member_id=?',
      whereArgs: [callId, memberId],
    );
    if (rows.isEmpty) return;
    final stored = JointPurchaseParticipation.decode(
      rows.single['server_participation_json'] as String?,
    );
    final merged = stored == null ? incoming : _merge(stored, incoming);
    await txn.update(
      callsTable,
      {'server_participation_json': merged.encode()},
      where: 'call_id=? AND member_id=?',
      whereArgs: [callId, memberId],
    );
  }

  static JointPurchaseParticipation _merge(
    JointPurchaseParticipation stored,
    JointPurchaseParticipation incoming,
  ) {
    final base = stored.lastSequence > incoming.lastSequence
        ? stored
        : incoming;
    final scope = stored.consentScopeSequence > incoming.consentScopeSequence
        ? stored
        : incoming;
    return identical(base, scope) ? base : base.withScopeOf(scope);
  }
}
