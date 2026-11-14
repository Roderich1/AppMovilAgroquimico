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

/// POCO §2.2 (2026-11-05; la sesión A lo reprodujo en HOST con audio
/// sintético): una pausa parte la frase en dos tramos cerrados y el borrador
/// interpretaba cada uno por separado, así que el producto dicho tras la
/// pausa se perdía. Frases propias; ninguna del conjunto de aceptación.
void main() {
  const mancozeb = CatalogEntry(
    id: 1,
    name: 'Mancozeb',
    unit: CatalogUnit.kilogram,
  );
  const bellator = CatalogEntry(
    id: 2,
    name: 'Bellator',
    unit: CatalogUnit.liter,
  );
  const belator = CatalogEntry(id: 3, name: 'Belator', unit: CatalogUnit.liter);
  const norte = CatalogEntry(id: 10, name: 'Norte', areaM2: 50000);
  const jose = CatalogEntry(id: 20, name: 'José');
  const catalog = VoiceCatalog(
    products: [mancozeb, bellator, belator],
    suppliers: [CatalogEntry(id: 30, name: 'Agro Norte')],
    people: [jose],
    farms: [norte],
    farmOwners: {10: jose},
    activeCampaign: CatalogEntry(id: 40, name: 'Verano'),
  );

  group('compra', () {
    VoicePurchaseDraft dictate(List<String> segments) {
      var d = VoicePurchaseDraft.start(catalog);
      for (final s in segments) {
        d = interpretPurchase(s, d, catalog).draft;
      }
      return d;
    }

    test('«compré cinco kilos de» [pausa] «Mancozeb»: una línea completa', () {
      final d = dictate(['compré cinco kilos de', 'Mancozeb']);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.product.value, mancozeb);
      expect(d.lines.single.product.origin, FieldOrigin.voice);
      expect(d.lines.single.quantityBase, 5000);
    });

    test('antes de la pausa la línea se ve y espera el producto', () {
      final d = dictate(['compré cinco kilos de']);
      expect(d.lines.single.quantityBase, isNull);
      expect(d.lines.single.product.status, FieldStatus.missing);
      expect(d.blockers.join(' '), contains('falta producto'));
    });

    test('un nombre que no está en el catálogo queda faltante, sin crear', () {
      final d = dictate(['compré cinco kilos de', 'de Paraquat']);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.product.status, FieldStatus.missing);
      expect(d.lines.single.product.heard, 'paraquat');
    });

    test('con varias candidatas queda ambiguo, no se elige', () {
      final d = dictate(['compré dos litros', 'belatorr']);
      expect(d.lines.single.product.status, FieldStatus.ambiguous);
      expect(
        d.lines.single.product.candidates,
        containsAll([bellator, belator]),
      );
    });

    test('un nombre suelto no crea una línea nueva ni toca una completa', () {
      final d = dictate([
        'compré cinco kilos de Mancozeb a 30 bolivianos el kilo',
        'Bellator',
      ]);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.product.value, mancozeb);
    });

    test('la línea espera sólo al tramo siguiente que dice un nombre: un '
        'tramo con más datos no la completa', () {
      final d = dictate(['compré cinco kilos de', 'proveedor Agro Norte']);
      expect(d.lines.single.product.status, FieldStatus.missing);
      expect(d.supplier.isResolved, isTrue);
    });

    test('una corrección a mano del producto no la cambia el tramo tardío', () {
      var d = dictate(['compré cinco kilos de']);
      d = d.updateLine(
        d.lines.single.key,
        (l) => l.copyWith(
          product: const DraftField.resolved(
            mancozeb,
            origin: FieldOrigin.manual,
          ),
        ),
      );
      d = interpretPurchase('Bellator', d, catalog).draft;
      expect(d.lines.single.product.value, mancozeb);
    });
  });

  group('aplicación', () {
    test('«apliqué doscientos cincuenta gramos» [pausa] «de Mancozeb»', () {
      var d = VoiceApplicationDraft.start(catalog);
      for (final s in const [
        'apliqué doscientos cincuenta gramos',
        'de Mancozeb',
      ]) {
        d = interpretApplication(s, d, catalog).draft;
      }
      expect(d.lines, hasLength(1));
      expect(d.lines.single.product.value, mancozeb);
      expect(d.lines.single.quantityBase, 250);
    });
  });

  group('planificación', () {
    test('«dos litros por hectárea» [pausa] «de Bellator»', () {
      var d = VoicePlanDraft.start(catalog);
      for (final s in const [
        'planificar el chaco Norte con dos litros por hectárea',
        'de Bellator',
      ]) {
        d = interpretPlan(s, d, catalog).draft;
      }
      expect(d.farm.value, norte);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.product.value, bellator);
      expect(d.lines.single.doseBasePerHa, 2000);
    });
  });
}
