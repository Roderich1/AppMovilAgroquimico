/// Piezas comunes del dictado de compra, planificación y aplicación (#16):
/// las pistas de vocabulario de cada motor, el texto cerrado nuevo de una
/// sesión y los auxiliares de valores dichos. (Las pantallas de borrador por
/// voz se retiraron en el formulario único, F09: la voz completa los
/// formularios normales.)
library;

import '../../domain/money.dart' show baseUnitsPerMajor;
import '../../domain/numeric_input.dart' show formatForInput;
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/text/units.dart';
import '../../voice_draft/core/draft_field.dart';

/// Lleva la cuenta del texto cerrado ya interpretado de una sesión de voz y
/// entrega **sólo lo nuevo**. Lo provisional nunca pasa por aquí: sólo el
/// texto que la sesión ya cerró (`committedText`).
/// Nombres que pueden dictarse en este borrador, como pista de vocabulario
/// para el reconocimiento local: productos, personas, proveedores, chacos y
/// la campaña activa. Sólo nombres; sin cantidades ni importes.
List<String> voiceVocabularyHints(VoiceCatalog catalog) {
  final seen = <String>{};
  return [
    for (final entry in [
      ...catalog.products,
      ...catalog.people,
      ...catalog.suppliers,
      ...catalog.farms,
      if (catalog.activeCampaign != null) catalog.activeCampaign!,
    ])
      if (seen.add(entry.name.trim().toLowerCase())) entry.name.trim(),
  ];
}

/// Términos del dominio para el experimento de contexto de Whisper (F09,
/// 2026-11-09): monedas, unidades y vocabulario agrícola. Son los mismos para
/// todos, no llevan cantidades, precios ni frases, y no son instrucciones.
const voiceDomainTerms = <String>[
  'bolivianos',
  'dólares',
  'litro',
  'litros',
  'kilo',
  'kilos',
  'hectárea',
  'hectáreas',
  'herbicida',
  'fungicida',
  'insecticida',
  'proveedor',
];

/// Pista de dominio y catálogo: primero los términos del dominio (así no los
/// corta el tope de longitud) y después los nombres del catálogo de **esta**
/// cuenta, sin repetir. Se construye siempre igual a partir del catálogo.
List<String> voiceDomainContextHints(VoiceCatalog catalog) {
  final seen = <String>{};
  return [
    for (final term in [...voiceDomainTerms, ...voiceVocabularyHints(catalog)])
      if (seen.add(term.trim().toLowerCase())) term.trim(),
  ];
}

/// Pista del **turno entero** de la compra (F09, 2026-11-10): vocabulario
/// breve y pertinente, en este orden:
///
/// 1. los productos del catálogo de **esta** cuenta (sólo nombres);
/// 2. las unidades de esos productos (litro / kilo);
/// 3. las monedas que la app admite (bolivianos, dólares);
/// 4. expresiones de precio unitario y total («por litro», «el litro», «en
///    total», «por un total de»).
///
/// Sin cantidades, precios, frases de casos, proveedores, personas, chacos
/// ni nada de un dictado anterior. Cada producto aparece una vez: la pista
/// orienta, no elige; el intérprete sigue sin aproximar nombres.
List<String> voicePurchaseTurnHints(VoiceCatalog catalog) {
  final units = {for (final p in catalog.products) p.unit}
      .whereType<CatalogUnit>();
  final hasLiter = units.contains(CatalogUnit.liter);
  final hasKilo = units.contains(CatalogUnit.kilogram);
  final seen = <String>{};
  return [
    for (final term in [
      for (final p in catalog.products) p.name,
      if (hasLiter) ...['litro', 'litros'],
      if (hasKilo) ...['kilo', 'kilos'],
      'bolivianos',
      'dólares',
      if (hasLiter) ...['por litro', 'el litro'],
      if (hasKilo) ...['por kilo', 'el kilo'],
      'en total',
      'por un total de',
    ])
      if (term.trim().isNotEmpty && seen.add(term.trim().toLowerCase()))
        term.trim(),
  ];
}

class VoiceSegmentFeed {
  String _consumed = '';

  /// Texto cerrado nuevo desde la última vez, o `null`. Si [ready] es falso
  /// (el borrador aún carga), no consume nada y lo entregará después.
  String? take(String committed, {required bool ready}) {
    if (!committed.startsWith(_consumed)) {
      // La sesión se descartó o se reinició: se sigue desde su texto actual.
      _consumed = committed;
      return null;
    }
    if (!ready || committed.length <= _consumed.length) return null;
    final fresh = committed.substring(_consumed.length).trim();
    _consumed = committed;
    return fresh.isEmpty ? null : fresh;
  }
}

/// Lo que deja un toque en el selector sobre [current]: elegir **otra**
/// opción es una corrección a mano; tocar la que ya estaba elegida sólo la
/// confirma (POCO 2026-11-08: «Corregido a mano» sin haber cambiado nada). Lo
/// que ya puso o confirmó la persona queda como estaba.
DraftField<T> pickEntry<T extends Object>(DraftField<T> current, T entry) {
  final same = current.value == entry && (current.isResolved || current.review);
  if (!same) return DraftField.resolved(entry, origin: FieldOrigin.manual);
  return current.isManual ? current : current.confirmedByUser();
}

/// Cantidad dicha en unidad base (ML o G) de su propia familia, sin depender
/// del producto: «un litro» → 1000, «500 ml» → 500. `null` si no es un entero
/// de ML o G mayor que cero.
int? spokenBase(int thousandths, SpokenUnit unit) {
  final base = unit.toBase(thousandths);
  return base == null || base <= 0 ? null : base;
}

/// Texto de un campo de cantidad: el valor leído, normalizado a L o KG
/// («1», «0,5»), aunque el producto aún no esté elegido; si no hay valor
/// utilizable, lo oído tal cual.
String spokenAmountText(int? base, String? heard) =>
    base == null ? (heard ?? '') : formatForInput(base / baseUnitsPerMajor);

/// Unidad en que se escribe una cantidad de la línea: la del producto si se
/// conoce; si no, la de lo dicho; si nada, litros.
CatalogUnit lineUnit(DraftField<CatalogEntry> product, SpokenUnit? spoken) =>
    product.value?.unit ?? spoken?.family ?? CatalogUnit.liter;

/// Aclaración o problema de unidad para una cantidad con valor (POCO
/// 2026-11-08, dosis con el producto pendiente): sin producto, la unidad aún
/// no se comprobó; con un producto de otra unidad, no se puede registrar.
({String? note, String? problem}) unitCheck({
  required DraftField<CatalogEntry> product,
  required SpokenUnit? spoken,
  String suffix = '',
}) {
  if (spoken == null) return (note: null, problem: null);
  final said = '${spoken.family.code}$suffix';
  final unit = product.isResolved ? product.value?.unit : null;
  if (unit == null) {
    return (
      note: 'En $said; falta elegir el producto para comprobar su unidad.',
      problem: null,
    );
  }
  if (unit != spoken.family) {
    return (
      note: null,
      problem:
          'La cifra está en $said, pero el producto se mide en '
          '${unit.code}$suffix: corrija la cifra o el producto.',
    );
  }
  return (note: null, problem: null);
}
