import '../port/speech_transcription_port.dart';

/// Estados de una sesión de dictado de `EVO-009`.
///
/// La lista es **cerrada y excluyente**: en todo momento la sesión está en uno y
/// sólo uno. No existe ningún par de banderas que pueda contradecirla —no hay
/// `isListening` junto a `hasError`—, porque el defecto clásico de una pantalla
/// de micrófono es quedarse con el indicador encendido y el motor apagado.
///
/// Refina la tabla de `EVO-009_SAFE_VOICE_SPEC.md` § Estados mínimos separando
/// lo que la interfaz debe tratar distinto:
///
/// | Spec | Aquí |
/// |---|---|
/// | `denied` | [permissionDenied] y [permissionPermanentlyDenied] |
/// | `unavailable` | [languageUnavailable] y [recognizerUnavailable] |
/// | `error` | [recoverableError] y [fatalError] |
/// | — | [starting] y [stopping], las transiciones donde se deshabilitan botones |
///
/// `ready` de la spec no tiene estado propio: entregar el texto no cambia el
/// modo de la sesión, deja un [VoiceSessionSnapshot.delivered]. Un estado
/// terminal habría obligado a salir de él para seguir editando, que es
/// justamente lo que `EVO-009-REQ-001` quiere permitir.
enum VoiceSessionStatus {
  /// Sin sesión. El micrófono está libre.
  idle,

  /// Esperando la respuesta del sistema al permiso de micrófono.
  requestingPermission,

  /// Permiso concedido; abriendo el turno en el motor. Nada se oye todavía.
  starting,

  /// El motor escucha. Es el único estado en que el micrófono está tomado.
  listening,

  /// Terminó el habla; el motor produce el resultado final del turno.
  processing,

  /// Hay texto de sesión editable y el micrófono está libre.
  preview,

  /// El usuario pidió detener y aún no llegó el cierre del motor.
  stopping,

  /// La sesión se descartó: no queda texto ni micrófono tomado.
  cancelled,

  /// El usuario negó el micrófono esta vez. Se puede volver a pedir.
  permissionDenied,

  /// Denegación permanente: sólo los ajustes del sistema lo revierten.
  permissionPermanentlyDenied,

  /// Ningún español de la lista de fallback resultó utilizable.
  languageUnavailable,

  /// No hay servicio de reconocimiento en el aparato.
  recognizerUnavailable,

  /// Fallo del que se puede volver reintentando, sin perder el texto.
  recoverableError,

  /// Fallo que no mejora reintentando. El texto acumulado se conserva.
  fatalError;

  /// `true` si el micrófono puede estar tomado ahora mismo.
  ///
  /// Lo usan el indicador visible y las guardas de ciclo de vida. Deriva del
  /// estado en vez de ser un campo propio, que es como se desincronizaría.
  bool get microphoneMayBeOpen => switch (this) {
    VoiceSessionStatus.starting ||
    VoiceSessionStatus.listening ||
    VoiceSessionStatus.processing ||
    VoiceSessionStatus.stopping => true,
    _ => false,
  };

  /// `true` mientras la sesión está en una transición y no acepta acciones.
  ///
  /// Es lo que impide la doble acción: los botones se deshabilitan aquí, no con
  /// un booleano aparte que pudiera quedar colgado.
  bool get isTransition => switch (this) {
    VoiceSessionStatus.requestingPermission ||
    VoiceSessionStatus.starting ||
    VoiceSessionStatus.stopping => true,
    _ => false,
  };

  /// `true` si la sesión terminó por un problema.
  bool get isProblem => switch (this) {
    VoiceSessionStatus.permissionDenied ||
    VoiceSessionStatus.permissionPermanentlyDenied ||
    VoiceSessionStatus.languageUnavailable ||
    VoiceSessionStatus.recognizerUnavailable ||
    VoiceSessionStatus.recoverableError ||
    VoiceSessionStatus.fatalError => true,
    _ => false,
  };
}

/// Qué se sabe —y qué no— sobre el funcionamiento sin red.
///
/// Existe porque `EVO-009-REQ-008` y `ADR-002` prohíben afirmar "funciona
/// offline" a partir de una API que devolvió `false` en un aparato donde el
/// offline sí funcionaba. Los cinco datos son **distintos** y la interfaz los
/// muestra por separado en lugar de resumirlos en un sí/no que sería mentira en
/// alguno de los casos.
final class VoiceOfflineEvidence {
  const VoiceOfflineEvidence({
    this.offlineRequested = true,
    this.airplaneMode = AirplaneMode.unknown,
    this.observedOffline = false,
    this.availabilityKnown = false,
    this.onDeviceApiReports = false,
    this.languageModelPossiblyMissing = false,
  });

  /// Se pidió al motor no usar red. Es una **preferencia**, no un resultado.
  final bool offlineRequested;

  /// Modo avión según el sistema, no según quien prueba.
  final AirplaneMode airplaneMode;

  /// Se transcribió de verdad con el modo avión activo.
  ///
  /// Es la **única** evidencia que permite decir que aquí funciona sin red, y se
  /// obtiene transcribiendo, no preguntando.
  final bool observedOffline;

  /// El sistema dejó consultar los idiomas instalados
  /// (`checkRecognitionSupport`, API 33+). En API 31 es `false` y eso significa
  /// "no se sabe", no "no hay".
  final bool availabilityKnown;

  /// Valor crudo de `isOnDeviceRecognitionAvailable()`. Se muestra como dato del
  /// sistema, nunca como promesa.
  final bool onDeviceApiReports;

  /// Se recibió `LANGUAGE_UNAVAILABLE`: el idioma existe pero puede faltar el
  /// modelo descargado. No se descarga nada en silencio; se informa.
  final bool languageModelPossiblyMissing;

  VoiceOfflineEvidence copyWith({
    bool? offlineRequested,
    AirplaneMode? airplaneMode,
    bool? observedOffline,
    bool? availabilityKnown,
    bool? onDeviceApiReports,
    bool? languageModelPossiblyMissing,
  }) => VoiceOfflineEvidence(
    offlineRequested: offlineRequested ?? this.offlineRequested,
    airplaneMode: airplaneMode ?? this.airplaneMode,
    observedOffline: observedOffline ?? this.observedOffline,
    availabilityKnown: availabilityKnown ?? this.availabilityKnown,
    onDeviceApiReports: onDeviceApiReports ?? this.onDeviceApiReports,
    languageModelPossiblyMissing:
        languageModelPossiblyMissing ?? this.languageModelPossiblyMissing,
  );
}

/// El texto que la sesión entrega al pulsar `Usar este texto`.
///
/// Es **sólo texto**. No lleva intención, entidades, importes ni referencias a
/// catálogo, porque nada de eso existe en `EVO-009`: interpretarlo es `EVO-010`
/// y ocurre detrás de otra frontera (`ADR-003`). Entregarlo no ejecuta ninguna
/// operación agrícola ni contable.
final class VoiceSessionText {
  const VoiceSessionText(
    this.text, {
    required this.segments,
    this.edited = false,
  });

  /// El contenido final, tal como quedó tras las ediciones del usuario.
  final String text;

  /// Cuántos segmentos del motor participaron. Métrica, no contenido.
  final int segments;

  /// El usuario modificó a mano lo que el motor produjo.
  final bool edited;

  @override
  String toString() =>
      'VoiceSessionText(chars=${text.length}, segments=$segments, '
      'edited=$edited)';
}

/// Fotografía completa e inmutable de la sesión.
///
/// La pantalla se dibuja **sólo** desde aquí: no consulta el puerto ni mantiene
/// estado propio salvo el controlador del campo de texto.
final class VoiceSessionSnapshot {
  const VoiceSessionSnapshot({
    this.status = VoiceSessionStatus.idle,
    this.committedText = '',
    this.partialText = '',
    this.segmentCount = 0,
    this.manuallyEdited = false,
    this.requestedLocale = '',
    this.localeInUse,
    this.localeAttempt = 0,
    this.localeCandidates = 0,
    this.route = TranscriptionEngineRoute.onDevice,
    this.observedRoute,
    this.routeFallbackOffered = false,
    this.routeFallbackUsed = false,
    this.offline = const VoiceOfflineEvidence(),
    this.errorCode,
    this.errorDetail,
    this.lastEndReason,
    this.canUndoAutoAppend = false,
    this.delivered,
    this.availability,
  });

  final VoiceSessionStatus status;

  /// Texto de sesión: segmentos finales acumulados **más** las ediciones a mano.
  ///
  /// Es la única fuente del campo editable. El parcial nunca entra aquí hasta
  /// que el motor lo confirma como segmento.
  final String committedText;

  /// Texto provisional del turno en curso, siempre **separado** de
  /// [committedText] para que una corrección manual no compita con un parcial
  /// que aún puede cambiar por completo.
  final String partialText;

  /// Cuántos segmentos finales se han acumulado.
  final int segmentCount;

  /// El usuario escribió o corrigió a mano.
  final bool manuallyEdited;

  /// El locale que se pidió (`es-BO`). Se muestra siempre junto a [localeInUse].
  final String requestedLocale;

  /// El locale que el motor aceptó **y que no falló después**.
  ///
  /// `null` mientras no lo haya aceptado ninguno. Se limpia si el idioma que se
  /// estaba anunciando termina fallando: el HONOR JDY-LX3P emitió «listo para
  /// escuchar» en `es-MX` y acto seguido devolvió el error 12, y la pantalla
  /// llegó a decir «Sin español disponible» y «Se está escuchando en es-MX» a la
  /// vez. Anunciar un idioma que no funciona es exactamente lo que prohíbe
  /// `EVO-009-REQ-015`.
  final String? localeInUse;

  /// Cuántos candidatos de español se han intentado en esta sesión.
  ///
  /// Existe porque el recorrido puede ser largo: en el HONOR tardó 17,6 s en
  /// agotar los diez, y sin esto la pantalla parecía colgada.
  final int localeAttempt;

  /// Cuántos candidatos tiene la lista. Cero antes de empezar.
  final int localeCandidates;

  /// El reconocedor que la sesión está pidiendo.
  ///
  /// Empieza siempre en [TranscriptionEngineRoute.onDevice] y sólo pasa a
  /// [TranscriptionEngineRoute.systemDefault] si el usuario lo autoriza. La
  /// autorización vale para **esta** sesión: descartar vuelve a empezar por el
  /// reconocedor local (`DEFECTO-004`).
  final TranscriptionEngineRoute route;

  /// El reconocedor que el motor dijo estar usando. `null` mientras no lo diga.
  ///
  /// Puede no coincidir con [route]: en API 31 se pide el local y el sistema
  /// entrega el predeterminado. La pantalla muestra **éste**, porque es el que
  /// describe por dónde pasa el audio.
  final TranscriptionEngineRoute? observedRoute;

  /// Hay una confirmación en pantalla para pasar al servicio del sistema.
  ///
  /// Se ofrece **sólo** al agotar los idiomas por el reconocedor local, nunca
  /// ante un silencio, un permiso denegado o un fallo transitorio: cambiar de
  /// reconocedor puede llevar el audio a un servicio que use Internet, y eso lo
  /// decide el dueño del teléfono.
  final bool routeFallbackOffered;

  /// Ya se hizo la única transición permitida en esta sesión.
  ///
  /// Impide preguntar dos veces y, sobre todo, impide alternar entre
  /// reconocedores en bucle.
  final bool routeFallbackUsed;

  final VoiceOfflineEvidence offline;

  /// Código del último fallo. La interfaz decide el mensaje a partir de él, no
  /// de texto libre del motor.
  final TranscriptionErrorCode? errorCode;

  /// Diagnóstico técnico del fallo. Nunca contenido dictado.
  final String? errorDetail;

  /// Cómo terminó el último turno.
  final TranscriptionEndReason? lastEndReason;

  /// Se puede deshacer el último añadido automático.
  ///
  /// Sólo es `true` inmediatamente después de que un segmento se sumara al
  /// texto, y deja de serlo en cuanto el usuario edita: deshacer entonces
  /// borraría una corrección suya, que es lo contrario de lo que pide.
  final bool canUndoAutoAppend;

  /// Resultado ya entregado, si el usuario pulsó `Usar este texto`.
  final VoiceSessionText? delivered;

  /// Última disponibilidad observada. `null` si aún no se consultó.
  final TranscriptionAvailability? availability;

  /// El locale mostrado difiere del pedido.
  bool get localeIsFallback =>
      localeInUse != null && localeInUse != requestedLocale;

  /// Hay algo que entregar o editar.
  bool get hasText => committedText.trim().isNotEmpty;

  /// Se está recorriendo la lista de idiomas y aún no hay uno que funcione.
  bool get isSearchingLocale =>
      localeInUse == null && localeAttempt > 1 && status.microphoneMayBeOpen;

  /// Texto que la pantalla muestra como "lo que se lleva", parcial incluido.
  ///
  /// Sólo para mostrar: lo que se entrega es [committedText].
  String get displayText => partialText.isEmpty
      ? committedText
      : (committedText.isEmpty ? partialText : '$committedText $partialText');

  VoiceSessionSnapshot copyWith({
    VoiceSessionStatus? status,
    String? committedText,
    String? partialText,
    int? segmentCount,
    bool? manuallyEdited,
    String? requestedLocale,
    String? localeInUse,
    bool clearLocaleInUse = false,
    int? localeAttempt,
    int? localeCandidates,
    TranscriptionEngineRoute? route,
    TranscriptionEngineRoute? observedRoute,
    bool clearObservedRoute = false,
    bool? routeFallbackOffered,
    bool? routeFallbackUsed,
    VoiceOfflineEvidence? offline,
    TranscriptionErrorCode? errorCode,
    String? errorDetail,
    bool clearError = false,
    TranscriptionEndReason? lastEndReason,
    bool? canUndoAutoAppend,
    VoiceSessionText? delivered,
    bool clearDelivered = false,
    TranscriptionAvailability? availability,
  }) => VoiceSessionSnapshot(
    status: status ?? this.status,
    committedText: committedText ?? this.committedText,
    partialText: partialText ?? this.partialText,
    segmentCount: segmentCount ?? this.segmentCount,
    manuallyEdited: manuallyEdited ?? this.manuallyEdited,
    requestedLocale: requestedLocale ?? this.requestedLocale,
    localeInUse: clearLocaleInUse ? null : (localeInUse ?? this.localeInUse),
    localeAttempt: localeAttempt ?? this.localeAttempt,
    localeCandidates: localeCandidates ?? this.localeCandidates,
    route: route ?? this.route,
    observedRoute: clearObservedRoute
        ? null
        : (observedRoute ?? this.observedRoute),
    routeFallbackOffered: routeFallbackOffered ?? this.routeFallbackOffered,
    routeFallbackUsed: routeFallbackUsed ?? this.routeFallbackUsed,
    offline: offline ?? this.offline,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
    lastEndReason: lastEndReason ?? this.lastEndReason,
    canUndoAutoAppend: canUndoAutoAppend ?? this.canUndoAutoAppend,
    delivered: clearDelivered ? null : (delivered ?? this.delivered),
    availability: availability ?? this.availability,
  );

  /// Representación para diagnóstico. **Sin una sola palabra de lo dictado.**
  @override
  String toString() =>
      'VoiceSessionSnapshot(${status.name}, chars=${committedText.length}, '
      'partialChars=${partialText.length}, segments=$segmentCount, '
      'edited=$manuallyEdited, locale=$localeInUse, '
      'route=${observedRoute?.name ?? route.name}, '
      'error=${errorCode?.name})';
}
