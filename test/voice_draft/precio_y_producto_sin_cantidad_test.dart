import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Precio sin «a», moneda conservada y producto dicho sin cantidad (F09,
/// POCO 2026-11-09, correcciones aprobadas por el autor).
///
/// TEXTO INYECTADO al intérprete, no reconocimiento real. Frases propias,
/// ninguna del holdout de #12. Las formas deformadas imitan lo que llegó al
/// formulario en el POCO; ninguna palabra se sustituye por otra.
void main() {
  const herbicida = CatalogEntry(
    id: 1,
    name: 'Herbicida DEMO',
    unit: CatalogUnit.liter,
  );
  const insecticida = CatalogEntry(
    id: 2,
    name: 'Insecticida DEMO',
    unit: CatalogUnit.liter,
  );
  const mancozeb = CatalogEntry(
    id: 3,
    name: 'Mancozeb DEMO',
    unit: CatalogUnit.kilogram,
  );
  const glifosato = CatalogEntry(
    id: 4,
    name: 'Glifosato 480',
    unit: CatalogUnit.liter,
  );
  const catalog = VoiceCatalog(
    products: [herbicida, insecticida, mancozeb, glifosato],
    suppliers: [],
    people: [],
    activeCampaign: CatalogEntry(id: 30, name: 'Campaña'),
  );

  ({VoicePurchaseDraft draft, String? notice, UnplacedPrice? unplaced}) run(
    List<String> parts, {
    VoicePurchaseDraft? from,
  }) {
    var d = from ?? VoicePurchaseDraft.start(catalog);
    String? notice;
    UnplacedPrice? unplaced;
    for (final p in parts) {
      final r = interpretPurchase(p, d, catalog);
      d = r.draft;
      notice = r.lineNotice;
      unplaced = r.unplacedPrice;
    }
    return (draft: d, notice: notice, unplaced: unplaced);
  }

  group('importe, moneda y unidad del precio', () {
    test('sin «a», con «en el litro»: conserva 120 y BOB y pregunta '
        '«¿120 Bs por L?», sin resolver', () {
      for (final text in const [
        'Compres 5 litros de Herbicida DEMO, 120 Bolivianos en el litro.',
        'COMPRÉ CINCO LITROS DE HERBICIDA DEMO, 120 BOLIVIANOS EN EL LITRO',
      ]) {
        final l = run([text]).draft.lines.single;
        expect(l.product.value, herbicida, reason: text);
        expect(l.price.status, FieldStatus.ambiguous, reason: text);
        expect(l.price.value?.minorPerUnit, 12000, reason: text);
        expect(l.unitPriceMinor, isNull, reason: text);
        expect(l.price.message, contains('¿120 Bs por L?'), reason: text);
        expect(l.currency.value, CurrencyCode.bob, reason: text);
        expect(l.currency.isResolved, isFalse, reason: text);
        expect(l.currency.review, isTrue, reason: text);
      }
    });

    test('con «a» y «en el litro»: la moneda queda dicha y se pregunta la '
        'unidad', () {
      final l = run([
        'compré cinco litros de herbicida demo a 120 bolivianos en el litro',
      ]).draft.lines.single;
      expect(l.price.status, FieldStatus.ambiguous);
      expect(l.price.message, contains('¿120 Bs por L?'));
      expect(l.currency.isResolved, isTrue);
      expect(l.currency.value, CurrencyCode.bob);
    });

    test('«Por L» confirma la propuesta; la moneda por revisar se confirma '
        'aparte; nada se registra solo', () {
      final d = run([
        'Compré 5 litros de Herbicida DEMO, 120 Bolivianos en el litro.',
      ]).draft;
      final l = d.lines.single;
      final confirmed = l.pricePerUnitConfirmed();
      expect(confirmed.unitPriceMinor, 12000);
      expect(confirmed.currency.review, isTrue);
      expect(d.blockers, isNotEmpty);
    });

    test('números con palabras y estructura inequívoca sin «a»: por revisar '
        'con su valor', () {
      for (final text in const [
        'compré cinco litros de herbicida demo ciento veinte bolivianos por '
            'litro',
        'compré cinco litros de herbicida demo, ciento veinte bolivianos el '
            'litro.',
      ]) {
        final l = run([text]).draft.lines.single;
        expect(l.price.isResolved, isFalse, reason: text);
        expect(l.price.review, isTrue, reason: text);
        expect(l.price.value?.minorPerUnit, 12000, reason: text);
        expect(l.price.value?.perUnit, CatalogUnit.liter, reason: text);
        expect(l.currency.value, CurrencyCode.bob, reason: text);
      }
    });

    test('con «a» y forma clara, con cifras o con palabras: resuelto', () {
      for (final text in const [
        'compré cinco litros de herbicida demo a ciento veinte bolivianos el '
            'litro',
        'Compré 5 litros de Herbicida DEMO a 120 bolivianos por litro.',
        'compré 5 litros de herbicida demo a 120 Bs el litro',
      ]) {
        final l = run([text]).draft.lines.single;
        expect(l.unitPriceMinor, 12000, reason: text);
        expect(l.currency.value, CurrencyCode.bob, reason: text);
        expect(l.currency.isResolved, isTrue, reason: text);
      }
    });

    test('«haciendo veinte» sigue sin resolver y sin valor; la moneda dicha '
        'queda por revisar', () {
      final l = run([
        'compré cinco litros de herbicida demo haciendo veinte bolivianos el '
            'litro',
      ]).draft.lines.single;
      expect(l.price.status, FieldStatus.invalid);
      expect(l.price.value, isNull);
      expect(l.unitPriceMinor, isNull);
      expect(l.currency.value, CurrencyCode.bob);
      expect(l.currency.isResolved, isFalse);
    });

    test('un total dicho sigue siendo total y conserva la moneda', () {
      final l = run([
        'compré cuatro litros de herbicida demo por 480 bolivianos en total',
      ]).draft.lines.single;
      expect(l.price.value?.total, isTrue);
      expect(l.unitPriceMinor, isNull);
      expect(l.currency.value, CurrencyCode.bob);
    });

    test('nombre comercial con número y precio sin «a» en el kilo: la cifra '
        'del nombre no es el precio', () {
      final d = run([
        'compré dos litros de glifosato 480, 45 bolivianos en el litro y tres '
            'kilos de mancozeb demo a treinta bolivianos el kilo',
      ]).draft;
      expect(d.lines, hasLength(2));
      expect(d.lines[0].product.value, glifosato);
      expect(d.lines[0].price.value?.minorPerUnit, 4500);
      expect(d.lines[0].price.message, contains('¿45 Bs por L?'));
      expect(d.lines[1].unitPriceMinor, 3000);
    });

    test('negativos: ninguna de estas frases deja un precio aceptado', () {
      for (final text in const [
        'compré cinco litros de herbicida demo haciendo veinte bolivianos',
        'compré cinco litros de herbicida demo cuarenta bolivianas el litro',
        'compré cinco litros de herbicida demo a 120 volviendo otra el litro',
        'compré cinco litros de herbicida demo 120 en el litro',
        'compré cinco litros de herbicida demo a ciento veinte',
      ]) {
        final l = run([text]).draft.lines.single;
        expect(l.unitPriceMinor, isNull, reason: text);
        expect(l.price.isResolved, isFalse, reason: text);
      }
    });
  });

  group('lo que extrae el comparador no se pierde en el formulario', () {
    // Misma lectura de tokens (cifra seguida de moneda) en los dos: si el
    // comparador ve una moneda tras el importe, el formulario la conserva,
    // aunque el precio quede en duda.
    for (final text in const [
      'Compré 5 litros de Herbicida DEMO, 120 Bolivianos en el litro.',
      'compré cinco litros de herbicida demo ciento veinte bolivianos litro',
      'compré cinco litros de herbicida demo, 120 bolivianos',
      'compré cinco litros de herbicida demo a 120 bolivianos de litro',
      'compré cinco litros de herbicida demo haciendo veinte bolivianos el '
          'litro',
    ]) {
      test(text, () {
        final facts = voiceQuantityFacts(text);
        expect(facts, contains('cbob'));
        final l = run([text]).draft.lines.single;
        expect(l.currency.value, CurrencyCode.bob);
      });
    }
  });

  group('producto dicho sin cantidad', () {
    test('con «compré» y precio, sin líneas: abre la línea con su precio y '
        'espera la cantidad', () {
      final d = run(['compré insecticida demo a cuarenta bolivianos el litro'])
          .draft;
      final l = d.lines.single;
      expect(l.product.value, insecticida);
      expect(l.quantity.status, FieldStatus.missing);
      expect(l.unitPriceMinor, 4000);
    });

    test('sin «compré», con precio: también abre la línea, con el precio por '
        'confirmar', () {
      final l = run(['Insecticida DEMO, 40 Bolivianos del litro.'])
          .draft
          .lines
          .single;
      expect(l.product.value, insecticida);
      expect(l.price.value?.minorPerUnit, 4000);
      expect(l.price.isResolved, isFalse);
      expect(l.currency.value, CurrencyCode.bob);
    });

    test('con una línea de producto oído sin resolver: no adivina ni '
        'duplica, pide elegir la línea', () {
      final r = run([
        'compré tres litros de insectisa',
        'Insecticida DEMO, 40 bolivianos el litro.',
      ]);
      expect(r.draft.lines, hasLength(1));
      expect(r.draft.lines.single.product.isResolved, isFalse);
      expect(r.draft.lines.single.price.status, FieldStatus.missing);
      expect(r.notice, contains('la línea 1'));
      expect(r.notice, contains('insectisa'));
    });

    test('la única línea de ese producto recibe el precio; lo puesto a mano '
        'no cambia', () {
      var d = run(['compré tres litros de insecticida demo']).draft;
      d = run(['Insecticida DEMO a 40 bolivianos el litro'], from: d).draft;
      expect(d.lines, hasLength(1));
      expect(d.lines.single.unitPriceMinor, 4000);

      d = d.updateLine(
        d.lines.single.key,
        (l) => l.copyWith(
          price: const DraftField.resolved(
            SpokenPrice(4500, perUnit: CatalogUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      );
      d = run(['Insecticida DEMO a 40 bolivianos el litro'], from: d).draft;
      expect(d.lines, hasLength(1));
      expect(d.lines.single.unitPriceMinor, 4500);
    });

    test('dos líneas del mismo producto: pide corregir la que corresponda', () {
      final r = run([
        'compré dos litros de insecticida demo',
        'y otros tres litros de insecticida demo',
        'insecticida demo a 40 bolivianos el litro',
      ]);
      expect(r.draft.lines, hasLength(2));
      expect(r.draft.lines.every((l) => l.unitPriceMinor == null), isTrue);
      expect(r.notice, contains('varias líneas'));
    });

    test('repetir la frase no añade líneas', () {
      final d = run([
        'compré insecticida demo a cuarenta bolivianos el litro',
        'compré insecticida demo a cuarenta bolivianos el litro',
      ]).draft;
      expect(d.lines, hasLength(1));
    });

    test('unidad del precio distinta de la del producto: no se pone y se '
        'informa', () {
      final r = run(['compré mancozeb demo a treinta bolivianos el litro']);
      expect(r.draft.lines.single.price.status, FieldStatus.missing);
      expect(r.notice, contains('no corresponde'));
    });

    test(
      'un nombre suelto sin «compré» ni precio no crea líneas, pero avisa',
      () {
        final r = run([
          'compré cinco kilos de mancozeb demo a 30 bolivianos el kilo',
          'Insecticida DEMO',
        ]);
        expect(r.draft.lines, hasLength(1));
        expect(r.notice, contains('no se añadió'));
      },
    );

    test('una palabra desconocida y un precio sin «compré» no se toman por '
        'producto', () {
      final r = run([
        'compré cinco litros de herbicida demo',
        'haciendo veinte bolivianas litro',
      ]);
      expect(r.draft.lines, hasLength(1));
      expect(r.notice, isNull);
      expect(r.unplaced?.reason, UnplacedPriceReason.unclear);
    });
  });
}
