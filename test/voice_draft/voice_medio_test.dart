import 'package:agroquimicos/voice_draft/application/application_interpreter.dart';
import 'package:agroquimicos/voice_draft/application/voice_application_draft.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/plan/plan_interpreter.dart';
import 'package:agroquimicos/voice_draft/plan/voice_plan_draft.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// POCO §2.1 (2026-11-05, `docs/evidence/F09_VOZ_LOCAL_POCO_2026-11-05.md`):
/// «un litro y medio de glifosato» se leía como 1 L y el producto «y medio de
/// glifosato». Las cuatro primeras frases de compra son las del hallazgo
/// (frases de ajuste); el resto son propias. Ninguna sale del conjunto de
/// aceptación. La regla es del español hablado («y medio» tras la unidad, o
/// «litro y medio» sin número), no de ningún producto.
void main() {
  const glifosato = CatalogEntry(
    id: 1,
    name: 'Glifosato',
    unit: CatalogUnit.liter,
  );
  const mancozeb = CatalogEntry(
    id: 2,
    name: 'Mancozeb',
    unit: CatalogUnit.kilogram,
  );
  const sur = CatalogEntry(id: 12, name: 'Sur', areaM2: 30000);
  const jose = CatalogEntry(id: 20, name: 'José');
  const campaign = CatalogEntry(id: 30, name: 'Verano 2026');
  const catalog = VoiceCatalog(
    products: [glifosato, mancozeb],
    suppliers: [CatalogEntry(id: 40, name: 'Agro Norte')],
    people: [jose],
    farms: [sur],
    farmOwners: {12: jose},
    activeCampaign: campaign,
  );

  VoicePurchaseDraft purchase(String text) =>
      interpretPurchase(text, VoicePurchaseDraft.start(catalog), catalog).draft;

  group('compra', () {
    void expectLine(
      VoicePurchaseLine line,
      CatalogEntry product,
      int quantityBase,
    ) {
      expect(line.product.status, FieldStatus.resolved, reason: 'producto');
      expect(line.product.value, product);
      expect(line.quantity.status, FieldStatus.resolved, reason: 'cantidad');
      expect(line.quantityBase, quantityBase);
    }

    for (final text in const [
      'compré un litro y medio de glifosato por ciento ochenta o el hierbas',
      'Compre un litro y medio de Glifosato por 180 bolivianos.',
      'Compré 1 litro y medio de Glifosato por 180 bolivianos.',
      'compré uno y medio litros de glifosato por ciento ochenta bolivianos',
    ]) {
      test('POCO §2.1: «$text» → 1,5 L de Glifosato', () {
        final d = purchase(text);
        expect(d.lines, hasLength(1));
        expectLine(d.lines.single, glifosato, 1500);
      });
    }

    test('«medio litro» y «litro y medio» sin número', () {
      expectLine(
        purchase('compré medio litro de glifosato').lines.single,
        glifosato,
        500,
      );
      expectLine(
        purchase('compré litro y medio de glifosato').lines.single,
        glifosato,
        1500,
      );
    });

    test('«kilo y medio» y «dos kilos y medio»', () {
      expectLine(
        purchase('compré kilo y medio de mancozeb').lines.single,
        mancozeb,
        1500,
      );
      expectLine(
        purchase('compré dos kilos y medio de mancozeb').lines.single,
        mancozeb,
        2500,
      );
      expectLine(
        purchase('compré un kilo y media de mancozeb').lines.single,
        mancozeb,
        1500,
      );
    });

    test('dos líneas con medio en cada una', () {
      final d = purchase(
        'compré un litro y medio de glifosato y kilo y medio de mancozeb',
      );
      expect(d.lines, hasLength(2));
      expectLine(d.lines[0], glifosato, 1500);
      expectLine(d.lines[1], mancozeb, 1500);
    });

    test('el precio de la línea sigue leyéndose tras «y medio»', () {
      final line = purchase(
        'compré un litro y medio de glifosato a 180 bolivianos el litro',
      ).lines.single;
      expect(line.price.status, FieldStatus.resolved);
      expect(line.unitPriceMinor, 18000);
    });

    test('«1,5 litros y medio» no se adivina: la cantidad queda inválida', () {
      final line = purchase('compré 1,5 litros y medio de glifosato')
          .lines
          .single;
      expect(line.product.value, glifosato);
      expect(line.quantity.status, FieldStatus.invalid);
      expect(line.quantityBase, isNull);
    });

    test('sin «y medio» nada cambia: «un litro de glifosato» es 1 L', () {
      expectLine(
        purchase('compré un litro de glifosato').lines.single,
        glifosato,
        1000,
      );
    });
  });

  group('aplicación', () {
    VoiceApplicationDraft apply(String text) => interpretApplication(
      text,
      VoiceApplicationDraft.start(catalog),
      catalog,
    ).draft;

    test(
      '«un litro y medio de glifosato» y el área «una hectárea y media»',
      () {
        final d = apply(
          'apliqué un litro y medio de glifosato en el chaco Sur en una '
          'hectárea y media',
        );
        expect(d.lines, hasLength(1));
        expect(d.lines.single.product.value, glifosato);
        expect(d.lines.single.quantityBase, 1500);
        expect(d.area.value, 15000);
        expect(d.area.origin, FieldOrigin.voice);
      },
    );

    test('«litro y medio» sin número y «media hectárea»', () {
      final d = apply('apliqué litro y medio de glifosato en media hectárea');
      expect(d.lines.single.product.value, glifosato);
      expect(d.lines.single.quantityBase, 1500);
      expect(d.area.value, 5000);
    });

    test('«dos litros y media hectárea» son dos cantidades, no 2,5 L', () {
      final d = apply('apliqué de glifosato dos litros y media hectárea');
      expect(d.lines.single.quantityBase, 2000);
      expect(d.area.value, 5000);
    });

    test(
      '«kilo y medio por hectárea» sigue siendo una dosis, no lo aplicado',
      () {
        final d = apply('apliqué kilo y medio por hectárea de mancozeb');
        expect(d.lines, isEmpty);
      },
    );
  });

  group('planificación', () {
    VoicePlanDraft plan(String text) =>
        interpretPlan(text, VoicePlanDraft.start(catalog), catalog).draft;

    test('«litro y medio por hectárea de glifosato»', () {
      final d = plan(
        'planificar el chaco Sur con litro y medio por hectárea '
        'de glifosato',
      );
      expect(d.lines.single.product.value, glifosato);
      expect(d.lines.single.doseBasePerHa, 1500);
    });

    test('«mancozeb a un kilo y medio por hectárea»', () {
      final d = plan(
        'planificar el chaco Sur, mancozeb a un kilo y medio por '
        'hectárea',
      );
      expect(d.lines.single.product.value, mancozeb);
      expect(d.lines.single.doseBasePerHa, 1500);
    });
  });
}
