import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frases **escritas y sintéticas** para separar un fallo de transcripción de
/// un fallo del intérprete (experimento «un solo transcriptor por turno»,
/// 2026-11-09). No hay micrófono ni dictado real: cada frase entra ya como
/// texto, tal como la entregaría un transcriptor, y se comprueba el borrador.
///
/// El catálogo imita al de la instalación de demostración del POCO.
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
  // Un segundo fungicida sólo para el caso ambiguo.
  const fungicidaCobre = CatalogEntry(
    id: 4,
    name: 'Fungicida Cobre DEMO',
    unit: CatalogUnit.kilogram,
  );
  const agroinsumos = CatalogEntry(
    id: 10,
    name: 'Agroinsumos DEMO (sintético)',
  );
  const rosa = CatalogEntry(id: 20, name: 'Rosa Mamani F09');
  const beto = CatalogEntry(id: 21, name: 'Beto Mamani (DEMO)');
  const campaign = CatalogEntry(id: 30, name: 'Invierno 2026 (DEMO)');

  const catalog = VoiceCatalog(
    products: [herbicida, fungicida, insecticida],
    suppliers: [agroinsumos],
    people: [rosa, beto],
    activeCampaign: campaign,
  );
  const withTwoFungicides = VoiceCatalog(
    products: [herbicida, fungicida, insecticida, fungicidaCobre],
    suppliers: [agroinsumos],
    people: [rosa, beto],
    activeCampaign: campaign,
  );

  VoicePurchaseDraft dictate(List<String> segments, {VoiceCatalog? using}) {
    final c = using ?? catalog;
    var d = VoicePurchaseDraft.start(c);
    for (final s in segments) {
      d = interpretPurchase(s, d, c).draft;
    }
    return d;
  }

  group('1. «un litro y medio de …»', () {
    for (final text in const [
      'compré un litro y medio de fungicida demo',
      'Compré un litro y medio de Fungicida DEMO.',
      'compré 1 litro y medio de fungicida demo',
      'compré litro y medio de fungicida demo',
    ]) {
      test(text, () {
        final d = dictate([text]);
        expect(d.lines, hasLength(1));
        final l = d.lines.single;
        expect(l.product.status, FieldStatus.resolved);
        expect(
          l.product.value,
          fungicida,
          reason: 'el producto es el del catálogo',
        );
        expect(l.quantity.status, FieldStatus.resolved);
        expect(l.quantityBase, 1500, reason: '1,5 L en mililitros');
        expect(l.quantity.value?.unit, SpokenUnit.liter);
        // Sin precio dictado: pendiente, sin inventar nada.
        expect(l.price.value, isNull);
        expect(l.unitPriceMinor, isNull);
        expect(d.totalBobMinor, isNull);
      });
    }
  });

  group('2. cantidad, precio unitario y moneda', () {
    for (final text in const [
      'compré dos litros de fungicida demo a cincuenta bolivianos por litro',
      'compré dos litros de fungicida demo a cincuenta bolivianos el litro',
      'Compré 2 litros de Fungicida DEMO a 50 bolivianos por litro.',
    ]) {
      test(text, () {
        final d = dictate([text]);
        final l = d.lines.single;
        expect(l.product.value, fungicida);
        expect(l.quantityBase, 2000);
        expect(l.price.status, FieldStatus.resolved);
        expect(l.unitPriceMinor, 5000, reason: '50,00 Bs por litro');
        expect(l.price.value?.total, isFalse);
        expect(l.currency.status, FieldStatus.resolved);
        expect(l.currency.value, CurrencyCode.bob);
        expect(d.totalBobMinor, 10000, reason: '2 L × 50 Bs = 100,00 Bs');
      });
    }
  });

  group('3. precio total, distinto del unitario', () {
    test('«… a cien bolivianos en total»: el total no se toma como precio por '
        'litro', () {
      final l = dictate([
        'compré dos litros de fungicida demo a cien bolivianos en total',
      ]).lines.single;
      expect(l.product.value, fungicida);
      expect(l.quantityBase, 2000);
      expect(l.price.value?.total, isTrue);
      expect(l.price.value?.minorPerUnit, 10000, reason: 'importe dicho');
      // Un total queda para que la persona elija «Total de la línea»: no se
      // reparte solo ni se registra como unitario.
      expect(l.price.status, FieldStatus.ambiguous);
      expect(l.unitPriceMinor, isNull);
      expect(l.currency.value, CurrencyCode.bob);
    });

    test('«… cien bolivianos por todo»: no es una forma reconocida de total; '
        'lo seguro es que no quede como precio por litro', () {
      final l = dictate([
        'compré dos litros de fungicida demo a cien bolivianos por todo',
      ]).lines.single;
      expect(l.price.status, isNot(FieldStatus.resolved));
      expect(l.unitPriceMinor, isNull);
      expect(
        l.price.value?.minorPerUnit,
        10000,
        reason: 'el importe se conserva',
      );
    });

    test('el unitario y el total de la misma compra no se confunden', () {
      final unit = dictate([
        'compré dos litros de fungicida demo a cincuenta bolivianos el litro',
      ]).lines.single;
      final total = dictate([
        'compré dos litros de fungicida demo a cien bolivianos en total',
      ]).lines.single;
      expect(unit.unitPriceMinor, 5000);
      expect(unit.price.value?.total, isFalse);
      expect(total.unitPriceMinor, isNull);
      expect(total.price.value?.total, isTrue);
    });
  });

  group('4. frase incompleta: campos pendientes, nada inventado', () {
    test('sólo producto y cantidad: faltan precio y moneda; el proveedor '
        'sigue sin elegir', () {
      final d = dictate(['compré tres litros de herbicida demo']);
      final l = d.lines.single;
      expect(l.product.value, herbicida);
      expect(l.quantityBase, 3000);
      expect(l.price.status, FieldStatus.missing);
      expect(l.unitPriceMinor, isNull);
      expect(l.currency.value, isNull);
      expect(d.supplier.status, FieldStatus.missing);
      expect(d.totalBobMinor, isNull);
      expect(d.blockers, isNotEmpty, reason: 'no se puede registrar así');
    });

    test('sólo producto: la cantidad queda pendiente, no se pone 1', () {
      final d = dictate(['compré herbicida demo']);
      expect(d.lines, hasLength(1));
      final l = d.lines.single;
      expect(l.product.value, herbicida);
      expect(l.quantity.value, isNull);
      expect(l.quantityBase, isNull);
    });

    test('precio sin cantidad: la cantidad sigue pendiente', () {
      final l = dictate([
        'compré fungicida demo a cincuenta bolivianos el litro',
      ]).lines.single;
      expect(l.product.value, fungicida);
      expect(l.quantity.value, isNull);
      expect(l.unitPriceMinor, 5000);
    });
  });

  group('5. producto ambiguo: pide elegir, no aproxima', () {
    test('«fungicida» con dos fungicidas en el catálogo', () {
      final l = dictate([
        'compré dos litros de fungicida',
      ], using: withTwoFungicides).lines.single;
      expect(l.product.status, FieldStatus.ambiguous);
      expect(l.product.value, isNull);
      expect(l.product.candidates.map((c) => c.id).toSet(), {
        fungicida.id,
        fungicidaCobre.id,
      });
      // Sin producto resuelto no hay unidad base, pero lo dicho se conserva.
      expect(l.quantity.status, FieldStatus.resolved);
      expect(l.quantity.value?.thousandths, 2000);
      expect(l.quantity.value?.unit, SpokenUnit.liter);
    });

    test('un nombre que no está en el catálogo queda faltante, sin '
        'coincidencia aproximada', () {
      final l = dictate(['compré dos litros de fungisida']).lines.single;
      expect(l.product.status, isNot(FieldStatus.resolved));
      expect(l.product.value, isNull);
      expect(l.quantity.value?.thousandths, 2000);
      expect(l.quantity.value?.unit, SpokenUnit.liter);
    });

    test('con el nombre completo, se resuelve aunque haya dos fungicidas', () {
      final l = dictate([
        'compré dos litros de fungicida demo',
      ], using: withTwoFungicides).lines.single;
      expect(l.product.status, FieldStatus.resolved);
      expect(l.product.value, fungicida);
    });
  });

  group('6. frase completa de compra en un solo turno', () {
    test('producto, cantidad, precio, moneda y proveedor en una frase', () {
      final d = dictate([
        'compré dos litros de fungicida demo a cincuenta bolivianos el litro '
            'al proveedor agroinsumos demo sintético',
      ]);
      final l = d.lines.single;
      expect(l.product.value, fungicida);
      expect(l.quantityBase, 2000);
      expect(l.unitPriceMinor, 5000);
      expect(l.currency.value, CurrencyCode.bob);
      expect(d.totalBobMinor, 10000);
      // El proveedor: resuelto o, como mucho, propuesto para elegir; nunca
      // otro proveedor.
      if (d.supplier.status == FieldStatus.resolved) {
        expect(d.supplier.value, agroinsumos);
      } else {
        expect(d.supplier.candidates, anyOf(isEmpty, contains(agroinsumos)));
      }
    });
  });
}
