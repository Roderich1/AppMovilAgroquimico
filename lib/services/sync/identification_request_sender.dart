import 'dart:math';

import '../../data/owner_binding_store.dart';
import '../../data/product_photo_storage.dart' show ProductPhoto;
import '../../data/sync/identification_request_store.dart';
import '../../domain/sync/identification_view.dart';
import 'identification_api.dart';
import 'sync_access.dart';
import 'sync_worker.dart' show SyncBackoff;

/// Resultado de un ciclo del emisor. Sin datos del producto ni credenciales.
class IdentificationRunReport {
  int received = 0;
  int rejected = 0;
  int retried = 0;
  int photosSent = 0;
  int photosFailed = 0;
  int photosRemoved = 0;
  int viewsApplied = 0;

  /// El sindicato respondió 401/403: el acceso en memoria ya no sirve.
  bool authFailed = false;

  /// La cuenta en sesión no es la del titular: no se envió nada.
  bool ownerMismatch = false;

  /// La lista del sindicato no se pudo leer o no respetó el contrato.
  bool listUnavailable = false;

  @override
  String toString() =>
      'IdentificationRunReport(received: $received, rejected: $rejected, '
      'retried: $retried, photosSent: $photosSent, photosFailed: '
      '$photosFailed, photosRemoved: $photosRemoved, viewsApplied: '
      '$viewsApplied, authFailed: $authFailed, ownerMismatch: '
      '$ownerMismatch, listUnavailable: $listUnavailable)';
}

/// Emisor de las solicitudes de identificación (contrato E1 §5.3).
///
/// Dos pasos independientes por solicitud (E1-D12): primero los datos
/// (`PUT /{id}` con el mismo `request_id` siempre, así un reenvío nunca
/// duplica) y, sólo cuando el sindicato los recibió, la foto autorizada
/// (`PUT /{id}/photo`) o su retiro (`DELETE /{id}/photo`). Una foto
/// pendiente o fallida no bloquea la solicitud. Después lee `GET /` y guarda
/// la vista del sindicato; **nunca** vincula.
///
/// - Códigos 4xx terminales: la solicitud queda `REJECTED` o la foto
///   `FAILED` sin reintento.
/// - 401/403: la solicitud queda `AUTH_PAUSED` (o la foto como estaba) y el
///   ciclo se detiene; se reanuda con el próximo envío explícito.
/// - 5xx, 429, red o respuesta inválida: reintento con [SyncBackoff].
///
/// No usa `sync_outbox` ni Sync v1, y nunca envía ids locales.
class IdentificationRequestSender {
  IdentificationRequestSender({
    required IdentificationRequestStore store,
    required OwnerBindingStore owners,
    required IdentificationApi Function() api,
    required Future<ProductPhoto?> Function(int productId) photoOf,
    this.backoff = const SyncBackoff(),
    Random? random,
    DateTime Function()? clock,
  }) : _store = store,
       _owners = owners,
       _api = api,
       _photoOf = photoOf,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final IdentificationRequestStore _store;
  final OwnerBindingStore _owners;
  final IdentificationApi Function() _api;
  final Future<ProductPhoto?> Function(int productId) _photoOf;
  final SyncBackoff backoff;
  final Random _random;
  final DateTime Function() _clock;

  Future<IdentificationRunReport>? _running;

  /// Códigos que rechazan los datos para siempre (E1 §5.3).
  static const terminalDataCodes = {
    'PAYLOAD_INVALID',
    'UNIT_UNSUPPORTED',
    'REQUEST_ID_CONFLICT',
    'UNIT_IMMUTABLE',
  };

  /// Códigos que hacen fallar la foto sin reintento.
  static const terminalPhotoCodes = {
    'IMAGE_INVALID',
    'IMAGE_TOO_LARGE',
    'PHOTO_CONSENT_REQUIRED',
    'PAYLOAD_INVALID',
    'REQUEST_ID_CONFLICT',
  };

  /// Un ciclo con [access]. [includePaused] reanuda lo pausado por
  /// autorización: sólo en un envío que pidió el agricultor. Un ciclo en
  /// curso no se duplica: se espera el mismo.
  Future<IdentificationRunReport> run(
    VerifiedAccess access, {
    bool includePaused = false,
  }) {
    final current = _running;
    if (current != null) return current;
    final next = _run(access, includePaused).whenComplete(() {
      _running = null;
    });
    return _running = next;
  }

  Future<IdentificationRunReport> _run(
    VerifiedAccess access,
    bool includePaused,
  ) async {
    final report = IdentificationRunReport();
    final tenantId = access.scope.tenantId;
    // Sin ninguna solicitud no hay nada que enviar ni que consultar: una sola
    // lectura y ninguna llamada de red.
    if (!await _store.hasAny(tenantId)) return report;
    final owner = await _owners.activeBinding();
    if (owner == null || owner.scope != access.scope) {
      report.ownerMismatch = true;
      return report;
    }
    final api = _api();
    final token = access.accessToken;
    final pending = await _store.withPendingWork(
      tenantId,
      includePaused: includePaused,
    );
    for (final request in pending) {
      if (!await _process(api, token, request, includePaused, report)) {
        return report;
      }
    }
    await _readViews(api, token, report);
    return report;
  }

  bool _due(String? at) =>
      at == null || !DateTime.parse(at).isAfter(_clock().toUtc());

  DateTime _retryAt(int attempts, Duration? retryAfter) =>
      _clock().add(backoff.delay(attempts, _random, retryAfter: retryAfter));

  static bool _isAuth(IdentificationResponse response) =>
      response.statusCode == 401 || response.statusCode == 403;

  static String _authCode(IdentificationResponse response) =>
      response.statusCode == 401 ? 'AUTH_REQUIRED' : 'FORBIDDEN';

  static String _codeOf(IdentificationResponse response) =>
      response.errorCode ??
      response.transportCode ??
      'HTTP_${response.statusCode}';

  Map<String, Object?> _body(IdentificationRequest request) => {
    'contractVersion': 1,
    'local_name': request.sentName,
    'active_ingredient': request.sentActiveIngredient,
    'unit': request.sentUnit,
    'photo_consent':
        request.photoConsentVersion == null || request.photoConsentAt == null
        ? null
        : {
            'version': request.photoConsentVersion,
            'accepted_at': request.photoConsentAt,
          },
  };

  /// Procesa una solicitud. Devuelve false si el ciclo debe detenerse (401
  /// o 403).
  Future<bool> _process(
    IdentificationApi api,
    String token,
    IdentificationRequest request,
    bool includePaused,
    IdentificationRunReport report,
  ) async {
    var received = request.sendStatus == IdentificationSendStatus.received;
    var dataSentNow = false;
    final dataDue =
        (request.sendStatus == IdentificationSendStatus.pendingSend &&
            _due(request.nextAttemptAt)) ||
        (request.sendStatus == IdentificationSendStatus.authPaused &&
            includePaused);
    if (dataDue) {
      final response = await api.upsert(
        request.requestId,
        _body(request),
        token,
      );
      if (_isAuth(response)) {
        await _store.markAuthPaused(request.requestId, _authCode(response));
        report.authFailed = true;
        return false;
      }
      final view = response.ok ? _view(response.body) : null;
      if (view != null && view.requestId == request.requestId) {
        await _store.markReceived(request.requestId);
        await _store.applyParsedView(view);
        report.received++;
        received = true;
        dataSentNow = true;
      } else if (!response.ok && _terminalData(response)) {
        await _store.markRejected(request.requestId, _codeOf(response));
        report.rejected++;
        return true;
      } else {
        await _store.scheduleRetry(
          request.requestId,
          response.ok ? 'INVALID_RESPONSE' : _codeOf(response),
          _retryAt(request.sendAttempts + 1, response.retryAfter),
        );
        report.retried++;
        return true;
      }
    }
    if (!received) return true;
    return _processPhoto(api, token, request, dataSentNow, report);
  }

  bool _terminalData(IdentificationResponse response) {
    final status = response.statusCode;
    if (status == null) return false;
    if (terminalDataCodes.contains(response.errorCode)) return true;
    return status == 400 || status == 409 || status == 413 || status == 422;
  }

  bool _terminalPhoto(IdentificationResponse response) {
    final status = response.statusCode;
    if (status == null) return false;
    if (terminalPhotoCodes.contains(response.errorCode)) return true;
    if (response.errorCode == 'CONTENT_HASH_MISMATCH') return false;
    return status == 400 || status == 409 || status == 413 || status == 422;
  }

  Future<bool> _processPhoto(
    IdentificationApi api,
    String token,
    IdentificationRequest request,
    bool dataSentNow,
    IdentificationRunReport report,
  ) async {
    final status = request.photoSendStatus;
    if (status == IdentificationPhotoStatus.removePending &&
        _due(request.photoNextAttemptAt)) {
      final response = await api.deletePhoto(request.requestId, token);
      if (_isAuth(response)) {
        report.authFailed = true;
        return false;
      }
      if (response.ok || response.statusCode == 404) {
        await _store.markPhotoRemoved(request.requestId);
        report.photosRemoved++;
      } else {
        await _store.schedulePhotoRemovalRetry(
          request.requestId,
          _codeOf(response),
          _retryAt(request.photoAttempts + 1, response.retryAfter),
        );
      }
      return true;
    }
    final sendDue =
        (status == IdentificationPhotoStatus.pendingSend ||
            request.photoRetryable) &&
        _due(request.photoNextAttemptAt);
    if (!sendDue) return true;

    final consented = request.photoSha256Consented;
    final photo = await _photoOf(request.productId);
    if (consented == null ||
        request.photoConsentVersion == null ||
        photo == null ||
        !photo.exists ||
        photo.sha256 != consented) {
      // Sólo sale la foto autorizada, tal cual: si ya no está o cambió, no
      // se envía otra en su lugar.
      await _store.markPhotoFailed(request.requestId, 'PHOTO_MISSING');
      report.photosFailed++;
      return true;
    }
    if (!dataSentNow) {
      // El consentimiento vigente viaja con los datos antes que la foto: un
      // reemplazo con consentimiento nuevo lo registra en el sindicato.
      final refreshed = await api.upsert(
        request.requestId,
        _body(request),
        token,
      );
      if (_isAuth(refreshed)) {
        report.authFailed = true;
        return false;
      }
      final view = refreshed.ok ? _view(refreshed.body) : null;
      if (view == null) {
        await _store.markPhotoFailed(
          request.requestId,
          refreshed.ok ? 'INVALID_RESPONSE' : _codeOf(refreshed),
          retryAt: _retryAt(request.photoAttempts + 1, refreshed.retryAfter),
        );
        report.photosFailed++;
        return true;
      }
      await _store.applyParsedView(view);
    }
    final response = await api.uploadPhoto(
      request.requestId,
      photo.file,
      consented,
      token,
    );
    if (_isAuth(response)) {
      report.authFailed = true;
      return false;
    }
    if (response.ok) {
      await _store.markPhotoSent(request.requestId, consented);
      final view = _view(response.body);
      if (view != null) await _store.applyParsedView(view);
      report.photosSent++;
    } else {
      await _store.markPhotoFailed(
        request.requestId,
        _codeOf(response),
        retryAt: _terminalPhoto(response)
            ? null
            : _retryAt(request.photoAttempts + 1, response.retryAfter),
      );
      report.photosFailed++;
    }
    return true;
  }

  Future<void> _readViews(
    IdentificationApi api,
    String token,
    IdentificationRunReport report,
  ) async {
    final response = await api.listOwn(token);
    if (_isAuth(response)) {
      report.authFailed = true;
      return;
    }
    if (!response.ok) {
      report.listUnavailable = true;
      return;
    }
    final List<IdentificationServerView> views;
    try {
      views = IdentificationServerView.listFromJson(response.body);
    } on IdentificationViewFormatException {
      report.listUnavailable = true;
      return;
    }
    for (final view in views) {
      if (await _store.applyParsedView(view)) report.viewsApplied++;
    }
  }

  static IdentificationServerView? _view(Object? body) {
    try {
      return IdentificationServerView.fromJson(body);
    } on IdentificationViewFormatException {
      return null;
    }
  }
}
