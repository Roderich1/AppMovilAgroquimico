/// Se niega a comparar mediciones que no son comparables.
///
/// HERRAMIENTA DE DESARROLLO. Vive en `tool/` y no se compila dentro de la
/// aplicación.
///
/// ## Por qué existe
///
/// El informe pone dos motores en la misma tabla y el propietario lee una
/// columna al lado de la otra. Eso significa algo sólo si las dos salieron del
/// mismo corpus, la misma versión, los mismos bytes, la misma partición y el
/// mismo modelo.
///
/// C1 se midió entero con el corpus de la Fase 0 mientras el plan pedía A–G,
/// porque la pantalla del banco decía «Corpus» sobre un menú que elegía la
/// partición. Sin esta guarda, esos números habrían entrado en la misma tabla
/// que C3 y C4 y la diferencia se habría leído como diferencia entre motores.
///
/// ## Cómo identifica un candidato mal etiquetado
///
/// No lleva una copia del registro de candidatos del banco. Una tabla duplicada
/// en dos paquetes se desincroniza y la guarda acabaría rechazando corridas
/// buenas. Comprueba una propiedad que no necesita tabla: dentro de lo que se
/// va a comparar, cada `candidateId` corresponde a un solo motor y cada motor a
/// un solo `candidateId`. Si `C1` aparece una vez como Vosk y otra como
/// Whisper, una de las dos está mal, sea cual sea la tabla.
library;

import 'result_parser.dart';

/// Por qué dos mediciones no se pueden poner en la misma tabla.
enum ComparisonReason {
  /// Unas traen identidad de corpus y otras no.
  identidadAusente,

  /// Corpus distinto.
  corpusId,

  /// El mismo corpus en dos versiones.
  corpusVersion,

  /// La misma versión con bytes distintos. Es el caso peligroso: alguien
  /// corrigió una frase «sin cambiar la versión».
  corpusDigest,

  /// Ajuste contra aceptación, o cualquiera de las dos contra el no-habla.
  partition,

  /// Configuración que cambia lo que el motor hace: locale solicitado.
  configuracionCritica,

  /// El mismo candidato con modelos distintos.
  modelo,

  /// Un candidato que no corresponde a su motor.
  candidato,
}

/// Un motivo concreto de rechazo, con los valores en conflicto.
final class ComparisonRejection {
  const ComparisonRejection(this.reason, this.detail);

  final ComparisonReason reason;

  /// Qué valores chocan, para poder arreglarlo sin abrir los archivos.
  final String detail;

  @override
  String toString() => '${reason.name}: $detail';
}

/// Qué se puede y qué no se puede comparar en un conjunto de mediciones.
final class ComparisonVerdict {
  const ComparisonVerdict({
    required this.rejections,
    required this.identityMissing,
  });

  final List<ComparisonRejection> rejections;

  /// Ninguna medición trae identidad de corpus.
  ///
  /// Son las tandas de la Fase 0, exportadas antes de que estos campos
  /// existieran. Siguen siendo válidas como historia y el informe las marca:
  /// lo que no pueden es entrar en la misma tabla que una corrida nueva.
  final bool identityMissing;

  bool get comparable => rejections.isEmpty;
}

abstract final class ComparisonGuard {
  /// Decide si [records] pueden compararse entre sí.
  ///
  /// Las razones se agrupan por eje. Dentro del eje del corpus se informa la
  /// primera diferencia y no las tres: si el corpus ya es otro, añadir «y
  /// además la versión difiere» no ayuda a nadie. Ejes distintos —corpus,
  /// partición, configuración, modelo, candidato— se informan todos, porque
  /// arreglar uno no arregla el otro.
  static ComparisonVerdict check(List<BenchRecord> records) {
    if (records.length < 2) {
      return ComparisonVerdict(
        rejections: const [],
        identityMissing: records.isNotEmpty && !_hasIdentity(records.first),
      );
    }

    final withIdentity = records.where(_hasIdentity).toList();
    final withoutIdentity = records.where((r) => !_hasIdentity(r)).toList();

    if (withIdentity.isNotEmpty && withoutIdentity.isNotEmpty) {
      return ComparisonVerdict(
        rejections: [
          ComparisonRejection(
            ComparisonReason.identidadAusente,
            '${withoutIdentity.length} mediciones no dicen de qué corpus '
            'salieron y ${withIdentity.length} sí '
            '(${_distinct(withIdentity, (r) => r.corpusId)}). Una corrida '
            'anterior a la identidad de corpus no puede ponerse al lado de '
            'una nueva: no hay forma de saber si midieron lo mismo.',
          ),
        ],
        identityMissing: false,
      );
    }

    if (withIdentity.isEmpty) {
      // Todas históricas. Se dejan pasar y el informe lo dice; rechazarlas
      // impediría regenerar el informe de la Fase 0, que sigue siendo válido.
      return const ComparisonVerdict(rejections: [], identityMissing: true);
    }

    final rejections = <ComparisonRejection>[];

    // --- eje del corpus: la primera diferencia, en orden de gravedad.
    final ejeCorpus =
        <(ComparisonReason, String, String Function(BenchRecord))>[
          (ComparisonReason.corpusId, 'corpus', (r) => r.corpusId),
          (ComparisonReason.corpusVersion, 'versión', (r) => r.corpusVersion),
          (ComparisonReason.corpusDigest, 'digest', (r) => r.corpusDigest),
        ];
    for (final (reason, etiqueta, valor) in ejeCorpus) {
      final valores = _distinctSet(withIdentity, valor);
      if (valores.length > 1) {
        rejections.add(
          ComparisonRejection(
            reason,
            'Se mezclan $valores en el $etiqueta del corpus.',
          ),
        );
        break;
      }
    }

    // --- eje de la partición.
    final particiones = _distinctSet(withIdentity, (r) => r.partition);
    if (particiones.length > 1) {
      rejections.add(
        ComparisonRejection(
          ComparisonReason.partition,
          'Se mezclan las particiones $particiones. Ajuste y aceptación miden '
          'cosas distintas, y el no-habla no es una tanda hablada.',
        ),
      );
    }

    // --- eje de la configuración crítica.
    final locales = _distinctSet(
      withIdentity.where((r) => r.requestedLocale.isNotEmpty),
      (r) => r.requestedLocale,
    );
    if (locales.length > 1) {
      rejections.add(
        ComparisonRejection(
          ComparisonReason.configuracionCritica,
          'Se pidieron locales distintos: $locales.',
        ),
      );
    }

    // --- eje del modelo: un candidato, un juego de modelos.
    final modelosPorCandidato = <String, Set<String>>{};
    for (final record in withIdentity) {
      modelosPorCandidato
          .putIfAbsent(_candidateKey(record), () => <String>{})
          .add(_modelKey(record));
    }
    for (final entry in modelosPorCandidato.entries) {
      if (entry.value.length > 1) {
        rejections.add(
          ComparisonRejection(
            ComparisonReason.modelo,
            'El candidato ${entry.key} aparece con modelos distintos: '
            '${entry.value}.',
          ),
        );
      }
    }

    // --- eje del candidato: correspondencia uno a uno con el motor.
    final motoresPorCandidato = <String, Set<String>>{};
    final candidatosPorMotor = <String, Set<String>>{};
    for (final record in withIdentity) {
      motoresPorCandidato
          .putIfAbsent(_candidateKey(record), () => <String>{})
          .add(record.engine);
      candidatosPorMotor
          .putIfAbsent(record.engine, () => <String>{})
          .add(_candidateKey(record));
    }
    for (final entry in motoresPorCandidato.entries) {
      if (entry.value.length > 1) {
        rejections.add(
          ComparisonRejection(
            ComparisonReason.candidato,
            'El candidato ${entry.key} aparece con más de un motor: '
            '${entry.value}. Uno de los dos está mal etiquetado.',
          ),
        );
      }
    }
    for (final entry in candidatosPorMotor.entries) {
      if (entry.value.length > 1) {
        rejections.add(
          ComparisonRejection(
            ComparisonReason.candidato,
            'El motor ${entry.key} aparece bajo más de un candidato: '
            '${entry.value}.',
          ),
        );
      }
    }

    return ComparisonVerdict(rejections: rejections, identityMissing: false);
  }

  /// La medición dice de qué corpus salió.
  static bool _hasIdentity(BenchRecord record) => record.corpusId.isNotEmpty;

  static String _candidateKey(BenchRecord record) =>
      record.candidateId.isEmpty ? '(sin candidato)' : record.candidateId;

  /// Forma estable del juego de modelos, para poder comparar dos mapas.
  static String _modelKey(BenchRecord record) {
    final entries =
        record.modelHashes.entries.map((e) => '${e.key}=${e.value}').toList()
          ..sort();
    return entries.join(';');
  }

  static Set<String> _distinctSet(
    Iterable<BenchRecord> records,
    String Function(BenchRecord) of,
  ) => records.map(of).toSet();

  static String _distinct(
    Iterable<BenchRecord> records,
    String Function(BenchRecord) of,
  ) => (records.map(of).toSet().toList()..sort()).join(', ');
}
