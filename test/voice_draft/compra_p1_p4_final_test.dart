import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los cuatro casos de la comprobación breve del 2026-11-10 (F09, small +
/// haz 5), sobre la versión final (`a340bbb`), con frases **escritas y
/// sintéticas** y el catálogo del POCO. Cada caso dice si el campo queda
/// resuelto solo o si hace falta una **intervención** de la persona; una
/// confirmación no se cuenta como reconocimiento automático. Se comprueba
/// además que la corrección de P4 (verbo pegado) no cambia P1–P3.
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
    suppliers: [CatalogEntry(id: 9, name: 'Agro insumos DEMO')],
    people: [],
  );

  PurchaseInterpretation hear(String text) =>
      interpretPurchase(text, VoicePurchaseDraft.start(catalog), catalog);

  VoicePurchaseLine only(String text) {
    final r = hear(text);
    expect(r.draft.lines, hasLength(1), reason: text);
    return r.draft.lines.single;
  }

  int? total(VoicePurchaseLine l) =>
      VoicePurchaseDraft.start(catalog).copyWith(lines: [l]).totalBobMinor;

  group('P1 precio unitario: Fungicida DEMO, 2 L, 50 Bs/L, BOB', () {
    test('dicho con «el litro»: todo resuelto solo, total 100,00', () {
      final l = only(
        'Compré dos litros de fungicida demo a cincuenta bolivianos el litro',
      );
      expect(l.product.value, fungicida);
      expect(l.quantityBase, 2000);
      expect(l.price.status, FieldStatus.resolved);
      expect(l.price.origin, FieldOrigin.voice);
      expect(l.unitPriceMinor, 5000);
      expect(l.currency.value, CurrencyCode.bob);
      expect(total(l), 10000);
    });

    test('con una preposición entre cifra y unidad (lo visto en el '
        'teléfono): 50 por confirmar; «Por L» es una intervención', () {
      for (final text in const [
        'Compré dos litros de fungicida demo a cincuenta bolivianos de litro',
        'Compré dos litros de fungicida demo a cincuenta bolivianos en el '
            'litro',
      ]) {
        final l = only(text);
        expect(l.price.status, FieldStatus.ambiguous, reason: text);
        expect(l.price.value?.minorPerUnit, 5000, reason: text);
        expect(l.unitPriceMinor, isNull, reason: 'no se presenta como hecho');
        final confirmed = l.pricePerUnitConfirmed();
        expect(confirmed.price.status, FieldStatus.resolved);
        expect(confirmed.price.origin, FieldOrigin.confirmed);
        expect(confirmed.unitPriceMinor, 5000);
        expect(total(confirmed), 10000);
      }
    });
  });

  group('P2 precio total: Insecticida DEMO, 2 L, total 100 Bs', () {
    test('el total queda por confirmar con su cifra; «Total de la línea» '
        '(intervención) lo reparte a 50 Bs/L y el total sigue en 100', () {
      final l = only(
        'Compré dos litros de insecticida demo por un total de cien '
        'bolivianos',
      );
      expect(l.product.value, insecticida);
      expect(l.quantityBase, 2000);
      expect(l.price.status, FieldStatus.ambiguous);
      expect(l.price.value?.total, isTrue);
      expect(l.price.value?.minorPerUnit, 10000);
      expect(l.price.message, contains('100 Bs (sin confirmar)'));
      expect(l.unitPriceMinor, isNull);
      expect(
        l.pricePerUnitConfirmed(),
        same(l),
        reason: 'un total no es «Por L»',
      );
      final split = l.priceFromLineTotal();
      expect(split.price.origin, FieldOrigin.confirmed);
      expect(split.unitPriceMinor, 5000);
      expect(total(split), 10000);
    });

    test('un total que no da centavos exactos no se redondea', () {
      final l = only(
        'Compré tres litros de insecticida demo por un total de cien '
        'bolivianos',
      );
      expect(l.priceFromLineTotal().unitPriceMinor, isNull);
    });
  });

  group('P3 cantidad decimal y nombre: Herbicida DEMO, 1,5 L, 80 Bs/L', () {
    test('todo resuelto solo, total 120,00', () {
      for (final text in const [
        'Compré un litro y medio de herbicida demo a ochenta bolivianos el '
            'litro',
        'Compré 1,5 litros de herbicida demo a ochenta bolivianos el litro',
        'Compré 1.5 litros de Herbicida DEMO a 80 Bs el litro.',
      ]) {
        final l = only(text);
        expect(l.product.value, herbicida, reason: text);
        expect(l.quantityBase, 1500, reason: text);
        expect(l.price.status, FieldStatus.resolved, reason: text);
        expect(l.unitPriceMinor, 8000, reason: text);
        expect(total(l), 12000, reason: text);
      }
    });
  });

  group('P4 sólo producto: una línea incompleta, registro bloqueado', () {
    for (final text in const [
      'Compré fungicida demo',
      'Compréfungicida DEMO.',
    ]) {
      test('«$text»', () async {
        final r = hear(text);
        final l = r.draft.lines.single;
        expect(l.product.value, fungicida);
        expect(l.quantity.status, FieldStatus.missing);
        expect(l.price.status, FieldStatus.missing);
        expect(l.currency.status, FieldStatus.missing);
        var writes = 0;
        final c = VoiceDraftController<VoicePurchaseDraft, int>(
          initial: VoicePurchaseDraft.start(catalog),
          commit: (_) async => ++writes,
        );
        c.applyVoice((d) {
          final x = interpretPurchase(text, d, catalog);
          return (x.draft, x.outcome);
        });
        expect(c.blockers, contains('Línea 1: falta cantidad.'));
        expect(c.blockers, contains('Línea 1: falta precio.'));
        expect(c.blockers, contains('Línea 1: falta moneda.'));
        expect(c.canConfirm, isFalse);
        expect(await c.confirm(), isNull);
        expect(writes, 0);
      });
    }
  });

  test('la corrección de P4 no cambia P1–P3: con el verbo pegado salen los '
      'mismos campos que separado', () {
    const pairs = [
      (
        'Compré dos litros de fungicida demo a cincuenta bolivianos el litro',
        'Compré dos litros de fungicida demo a cincuenta bolivianos el litro',
      ),
      (
        'Compré dos litros de insecticida demo por un total de cien bolivianos',
        'Compré dos litros de insecticida demo por un total de cien bolivianos',
      ),
      (
        'Compré un litro y medio de herbicida demo a ochenta bolivianos el '
            'litro',
        'Compré un litro y medio de herbicida demo a ochenta bolivianos el '
            'litro',
      ),
    ];
    for (final (a, b) in pairs) {
      final x = only(a);
      final y = only(b.replaceFirst('Compré ', 'Compré'));
      expect(y.product.value, x.product.value, reason: b);
      expect(y.quantityBase, x.quantityBase, reason: b);
      expect(y.price.value, x.price.value, reason: b);
      expect(y.price.status, x.price.status, reason: b);
      expect(y.currency.value, x.currency.value, reason: b);
    }
  });
}
