/// «Usar la otra propuesta» (diagnóstico, política B, 2026-11-09).
///
/// Una frase dictada aportó al borrador lo que interpretó su texto (el de un
/// motor). Esto planifica **sustituir sólo esa aportación** por la del otro
/// motor, sin mezclar textos y sin suponer:
///
/// * Se interpreta el texto **completo** del otro motor sobre el borrador de
///   **antes** de la frase, con las mismas marcas de revisión.
/// * Campo a campo, sólo se cambia lo que la frase dejó y **nadie ha tocado
///   después**: lo corregido o confirmado a mano y lo que aportaron otras
///   frases se conserva tal cual.
/// * Las líneas que creó la frase se emparejan por orden con las que crearía
///   la otra propuesta. Una línea creada por la frase que ya no está (se
///   quitó) o que se tocó después y la otra propuesta no crearía, o una línea
///   nueva que quedaría repetida con otra, **bloquean** la sustitución: no se
///   puede decidir sin suponer y se ofrece corregir a mano.
///
/// No escribe nada: devuelve el borrador resultante y un resumen para la
/// vista previa. Aplicarlo es una acción explícita aparte.
library;

import 'package:flutter/material.dart';

import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/purchase/voice_purchase_draft.dart';

/// Lo que aportó una frase al borrador, para poder sustituirlo.
final class TurnContribution {
  TurnContribution({
    required this.turn,
    required this.seq,
    required this.before,
    required this.after,
    this.disagreed = false,
    this.conflict = const {},
    this.single = const {},
  });

  /// La frase llegó con desacuerdo entre motores y sus campos por revisar
  /// (regla A: todos; política B: [conflict] y [single]). La otra propuesta
  /// se marca igual: los conflictos siguen pendientes.
  final bool disagreed;
  final Set<String> conflict;
  final Set<String> single;

  /// Se ofreció: la otra propuesta trae algún dato que faltaba.
  bool offered = false;

  /// Identidad estable de la frase (turno del motor y número de frase).
  final int turn;
  final int seq;

  /// Borrador justo antes y justo después de aplicar la frase.
  final VoicePurchaseDraft before;
  final VoicePurchaseDraft after;

  /// Ya se sustituyó: no se vuelve a ofrecer ni a aplicar.
  bool used = false;

  String get key => '$turn:$seq';
}

/// Resultado de planificar la sustitución.
final class AlternativePlan {
  const AlternativePlan.blocked(this.reason)
    : draft = null,
      recovered = const [],
      changed = const [],
      pending = const [],
      kept = const [],
      added = const [],
      mayRepeat = false;

  const AlternativePlan({
    required VoicePurchaseDraft this.draft,
    required this.recovered,
    required this.changed,
    required this.pending,
    required this.kept,
    this.added = const [],
    this.mayRepeat = false,
  }) : reason = null;

  /// Borrador con la otra propuesta, o `null` si está bloqueada.
  final VoicePurchaseDraft? draft;

  /// Por qué no se puede sustituir sin suponer.
  final String? reason;

  /// Datos que ahora faltan y la otra propuesta trae (en líneas que ya
  /// están).
  final List<String> recovered;

  /// Datos que cambiarían de valor.
  final List<String> changed;

  /// Datos que la frase trajo y la otra propuesta no: quedarían pendientes.
  final List<String> pending;

  /// Lo que se conserva porque se tocó después (a mano u otra frase).
  final List<String> kept;

  /// Líneas que la otra propuesta **añadiría**.
  final List<String> added;

  /// Se añadirían líneas a un borrador que ya tiene otras: podrían repetir
  /// algo dictado antes. Sólo un aviso: no se fusiona ni se quita nada, y
  /// nada dice que haya una compra repetida en la base de datos.
  final bool mayRepeat;

  bool get blocked => draft == null;

  bool get hasChanges =>
      recovered.isNotEmpty ||
      changed.isNotEmpty ||
      pending.isNotEmpty ||
      added.isNotEmpty;
}

/// ¿Trae la otra propuesta algún dato que falta en lo que aportó la frase?
bool alternativeAddsData(TurnContribution c, VoicePurchaseDraft alternative) {
  final plan = planAlternative(
    current: c.after,
    contribution: c,
    alternative: alternative,
  );
  return !plan.blocked && (plan.recovered.isNotEmpty || plan.added.isNotEmpty);
}

/// Bloqueo por falta de correspondencia segura entre líneas.
const _noCorrespondence =
    'No se puede saber con seguridad qué línea de la otra propuesta '
    'corresponde a cada línea de esta frase: no se sustituye. Corrija a mano.';

/// Empareja las líneas que creó la frase ([orig]) con las que crearía la
/// otra propuesta ([alt]), sin suponer:
///
/// 1. Por **producto del catálogo resuelto**: mismo producto en los dos
///    lados. Con más de una línea de un mismo producto, sólo si hay las
///    mismas en los dos lados, en orden, y ninguna se tocó después.
/// 2. Lo que queda (productos sin resolver, o distintos en los dos lados):
///    sólo si queda **exactamente una línea** en cada lado.
///
/// Devuelve `orig → alt` y las líneas sin pareja, o `null` si no hay
/// correspondencia segura.
({Map<int, int> pairs, List<int> origOnly, List<int> altOnly})? _pairLines(
  List<VoicePurchaseLine> orig,
  List<VoicePurchaseLine> alt,
  bool Function(int key) touched,
) {
  int? idOf(VoicePurchaseLine l) =>
      l.product.isResolved ? l.product.value?.id : null;
  final pairs = <int, int>{};
  final ids = {
    for (final l in [...orig, ...alt])
      if (idOf(l) != null) idOf(l)!,
  };
  for (final id in ids) {
    final o = [
      for (final l in orig)
        if (idOf(l) == id) l.key,
    ];
    final a = [
      for (final l in alt)
        if (idOf(l) == id) l.key,
    ];
    if (o.isEmpty || a.isEmpty) continue;
    if (o.length != a.length) return null;
    if (o.length > 1 && o.any(touched)) return null;
    for (var i = 0; i < o.length; i++) {
      pairs[o[i]] = a[i];
    }
  }
  final restO = [
    for (final l in orig)
      if (!pairs.containsKey(l.key)) l.key,
  ];
  final restA = [
    for (final l in alt)
      if (!pairs.containsValue(l.key)) l.key,
  ];
  if (restO.length == 1 && restA.length == 1) {
    pairs[restO.single] = restA.single;
    return (pairs: pairs, origOnly: const [], altOnly: const []);
  }
  // Lo que queda en un solo lado se quita o se añade; en los dos, no se sabe
  // qué corresponde a qué.
  if (restO.isNotEmpty && restA.isNotEmpty) return null;
  return (pairs: pairs, origOnly: restO, altOnly: restA);
}

/// Planifica sustituir la aportación de [contribution] en [current] por
/// [alternative]: la otra propuesta ya interpretada y marcada sobre
/// `contribution.before`.
AlternativePlan planAlternative({
  required VoicePurchaseDraft current,
  required TurnContribution contribution,
  required VoicePurchaseDraft alternative,
}) {
  final before = contribution.before;
  final orig = contribution.after;
  final beforeByKey = {for (final l in before.lines) l.key: l};
  final currentByKey = {for (final l in current.lines) l.key: l};
  final origByKey = {for (final l in orig.lines) l.key: l};
  final altByKey = {for (final l in alternative.lines) l.key: l};
  final origNew = [
    for (final l in orig.lines)
      if (!beforeByKey.containsKey(l.key)) l,
  ];
  final altNew = [
    for (final l in alternative.lines)
      if (!beforeByKey.containsKey(l.key)) l,
  ];

  // Una línea que creó la frase y ya no está: se quitó a mano.
  for (final l in origNew) {
    if (!currentByKey.containsKey(l.key)) {
      return const AlternativePlan.blocked(
        'Una línea de esa frase se quitó del borrador: no se puede sustituir '
        'sin suponer. Corrija a mano.',
      );
    }
  }
  bool touched(int key) => !sameLine(currentByKey[key]!, origByKey[key]!);

  final paired = _pairLines(origNew, altNew, touched);
  if (paired == null) {
    return const AlternativePlan.blocked(_noCorrespondence);
  }

  final recovered = <String>[];
  final changed = <String>[];
  final pending = <String>[];
  final kept = <String>[];
  final added = <String>[];

  DraftField<T> merge<T>(
    String label,
    DraftField<T>? before,
    DraftField<T> orig,
    DraftField<T> alt,
    DraftField<T> cur,
  ) {
    // Un campo que ni la frase ni la otra propuesta tocan no es de esta
    // aportación: queda como está y no se menciona.
    if (before != null && sameField(before, orig) && sameField(before, alt)) {
      return cur;
    }
    // Lo tocado después (a mano u otra frase) se conserva y se dice, aunque
    // la otra propuesta coincida con la frase.
    if (!sameField(cur, orig)) {
      kept.add(cur.isManual ? '$label (corregido a mano)' : label);
      return cur;
    }
    if (sameField(orig, alt)) return cur;
    final had = orig.value != null;
    final has = alt.value != null;
    if (!had && has) {
      recovered.add('$label: ${describeValue(alt)}');
    } else if (had && !has) {
      pending.add(label);
    } else {
      changed.add('$label: ${describeValue(orig)} → ${describeValue(alt)}');
    }
    return alt;
  }

  String nameOf(int key) {
    final i = current.lines.indexWhere((l) => l.key == key);
    return i < 0 ? 'Línea nueva' : 'Línea ${i + 1}';
  }

  /// Mezcla una línea. `null` si una corrección hecha después en ella
  /// pasaría a ser de otro producto.
  VoicePurchaseLine? mergeLine(
    VoicePurchaseLine? b,
    VoicePurchaseLine o,
    VoicePurchaseLine a,
    VoicePurchaseLine c,
  ) {
    final name = nameOf(c.key);
    final product = merge(
      '$name, producto',
      b?.product,
      o.product,
      a.product,
      c.product,
    );
    final otherTouched =
        !sameField(c.quantity, o.quantity) ||
        !sameField(c.price, o.price) ||
        !sameField(c.currency, o.currency);
    final productChanges = !_sameValue(product.value, c.product.value);
    if (otherTouched && productChanges) return null;
    return c.copyWith(
      product: product,
      quantity: merge(
        '$name, cantidad',
        b?.quantity,
        o.quantity,
        a.quantity,
        c.quantity,
      ),
      price: merge('$name, precio', b?.price, o.price, a.price, c.price),
      currency: merge(
        '$name, moneda',
        b?.currency,
        o.currency,
        a.currency,
        c.currency,
      ),
    );
  }

  const transfer = AlternativePlan.blocked(
    'Una corrección hecha después en esa línea pasaría a otro producto: no '
    'se sustituye. Corrija a mano.',
  );
  final lines = <VoicePurchaseLine>[];
  for (final c in current.lines) {
    final o = origByKey[c.key];
    if (o == null) {
      lines.add(c); // de después de la frase: no es de esta aportación
      continue;
    }
    final b = beforeByKey[c.key];
    if (b != null) {
      // Ya estaba antes de la frase: la misma clave en los dos lados.
      final merged = mergeLine(b, o, altByKey[c.key] ?? b, c);
      if (merged == null) return transfer;
      lines.add(merged);
      continue;
    }
    final altKey = paired.pairs[c.key];
    if (altKey != null) {
      final merged = mergeLine(null, o, altByKey[altKey]!, c);
      if (merged == null) return transfer;
      lines.add(merged);
      continue;
    }
    // La creó la frase y la otra propuesta no la crearía.
    if (touched(c.key)) {
      return const AlternativePlan.blocked(
        'Una línea de esa frase se corrigió después y la otra propuesta no '
        'la tiene: no se puede quitar sin suponer. Corrija a mano.',
      );
    }
    pending.add('${nameOf(c.key)} (se quitaría: la otra propuesta no la trae)');
  }

  // Líneas que sólo crearía la otra propuesta: claves libres.
  var next = current.nextLineKey;
  for (final k in paired.altOnly) {
    final a = altByKey[k]!;
    lines.add(a.copyWithKey(next++));
    added.add(describeLine(a));
  }

  // Un producto que quedaría repetido y antes no lo estaba: no se decide.
  // (Dos líneas del mismo producto que ya existían siguen con su aviso del
  // borrador.)
  Set<int> repeated(List<VoicePurchaseLine> ls) {
    final seen = <int>{};
    final out = <int>{};
    for (final l in ls) {
      final id = l.product.value?.id;
      if (id == null || !l.product.isResolved) continue;
      if (!seen.add(id)) out.add(id);
    }
    return out;
  }

  if (!repeated(current.lines).containsAll(repeated(lines))) {
    return const AlternativePlan.blocked(
      'Con la otra propuesta un producto quedaría en dos líneas: no se '
      'sustituye. Corrija a mano.',
    );
  }

  var draft = current.copyWith(lines: lines, nextLineKey: next);
  draft = draft.copyWith(
    supplier: merge(
      'Proveedor',
      before.supplier,
      orig.supplier,
      alternative.supplier,
      current.supplier,
    ),
    recipient: merge(
      'Recibe la compra',
      before.recipient,
      orig.recipient,
      alternative.recipient,
      current.recipient,
    ),
    exchangeRate: merge(
      'Tipo de cambio',
      before.exchangeRate,
      orig.exchangeRate,
      alternative.exchangeRate,
      current.exchangeRate,
    ),
  );
  // Aviso: se añaden líneas a un borrador que ya tiene otras.
  final mayRepeat = added.isNotEmpty && current.lines.isNotEmpty;
  return AlternativePlan(
    draft: draft,
    recovered: recovered,
    changed: changed,
    pending: pending,
    kept: kept,
    added: added,
    mayRepeat: mayRepeat,
  );
}

/// Dos campos dicen lo mismo: estado, origen, revisión y valor (las
/// entradas del catálogo, por su número). Lo oído no cuenta: el mismo dato
/// dicho con otras palabras no es un cambio.
bool sameField(DraftField<Object?> a, DraftField<Object?> b) =>
    a.status == b.status &&
    a.origin == b.origin &&
    a.review == b.review &&
    _sameValue(a.value, b.value);

bool _sameValue(Object? a, Object? b) {
  if (a is CatalogEntry && b is CatalogEntry) return a.id == b.id;
  return a == b;
}

bool sameLine(VoicePurchaseLine a, VoicePurchaseLine b) =>
    sameField(a.product, b.product) &&
    sameField(a.quantity, b.quantity) &&
    sameField(a.price, b.price) &&
    sameField(a.currency, b.currency);

/// Un valor en palabras para la vista previa.
String describeValue(DraftField<Object?> f) {
  final v = f.value;
  final text = switch (v) {
    null => f.heard == null ? 'falta' : '«${f.heard}»',
    CatalogEntry(:final name) => name,
    SpokenQuantity(:final thousandths) =>
      (thousandths / 1000)
          .toString()
          .replaceAll('.', ',')
          .replaceAll(RegExp(r',0$'), ''),
    SpokenPrice(:final minorPerUnit, :final total) =>
      '${(minorPerUnit / 100).toString().replaceAll('.', ',').replaceAll(RegExp(r',0$'), '')}'
          '${total ? ' en total' : ''}',
    _ => '$v'.split('.').last.toUpperCase(),
  };
  final state = f.isResolved && !f.review ? '' : ' (pendiente)';
  return '$text$state';
}

String describeLine(VoicePurchaseLine l) =>
    '${describeValue(l.product)}, ${describeValue(l.quantity)}, '
    '${describeValue(l.price)}, ${describeValue(l.currency)}';

extension on VoicePurchaseLine {
  VoicePurchaseLine copyWithKey(int key) => VoicePurchaseLine(
    key: key,
    product: product,
    quantity: quantity,
    price: price,
    currency: currency,
  );
}

/// Vista previa antes de usar la otra propuesta. No dice que sea mejor: sólo
/// qué cambiaría. Devuelve `true` si se confirma.
class AlternativePreviewDialog extends StatelessWidget {
  const AlternativePreviewDialog({super.key, required this.plan});

  final AlternativePlan plan;

  @override
  Widget build(BuildContext context) {
    final bold = Theme.of(context).textTheme.titleSmall;
    Widget section(String title, List<String> items) => items.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: bold),
                for (final i in items) Text('· $i'),
              ],
            ),
          );
    return AlertDialog(
      key: const Key('voz-otra-propuesta-vista'),
      title: const Text('Usar la otra propuesta de esta frase'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Diagnóstico. Se usaría el texto completo del otro motor sólo '
              'para lo que aportó esta frase. No es necesariamente mejor: '
              'revise cada campo. Nada se registra.',
            ),
            if (plan.blocked)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  plan.reason!,
                  key: const Key('voz-otra-propuesta-bloqueada'),
                ),
              )
            else ...[
              section('Datos que se recuperarían', plan.recovered),
              section('Líneas que se añadirían', plan.added),
              if (plan.mayRepeat)
                const Padding(
                  key: Key('voz-otra-propuesta-aviso-repetir'),
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Atención: el borrador ya tiene otras líneas. Las líneas '
                    'añadidas podrían repetir algo que ya dictó. Revíselas: '
                    'no se fusiona ni se quita nada.',
                  ),
                ),
              section('Datos que cambiarían', plan.changed),
              section('Quedarían pendientes', plan.pending),
              section('Se conservan (tocados después)', plan.kept),
              if (!plan.hasChanges)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No cambiaría nada.'),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('voz-otra-propuesta-cancelar'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        if (!plan.blocked && plan.hasChanges)
          FilledButton(
            key: const Key('voz-otra-propuesta-usar'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Usar esta propuesta'),
          ),
      ],
    );
  }
}
