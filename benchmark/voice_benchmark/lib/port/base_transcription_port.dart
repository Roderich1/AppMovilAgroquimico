import 'dart:async';

import 'speech_transcription_port.dart';

/// Reglas de ciclo de vida compartidas por todos los adaptadores.
///
/// Existe para que el contrato se pruebe **una sola vez**: doble inicio,
/// cancelación, timeout, liberación del micrófono y `dispose` idempotente se
/// comportan igual en el motor de Android, en Whisper y en el fake. Un adaptador
/// nuevo hereda el comportamiento en lugar de reimplementarlo, que es donde
/// aparecerían las diferencias entre test y dispositivo (`RISK-007`).
///
/// Las subclases sólo implementan el trabajo del motor: [engineStart],
/// [engineStop], [engineCancel] y [engineDispose].
abstract class BaseSpeechTranscriptionPort implements SpeechTranscriptionPort {
  BaseSpeechTranscriptionPort();

  final StreamController<TranscriptionEvent> _events =
      StreamController<TranscriptionEvent>.broadcast();

  TranscriptionState _state = TranscriptionState.idle;
  Stopwatch? _clock;
  Timer? _deadline;
  bool _disposed = false;

  @override
  TranscriptionState get state => _state;

  @override
  Stream<TranscriptionEvent> get events => _events.stream;

  /// Tiempo transcurrido desde `start()`. Cero fuera de sesión.
  Duration get elapsed => _clock?.elapsed ?? Duration.zero;

  /// `true` mientras el micrófono puede estar tomado.
  bool get isSessionOpen =>
      _state == TranscriptionState.requestingPermission ||
      _state == TranscriptionState.listening ||
      _state == TranscriptionState.processing;

  // --------------------------------------------------------------- protegido

  /// Abre la captura real. Debe pedir permiso y empezar a escuchar.
  Future<void> engineStart(TranscriptionRequest request);

  /// Pide el resultado final y deja de escuchar.
  Future<void> engineStop();

  /// Descarta la sesión en el motor.
  Future<void> engineCancel();

  /// Libera recursos nativos. Debe tolerar ser llamado sin sesión.
  Future<void> engineDispose();

  /// Publica un cambio de estado.
  void emitState(TranscriptionState next) {
    if (_disposed || _state == next) return;
    _state = next;
    _publish(TranscriptionStateChanged(next));
  }

  /// Publica texto parcial. Ignorado si la sesión ya terminó.
  void emitPartial(String text) {
    if (_disposed || !isSessionOpen) return;
    emitState(TranscriptionState.listening);
    _publish(TranscriptionPartial(text, elapsed: elapsed));
  }

  /// Publica el resultado final y cierra la sesión dejando el micrófono libre.
  void emitFinal(String text) {
    if (_disposed) return;
    final at = elapsed;
    _closeSession();
    _publish(TranscriptionFinal(text, elapsed: at));
    emitState(TranscriptionState.preview);
  }

  /// Publica un fallo y cierra la sesión. El micrófono queda libre.
  void emitFailure(TranscriptionErrorCode code, {String? detail}) {
    if (_disposed) return;
    _closeSession();
    _publish(TranscriptionFailed(code, detail: detail));
    emitState(switch (code) {
      TranscriptionErrorCode.permissionDenied ||
      TranscriptionErrorCode.permissionPermanentlyDenied =>
        TranscriptionState.denied,
      TranscriptionErrorCode.serviceUnavailable ||
      TranscriptionErrorCode.localeUnavailable =>
        TranscriptionState.unavailable,
      _ => TranscriptionState.error,
    });
  }

  // ------------------------------------------------------------------ público

  @override
  Future<void> start(TranscriptionRequest request) async {
    if (_disposed) {
      throw StateError('El puerto ya fue liberado.');
    }
    // Doble toque: no se abre una segunda captura ni se pisa la sesión activa.
    if (isSessionOpen) {
      _publish(
        const TranscriptionFailed(
          TranscriptionErrorCode.busy,
          detail: 'session-already-open',
        ),
      );
      return;
    }
    _clock = Stopwatch()..start();
    emitState(TranscriptionState.requestingPermission);
    _deadline = Timer(request.maxDuration, () {
      // Una sesión colgada nunca puede quedarse con el micrófono.
      if (isSessionOpen) {
        unawaited(engineCancel().catchError((_) {}));
        emitFailure(TranscriptionErrorCode.timeout, detail: 'max-duration');
      }
    });
    try {
      await engineStart(request);
    } on Object catch (e) {
      emitFailure(
        TranscriptionErrorCode.engineFailure,
        detail: e.runtimeType.toString(),
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed || !isSessionOpen) return;
    emitState(TranscriptionState.processing);
    try {
      await engineStop();
    } on Object catch (e) {
      emitFailure(
        TranscriptionErrorCode.engineFailure,
        detail: e.runtimeType.toString(),
      );
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    final wasOpen = isSessionOpen;
    _closeSession();
    if (wasOpen) {
      try {
        await engineCancel();
      } on Object {
        // Cancelar nunca puede fallar hacia afuera: el objetivo es soltar el
        // micrófono, y ya se cerró la sesión.
      }
    }
    emitState(TranscriptionState.cancelled);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _closeSession();
    _state = TranscriptionState.idle;
    try {
      await engineDispose();
    } on Object {
      // Liberar recursos es best-effort: propagar aquí dejaría al llamador sin
      // forma de terminar.
    }
    await _events.close();
  }

  // ------------------------------------------------------------------ privado

  void _closeSession() {
    _deadline?.cancel();
    _deadline = null;
    _clock?.stop();
  }

  void _publish(TranscriptionEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }
}
