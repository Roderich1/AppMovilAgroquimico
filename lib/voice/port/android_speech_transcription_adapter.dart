import 'dart:async';

import 'package:flutter/services.dart';

import 'native_event_hub.dart';
import 'speech_transcription_port.dart';

/// Adaptador de [SpeechTranscriptionPort] sobre `android.speech.SpeechRecognizer`.
///
/// Es el motor productivo que fijó `ADR-002`. **No añade ninguna dependencia ni
/// modelo al APK**: el reconocimiento lo pone el propio sistema, y por eso el
/// crecimiento medido de la distribución fue de 0 B.
///
/// El puente transporta **texto y estados**. El audio no cruza a Dart, no se
/// escribe en disco y no aparece en ningún registro. Cambiar de motor —a Whisper
/// como reserva, o a cualquier otro— significa escribir otra clase como ésta y
/// no tocar nada más: es el escape hatch que exige `ADR-002`.
///
/// Toda la disciplina de turno vive aquí, no en Kotlin: un turno abierto acaba
/// **siempre** en exactamente un [TranscriptionTurnEnded], incluso si el servicio
/// del sistema se queda mudo. Sin ese cierre garantizado la sesión no sabría
/// cuándo el micrófono quedó libre.
///
/// Cada turno lleva un **número de turno** único en el proceso (#119). El lado
/// nativo lo devuelve en cada evento, y lo que llegue con otro número —un
/// resultado tardío de un turno cancelado, o de la pantalla anterior— se
/// descarta aquí, sin llegar a la sesión.
final class AndroidSpeechTranscriptionAdapter
    implements SpeechTranscriptionPort {
  AndroidSpeechTranscriptionAdapter({
    MethodChannel? method,
    EventChannel? event,
  }) : _method = method ?? const MethodChannel(methodChannelName),
       _event = event ?? const EventChannel(eventChannelName) {
    _lease = NativeEventHub.attach(
      _event,
      onEvent: _onNativeEvent,
      onError: (Object error) => _failTurn(
        TranscriptionErrorCode.engineFailure,
        error.runtimeType.toString(),
      ),
    );
  }

  static const methodChannelName = 'agro.voice/speech';
  static const eventChannelName = 'agro.voice/speech_events';

  final MethodChannel _method;
  final EventChannel _event;
  late final NativeEventLease _lease;

  /// Último número de turno entregado en este proceso. Compartido entre
  /// instancias: dos pantallas vivas a la vez no pueden repetir número.
  static int _lastGeneration = 0;

  final StreamController<TranscriptionEvent> _events =
      StreamController<TranscriptionEvent>.broadcast();

  bool _turnOpen = false;
  bool _disposed = false;
  int _generation = 0;
  Stopwatch? _clock;
  Timer? _deadline;

  /// Cuánto puede durar el turno una vez el motor está escuchando.
  Duration _turnBudget = Duration.zero;

  @override
  String get engineId => 'android-speech';

  @override
  bool get listensAcrossPauses => false;

  @override
  bool get isTurnOpen => _turnOpen;

  @override
  Stream<TranscriptionEvent> get events => _events.stream;

  @override
  Future<TranscriptionAvailability> checkAvailability(String locale) async {
    try {
      final raw = await _method.invokeMapMethod<String, Object?>(
        'availability',
        {'locale': locale},
      );
      final map = raw ?? const <String, Object?>{};
      final availability = TranscriptionAvailability(
        recognizerAvailable: map['recognizerAvailable'] as bool? ?? false,
        onDeviceApiReports: map['onDeviceApiReports'] as bool? ?? false,
        localeSupportKnown: map['localeSupportKnown'] as bool? ?? false,
        installedLocales: _strings(map['installedLocales']),
        supportedLocales: _strings(map['supportedLocales']),
        airplaneMode: _airplaneFrom(map['airplaneMode']),
        engineName: map['engineName'] as String? ?? '',
        engineVersion: map['engineVersion'] as String? ?? '',
        detail: map['detail'] as String?,
      );
      _emit(TranscriptionAvailabilityObserved(availability));
      return availability;
    } on PlatformException catch (error) {
      // Sin plataforma —o con un servicio que no responde— no se sabe nada. Se
      // devuelve el "no se sabe" honesto y la sesión intentará igualmente:
      // `EVO-009-REQ-014` prohíbe decidir con la consulta.
      return TranscriptionAvailability.none(detail: 'platform:${error.code}');
    } on MissingPluginException {
      return const TranscriptionAvailability.none(detail: 'no-platform');
    }
  }

  @override
  Future<void> start(TranscriptionRequest request) async {
    if (_disposed) throw StateError('El puerto ya fue liberado.');
    if (_turnOpen) {
      // Doble toque: no se abre una segunda captura ni se pisa el turno vivo.
      _emit(
        const TranscriptionFailed(
          TranscriptionErrorCode.busy,
          detail: 'turn-already-open',
        ),
      );
      return;
    }
    _turnOpen = true;
    final generation = _generation = ++_lastGeneration;
    _clock = Stopwatch()..start();
    _turnBudget = request.maxTurnDuration;
    _armDeadline();
    try {
      final reply = await _method.invokeMethod<Object?>('start', {
        'gen': generation,
        'locale': request.locale,
        'preferOffline': request.preferOffline,
        'partialResults': request.partialResults,
        'route': request.route.name,
      });
      // #119: habrá diálogo de permiso. Se sabe por la respuesta, que llega
      // antes que la pausa que provoca el propio diálogo; el evento podía
      // llegar después, y entonces la sesión tomaba la pausa por «el usuario
      // se fue» y cancelaba justo antes de que concediera.
      if (reply == 'awaitingPermission' &&
          _turnOpen &&
          _generation == generation) {
        _onStage(TranscriptionStage.awaitingPermission);
      }
    } on PlatformException catch (error) {
      _failTurn(TranscriptionErrorCode.engineFailure, 'platform:${error.code}');
    } on MissingPluginException {
      _failTurn(TranscriptionErrorCode.recognizerUnavailable, 'no-platform');
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed || !_turnOpen) return;
    try {
      await _method.invokeMethod<void>('stop', {'gen': _generation});
    } on PlatformException catch (error) {
      _failTurn(TranscriptionErrorCode.engineFailure, 'platform:${error.code}');
    } on MissingPluginException {
      _failTurn(TranscriptionErrorCode.recognizerUnavailable, 'no-platform');
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    final wasOpen = _turnOpen;
    // Se cierra ANTES de hablar con el motor: mientras se espera la respuesta,
    // un resultado de este turno ya no puede entrar en la sesión.
    if (wasOpen) {
      _emit(const TranscriptionCancelled());
      _closeTurn(TranscriptionEndReason.cancelled);
    }
    try {
      await _method.invokeMethod<void>('cancel', {'gen': _generation});
    } on Object {
      // Cancelar nunca puede fallar hacia afuera: el objetivo es soltar el
      // micrófono y el turno ya se da por cerrado aquí.
    }
  }

  @override
  Future<bool> openSystemSettings() async {
    try {
      return await _method.invokeMethod<bool>('openSettings') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _deadline?.cancel();
    _deadline = null;
    _turnOpen = false;
    await _lease.cancel();
    try {
      // Con el número: liberar esta pantalla no puede cortar el turno de otra
      // que ya se abrió (#119).
      await _method.invokeMethod<void>('dispose', {'gen': _generation});
    } on Object {
      // Liberar recursos es best-effort: propagar aquí dejaría al llamador sin
      // forma de terminar de cerrar la pantalla.
    }
    await _events.close();
  }

  // ---------------------------------------------------------------- privado

  Duration get _elapsed => _clock?.elapsed ?? Duration.zero;

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final map = raw.cast<Object?, Object?>();
    // Un evento con número de turno sólo vale para ese turno. Sin número sólo
    // llega la cancelación por pérdida de foco, que vale para el que esté
    // abierto.
    final gen = map['gen'];
    if (gen != null && gen != _generation) return;
    // Todo evento es de un turno: con el turno cerrado no queda a quién
    // atribuirlo. Un error suelto, además, quedaría pendiente en la sesión y
    // haría fallar el turno siguiente.
    if (!_turnOpen) return;
    switch (map['type'] as String?) {
      case 'stage':
        final name = map['stage'] as String?;
        for (final stage in TranscriptionStage.values) {
          if (stage.name == name) _onStage(stage);
        }

      // El reconocedor que el motor creó de verdad, que puede no ser el pedido:
      // en API 31 se pide el local y el sistema entrega el predeterminado.
      case 'route':
        final name = map['route'] as String?;
        for (final route in TranscriptionEngineRoute.values) {
          if (route.name == name) _emit(TranscriptionRouteInUse(route));
        }

      case 'locale':
        final locale = map['locale'] as String?;
        if (locale != null) _emit(TranscriptionLocaleInUse(locale));

      case 'partial':
        _emit(
          TranscriptionPartial(map['text'] as String? ?? '', elapsed: _elapsed),
        );

      case 'final':
        _emit(
          TranscriptionSegment(map['text'] as String? ?? '', elapsed: _elapsed),
        );
        _closeTurn(TranscriptionEndReason.segment);

      case 'noMatch':
        _emit(const TranscriptionNoMatch());
        _closeTurn(TranscriptionEndReason.noMatch);

      // `ERROR_SPEECH_TIMEOUT`: el motor no oyó habla. Se distingue de `noMatch`
      // —que sí oyó algo y no lo reconoció— porque la sesión los cuenta igual
      // pero el diagnóstico debe poder separarlos.
      case 'timeout':
        _emit(const TranscriptionTimeout());
        _closeTurn(TranscriptionEndReason.timeout);

      case 'error':
        _failTurn(_codeFrom(map['code'] as String?), map['detail'] as String?);

      case 'cancelled':
        _emit(const TranscriptionCancelled());
        _closeTurn(TranscriptionEndReason.cancelled);
    }
  }

  void _onStage(TranscriptionStage stage) {
    switch (stage) {
      // `DEFECTO-005`: el plazo protege contra un motor colgado que se quede
      // con el micrófono. Mientras el sistema pregunta por el permiso no hay
      // micrófono tomado, así que no tiene nada que proteger. Dejarlo correr
      // vencía el turno mientras el diálogo seguía abierto, la sesión reabría
      // otro turno y pedía el permiso por segunda vez; Android respondía «Can
      // request only one set of permissions at a time» y entregaba una
      // denegación inmediata. En el HONOR JDY-LX3P eso convirtió un permiso
      // **concedido** en «Permiso de micrófono denegado».
      case TranscriptionStage.awaitingPermission:
        _deadline?.cancel();
        _deadline = null;
      // El micrófono se acaba de abrir: el plazo cuenta desde aquí, no desde
      // antes de saber si habría permiso.
      case TranscriptionStage.listening:
        _armDeadline();
      case TranscriptionStage.processing:
        break;
    }
    _emit(TranscriptionStageChanged(stage));
  }

  void _failTurn(TranscriptionErrorCode code, String? detail) {
    // Sin turno abierto no hay a quién atribuir el fallo: un error suelto
    // quedaría pendiente en la sesión y haría fallar el turno siguiente
    // (#119). `start` abre el turno antes de hablar con el motor, así que una
    // denegación del permiso siempre encuentra su turno.
    if (_disposed || !_turnOpen) return;
    _emit(TranscriptionFailed(code, detail: detail));
    _closeTurn(TranscriptionEndReason.error);
  }

  /// Arma el plazo del turno desde ahora.
  ///
  /// Un turno colgado no puede quedarse con el micrófono: se cancela en el
  /// motor y se cierra aquí aunque el sistema nunca conteste.
  void _armDeadline() {
    _deadline?.cancel();
    _deadline = Timer(_turnBudget, () {
      if (!_turnOpen) return;
      unawaited(
        _method
            .invokeMethod<void>('cancel', {'gen': _generation})
            .catchError((_) {}),
      );
      _emit(const TranscriptionTimeout());
      _closeTurn(TranscriptionEndReason.timeout);
    });
  }

  void _closeTurn(TranscriptionEndReason reason) {
    _deadline?.cancel();
    _deadline = null;
    _clock?.stop();
    _turnOpen = false;
    _emit(TranscriptionTurnEnded(reason));
  }

  void _emit(TranscriptionEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  static TranscriptionErrorCode _codeFrom(String? name) {
    for (final code in TranscriptionErrorCode.values) {
      if (code.name == name) return code;
    }
    return TranscriptionErrorCode.engineFailure;
  }

  static AirplaneMode _airplaneFrom(Object? value) => switch (value) {
    true => AirplaneMode.on,
    false => AirplaneMode.off,
    _ => AirplaneMode.unknown,
  };

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }
}
