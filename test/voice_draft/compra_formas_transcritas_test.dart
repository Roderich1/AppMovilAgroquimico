import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formas que el intérprete no entendía (F09, 2026-11-10): las encontraron
/// sondas **escritas y sintéticas** (§9.5 del informe del experimento), sin
/// texto de ningún dictado real. Sólo pruebas del **intérprete**; el
/// borrador y la pantalla tienen las suyas
/// (`compra_formas_borrador_test.dart`, `compra_formas_pantalla_test.dart`).
///
/// Cada arreglo es acotado: no se borran palabras al azar. Un artículo sólo
/// se quita al **principio** del nombre, una expresión de tiempo sólo al
/// **final**, y sólo si así el nombre coincide exactamente con uno del
/// catálogo; si el nombre del catálogo lleva esa palabra, gana el nombre.
void main() {
  const herbicida = CatalogEntry(
    id: 1,
    name: 'Herbicida DEMO',
    unit: CatalogUnit.liter,
  );
  const fungicida = CatalogEntry(
    id: 2,
    name: 'Fungicida DEMO',
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

  PurchaseInterpretation hear(String text, [VoiceCatalog c = catalog]) =>
      interpretPurchase(text, VoicePurchaseDraft.start(c), c);

  VoicePurchaseLine only(PurchaseInterpretation r) => r.draft.lines.single;

  /// Una línea con el producto resuelto y lo demás pendiente.
  void expectIncompleteLine(PurchaseInterpretation r, CatalogEntry product) {
    final l = only(r);
    expect(l.product.status, FieldStatus.resolved);
    expect(l.product.value, product);
    expect(l.quantity.status, FieldStatus.missing);
    expect(l.price.status, FieldStatus.missing);
    expect(r.draft.blockers, isNotEmpty);
  }

  group('importe pegado a la moneda: «100Bs»', () {
    test('«por un total de 100Bs» es un total de 100 Bs', () {
      final l = only(
        hear('Compré dos litros de Fungicida DEMO por un total de 100Bs'),
      );
      expect(l.price.value?.minorPerUnit, 10000);
      expect(l.price.value?.total, isTrue);
      expect(l.price.status, FieldStatus.ambiguous, reason: 'se confirma');
      expect(l.currency.value, CurrencyCode.bob);
    });

    test('«a 50Bs el litro» es 50 Bs por litro, con punto final', () {
      for (final text in const [
        'Compré dos litros de Fungicida DEMO a 50Bs el litro',
        'Compré dos litros de Fungicida DEMO a 50Bs. el litro',
        'Compré dos litros de Fungicida DEMO a 50 Bs el litro.',
      ]) {
        final l = only(hear(text));
        expect(l.unitPriceMinor, 5000, reason: text);
        expect(l.currency.value, CurrencyCode.bob, reason: text);
      }
    });

    test('una sigla de moneda dentro de un nombre no se separa', () {
      // «Bs» sólo se separa de una cifra; «Bsx» no es moneda.
      final l = only(hear('Compré dos litros de Fungicida DEMO a 50bsx'));
      expect(l.price.isResolved, isFalse);
    });
  });

  group('separadores decimales y de miles', () {
    test('«100.00 bolivianos»: punto con dos decimales es decimal', () {
      final l = only(
        hear(
          'Compré dos litros de Fungicida DEMO a 100.00 bolivianos el litro',
        ),
      );
      expect(l.unitPriceMinor, 10000);
    });

    test('«1.5 litros» es litro y medio', () {
      final l = only(
        hear('Compré 1.5 litros de Fungicida DEMO a 50 bolivianos el litro'),
      );
      expect(l.quantityBase, 1500);
      expect(l.unitPriceMinor, 5000);
    });

    test('«1,500 bolivianos» es ambiguo (1,5 o 1500): no se resuelve', () {
      final l = only(
        hear('Compré dos litros de Fungicida DEMO a 1,500 bolivianos el litro'),
      );
      expect(l.price.isResolved, isFalse);
      expect(l.unitPriceMinor, isNull);
      expect(l.price.message, contains('1.500'));
      expect(l.price.message, contains('1,5'));
    });

    test('«1.500 bolivianos» sigue el convenio es-BO (miles), como los '
        'formularios', () {
      final l = only(
        hear('Compré dos litros de Fungicida DEMO a 1.500 bolivianos el litro'),
      );
      expect(l.unitPriceMinor, 150000);
    });

    test('«100.000» con punto y tres cifras sigue siendo miles', () {
      final l = only(
        hear(
          'Compré dos litros de Fungicida DEMO a 100.000 bolivianos el litro',
        ),
      );
      expect(l.unitPriceMinor, 10000000);
    });
  });

  group('«un total de» según su contexto', () {
    for (final lead in const ['en', 'con', 'para', 'por']) {
      test('«$lead un total de cien bolivianos» tras el producto es un total '
          'de la línea, por confirmar', () {
        final r = hear(
          'Compré dos litros de Fungicida DEMO $lead un total de cien '
          'bolivianos',
        );
        final l = only(r);
        expect(l.product.value, fungicida, reason: 'el producto no cambia');
        expect(l.product.status, FieldStatus.resolved);
        expect(l.price.value?.minorPerUnit, 10000);
        expect(l.price.value?.total, isTrue);
        expect(l.price.status, FieldStatus.ambiguous);
        expect(r.unplacedPrice, isNull);
        expect(r.trace.loosePrices, 0);
      });
    }

    test('sin cantidad: «Compré fungicida demo con un total de cien '
        'bolivianos» abre la línea con el total por confirmar', () {
      final l = only(
        hear('Compré fungicida demo con un total de cien bolivianos'),
      );
      expect(l.product.value, fungicida);
      expect(l.quantity.status, FieldStatus.missing);
      expect(l.price.value?.total, isTrue);
      expect(l.price.value?.minorPerUnit, 10000);
    });

    test('«para» sin «total» no cambia: no se toma como precio', () {
      final l = only(
        hear('Compré dos litros de Fungicida DEMO para el chaco de arriba'),
      );
      expect(l.price.status, FieldStatus.missing);
    });

    for (final lead in const ['en', 'con', 'para', 'por']) {
      test('varias líneas y «$lead un total de»: el total global no va a '
          'ninguna línea', () {
        final r = hear(
          'Compré dos litros de Fungicida DEMO y tres litros de Herbicida '
          'DEMO $lead un total de doscientos cincuenta bolivianos',
        );
        expect(r.draft.lines, hasLength(2));
        for (final l in r.draft.lines) {
          expect(l.price.value, isNull, reason: 'ninguna recibe el total');
          expect(l.price.isResolved, isFalse);
        }
        expect(r.draft.blockers, isNotEmpty);
      });
    }

    test('cifras contradictorias con «con un total de»: sin valor', () {
      final l = only(
        hear(
          'Compré dos litros de Fungicida DEMO a cincuenta bolivianos el '
          'litro con un total de ciento veinte bolivianos',
        ),
      );
      expect(l.price.status, FieldStatus.ambiguous);
      expect(l.price.value, isNull);
      expect(l.price.message, contains('no cuadran'));
    });

    test('cifras que cuadran con «para un total de»: 50 por litro', () {
      final l = only(
        hear(
          'Compré dos litros de Fungicida DEMO a cincuenta bolivianos el '
          'litro para un total de cien bolivianos',
        ),
      );
      expect(l.unitPriceMinor, 5000);
    });
  });

  group('artículo antes del producto', () {
    for (final text in const [
      'Compré el fungicida demo',
      'Compré un fungicida demo',
      'Compré la Fungicida DEMO',
    ]) {
      test('«$text»: línea incompleta con el producto', () {
        expectIncompleteLine(hear(text), fungicida);
      });
    }

    test('con cantidad: «dos litros del fungicida demo» y «dos litros de el '
        'fungicida demo»', () {
      for (final text in const [
        'Compré dos litros del fungicida demo a cincuenta bolivianos el litro',
        'Compré dos litros de el fungicida demo a cincuenta bolivianos el '
            'litro',
      ]) {
        final l = only(hear(text));
        expect(l.product.value, fungicida, reason: text);
        expect(l.product.isResolved, isTrue, reason: text);
        expect(l.unitPriceMinor, 5000, reason: text);
      }
    });

    test('«un» antes del producto no es una cantidad', () {
      final l = only(hear('Compré un fungicida demo'));
      expect(l.quantity.status, FieldStatus.missing);
      expect(l.quantityBase, isNull);
    });
  });

  group('expresión de tiempo después del producto', () {
    for (final text in const [
      'Compré fungicida demo hoy',
      'Compré fungicida demo ayer',
      'Compré fungicida demo esta mañana',
    ]) {
      test('«$text»: línea incompleta con el producto', () {
        expectIncompleteLine(hear(text), fungicida);
      });
    }

    test('con cantidad y precio: «dos litros de fungicida demo hoy a '
        'cincuenta bolivianos el litro»', () {
      final l = only(
        hear(
          'Compré dos litros de fungicida demo hoy a cincuenta bolivianos el '
          'litro',
        ),
      );
      expect(l.product.value, fungicida);
      expect(l.unitPriceMinor, 5000);
    });

    test('otras palabras después del nombre no se quitan: «para la campaña» '
        'sigue pidiendo elegir', () {
      final l = only(hear('Compré fungicida demo para la campaña'));
      expect(l.product.isResolved, isFalse);
    });
  });

  group('verbo pegado a la palabra siguiente (POCO, 2026-11-10, P4)', () {
    // En el teléfono, «Compré fungicida demo» llegó con el verbo y el
    // producto juntos en una palabra y «demo» aparte (dicho por el autor,
    // sin copiar el texto). En HOST, con voz sintética, «compra de» llegó
    // como «Comprade». Las frases de aquí son sintéticas.
    for (final text in const [
      'Comprefungicida demo',
      'Compréfungicida DEMO.',
      'Comprafungicida demo',
      'Comprade fungicida demo',
    ]) {
      test('«$text»: línea incompleta con el producto', () {
        final r = hear(text);
        expectIncompleteLine(r, fungicida);
        expect(r.trace.intent, 'purchase');
      });
    }

    test('«Comprédos litros de fungicida demo a cincuenta bolivianos el '
        'litro»', () {
      final l = only(
        hear(
          'Comprédos litros de fungicida demo a cincuenta bolivianos el litro',
        ),
      );
      expect(l.product.value, fungicida);
      expect(l.quantityBase, 2000);
      expect(l.unitPriceMinor, 5000);
    });

    test('no se parte una palabra que no termina en algo conocido', () {
      for (final text in const [
        'Comprador fungicida demo',
        'Comprender fungicida demo',
        'Comprefungi demo',
      ]) {
        final r = hear(text);
        expect(r.draft.lines, isEmpty, reason: text);
      }
    });

    test('pegado y negado: «No comprefungicida demo» no anota nada', () {
      final r = hear('No comprefungicida demo');
      expect(r.draft.lines, isEmpty);
      expect(r.trace.reason, 'negacion');
    });
  });

  group('el verbo no es la primera palabra', () {
    for (final text in const [
      'Hoy compré fungicida demo',
      'Ayer compré fungicida demo.',
      'Bueno, compré fungicida demo',
      'Yo compré fungicida demo',
      'Esta mañana compré fungicida demo',
      'He comprado fungicida demo',
      'Compra de fungicida demo',
      'Compra fungicida demo',
    ]) {
      test('«$text»: línea incompleta (no se ignora)', () {
        final r = hear(text);
        expectIncompleteLine(r, fungicida);
        expect(r.trace.mention, 'unico-nueva');
      });
    }

    test('con cantidad, como antes: «Hoy compré dos litros de fungicida demo '
        'a cincuenta bolivianos el litro»', () {
      final l = only(
        hear(
          'Hoy compré dos litros de fungicida demo a cincuenta bolivianos el '
          'litro',
        ),
      );
      expect(l.product.value, fungicida);
      expect(l.unitPriceMinor, 5000);
    });

    test('un nombre suelto sin verbo sigue sin abrir línea', () {
      final r = hear('Fungicida demo');
      expect(r.draft.lines, isEmpty);
    });
  });

  group('negación e intención futura: no se anota nada', () {
    for (final text in const [
      'No compré fungicida demo',
      'No compré dos litros de fungicida demo a cincuenta bolivianos el litro',
      'Hoy no compré fungicida demo',
      'Nunca compramos fungicida demo',
    ]) {
      test('«$text»', () {
        final r = hear(text);
        expect(r.draft.lines, isEmpty);
        expect(r.outcome.applied, 0);
        expect(r.trace.reason, 'negacion');
        expect(r.lineNotice ?? '', contains('no se añadió'));
      });
    }

    for (final text in const [
      'Quiero comprar fungicida demo',
      'Voy a comprar dos litros de fungicida demo',
      'Tengo que comprar dos litros de fungicida demo',
      'Necesito comprar fungicida demo',
      'Compraré dos litros de fungicida demo',
    ]) {
      test('«$text»', () {
        final r = hear(text);
        expect(r.draft.lines, isEmpty);
        expect(r.outcome.applied, 0);
        expect(r.trace.reason, 'intencion-futura');
        expect(r.lineNotice ?? '', contains('no se añadió'));
      });
    }

    test('«No, compré dos litros…» (corrección tras una pausa) sí es una '
        'compra', () {
      final l = only(
        hear(
          'No, compré dos litros de fungicida demo a cincuenta bolivianos el '
          'litro',
        ),
      );
      expect(l.product.value, fungicida);
      expect(l.unitPriceMinor, 5000);
    });
  });

  group('nombres parecidos y nombres con palabras «prescindibles»', () {
    const plus = CatalogEntry(
      id: 4,
      name: 'Fungicida DEMO Plus',
      unit: CatalogUnit.liter,
    );
    const tigre = CatalogEntry(
      id: 5,
      name: 'El Tigre',
      unit: CatalogUnit.liter,
    );
    const total = CatalogEntry(
      id: 6,
      name: 'Total 500',
      unit: CatalogUnit.liter,
    );
    const ahora = CatalogEntry(
      id: 7,
      name: 'Ahora Plus',
      unit: CatalogUnit.liter,
    );
    const hoy = CatalogEntry(
      id: 8,
      name: 'Fungicida Hoy',
      unit: CatalogUnit.liter,
    );
    const similar = VoiceCatalog(
      products: [fungicida, plus, tigre, total, ahora, hoy],
      suppliers: [],
      people: [],
    );

    test('«el fungicida demo plus» es Plus; «el fungicida demo», el otro', () {
      expect(
        only(hear('Compré el fungicida demo plus', similar)).product.value,
        plus,
      );
      expect(
        only(hear('Compré el fungicida demo', similar)).product.value,
        fungicida,
      );
    });

    test('«fungicida» solo sigue pidiendo elegir', () {
      final l = only(hear('Compré fungicida', similar));
      expect(l.product.status, FieldStatus.ambiguous);
    });

    test('«El Tigre»: el artículo es del nombre', () {
      expect(only(hear('Compré el tigre', similar)).product.value, tigre);
    });

    test('«Total 500»: «total» es del nombre, no un importe', () {
      final l = only(
        hear(
          'Compré dos litros de Total 500 a cincuenta bolivianos el litro',
          similar,
        ),
      );
      expect(l.product.value, total);
      expect(l.unitPriceMinor, 5000);
      expect(l.price.value?.total, isFalse);
    });

    test('«Ahora Plus hoy»: se quita «hoy» del final, no «ahora» del '
        'principio', () {
      expect(only(hear('Compré ahora plus hoy', similar)).product.value, ahora);
    });

    test('«Fungicida Hoy»: «hoy» es del nombre', () {
      expect(only(hear('Compré fungicida hoy', similar)).product.value, hoy);
    });
  });

  group('la traza no lleva texto', () {
    test('los códigos nuevos', () {
      final line = hear('No compré fungicida demo').trace
          .logLine(applied: 0, keptManual: 0);
      expect(line, contains('motivo=negacion'));
      expect(line.toLowerCase(), isNot(contains('fungicida')));
    });
  });
}
