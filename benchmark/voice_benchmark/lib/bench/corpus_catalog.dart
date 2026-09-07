/// Qué corpus se puede medir, cuál está cargado y por qué se bloquea.
///
/// ## El defecto que origina este archivo
///
/// C1 (Vosk aislado) se midió entero con el corpus de la Fase 0 mientras la
/// pantalla mostraba «Corpus: aceptación». Ese menú nunca eligió un corpus:
/// elegía la partición, y el archivo estaba fijado en `main.dart`. No hubo
/// error, ni aviso, ni forma de notarlo desde el teléfono. Los números salieron
/// con aspecto de comparables con C3 y C4, que aún no existen.
///
/// La corrección no es «añadir un menú». Es que **el banco no pueda medir sin
/// saber exactamente qué está midiendo**, y que lo que la pantalla dice venga
/// de los bytes que se leyeron, nunca de lo que se pidió leer.
///
/// ## Las reglas
///
/// 1. Un corpus se identifica por `id`, versión y **digest de sus bytes**. Los
///    tres se muestran antes de grabar y viajan en cada resultado exportado.
/// 2. Si el archivo falta, está vacío, no se puede leer o su digest no coincide,
///    **se bloquea la ejecución**. No se sustituye por otro, ni se conserva el
///    anterior: quedarse con el corpus previo es precisamente cómo se mediría
///    Fase 0 creyendo estar en A–G.
/// 3. Ajuste y aceptación no comparten frase. Se comprueba por identificador y
///    por texto normalizado, dentro de cada partición y entre las dos.
/// 4. El corpus de aceptación no se edita después de ver resultados. El digest
///    fijado aquí es la guarda: cualquier cambio rompe la carga y obliga a
///    versionar un corpus nuevo y explicar qué invalida.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'corpus.dart';
import 'sha256.dart';

/// Lee los bytes de un asset. Debe lanzar si la ruta no existe.
///
/// Se inyecta en vez de llamar a `rootBundle` directamente para que las pruebas
/// puedan poner un archivo ausente, vacío o manipulado sin tocar el paquete.
typedef AssetBytesReader = Future<Uint8List> Function(String path);

/// Un corpus que el banco puede ejecutar, con su identidad fijada.
final class CorpusDescriptor {
  const CorpusDescriptor({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.expectedVersion,
    required this.expectedDigest,
    this.note = '',
  });

  /// Identificador estable que viaja en cada resultado exportado.
  final String id;

  /// Cómo se llama en la pantalla.
  final String label;

  final String assetPath;

  /// Versión que el archivo debe declarar.
  final String expectedVersion;

  /// SHA-256 de los bytes del archivo, en minúsculas.
  ///
  /// Es el mismo que devuelve `sha256sum` sobre el archivo del repositorio: el
  /// `.gitattributes` marca estos assets `-text` para que el checkout no
  /// cambie los fines de línea y el digest identifique el contenido y no la
  /// máquina.
  final String expectedDigest;

  final String note;
}

/// Los corpus versionados del banco.
abstract final class CorpusCatalog {
  /// El de la Fase 0, con el que se decidió `ADR-002`.
  ///
  /// Se conserva sin tocar para poder repetir aquellas mediciones. No sirve
  /// para el benchmark híbrido: se escribió antes de que existieran las
  /// categorías A–G y no tiene muestras sin habla.
  static const fase0 = CorpusDescriptor(
    id: 'fase0',
    label: 'Fase 0 histórica (100 frases)',
    assetPath: 'assets/corpus.json',
    expectedVersion: '1.0.0',
    expectedDigest:
        '7a891fd1a6aa2d9c4f122cc79a9f7fac646ce52f634bc51dcc59a7c9683f6b6b',
    note: 'Comparable con lo medido en el POCO. No cubre A–G ni el no-habla.',
  );

  /// El de la Fase 0-bis, con las siete categorías del plan híbrido.
  static const hibridoAG = CorpusDescriptor(
    id: 'hibrido-ag',
    label: 'Híbrido A–G (54 frases)',
    assetPath: 'assets/corpus_hybrid.json',
    expectedVersion: 'hybrid-1.0.0',
    expectedDigest:
        '52822895357baf2f9d207d346bef22b07970035d66103ec005609dfaefb00bd0',
    note: 'El único con el que C1, C3 y C4 son comparables entre sí.',
  );

  static const all = <CorpusDescriptor>[hibridoAG, fase0];

  static CorpusDescriptor? byId(String id) {
    for (final descriptor in all) {
      if (descriptor.id == id) return descriptor;
    }
    return null;
  }
}

/// Las tres partes en que se dicta un corpus.
///
/// Son una partición de verdad: disjuntas y, juntas, el corpus entero. Que el
/// no-habla salga de ajuste y de aceptación no lo convierte en una mezcla de
/// las dos: es la tanda técnica, se dicta aparte, y sus resultados no entran en
/// la misma tabla que las frases habladas.
enum BenchPartition {
  ajuste('ajuste', 'Ajuste'),
  aceptacion('aceptacion', 'Aceptación'),
  sinHabla('sin_habla', 'Técnicas / sin habla');

  const BenchPartition(this.id, this.label);

  /// Identificador que viaja en el resultado exportado.
  final String id;
  final String label;

  static BenchPartition? byId(String id) {
    for (final partition in values) {
      if (partition.id == id) return partition;
    }
    return null;
  }
}

/// Por qué un corpus no se puede ejecutar.
enum CorpusFailureKind {
  /// No hay ningún corpus con ese identificador.
  desconocido,

  /// El archivo no está en el paquete.
  ausente,

  /// El archivo está, y no tiene contenido.
  vacio,

  /// El archivo está, y no es el JSON esperado.
  ilegible,

  /// Los bytes no son los fijados.
  digestDistinto,

  /// El archivo declara otra versión.
  versionDistinta,

  /// El JSON es válido y no trae ninguna frase.
  sinMuestras,

  /// Dos frases comparten identificador.
  idDuplicado,

  /// Dos frases distintas dicen lo mismo dentro de la misma partición.
  fraseDuplicada,

  /// La misma frase aparece en ajuste y en aceptación.
  contaminacionEntreParticiones,
}

/// Un corpus que no puede usarse, con lo necesario para arreglarlo.
///
/// Lleva los dos valores en conflicto a propósito: «el digest no coincide» sin
/// decir cuál se esperaba y cuál se obtuvo obliga a adivinar desde el teléfono,
/// donde no hay herramientas.
final class CorpusLoadFailure implements Exception {
  const CorpusLoadFailure({
    required this.kind,
    required this.assetPath,
    required this.diagnostic,
    this.expected,
    this.actual,
  });

  final CorpusFailureKind kind;
  final String assetPath;

  /// Texto que se muestra en la pantalla, en español y sin jerga.
  final String diagnostic;

  final String? expected;
  final String? actual;

  @override
  String toString() => 'CorpusLoadFailure(${kind.name}): $diagnostic';
}

/// Un corpus leído y verificado. Que exista una instancia es la prueba de que
/// pasó todas las comprobaciones.
final class LoadedCorpus {
  const LoadedCorpus({
    required this.descriptor,
    required this.digest,
    required this.version,
    required this.corpus,
  });

  final CorpusDescriptor descriptor;

  /// El digest **calculado** sobre los bytes leídos, no el fijado.
  ///
  /// Coinciden siempre —si no, la carga habría fallado—, pero lo que se exporta
  /// es éste: lo que se midió, no lo que se esperaba medir.
  final String digest;

  /// La versión que declara el archivo leído.
  final String version;

  final Corpus corpus;

  /// Las frases de una partición, en el orden del archivo.
  List<CorpusSample> samplesOf(BenchPartition partition) => switch (partition) {
    BenchPartition.ajuste =>
      corpus.samples
          .where((s) => s.split == 'ajuste' && !s.isNonSpeech)
          .toList(growable: false),
    BenchPartition.aceptacion =>
      corpus.samples
          .where((s) => s.split == 'aceptacion' && !s.isNonSpeech)
          .toList(growable: false),
    BenchPartition.sinHabla =>
      corpus.samples.where((s) => s.isNonSpeech).toList(growable: false),
  };

  /// El corpus tiene frases en esa partición.
  ///
  /// La Fase 0 no tiene ninguna sin habla. Ofrecerla vacía y dejar grabar
  /// produciría una tanda de cero muestras que el informe leería después como
  /// «ninguna falsa afirmación».
  bool hasPartition(BenchPartition partition) =>
      samplesOf(partition).isNotEmpty;
}

/// Lee y verifica un corpus. No devuelve nunca uno distinto del pedido.
final class CorpusLoader {
  const CorpusLoader(this._read);

  final AssetBytesReader _read;

  /// Carga [descriptor] o lanza [CorpusLoadFailure].
  ///
  /// El orden importa. El digest se comprueba **antes** de interpretar el JSON:
  /// si los bytes no son los fijados, lo que diga su contenido no es evidencia
  /// de nada, y leerlo primero llevaría a informar «versión distinta» sobre un
  /// archivo que en realidad está cambiado entero.
  Future<LoadedCorpus> load(CorpusDescriptor descriptor) async {
    final Uint8List bytes;
    try {
      bytes = await _read(descriptor.assetPath);
    } on Object catch (e) {
      throw CorpusLoadFailure(
        kind: CorpusFailureKind.ausente,
        assetPath: descriptor.assetPath,
        diagnostic:
            'No se encontró ${descriptor.assetPath} en la aplicación. '
            'El APK no lleva ese corpus: no se puede medir con él. ($e)',
      );
    }

    if (bytes.isEmpty) {
      throw CorpusLoadFailure(
        kind: CorpusFailureKind.vacio,
        assetPath: descriptor.assetPath,
        diagnostic:
            '${descriptor.assetPath} está vacío. Un archivo de cero bytes no '
            'es un corpus sin frases: es un archivo roto.',
      );
    }

    final digest = sha256Hex(bytes);
    if (digest != descriptor.expectedDigest) {
      throw CorpusLoadFailure(
        kind: CorpusFailureKind.digestDistinto,
        assetPath: descriptor.assetPath,
        expected: descriptor.expectedDigest,
        actual: digest,
        diagnostic:
            'Los bytes de ${descriptor.assetPath} no son los fijados. '
            'Esperado ${descriptor.expectedDigest}, obtenido $digest. '
            'No se mide: si el corpus cambió hay que '
            'versionarlo y decir qué mediciones invalida.',
      );
    }

    final Corpus corpus;
    try {
      corpus = Corpus.fromJsonString(utf8.decode(bytes));
    } on Object catch (e) {
      throw CorpusLoadFailure(
        kind: CorpusFailureKind.ilegible,
        assetPath: descriptor.assetPath,
        diagnostic:
            'No se pudo interpretar ${descriptor.assetPath} como corpus. ($e)',
      );
    }

    if (corpus.corpusVersion != descriptor.expectedVersion) {
      throw CorpusLoadFailure(
        kind: CorpusFailureKind.versionDistinta,
        assetPath: descriptor.assetPath,
        expected: descriptor.expectedVersion,
        actual: corpus.corpusVersion,
        diagnostic:
            '${descriptor.assetPath} declara la versión '
            '«${corpus.corpusVersion}» y el banco espera '
            '«${descriptor.expectedVersion}».',
      );
    }

    if (corpus.samples.isEmpty) {
      throw CorpusLoadFailure(
        kind: CorpusFailureKind.sinMuestras,
        assetPath: descriptor.assetPath,
        diagnostic: '${descriptor.assetPath} no trae ninguna frase.',
      );
    }

    _checkDuplicates(descriptor, corpus);
    return LoadedCorpus(
      descriptor: descriptor,
      digest: digest,
      version: corpus.corpusVersion,
      corpus: corpus,
    );
  }

  void _checkDuplicates(CorpusDescriptor descriptor, Corpus corpus) {
    final vistos = <String, String>{};
    for (final sample in corpus.samples) {
      final anterior = vistos[sample.id];
      if (anterior != null) {
        throw CorpusLoadFailure(
          kind: CorpusFailureKind.idDuplicado,
          assetPath: descriptor.assetPath,
          diagnostic:
              'El identificador ${sample.id} aparece dos veces. Una frase '
              'medida dos veces bajo el mismo nombre no se puede separar '
              'después.',
        );
      }
      vistos[sample.id] = sample.id;
    }

    // Las muestras sin habla no tienen texto que comparar: todas coincidirían
    // entre sí. Se comprueban por identificador, que ya está hecho arriba.
    //
    // La misma frase puede aparecer dos veces dentro de un conjunto **si se
    // dicta bajo condiciones distintas**. El corpus de la Fase 0 lo hace a
    // propósito: `AC-046` en silencio y `AC-055` con ruido de campo son la
    // misma frase medida en dos entornos, y comparar sus resultados es
    // justamente el objetivo. Lo que no puede repetirse es la misma frase en
    // las mismas condiciones, que no mide nada nuevo y sólo infla la muestra.
    final porTexto = <String, List<CorpusSample>>{};
    for (final sample in corpus.samples) {
      if (sample.isNonSpeech) continue;
      final clave = normalizeSampleText(sample.text);
      final anteriores = porTexto.putIfAbsent(clave, () => <CorpusSample>[]);
      for (final anterior in anteriores) {
        if (anterior.split != sample.split) {
          throw CorpusLoadFailure(
            kind: CorpusFailureKind.contaminacionEntreParticiones,
            assetPath: descriptor.assetPath,
            diagnostic:
                '${sample.id} («${sample.split}») repite la frase de '
                '${anterior.id} («${anterior.split}»). Afinar con una frase y '
                'evaluarse con ella mide el ajuste, no el motor.',
          );
        }
        if (_sameConditions(anterior, sample)) {
          throw CorpusLoadFailure(
            kind: CorpusFailureKind.fraseDuplicada,
            assetPath: descriptor.assetPath,
            diagnostic:
                '${sample.id} repite la frase de ${anterior.id} dentro de '
                '«${sample.split}» y en las mismas condiciones '
                '(${_conditionsLabel(sample)}). Dictarla dos veces así infla '
                'la muestra sin medir nada nuevo.',
          );
        }
      }
      anteriores.add(sample);
    }
  }

  /// Las dos muestras se dictarían en el mismo entorno.
  static bool _sameConditions(CorpusSample a, CorpusSample b) {
    final ca = a.conditions.toSet();
    final cb = b.conditions.toSet();
    return ca.length == cb.length && ca.containsAll(cb);
  }

  static String _conditionsLabel(CorpusSample sample) =>
      sample.conditions.isEmpty
      ? 'sin condiciones'
      : sample.conditions.join(', ');
}

/// Forma canónica de una frase para detectar repeticiones.
///
/// Ignora mayúsculas, tildes, puntuación y espacios repetidos, porque mover una
/// frase de un conjunto a otro cambiándole una coma seguiría siendo la misma
/// frase dictada. No toca los números: `12` y `doce` se pronuncian distinto y
/// son muestras distintas.
String normalizeSampleText(String text) {
  const acentos = <String, String>{
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
  };
  final plegado = text
      .toLowerCase()
      .split('')
      .map((c) => acentos[c] ?? c)
      .join();
  return plegado
      .replaceAll(RegExp(r'[^a-z0-9ñ ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
