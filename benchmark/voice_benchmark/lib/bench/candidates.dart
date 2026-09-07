/// Los candidatos del benchmark híbrido, con su motor y sus modelos.
///
/// ## Qué resuelve
///
/// El resultado exportado tiene que decir **qué se midió**, no sólo qué motor
/// respondió. «`vosk-small-es-0.42`» no distingue C1 de la mitad de C4: es el
/// mismo motor en los dos, y sólo el candidato dice si hubo una segunda pasada
/// de Whisper detrás.
///
/// ## De dónde sale el candidato
///
/// De `engineId`, que llega del sabor compilado (`BuildConfig.ENGINE_ID`). Es
/// **observado**, no declarado por Dart: si alguien instala el APK equivocado,
/// el banco lo ve. Un `engineId` que no esté en esta tabla no se convierte en
/// «candidato desconocido» ni se aproxima al más parecido: bloquea la
/// grabación. Medir sin poder nombrar el candidato produce filas que después no
/// se pueden colocar en ninguna columna.
///
/// ## Qué son los hashes de esta tabla, exactamente
///
/// Son los SHA-256 que `tool/fetch_vosk_model.sh` y
/// `tool/fetch_whisper_models.sh` **verifican antes** de dejar el modelo donde
/// Gradle lo empaqueta: si no coinciden, el script borra el archivo y falla, y
/// el APK no llega a construirse. No son una comprobación hecha en el teléfono
/// durante la corrida. Una prueba contrasta esta tabla contra esos scripts, de
/// modo que subir de modelo tocando un solo lado falla en vez de exportar un
/// hash que no corresponde al binario instalado.
library;

/// Un candidato de la matriz de `EVOLUTION-3_HYBRID_ENGINE_BENCHMARK_PLAN.md`.
final class BenchCandidate {
  const BenchCandidate({
    required this.id,
    required this.engineId,
    required this.flavor,
    required this.label,
    required this.partialEngine,
    required this.finalEngine,
    required this.modelHashes,
  });

  /// `C0`…`C4`, o `F0T` para el Whisper tiny de la Fase 0, que no es candidato
  /// del plan híbrido pero sigue siendo construible.
  final String id;

  /// Lo que reporta el sabor compilado.
  final String engineId;

  /// Sabor de Gradle con el que se construye.
  final String flavor;

  final String label;

  /// Motor que produce los parciales. `null` cuando el candidato **no promete
  /// parciales**: Whisper no los da, y registrar «sin medir» donde no hay nada
  /// que medir es distinto de registrar una latencia que nadie tomó.
  final String? partialEngine;

  /// Motor que produce el texto final propuesto.
  final String finalEngine;

  /// Modelo → SHA-256 verificado por el script de descarga.
  final Map<String, String> modelHashes;
}

abstract final class CandidateRegistry {
  static const c0 = BenchCandidate(
    id: 'C0',
    engineId: 'android-speech',
    flavor: 'androidSpeech',
    label: 'C0 · Android SpeechRecognizer (baseline histórico)',
    partialEngine: 'android-speech',
    finalEngine: 'android-speech',
    // El modelo lo pone el sistema y no es reproducible: depende del OEM y de
    // qué paquete de idioma haya instalado. Es justo la dependencia que abrió
    // ADR-004.
    modelHashes: <String, String>{},
  );

  static const c1 = BenchCandidate(
    id: 'C1',
    engineId: 'vosk-small-es-0.42',
    flavor: 'vosk',
    label: 'C1 · Vosk small es 0.42 aislado',
    partialEngine: 'vosk-small-es-0.42',
    finalEngine: 'vosk-small-es-0.42',
    modelHashes: <String, String>{
      'vosk-model-small-es-0.42':
          '09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f',
    },
  );

  static const c2 = BenchCandidate(
    id: 'C2',
    engineId: 'whisper-base-q5_1',
    flavor: 'whisperBase',
    label: 'C2 · Whisper base q5_1 (baseline Whisper anterior)',
    partialEngine: null,
    finalEngine: 'whisper-base-q5_1',
    modelHashes: <String, String>{
      'ggml-base-q5_1.bin':
          '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
    },
  );

  static const c3 = BenchCandidate(
    id: 'C3',
    engineId: 'whisper-small-q5_1',
    flavor: 'whisperSmall',
    label: 'C3 · Whisper small q5_1 aislado',
    partialEngine: null,
    finalEngine: 'whisper-small-q5_1',
    modelHashes: <String, String>{
      'ggml-small-q5_1.bin':
          'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
    },
  );

  static const c4 = BenchCandidate(
    id: 'C4',
    engineId: 'hybrid-vosk-whisper-small',
    flavor: 'hybrid',
    label: 'C4 · Híbrido Vosk parcial + Whisper small final',
    partialEngine: 'vosk-small-es-0.42',
    finalEngine: 'whisper-small-q5_1',
    modelHashes: <String, String>{
      'vosk-model-small-es-0.42':
          '09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f',
      'ggml-small-q5_1.bin':
          'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
    },
  );

  /// Whisper tiny. No está en la matriz del plan híbrido; se conserva porque el
  /// sabor existe desde la Fase 0 y un APK construible tiene que poder decir
  /// qué es.
  static const f0tiny = BenchCandidate(
    id: 'F0T',
    engineId: 'whisper-tiny-q5_1',
    flavor: 'whisperTiny',
    label: 'Fase 0 · Whisper tiny q5_1 (fuera de la matriz híbrida)',
    partialEngine: null,
    finalEngine: 'whisper-tiny-q5_1',
    modelHashes: <String, String>{
      'ggml-tiny-q5_1.bin':
          '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
    },
  );

  static const all = <BenchCandidate>[c0, c1, c2, c3, c4, f0tiny];

  /// El candidato de un motor, o `null` si ese motor no está registrado.
  static BenchCandidate? byEngineId(String engineId) {
    for (final candidate in all) {
      if (candidate.engineId == engineId) return candidate;
    }
    return null;
  }

  static BenchCandidate? byId(String id) {
    for (final candidate in all) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }
}
