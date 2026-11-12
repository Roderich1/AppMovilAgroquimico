import 'dart:math';

import '../../data/owner_binding_store.dart';
import '../../data/sync/joint_purchase_store.dart';
import '../../domain/sync/joint_purchase_call_view.dart';
import '../auth/auth_api_exception.dart';
import 'joint_purchase_api.dart';
import 'sync_access.dart';
import 'sync_worker.dart' show SyncBackoff;

/// Resultado de un ciclo del emisor. Sin cantidades ni credenciales.
class JointPurchaseRunReport {
  int received = 0;
  int rejected = 0;
  int outOfTime = 0;
  int superseded = 0;
  int retried = 0;

  /// Se leyó y guardó la lista del sindicato.
  bool listed = false;

  /// El sindicato respondió 401/403: el acceso en memoria ya no sirve.
  bool authFailed = false;

  /// La cuenta en sesión no es la del titular: no se envió ni leyó nada.
  bool ownerMismatch = false;

  /// La lista del sindicato no se pudo leer o no respetó el contrato.
  bool listUnavailable = false;

  /// N7: por qué no se pudo leer la lista, para decirlo con precisión:
  /// [JointPurchaseListProblem.incompatibleVersion] (hay que actualizar la
  /// aplicación), [JointPurchaseListProblem.offline] (sin conexión) o
  /// [JointPurchaseListProblem.temporary] (el sindicato no respondió bien).
  JointPurchaseListProblem? listProblem;

  /// Sin dirección del sindicato configurada: nada que hacer.
  bool apiUnavailable = false;

  /// Algo cambió en la base: las pantallas deben releer.
  bool get changed =>
      listed ||
      received + rejected + outOfTime + superseded + retried > 0 ||
      authFailed;

  @override
  String toString() =>
      'JointPurchaseRunReport(received: $received, rejected: $rejected, '
      'outOfTime: $outOfTime, superseded: $superseded, retried: $retried, '
      'listed: $listed, authFailed: $authFailed, ownerMismatch: '
      '$ownerMismatch, listUnavailable: $listUnavailable, apiUnavailable: '
      '$apiUnavailable)';
}

/// N7 (E2 §10.6): motivo de una lista no leída.
enum JointPurchaseListProblem { incompatibleVersion, offline, temporary }

/// Resultado de pedir una página de «Historial» (E2 §10.1).
enum JointPurchaseHistoryOutcome {
  /// Página guardada en el teléfono.
  saved,

  /// Sin respuesta del sindicato (red o plazo).
  offline,

  /// 401/403: el acceso en memoria ya no sirve.
  authFailed,

  /// La cuenta en sesión no es la del titular: no se pidió nada.
  ownerMismatch,

  /// Sin dirección del sindicato configurada.
  apiUnavailable,

  /// `400 PAYLOAD_INVALID`: el sindicato no reconoce el cursor.
  invalidCursor,

  /// N7: el sindicato usa otra versión del contrato: actualizar la app.
  incompatibleVersion,

  /// Otra respuesta, o una que no respeta el contrato: no se guarda nada.
  unavailable,
}

class JointPurchaseHistoryResult {
  const JointPurchaseHistoryResult(
    this.outcome, {
    this.saved = 0,
    this.nextCursor,
  });

  final JointPurchaseHistoryOutcome outcome;

  /// Convocatorias guardadas de esta página.
  final int saved;

  /// Para «Ver más»; null si no hay más páginas (o si no se guardó nada).
  final String? nextCursor;

  @override
  String toString() =>
      'JointPurchaseHistoryResult(${outcome.name}, saved: $saved, '
      'more: ${nextCursor != null})';
}

/// Emisor de las participaciones en convocatorias (contrato E2 §4.2 y §5).
///
/// Por convocatoria, sólo sale la operación pendiente más nueva (las
/// anteriores ya quedaron `SUPERSEDED` al prepararla), siempre con el mismo
/// `operation_id`, `sequence` y contenido: un reenvío nunca duplica (E2-D10).
/// Después lee `GET /me/joint-purchase-calls` y guarda la lista.
///
/// - `ACCEPTED` → `RECEIVED` y se adopta la participación devuelta (si no
///   es más vieja que la guardada).
/// - `409 CALL_NOT_OPEN`: `DEADLINE_PASSED` → `OUT_OF_TIME`; `CLOSED`,
///   `CANCELLED`, `DRAFT` → `REJECTED` (y la copia local toma el estado).
/// - `409 STALE_SEQUENCE` → `SUPERSEDED` y se adopta la participación
///   vigente del servidor.
/// - Otros 400/404/409/413/422 → `REJECTED` con su código.
/// - 401/403 → `AUTH_PAUSED` y el ciclo se detiene.
/// - 5xx, 429, red o respuesta inválida → sigue `PENDING_SEND` con
///   [SyncBackoff].
///
/// Nunca envía si la cuenta en sesión no es la del titular, ni operaciones
/// preparadas por otro titular (E2-D16). No usa `sync_outbox` ni Sync v1.
class JointPurchaseSender {
  JointPurchaseSender({
    required JointPurchaseStore store,
    required OwnerBindingStore owners,
    required JointPurchaseApi Function() api,
    this.backoff = const SyncBackoff(),
    this.listInterval = const Duration(minutes: 10),
    Random? random,
    DateTime Function()? clock,
  }) : _store = store,
       _owners = owners,
       _api = api,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final JointPurchaseStore _store;
  final OwnerBindingStore _owners;
  final JointPurchaseApi Function() _api;
  final SyncBackoff backoff;

  /// Separación mínima entre lecturas automáticas de la lista (los ciclos
  /// del worker son cada minuto). Un «Actualizar» del agricultor, o un
  /// envío en este ciclo, lee siempre.
  final Duration listInterval;
  final Random _random;
  final DateTime Function() _clock;

  Future<JointPurchaseRunReport>? _running;
  DateTime? _lastListedAt;

  /// Un ciclo con [access]. [includePaused] reanuda lo pausado por
  /// autorización (sólo en una acción del agricultor); [forceList] lee la
  /// lista aunque se haya leído hace poco. Un ciclo automático en curso no se
  /// duplica; una acción del agricultor espera al que esté en curso y hace
  /// el suyo.
  Future<JointPurchaseRunReport> run(
    VerifiedAccess access, {
    bool includePaused = false,
    bool forceList = false,
  }) async {
    final current = _running;
    if (current != null) {
      if (!includePaused && !forceList) return current;
      try {
        await current;
      } on Object {
        // El ciclo anterior ya informó lo suyo.
      }
      return run(access, includePaused: includePaused, forceList: forceList);
    }
    final next = _run(access, includePaused, forceList);
    _running = next;
    try {
      return await next;
    } finally {
      if (identical(_running, next)) _running = null;
    }
  }

  Future<JointPurchaseRunReport> _run(
    VerifiedAccess access,
    bool includePaused,
    bool forceList,
  ) async {
    final report = JointPurchaseRunReport();
    final JointPurchaseApi api;
    try {
      // Sin dirección configurada falla aquí, sin leer la base.
      api = _api();
    } on AuthApiException {
      report.apiUnavailable = true;
      return report;
    }
    final owner = await _owners.activeBinding();
    if (owner == null || owner.scope != access.scope) {
      report.ownerMismatch = true;
      return report;
    }
    final token = access.accessToken;
    final pending = await _store.sendable(
      access.scope,
      includePaused: includePaused,
    );
    var processed = false;
    for (final op in pending) {
      final due =
          op.sendStatus == JointPurchaseOpStatus.authPaused ||
          _due(op.nextAttemptAt);
      if (!due) continue;
      processed = true;
      if (!await _send(api, token, op, report)) return report;
    }
    // E2 §10.6: las decisiones sobre el consentimiento van después (una
    // primera confirmación enviada en este ciclo ya existe en el sindicato),
    // en su propia cola y con su propio orden.
    final decisions = await _store.sendableConsent(
      access.scope,
      includePaused: includePaused,
    );
    for (final op in decisions) {
      final due =
          op.sendStatus == JointPurchaseOpStatus.authPaused ||
          _due(op.nextAttemptAt);
      if (!due) continue;
      processed = true;
      if (!await _sendConsent(api, token, op, report)) return report;
    }
    final now = _clock();
    final last = _lastListedAt;
    if (forceList ||
        processed ||
        last == null ||
        now.difference(last) >= listInterval) {
      await _list(api, access, report);
    }
    return report;
  }

  /// «Consultar historial» / «Ver más» (E2 §10.1): pide una página de
  /// convocatorias terminadas anteriores con [access] y la guarda sin
  /// borrar nada. Nunca envía operaciones ni pide si la cuenta en sesión no
  /// es la del titular. Una respuesta que no respeta el contrato no guarda
  /// nada de esa página.
  Future<JointPurchaseHistoryResult> fetchHistory(
    VerifiedAccess access, {
    String? before,
    int limit = jointPurchaseHistoryPageSize,
  }) async {
    final JointPurchaseApi api;
    try {
      api = _api();
    } on AuthApiException {
      return const JointPurchaseHistoryResult(
        JointPurchaseHistoryOutcome.apiUnavailable,
      );
    }
    final owner = await _owners.activeBinding();
    if (owner == null || owner.scope != access.scope) {
      return const JointPurchaseHistoryResult(
        JointPurchaseHistoryOutcome.ownerMismatch,
      );
    }
    // Un cursor que no tiene la forma de los que emite el sindicato no sale
    // del teléfono.
    if (before != null && !jointPurchaseHistoryCursor.hasMatch(before)) {
      return const JointPurchaseHistoryResult(
        JointPurchaseHistoryOutcome.invalidCursor,
      );
    }
    final response = await api.history(
      access.accessToken,
      before: before,
      limit: limit,
    );
    if (response.isAuth) {
      return const JointPurchaseHistoryResult(
        JointPurchaseHistoryOutcome.authFailed,
      );
    }
    if (response.statusCode == null) {
      return JointPurchaseHistoryResult(
        response.transportCode == 'TRANSPORT'
            ? JointPurchaseHistoryOutcome.unavailable
            : JointPurchaseHistoryOutcome.offline,
      );
    }
    if (response.statusCode == 400 && response.errorCode == 'PAYLOAD_INVALID') {
      return const JointPurchaseHistoryResult(
        JointPurchaseHistoryOutcome.invalidCursor,
      );
    }
    if (!response.ok) {
      return const JointPurchaseHistoryResult(
        JointPurchaseHistoryOutcome.unavailable,
      );
    }
    final JointPurchaseHistoryPage page;
    try {
      page = JointPurchaseHistoryPage.fromJson(response.body, limit: limit);
    } on JointPurchaseVersionException {
      return const JointPurchaseHistoryResult(
        JointPurchaseHistoryOutcome.incompatibleVersion,
      );
    } on JointPurchaseFormatException {
      return const JointPurchaseHistoryResult(
        JointPurchaseHistoryOutcome.unavailable,
      );
    }
    await _store.saveHistory(access.scope, page.calls);
    return JointPurchaseHistoryResult(
      JointPurchaseHistoryOutcome.saved,
      saved: page.calls.length,
      nextCursor: page.nextCursor,
    );
  }

  bool _due(String? at) =>
      at == null || !DateTime.parse(at).isAfter(_clock().toUtc());

  DateTime _retryAt(int attempts, Duration? retryAfter) =>
      _clock().add(backoff.delay(attempts, _random, retryAfter: retryAfter));

  static String _authCode(JointPurchaseResponse response) =>
      response.statusCode == 401 ? 'AUTH_REQUIRED' : 'FORBIDDEN';

  /// E2 §10.6: el consentimiento sólo viaja en la confirmación que lo
  /// guardó (la primera participación); modificar no lo lleva.
  Map<String, Object?> _body(JointPurchaseOp op) => op.isWithdraw
      ? {'operation_id': op.operationId, 'sequence': op.sequence}
      : {
          'operation_id': op.operationId,
          'sequence': op.sequence,
          if (op.consentVersion != null && op.consentAcceptedAt != null)
            'consent': {
              'version': op.consentVersion,
              'accepted_at': op.consentAcceptedAt,
            },
          // P-A C1: la responsable que se mostró al aceptar (primera vez).
          if (op.consentVersion != null && op.responsibleVersion != null)
            'responsible_version': op.responsibleVersion,
          'lines': op.wireLines,
        };

  /// Envía una decisión sobre el consentimiento. Devuelve false si el ciclo
  /// debe detenerse (401/403).
  ///
  /// - `ACCEPTED` → `RECEIVED` (aplicada en el sindicato).
  /// - `STALE_SEQUENCE` → `SUPERSEDED`: una decisión posterior ya rige.
  /// - `PARTICIPATION_REQUIRED` (la primera confirmación aún no llegó), 5xx,
  ///   429, red o respuesta inválida → sigue pendiente y se reintenta.
  /// - Otros 400/404/409/422 → `REJECTED` con su código.
  Future<bool> _sendConsent(
    JointPurchaseApi api,
    String token,
    JointPurchaseConsentOp op,
    JointPurchaseRunReport report,
  ) async {
    final response = await api.decideConsent(op.callId, op.wireBody, token);
    if (response.isAuth) {
      await _store.markConsentAuthPaused(op, _authCode(response));
      report.authFailed = true;
      return false;
    }
    final products = await _store.productBaseUnits(op.callId);
    if (response.ok) {
      final JointPurchaseParticipation? participation;
      try {
        participation = parseAcceptedResponse(response.body, products);
      } on JointPurchaseFormatException {
        await _store.scheduleConsentRetry(
          op,
          'INVALID_RESPONSE',
          _retryAt(op.attempts + 1, null),
        );
        report.retried++;
        return true;
      }
      await _store.markConsentReceived(op, participation);
      report.received++;
      return true;
    }
    final status = response.statusCode;
    if (status == 409 && response.errorCode == 'STALE_SEQUENCE') {
      final error = JointPurchaseErrorBody.tryParse(response.body, products);
      await _store.markConsentStale(op, error?.participation);
      report.superseded++;
      return true;
    }
    // P-A C1: la responsable cambió antes de que llegara la decisión, o se
    // intentó ampliar sin autorizarla. Rechazo definitivo (no se reintenta:
    // el agricultor revisa de nuevo); se adopta la participación vigente.
    if (status == 409 &&
        (response.errorCode == 'RESPONSIBLE_CHANGED' ||
            response.errorCode == 'AUTHORIZATION_REQUIRED')) {
      final error = JointPurchaseErrorBody.tryParse(response.body, products);
      await _store.markConsentRejected(
        op,
        response.errorCode!,
        participation: error?.participation,
      );
      report.rejected++;
      return true;
    }
    if (status == 409 && response.errorCode == 'PARTICIPATION_REQUIRED') {
      await _store.scheduleConsentRetry(
        op,
        'PARTICIPATION_REQUIRED',
        _retryAt(op.attempts + 1, null),
      );
      report.retried++;
      return true;
    }
    if (status != null && const {400, 404, 409, 413, 422}.contains(status)) {
      await _store.markConsentRejected(op, response.code);
      report.rejected++;
      return true;
    }
    await _store.scheduleConsentRetry(
      op,
      response.code,
      _retryAt(op.attempts + 1, response.retryAfter),
    );
    report.retried++;
    return true;
  }

  /// Envía [op]. Devuelve false si el ciclo debe detenerse (401/403).
  Future<bool> _send(
    JointPurchaseApi api,
    String token,
    JointPurchaseOp op,
    JointPurchaseRunReport report,
  ) async {
    final response = op.isWithdraw
        ? await api.withdraw(op.callId, _body(op), token)
        : await api.confirm(op.callId, _body(op), token);
    if (response.isAuth) {
      await _store.markAuthPaused(op, _authCode(response));
      report.authFailed = true;
      return false;
    }
    final products = await _store.productBaseUnits(op.callId);
    if (response.ok) {
      final JointPurchaseParticipation? participation;
      try {
        participation = parseAcceptedResponse(response.body, products);
      } on JointPurchaseFormatException {
        await _store.scheduleRetry(
          op,
          'INVALID_RESPONSE',
          _retryAt(op.attempts + 1, null),
        );
        report.retried++;
        return true;
      }
      await _store.markReceived(op, participation);
      report.received++;
      return true;
    }
    final status = response.statusCode;
    final error = JointPurchaseErrorBody.tryParse(response.body, products);
    if (status == 409 && response.errorCode == 'CALL_NOT_OPEN') {
      switch (error?.reason) {
        case CallNotOpenReason.deadlinePassed:
          await _store.markOutOfTime(op);
          report.outOfTime++;
        case CallNotOpenReason.closed:
          await _store.markRejected(
            op,
            JointPurchaseCodes.callClosed,
            callStatus: JointPurchaseCallStatus.closed,
          );
          report.rejected++;
        case CallNotOpenReason.cancelled:
          await _store.markRejected(
            op,
            JointPurchaseCodes.callCancelled,
            callStatus: JointPurchaseCallStatus.cancelled,
          );
          report.rejected++;
        case CallNotOpenReason.draft:
          await _store.markRejected(op, JointPurchaseCodes.callDraft);
          report.rejected++;
        default:
          await _store.markRejected(op, 'CALL_NOT_OPEN');
          report.rejected++;
      }
      return true;
    }
    if (status == 409 && response.errorCode == 'STALE_SEQUENCE') {
      await _store.markStale(op, error?.participation);
      report.superseded++;
      return true;
    }
    if (status != null && const {400, 404, 409, 413, 422}.contains(status)) {
      await _store.markRejected(op, response.code);
      report.rejected++;
      return true;
    }
    await _store.scheduleRetry(
      op,
      response.code,
      _retryAt(op.attempts + 1, response.retryAfter),
    );
    report.retried++;
    return true;
  }

  Future<void> _list(
    JointPurchaseApi api,
    VerifiedAccess access,
    JointPurchaseRunReport report,
  ) async {
    final response = await api.list(access.accessToken);
    if (response.isAuth) {
      report.authFailed = true;
      return;
    }
    if (!response.ok) {
      report.listUnavailable = true;
      report.listProblem =
          response.statusCode == null && response.transportCode != 'TRANSPORT'
          ? JointPurchaseListProblem.offline
          : JointPurchaseListProblem.temporary;
      return;
    }
    final JointPurchaseCallList list;
    try {
      list = JointPurchaseCallList.fromJson(response.body);
    } on JointPurchaseVersionException {
      report.listUnavailable = true;
      report.listProblem = JointPurchaseListProblem.incompatibleVersion;
      return;
    } on JointPurchaseFormatException {
      report.listUnavailable = true;
      report.listProblem = JointPurchaseListProblem.temporary;
      return;
    }
    await _store.saveFetched(access.scope, list);
    _lastListedAt = _clock();
    report.listed = true;
  }
}
