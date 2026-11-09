import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/voice/voice_alternative.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Usar la otra propuesta» (diagnóstico, política B, 2026-11-09).
///
/// PROPUESTAS SINTÉTICAS escritas a mano (no son transcripciones del
/// teléfono). Se distingue **conservar lo editado a mano** (lo decide la
/// persona) de **mezclar resultados de motores** (nunca: la otra propuesta
/// entra entera o no entra).
void main() {
  const fungicida = CatalogEntry(
    id: 1,
    name: 'Fungicida DEMO',
    unit: CatalogUnit.liter,
  );
  const herbicida = CatalogEntry(
    id: 2,
    name: 'Herbicida DEMO',
    unit: CatalogUnit.liter,
  );
  const mancozeb = CatalogEntry(
    id: 3,
    name: 'Mancozeb DEMO',
    unit: CatalogUnit.kilogram,
  );
  const catalog = VoiceCatalog(
    products: [fungicida, herbicida, mancozeb],
    suppliers: [CatalogEntry(id: 10, name: 'Agro Norte')],
    people: [],
    activeCampaign: CatalogEntry(id: 30, name: 'Campaña'),
  );

  VoicePurchaseDraft apply(String text, VoicePurchaseDraft d) =>
      interpretPurchase(text, d, catalog).draft;

  ({TurnContribution c, VoicePurchaseDraft alt}) turn(
    VoicePurchaseDraft before,
    String delivered,
    String other,
  ) => (
    c: TurnContribution(
      turn: 1,
      seq: 0,
      before: before,
      after: apply(delivered, before),
    ),
    alt: apply(other, before),
  );

  final empty = VoicePurchaseDraft.start(catalog);

  test(
    'recupera la cantidad y deja pendiente la moneda que la otra no trae',
    () {
      final t = turn(
        empty,
        'compré fungicida demo a 45 bolivianos el litro',
        'compré tres litros de fungicida demo a 45 el litro',
      );
      final plan = planAlternative(
        current: t.c.after,
        contribution: t.c,
        alternative: t.alt,
      );
      expect(plan.blocked, isFalse);
      expect(plan.recovered.join(' '), contains('cantidad'));
      expect(plan.pending.join(' '), contains('moneda'));
      final l = plan.draft!.lines.single;
      expect(l.quantity.value?.thousandths, 3000);
      expect(l.currency.status, FieldStatus.missing);
      expect(l.unitPriceMinor, 4500);
      expect(alternativeAddsData(t.c, t.alt), isTrue);
    },
  );

  test('recupera la moneda pero cambia el producto: los dos se muestran', () {
    final t = turn(
      empty,
      'compré tres litros de herbicida demo a 45 el litro',
      'compré tres litros de fungicida demo a 45 bolivianos el litro',
    );
    final plan = planAlternative(
      current: t.c.after,
      contribution: t.c,
      alternative: t.alt,
    );
    expect(plan.recovered.join(' '), contains('moneda'));
    expect(plan.changed.join(' '), contains('Herbicida DEMO → Fungicida DEMO'));
    expect(plan.draft!.lines.single.product.value, fungicida);
  });

  test('una corrección a mano posterior se conserva y se dice', () {
    final t = turn(
      empty,
      'compré fungicida demo a 45 bolivianos el litro',
      'compré tres litros de fungicida demo a 40 bolivianos el litro',
    );
    final current = t.c.after.updateLine(
      t.c.after.lines.single.key,
      (l) => l.copyWith(
        price: const DraftField.resolved(
          SpokenPrice(4700, perUnit: CatalogUnit.liter),
          origin: FieldOrigin.manual,
        ),
      ),
    );
    final plan = planAlternative(
      current: current,
      contribution: t.c,
      alternative: t.alt,
    );
    final l = plan.draft!.lines.single;
    expect(l.unitPriceMinor, 4700);
    expect(l.price.origin, FieldOrigin.manual);
    expect(plan.kept.join(' '), contains('corregido a mano'));
    expect(l.quantity.value?.thousandths, 3000);
  });

  test('lo que añadió una frase posterior se conserva; no se duplican '
      'líneas', () {
    final t = turn(
      empty,
      'compré fungicida demo a 45 bolivianos el litro',
      'compré tres litros de fungicida demo a 45 bolivianos el litro',
    );
    final current = apply(
      'también compré dos kilos de mancozeb demo a 30 bolivianos el kilo',
      t.c.after,
    );
    final plan = planAlternative(
      current: current,
      contribution: t.c,
      alternative: t.alt,
    );
    expect(plan.draft!.lines, hasLength(2));
    expect(plan.draft!.lines[0].quantity.value?.thousandths, 3000);
    expect(plan.draft!.lines[1].product.value, mancozeb);
    expect(plan.draft!.lines[1].unitPriceMinor, 3000);
  });

  test('una línea nueva de la otra propuesta toma una clave libre, sin '
      'chocar con las de frases posteriores', () {
    final t = turn(
      empty,
      'compré tres litros de fungicida demo',
      'compré tres litros de fungicida demo y dos litros de herbicida demo',
    );
    final current = apply(
      'también compré dos kilos de mancozeb demo',
      t.c.after,
    );
    final plan = planAlternative(
      current: current,
      contribution: t.c,
      alternative: t.alt,
    );
    final keys = plan.draft!.lines.map((l) => l.key).toList();
    expect(keys.toSet(), hasLength(keys.length));
    expect(plan.draft!.lines, hasLength(3));
    expect(
      plan.draft!.nextLineKey,
      greaterThan(keys.reduce((a, b) => a > b ? a : b)),
    );
  });

  test('una línea de esa frase que se quitó bloquea: corregir a mano', () {
    final t = turn(
      empty,
      'compré tres litros de fungicida demo',
      'compré tres litros de fungicida demo a 45 bolivianos el litro',
    );
    final current = t.c.after.removeLine(t.c.after.lines.single.key);
    final plan = planAlternative(
      current: current,
      contribution: t.c,
      alternative: t.alt,
    );
    expect(plan.blocked, isTrue);
    expect(plan.reason, contains('se quitó'));
  });

  test('si quedaría un producto repetido que no lo estaba, se bloquea', () {
    final t = turn(
      empty,
      'compré tres litros de herbicida demo',
      'compré tres litros de fungicida demo',
    );
    final current = apply(
      'también compré dos litros de fungicida demo',
      t.c.after,
    );
    final plan = planAlternative(
      current: current,
      contribution: t.c,
      alternative: t.alt,
    );
    expect(plan.blocked, isTrue);
    expect(plan.reason, contains('dos líneas'));
  });

  test('dos líneas del mismo producto que ya existían no bloquean por sí '
      'solas', () {
    final first = apply('compré dos litros de fungicida demo', empty);
    final t = turn(
      first,
      'y otros tres litros de fungicida demo',
      'y otros tres litros de fungicida demo a 40 bolivianos el litro',
    );
    final plan = planAlternative(
      current: t.c.after,
      contribution: t.c,
      alternative: t.alt,
    );
    expect(plan.blocked, isFalse);
    expect(plan.draft!.lines, hasLength(2));
    expect(plan.draft!.lines[1].unitPriceMinor, 4000);
    expect(plan.draft!.lines[0].quantity.value?.thousandths, 2000);
  });

  test('una propuesta igual no cambia nada ni se ofrece', () {
    final t = turn(
      empty,
      'compré tres litros de fungicida demo a 45 bolivianos el litro',
      'Compré 3 litros de Fungicida DEMO a 45 bolivianos el litro.',
    );
    final plan = planAlternative(
      current: t.c.after,
      contribution: t.c,
      alternative: t.alt,
    );
    expect(plan.hasChanges, isFalse);
    expect(alternativeAddsData(t.c, t.alt), isFalse);
  });

  test('aplicar dos veces el plan sobre su propio resultado no cambia nada '
      'más (sin reaplicar el dictado)', () {
    final t = turn(
      empty,
      'compré fungicida demo a 45 bolivianos el litro',
      'compré tres litros de fungicida demo a 45 el litro',
    );
    final once = planAlternative(
      current: t.c.after,
      contribution: t.c,
      alternative: t.alt,
    ).draft!;
    final twice = planAlternative(
      current: once,
      contribution: t.c,
      alternative: t.alt,
    );
    expect(twice.draft!.lines, hasLength(1));
    expect(twice.draft!.lines.single.quantity.value?.thousandths, 3000);
  });

  test('los conflictos y ambigüedades siguen pendientes: nada se confirma '
      'solo', () {
    final t = turn(
      empty,
      'compré fungicida demo a 45 bolivianos el litro',
      'compré tres litros de fungicida demo a 120 volviendo el litro',
    );
    final l = planAlternative(
      current: t.c.after,
      contribution: t.c,
      alternative: t.alt,
    ).draft!.lines.single;
    expect(l.price.isResolved, isFalse);
    expect(l.currency.isResolved, isFalse);
    expect(
      t.c.after.blockers.isNotEmpty ||
          planAlternative(
            current: t.c.after,
            contribution: t.c,
            alternative: t.alt,
          ).draft!.blockers.isNotEmpty,
      isTrue,
    );
  });

  group('coma entre importe y moneda', () {
    VoicePurchaseLine line(String t) => apply(t, empty).lines.single;

    test('coma separadora: se lee como sin coma', () {
      final l = line(
        'Compare 3 litros de Fungicida DEMO a 45, Bolivianos el '
        'litro.',
      );
      expect(l.unitPriceMinor, 4500);
      expect(l.currency.value, CurrencyCode.bob);
    });

    test('coma decimal: el importe no cambia', () {
      expect(
        line('compré 3 litros de fungicida demo a 45,50 bolivianos el litro')
            .unitPriceMinor,
        4550,
      );
    });

    test('negativos: una coma seguida de otra cifra o de la unidad no '
        'inventa moneda ni junta cifras', () {
      final a = line(
        'compré 3 litros de fungicida demo a 45, 50 bolivianos el litro',
      );
      expect(a.unitPriceMinor, isNull);
      expect(a.price.value?.minorPerUnit, 4500);
      final b = line('compré 3 litros de fungicida demo a 45, el litro');
      expect(b.currency.status, FieldStatus.missing);
      expect(b.unitPriceMinor, isNull);
    });

    test('la coma entre productos sigue separando líneas', () {
      final d = apply(
        'compré dos litros de fungicida demo, tres kilos de mancozeb demo',
        empty,
      );
      expect(d.lines, hasLength(2));
    });
  });

  group('emparejamiento de líneas sin suponer', () {
    VoicePurchaseDraft manualPrice(
      VoicePurchaseDraft d,
      int index,
      int minor,
    ) => d.updateLine(
      d.lines[index].key,
      (l) => l.copyWith(
        price: DraftField.resolved(
          SpokenPrice(minor, perUnit: CatalogUnit.liter),
          origin: FieldOrigin.manual,
        ),
      ),
    );

    test('la otra omite un producto: se empareja por producto; la línea '
        'omitida sin tocar se quitaría', () {
      final t = turn(
        empty,
        'compré dos litros de fungicida demo y tres litros de herbicida demo',
        'compré tres litros de herbicida demo a 40 bolivianos el litro',
      );
      final plan = planAlternative(
        current: t.c.after,
        contribution: t.c,
        alternative: t.alt,
      );
      expect(plan.blocked, isFalse);
      expect(plan.draft!.lines, hasLength(1));
      expect(plan.draft!.lines.single.product.value, herbicida);
      expect(plan.draft!.lines.single.unitPriceMinor, 4000);
      expect(plan.pending.join(' '), contains('se quitaría'));
    });

    test('la otra omite un producto corregido a mano: bloquea, no traslada '
        'la corrección', () {
      final t = turn(
        empty,
        'compré dos litros de fungicida demo y tres litros de herbicida demo',
        'compré tres litros de herbicida demo a 40 bolivianos el litro',
      );
      final plan = planAlternative(
        current: manualPrice(t.c.after, 0, 4700),
        contribution: t.c,
        alternative: t.alt,
      );
      expect(plan.blocked, isTrue);
    });

    test('otro orden: cada línea con su producto y la corrección a mano se '
        'queda en el suyo', () {
      final t = turn(
        empty,
        'compré dos litros de fungicida demo y tres litros de herbicida demo',
        'compré tres litros de herbicida demo a 40 bolivianos el litro y dos '
            'litros de fungicida demo a 50 bolivianos el litro',
      );
      final plan = planAlternative(
        current: manualPrice(t.c.after, 0, 4700),
        contribution: t.c,
        alternative: t.alt,
      );
      expect(plan.blocked, isFalse);
      final byProduct = {
        for (final l in plan.draft!.lines) l.product.value!.id: l,
      };
      expect(byProduct[fungicida.id]!.unitPriceMinor, 4700);
      expect(byProduct[fungicida.id]!.price.origin, FieldOrigin.manual);
      expect(byProduct[herbicida.id]!.unitPriceMinor, 4000);
      expect(plan.draft!.lines, hasLength(2));
    });

    test('dos líneas del mismo producto en los dos lados: en orden si nada se '
        'tocó; si se tocó una, bloquea', () {
      final t = turn(
        empty,
        'compré dos litros de fungicida demo y tres litros de fungicida demo',
        'compré dos litros de fungicida demo a 40 bolivianos el litro y tres '
            'litros de fungicida demo a 41 bolivianos el litro',
      );
      final ok = planAlternative(
        current: t.c.after,
        contribution: t.c,
        alternative: t.alt,
      );
      expect(ok.blocked, isFalse);
      expect(ok.draft!.lines.map((l) => l.unitPriceMinor), [4000, 4100]);
      final touched = planAlternative(
        current: manualPrice(t.c.after, 1, 4700),
        contribution: t.c,
        alternative: t.alt,
      );
      expect(touched.blocked, isTrue);
    });

    test('distinto número de líneas de un mismo producto: bloquea', () {
      final t = turn(
        empty,
        'compré dos litros de fungicida demo y tres litros de fungicida demo',
        'compré cinco litros de fungicida demo',
      );
      expect(
        planAlternative(
          current: t.c.after,
          contribution: t.c,
          alternative: t.alt,
        ).blocked,
        isTrue,
      );
    });

    test('cambiar el producto de una línea con una corrección a mano en otro '
        'campo: bloquea (la corrección no pasa a otro producto)', () {
      final t = turn(
        empty,
        'compré tres litros de herbicida demo',
        'compré tres litros de fungicida demo a 40 bolivianos el litro',
      );
      final plan = planAlternative(
        current: manualPrice(t.c.after, 0, 4700),
        contribution: t.c,
        alternative: t.alt,
      );
      expect(plan.blocked, isTrue);
      expect(plan.reason, contains('otro producto'));
    });

    test('un producto sin resolver frente a uno resuelto, una línea por lado: '
        'se emparejan', () {
      final t = turn(
        empty,
        'compré tres litros de fungisida',
        'compré tres litros de fungicida demo',
      );
      final plan = planAlternative(
        current: t.c.after,
        contribution: t.c,
        alternative: t.alt,
      );
      expect(plan.blocked, isFalse);
      expect(plan.draft!.lines.single.product.value, fungicida);
      expect(plan.added, isEmpty);
    });

    test('varias líneas sin resolver en los dos lados: bloquea', () {
      final t = turn(
        empty,
        'compré tres litros de fungisida y dos litros de erbisida',
        'compré tres litros de fungicida demo y dos litros de herbicida demo',
      );
      expect(
        planAlternative(
          current: t.c.after,
          contribution: t.c,
          alternative: t.alt,
        ).blocked,
        isTrue,
      );
    });
  });

  group('aviso de posible repetición', () {
    test(
      'añadir líneas a un borrador con otras avisa; no fusiona ni quita',
      () {
        final first = apply('compré tres litros de fungicida demo', empty);
        final t = turn(
          first,
          'compré algo',
          'compré dos kilos de mancozeb demo a 30 bolivianos el kilo',
        );
        final plan = planAlternative(
          current: t.c.after,
          contribution: t.c,
          alternative: t.alt,
        );
        expect(plan.added, hasLength(1));
        expect(plan.mayRepeat, isTrue);
        expect(plan.draft!.lines, hasLength(2));
        expect(plan.draft!.lines.first.product.value, fungicida);
      },
    );

    test('en un borrador vacío no hay aviso', () {
      final t = turn(
        empty,
        'compré algo',
        'compré dos kilos de mancozeb demo a 30 bolivianos el kilo',
      );
      final plan = planAlternative(
        current: t.c.after,
        contribution: t.c,
        alternative: t.alt,
      );
      expect(plan.added, hasLength(1));
      expect(plan.mayRepeat, isFalse);
    });

    testWidgets(
      'la vista previa lista las líneas añadidas y muestra el aviso',
      (tester) async {
        final first = apply('compré tres litros de fungicida demo', empty);
        final t = turn(
          first,
          'compré algo',
          'compré dos kilos de mancozeb demo a 30 bolivianos el kilo',
        );
        final plan = planAlternative(
          current: t.c.after,
          contribution: t.c,
          alternative: t.alt,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AlternativePreviewDialog(plan: plan)),
          ),
        );
        expect(find.text('Líneas que se añadirían'), findsOneWidget);
        expect(
          find.byKey(const Key('voz-otra-propuesta-aviso-repetir')),
          findsOneWidget,
        );
        expect(
          find.textContaining('no se fusiona ni se quita nada'),
          findsOneWidget,
        );
      },
    );
  });
}
