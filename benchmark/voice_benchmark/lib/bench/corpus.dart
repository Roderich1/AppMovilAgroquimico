import 'dart:convert';

/// Una frase del corpus de evaluación.
///
/// El corpus es **texto**: no contiene ni referencia grabaciones de personas
/// reales. Personas, proveedores y chacos son ficticios. Quien ejecuta la prueba
/// lee la frase en voz alta; por eso el texto lleva ortografía española real.
final class CorpusSample {
  const CorpusSample({
    required this.id,
    required this.split,
    required this.intent,
    required this.text,
    required this.expected,
    required this.slots,
    required this.conditions,
    required this.tags,
    this.note,
  });

  factory CorpusSample.fromJson(Map<String, Object?> json) => CorpusSample(
    id: json['id'] as String,
    split: json['split'] as String,
    intent: json['intent'] as String,
    text: json['text'] as String,
    expected: json['expected'] as String,
    slots: (json['slots'] as Map).cast<String, Object?>().map(
      (k, v) => MapEntry(k, '$v'),
    ),
    conditions: _stringList(json['conditions']),
    tags: _stringList(json['tags']),
    note: json['note'] as String?,
  );

  /// Identificador estable, por ejemplo `AC-012`.
  final String id;

  /// `ajuste` o `aceptacion`. El corpus de aceptación no se usa para afinar.
  final String split;

  /// `compra`, `aplicacion`, `pago`, `fuera_de_alcance` o `mezclada`.
  final String intent;

  /// Lo que se dicta.
  final String text;

  /// `listo`, `incompleto`, `ambiguo` o `rechazado`.
  ///
  /// No lo decide el motor de voz: es lo que el draft tipado de `EVO-010`
  /// deberá concluir. Aquí sirve para clasificar la muestra.
  final String expected;

  /// Datos críticos esperados. `AMBIGUO` marca los que deben bloquearse.
  final Map<String, String> slots;

  /// Condiciones de ejecución: `silencio`, `ruido`, `pausas`, `habla_rapida`,
  /// `correccion`.
  final List<String> conditions;

  final List<String> tags;

  final String? note;

  /// La muestra exige un dato crítico que **no** debe autoresolverse.
  bool get hasBlockingAmbiguity => slots.values.contains('AMBIGUO');

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.map((e) => '$e').toList(growable: false);
  }
}

/// El corpus completo.
final class Corpus {
  const Corpus({
    required this.corpusVersion,
    required this.locale,
    required this.samples,
  });

  factory Corpus.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    return Corpus(
      corpusVersion: json['corpusVersion'] as String? ?? 'desconocida',
      locale: json['locale'] as String? ?? 'es-BO',
      samples: (json['samples'] as List)
          .map((e) => CorpusSample.fromJson((e as Map).cast<String, Object?>()))
          .toList(growable: false),
    );
  }

  final String corpusVersion;
  final String locale;
  final List<CorpusSample> samples;

  List<CorpusSample> get ajuste =>
      samples.where((s) => s.split == 'ajuste').toList(growable: false);

  List<CorpusSample> get aceptacion =>
      samples.where((s) => s.split == 'aceptacion').toList(growable: false);

  /// Muestras de un `split`, o todas si [split] es `null`.
  List<CorpusSample> bySplit(String? split) => split == null
      ? samples
      : samples.where((s) => s.split == split).toList(growable: false);
}
