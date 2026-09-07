/// Comparación entre lo que oyó cada motor del candidato híbrido.
///
/// ## La regla que gobierna este archivo
///
/// **No se fabrica una tercera transcripción.** No se mezclan palabras de los
/// dos motores, no se vota por mayoría y no se elige "la mejor" por longitud o
/// por confianza. Se conservan los dos textos tal como llegaron, se señala en
/// qué datos críticos no coinciden y **decide el usuario**.
///
/// El motivo no es purismo: en la Fase 0, la misma frase dictada dos veces dio
/// `12` y `dos` como cantidad (`RISK-027`). Un algoritmo que eligiera solo
/// acertaría a veces y se equivocaría en silencio el resto, sobre cantidades y
/// montos de dinero. Marcar y preguntar es la única política que no puede
/// producir un dato inventado.
///
/// ## Reparto de papeles
///
/// * **Vosk** produce el parcial visible mientras se habla. Nunca es
///   autoritativo y nunca dispara nada.
/// * **Whisper** produce el **final propuesto**.
/// * Este comparador no cambia ninguno de los dos: sólo los describe.
///
/// ## Qué normaliza, y qué no
///
/// Normaliza **sólo formato superficial**: mayúsculas, tildes, signos de
/// puntuación y espacios repetidos. Eso permite ver que «Bellator.» y
/// «bellator» son la misma palabra.
///
/// **No convierte palabras a números.** «doce» no se transforma en `12`. Si un
/// motor dice `12` y el otro «dos», eso es exactamente la discrepancia que hay
/// que enseñar, y convertir una forma en otra la escondería o inventaría una
/// equivalencia que nadie midió.
///
/// ## Lo que este archivo nunca hace
///
/// No navega, no escribe, no toca el negocio y no acepta nada por su cuenta.
/// Produce una descripción; el banco la registra y la persona decide.
library;

/// De qué motor viene un texto.
enum TranscriptEngine {
  vosk,
  whisper,
  androidSpeech;

  String get label => switch (this) {
    TranscriptEngine.vosk => 'Vosk',
    TranscriptEngine.whisper => 'Whisper',
    TranscriptEngine.androidSpeech => 'Android',
  };
}

/// Un texto tal como lo entregó un motor, con lo que se sabe de él.
final class EngineTranscript {
  const EngineTranscript({
    required this.engine,
    required this.text,
    this.elapsedMs,
    this.flags = const [],
  });

  final TranscriptEngine engine;

  /// El texto **sin tocar**. La normalización es interna a la comparación.
  final String text;

  /// Milisegundos hasta este resultado. `null` si no se midió.
  final int? elapsedMs;

  /// Marcas de calidad del motor: `noSpeech`, `possibleHallucination`,
  /// `degenerateRepetition`, `lowSpeechRatio`, `whisperUnusable`.
  final List<String> flags;

  bool get isEmpty => text.trim().isEmpty;

  Map<String, Object?> toJson() => {
    'engine': engine.name,
    'text': text,
    'elapsedMs': elapsedMs,
    'flags': flags,
  };
}

/// Clase de dato crítico. Sólo estas disparan discrepancia.
///
/// Una diferencia en una muletilla no importa; una diferencia en una cantidad,
/// un precio o un nombre de producto cambia lo que se registraría.
enum CriticalTokenKind {
  /// Contiene cifras: `12`, `186`, `1.500,25`.
  digitos,

  /// Número dicho con letras: `doce`, `ciento`, `mil`. **No se convierte** a
  /// cifras; se compara como palabra.
  numeroEnPalabras,

  /// `litro`, `kilo`, `unidad` y sus plurales.
  unidad,

  /// `bolivianos`, `bs`, `dólares`, `usd`.
  moneda,

  /// Producto, persona, chaco o proveedor: el vocabulario que aporta la muestra
  /// del corpus. Sin ese vocabulario esta clase no se usa, porque adivinar
  /// nombres propios por la mayúscula no funciona: Vosk devuelve todo en
  /// minúsculas.
  terminoDeCatalogo;

  String get label => switch (this) {
    CriticalTokenKind.digitos => 'cifras',
    CriticalTokenKind.numeroEnPalabras => 'números en palabras',
    CriticalTokenKind.unidad => 'unidades',
    CriticalTokenKind.moneda => 'moneda',
    CriticalTokenKind.terminoDeCatalogo => 'catálogo',
  };
}

/// Un desacuerdo concreto entre los dos motores.
///
/// Lleva **las dos alternativas completas**, no una elegida: si uno dijo `12` y
/// el otro `dos`, se muestran ambas.
final class CriticalDisagreement {
  const CriticalDisagreement({
    required this.kind,
    required this.left,
    required this.right,
  });

  final CriticalTokenKind kind;

  /// Los tokens de esa clase según el primer motor, en orden de aparición.
  final List<String> left;

  /// Los del segundo motor.
  final List<String> right;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'left': left,
    'right': right,
  };

  @override
  String toString() => '${kind.label}: ${left.join(' ')} | ${right.join(' ')}';
}

/// El resultado de comparar los dos motores sobre una misma captura.
final class HybridComparison {
  const HybridComparison({
    required this.partial,
    required this.proposed,
    required this.disagreements,
    required this.flags,
  });

  /// Lo que mostró Vosk en vivo. `null` si el candidato no tiene parcial.
  final EngineTranscript? partial;

  /// El final propuesto. Normalmente Whisper.
  final EngineTranscript? proposed;

  /// En qué datos críticos no coinciden.
  final List<CriticalDisagreement> disagreements;

  /// Marcas agregadas de los dos motores más las que añade la comparación.
  final List<String> flags;

  bool get hasCriticalDisagreement => disagreements.isNotEmpty;

  /// No hubo habla utilizable por ningún camino.
  bool get isNoSpeech => flags.contains(flagNoSpeech);

  /// Las marcas que **impiden** aceptar sin revisión.
  ///
  /// [flagIdentical] no está: que los dos motores digan exactamente lo mismo es
  /// la mejor señal posible, no una advertencia. Tratarla como tal habría hecho
  /// que el caso bueno pidiera revisión igual que el malo, y entonces la
  /// revisión no distinguiría nada.
  List<String> get blockingFlags =>
      flags.where((f) => f != flagIdentical).toList(growable: false);

  /// El texto puede proponerse sin pedir revisión.
  ///
  /// Falso ante silencio, ante cualquier marca de sospecha y ante cualquier
  /// discrepancia crítica. **Nunca** se acepta algo automáticamente por el
  /// hecho de que un motor haya devuelto letras.
  bool get isAcceptableWithoutReview =>
      proposed != null &&
      !proposed!.isEmpty &&
      blockingFlags.isEmpty &&
      disagreements.isEmpty;

  Map<String, Object?> toJson() => {
    'partial': partial?.toJson(),
    'proposed': proposed?.toJson(),
    'disagreements': [for (final d in disagreements) d.toJson()],
    'flags': flags,
    'blockingFlags': blockingFlags,
    'hasCriticalDisagreement': hasCriticalDisagreement,
    'acceptableWithoutReview': isAcceptableWithoutReview,
  };

  /// No hubo habla en ninguno de los dos motores.
  static const flagNoSpeech = 'noSpeech';

  /// Los dos coinciden palabra por palabra tras normalizar el formato.
  static const flagIdentical = 'identical';

  /// Discrepan en algún dato crítico.
  static const flagCriticalDisagreement = 'criticalDisagreement';

  /// Sólo uno de los dos produjo texto.
  static const flagSingleEngine = 'singleEngine';
}

/// Compara dos transcripciones de la misma captura.
///
/// [catalogTerms] son los términos de catálogo relevantes para esta muestra
/// —producto, persona, chaco, proveedor—, que aporta el corpus. Sin ellos la
/// comparación sigue funcionando sobre cifras, unidades y moneda.
HybridComparison compareTranscripts({
  EngineTranscript? partial,
  EngineTranscript? proposed,
  Iterable<String> catalogTerms = const [],
}) {
  final flags = <String>{...?partial?.flags, ...?proposed?.flags};

  final partialEmpty = partial == null || partial.isEmpty;
  final proposedEmpty = proposed == null || proposed.isEmpty;

  if (partialEmpty && proposedEmpty) {
    // Silencio o ruido. Nunca es texto aceptable.
    flags.add(HybridComparison.flagNoSpeech);
    return HybridComparison(
      partial: partial,
      proposed: proposed,
      disagreements: const [],
      flags: flags.toList()..sort(),
    );
  }

  if (partialEmpty || proposedEmpty) {
    // Con un solo texto no hay nada que contrastar. Se dice, en vez de dar la
    // coincidencia por buena.
    flags.add(HybridComparison.flagSingleEngine);
    return HybridComparison(
      partial: partial,
      proposed: proposed,
      disagreements: const [],
      flags: flags.toList()..sort(),
    );
  }

  final catalog = {
    for (final term in catalogTerms)
      for (final word in _normalize(term).split(' '))
        if (word.length > 2) word,
  };

  final disagreements = <CriticalDisagreement>[];
  for (final kind in CriticalTokenKind.values) {
    final left = _criticalTokens(partial.text, kind, catalog);
    final right = _criticalTokens(proposed.text, kind, catalog);
    if (!_sameMultiset(left, right)) {
      disagreements.add(
        CriticalDisagreement(kind: kind, left: left, right: right),
      );
    }
  }

  if (disagreements.isNotEmpty) {
    flags.add(HybridComparison.flagCriticalDisagreement);
  } else if (_normalize(partial.text) == _normalize(proposed.text)) {
    flags.add(HybridComparison.flagIdentical);
  }

  return HybridComparison(
    partial: partial,
    proposed: proposed,
    disagreements: disagreements,
    flags: flags.toList()..sort(),
  );
}

// --------------------------------------------------------------- normalización

/// Formato superficial y nada más: minúsculas, sin tildes, sin puntuación de
/// separación y sin espacios repetidos.
///
/// **No toca las cifras.** `1.500,25` conserva sus separadores porque cambiarlos
/// cambiaría el número.
String _normalize(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final folded = _accents[char] ?? char;
    if (_isWordChar(folded) || folded == ' ') {
      buffer.write(folded);
    } else if (_isNumberPunctuation(folded)) {
      buffer.write(folded);
    } else {
      buffer.write(' ');
    }
  }
  return buffer
      .toString()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map(_trimNumberPunctuation)
      .where((w) => w.isNotEmpty)
      .join(' ');
}

bool _isWordChar(String c) {
  final code = c.codeUnitAt(0);
  final isLetter = code >= 0x61 && code <= 0x7A;
  final isDigit = code >= 0x30 && code <= 0x39;
  return isLetter || isDigit || c == 'ñ';
}

/// `.` y `,` sólo sobreviven **dentro** de una cifra.
bool _isNumberPunctuation(String c) => c == '.' || c == ',';

String _trimNumberPunctuation(String word) {
  var result = word;
  while (result.isNotEmpty && _isNumberPunctuation(result[0])) {
    result = result.substring(1);
  }
  while (result.isNotEmpty && _isNumberPunctuation(result[result.length - 1])) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

const _accents = {
  'á': 'a',
  'é': 'e',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'ü': 'u',
  'à': 'a',
  'è': 'e',
  'ì': 'i',
  'ò': 'o',
  'ù': 'u',
};

// ------------------------------------------------------------ tokens críticos

List<String> _criticalTokens(
  String text,
  CriticalTokenKind kind,
  Set<String> catalog,
) {
  final words = _normalize(text).split(' ').where((w) => w.isNotEmpty);
  return [
    for (final word in words)
      if (_isKind(word, kind, catalog)) word,
  ];
}

bool _isKind(String word, CriticalTokenKind kind, Set<String> catalog) =>
    switch (kind) {
      CriticalTokenKind.digitos => word.contains(RegExp(r'[0-9]')),
      CriticalTokenKind.numeroEnPalabras => _numberWords.contains(word),
      CriticalTokenKind.unidad => _unitWords.contains(word),
      CriticalTokenKind.moneda => _currencyWords.contains(word),
      CriticalTokenKind.terminoDeCatalogo => catalog.contains(word),
    };

bool _sameMultiset(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final left = [...a]..sort();
  final right = [...b]..sort();
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

/// Números dichos con letras. Se comparan **como palabras**: aquí no se
/// convierte nada a cifras.
const _numberWords = <String>{
  'cero',
  'un',
  'uno',
  'una',
  'dos',
  'tres',
  'cuatro',
  'cinco',
  'seis',
  'siete',
  'ocho',
  'nueve',
  'diez',
  'once',
  'doce',
  'trece',
  'catorce',
  'quince',
  'dieciseis',
  'diecisiete',
  'dieciocho',
  'diecinueve',
  'veinte',
  'veintiuno',
  'veintidos',
  'veintitres',
  'veinticuatro',
  'veinticinco',
  'veintiseis',
  'veintisiete',
  'veintiocho',
  'veintinueve',
  'treinta',
  'cuarenta',
  'cincuenta',
  'sesenta',
  'setenta',
  'ochenta',
  'noventa',
  'cien',
  'ciento',
  'doscientos',
  'trescientos',
  'cuatrocientos',
  'quinientos',
  'seiscientos',
  'setecientos',
  'ochocientos',
  'novecientos',
  'mil',
  'millon',
  'millones',
  'media',
  'medio',
  'mitad',
};

const _unitWords = <String>{
  'litro',
  'litros',
  'kilo',
  'kilos',
  'kilogramo',
  'kilogramos',
  'gramo',
  'gramos',
  'unidad',
  'unidades',
  'bidon',
  'bidones',
  'bolsa',
  'bolsas',
  'caja',
  'cajas',
  'hectarea',
  'hectareas',
};

const _currencyWords = <String>{
  'boliviano',
  'bolivianos',
  'bs',
  'bob',
  'dolar',
  'dolares',
  'usd',
};
