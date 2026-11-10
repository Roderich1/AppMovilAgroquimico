import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Precio unitario frente a total, con frases **escritas y sintéticas**
/// (F09, 2026-11-10). Antes de corregir (`4a2f324`), «… por un total de cien
/// bolivianos» se leía como total de **1,00** («un» tomado como la cifra), el
/// campo «Precio por L» quedaba vacío, aparecía además un precio suelto «no
/// colocado», y al tocar «Total de la línea» quedaba **0,50 Bs/L resuelto**.
///
/// Para cada frase se comprueba por separado: el importe extraído, el tipo
/// (unitario, total o pendiente), lo que muestra el campo «Precio por L» y el
/// resultado después de elegir el tipo, sin registrar nada.
void main() {
  const fungicida = CatalogEntry(
    id: 2,
    name: 'Fungicida DEMO',
    unit: CatalogUnit.liter,
  );
  const herbicida = CatalogEntry(
    id: 1,
    name: 'Herbicida DEMO',
    unit: CatalogUnit.liter,
  );
  const insecticida = CatalogEntry(
    id: 3,
    name: 'Insecticida DEMO',
    unit: CatalogUnit.liter,
  );
  const catalog = VoiceCatalog(
    products: [herbicida, fungicida, insecticida],
    suppliers: [],
    people: [],
  );

  PurchaseInterpretation hear(String text, [VoicePurchaseDraft? from]) =>
      interpretPurchase(
        text,
        from ?? VoicePurchaseDraft.start(catalog),
        catalog,
      );

  // Lo que muestra el campo «Precio por L» (como `_priceText` de la
  // pantalla): un total no se muestra ahí.
  String shown(VoicePurchaseLine l) {
    final v = l.price.value;
    if (v == null || v.total) return '';
    return (v.minorPerUnit / 100).toStringAsFixed(2);
  }

  group('1. «por un total de»: «un» no es la cifra', () {
    test('defecto reproducido y corregido: importe 100,00, tipo total, '
        'pendiente; «Total de la línea» da 50 Bs/L', () {
      final r = hear(
        'Compré dos litros de Fungicida DEMO por un total de cien bolivianos',
      );
      final l = r.draft.lines.single;
      expect(l.product.value, fungicida);
      expect(l.quantityBase, 2000);
      // Importe extraído y tipo.
      expect(l.price.value?.minorPerUnit, 10000, reason: '100,00 Bs, no 1,00');
      expect(l.price.value?.total, isTrue);
      // Pendiente: no se presenta como confirmado.
      expect(l.price.status, FieldStatus.ambiguous);
      expect(l.unitPriceMinor, isNull);
      expect(shown(l), '', reason: 'un total no va en «Precio por L»');
      // La cifra candidata está a la vista en el aviso.
      expect(l.price.message, contains('100 Bs'));
      expect(l.price.message, contains('sin confirmar'));
      expect(l.currency.value, CurrencyCode.bob);
      // Ya no sobra un «precio suelto» con el resto de la frase.
      expect(r.unplacedPrice, isNull);
      // Elegir el tipo.
      expect(
        l.pricePerUnitConfirmed(),
        same(l),
        reason: 'un total no se ofrece como precio por unidad',
      );
      final asTotal = l.priceFromLineTotal();
      expect(asTotal.price.status, FieldStatus.resolved);
      expect(
        asTotal.price.origin,
        FieldOrigin.confirmed,
        reason: 'intervención',
      );
      expect(asTotal.unitPriceMinor, 5000);
      expect(r.draft.copyWith(lines: [asTotal]).totalBobMinor, 10000);
    });

    test('«a cien bolivianos en total» significa lo mismo', () {
      final a = hear(
        'Compré dos litros de Fungicida DEMO por un total de cien bolivianos',
      ).draft.lines.single;
      final b = hear(
        'Compré dos litros de Fungicida DEMO a cien bolivianos en total',
      ).draft.lines.single;
      expect(b.price.value, a.price.value);
      expect(b.price.status, a.price.status);
      expect(b.priceFromLineTotal().unitPriceMinor, 5000);
    });

    test('otras formas: «por el total de», «por un monto total de», sin '
        'moneda dicha', () {
      for (final text in const [
        'compré dos litros de fungicida demo por el total de cien bolivianos',
        'compré dos litros de fungicida demo por un monto total de cien '
            'bolivianos',
        'compré dos litros de fungicida demo a un total de cien bolivianos',
      ]) {
        final l = hear(text).draft.lines.single;
        expect(l.price.value?.minorPerUnit, 10000, reason: text);
        expect(l.price.value?.total, isTrue, reason: text);
        expect(l.price.status, FieldStatus.ambiguous, reason: text);
      }
      final noCurrency = hear(
        'compré dos litros de fungicida demo por un total de cien',
      ).draft.lines.single;
      expect(noCurrency.price.value?.minorPerUnit, 10000);
      expect(noCurrency.price.value?.total, isTrue);
      expect(noCurrency.currency.value, isNull, reason: 'no se dijo');
    });

    test('«un» sigue siendo una cifra fuera de «un total»', () {
      final l = hear(
        'compré dos litros de fungicida demo a un boliviano el litro',
      ).draft.lines.single;
      expect(l.unitPriceMinor, 100);
      expect(l.price.status, FieldStatus.resolved);
    });
  });

  group('2. precio unitario y cantidad decimal', () {
    test('dos litros a cincuenta bolivianos por litro: unitario 50, total '
        '100', () {
      final d = hear(
        'compré dos litros de fungicida demo a cincuenta bolivianos por litro',
      ).draft;
      final l = d.lines.single;
      expect(l.price.status, FieldStatus.resolved);
      expect(l.price.value?.total, isFalse);
      expect(l.unitPriceMinor, 5000);
      expect(shown(l), '50.00');
      expect(d.totalBobMinor, 10000);
    });

    test('un litro y medio a cincuenta bolivianos por litro: 1,5 L, total '
        '75', () {
      final d = hear(
        'compré un litro y medio de fungicida demo a cincuenta bolivianos por '
        'litro',
      ).draft;
      final l = d.lines.single;
      expect(l.quantityBase, 1500);
      expect(l.unitPriceMinor, 5000);
      expect(d.totalBobMinor, 7500);
    });
  });

  group('3. sin indicación suficiente: se pide confirmar', () {
    test('importe sin unidad ni «total»: candidato a la vista, sin tipo', () {
      final l = hear('compré dos litros de fungicida demo a cien bolivianos')
          .draft
          .lines
          .single;
      expect(l.price.status, FieldStatus.ambiguous);
      expect(l.price.value?.minorPerUnit, 10000);
      expect(l.price.value?.total, isFalse);
      expect(l.unitPriceMinor, isNull, reason: 'no confirmado');
      // Las dos salidas son una intervención de la persona.
      final perUnit = l.pricePerUnitConfirmed();
      expect(perUnit.unitPriceMinor, 10000);
      expect(perUnit.price.origin, FieldOrigin.confirmed);
      final asTotal = l.priceFromLineTotal();
      expect(asTotal.unitPriceMinor, 5000);
      expect(asTotal.price.origin, FieldOrigin.confirmed);
    });

    test('«total» y «el litro» a la vez: candidato sin tipo, se elige', () {
      final l = hear(
        'compré dos litros de fungicida demo por un total de cien bolivianos '
        'el litro',
      ).draft.lines.single;
      expect(l.price.status, FieldStatus.ambiguous);
      expect(l.price.value?.minorPerUnit, 10000);
      expect(l.price.value?.total, isFalse);
      expect(l.unitPriceMinor, isNull);
      expect(l.price.message, contains('total'));
    });

    test('«Total de la línea» sin cantidad no borra el importe oído', () {
      final l = hear('compré fungicida demo por un total de cien bolivianos')
          .draft
          .lines
          .single;
      expect(l.quantity.value, isNull);
      expect(l.price.value?.minorPerUnit, 10000);
      final tried = l.priceFromLineTotal();
      expect(tried.price.status, FieldStatus.ambiguous);
      expect(tried.price.value?.minorPerUnit, 10000, reason: 'se conserva');
      expect(tried.price.message, totalNeedsQuantityMessage);
      // Con la cantidad escrita a mano, ya se reparte.
      final withQuantity = tried.copyWith(
        quantity: const DraftField.resolved(
          SpokenQuantity(2000, SpokenUnit.liter),
          origin: FieldOrigin.manual,
        ),
      );
      expect(withQuantity.priceFromLineTotal().unitPriceMinor, 5000);
    });
  });

  group('4. cifras contradictorias: nunca se resuelven en silencio', () {
    test('unitario y total que no cuadran: precio ambiguo y sin valor', () {
      final r = hear(
        'compré dos litros de fungicida demo a cincuenta bolivianos el litro '
        'por un total de ciento veinte bolivianos',
      );
      final l = r.draft.lines.single;
      expect(l.price.status, FieldStatus.ambiguous);
      expect(l.price.value, isNull, reason: 'no se elige una de las cifras');
      expect(l.unitPriceMinor, isNull);
      expect(l.price.message, contains('no cuadran'));
      expect(r.draft.totalBobMinor, isNull);
      expect(r.draft.blockers, isNotEmpty);
    });

    test('unitario y total que cuadran: el unitario queda dicho', () {
      final d = hear(
        'compré dos litros de fungicida demo a cincuenta bolivianos el litro, '
        'en total cien bolivianos',
      ).draft;
      expect(d.lines.single.price.status, FieldStatus.resolved);
      expect(d.lines.single.unitPriceMinor, 5000);
      expect(d.totalBobMinor, 10000);
    });

    test('dos precios por litro distintos, o monedas distintas: ambiguo', () {
      for (final text in const [
        'compré dos litros de fungicida demo a cincuenta bolivianos el litro '
            'o sea a sesenta bolivianos el litro',
        'compré dos litros de fungicida demo a cincuenta bolivianos el litro '
            'y en total cien dólares',
      ]) {
        final l = hear(text).draft.lines.single;
        expect(l.price.status, FieldStatus.ambiguous, reason: text);
        expect(l.price.value, isNull, reason: text);
      }
    });
  });

  group('5. dos productos: el total de la compra no va a una línea', () {
    test('«… y tres litros de B por un total de doscientos»: ninguna línea '
        'recibe el total', () {
      final d = hear(
        'compré dos litros de fungicida demo y cuatro litros de herbicida '
        'demo por un total de doscientos bolivianos',
      ).draft;
      expect(d.lines, hasLength(2));
      for (final l in d.lines) {
        expect(l.unitPriceMinor, isNull);
        expect(l.price.value, isNull, reason: 'sin candidato que repartir');
      }
      expect(d.lines.last.price.status, FieldStatus.ambiguous);
      expect(d.lines.last.price.message, contains('toda la compra'));
      expect(d.lines.last.price.message, contains('200 Bs'));
      // «Total de la línea» no le carga 200 a la segunda línea.
      expect(d.lines.last.priceFromLineTotal(), same(d.lines.last));
      expect(d.totalBobMinor, isNull);
    });

    test('un total pegado a la primera línea sí es de esa línea', () {
      final d = hear(
        'compré dos litros de fungicida demo por un total de cien bolivianos '
        'y cuatro litros de herbicida demo a treinta bolivianos el litro',
      ).draft;
      expect(d.lines, hasLength(2));
      expect(d.lines.first.price.value?.total, isTrue);
      expect(d.lines.first.price.value?.minorPerUnit, 10000);
      expect(d.lines.first.priceFromLineTotal().unitPriceMinor, 5000);
      expect(d.lines.last.unitPriceMinor, 3000);
    });

    test('dos líneas con su precio por litro: sin cambios', () {
      final d = hear(
        'compré dos litros de fungicida demo a cincuenta bolivianos el litro '
        'y cuatro litros de herbicida demo a treinta bolivianos el litro',
      ).draft;
      expect(d.lines.map((l) => l.unitPriceMinor), [5000, 3000]);
      expect(d.totalBobMinor, 22000);
    });
  });

  group('6. R6: «Compré fungicida demo» (recorrido escrito)', () {
    for (final text in const [
      'Compré fungicida demo',
      'Compré fungicida demo.',
      'Compré Fungicida DEMO.',
      'compre fungicida demo',
    ]) {
      test(text, () {
        final r = hear(text);
        // Intérprete → propuesta de línea → incorporación.
        expect(r.trace.words, greaterThan(0));
        expect(r.trace.mention, 'unico-nueva');
        expect(r.trace.reason, 'ok');
        expect(r.outcome.applied, 1);
        final l = r.draft.lines.single;
        expect(l.product.value, fungicida);
        expect(l.quantity.status, FieldStatus.missing);
        expect(l.price.status, FieldStatus.missing);
        expect(l.currency.status, FieldStatus.missing);
        // Incompleta: no se puede registrar.
        expect(r.draft.blockers, isNotEmpty);
      });
    }

    test('la traza no lleva texto ni nombres', () {
      final r = hear('Compré fungicida demo');
      final line = r.trace.logLine(applied: 1, keptManual: 0);
      expect(line, startsWith('voz compra: palabras=3 '));
      final rest = line.substring('voz compra: '.length).toLowerCase();
      expect(rest, isNot(contains('fungicida')));
      expect(rest, isNot(contains('demo')));
      expect(rest, isNot(contains('compr')));
    });

    test('códigos cuando no cambia el borrador', () {
      expect(hear('').trace.reason, 'vacio');
      expect(hear('eso sería todo').trace.reason, isNot('ok'));
      final outside = hear('compré fungicida de mo');
      expect(outside.outcome.applied, 0);
      expect(outside.trace.mention, 'ninguno-aviso');
      expect(outside.trace.reason, 'aviso');
    });
  });
}
