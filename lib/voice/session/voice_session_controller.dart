import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/app_log.dart';
import '../port/speech_transcription_port.dart';
import 'voice_continuity_policy.dart';
import 'voice_locale_policy.dart';
import 'voice_session_state.dart';

/// Sesión de dictado de `EVO-009`: continuidad, acumulación y edición.
///
/// ## Qué hace y qué no
///
/// Convierte una sucesión de **turnos** del motor —que Android cierra por su
/// cuenta al detectar silencio— en **una sesión** que el usuario controla.
/// Acumula segmentos, mantiene el parcial aparte, recorre la lista de idiomas y
/// decide cuándo dejar de reintentar.
///
/// **No interpreta nada.** No conoce productos, personas, cantidades ni dinero,
/// no importa `AgroRepository` ni SQLite y no puede escribir en el negocio:
/// entregar el texto sólo devuelve un [VoiceSessionText].
/// `test/voice/voice_architecture_guard_test.dart` lo comprueba leyendo los
/// archivos, no confiando en esta nota.
///
/// ## Cómo se combinan la voz y las correcciones a mano
///
/// La regla es **añadir al final, nunca reescribir**:
///
/// * [VoiceSessionSnapshot.committedText] es el texto de sesión y es
///   enteramente del usuario; [editText] lo reemplaza por completo.
/// * Un segmento nuevo se **concatena al final** de lo que haya, sea del motor o
///   escrito a mano.
/// * El parcial vive en [VoiceSessionSnapshot.partialText] y **nunca** toca el
///   texto de sesión hasta que el motor lo confirma como segmento.
///
/// Así, corregir «sinco» por «cinco» y seguir hablando produce
/// «cinco litros de bellator», no «sinco litros de bellator»: lo dictado después
/// se suma, y lo corregido antes se respeta. Es la única regla que no puede
/// perder una corrección, porque el motor jamás reescribe lo ya escrito.
///
/// [undoLastAutoAppend] deshace el último añadido automático, y deja de estar
/// disponible en cuanto el usuario edita: deshacer entonces borraría su propia
/// corrección.
class VoiceSessionController extends ChangeNotifier {
  VoiceSessionController({
    required SpeechTranscriptionPort port,
    VoiceLocalePolicy localePolicy = const VoiceLocalePolicy(),
    VoiceContinuityPolicy continuity = const VoiceContinuityPolicy(),
  }) : _port = port,
       _locales = localePolicy,
       _continuity = continuity {
    _subscription = _port.events.listen(_onEvent);
  }

  final SpeechTranscriptionPort _port;
  final VoiceLocalePolicy _locales;
  final VoiceContinuityPolicy _continuity;

  late final StreamSubscription<TranscriptionEvent> _subscription;

  VoiceSessionSnapshot _snapshot = const VoiceSessionSnapshot(
    requestedLocale: VoiceLocalePolicy.requested,
  );

  /// Fotografía actual. La pantalla no lee ningún otro estado.
  VoiceSessionSnapshot get snapshot => _snapshot;

  /// El usuario mantiene la sesión abierta. Es la condición sin la cual **nunca**
  /// se reabre un turno: cubre a la vez detener, descartar, salir y el fallo
  /// fatal.
  bool _userListening = false;

  bool _disposed = false;
  bool _stopRequested = false;
  bool _turnSegmentConsumed = false;

  int _turnCount = 0;
  int _unproductive = 0;

  List<String> _localeOrder = VoiceLocalePolicy.candidates;
  int _localeIndex = 0;

  /// Candidatos que ya fallaron por idioma en esta sesión y por este
  /// reconocedor. Se agota el camino cuando están **todos**, no cuando se llega
  /// al final de la lista: la sesión puede haber empezado por el medio si ya
  /// había un idioma confirmado.
  final Set<String> _localeExhausted = <String>{};

  /// El usuario ya decidió sobre el servicio del sistema en esta sesión, sea
  /// que lo aceptara o que lo rechazara. Sólo se pregunta una vez
  /// (`DEFECTO-004`).
  bool _routeFallbackDecided = false;

  Timer? _restartTimer;
  Timer? _sessionTimer;

  TranscriptionErrorCode? _pendingErrorCode;
  String? _pendingErrorDetail;

  /// Texto anterior al último añadido automático, para [undoLastAutoAppend].
  String? _undoText;

  // ------------------------------------------------------------------ acciones

  /// Toca el micrófono, o pulsa `Seguir hablando`.
  ///
  /// Pide el permiso en contexto —lo hace el adaptador, que es quien sabe si
  /// hace falta el diálogo— y abre el primer turno. Un segundo toque mientras la
  /// sesión ya está en marcha no hace nada: no puede haber dos capturas.
  Future<void> startListening() async {
    if (_disposed) return;
    if (_snapshot.status.microphoneMayBeOpen || _restartTimer != null) return;

    // El estado cambia ANTES del primer `await`: si esperase a la consulta de
    // disponibilidad, dos toques seguidos abrirían dos sesiones.
    _userListening = true;
    _stopRequested = false;
    _unproductive = 0;
    _update(
      _snapshot.copyWith(
        status: VoiceSessionStatus.starting,
        partialText: '',
        clearError: true,
        clearDelivered: true,
      ),
    );

    final availability = await _readAvailability();
    if (_disposed || !_userListening) return;

    if (!availability.recognizerAvailable) {
      _fail(
        VoiceSessionStatus.recognizerUnavailable,
        TranscriptionErrorCode.recognizerUnavailable,
        availability.detail,
      );
      return;
    }

    _localeOrder = _locales.attemptOrder(availability);
    // Un locale ya confirmado no se vuelve a buscar: repetir el recorrido en
    // cada `Seguir hablando` gastaría un turno por candidato fallido.
    final confirmed = _snapshot.localeInUse;
    final index = confirmed == null ? -1 : _localeOrder.indexOf(confirmed);
    _localeIndex = index < 0 ? (_nextLocaleIndex() ?? 0) : index;

    _turnCount = 0;
    _update(
      _snapshot.copyWith(
        localeAttempt: _localeProgress,
        localeCandidates: _localeOrder.length,
      ),
    );
    _sessionTimer?.cancel();
    _sessionTimer = Timer(_continuity.maxSessionDuration, () {
      // Última red: ni siquiera una sesión productiva puede quedarse escuchando
      // indefinidamente.
      AppLog.info('voz: sesión cerrada por duración máxima');
      _stopContinuity();
      unawaited(_releaseMicrophone());
      _settleToPreview();
    });

    await _openTurn();
  }

  /// Pulsa `Detener`. El texto se conserva y el micrófono se libera.
  Future<void> stopListening() async {
    if (_disposed) return;
    _stopContinuity();
    if (!_port.isTurnOpen) {
      _settleToPreview();
      return;
    }
    _stopRequested = true;
    _update(_snapshot.copyWith(status: VoiceSessionStatus.stopping));
    await _port.stop();
  }

  /// Pulsa `Reintentar` tras un error recuperable.
  ///
  /// Conserva el texto acumulado: un fallo del motor no es motivo para perder lo
  /// que el usuario ya dictó.
  Future<void> retry() async {
    if (_disposed) return;
    _unproductive = 0;
    // Reintentar es una petición explícita: se vuelve a recorrer la lista de
    // idiomas. Lo que NO se rehace es preguntar por el reconocedor del sistema,
    // que ya se decidió una vez en esta sesión.
    _localeExhausted.clear();
    _update(_snapshot.copyWith(clearError: true));
    await startListening();
  }

  /// Pulsa `Descartar`. Borra el texto de sesión y libera el micrófono.
  ///
  /// `EVO-009-REQ-003`. No queda audio —nunca lo hubo en Dart—, ni transcripción
  /// ni resultado entregado.
  Future<void> discard() async {
    if (_disposed) return;
    _stopContinuity();
    await _releaseMicrophone();
    _turnCount = 0;
    _undoText = null;
    _localeExhausted.clear();
    // La autorización para usar el servicio del sistema valía **para esta
    // sesión**. No se guarda en ningún sitio y no sobrevive a descartar
    // (`DEFECTO-004`).
    _routeFallbackDecided = false;
    AppLog.info('voz: sesión descartada por el usuario');
    _update(
      VoiceSessionSnapshot(
        status: VoiceSessionStatus.cancelled,
        requestedLocale: VoiceLocalePolicy.requested,
        // El idioma y la disponibilidad son hechos del aparato, no contenido de
        // la sesión: conservarlos evita volver a recorrer la lista de idiomas.
        // Salvo que se hubiera cambiado de reconocedor: un idioma confirmado
        // por el servicio del sistema no dice nada del reconocedor local, con
        // el que la siguiente sesión vuelve a empezar.
        localeInUse: _snapshot.routeFallbackUsed ? null : _snapshot.localeInUse,
        offline: _snapshot.offline,
        availability: _snapshot.availability,
      ),
    );
  }

  /// Pulsa `Usar servicio del teléfono` en la confirmación de `DEFECTO-004`.
  ///
  /// Es la **única** transición permitida, y sólo con el sí explícito del
  /// usuario: el reconocedor local se destruye, se crea el predeterminado del
  /// teléfono y se le sigue pidiendo trabajar sin conexión. No se vuelve
  /// automáticamente al local, no se pregunta dos veces y no se guarda la
  /// autorización en ningún sitio.
  Future<void> useSystemRecognizer() async {
    if (_disposed) return;
    if (!_snapshot.routeFallbackOffered) return;
    _routeFallbackDecided = true;
    _localeExhausted.clear();
    _localeIndex = 0;
    // Se suelta antes de crear el otro: dos reconocedores vivos se pelearían
    // por el micrófono.
    await _releaseMicrophone();
    AppLog.info('voz: el usuario autorizó el reconocedor del sistema');
    _update(
      _snapshot.copyWith(
        route: TranscriptionEngineRoute.systemDefault,
        clearObservedRoute: true,
        routeFallbackOffered: false,
        routeFallbackUsed: true,
        clearLocaleInUse: true,
        clearError: true,
      ),
    );
    await startListening();
  }

  /// Pulsa `Continuar escribiendo` en la confirmación de `DEFECTO-004`.
  ///
  /// No cambia de reconocedor, conserva el texto y suelta el micrófono. La
  /// pantalla sigue permitiendo escribir a mano, que es lo que `EVO-009-REQ-017`
  /// exige que nunca se pierda.
  Future<void> declineSystemRecognizer() async {
    if (_disposed) return;
    if (!_snapshot.routeFallbackOffered) return;
    _routeFallbackDecided = true;
    _stopContinuity();
    await _releaseMicrophone();
    AppLog.info('voz: el usuario prefirió seguir escribiendo a mano');
    _update(
      _snapshot.copyWith(
        status: VoiceSessionStatus.languageUnavailable,
        routeFallbackOffered: false,
      ),
    );
  }

  /// Reemplaza el texto de sesión con lo que el usuario escribió.
  ///
  /// Todo el texto es editable, incluido lo que produjo el motor
  /// (`EVO-009-REQ-001`).
  void editText(String text) {
    if (_disposed) return;
    if (text == _snapshot.committedText) return;
    _undoText = null;
    _update(
      _snapshot.copyWith(
        committedText: text,
        manuallyEdited: true,
        canUndoAutoAppend: false,
        clearDelivered: true,
      ),
    );
  }

  /// Deshace el último añadido automático del motor.
  ///
  /// Sólo actúa inmediatamente después de ese añadido. Si el usuario ya editó,
  /// no hace nada: deshacer borraría su corrección.
  void undoLastAutoAppend() {
    if (_disposed) return;
    final previous = _undoText;
    if (!_snapshot.canUndoAutoAppend || previous == null) return;
    _undoText = null;
    _update(
      _snapshot.copyWith(
        committedText: previous,
        segmentCount: _snapshot.segmentCount > 0
            ? _snapshot.segmentCount - 1
            : 0,
        canUndoAutoAppend: false,
      ),
    );
  }

  /// Pulsa `Usar este texto`.
  ///
  /// **Entrega texto y nada más.** No interpreta intención, no resuelve
  /// productos ni personas, no toca SQLite y no ejecuta ninguna operación
  /// agrícola o contable (`EVO-009-REQ-002`). El consumidor tipado es `EVO-010`
  /// y todavía no existe.
  VoiceSessionText? deliver() {
    if (_disposed) return null;
    final text = _snapshot.committedText.trim();
    if (text.isEmpty) return null;

    _stopContinuity();
    unawaited(_releaseMicrophone());

    final result = VoiceSessionText(
      text,
      segments: _snapshot.segmentCount,
      edited: _snapshot.manuallyEdited,
    );
    AppLog.info('voz: texto de sesión entregado (chars=${text.length})');
    _update(
      _snapshot.copyWith(
        status: VoiceSessionStatus.preview,
        partialText: '',
        delivered: result,
      ),
    );
    return result;
  }

  /// La aplicación pasó a segundo plano, se bloqueó la pantalla o hubo una
  /// interrupción.
  ///
  /// Suelta el micrófono **siempre** y detiene la continuidad
  /// (`EVO-009-REQ-005`). No borra el texto: perder lo dictado por atender una
  /// llamada sería un castigo, no una medida de seguridad.
  Future<void> handleAppPaused() async {
    if (_disposed) return;
    // El diálogo de permisos del sistema pone la aplicación en segundo plano.
    // Tratar eso como «el usuario se fue» cancelaba la sesión justo antes de que
    // concediera el permiso, y el micrófono no llegaba a abrirse nunca: había
    // que tocar el micrófono una segunda vez. Medido en el HONOR JDY-LX3P.
    //
    // Es seguro no soltar nada aquí: en este estado el motor todavía no ha
    // arrancado, así que no hay micrófono tomado que liberar.
    if (_snapshot.status == VoiceSessionStatus.requestingPermission) return;
    if (!_userListening && !_snapshot.status.microphoneMayBeOpen) return;
    _stopContinuity();
    await _releaseMicrophone();
    AppLog.info('voz: micrófono liberado al pasar a segundo plano');
    _settleToPreview();
  }

  /// Abre los ajustes del sistema para revertir una denegación permanente.
  Future<bool> openSystemSettings() => _port.openSystemSettings();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _restartTimer?.cancel();
    _sessionTimer?.cancel();
    _userListening = false;
    unawaited(_subscription.cancel());
    // Salir de la pantalla no puede dejar un reconocedor vivo.
    unawaited(_port.cancel());
    unawaited(_port.dispose());
    super.dispose();
  }

  // -------------------------------------------------------------------- turnos

  Future<TranscriptionAvailability> _readAvailability() async {
    try {
      final availability = await _port.checkAvailability(
        VoiceLocalePolicy.requested,
      );
      _applyAvailability(availability);
      return availability;
    } on Object catch (error) {
      // Que la consulta falle no significa que el motor no sirva, pero sí que no
      // se sabe nada: se sigue adelante e intenta transcribir, que es lo que
      // `EVO-009-REQ-014` pide en lugar de creerle a la API.
      AppLog.warning(
        'voz: consulta de disponibilidad fallida (${error.runtimeType})',
      );
      return const TranscriptionAvailability(
        recognizerAvailable: true,
        onDeviceApiReports: false,
        localeSupportKnown: false,
        detail: 'availability-query-failed',
      );
    }
  }

  void _applyAvailability(TranscriptionAvailability availability) {
    _update(
      _snapshot.copyWith(
        availability: availability,
        offline: _snapshot.offline.copyWith(
          availabilityKnown: availability.localeSupportKnown,
          onDeviceApiReports: availability.onDeviceApiReports,
          airplaneMode: availability.airplaneMode,
        ),
      ),
    );
  }

  Future<void> _openTurn() async {
    if (_disposed || !_userListening) return;
    if (_turnCount >= _continuity.maxTurns) {
      AppLog.info('voz: alcanzado el máximo de turnos de la sesión');
      _stopContinuity();
      _settleToPreview();
      return;
    }
    _turnCount++;
    _turnSegmentConsumed = false;
    _update(_snapshot.copyWith(status: VoiceSessionStatus.starting));
    await _port.start(
      TranscriptionRequest(
        locale: _localeOrder[_localeIndex],
        // Se sigue pidiendo trabajar sin conexión también por el servicio del
        // sistema. Es una preferencia, no una garantía, y la pantalla lo dice.
        preferOffline: true,
        partialResults: true,
        maxTurnDuration: _continuity.turnDuration,
        route: _snapshot.route,
      ),
    );
  }

  void _scheduleRestart(Duration delay) {
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      _restartTimer = null;
      if (_disposed || !_userListening) return;
      unawaited(_openTurn());
    });
  }

  // -------------------------------------------------------------------- eventos

  void _onEvent(TranscriptionEvent event) {
    if (_disposed) return;
    switch (event) {
      case TranscriptionAvailabilityObserved(:final availability):
        _applyAvailability(availability);

      case TranscriptionStageChanged(:final stage):
        _onStage(stage);

      case TranscriptionLocaleInUse(:final locale):
        _update(_snapshot.copyWith(localeInUse: locale));

      case TranscriptionRouteInUse(:final route):
        // Lo que el motor está usando de verdad, que puede no ser lo pedido.
        _update(_snapshot.copyWith(observedRoute: route));

      case TranscriptionPartial(:final text):
        if (!_snapshot.status.microphoneMayBeOpen) return;
        _noteOfflineEvidence(text);
        _update(_snapshot.copyWith(partialText: text));

      case TranscriptionSegment(:final text):
        _appendSegment(text);

      case TranscriptionFailed(:final code, :final detail):
        _pendingErrorCode = code;
        _pendingErrorDetail = detail;

      case TranscriptionTurnEnded(:final reason):
        _onTurnEnded(reason);

      // Sin efecto propio: el motivo llega con el cierre del turno y allí se
      // decide. Tenerlos como eventos permite que la pantalla y las pruebas
      // distingan silencio de fallo sin leer texto libre.
      case TranscriptionNoMatch():
      case TranscriptionTimeout():
      case TranscriptionCancelled():
        return;
    }
  }

  void _onStage(TranscriptionStage stage) {
    // Un evento tardío del motor no puede reencender el indicador de micrófono
    // de una sesión ya detenida, descartada o fallida.
    if (!_userListening && !_snapshot.status.microphoneMayBeOpen) return;
    if (_stopRequested && stage != TranscriptionStage.awaitingPermission)
      return;
    _update(
      _snapshot.copyWith(
        status: switch (stage) {
          TranscriptionStage.awaitingPermission =>
            VoiceSessionStatus.requestingPermission,
          TranscriptionStage.listening => VoiceSessionStatus.listening,
          TranscriptionStage.processing => VoiceSessionStatus.processing,
        },
      ),
    );
  }

  void _appendSegment(String text) {
    // Android puede repetir el resultado de un turno ya cerrado. Un segundo
    // segmento del mismo turno duplicaría la frase en el texto de sesión.
    if (_turnSegmentConsumed) return;
    _turnSegmentConsumed = true;

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _update(_snapshot.copyWith(partialText: ''));
      return;
    }
    _noteOfflineEvidence(trimmed);

    final base = _snapshot.committedText.trimRight();
    _undoText = _snapshot.committedText;
    _update(
      _snapshot.copyWith(
        committedText: base.isEmpty ? trimmed : '$base $trimmed',
        partialText: '',
        segmentCount: _snapshot.segmentCount + 1,
        canUndoAutoAppend: true,
        clearDelivered: true,
      ),
    );
  }

  /// Transcribir con las radios apagadas es la **única** prueba de que aquí
  /// funciona sin red.
  ///
  /// `ADR-002` midió `isOnDeviceRecognitionAvailable()` devolviendo `false` en
  /// un teléfono donde el offline sí funcionaba, así que la evidencia se anota
  /// al recibir texto, no al preguntar.
  void _noteOfflineEvidence(String text) {
    if (text.trim().isEmpty) return;
    if (_snapshot.offline.airplaneMode != AirplaneMode.on) return;
    if (_snapshot.offline.observedOffline) return;
    _update(
      _snapshot.copyWith(
        offline: _snapshot.offline.copyWith(observedOffline: true),
      ),
    );
  }

  void _onTurnEnded(TranscriptionEndReason reason) {
    final code = _pendingErrorCode;
    final detail = _pendingErrorDetail;
    _pendingErrorCode = null;
    _pendingErrorDetail = null;

    _update(_snapshot.copyWith(partialText: '', lastEndReason: reason));

    // Descartar y segundo plano fijan su propio estado; el cierre que provocan
    // no debe reabrir nada ni pisarlo.
    if (reason == TranscriptionEndReason.cancelled) return;

    if (_stopRequested) {
      _stopRequested = false;
      _userListening = false;
      _settleToPreview();
      return;
    }

    if (code != null) {
      _onTurnFailed(code, detail);
      return;
    }

    if (!_userListening) {
      _settleToPreview();
      return;
    }

    if (reason == TranscriptionEndReason.segment) {
      // Turno productivo: se reabre de inmediato, sin espera. Retrasar aquí
      // cortaría al usuario justo cuando el motor está funcionando.
      _unproductive = 0;
      _scheduleRestart(Duration.zero);
      return;
    }

    // `noMatch` y `timeout`: el usuario calló, o el motor no oyó nada.
    _unproductive++;
    if (_unproductive >= _continuity.maxConsecutiveUnproductive) {
      AppLog.info(
        'voz: continuidad detenida tras $_unproductive turnos sin texto',
      );
      _stopContinuity();
      _settleToPreview();
      return;
    }
    _scheduleRestart(_continuity.backoffFor(_unproductive));
  }

  void _onTurnFailed(TranscriptionErrorCode code, String? detail) {
    // El diagnóstico lleva códigos, nunca lo dictado (`RISK-014`).
    AppLog.warning('voz: turno fallido code=${code.name} detail=$detail');

    if (_locales.advancesLocale(code)) {
      _update(
        _snapshot.copyWith(
          // El motor puede anunciar «listo para escuchar» y fallar a
          // continuación: el HONOR lo hizo con `es-MX`. Si no se limpiara aquí,
          // la pantalla diría «Sin español disponible» y «Se está escuchando en
          // es-MX» a la vez.
          clearLocaleInUse: true,
          offline: _snapshot.offline.copyWith(
            languageModelPossiblyMissing: true,
          ),
        ),
      );
      _localeExhausted.add(_localeOrder[_localeIndex]);
      _update(_snapshot.copyWith(localeAttempt: _localeProgress));

      final next = _nextLocaleIndex();
      if (next != null && _userListening) {
        // Intentar y observar: la lista de idiomas del sistema no decide
        // (`EVO-009-REQ-014`). No cuenta como turno improductivo, porque el
        // presupuesto de esta búsqueda es la longitud de la lista.
        _turnCount--;
        _localeIndex = next;
        unawaited(_openTurn());
        return;
      }
      _onLocalesExhausted(code, detail);
      return;
    }

    if (code.isFatal) {
      _fail(_statusForFatal(code), code, detail);
      return;
    }

    _unproductive++;
    if (_unproductive >= _continuity.maxConsecutiveUnproductive ||
        !_userListening) {
      _fail(VoiceSessionStatus.recoverableError, code, detail);
      return;
    }
    _scheduleRestart(_continuity.backoffFor(_unproductive));
  }

  /// Qué hacer cuando ningún español funcionó por el reconocedor actual.
  ///
  /// `DEFECTO-004`: el HONOR JDY-LX3P tiene reconocedor local sin ningún
  /// español y se quedaba aquí, sin salida, aunque el servicio del sistema —el
  /// que funcionó en el aparato de `ADR-002`— estuviera disponible. Ahora se
  /// ofrece, pero **se pregunta**: ese servicio puede transcribir usando
  /// Internet y esa decisión es del dueño del teléfono.
  ///
  /// No se ofrece nada si ya se está en el servicio del sistema, si el motor ya
  /// estaba usándolo —el caso de API 31, donde no hay a dónde cambiar— o si el
  /// usuario ya decidió en esta sesión.
  void _onLocalesExhausted(TranscriptionErrorCode code, String? detail) {
    final canOffer =
        _snapshot.route == TranscriptionEngineRoute.onDevice &&
        _snapshot.observedRoute == TranscriptionEngineRoute.onDevice &&
        !_routeFallbackDecided;
    if (!canOffer) {
      _fail(VoiceSessionStatus.languageUnavailable, code, detail);
      return;
    }
    AppLog.info(
      'voz: sin español por el reconocedor local; se ofrece el del sistema',
    );
    _stopContinuity();
    _update(
      _snapshot.copyWith(
        status: VoiceSessionStatus.languageUnavailable,
        partialText: '',
        errorCode: code,
        errorDetail: detail,
        routeFallbackOffered: true,
      ),
    );
  }

  /// El siguiente candidato sin agotar, o `null` si no queda ninguno.
  ///
  /// Recorre la lista entera y no sólo lo que quede por delante: una sesión que
  /// empezó por un idioma ya confirmado dejaría atrás candidatos sin probar, y
  /// entonces «se agotaron todos» sería falso.
  int? _nextLocaleIndex() {
    for (var i = 0; i < _localeOrder.length; i++) {
      if (!_localeExhausted.contains(_localeOrder[i])) return i;
    }
    return null;
  }

  /// Por qué candidato va el recorrido, para mostrarlo. Nunca pasa del total.
  int get _localeProgress {
    final total = _localeOrder.length;
    final next = _localeExhausted.length + 1;
    return total == 0 ? next : (next > total ? total : next);
  }

  VoiceSessionStatus _statusForFatal(TranscriptionErrorCode code) =>
      switch (code) {
        TranscriptionErrorCode.permissionDenied =>
          VoiceSessionStatus.permissionDenied,
        TranscriptionErrorCode.permissionPermanentlyDenied =>
          VoiceSessionStatus.permissionPermanentlyDenied,
        TranscriptionErrorCode.recognizerUnavailable =>
          VoiceSessionStatus.recognizerUnavailable,
        TranscriptionErrorCode.localeUnavailable =>
          VoiceSessionStatus.languageUnavailable,
        _ => VoiceSessionStatus.fatalError,
      };

  void _fail(
    VoiceSessionStatus status,
    TranscriptionErrorCode code,
    String? detail,
  ) {
    _stopContinuity();
    _update(
      _snapshot.copyWith(
        status: status,
        partialText: '',
        errorCode: code,
        errorDetail: detail,
      ),
    );
  }

  // ------------------------------------------------------------------ utilidad

  /// Deja de reabrir turnos. No toca el texto ni el estado visible.
  void _stopContinuity() {
    _userListening = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  Future<void> _releaseMicrophone() async {
    _stopRequested = false;
    await _port.cancel();
  }

  /// Cierra la sesión dejando el texto editable y el micrófono libre.
  void _settleToPreview() {
    if (_snapshot.status.isProblem ||
        _snapshot.status == VoiceSessionStatus.cancelled) {
      return;
    }
    _update(
      _snapshot.copyWith(status: VoiceSessionStatus.preview, partialText: ''),
    );
  }

  void _update(VoiceSessionSnapshot next) {
    if (_disposed) return;
    _snapshot = next;
    notifyListeners();
  }
}
