import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

import '../../data/app_log.dart';
import 'native_event_hub.dart';
import 'review_capability.dart';
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
/// * Cada turno lleva un **número de sesión**, único en el proceso. Lo que
///   llegue de un número que no es el turno abierto —un resultado tardío de un
///   turno cancelado o anterior, o de la pantalla anterior— se descarta aquí,
///   sin llegar a la sesión.
/// * Si el modelo falta o no se pudo preparar (copia o carga fallida), la
///   disponibilidad lo dice: `recognizerAvailable` es `false` y la sesión no
///   abre el micrófono. La escritura a mano no depende de nada de esto.
///
/// ## Segunda pasada condicional (#166)
///
/// * **Sólo si el teléfono la admite.** [checkAvailability] lee los hechos del
///   aparato (memoria total, poca memoria, fallo de carga) y los decide con
///   [ReviewCapabilityPolicy]. Si no la admite, el turno se pide **sin**
///   revisión —el lado nativo ni siquiera carga el modelo— y la disponibilidad
///   lo dice: `reviewModel` es `null` y `reviewDetail` lleva el motivo.
/// * **Una sola transcripción por frase.** Cada frase numerada se entrega una
///   vez, con el texto de Vosk **o** el de la revisión, nunca los dos ni una
///   mezcla ([chooseReviewedText]). Un segundo resultado de la misma frase se
///   descarta.
/// * **Desacuerdo numérico a la vista.** Si la revisión lee otros valores de
///   cantidad, unidad o moneda, la frase sale con el texto de Vosk y con
///   [TranscriptionSegment.numericDisagreement]; no se calla. Si la revisión
///   no llegó a tiempo (o tras el cierre), no hay desacuerdo que marcar.
/// * **Tope por frase.** Si la revisión de una frase no llega en
///   [reviewTimeout] desde que Vosk la cerró, se entrega el texto de Vosk sin
///   esperar más, y la revisión que llegue después se descarta. Un fallo de la
///   revisión (`review: null`) también deja el texto de Vosk.
/// * **Cancelar descarta** las revisiones pendientes; detener las espera como
///   mucho hasta su tope, y lo que llegue tras el cierre del turno no entra.
///
/// La disciplina de turno es la misma: un turno abierto acaba **siempre** en
/// exactamente un [TranscriptionTurnEnded].
final class LocalSpeechTranscriptionAdapter implements SpeechTranscriptionPort {
  LocalSpeechTranscriptionAdapter({
    MethodChannel? method,
    EventChannel? event,
    ReviewFacts? facts,
    ReviewCapabilityPolicy capabilityPolicy = const ReviewCapabilityPolicy(),
    this.reviewTimeout = defaultReviewTimeout,
  }) : _method = method ?? const MethodChannel(methodChannelName),
       _event = event ?? const EventChannel(eventChannelName),
       _facts = facts,
       _capabilityPolicy = capabilityPolicy {
    _lease = NativeEventHub.attach(
      _event,
      onEvent: _onNativeEvent,
      onError: (Object error) => _failTurn(
        TranscriptionErrorCode.engineFailure,
        error.runtimeType.toString(),
      ),
    );
    // Copia, verifica y carga el modelo mientras el usuario lee la pantalla:
    // el primer «Hablar» no espera. No abre el micrófono.
    _preparing = _prepare();
  }

  static const methodChannelName = 'agro.voice/local';
  static const eventChannelName = 'agro.voice/local_events';

  /// Margen para que el motor entregue lo pendiente tras pedir detener.
  static const stopGrace = Duration(seconds: 15);

  /// Tope por defecto de la revisión de una frase, desde que Vosk la cerró.
  ///
  /// Es el p95 que #12 exige al final de Whisper small en frases de hasta
  /// 20 s (≤ 5 000 ms): una revisión más lenta que eso ya no cumple el umbral
  /// que habilita la segunda pasada, y esperar más sólo retrasaría el borrador.
  static const defaultReviewTimeout = Duration(milliseconds: 5000);

  /// Tope de la revisión de cada frase. Pasado, queda el texto de Vosk.
  final Duration reviewTimeout;

  final MethodChannel _method;
  final EventChannel _event;

  /// Con qué se comprueba que la revisión no cambia cantidades. Sin ella, la
  /// revisión no se acepta.
  final ReviewFacts? _facts;
  final ReviewCapabilityPolicy _capabilityPolicy;
  late final NativeEventLease _lease;

  /// Si este aparato admite la segunda pasada. Hasta la primera consulta de
  /// disponibilidad, desconocido (y entonces no se usa).
  ReviewCapability _capability = ReviewCapability.unknown;
  bool _capabilityKnown = false;

  /// Frases cerradas por Vosk que esperan su revisión, por número.
  final SplayTreeMap<int, _PendingPhrase> _pending =
      SplayTreeMap<int, _PendingPhrase>();

  /// Frases ya entregadas en este turno: cada número entra una sola vez.
  final Set<int> _delivered = <int>{};

  /// Frases entregadas por tope cuyo resultado nativo aún no llegó. El
  /// parcial nativo todavía las incluye al principio, y se quitan de él para
  /// no mostrarlas dos veces.
  final List<_PendingPhrase> _expiredAwaitingNative = <_PendingPhrase>[];

  /// Último número de turno entregado en este proceso. Compartido entre
  /// instancias: dos pantallas vivas a la vez no pueden repetir número.
  static int _lastGeneration = 0;

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
  late Future<void> _preparing;

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
    } on MissingPluginException {
      _prepareError = 'no-platform';
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
      // Un modelo que el APK declara pero que no se pudo copiar, verificar o
      // cargar no sirve para escuchar: se dice ahora, antes de abrir el
      // micrófono. Se reintenta la preparación en cada consulta, porque una
      // copia interrumpida (sin espacio, por ejemplo) puede salir bien después.
      if (present) {
        await _preparing;
        if (_prepareError != null) {
          _preparing = _prepare();
          await _preparing;
        }
      }
      final usable = present && _prepareError == null;
      final capability = _capabilityPolicy.evaluate(
        ReviewDeviceFacts.fromDescribe(map),
      );
      _capability = capability;
      _capabilityKnown = true;
      // Sólo códigos: ningún dato dictado.
      AppLog.info('voz local: segunda pasada ${capability.reason}');
      final reviewModel = capability.allowed
          ? map['reviewModel'] as String?
          : null;
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
        engineName: map['engineName'] as String? ?? '',
        engineVersion: map['engineVersion'] as String? ?? '',
        reviewModel: usable ? reviewModel : null,
        reviewDetail: usable ? capability.reason : null,
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
    final generation = _generation = ++_lastGeneration;
    _segments = 0;
    _resetPhrases();
    _deadlineHit = false;
    _clock = Stopwatch()..start();
    _turnBudget = request.maxTurnDuration;
    try {
      // Sin consulta previa no se sabe si el aparato admite la revisión: se
      // pregunta ahora, sin emitir nada.
      if (request.review && !_capabilityKnown) await _refreshCapability();
      // Cancelado mientras se consultaba: no se abre nada.
      if (!_turnOpen || _generation != generation) return;
      final reply = await _method.invokeMethod<String>('start', {
        'gen': generation,
        'hints': _hintText(request.hints),
        'review': request.review && _capability.allowed,
        'reviewTimeoutMs': reviewTimeout.inMilliseconds,
      });
      // Habrá diálogo de permiso: se avisa ahora, antes de la pausa que
      // provoca, para que la sesión no la tome por «el usuario se fue».
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
    final wasOpen = _turnOpen;
    // Cerrar aquí invalida el número de sesión: nada de lo que llegue después
    // de este turno entra en la sesión.
    if (wasOpen) {
      _emit(const TranscriptionCancelled());
      _closeTurn(TranscriptionEndReason.cancelled);
    }
    try {
      // Con el número: cancelar este turno no puede cortar el de otra
      // pantalla que ya se abrió (#119).
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
    _disposed = true;
    _deadline?.cancel();
    _stopGuard?.cancel();
    _turnOpen = false;
    await _lease.cancel();
    try {
      await _method.invokeMethod<void>('dispose', {'gen': _generation});
    } on Object {
      // Liberar es best-effort.
    }
    await _events.close();
  }

  // ---------------------------------------------------------------- privado

  Future<void> _refreshCapability() async {
    try {
      final map =
          await _method.invokeMapMethod<String, Object?>('describe') ??
          const <String, Object?>{};
      _capability = _capabilityPolicy.evaluate(
        ReviewDeviceFacts.fromDescribe(map),
      );
      _capabilityKnown = true;
    } on Object {
      // Sin datos, sin revisión: el turno sigue sólo con Vosk.
      _capability = ReviewCapability.unknown;
    }
  }

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
            _emit(
              const TranscriptionStageChanged(TranscriptionStage.listening),
            );
          case 'processing':
            _emit(
              const TranscriptionStageChanged(TranscriptionStage.processing),
            );
        }

      case 'partial':
        final (text, reviewing) = _withoutExpired(
          map['text'] as String? ?? '',
          map['reviewing'] as int? ?? 0,
        );
        _emit(
          TranscriptionPartial(text, elapsed: _elapsed, reviewing: reviewing),
        );

      // Vosk cerró una frase; su revisión, si la hay, viene después. Desde
      // aquí corre el tope de esa frase.
      case 'phrase':
        final seq = map['seq'] as int?;
        if (seq == null ||
            _delivered.contains(seq) ||
            _pending.containsKey(seq)) {
          return;
        }
        final phrase = _PendingPhrase(
          seq,
          map['vosk'] as String? ?? '',
          reviewed: map['review'] as bool? ?? false,
        );
        _pending[seq] = phrase;
        phrase.timer = Timer(reviewTimeout, () => _expireUpTo(seq));

      case 'segment':
        final seq = map['seq'] as int?;
        if (seq != null) {
          _expiredAwaitingNative.removeWhere((p) => p.seq == seq);
          if (_delivered.contains(seq)) {
            // Ya se entregó (por tope, o repetido): una revisión tardía no
            // sustituye ni se suma a lo entregado.
            AppLog.info('voz local: frase $seq resultado tardío descartado');
            return;
          }
          _pending.remove(seq)?.timer?.cancel();
        }
        final choice = chooseReviewedText(
          map['vosk'] as String? ?? '',
          map['review'] as String?,
          facts: _facts,
        );
        // Diagnóstico con códigos y tiempos, nunca con lo dictado.
        AppLog.info(
          'voz local: frase $seq ${choice.verdict.name} '
          'revision=${map['reviewMs']}ms',
        );
        _deliver(
          seq,
          choice.text,
          revised: choice.revised,
          numericDisagreement: choice.numericDisagreement,
        );

      case 'error':
        _failTurn(_codeFrom(map['code'] as String?), map['detail'] as String?);

      case 'ended':
        // El motor siempre entrega sus frases antes de cerrar. Si alguna
        // quedó pendiente, se entrega como la oyó Vosk: lo dicho no se pierde
        // y su revisión se descarta.
        _expireUpTo(null);
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

  /// Entrega una frase una sola vez. La marca de desacuerdo numérico viaja
  /// con su frase y con nada más: no hay contador aquí que pueda pasar a otra
  /// frase, a otro turno o a otra pantalla.
  void _deliver(
    int? seq,
    String text, {
    required bool revised,
    bool numericDisagreement = false,
  }) {
    if (seq != null && !_delivered.add(seq)) return;
    if (text.isEmpty) return;
    _segments++;
    _emit(
      TranscriptionSegment(
        text,
        elapsed: _elapsed,
        sequence: seq,
        revised: revised,
        numericDisagreement: numericDisagreement,
      ),
    );
  }

  /// Venció el tope de la frase [last] (o, con `null`, el turno se cierra):
  /// ella y las anteriores pendientes salen con el texto de Vosk, en orden.
  void _expireUpTo(int? last) {
    if (!_turnOpen) return;
    final due = _pending.keys
        .where((seq) => last == null || seq <= last)
        .toList(growable: false);
    for (final seq in due) {
      final phrase = _pending.remove(seq)!;
      phrase.timer?.cancel();
      AppLog.info('voz local: frase $seq ${ReviewVerdict.timedOut.name}');
      _expiredAwaitingNative.add(phrase);
      _deliver(seq, phrase.vosk.trim(), revised: false);
    }
  }

  /// El parcial nativo empieza por las frases que esperan revisión. Las que ya
  /// se entregaron por tope se quitan, para no mostrarlas dos veces.
  (String, int) _withoutExpired(String text, int reviewing) {
    var rest = text;
    var count = reviewing;
    for (final phrase in _expiredAwaitingNative) {
      final vosk = phrase.vosk.trim();
      if (vosk.isEmpty) continue;
      if (rest == vosk) {
        rest = '';
      } else if (rest.startsWith('$vosk ')) {
        rest = rest.substring(vosk.length + 1);
      } else {
        break;
      }
      if (phrase.reviewed && count > 0) count--;
    }
    return (rest, count);
  }

  void _resetPhrases() {
    for (final phrase in _pending.values) {
      phrase.timer?.cancel();
    }
    _pending.clear();
    _delivered.clear();
    _expiredAwaitingNative.clear();
  }

  void _failTurn(TranscriptionErrorCode code, String? detail) {
    // Sin turno abierto no hay a quién atribuir el fallo: un error suelto
    // quedaría pendiente en la sesión y haría fallar el turno siguiente.
    if (_disposed || !_turnOpen) return;
    _emit(TranscriptionFailed(code, detail: detail));
    unawaited(
      _method
          .invokeMethod<void>('cancel', {'gen': _generation})
          .catchError((_) {}),
    );
    _closeTurn(TranscriptionEndReason.error);
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
    // Cancelar, fallar o cerrar descarta las revisiones pendientes: ningún
    // tope vence ya y ningún resultado de este turno entra después.
    _resetPhrases();
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

/// Una frase que Vosk cerró y espera su revisión. El texto sólo vive en
/// memoria, para entregarlo si la revisión no llega a tiempo.
final class _PendingPhrase {
  _PendingPhrase(this.seq, this.vosk, {required this.reviewed});

  final int seq;
  final String vosk;

  /// El lado nativo la mandó a revisar (cuenta en `reviewing`).
  final bool reviewed;
  Timer? timer;
}
