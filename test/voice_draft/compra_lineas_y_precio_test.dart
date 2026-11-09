import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/voice/voice_draft_widgets.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/interpretation/phrases.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Etapa «base» tras la prueba del autor en el POCO (2026-11-08, datos
/// sintéticos): unidad del precio, total de la línea, decimales dichos con
/// palabras, y a qué línea va cada dictado (repeticiones sin líneas vacías,
/// complemento de una línea pendiente, línea nueva explícita y dos líneas del
/// mismo producto que no se funden en silencio).
///
/// Todo es **texto inyectado** al intérprete: no prueba el reconocimiento.
/// Frases propias, distintas de las usadas al desarrollar la corrección (otros
/// productos, kilos, otras formas de decir lo mismo); ninguna del corpus de
/// aceptación ni del holdout de #12.
void main() {
  const mancozeb = CatalogEntry(
    id: 1,
    name: 'Mancozeb DEMO',
    unit: CatalogUnit.kilogram,
  );
  const insecticida = CatalogEntry(
    id: 2,
    name: 'Insecticida DEMO',
    unit: CatalogUnit.liter,
  );
  const fungicida = CatalogEntry(
    id: 3,
    name: 'Fungicida DEMO',
    unit: CatalogUnit.liter,
  );
  const atrazina = CatalogEntry(
    id: 4,
    name: 'Atrazina 90',
    unit: CatalogUnit.kilogram,
  );
  const catalog = VoiceCatalog(
    products: [mancozeb, insecticida, fungicida, atrazina],
    suppliers: [CatalogEntry(id: 10, name: 'Agro Norte')],
    people: [
      CatalogEntry(id: 20, name: 'Rosa Mamani F09'),
      CatalogEntry(id: 21, name: 'Beto Mamani'),
    ],
    activeCampaign: CatalogEntry(id: 30, name: 'Campaña'),
  );

  ({VoicePurchaseDraft draft, String? notice}) dictate(List<String> parts) {
    var d = VoicePurchaseDraft.start(catalog);
    String? notice;
    for (final p in parts) {
      final r = interpretPurchase(p, d, catalog);
      d = r.draft;
      notice = r.lineNotice;
    }
    return (draft: d, notice: notice);
  }

  group('unidad del precio', () {
    test('«por el kilo» y «por cada kilo» son precio por unidad', () {
      for (final text in const [
        'compré cuatro kilos de mancozeb demo a treinta y cinco bolivianos '
            'por el kilo',
        'compré cuatro kilos de mancozeb demo a treinta y cinco bolivianos '
            'por cada kilo',
      ]) {
        final line = dictate([text]).draft.lines.single;
        expect(line.price.isResolved, isTrue, reason: text);
        expect(line.unitPriceMinor, 3500, reason: text);
        expect(line.subtotalBobMinor(null), 14000, reason: text);
      }
    });

    test('sin unidad no se supone por unidad aunque el producto se mida en '
        'kilos: se elige «Por kg» o «Total de la línea»', () {
      final line = dictate([
        'compré cuatro kilos de mancozeb demo a ciento cuarenta bolivianos',
      ]).draft.lines.single;
      expect(line.price.status, FieldStatus.ambiguous);
      expect(line.unitPriceMinor, isNull);
      expect(line.price.message, unitNotSaidMessage);

      final perUnit = line.pricePerUnitConfirmed();
      expect(perUnit.price.origin, FieldOrigin.confirmed);
      expect(perUnit.unitPriceMinor, 14000);

      final total = line.priceFromLineTotal();
      expect(total.price.origin, FieldOrigin.confirmed);
      expect(total.unitPriceMinor, 3500);
      expect(total.subtotalBobMinor(null), 14000);
    });

    test('un total dicho se reparte sólo si da centavos exactos, y nunca '
        'se ofrece como precio por unidad', () {
      final exact = dictate([
        'compré cuatro litros de insecticida demo por doscientos bolivianos '
            'en total',
      ]).draft.lines.single;
      expect(exact.price.value?.total, isTrue);
      expect(exact.pricePerUnitConfirmed(), same(exact));
      expect(exact.priceFromLineTotal().unitPriceMinor, 5000);

      final inexact = dictate([
        'compré tres litros de insecticida demo por cien bolivianos en total',
      ]).draft.lines.single;
      final r = inexact.priceFromLineTotal();
      expect(r.price.status, FieldStatus.invalid);
      expect(r.price.value, isNull);
      expect(r.price.message, contains('centavos exactos'));
    });

    test('el total sin cantidad no se reparte: pide completarla', () {
      final d = dictate([
        'compré fungicida demo',
        'a noventa bolivianos en total',
      ]).draft;
      // Un precio suelto que es un total no se pone en ninguna línea.
      expect(d.lines.single.price.status, FieldStatus.missing);
      const line = VoicePurchaseLine(
        key: 1,
        product: DraftField.resolved(fungicida, origin: FieldOrigin.voice),
        price: DraftField.ambiguous(
          candidates: [],
          heard: 'noventa bolivianos en total',
          value: SpokenPrice(9000, total: true),
        ),
      );
      final r = line.priceFromLineTotal();
      expect(r.price.status, FieldStatus.invalid);
      expect(r.price.message, contains('cantidad'));
    });

    test('decimales con palabras: dos cifras como centavos, «cero» delante '
        'y una sola cifra', () {
      int? price(String said) => dictate([
        'compré dos kilos de mancozeb demo a $said bolivianos el kilo',
      ]).draft.lines.single.unitPriceMinor;
      expect(price('cuarenta y dos coma veinticinco'), 4225);
      expect(price('dieciocho coma cero cinco'), 1805);
      expect(price('nueve coma cinco'), 950);
      expect(price('treinta coma noventa y nueve'), 3099);
    });

    test('un número del nombre comercial no se toma por precio', () {
      final line = dictate([
        'compré seis kilos de atrazina noventa a veinte bolivianos el kilo',
      ]).draft.lines.single;
      expect(line.product.value, atrazina);
      expect(line.unitPriceMinor, 2000);
    });
  });

  group('a qué línea va cada dictado', () {
    test('repetir una cantidad sin producto no añade líneas vacías', () {
      final d = dictate(['dos kilos', 'dos kilos', 'compré dos kilos de'])
          .draft;
      expect(d.lines, hasLength(1));
      expect(isAwaitingProduct(d.lines.single.product), isTrue);
    });

    test('una cantidad sin producto completa la única línea que la espera', () {
      final d = dictate(['compré insecticida demo', 'seis litros']).draft;
      final line = d.lines.single;
      expect(line.product.value, insecticida);
      expect(line.quantity.value, const SpokenQuantity(6000, SpokenUnit.liter));
    });

    test('con varias líneas sin cantidad no se adivina: se avisa y no '
        'cambia nada', () {
      final r = dictate([
        'compré insecticida demo',
        'también compré fungicida demo',
        'seis litros',
      ]);
      expect(r.draft.lines, hasLength(2));
      expect(
        r.draft.lines.every((l) => l.quantity.status == FieldStatus.missing),
        isTrue,
      );
      expect(r.notice, contains('varias líneas sin cantidad'));
    });

    test(
      '«… de» al final espera un producto nuevo; no completa otra línea',
      () {
        final d = dictate([
          'compré insecticida demo',
          'y seis litros de',
          'fungicida demo',
        ]).draft;
        expect(d.lines, hasLength(2));
        expect(d.lines[0].quantity.status, FieldStatus.missing);
        expect(d.lines[1].product.value, fungicida);
        expect(d.lines[1].quantity.value?.thousandths, 6000);
      },
    );

    test('repetir un producto fuera del catálogo no lo duplica', () {
      final d = dictate([
        'compré siete litros de pirimicarb',
        'compré siete litros de pirimicarb',
      ]).draft;
      expect(d.lines, hasLength(1));
      expect(d.lines.single.product.status, FieldStatus.missing);
    });

    test('un producto fuera del catálogo dicho sin cantidad avisa y no abre '
        'línea', () {
      final r = dictate(['compré pirimicarb']);
      expect(r.draft.lines, isEmpty);
      expect(r.notice, contains('no está en el catálogo'));
    });

    test('el mismo producto dos veces en una frase son dos líneas (bloquean '
        'como repetidas), no una sobrescrita', () {
      final d = dictate([
        'compré dos kilos de mancozeb demo a treinta bolivianos el kilo y '
            'tres kilos de mancozeb demo a veintiocho bolivianos el kilo',
      ]).draft;
      expect(d.lines, hasLength(2));
      expect(d.lines[0].unitPriceMinor, 3000);
      expect(d.lines[1].unitPriceMinor, 2800);
      expect(d.blockers.join(' '), contains('repetido'));
    });

    test('«otros …» pide una línea nueva; nombrar el producto otra vez sin '
        '«otros» corrige su línea', () {
      final nueva = dictate([
        'compré dos kilos de mancozeb demo',
        'y otros tres kilos de mancozeb demo',
      ]).draft;
      expect(nueva.lines, hasLength(2));
      expect(nueva.lines[0].quantity.value?.thousandths, 2000);

      final corrige = dictate([
        'compré dos kilos de mancozeb demo',
        'tres kilos de mancozeb demo',
      ]).draft;
      expect(corrige.lines, hasLength(1));
      expect(corrige.lines.single.quantity.value?.thousandths, 3000);
    });

    test('con dos líneas del mismo producto, un dictado de ese producto no '
        'elige una: se avisa', () {
      final r = dictate([
        'compré dos kilos de mancozeb demo',
        'y otros tres kilos de mancozeb demo',
        'cuatro kilos de mancozeb demo',
      ]);
      expect(r.draft.lines.map((l) => l.quantity.value?.thousandths), [
        2000,
        3000,
      ]);
      expect(r.notice, contains('varias líneas de Mancozeb DEMO'));
    });

    test('repetir la cantidad de una línea pendiente no cambia lo corregido '
        'a mano', () {
      var d = dictate(['compré dos kilos de']).draft;
      d = d.updateLine(
        d.lines.single.key,
        (l) => l.copyWith(
          quantity: const DraftField.resolved(
            SpokenQuantity(5000, SpokenUnit.kilogram),
            origin: FieldOrigin.manual,
          ),
        ),
      );
      final r = interpretPurchase('dos kilos de', d, catalog);
      expect(r.draft.lines, hasLength(1));
      expect(r.draft.lines.single.quantity.value?.thousandths, 5000);
      expect(r.outcome.keptManual, 1);
    });
  });

  group('el mismo texto cerrado no se aplica dos veces', () {
    test('un aviso repetido de la sesión no entrega texto nuevo', () {
      final feed = VoiceSegmentFeed();
      expect(feed.take('dos kilos', ready: true), 'dos kilos');
      expect(feed.take('dos kilos', ready: true), isNull);
      expect(
        feed.take('dos kilos de mancozeb demo', ready: true),
        'de mancozeb demo',
      );
    });
  });

  test('la moneda dicha queda en BOB; el total de la línea la conserva', () {
    final line = dictate([
      'compré cuatro kilos de mancozeb demo a ciento cuarenta bolivianos',
    ]).draft.lines.single;
    expect(line.currency.value, CurrencyCode.bob);
    expect(line.priceFromLineTotal().currency.value, CurrencyCode.bob);
  });
}
