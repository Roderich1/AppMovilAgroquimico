import 'dart:async';

import 'package:flutter/services.dart';

import '../../data/app_log.dart';
import 'review_selection.dart';
import 'speech_transcription_port.dart';

/// Adaptador de [SpeechTranscriptionPort] sobre el reconocimiento **dentro de
/// la app** (`LocalVoiceEngine` en Kotlin): Vosk en vivo y, si el APK la trae,
/// una segunda pasada local con whisper.cpp (#165, #166).
///
/// ## Lo que lo distingue del adaptador de Android
///
/// * No depende de ningún servicio del sistema ni de paquetes de idioma: el
///   modelo viaja en el APK y el audio se procesa en el proceso de la app. No
///   hay red en ningún punto del camino.
/// * Un turno **sigue escuchando a través de las pausas**
///   ([listensAcrossPauses]): cada pausa cierra una frase numerada, y el
///   micrófono no se cierra hasta que el usuario detiene, el turno agota su
///   plazo o pasan muchos segundos sin voz.
/// * Cada turno lleva un **número de sesión**. Lo que llegue de un número que
///   no es el turno abierto —un resultado tardío de un turno cancelado o
///   anterior— se descarta aquí, sin llegar a la sesión.
///
/// La disciplina de turno es la misma: un turno abierto acaba **siempre** en
/// exactamente un [TranscriptionTurnEnded].
final class LocalSpeechTranscriptionAdapter implements SpeechTranscriptionPort {
  LocalSpeechTranscriptionAdapter({MethodChannel? method, EventChannel? event})
    : _method = method ?? const MethodChannel(methodChannelName),
      _event = event ?? const EventChannel(eventChannelName) {
    _subscription = _event.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object error) => _failTurn(
        TranscriptionErrorCode.engineFailure,
        error.runtimeType.toString(),
      ),
    );
    // Copia, verifica y carga el modelo mientras el usuario lee la pantalla:
    // el primer «Hablar» no espera. No abre el micrófono.
    unawaited(_prepare());
  }

  static const methodChannelName = 'agro.voice/local';
  static const eventChannelName = 'agro.voice/local_events';

  /// Margen para que el motor entregue lo pendiente tras pedir detener.
  static const stopGrace = Duration(seconds: 15);

  final MethodChannel _method;
  final EventChannel _event;
  late final StreamSubscription<dynamic> _subscription;

  final StreamController<TranscriptionEvent> _events =
      StreamController<TranscriptionEvent>.broadcast();

  bool _turnOpen = false;
  bool _disposed = false;
  int _generation = 0;
  int _segments = 0;
  Stopwatch? _clock;
  Timer? _deadline;
  Timer? _stopGuard;
  bool _deadlineHit = false;
  Duration _turnBudget = Duration.zero;
  String? _prepareError;

  @override
  String get engineId => 'vosk-local';

  @override
  bool get listensAcrossPauses => true;

  @override
  bool get isTurnOpen => _turnOpen;

  @override
  Stream<TranscriptionEvent> get events => _events.stream;

  Future<void> _prepare() async {
    try {
      _prepareError = await _method.invokeMethod<String>('prepare');
    } on Object {
      _prepareError = 'prepare-failed';
    }
  }

  @override
  Future<TranscriptionAvailability> checkAvailability(String locale) async {
    try {
      final map =
          await _method.invokeMapMethod<String, Object?>('describe') ??
          const <String, Object?>{};
      final present = map['modelPresent'] as bool? ?? false;
      final reviewModel = (map['reviewAvailable'] as bool? ?? false)
          ? map['reviewModel'] as String?
          : null;
      final availability = TranscriptionAvailability(
        recognizerAvailable: present,
        onDeviceApiReports: false,
        localeSupportKnown: true,
        installedLocales: present ? const ['es'] : const [],
        supportedLocales: present ? const ['es'] : const [],
        airplaneMode: switch (map['airplaneMode']) {
          true => AirplaneMode.on,
          false => AirplaneMode.off,
          _ => AirplaneMode.unknown,
        },
        engineName: map['engineName'] as String? ?? '',
        engineVersion: map['engineVersion'] as String? ?? '',
        reviewModel: reviewModel,
        detail: present ? _prepareError : 'model-missing',
      );
      _emit(TranscriptionAvailabilityObserved(availability));
      return availability;
    } on PlatformException catch (error) {
      return TranscriptionAvailability.none(detail: 'platform:${error.code}');
    } on MissingPluginException {
      return const TranscriptionAvailability.none(detail: 'no-platform');
    }
  }

  @override
  Future<void> start(TranscriptionRequest request) async {
    if (_disposed) throw StateError('El puerto ya fue liberado.');
    if (_turnOpen) {
      _emit(
        const TranscriptionFailed(
          TranscriptionErrorCode.busy,
          detail: 'turn-already-open',
        ),
      );
      return;
    }
    _turnOpen = true;
    _generation++;
    _segments = 0;
    _deadlineHit = false;
    _clock = Stopwatch()..start();
    _turnBudget = request.maxTurnDuration;
    try {
      final reply = await _method.invokeMethod<String>('start', {
        'gen': _generation,
        'hints': _hintText(request.hints),
        'review': request.review,
      });
      // Habrá diálogo de permiso: se avisa ahora, antes de la pausa que
      // provoca, para que la sesión no la tome por «el usuario se fue».
      if (reply == 'awaitingPermission' && _turnOpen) {
        _deadline?.cancel();
        _emit(
          const TranscriptionStageChanged(TranscriptionStage.awaitingPermission),
        );
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
    _armStopGuard();
    try {
      await _method.invokeMethod<void>('stop', {'gen': _generation});
    } on Object catch (error) {
      _failTurn(TranscriptionErrorCode.engineFailure, error.runtimeType.toString());
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    final wasOpen = _turnOpen;
    // Cerrar aquí invalida el número de sesión: nada de lo que llegue después
    // de este turno entra en la sesión.
    if (wasOpen) {
      _emit(const TranscriptionCancelled());
      _closeTurn(TranscriptionEndReason.cancelled);
    }
    try {
      await _method.invokeMethod<void>('cancel');
    } on Object {
      // Cancelar nunca falla hacia afuera: el turno ya está cerrado aquí.
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
    _stopGuard?.cancel();
    _turnOpen = false;
    await _subscription.cancel();
    try {
      await _method.invokeMethod<void>('dispose');
    } on Object {
      // Liberar es best-effort.
    }
    await _events.close();
  }

  // ---------------------------------------------------------------- privado

  /// La pista que recibe la segunda pasada: nombres separados por comas, con
  /// tope de longitud (Whisper admite unos 220 símbolos de contexto).
  static String _hintText(List<String> hints) {
    final out = StringBuffer();
    for (final hint in hints.map((h) => h.trim()).where((h) => h.isNotEmpty)) {
      if (out.length + hint.length + 2 > 600) break;
      if (out.isNotEmpty) out.write(', ');
      out.write(hint);
    }
    return out.isEmpty ? '' : '$out.';
  }

  Duration get _elapsed => _clock?.elapsed ?? Duration.zero;

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final map = raw.cast<Object?, Object?>();
    final type = map['type'] as String?;
    // Sin número sólo llega la cancelación por pérdida de foco, que vale para
    // el turno que esté abierto.
    if (type == 'cancelled') {
      if (!_turnOpen) return;
      _emit(const TranscriptionCancelled());
      _closeTurn(TranscriptionEndReason.cancelled);
      return;
    }
    if (map['gen'] != _generation || !_turnOpen) return;

    switch (type) {
      case 'stage':
        switch (map['stage']) {
          case 'awaitingPermission':
            _deadline?.cancel();
            _emit(
              const TranscriptionStageChanged(
                TranscriptionStage.awaitingPermission,
              ),
            );
          case 'listening':
            _armDeadline();
            _emit(
              const TranscriptionRouteInUse(TranscriptionEngineRoute.embedded),
            );
            _emit(const TranscriptionLocaleInUse('es'));
            _emit(const TranscriptionStageChanged(TranscriptionStage.listening));
          case 'processing':
            _emit(
              const TranscriptionStageChanged(TranscriptionStage.processing),
            );
        }

      case 'partial':
        _emit(
          TranscriptionPartial(
            map['text'] as String? ?? '',
            elapsed: _elapsed,
            reviewing: map['reviewing'] as int? ?? 0,
          ),
        );

      case 'segment':
        final choice = chooseReviewedText(
          map['vosk'] as String? ?? '',
          map['review'] as String?,
        );
        // Diagnóstico con códigos y tiempos, nunca con lo dictado.
        AppLog.info(
          'voz local: frase ${map['seq']} ${choice.verdict.name} '
          'revision=${map['reviewMs']}ms',
        );
        if (choice.text.isEmpty) return;
        _segments++;
        _emit(
          TranscriptionSegment(
            choice.text,
            elapsed: _elapsed,
            sequence: map['seq'] as int?,
            revised: choice.revised,
          ),
        );

      case 'error':
        _failTurn(_codeFrom(map['code'] as String?), map['detail'] as String?);

      case 'ended':
        final reason = switch (map['reason']) {
          'timeout' => TranscriptionEndReason.timeout,
          'error' => TranscriptionEndReason.error,
          _ when _deadlineHit => TranscriptionEndReason.timeout,
          _ when _segments == 0 => TranscriptionEndReason.noMatch,
          _ => TranscriptionEndReason.stoppedByUser,
        };
        switch (reason) {
          case TranscriptionEndReason.noMatch:
            _emit(const TranscriptionNoMatch());
          case TranscriptionEndReason.timeout:
            _emit(const TranscriptionTimeout());
          default:
            break;
        }
        _closeTurn(reason);
    }
  }

  void _failTurn(TranscriptionErrorCode code, String? detail) {
    if (_disposed) return;
    _emit(TranscriptionFailed(code, detail: detail));
    if (_turnOpen) {
      unawaited(_method.invokeMethod<void>('cancel').catchError((_) {}));
      _closeTurn(TranscriptionEndReason.error);
    }
  }

  /// Plazo del turno desde que el micrófono está abierto. Al vencer se pide
  /// detener —lo dicho se conserva— y el cierre cuenta como `timeout`.
  void _armDeadline() {
    _deadline?.cancel();
    _deadline = Timer(_turnBudget, () {
      if (!_turnOpen) return;
      _deadlineHit = true;
      unawaited(stop());
    });
  }

  /// Si el motor no cierra tras detener, se cancela: un turno colgado no puede
  /// quedarse con el micrófono.
  void _armStopGuard() {
    _stopGuard?.cancel();
    final generation = _generation;
    _stopGuard = Timer(stopGrace, () {
      if (!_turnOpen || _generation != generation) return;
      unawaited(_method.invokeMethod<void>('cancel').catchError((_) {}));
      _emit(const TranscriptionTimeout());
      _closeTurn(TranscriptionEndReason.timeout);
    });
  }

  void _closeTurn(TranscriptionEndReason reason) {
    _deadline?.cancel();
    _deadline = null;
    _stopGuard?.cancel();
    _stopGuard = null;
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
}
