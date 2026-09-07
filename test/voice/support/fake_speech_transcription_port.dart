import 'dart:async';

import 'package:agroquimicos/voice/port/speech_transcription_port.dart';

/// Guion de **un turno** del motor falso.
///
/// Describe qué hará el "motor" sin micrófono, sin hilo nativo y sin teléfono.
/// Es lo que permite probar permiso denegado, idioma ausente, `noMatch`,
/// timeout, servicio muerto y continuidad de forma determinista.
final class FakeTurn {
  const FakeTurn({
    this.partials = const [],
    this.segment,
    this.failWith,
    this.failDetail,
    this.noMatch = false,
    this.timeout = false,
    this.silent = false,
    this.acceptsLocale,
    this.delay = Duration.zero,
    this.endsOnStop = false,
    this.announcesLocaleBeforeFailing = false,
    this.awaitsPermission = false,
    this.acceptsRoute,
    this.reportsRoute,
  });

  /// Parciales que se emiten al abrir el turno, en orden.
  final List<String> partials;

  /// Segmento final del turno. `null` si el turno no produce texto.
  final String? segment;

  /// Si no es nulo, el turno falla con este código.
  final TranscriptionErrorCode? failWith;
  final String? failDetail;

  /// El motor termina sin reconocer nada.
  final bool noMatch;

  /// El motor agota el plazo.
  final bool timeout;

  /// **Servicio muerto**: no llega ningún callback. El turno queda abierto hasta
  /// que alguien lo cancele o venza su plazo. Reproduce el caso en que
  /// `SpeechRecognizer` se queda sin responder y el micrófono quedaría tomado.
  final bool silent;

  /// Si no es nulo, el turno sólo funciona con ese locale exacto; con cualquier
  /// otro falla con [TranscriptionErrorCode.localeUnavailable].
  ///
  /// Reproduce lo medido en `ADR-002`: `es-BO` da error 12, `es-ES` error 13 y
  /// sólo un locale concreto llega a escuchar.
  final String? acceptsLocale;

  /// Demora antes de emitir. Con `fake_async` permite probar backoff y timeout.
  final Duration delay;

  /// El segmento no llega solo: espera a que la sesión pida `stop()`.
  ///
  /// Es el turno "el usuario habla y calla cuando quiere", frente al turno que
  /// Android cierra por su cuenta al detectar silencio.
  final bool endsOnStop;

  /// El motor anuncia que está listo a escuchar y **luego** falla.
  ///
  /// No es un caso teórico: el HONOR JDY-LX3P (Android 16 / API 36) emitió
  /// `onReadyForSpeech` para `es-MX` y a continuación devolvió el error 12. Sin
  /// este guion no se puede reproducir el defecto de mostrar como «utilizado»
  /// un idioma que nunca llegó a funcionar.
  final bool announcesLocaleBeforeFailing;

  /// El turno se queda esperando a que el sistema resuelva el permiso.
  ///
  /// Es el estado real entre tocar el micrófono y contestar el diálogo: el
  /// motor **no** ha arrancado y no hay micrófono tomado. Reproducirlo hace
  /// falta para comprobar que mostrar el diálogo —que pone la aplicación en
  /// segundo plano— no cancela la sesión.
  final bool awaitsPermission;

  /// Si no es nulo, el turno sólo funciona por ese reconocedor; con el otro
  /// falla con [TranscriptionErrorCode.localeUnavailable].
  ///
  /// Reproduce el HONOR JDY-LX3P de `DEFECTO-004`: el reconocedor local existe
  /// y no tiene ningún español, mientras que el servicio del sistema sí
  /// transcribe.
  final TranscriptionEngineRoute? acceptsRoute;

  /// El camino que el motor **dice** estar usando, si no es el pedido.
  ///
  /// Es el caso de API 31: se pide el reconocedor local, el sistema no lo tiene
  /// y entrega el predeterminado sin avisar a nadie.
  final TranscriptionEngineRoute? reportsRoute;

  /// Turno sano con texto.
  static const ok = FakeTurn(
    partials: ['registrar', 'registrar compra'],
    segment: 'registrar compra de cincuenta litros',
  );
}

/// Implementación determinista de [SpeechTranscriptionPort], sin plataforma.
///
/// Reproduce el contrato completo del puerto: doble inicio, cancelación,
/// liberación del micrófono, `dispose` idempotente y exactamente un
/// [TranscriptionTurnEnded] por turno abierto.
final class FakeSpeechTranscriptionPort implements SpeechTranscriptionPort {
  FakeSpeechTranscriptionPort({List<FakeTurn>? script, this.repeatLast = true})
    : _script = List<FakeTurn>.from(script ?? const [FakeTurn.ok]);

  final List<FakeTurn> _script;

  /// Al agotar el guion, repite el último turno. Sin esto, probar la
  /// continuidad exigiría escribir cien turnos idénticos.
  final bool repeatLast;

  final StreamController<TranscriptionEvent> _events =
      StreamController<TranscriptionEvent>.broadcast();

  /// Disponibilidad que devolverá [checkAvailability].
  TranscriptionAvailability availability = const TranscriptionAvailability(
    recognizerAvailable: true,
    onDeviceApiReports: false,
    localeSupportKnown: false,
    airplaneMode: AirplaneMode.unknown,
    engineName: 'fake',
    engineVersion: 'test',
  );

  // --------------------------------------------------------------- registro

  /// Peticiones con las que se abrió cada turno, en orden.
  final List<TranscriptionRequest> startRequests = <TranscriptionRequest>[];
  final List<String> calls = <String>[];
  int openSettingsCalls = 0;

  /// `true` mientras el turno tiene el micrófono tomado.
  bool microphoneOpen = false;

  /// Nunca debe quedar `true` al terminar una prueba.
  bool get microphoneReleased => !microphoneOpen;

  bool _disposed = false;
  int _turnIndex = 0;
  FakeTurn? _openTurn;
  Timer? _pending;

  /// Locales con los que se intentó abrir un turno, en orden. Es lo que prueba
  /// la lista de fallback sin depender de un teléfono.
  List<String> get attemptedLocales =>
      startRequests.map((r) => r.locale).toList(growable: false);

  // ----------------------------------------------------------------- puerto

  @override
  String get engineId => 'fake';

  @override
  bool get isTurnOpen => _openTurn != null;

  @override
  Stream<TranscriptionEvent> get events => _events.stream;

  @override
  Future<TranscriptionAvailability> checkAvailability(String locale) async {
    calls.add('availability');
    _emit(TranscriptionAvailabilityObserved(availability));
    return availability;
  }

  @override
  Future<void> start(TranscriptionRequest request) async {
    if (_disposed) throw StateError('El puerto ya fue liberado.');
    calls.add('start');
    if (isTurnOpen) {
      // Doble toque: no se abre una segunda captura ni se pisa el turno vivo.
      _emit(
        const TranscriptionFailed(
          TranscriptionErrorCode.busy,
          detail: 'turn-already-open',
        ),
      );
      return;
    }
    startRequests.add(request);
    final turn = _nextTurn();
    _openTurn = turn;
    microphoneOpen = true;

    if (turn.delay == Duration.zero) {
      _run(turn, request);
    } else {
      _pending = Timer(turn.delay, () => _run(turn, request));
    }
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    final turn = _openTurn;
    if (turn == null) return;
    if (turn.endsOnStop) {
      _emit(const TranscriptionStageChanged(TranscriptionStage.processing));
      final text = turn.segment;
      if (text != null && text.isNotEmpty) {
        _emit(TranscriptionSegment(text, elapsed: Duration.zero));
        _end(TranscriptionEndReason.stoppedByUser);
      } else {
        _emit(const TranscriptionNoMatch());
        _end(TranscriptionEndReason.noMatch);
      }
      return;
    }
    // Un turno que ya se estaba cerrando solo: `stop` sólo apura el cierre.
    if (turn.silent) _end(TranscriptionEndReason.stoppedByUser);
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    if (!isTurnOpen) {
      // Cancelar sin turno no toca el motor, pero deja el micrófono libre.
      microphoneOpen = false;
      return;
    }
    _emit(const TranscriptionCancelled());
    _end(TranscriptionEndReason.cancelled);
  }

  @override
  Future<bool> openSystemSettings() async {
    openSettingsCalls++;
    calls.add('openSystemSettings');
    return true;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    calls.add('dispose');
    _pending?.cancel();
    _pending = null;
    _openTurn = null;
    microphoneOpen = false;
    await _events.close();
  }

  /// Inyecta un evento suelto, fuera del guion.
  ///
  /// Sirve para lo que un guion no puede describir: que el motor repita el
  /// resultado de un turno ya cerrado, o que el sistema anuncie el diálogo de
  /// permiso. Son los dos casos en que la sesión debe defenderse del motor.
  void emitForTest(TranscriptionEvent event) => _emit(event);

  // ---------------------------------------------------------------- privado

  FakeTurn _nextTurn() {
    if (_turnIndex < _script.length) return _script[_turnIndex++];
    if (repeatLast && _script.isNotEmpty) return _script.last;
    return const FakeTurn(noMatch: true);
  }

  void _run(FakeTurn turn, TranscriptionRequest request) {
    _pending = null;
    if (_openTurn != turn) return;

    // El motor anuncia por dónde escucha antes que nada: en Android el
    // reconocedor ya está creado cuando empieza el turno.
    _emit(TranscriptionRouteInUse(turn.reportsRoute ?? request.route));

    final route = turn.acceptsRoute;
    if (route != null && route != (turn.reportsRoute ?? request.route)) {
      _announceIfRequested(turn, request);
      _emit(
        TranscriptionFailed(
          TranscriptionErrorCode.localeUnavailable,
          detail: turn.failDetail ?? 'fake-route',
        ),
      );
      _end(TranscriptionEndReason.error);
      return;
    }

    final accepted = turn.acceptsLocale;
    if (accepted != null && accepted != request.locale) {
      _announceIfRequested(turn, request);
      _emit(
        const TranscriptionFailed(
          TranscriptionErrorCode.localeUnavailable,
          detail: 'fake-locale',
        ),
      );
      _end(TranscriptionEndReason.error);
      return;
    }

    if (turn.failWith != null) {
      _announceIfRequested(turn, request);
      _emit(TranscriptionFailed(turn.failWith!, detail: turn.failDetail));
      _end(TranscriptionEndReason.error);
      return;
    }

    if (turn.awaitsPermission) {
      _emit(
        const TranscriptionStageChanged(TranscriptionStage.awaitingPermission),
      );
      // El micrófono no se toma hasta que haya permiso.
      microphoneOpen = false;
      return;
    }

    _emit(const TranscriptionStageChanged(TranscriptionStage.listening));
    _emit(TranscriptionLocaleInUse(request.locale));

    if (turn.silent) return;

    for (final partial in turn.partials) {
      _emit(TranscriptionPartial(partial, elapsed: Duration.zero));
    }

    if (turn.endsOnStop) return;

    if (turn.timeout) {
      _emit(const TranscriptionTimeout());
      _end(TranscriptionEndReason.timeout);
      return;
    }
    if (turn.noMatch || turn.segment == null) {
      _emit(const TranscriptionNoMatch());
      _end(TranscriptionEndReason.noMatch);
      return;
    }
    _emit(const TranscriptionStageChanged(TranscriptionStage.processing));
    _emit(TranscriptionSegment(turn.segment!, elapsed: Duration.zero));
    _end(TranscriptionEndReason.segment);
  }

  /// Reproduce el motor que dice «listo» y después falla.
  void _announceIfRequested(FakeTurn turn, TranscriptionRequest request) {
    if (!turn.announcesLocaleBeforeFailing) return;
    _emit(const TranscriptionStageChanged(TranscriptionStage.listening));
    _emit(TranscriptionLocaleInUse(request.locale));
  }

  void _end(TranscriptionEndReason reason) {
    _pending?.cancel();
    _pending = null;
    _openTurn = null;
    microphoneOpen = false;
    _emit(TranscriptionTurnEnded(reason));
  }

  void _emit(TranscriptionEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }
}
