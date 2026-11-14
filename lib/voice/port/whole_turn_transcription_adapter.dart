import 'dart:async';

import 'package:flutter/services.dart';

import '../../data/app_log.dart';
import 'local_speech_transcription_adapter.dart'
    show LocalSpeechTranscriptionAdapter;
import 'native_event_hub.dart';
import 'speech_transcription_port.dart';
import 'voice_engine_diagnostics.dart';

/// Puerto experimental **«un solo transcriptor por turno»** (F09, 2026-11-09).
///
/// Mismo motor nativo y mismos canales que [LocalSpeechTranscriptionAdapter],
/// pero en modo `whole`: el micrófono graba todo el turno en memoria (tope
/// [maxCapture]) y, al pulsar «Terminar», el modelo de revisión transcribe el
/// audio entero de una vez. Vosk no segmenta, no produce parciales y no decide
/// si el modelo corre. Un solo modelo por turno, la variante que diga
/// [VoiceExperiment.turnVariant] al abrirlo; nunca se combinan resultados.
///
/// Garantías:
/// * **Nada tardío entra.** Cada turno lleva un número único en el proceso;
///   un resultado de un turno cancelado o anterior se descarta aquí.
/// * **Cancelar descarta el audio.** No llega ningún segmento del turno.
/// * **Un resultado vacío, el silencio o un error** cierran el turno con su
///   motivo y dejan la sesión recuperable, sin texto nuevo.
/// * **Sólo códigos y tiempos en el registro.** El texto va únicamente a la
///   sesión que lo pidió, por el flujo de eventos.
final class WholeTurnTranscriptionAdapter implements SpeechTranscriptionPort {
  WholeTurnTranscriptionAdapter({
    MethodChannel? method,
    EventChannel? event,
    String? variant,
    WholeTurnDecoding? decoding,
    this.maxCapture = defaultMaxCapture,
    this.transcriptionTimeout = defaultTranscriptionTimeout,
  }) : _method =
           method ??
           const MethodChannel(
             LocalSpeechTranscriptionAdapter.methodChannelName,
           ),
       _event =
           event ??
           const EventChannel(LocalSpeechTranscriptionAdapter.eventChannelName),
       _fixedVariant = variant,
       _fixedDecoding = decoding {
    _lease = NativeEventHub.attach(
      _event,
      onEvent: _onNativeEvent,
      onError: (Object error) => _failTurn(
        TranscriptionErrorCode.engineFailure,
        error.runtimeType.toString(),
      ),
    );
  }

  /// Audio máximo de un turno. Es la ventana del modelo (30 s): más audio
  /// serían varias ventanas y el modo perdería su sentido. Al llegar, el turno
  /// termina solo y lo oído se transcribe igual.
  static const defaultMaxCapture = Duration(seconds: 30);

  /// Tope de la transcripción del turno entero, explícito: pasado, se aborta
  /// y el turno termina por tiempo, sin texto.
  static const defaultTranscriptionTimeout = Duration(seconds: 45);

  /// Margen tras pedir terminar: la transcripción entera más la carga del
  /// modelo. Si el motor no cierra, se cancela.
  static const stopGraceMargin = Duration(seconds: 20);

  final Duration maxCapture;
  final Duration transcriptionTimeout;

  /// Caracteres máximos de la pista del turno entero.
  static const maxHintChars = 400;

  /// Decodificación del próximo turno: la fijada al crear el puerto (pruebas)
  /// o la de [VoiceExperiment.turnDecoding].
  WholeTurnDecoding get decoding =>
      _fixedDecoding ?? VoiceExperiment.instance.turnDecoding;
  final WholeTurnDecoding? _fixedDecoding;
  final MethodChannel _method;
  final EventChannel _event;

  /// Variante fija (pruebas); sin ella, la del experimento al abrir el turno.
  final String? _fixedVariant;
  late final NativeEventLease _lease;

  final StreamController<TranscriptionEvent> _events =
      StreamController<TranscriptionEvent>.broadcast();

  bool _turnOpen = false;
  bool _disposed = false;
  int _generation = 0;
  bool _delivered = false;
  bool _deadlineHit = false;
  String _variantInUse = '';
  Stopwatch? _clock;
  Timer? _deadline;
  Timer? _stopGuard;
  Duration _turnBudget = Duration.zero;

  /// Variante que correrá en el próximo turno.
  String get variant => _fixedVariant ?? VoiceExperiment.instance.turnVariant;

  @override
  String get engineId => singleTranscriberTurnEngineId;

  @override
  bool get listensAcrossPauses => true;

  @override
  bool get isTurnOpen => _turnOpen;

  @override
  Stream<TranscriptionEvent> get events => _events.stream;

  Duration get _elapsed => _clock?.elapsed ?? Duration.zero;

  @override
  Future<TranscriptionAvailability> checkAvailability(String locale) async {
    try {
      final map =
          await _method.invokeMapMethod<String, Object?>('describe') ??
          const <String, Object?>{};
      final reviewAvailable = map['reviewAvailable'] as bool? ?? false;
      final variants =
          (map['reviewVariants'] as List?)?.whereType<String>().toList() ??
          const <String>[];
      final models =
          (map['reviewModels'] as Map?)?.cast<Object?, Object?>() ??
          const <Object?, Object?>{};
      final chosen = variant;
      final usable = reviewAvailable && variants.contains(chosen);
      final detail = !reviewAvailable
          ? (map['reviewNativeLib'] as String? ??
                map['reviewDetail'] as String? ??
                'review-unavailable')
          : (usable ? null : 'variant-missing:$chosen');
      AppLog.info(
        'voz turno: variante=$chosen disponible=${usable ? 'si' : 'no'} '
        'variantes=${variants.join('/')}${detail == null ? '' : ' motivo=$detail'}',
      );
      final availability = TranscriptionAvailability(
        recognizerAvailable: usable,
        onDeviceApiReports: false,
        localeSupportKnown: true,
        installedLocales: usable ? const ['es'] : const [],
        supportedLocales: usable ? const ['es'] : const [],
        airplaneMode: switch (map['airplaneMode']) {
          true => AirplaneMode.on,
          false => AirplaneMode.off,
          _ => AirplaneMode.unknown,
        },
        engineName: 'Un solo transcriptor por turno ($chosen)',
        engineVersion: models[chosen] as String? ?? '',
        // Sin revisión aparte: el único modelo es el transcriptor.
        reviewModel: null,
        reviewDetail: usable ? 'turno-entero' : null,
        detail: detail,
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
    final generation = _generation =
        LocalSpeechTranscriptionAdapter.nextGeneration();
    _delivered = false;
    _deadlineHit = false;
    _clock = Stopwatch()..start();
    _turnBudget = request.maxTurnDuration < maxCapture
        ? request.maxTurnDuration
        : maxCapture;
    _variantInUse = variant;
    try {
      final reply = await _method.invokeMethod<String>('start', {
        'gen': generation,
        'mode': 'whole',
        'variant': _variantInUse,
        // Tope de la pista por debajo de los 223 tokens que whisper.cpp
        // admite (n_text_ctx / 2 − 1); más allá recorta el principio en
        // silencio. ~2,4 caracteres por token con nombres de productos
        // (medido en HOST, 2026-11-10): 400 caracteres ≈ 170 tokens.
        'hints': LocalSpeechTranscriptionAdapter.hintText(
          request.hints,
          maxChars: maxHintChars,
        ),
        'beamSize': decoding.beamSize,
        'review': false,
        'turnMaxMs': maxCapture.inMilliseconds,
        'turnTimeoutMs': transcriptionTimeout.inMilliseconds,
      });
      if (reply == 'awaitingPermission' &&
          _turnOpen &&
          _generation == generation) {
        _deadline?.cancel();
        _emit(
          const TranscriptionStageChanged(
            TranscriptionStage.awaitingPermission,
          ),
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
      _failTurn(
        TranscriptionErrorCode.engineFailure,
        error.runtimeType.toString(),
      );
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    if (_turnOpen) {
      AppLog.info('voz turno: turno=$_generation cancelado');
      _emit(const TranscriptionCancelled());
      _closeTurn(TranscriptionEndReason.cancelled);
    }
    try {
      await _method.invokeMethod<void>('cancel', {'gen': _generation});
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
    await cancel();
    _disposed = true;
    try {
      await _method.invokeMethod<void>('dispose', {'gen': _generation});
    } on Object {
      // Liberar no falla hacia afuera.
    }
    await _lease.cancel();
    await _events.close();
  }

  // ------------------------------------------------------------------ eventos

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final map = raw.cast<Object?, Object?>();
    final type = map['type'] as String?;
    if (type == 'cancelled') {
      if (!_turnOpen) return;
      _emit(const TranscriptionCancelled());
      _closeTurn(TranscriptionEndReason.cancelled);
      return;
    }
    // De otro turno (anterior, cancelado o de otra pantalla): no es nuestro.
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
            _emit(
              const TranscriptionStageChanged(TranscriptionStage.listening),
            );
          case 'processing':
            _emit(
              const TranscriptionStageChanged(TranscriptionStage.processing),
            );
        }

      case 'turnText':
        final outcome = map['outcome'] as String? ?? 'error';
        final text = (map['text'] as String?)?.trim() ?? '';
        final info =
            (map['info'] as Map?)?.cast<Object?, Object?>() ??
            const <Object?, Object?>{};
        _noteMetric(outcome, text.isNotEmpty, info);
        switch (outcome) {
          case 'ok':
            if (text.isNotEmpty) {
              _delivered = true;
              _emit(
                TranscriptionSegment(
                  text,
                  elapsed: _elapsed,
                  sequence: 0,
                  revised: false,
                  turn: _generation,
                ),
              );
            }
          case 'aborted':
            _emit(const TranscriptionTimeout());
            _closeTurn(TranscriptionEndReason.timeout);
          case 'unavailable':
            // El motor manda a continuación su `error` con el código.
            break;
          default:
            _failTurn(TranscriptionErrorCode.engineFailure, 'turn-transcribe');
        }

      case 'error':
        _failTurn(_codeFrom(map['code'] as String?), map['detail'] as String?);

      case 'ended':
        final reason = switch (map['reason']) {
          'error' => TranscriptionEndReason.error,
          // Se alcanzó el audio máximo del turno: lo oído ya se entregó.
          'maxDuration' || 'timeout' => TranscriptionEndReason.timeout,
          _ when _deadlineHit => TranscriptionEndReason.timeout,
          _ when !_delivered => TranscriptionEndReason.noMatch,
          _ => TranscriptionEndReason.stoppedByUser,
        };
        switch (reason) {
          case TranscriptionEndReason.noMatch:
            _emit(const TranscriptionNoMatch());
          case TranscriptionEndReason.timeout:
            if (!_delivered) _emit(const TranscriptionTimeout());
          default:
            break;
        }
        _closeTurn(reason);
    }
  }

  void _noteMetric(String outcome, bool hadText, Map<Object?, Object?> info) {
    int asInt(Object? v) => (v as num?)?.round() ?? 0;
    final metric = SingleTranscriberTurnMetric(
      turn: _generation,
      variant: info['variant'] as String? ?? _variantInUse,
      model: info['model'] as String? ?? '-',
      outcome: outcome,
      hadText: hadText,
      audioMs: asInt(info['audioMs']),
      speechMs: asInt(info['speechMs']),
      speechDbfs: (info['speechRmsDbfs'] as num?)?.round(),
      loadMs: asInt(info['loadMs']),
      inferenceMs: asInt(info['inferenceMs']),
      closedBy: info['closedBy'] as String? ?? '-',
      beamSize: (info['beamSize'] as num?)?.round() ?? 1,
      leadingQuietMs: _quiet(info['leadingQuietMs']),
      trailingQuietMs: _quiet(info['trailingQuietMs']),
      droppedMs: asInt(info['droppedMs']),
    );
    VoiceExperiment.instance.noteTurn(metric);
    // Sólo códigos y tiempos; nunca el texto.
    AppLog.info(metric.logLine);
  }

  /// `-1` del motor (sin voz detectada) → `null`.
  static int? _quiet(Object? v) {
    final n = (v as num?)?.round();
    return n == null || n < 0 ? null : n;
  }

  void _failTurn(TranscriptionErrorCode code, String? detail) {
    if (_disposed || !_turnOpen) return;
    _emit(TranscriptionFailed(code, detail: detail));
    unawaited(
      _method
          .invokeMethod<void>('cancel', {'gen': _generation})
          .catchError((_) {}),
    );
    _closeTurn(TranscriptionEndReason.error);
  }

  /// Plazo de grabación desde que el micrófono está abierto: al vencer se
  /// pide terminar y lo grabado se transcribe igual.
  void _armDeadline() {
    _deadline?.cancel();
    _deadline = Timer(_turnBudget, () {
      if (!_turnOpen) return;
      _deadlineHit = true;
      unawaited(stop());
    });
  }

  void _armStopGuard() {
    // Un segundo «terminar» (el plazo de grabación tras el toque del usuario)
    // no alarga el margen: cuenta desde la primera petición.
    if (_stopGuard != null) return;
    final generation = _generation;
    _stopGuard = Timer(transcriptionTimeout + stopGraceMargin, () {
      if (!_turnOpen || _generation != generation) return;
      unawaited(
        _method
            .invokeMethod<void>('cancel', {'gen': generation})
            .catchError((_) {}),
      );
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
