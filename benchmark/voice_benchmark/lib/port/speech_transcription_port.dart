/// Contrato de transcripción por voz (`SpeechTranscriptionPort`).
///
/// Es la frontera que exige `ADR-002` y `EVO-009_SAFE_VOICE_SPEC.md`: el dominio
/// depende de este puerto, nunca de una API concreta. Cambiar de motor no debe
/// cambiar ni un tipo de este archivo.
///
/// ## Lo que este puerto NO conoce, por diseño
///
/// SQLite, `AgroRepository`, compras, productos, proveedores, inventario, FIFO,
/// aplicaciones, planificaciones, cuentas, pagos, reportes, backups y la
/// navegación de Operaciones. No importa nada del paquete `agroquimicos`. Esa
/// ausencia es el control: un motor de voz no puede escribir en el negocio si no
/// tiene forma de nombrarlo.
///
/// El puerto produce **texto y estados**. Nada más. La interpretación tipada es
/// `EVO-010` y vive detrás de otra frontera (`ADR-003`).
library;

/// Estados observables de una sesión, según `EVO-009` § Estados mínimos.
enum TranscriptionState {
  /// Sin sesión activa.
  idle,

  /// Esperando la respuesta del permiso de micrófono.
  requestingPermission,

  /// Micrófono activo.
  listening,

  /// Habla terminada; esperando el resultado final del motor.
  processing,

  /// Hay texto disponible y editable.
  preview,

  /// Texto de sesión listo para entregar. **No ejecuta dominio.**
  ready,

  /// Sesión descartada por el usuario.
  cancelled,

  /// Permiso rechazado.
  denied,

  /// Servicio o locale no disponible.
  unavailable,

  /// Fallo recuperable y seguro.
  error,
}

/// Causas de fallo que la UI debe poder distinguir sin leer texto libre.
enum TranscriptionErrorCode {
  /// El usuario negó el micrófono esta vez.
  permissionDenied,

  /// Denegación permanente: hay que ir a los ajustes del sistema.
  permissionPermanentlyDenied,

  /// No hay servicio de reconocimiento utilizable en el dispositivo.
  serviceUnavailable,

  /// El servicio existe pero no tiene el idioma pedido.
  localeUnavailable,

  /// El motor necesitaba red y no la había.
  networkRequired,

  /// El motor terminó sin reconocer nada.
  noMatch,

  /// El motor no respondió dentro del plazo.
  timeout,

  /// Ya había una sesión activa.
  busy,

  /// Otro fallo del motor. `detail` lleva el código nativo, nunca la frase.
  engineFailure,
}

/// Un evento emitido por el adaptador durante la sesión.
sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

/// Cambio de estado de la sesión.
final class TranscriptionStateChanged extends TranscriptionEvent {
  const TranscriptionStateChanged(this.state);

  final TranscriptionState state;

  @override
  String toString() => 'TranscriptionStateChanged(${state.name})';
}

/// Texto parcial: puede cambiar por completo en el siguiente evento.
final class TranscriptionPartial extends TranscriptionEvent {
  const TranscriptionPartial(this.text, {required this.elapsed});

  final String text;

  /// Tiempo desde `start()` hasta este parcial.
  final Duration elapsed;

  /// Nunca incluye el texto: los logs no deben contener lo dictado.
  @override
  String toString() =>
      'TranscriptionPartial(chars=${text.length}, elapsed=${elapsed.inMilliseconds}ms)';
}

/// Texto final de un tramo de habla.
final class TranscriptionFinal extends TranscriptionEvent {
  const TranscriptionFinal(this.text, {required this.elapsed});

  final String text;

  /// Tiempo desde `start()` hasta el resultado final.
  final Duration elapsed;

  @override
  String toString() =>
      'TranscriptionFinal(chars=${text.length}, elapsed=${elapsed.inMilliseconds}ms)';
}

/// Fallo de la sesión. La sesión queda terminada y el micrófono liberado.
final class TranscriptionFailed extends TranscriptionEvent {
  const TranscriptionFailed(this.code, {this.detail});

  final TranscriptionErrorCode code;

  /// Diagnóstico técnico (código nativo, nombre de excepción). **Nunca** la
  /// transcripción ni datos del negocio.
  final String? detail;

  @override
  String toString() => 'TranscriptionFailed(${code.name}, detail=$detail)';
}

/// Qué sabe hacer el motor aquí y ahora. Se consulta antes de ofrecer voz.
final class TranscriptionAvailability {
  const TranscriptionAvailability({
    required this.available,
    required this.onDeviceAvailable,
    required this.requestedLocale,
    this.effectiveLocale,
    this.installedLocales = const [],
    this.supportedLocales = const [],
    this.engineName = '',
    this.engineVersion = '',
    this.modelName,
    this.requiresNetwork = true,
    this.detail,
  });

  /// Hay algún reconocedor utilizable.
  final bool available;

  /// Hay reconocimiento que no necesita red.
  final bool onDeviceAvailable;

  /// El locale que se pidió (por ejemplo `es-BO`).
  final String requestedLocale;

  /// El locale que el motor usará realmente (por ejemplo `es-ES`).
  ///
  /// Puede diferir del pedido. `EVO-009-REQ-008` obliga a mostrarlo: la UI no
  /// puede afirmar `es-BO` si el motor va a escuchar en `es-ES`.
  final String? effectiveLocale;

  /// Idiomas con modelo ya descargado en el aparato.
  final List<String> installedLocales;

  /// Idiomas que el motor admitiría, estén instalados o no.
  final List<String> supportedLocales;

  final String engineName;
  final String engineVersion;

  /// Modelo concreto, cuando el motor lo tiene (Whisper). `null` para motores
  /// del sistema que no lo exponen.
  final String? modelName;

  /// `true` si transcribir puede necesitar Internet.
  ///
  /// Se declara pesimista a propósito: prometer offline sin garantía está
  /// prohibido por `EVO-009-REQ-008`.
  final bool requiresNetwork;

  final String? detail;

  /// El locale pedido no es el que se usará.
  bool get localeIsFallback =>
      effectiveLocale != null && effectiveLocale != requestedLocale;

  Map<String, Object?> toJson() => {
    'available': available,
    'onDeviceAvailable': onDeviceAvailable,
    'requestedLocale': requestedLocale,
    'effectiveLocale': effectiveLocale,
    'installedLocales': installedLocales,
    'supportedLocales': supportedLocales,
    'engineName': engineName,
    'engineVersion': engineVersion,
    'modelName': modelName,
    'requiresNetwork': requiresNetwork,
    'detail': detail,
  };
}

/// Parámetros de una sesión de dictado.
final class TranscriptionRequest {
  const TranscriptionRequest({
    this.locale = 'es-BO',
    this.preferOffline = true,
    this.partialResults = true,
    this.maxDuration = const Duration(seconds: 60),
  });

  final String locale;

  /// Pide al motor no usar red. No garantiza que la respete.
  final bool preferOffline;

  final bool partialResults;

  /// Tope de sesión. Al agotarse se emite [TranscriptionErrorCode.timeout] y se
  /// libera el micrófono: una sesión colgada no puede quedar escuchando.
  final Duration maxDuration;
}

/// Fuente reemplazable de transcripción.
///
/// Contrato de ciclo de vida:
///
/// * `start` sobre una sesión activa emite [TranscriptionErrorCode.busy] y **no**
///   abre una segunda captura (protege contra el doble toque).
/// * `stop` pide el resultado final y deja de escuchar.
/// * `cancel` descarta la sesión sin resultado.
/// * `dispose` libera el micrófono y cierra [events]. Es idempotente.
/// * Tras `cancel`, `stop` o un fallo, el micrófono queda libre siempre.
abstract interface class SpeechTranscriptionPort {
  /// Identificador estable del motor, para etiquetar mediciones.
  String get engineId;

  /// Estado actual, sin suscribirse al stream.
  TranscriptionState get state;

  /// Eventos de la sesión. Broadcast: la UI y el medidor escuchan a la vez.
  Stream<TranscriptionEvent> get events;

  /// Qué puede hacer el motor para [locale] en este aparato.
  Future<TranscriptionAvailability> checkAvailability(String locale);

  /// Abre una sesión. Pide permiso si hace falta.
  Future<void> start(TranscriptionRequest request);

  /// Deja de escuchar y espera el resultado final.
  Future<void> stop();

  /// Descarta la sesión. No habrá resultado final.
  Future<void> cancel();

  /// Libera micrófono y recursos nativos. Idempotente.
  Future<void> dispose();
}
