/// Resultado de dictar UNA frase del corpus con UN motor.
///
/// Es la unidad que se exporta y la que el agregador del repositorio lee. Todo
/// campo no medido queda `null` y se publica como `NOT_MEASURED`: el informe no
/// puede inventar una cifra que nadie tomó.
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
  });

  /// Identificador de la frase, por ejemplo `AC-012`.
  final String sampleId;
  final String split;
  final String intent;

  /// Lo que se debía decir.
  final String expectedText;

  /// Lo que el motor entendió. `null` si falló o si se redactó antes de exportar.
  final String? obtainedText;

  /// `android-speech`, `whisper-tiny-q5_1`, …
  final String engine;

  /// Modelo concreto cuando aplica; vacío para el motor del sistema.
  final String model;

  final String requestedLocale;

  /// El que el motor usó realmente. Puede diferir del pedido (por ejemplo
  /// `es-ES` cuando se pidió `es-BO`).
  final String? effectiveLocale;

  final String device;
  final String androidRelease;
  final int androidSdk;

  /// La prueba se hizo en modo avión.
  final bool airplaneMode;

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
    intent: intent,
    expectedText: expectedText,
    obtainedText: clearObtainedText
        ? null
        : (obtainedText ?? this.obtainedText),
    engine: engine,
    model: model,
    requestedLocale: requestedLocale,
    effectiveLocale: effectiveLocale ?? this.effectiveLocale,
    device: device,
    androidRelease: androidRelease,
    androidSdk: androidSdk,
    airplaneMode: airplaneMode,
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
    'intent': intent,
    'expectedText': expectedText,
    'obtainedText': obtainedText,
    'engine': engine,
    'model': model,
    'requestedLocale': requestedLocale,
    'effectiveLocale': effectiveLocale,
    'device': device,
    'androidRelease': androidRelease,
    'androidSdk': androidSdk,
    'airplaneMode': airplaneMode,
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
