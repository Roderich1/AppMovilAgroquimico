import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Moneda y unidad del precio por separado (F09, POCO 2026-11-09).
///
/// TEXTO INYECTADO al intérprete, no reconocimiento real. Frases propias,
/// ninguna del holdout de #12. «a 120 volviendo el litro» imita la forma de
/// lo que llegó al formulario en el POCO; «volviendo» **no** se convierte en
/// «bolivianos».
void main() {
  const herbicida = CatalogEntry(
    id: 1,
    name: 'Herbicida DEMO',
    unit: CatalogUnit.liter,
  );
  const mancozeb = CatalogEntry(
    id: 2,
    name: 'Mancozeb DEMO',
    unit: CatalogUnit.kilogram,
  );
  const glifosato = CatalogEntry(
    id: 3,
    name: 'Glifosato 480',
    unit: CatalogUnit.liter,
  );
  const catalog = VoiceCatalog(
    products: [herbicida, mancozeb, glifosato],
    suppliers: [],
    people: [],
    activeCampaign: CatalogEntry(id: 30, name: 'Campaña'),
  );

  VoicePurchaseDraft run(String text) =>
      interpretPurchase(text, VoicePurchaseDraft.start(catalog), catalog).draft;

  test('A: sin moneda pero con «el litro»: 120 por L, moneda pendiente', () {
    final l = run(
      'compré cinco litros de herbicida demo a ciento veinte el litro',
    ).lines.single;
    expect(l.quantity.value, const SpokenQuantity(5000, SpokenUnit.liter));
    expect(l.price.isResolved, isTrue);
    expect(l.unitPriceMinor, 12000);
    expect(l.price.value!.perUnit, CatalogUnit.liter);
    expect(l.currency.status, FieldStatus.missing);
  });

  test('B: una palabra desconocida entre el importe y «el litro» pregunta '
      '«¿120 por L?», no la sustituye y deja la moneda pendiente', () {
    final d = run('compré 5 litros de herbicida demo a 120 volviendo el litro');
    final l = d.lines.single;
    expect(l.product.value, herbicida);
    expect(l.price.status, FieldStatus.ambiguous);
    expect(l.unitPriceMinor, isNull);
    expect(l.price.message, contains('«volviendo»'));
    expect(l.price.message, contains('¿120 por L?'));
    expect(l.price.message, contains('La moneda sigue pendiente'));
    expect(l.price.heard, '120 volviendo el litro');
    expect(l.currency.status, FieldStatus.missing);
    expect(d.blockers, isNotEmpty);

    // «Por L» lo confirma; la moneda sigue sin elegir.
    final confirmed = l.pricePerUnitConfirmed();
    expect(confirmed.unitPriceMinor, 12000);
    expect(confirmed.price.origin, FieldOrigin.confirmed);
    expect(confirmed.currency.status, FieldStatus.missing);
  });

  test('C: importe sin unidad sigue pendiente entre unidad y total', () {
    final l = run('compré cinco litros de herbicida demo a ciento veinte')
        .lines
        .single;
    expect(l.price.status, FieldStatus.ambiguous);
    expect(l.price.message, unitNotSaidMessage);
    expect(l.currency.status, FieldStatus.missing);
  });

  test('con moneda dicha: precio por L y BOB', () {
    final l = run(
      'compré cinco litros de herbicida demo a ciento veinte bolivianos el '
      'litro',
    ).lines.single;
    expect(l.unitPriceMinor, 12000);
    expect(l.currency.value, CurrencyCode.bob);
  });

  test('dólares dichos no son una palabra desconocida', () {
    final l = run(
      'compré cinco litros de herbicida demo a doce dólares el litro',
    ).lines.single;
    expect(l.unitPriceMinor, 1200);
    expect(l.currency.value, CurrencyCode.usd);
  });

  test('un total dicho sigue siendo total, no precio por unidad', () {
    final l = run(
      'compré cuatro litros de herbicida demo por doscientos bolivianos en '
      'total',
    ).lines.single;
    expect(l.price.value?.total, isTrue);
    expect(l.unitPriceMinor, isNull);
  });

  test('en kilos pregunta «¿… por kg?»', () {
    final l = run('compré tres kilos de mancozeb demo a 35 vuelto el kilo')
        .lines
        .single;
    expect(l.price.status, FieldStatus.ambiguous);
    expect(l.price.message, contains('¿35 por kg?'));
    expect(l.currency.status, FieldStatus.missing);
  });

  test(
    'el número del nombre comercial no es precio ni palabra desconocida',
    () {
      final l = run('compré dos litros de glifosato 480 a 45 el litro')
          .lines
          .single;
      expect(l.product.value, glifosato);
      expect(l.unitPriceMinor, 4500);
      expect(l.currency.status, FieldStatus.missing);
    },
  );

  test('varias líneas y unidades: cada una con lo suyo', () {
    final d = run(
      'compré dos litros de herbicida demo a 50 el litro y tres kilos de '
      'mancozeb demo a 30 vuelto el kilo',
    );
    expect(d.lines, hasLength(2));
    expect(d.lines[0].unitPriceMinor, 5000);
    expect(d.lines[1].price.status, FieldStatus.ambiguous);
    expect(d.lines[1].price.message, contains('¿30 por kg?'));
  });

  test('dos palabras desconocidas no se interpretan: sigue ambiguo y '
      'bloqueado', () {
    final d = run(
      'compré cinco litros de herbicida demo a 120 volviendo otra el litro',
    );
    final l = d.lines.single;
    expect(l.price.status, FieldStatus.ambiguous);
    expect(l.price.message, unitNotSaidMessage);
    expect(d.blockers, isNotEmpty);
  });
}
