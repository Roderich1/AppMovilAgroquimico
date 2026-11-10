import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/interpretation/voice_intent.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Interpretación de la compra por voz tras la prueba del autor en el POCO
/// (2026-11-08, datos sintéticos): precio separado del nombre, precio mal
/// transcrito que no se da por bueno, destinatario con «va para», proveedor
/// dicho «provedor» y precio dicho aparte.
///
/// Frases propias, escritas para demostrar cada regla general con variantes;
/// ninguna del corpus de aceptación.
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
  const mancozeb = CatalogEntry(
    id: 4,
    name: 'Mancozeb DEMO',
    unit: CatalogUnit.kilogram,
  );
  const germi = CatalogEntry(id: 5, name: 'Germi-100', unit: CatalogUnit.liter);
  const glifosato = CatalogEntry(
    id: 6,
    name: 'Glifosato 480',
    unit: CatalogUnit.liter,
  );
  const amina = CatalogEntry(
    id: 7,
    name: '2,4-D Amina 720',
    unit: CatalogUnit.liter,
  );
  const agroinsumos = CatalogEntry(
    id: 10,
    name: 'Agroinsumos DEMO (sintético)',
  );
  const rosa = CatalogEntry(id: 20, name: 'Rosa Mamani F09');
  const beto = CatalogEntry(id: 21, name: 'Beto Mamani (DEMO)');
  const carmen = CatalogEntry(id: 22, name: 'Carmen Choque (DEMO, tercera)');
  const campaign = CatalogEntry(id: 30, name: 'Campaña DEMO');

  const catalog = VoiceCatalog(
    products: [
      herbicida,
      fungicida,
      insecticida,
      mancozeb,
      germi,
      glifosato,
      amina,
    ],
    suppliers: [agroinsumos],
    people: [rosa, beto, carmen],
    activeCampaign: campaign,
  );

  PurchaseInterpretation run(
    String text, {
    VoicePurchaseDraft? current,
    VoiceCatalog using = catalog,
  }) => interpretPurchase(
    text,
    current ?? VoicePurchaseDraft.start(using),
    using,
  );

  VoicePurchaseDraft dictate(List<String> segments, {VoiceCatalog? using}) {
    final c = using ?? catalog;
    var d = VoicePurchaseDraft.start(c);
    for (final s in segments) {
      d = interpretPurchase(s, d, c).draft;
    }
    return d;
  }

  group('A. el precio se separa del nombre del producto', () {
    test('el caso observado: el precio mal transcrito no se da por bueno, '
        'nunca vale 120 y no acaba en el nombre', () {
      final d = dictate([
        'compré cinco litros de herbicidas demo haciendo veinte bolivianas '
            'litro',
      ]);
      final line = d.lines.single;
      // La cantidad se leyó (la base en ML espera a que se elija el producto).
      expect(line.quantity.value, const SpokenQuantity(5000, SpokenUnit.liter));
      // El nombre ya no se come el precio: queda lo dicho del producto, que
      // se propone (plural) sin elegirse solo.
      expect(line.product.heard, 'herbicidas demo');
      expect(line.product.status, FieldStatus.ambiguous);
      expect(line.product.candidates, [herbicida]);
      // El precio: no resuelto, sin valor, con lo oído y pidiendo repetirlo.
      expect(line.price.status, FieldStatus.invalid);
      expect(line.price.isResolved, isFalse);
      expect(line.price.value, isNull);
      expect(line.price.heard, 'haciendo veinte bolivianas litro');
      expect(line.price.message, contains('no se entendió bien'));
      expect(line.unitPriceMinor, isNull);
      // «bolivianas» corta el nombre, pero no da la moneda por buena.
      expect(line.currency.status, FieldStatus.missing);
      expect(d.blockers.join(' '), contains('precio no válido'));
      expect(d.totalBobMinor, isNull);
    });

    test('variantes de mala transcripción sin «a»: nunca resuelto ni con '
        'valor aceptado', () {
      // Palabra extraña antes de la cifra o moneda deformada: no válido, sin
      // valor (no se reconstruye nada).
      for (final text in const [
        'compré tres litros de fungicida demo cuando cuarenta bolivianos el '
            'litro',
        'compré tres litros de fungicida demo cuarenta bolivianas el litro',
      ]) {
        final line = dictate([text]).lines.single;
        expect(line.product.value, fungicida, reason: text);
        expect(line.price.status, FieldStatus.invalid, reason: text);
        expect(line.price.value, isNull, reason: text);
        expect(line.unitPriceMinor, isNull, reason: text);
        expect(line.price.heard, contains('cuarenta'), reason: text);
      }
      // Estructura incompleta sin palabra extraña (2026-11-09, aprobado por
      // el autor): la cifra queda a la vista **pendiente de confirmar**, sin
      // aceptarse, y la moneda dicha se conserva por revisar.
      for (final text in const [
        // Falta «el» antes de la unidad.
        'compré tres litros de fungicida demo cuarenta bolivianos litro',
        // «de litro» no es una forma clara de precio unitario.
        'compré tres litros de fungicida demo cuarenta bolivianos de litro',
        // Sin unidad: ¿por litro o total?
        'compré tres litros de fungicida demo cuarenta bolivianos',
      ]) {
        final line = dictate([text]).lines.single;
        expect(line.product.value, fungicida, reason: text);
        expect(line.price.isResolved, isFalse, reason: text);
        expect(line.price.status, FieldStatus.ambiguous, reason: text);
        expect(line.unitPriceMinor, isNull, reason: text);
        expect(line.price.value?.minorPerUnit, 4000, reason: text);
        expect(line.price.value?.perUnit, isNull, reason: text);
        expect(line.price.heard, contains('cuarenta'), reason: text);
        expect(line.currency.value, CurrencyCode.bob, reason: text);
        expect(line.currency.isResolved, isFalse, reason: text);
      }
    });

    test('sin «a» y con la cláusula completa y limpia: queda por revisar con '
        'el valor a la vista, y confirmarlo lo resuelve', () {
      for (final text in const [
        'compré cinco litros de herbicida demo ciento veinte bolivianos el '
            'litro',
        'compré cinco litros de herbicida demo, ciento veinte bolivianos el '
            'litro',
        'compré cinco litros de herbicida demo de ciento veinte bolivianos '
            'por litro',
      ]) {
        final d = dictate([text]);
        final line = d.lines.single;
        expect(line.product.value, herbicida, reason: text);
        expect(line.price.review, isTrue, reason: text);
        expect(line.price.isResolved, isFalse, reason: text);
        expect(
          line.price.value,
          const SpokenPrice(12000, perUnit: CatalogUnit.liter),
          reason: text,
        );
        expect(line.price.message, contains('sin «a»'), reason: text);
        expect(line.currency.value, CurrencyCode.bob, reason: text);
        expect(line.unitPriceMinor, isNull, reason: text);
        expect(d.blockers.join(' '), contains('precio por revisar'));

        final confirmed = d.updateLine(
          line.key,
          (l) => l.copyWith(price: l.price.confirmedByUser()),
        );
        expect(confirmed.lines.single.unitPriceMinor, 12000, reason: text);
        expect(
          confirmed.lines.single.price.origin,
          FieldOrigin.confirmed,
          reason: text,
        );
      }
    });

    test('con conector se mantiene lo de antes: unitario resuelto, sin '
        'unidad ambiguo y total no válido', () {
      final unit = dictate([
        'compré cinco litros de herbicida demo a ciento veinte bolivianos el '
            'litro',
      ]).lines.single;
      expect(unit.price.isResolved, isTrue);
      expect(unit.unitPriceMinor, 12000);
      expect(unit.price.heard, 'ciento veinte bolivianos el litro');
      expect(unit.currency.value, CurrencyCode.bob);

      final perEach = dictate([
        'compré dos kilos de mancozeb demo por 35 bolivianos cada kilo',
      ]).lines.single;
      expect(perEach.unitPriceMinor, 3500);

      final noUnit = dictate([
        'compré cinco litros de herbicida demo a ciento veinte bolivianos',
      ]).lines.single;
      expect(noUnit.price.status, FieldStatus.ambiguous);
      expect(noUnit.price.review, isFalse);
      expect(noUnit.price.value?.minorPerUnit, 12000);
      expect(noUnit.price.message, unitNotSaidMessage);

      // Un total dicho no se registra como precio por unidad: queda para
      // elegir «Total de la línea» (antes era no válido sin opción).
      final total = dictate([
        'compré cinco litros de herbicida demo a 600 bolivianos en total',
      ]).lines.single;
      expect(total.price.status, FieldStatus.ambiguous);
      expect(total.price.value?.total, isTrue);
      // Desde 2026-11-10 el aviso lleva además la cifra oída, sin confirmar.
      expect(total.price.message, totalSaidMessageFor(60000, CurrencyCode.bob));
      expect(total.price.message, contains(totalSaidMessage));
      expect(total.unitPriceMinor, isNull);

      // Con pausa antes de la «a», y con «precio de»: igual.
      for (final text in const [
        'compré cinco litros de herbicida demo, a ciento veinte bolivianos '
            'el litro',
        'compré cinco litros de herbicida demo con el precio de ciento '
            'veinte bolivianos el litro',
        'compré cinco litros de herbicida demo a un precio de ciento veinte '
            'bolivianos el litro',
      ]) {
        final line = dictate([text]).lines.single;
        expect(line.product.value, herbicida, reason: text);
        expect(line.unitPriceMinor, 12000, reason: text);
      }
    });

    test('con conector y moneda deformada la cifra queda por revisar y la '
        'moneda sin elegir', () {
      final line = dictate([
        'compré cinco litros de herbicida demo a ciento veinte bolivianas el '
            'litro',
      ]).lines.single;
      expect(line.product.value, herbicida);
      expect(line.price.review, isTrue);
      expect(line.price.value?.minorPerUnit, 12000);
      expect(line.currency.status, FieldStatus.missing);
    });

    test('un número sin moneda detrás sigue siendo parte del nombre', () {
      final cases = <String, CatalogEntry>{
        'compré diez litros de Germi cien a setenta bolivianos el litro': germi,
        'compré diez litros de glifosato 480 a 45 bolivianos el litro':
            glifosato,
        'compré cuatro litros de 2,4-D amina 720 a 60 bolivianos el litro':
            amina,
      };
      for (final MapEntry(key: text, value: product) in cases.entries) {
        final line = dictate([text]).lines.single;
        expect(line.product.value, product, reason: text);
        expect(line.price.isResolved, isTrue, reason: text);
      }
      // Sin «a»: el número del nombre se queda en el nombre y la cifra con
      // moneda es el precio, por revisar.
      final noConnector = dictate([
        'compré diez litros de glifosato 480 45 bolivianos el litro',
      ]).lines.single;
      expect(noConnector.product.value, glifosato);
      expect(noConnector.price.review, isTrue);
      expect(noConnector.price.value?.minorPerUnit, 4500);

      final germiNoConnector = dictate([
        'compré diez litros de Germi cien ciento veinte bolivianos el litro',
      ]).lines.single;
      expect(germiNoConnector.product.value, germi);
      expect(germiNoConnector.price.review, isTrue);
      expect(germiNoConnector.price.value?.minorPerUnit, 12000);
    });

    test('un nombre que no está en el catálogo no pierde palabras si es la '
        'única', () {
      final line = dictate([
        'compré cinco litros de Paraquat ciento veinte bolivianos el litro',
      ]).lines.single;
      expect(line.product.heard, 'paraquat');
      expect(line.product.status, FieldStatus.missing);
      expect(line.price.review, isTrue);
    });

    test('dos líneas con el precio sin «a» en la primera no se mezclan', () {
      final d = dictate([
        'compré cinco litros de herbicida demo ciento veinte bolivianos el '
            'litro y dos kilos de mancozeb demo a 35 bolivianos el kilo',
      ]);
      expect(d.lines.map((l) => l.product.value), [herbicida, mancozeb]);
      expect(d.lines.first.price.review, isTrue);
      expect(d.lines.last.unitPriceMinor, 3500);
    });
  });

  group('B. destinatario', () {
    test('«esta compra va para …»: la compra es el sujeto', () {
      final r = run('Esta compra va para Beto Mamani.');
      expect(r.draft.recipient.status, FieldStatus.ambiguous);
      expect(r.draft.recipient.candidates, [beto]);
      expect(r.outcome.applied, 1);

      final exact = run('la compra es para Beto Mamani demo');
      expect(exact.draft.recipient.value, beto);
      expect(exact.draft.recipient.isResolved, isTrue);

      // No está entre las personas elegibles: faltante, sin crear nada.
      final unknown = run('esta compra va para Pedro Quispe');
      expect(unknown.draft.recipient.status, FieldStatus.missing);
      expect(unknown.draft.recipient.heard, 'pedro quispe');
    });

    test('«es para …» / «va para …» sin la compra: sólo si empieza por una '
        'persona elegible', () {
      final es = run('es para Carmen Choque');
      expect(es.draft.recipient.candidates, [carmen]);
      final va = run(
        'compré cinco litros de herbicida demo, va para Rosa '
        'Mamani',
      );
      expect(va.draft.recipient.candidates, [rosa]);
      expect(va.draft.lines.single.product.value, herbicida);

      // Alguien que no está: no se toma (podría ser un uso).
      final other = run('es para Pedro Quispe');
      expect(other.draft.recipient.status, FieldStatus.missing);
      expect(other.draft.recipient.heard, isNull);
      expect(other.outcome.applied, 0);
    });

    test('los usos del producto no son destinatarios', () {
      final start = VoicePurchaseDraft.start(catalog).copyWith(
        recipient: const DraftField.resolved(beto, origin: FieldOrigin.voice),
      );
      for (final text in const [
        'es para el maíz',
        'va para la plaga',
        'va para el chaco norte',
        'es para la parcela del fondo',
        'esta compra es para el maíz',
        'la compra va para el chaco norte',
        'esta compra es para controlar la roya',
        'es para mi soya',
        'compré cinco litros de herbicida demo a 120 bolivianos el litro, es '
            'para el maíz',
      ]) {
        final r = run(text, current: start);
        expect(r.draft.recipient.value, beto, reason: text);
        expect(r.draft.recipient.isResolved, isTrue, reason: text);
        expect(r.ignoredRecipient, isNull, reason: text);
      }
      // «fumigar» es otra operación: no se toca nada.
      final fumigar = run('es para fumigar', current: start);
      expect(fumigar.otherIntent, VoiceIntent.application);
      expect(identical(fumigar.draft, start), isTrue);
    });

    test('un nombre de persona que parece infinitivo sigue siendo persona', () {
      const javier = CatalogEntry(id: 23, name: 'Javier Choque');
      final r = run(
        'es para Javier Choque',
        using: catalog.copyWith(people: [rosa, beto, javier]),
      );
      expect(r.draft.recipient.value, javier);
    });

    test('en inventario propio la persona dictada se ignora y se informa', () {
      const personal = VoiceCatalog(
        products: [herbicida],
        suppliers: [agroinsumos],
        people: [rosa],
        personalOwner: rosa,
        activeCampaign: campaign,
      );
      final r = run('esta compra va para Beto Mamani', using: personal);
      expect(r.ignoredRecipient, 'beto mamani');
      expect(r.draft.recipient.value, rosa);
      expect(r.draft.recipient.origin, FieldOrigin.preset);

      // «es para …» sin la compra y con alguien que no es elegible: no se
      // toma como persona y no hay nada que avisar.
      expect(
        run('es para Beto Mamani', using: personal).ignoredRecipient,
        isNull,
      );
    });

    test('una persona elegida a mano no la cambia la voz', () {
      final start = VoicePurchaseDraft.start(catalog).copyWith(
        recipient: const DraftField.resolved(rosa, origin: FieldOrigin.manual),
      );
      final r = run('esta compra va para Carmen Choque', current: start);
      expect(r.draft.recipient.value, rosa);
      expect(r.outcome.keptManual, 1);
    });

    test('«todo para …» sigue igual', () {
      final r = run('todo queda asignado a Beto Mamani demo');
      expect(r.draft.recipient.value, beto);
    });
  });

  group('C. proveedor', () {
    test('«provedor» es la palabra clave; lo aproximado queda ambiguo', () {
      final near = run('Provedor Agroinsumos DEMO.');
      expect(near.draft.supplier.status, FieldStatus.ambiguous);
      expect(near.draft.supplier.candidates, [agroinsumos]);

      // El paréntesis no cuenta para comparar: el nombre completo resuelve.
      for (final text in const [
        'provedor agroinsumos demo sintético',
        'la provedora es Agroinsumos DEMO sintético',
        'el proveedor es agroinsumos demo sintetico',
      ]) {
        expect(run(text).draft.supplier.value, agroinsumos, reason: text);
      }
    });

    test('un proveedor que no está queda faltante; varios parecidos, '
        'ambiguo', () {
      final missing = run('provedor Agro Sur');
      expect(missing.draft.supplier.status, FieldStatus.missing);
      expect(missing.draft.supplier.heard, 'agro sur');

      const other = CatalogEntry(id: 11, name: 'Agroinsumos DEMO Norte');
      final several = run(
        'provedor agroinsumos demo',
        using: catalog.copyWith(suppliers: [agroinsumos, other]),
      );
      expect(several.draft.supplier.status, FieldStatus.ambiguous);
      expect(
        several.draft.supplier.candidates,
        containsAll([agroinsumos, other]),
      );
    });

    test('«provedor» corta el nombre del producto y no completa una línea en '
        'espera', () {
      final d = dictate([
        'compré cinco litros de herbicida demo provedor agroinsumos demo '
            'sintético',
      ]);
      expect(d.lines.single.product.value, herbicida);
      expect(d.supplier.value, agroinsumos);

      final waiting = dictate([
        'compré tres litros de',
        'provedor agroinsumos demo sintético',
      ]);
      expect(waiting.lines.single.product.status, FieldStatus.missing);
      expect(waiting.supplier.value, agroinsumos);
    });
  });

  group('D. precio dicho aparte', () {
    test('con una sola línea que puede recibirlo, se pone en ella', () {
      final r = run(
        'a ciento veinte bolivianos el litro',
        current: dictate(['compré cinco litros de herbicida demo']),
      );
      expect(r.unplacedPrice, isNull);
      final line = r.draft.lines.single;
      expect(line.price.isResolved, isTrue);
      expect(line.unitPriceMinor, 12000);
      expect(line.currency.value, CurrencyCode.bob);
      expect(r.outcome.applied, 2);

      final precio = run(
        'el precio es ciento veinte bolivianos el litro',
        current: dictate(['compré cinco litros de herbicida demo']),
      );
      expect(precio.draft.lines.single.unitPriceMinor, 12000);
    });

    test('sin «a», como mucho por revisar', () {
      final r = run(
        'ciento veinte bolivianos el litro',
        current: dictate(['compré cinco litros de herbicida demo']),
      );
      expect(r.unplacedPrice, isNull);
      expect(r.draft.lines.single.price.review, isTrue);
      expect(r.draft.lines.single.price.value?.minorPerUnit, 12000);
    });

    test('la línea objetivo es la única sin precio, no la última', () {
      final d = dictate([
        'compré cinco litros de herbicida demo y dos litros de fungicida demo '
            'a 80 bolivianos el litro',
        'a cincuenta bolivianos el litro',
      ]);
      expect(d.lines.first.unitPriceMinor, 5000);
      expect(d.lines.last.unitPriceMinor, 8000);
    });

    test('con varias líneas posibles no cambia ninguna y lo dice', () {
      final before = dictate([
        'compré cinco litros de herbicida demo y dos litros de fungicida demo',
      ]);
      final r = run('a cincuenta bolivianos el litro', current: before);
      expect(r.draft.lines, before.lines);
      for (final l in r.draft.lines) {
        expect(l.price.status, FieldStatus.missing);
      }
      expect(r.unplacedPrice?.reason, UnplacedPriceReason.severalLines);
      expect(r.unplacedPrice?.heard, 'cincuenta bolivianos el litro');
      expect(r.unplacedPrice?.message, contains('no se sabe a qué línea va'));
      expect(r.outcome.applied, 0);
    });

    test(
      'ninguna línea, una sin producto, o la unidad no casa: no se pone',
      () {
        final none = run('a cincuenta bolivianos el litro');
        expect(none.draft.lines, isEmpty);
        expect(none.unplacedPrice?.reason, UnplacedPriceReason.noLine);

        final waiting = run(
          'a cincuenta bolivianos el litro',
          current: dictate(['compré tres litros de']),
        );
        expect(waiting.draft.lines.single.price.status, FieldStatus.missing);
        expect(waiting.unplacedPrice?.reason, UnplacedPriceReason.noLine);

        final kilos = run(
          'a cincuenta bolivianos el litro',
          current: dictate(['compré dos kilos de mancozeb demo']),
        );
        expect(kilos.draft.lines.single.price.status, FieldStatus.missing);
        expect(kilos.unplacedPrice?.reason, UnplacedPriceReason.unitMismatch);
      },
    );

    test('precio poco claro, sin unidad o total: no se pone y se informa', () {
      final current = dictate(['compré cinco litros de herbicida demo']);
      final cases = <String, UnplacedPriceReason>{
        '50 bolivianos de litro.': UnplacedPriceReason.unitNotSaid,
        'a cincuenta bolivianos de litro': UnplacedPriceReason.unitNotSaid,
        'a cincuenta bolivianos': UnplacedPriceReason.unitNotSaid,
        'cincuenta bolivianos litro': UnplacedPriceReason.unitNotSaid,
        'a 600 bolivianos en total': UnplacedPriceReason.total,
        'haciendo veinte bolivianas litro': UnplacedPriceReason.unclear,
        'cincuenta bolivianas el litro': UnplacedPriceReason.unclear,
      };
      for (final MapEntry(key: text, value: reason) in cases.entries) {
        final r = run(text, current: current);
        expect(r.draft.lines, current.lines, reason: text);
        expect(r.unplacedPrice?.reason, reason, reason: text);
        expect(r.unplacedPrice?.message, contains('Se oyó un precio'));
      }
    });

    test('un precio suelto junto a otra línea en el mismo dictado no se '
        'reparte', () {
      final r = run(
        'compré dos litros de fungicida demo, y a cincuenta bolivianos el '
        'litro',
        current: dictate(['compré cinco litros de herbicida demo']),
      );
      expect(r.draft.lines, hasLength(2));
      expect(r.draft.lines.every((l) => !l.price.isResolved), isTrue);
      expect(r.unplacedPrice?.reason, UnplacedPriceReason.notAlone);
    });

    test('lo puesto a mano se respeta', () {
      var d = dictate(['compré cinco litros de herbicida demo']);
      d = d.updateLine(
        d.lines.single.key,
        (l) => l.copyWith(
          price: const DraftField.resolved(
            SpokenPrice(11000),
            origin: FieldOrigin.manual,
          ),
        ),
      );
      final r = run('a cincuenta bolivianos el litro', current: d);
      expect(r.draft.lines.single.unitPriceMinor, 11000);
      expect(r.unplacedPrice?.reason, UnplacedPriceReason.noLine);

      // Moneda elegida a mano: el precio entra y la moneda no cambia.
      var usd = dictate(['compré cinco litros de herbicida demo']);
      usd = usd.updateLine(
        usd.lines.single.key,
        (l) => l.copyWith(
          currency: const DraftField.resolved(
            CurrencyCode.usd,
            origin: FieldOrigin.manual,
          ),
        ),
      );
      final r2 = run('a cincuenta bolivianos el litro', current: usd);
      expect(r2.draft.lines.single.unitPriceMinor, 5000);
      expect(r2.draft.lines.single.currency.value, CurrencyCode.usd);
      expect(r2.outcome.keptManual, 1);
    });

    test('la cifra del tipo de cambio no es un precio suelto', () {
      final r = run(
        'tipo de cambio 6,96 bolivianos',
        current: dictate(['compré cinco litros de herbicida demo']),
      );
      expect(r.unplacedPrice, isNull);
      expect(r.draft.exchangeRate.value, 6960000);
      expect(r.draft.lines.single.price.status, FieldStatus.missing);
    });
  });

  group('sin regresiones', () {
    test('«un litro y medio» con y sin «a»', () {
      final a = dictate([
        'compré un litro y medio de insecticida demo a 90 bolivianos el litro',
      ]).lines.single;
      expect(a.quantityBase, 1500);
      expect(a.product.value, insecticida);
      expect(a.unitPriceMinor, 9000);

      final b = dictate([
        'compré litro y medio de insecticida demo noventa bolivianos el litro',
      ]).lines.single;
      expect(b.quantityBase, 1500);
      expect(b.product.value, insecticida);
      expect(b.price.review, isTrue);
    });

    test('la pausa: «compré tres litros de» + «insecticida demo»', () {
      final d = dictate(['compré tres litros de', 'insecticida demo']);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.product.value, insecticida);
      expect(d.lines.single.quantityBase, 3000);
    });
  });
}
