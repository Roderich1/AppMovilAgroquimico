/// Contrato de transcripción por voz de `EVO-009` (`SpeechTranscriptionPort`).
///
/// Es la frontera que exigen `ADR-002` y `EVO-009_SAFE_VOICE_SPEC.md`: la sesión
/// depende de este puerto, nunca de una API concreta. Cambiar de motor no debe
/// cambiar ni un tipo de este archivo.
///
/// ## Lo que este puerto NO conoce, por diseño
///
/// SQLite, `AgroRepository`, compras, aplicaciones, planificaciones, cuentas,
/// pagos, FIFO, reportes, backup y la navegación de la aplicación. Tampoco
/// importa `package:flutter/material.dart`. Esa ausencia es el control: un motor
/// de voz no puede escribir en el negocio si no tiene forma de nombrarlo, y
/// `test/voice/voice_architecture_guard_test.dart` lo comprueba en cada CI.
///
/// El puerto produce **texto y estados**. Nada más. La interpretación tipada es
/// `EVO-010` y vive detrás de otra frontera (`ADR-003`).
///
/// ## Un turno, no una sesión
///
/// Android `SpeechRecognizer` termina de escuchar por su cuenta al detectar
/// silencio. Este puerto modela **un turno de escucha**, no la sesión completa
/// del usuario: emite [TranscriptionTurnEnded] cuando el motor deja de escuchar,
/// y es `VoiceSessionController` quien decide si abre otro turno. Mezclar ambas
/// cosas aquí obligaría a cada adaptador a reimplementar la continuidad.
library;

/// Causas de fallo que la interfaz debe poder distinguir sin leer texto libre.
enum TranscriptionErrorCode {
  /// El usuario negó el micrófono esta vez.
  permissionDenied,

  /// Denegación permanente: el sistema ya no muestra el diálogo y hay que ir a
  /// los ajustes de la aplicación.
  permissionPermanentlyDenied,

  /// No hay servicio de reconocimiento utilizable en el dispositivo.
  recognizerUnavailable,

  /// El servicio existe pero no tiene, o no admite, el idioma pedido.
  ///
  /// Cubre `ERROR_LANGUAGE_NOT_SUPPORTED` (error 12, el caso de `es-BO`) y
  /// `ERROR_LANGUAGE_UNAVAILABLE` (error 13, el caso de `es-ES` sin modelo
  /// descargado). Ambos están medidos en `ADR-002`.
  localeUnavailable,

  /// El motor necesitaba red y no la había.
  networkRequired,

  /// Ya había un turno abierto en el motor.
  busy,

  /// `ERROR_CLIENT` de Android: fallo del lado del cliente, típicamente al
  /// reiniciar demasiado rápido.
  ///
  /// Tiene código propio porque es la causa conocida de bucles de reinicio: el
  /// motor falla al instante y un reintento inmediato vuelve a fallar. La
  /// política de continuidad lo cuenta como turno no productivo.
  clientError,

  /// El servicio de reconocimiento respondió con un error propio.
  serverError,

  /// Otro fallo del motor. `detail` lleva el código nativo, nunca la frase.
  engineFailure;

  /// `true` si reintentar no tiene sentido sin una acción del usuario.
  ///
  /// Un fallo fatal detiene la continuidad: la sesión no vuelve a abrir un turno
  /// por su cuenta. `EVO-009-REQ-017` prohíbe reintentar infinitamente.
  bool get isFatal => switch (this) {
    TranscriptionErrorCode.permissionDenied ||
    TranscriptionErrorCode.permissionPermanentlyDenied ||
    TranscriptionErrorCode.recognizerUnavailable ||
    TranscriptionErrorCode.localeUnavailable => true,
    _ => false,
  };
}

/// Por qué el motor dejó de escuchar.
///
/// La sesión decide con esto si reabre un turno, y con qué espera.
enum TranscriptionEndReason {
  /// Llegó un resultado final con texto.
  segment,

  /// El motor terminó sin reconocer nada (`ERROR_NO_MATCH`).
  ///
  /// Silencio **no es texto**: `ADR-002` eligió este motor justamente porque no
  /// inventa contenido donde no hubo habla.
  noMatch,

  /// El motor no oyó nada dentro del plazo, o el turno agotó su duración máxima.
  timeout,

  /// El usuario o el ciclo de vida descartaron el turno.
  cancelled,

  /// El usuario pidió detener y el motor cerró el turno.
  stoppedByUser,

  /// El turno terminó por un fallo. El evento de error viaja aparte.
  error,
}

/// Etapa observable del motor dentro de un turno.
enum TranscriptionStage {
  /// El sistema está preguntando por el permiso de micrófono.
  ///
  /// Lo emite el lado nativo, que es quien sabe si hará falta el diálogo. La
  /// sesión no puede deducirlo: `EVO-009-REQ-004` exige que el permiso se pida
  /// **al tocar**, y sólo el adaptador sabe si ya estaba concedido.
  awaitingPermission,

  /// El micrófono está tomado y el motor escucha.
  listening,

  /// Terminó el habla; el motor está produciendo el resultado final.
  processing,
}

/// Cuál de los dos reconocedores de Android atiende el turno.
///
/// Android expone **dos** servicios distintos y la diferencia importa:
///
/// * [onDevice] es `createOnDeviceSpeechRecognizer()`, un reconocedor dedicado
///   que trabaja sin red pero que sólo entiende los idiomas cuyo modelo esté
///   descargado en el aparato.
/// * [systemDefault] es `createSpeechRecognizer()`, el servicio de
///   reconocimiento que el teléfono trae configurado. Se le puede **pedir**
///   `EXTRA_PREFER_OFFLINE`, pero es el sistema quien decide, y puede usar
///   Internet.
///
/// La distinción existe por `DEFECTO-004`: el HONOR JDY-LX3P (API 36) tiene
/// reconocedor [onDevice] —Android System Intelligence— **sin ningún español**,
/// y agotaba los diez candidatos sin llegar a intentar el [systemDefault], que
/// es exactamente el que había funcionado en el aparato de `ADR-002`. Allí
/// `isOnDeviceRecognitionAvailable()` devolvía `false` y el sistema entregaba el
/// predeterminado sin que nadie tuviera que elegir.
enum TranscriptionEngineRoute {
  /// Reconocedor local dedicado. No usa red.
  onDevice,

  /// Servicio de reconocimiento del teléfono. Puede usar red.
  systemDefault,
}

/// Qué se sabe del modo avión del dispositivo.
///
/// Es un dato del sistema, no una afirmación del operador: `ADR-002` se aceptó
/// contrastando `Settings.Global.AIRPLANE_MODE_ON`, no lo que dijera quien
/// probaba. Se lee sin permisos y no implica acceso a red.
enum AirplaneMode { on, off, unknown }

/// Un evento emitido por el adaptador durante un turno de escucha.
sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

/// Texto provisional. Puede cambiar por completo en el siguiente evento.
///
/// `EVO-009-REQ-019`: es sólo texto, no alimenta ninguna decisión. Nunca se
/// acumula por su cuenta en el texto de sesión.
final class TranscriptionPartial extends TranscriptionEvent {
  const TranscriptionPartial(this.text, {required this.elapsed});

  final String text;
  final Duration elapsed;

  /// Nunca incluye el texto: los registros no deben contener lo dictado.
  @override
  String toString() =>
      'TranscriptionPartial(chars=${text.length}, '
      'elapsed=${elapsed.inMilliseconds}ms)';
}

/// Resultado final de **un tramo** de habla.
///
/// Varios segmentos componen la sesión. El puerto no los acumula: eso es
/// política de sesión y vive en `VoiceSessionController`.
final class TranscriptionSegment extends TranscriptionEvent {
  const TranscriptionSegment(this.text, {required this.elapsed});

  final String text;
  final Duration elapsed;

  @override
  String toString() =>
      'TranscriptionSegment(chars=${text.length}, '
      'elapsed=${elapsed.inMilliseconds}ms)';
}

/// El motor dejó de escuchar. Siempre llega, gane o falle el turno.
///
/// Es el único punto donde la sesión decide continuidad, y por eso el micrófono
/// ya está liberado cuando se emite.
final class TranscriptionTurnEnded extends TranscriptionEvent {
  const TranscriptionTurnEnded(this.reason);

  final TranscriptionEndReason reason;

  @override
  String toString() => 'TranscriptionTurnEnded(${reason.name})';
}

/// El motor terminó sin reconocer nada.
final class TranscriptionNoMatch extends TranscriptionEvent {
  const TranscriptionNoMatch();

  @override
  String toString() => 'TranscriptionNoMatch()';
}

/// El motor no respondió, o no oyó nada, dentro del plazo.
final class TranscriptionTimeout extends TranscriptionEvent {
  const TranscriptionTimeout();

  @override
  String toString() => 'TranscriptionTimeout()';
}

/// El turno se descartó sin resultado.
final class TranscriptionCancelled extends TranscriptionEvent {
  const TranscriptionCancelled();

  @override
  String toString() => 'TranscriptionCancelled()';
}

/// Fallo del turno. El micrófono queda liberado.
final class TranscriptionFailed extends TranscriptionEvent {
  const TranscriptionFailed(this.code, {this.detail});

  final TranscriptionErrorCode code;

  /// Diagnóstico técnico (código nativo, nombre de excepción). **Nunca** la
  /// transcripción ni datos del negocio.
  final String? detail;

  @override
  String toString() => 'TranscriptionFailed(${code.name}, detail=$detail)';
}

/// Cambio de etapa dentro del turno.
final class TranscriptionStageChanged extends TranscriptionEvent {
  const TranscriptionStageChanged(this.stage);

  final TranscriptionStage stage;

  @override
  String toString() => 'TranscriptionStageChanged(${stage.name})';
}

/// El locale con el que el motor **aceptó** escuchar.
///
/// Se emite cuando el motor confirma que está escuchando, no antes: prometer un
/// idioma antes de que el motor responda es exactamente lo que `ADR-002`
/// prohíbe. El puerto informa sólo lo que aceptó; comparar eso con lo que el
/// producto quiso (`es-BO`) es política de sesión, no del motor.
final class TranscriptionLocaleInUse extends TranscriptionEvent {
  const TranscriptionLocaleInUse(this.locale);

  /// Lo que el motor realmente aceptó (`es-US`, por ejemplo).
  final String locale;

  @override
  String toString() => 'TranscriptionLocaleInUse($locale)';
}

/// Por qué reconocedor está escuchando el motor, de verdad.
///
/// No es el que se pidió: es el que el sistema acabó creando. En API 31 se pide
/// [TranscriptionEngineRoute.onDevice] y el sistema entrega el predeterminado
/// porque no hay otro, y anunciar el pedido en vez del usado escondería por
/// dónde pasa el audio.
final class TranscriptionRouteInUse extends TranscriptionEvent {
  const TranscriptionRouteInUse(this.route);

  final TranscriptionEngineRoute route;

  @override
  String toString() => 'TranscriptionRouteInUse(${route.name})';
}

/// Disponibilidad **observada**, no prometida.
final class TranscriptionAvailabilityObserved extends TranscriptionEvent {
  const TranscriptionAvailabilityObserved(this.availability);

  final TranscriptionAvailability availability;

  @override
  String toString() => 'TranscriptionAvailabilityObserved($availability)';
}

/// Qué declara el aparato sobre el reconocimiento, aquí y ahora.
///
/// **Ninguno de estos campos es una garantía.** `ADR-002` midió
/// `isOnDeviceRecognitionAvailable()` devolviendo `false` en un teléfono donde
/// el reconocimiento offline sí funcionaba. Por eso los nombres dicen lo que
/// dicen: [onDeviceApiReports] es *lo que contestó la API*, no *lo que ocurre*.
/// La única prueba de que el motor funciona sin red es haber transcrito sin red,
/// y eso lo registra la sesión, no esta consulta.
final class TranscriptionAvailability {
  const TranscriptionAvailability({
    required this.recognizerAvailable,
    required this.onDeviceApiReports,
    this.localeSupportKnown = true,
    this.installedLocales = const [],
    this.supportedLocales = const [],
    this.airplaneMode = AirplaneMode.unknown,
    this.engineName = '',
    this.engineVersion = '',
    this.detail,
  });

  /// Sin reconocimiento utilizable: la pantalla sigue permitiendo escribir.
  const TranscriptionAvailability.none({this.detail})
    : recognizerAvailable = false,
      onDeviceApiReports = false,
      localeSupportKnown = false,
      installedLocales = const [],
      supportedLocales = const [],
      airplaneMode = AirplaneMode.unknown,
      engineName = '',
      engineVersion = '';

  /// `isRecognitionAvailable()`: hay algún reconocedor instalado.
  final bool recognizerAvailable;

  /// Valor **crudo** de `isOnDeviceRecognitionAvailable()`.
  ///
  /// Se conserva sin interpretar y no se muestra como promesa de offline.
  final bool onDeviceApiReports;

  /// `false` cuando el sistema **no permite consultar** qué idiomas hay
  /// instalados (`checkRecognitionSupport` es API 33; el dispositivo de
  /// referencia de `ADR-002` es API 31).
  ///
  /// Distinto de "no hay ninguno". Sin esta marca, una lista vacía se leería
  /// como ausencia comprobada de idiomas y se registraría como medición algo que
  /// nunca se midió.
  final bool localeSupportKnown;

  /// Idiomas con modelo ya descargado. Vacío no significa "ninguno" si
  /// [localeSupportKnown] es `false`.
  final List<String> installedLocales;

  /// Idiomas que el motor admitiría, estén instalados o no.
  final List<String> supportedLocales;

  /// Modo avión según el sistema.
  final AirplaneMode airplaneMode;

  final String engineName;
  final String engineVersion;

  /// Diagnóstico técnico. Nunca contenido dictado.
  final String? detail;

  @override
  String toString() =>
      'TranscriptionAvailability(recognizer=$recognizerAvailable, '
      'onDeviceApiReports=$onDeviceApiReports, '
      'localeSupportKnown=$localeSupportKnown, '
      'installed=${installedLocales.length}, '
      'airplaneMode=${airplaneMode.name})';
}

/// Parámetros de **un turno** de dictado.
final class TranscriptionRequest {
  const TranscriptionRequest({
    required this.locale,
    this.preferOffline = true,
    this.partialResults = true,
    this.maxTurnDuration = const Duration(seconds: 60),
    this.route = TranscriptionEngineRoute.onDevice,
  });

  /// Locale concreto que se intentará. Lo elige `VoiceLocalePolicy`, nunca el
  /// adaptador: fijar un idioma dentro del motor escondería el fallback.
  final String locale;

  /// Pide al motor no usar red. **No garantiza** que lo respete
  /// (`EVO-009-REQ-013`).
  final bool preferOffline;

  final bool partialResults;

  /// Tope del turno. Al agotarse se emite [TranscriptionTimeout] y se libera el
  /// micrófono: un turno colgado no puede quedarse escuchando.
  final Duration maxTurnDuration;

  /// Qué reconocedor se pide. Lo decide la sesión, nunca el adaptador: elegirlo
  /// dentro del motor escondería el cambio a los ojos del usuario, y el paso al
  /// [TranscriptionEngineRoute.systemDefault] requiere su autorización.
  final TranscriptionEngineRoute route;

  TranscriptionRequest withLocale(String value) => TranscriptionRequest(
    locale: value,
    preferOffline: preferOffline,
    partialResults: partialResults,
    maxTurnDuration: maxTurnDuration,
    route: route,
  );
}

/// Fuente reemplazable de transcripción.
///
/// Contrato de ciclo de vida:
///
/// * `start` sobre un turno abierto emite [TranscriptionErrorCode.busy] y **no**
///   abre una segunda captura (protege contra el doble toque).
/// * `stop` pide el resultado final y deja de escuchar.
/// * `cancel` descarta el turno sin resultado.
/// * `dispose` libera el micrófono y cierra [events]. Es idempotente.
/// * Tras `stop`, `cancel` o un fallo, el micrófono queda libre **siempre**.
/// * Todo turno abierto termina con exactamente un [TranscriptionTurnEnded].
abstract interface class SpeechTranscriptionPort {
  /// Identificador estable del motor, para diagnóstico.
  String get engineId;

  /// `true` mientras el micrófono puede estar tomado.
  bool get isTurnOpen;

  /// Eventos del turno. Broadcast: la sesión y las pruebas escuchan a la vez.
  Stream<TranscriptionEvent> get events;

  /// Qué declara el motor para [locale] en este aparato. No es una garantía.
  Future<TranscriptionAvailability> checkAvailability(String locale);

  /// Abre un turno. Pide permiso si hace falta.
  Future<void> start(TranscriptionRequest request);

  /// Deja de escuchar y espera el resultado final.
  Future<void> stop();

  /// Descarta el turno. No habrá resultado final.
  Future<void> cancel();

  /// Abre los ajustes de la aplicación, para una denegación permanente.
  ///
  /// Devuelve `false` si el sistema no pudo abrirlos. No descarga nada y no
  /// concede ningún permiso por su cuenta.
  Future<bool> openSystemSettings();

  /// Libera micrófono y recursos nativos. Idempotente.
  Future<void> dispose();
}
