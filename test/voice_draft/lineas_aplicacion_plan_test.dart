import 'package:agroquimicos/voice_draft/application/application_interpreter.dart';
import 'package:agroquimicos/voice_draft/application/voice_application_draft.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/interpretation/phrases.dart';
import 'package:agroquimicos/voice_draft/plan/plan_interpreter.dart';
import 'package:agroquimicos/voice_draft/plan/voice_plan_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';

/// Aplicación y planificación: repetir un dictado no añade líneas vacías ni
/// duplica un producto fuera del catálogo, y el mismo producto dos veces en
/// una frase no se funde en silencio (POCO 2026-11-08). Texto inyectado, no
/// reconocimiento real; frases propias, ninguna del holdout de #12.
void main() {
  const insecticida = CatalogEntry(
    id: 1,
    name: 'Insecticida DEMO',
    unit: CatalogUnit.liter,
  );
  const mancozeb = CatalogEntry(
    id: 2,
    name: 'Mancozeb DEMO',
    unit: CatalogUnit.kilogram,
  );
  const catalog = VoiceCatalog(
    products: [insecticida, mancozeb],
    suppliers: [],
    people: [CatalogEntry(id: 20, name: 'Rosa Mamani F09')],
    activeCampaign: CatalogEntry(id: 30, name: 'Campaña'),
  );

  VoiceApplicationDraft apply(List<String> parts) {
    var d = VoiceApplicationDraft.start(catalog);
    for (final p in parts) {
      d = interpretApplication(p, d, catalog).draft;
    }
    return d;
  }

  VoicePlanDraft plan(List<String> parts) {
    var d = VoicePlanDraft.start(catalog);
    for (final p in parts) {
      d = interpretPlan(p, d, catalog).draft;
    }
    return d;
  }

  group('aplicación', () {
    test('repetir «apliqué … de» sin producto deja una sola línea que espera '
        'y el producto la completa', () {
      final d = apply([
        'apliqué tres litros de',
        'apliqué tres litros de',
        'insecticida demo',
      ]);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.product.value, insecticida);
    });

    test('repetir un producto fuera del catálogo no lo duplica', () {
      final d = apply([
        'apliqué dos litros de clorpirifos',
        'apliqué dos litros de clorpirifos',
      ]);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.product.status, FieldStatus.missing);
    });

    test('el mismo producto dos veces en una frase son dos líneas que '
        'bloquean como repetidas', () {
      final d = apply([
        'apliqué un kilo de mancozeb demo y dos kilos de mancozeb demo',
      ]);
      expect(d.lines, hasLength(2));
      expect(d.blockers.join(' '), contains('repetido'));
    });
  });

  group('planificación', () {
    test('repetir una dosis sin producto no añade líneas', () {
      final d = plan([
        'medio kilo por hectárea de',
        'medio kilo por hectárea de',
      ]);
      expect(d.lines, hasLength(1));
      expect(isAwaitingProduct(d.lines.single.product), isTrue);
    });

    test('nombrar otra vez el producto corrige su dosis', () {
      final d = plan([
        'un litro por hectárea de insecticida demo',
        'dos litros por hectárea de insecticida demo',
      ]);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.dose.value, isNotNull);
    });
  });
}
