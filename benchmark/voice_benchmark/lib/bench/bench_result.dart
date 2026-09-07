/// Resultado de dictar UNA frase del corpus con UN motor.
///
/// Es la unidad que se exporta y la que el agregador del repositorio lee. Todo
/// campo no medido queda `null` y se publica como `NOT_MEASURED`: el informe no
/// puede inventar una cifra que nadie tomó.
///
/// ## Identidad de la corrida
///
/// Cada resultado lleva encima **con qué se midió**: corpus, versión, digest de
/// sus bytes, partición, candidato, motores, hashes de los modelos, commit del
/// banco, aparato, API, ABI, fecha y el modo avión realmente observado.
///
/// Se repite en cada fila y no sólo en la cabecera de la tanda a propósito. Los
/// archivos se separan, se juntan, se convierten a CSV y se pegan en una hoja;
/// una fila que pierde su identidad por el camino es una fila que después se
/// coloca en la columna equivocada. Fue lo que estuvo a punto de pasar con C1,
/// medido con el corpus de la Fase 0 mientras la pantalla decía otra cosa.
///
/// Los valores por omisión están vacíos porque las tandas de la Fase 0 se
/// exportaron antes de que existieran estos campos. Ese vacío es información:
/// el agregador lo lee como «corrida sin identidad» y se niega a ponerla en la
/// misma tabla que una nueva.
final class BenchResult {
  const BenchResult({
    required this.sampleId,
    required this.split,
    required this.intent,
    required this.expectedText,
    required this.engine,
    required this.model,
    required this.requestedLocale,
    required this.effectiveLocale,
    required this.device,
    required this.androidRelease,
    required this.androidSdk,
    required this.airplaneMode,
    this.systemAirplaneMode,
    required this.startedAt,
    this.obtainedText,
    this.partialLatencyMs,
    this.finalLatencyMs,
    this.audioDurationMs,
    this.memoryBytes,
    this.errorCode,
    this.errorDetail,
    this.attempt = 1,
    this.notes,
    this.transcriptRedacted = false,
    this.corpusId = '',
    this.corpusVersion = '',
    this.corpusDigest = '',
    this.partition = '',
    this.candidateId = '',
    this.partialEngine,
    this.finalEngine = '',
    this.modelHashes = const <String, String>{},
    this.benchCommit = '',
    this.abi = '',
  });

  /// Identificador de la frase, por ejemplo `AC-012`.
  final String sampleId;

  /// El conjunto al que la frase pertenece en el corpus: `ajuste` o
  /// `aceptacion`. Es una propiedad de la frase.
  final String split;

  /// La partición que se estaba dictando: `ajuste`, `aceptacion` o `sin_habla`.
  ///
  /// Distinta de [split] sólo en el no-habla, que sale de los dos conjuntos y
  /// se dicta como tanda técnica aparte.
  final String partition;

  final String intent;

  /// Lo que se debía decir.
  final String expectedText;

  /// Lo que el motor entendió. `null` si falló o si se redactó antes de exportar.
  final String? obtainedText;

  /// `android-speech`, `whisper-tiny-q5_1`, …
  final String engine;

  /// Modelo concreto cuando aplica; vacío para el motor del sistema.
  final String model;

  // --------------------------------------------------------- identidad

  /// Corpus con el que se dictó: `fase0` o `hibrido-ag`.
  final String corpusId;

  /// Versión que declaraba ese corpus.
  final String corpusVersion;

  /// SHA-256 de los bytes del corpus leídos por la aplicación.
  ///
  /// Es el mismo que da `sha256sum` sobre el archivo del repositorio: se puede
  /// comprobar desde fuera sin creerle nada al teléfono.
  final String corpusDigest;

  /// `C0`…`C4`. Vacío si el motor no correspondía a ningún candidato conocido,
  /// caso en el que el banco no debería haber dejado grabar.
  final String candidateId;

  /// Motor que produjo los parciales. `null` cuando el candidato no promete
  /// parciales: Whisper no los da, y eso no es una latencia sin medir.
  final String? partialEngine;

  /// Motor que produjo el texto final propuesto.
  final String finalEngine;

  /// Modelo → SHA-256 verificado por el script que lo dejó en el APK.
  final Map<String, String> modelHashes;

  /// Commit del banco con el que se construyó el APK.
  final String benchCommit;

  /// ABI del aparato. El APK debe llevar una sola, y ésta es la que corrió.
  final String abi;

  // ---------------------------------------------------------- el aparato

  final String requestedLocale;

  /// El que el motor usó realmente. Puede diferir del pedido (por ejemplo
  /// `es-ES` cuando se pidió `es-BO`).
  final String? effectiveLocale;

  final String device;
  final String androidRelease;
  final int androidSdk;

  /// Modo avión **declarado** por quien opera el banco.
  final bool airplaneMode;

  /// Modo avión **leído del sistema** en el momento de guardar la medición.
  ///
  /// `null` si no se pudo consultar. Cuando difiere de [airplaneMode] la tanda
  /// está mal etiquetada y no puede sostener ninguna conclusión sobre
  /// funcionamiento sin Internet: ver [airplaneModeMismatch].
  final bool? systemAirplaneMode;

  /// Lo declarado no coincide con lo que dice el teléfono.
  bool get airplaneModeMismatch =>
      systemAirplaneMode != null && systemAirplaneMode != airplaneMode;

  final DateTime startedAt;

  /// Milisegundos hasta el primer resultado parcial.
  final int? partialLatencyMs;

  /// Milisegundos hasta el resultado final.
  final int? finalLatencyMs;

  /// Duración del audio dictado.
  final int? audioDurationMs;

  /// Memoria del proceso al terminar la frase.
  final int? memoryBytes;

  /// Código del puerto (`permissionDenied`, `localeUnavailable`, …).
  final String? errorCode;

  /// Diagnóstico técnico. Nunca la frase dictada.
  final String? errorDetail;

  /// Número de intento sobre la misma frase (repetir cuenta).
  final int attempt;

  /// Observación escrita por quien ejecuta la prueba.
  final String? notes;

  /// La transcripción se eliminó a propósito antes de exportar.
  final bool transcriptRedacted;

  /// Sin fallo y con texto reconocido.
  bool get succeeded => errorCode == null && (obtainedText ?? '').isNotEmpty;

  /// Copia sin la transcripción. **La identidad se conserva**: quitar el texto
  /// dictado protege datos reales; quitar de qué corpus salió convertiría la
  /// medición en una cifra suelta.
  BenchResult redacted() => copyWith(
    obtainedText: null,
    clearObtainedText: true,
    transcriptRedacted: true,
  );

  BenchResult copyWith({
    String? obtainedText,
    bool clearObtainedText = false,
    int? partialLatencyMs,
    int? finalLatencyMs,
    int? audioDurationMs,
    int? memoryBytes,
    String? errorCode,
    String? errorDetail,
    String? effectiveLocale,
    String? notes,
    int? attempt,
    bool? transcriptRedacted,
  }) => BenchResult(
    sampleId: sampleId,
    split: split,
    partition: partition,
    intent: intent,
    expectedText: expectedText,
    obtainedText: clearObtainedText
        ? null
        : (obtainedText ?? this.obtainedText),
    engine: engine,
    model: model,
    corpusId: corpusId,
    corpusVersion: corpusVersion,
    corpusDigest: corpusDigest,
    candidateId: candidateId,
    partialEngine: partialEngine,
    finalEngine: finalEngine,
    modelHashes: modelHashes,
    benchCommit: benchCommit,
    abi: abi,
    requestedLocale: requestedLocale,
    effectiveLocale: effectiveLocale ?? this.effectiveLocale,
    device: device,
    androidRelease: androidRelease,
    androidSdk: androidSdk,
    airplaneMode: airplaneMode,
    systemAirplaneMode: systemAirplaneMode,
    startedAt: startedAt,
    partialLatencyMs: partialLatencyMs ?? this.partialLatencyMs,
    finalLatencyMs: finalLatencyMs ?? this.finalLatencyMs,
    audioDurationMs: audioDurationMs ?? this.audioDurationMs,
    memoryBytes: memoryBytes ?? this.memoryBytes,
    errorCode: errorCode ?? this.errorCode,
    errorDetail: errorDetail ?? this.errorDetail,
    attempt: attempt ?? this.attempt,
    notes: notes ?? this.notes,
    transcriptRedacted: transcriptRedacted ?? this.transcriptRedacted,
  );

  Map<String, Object?> toJson() => {
    'sampleId': sampleId,
    'split': split,
    'partition': partition,
    'intent': intent,
    'expectedText': expectedText,
    'obtainedText': obtainedText,
    'engine': engine,
    'model': model,
    'corpusId': corpusId,
    'corpusVersion': corpusVersion,
    'corpusDigest': corpusDigest,
    'candidateId': candidateId,
    'partialEngine': partialEngine,
    'finalEngine': finalEngine,
    'modelHashes': modelHashes,
    'benchCommit': benchCommit,
    'abi': abi,
    'requestedLocale': requestedLocale,
    'effectiveLocale': effectiveLocale,
    'device': device,
    'androidRelease': androidRelease,
    'androidSdk': androidSdk,
    'airplaneMode': airplaneMode,
    'systemAirplaneMode': systemAirplaneMode,
    'startedAt': startedAt.toIso8601String(),
    'partialLatencyMs': partialLatencyMs,
    'finalLatencyMs': finalLatencyMs,
    'audioDurationMs': audioDurationMs,
    'memoryBytes': memoryBytes,
    'errorCode': errorCode,
    'errorDetail': errorDetail,
    'attempt': attempt,
    'notes': notes,
    'transcriptRedacted': transcriptRedacted,
  };
}
