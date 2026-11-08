import 'package:agroquimicos/presentation/voice/voice_plan_draft_screen.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/plan/voice_plan_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../voice/support/fake_speech_transcription_port.dart';
import 'ui_draft_harness.dart';

/// Presentación del borrador de planificación por voz tras la prueba del
/// autor en el POCO (2026-11-08). Todo el texto «dictado» lo inyecta el
/// puerto falso: no es reconocimiento real. Datos sintéticos.
void main() {
  String need(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('voz-necesita-1'))).data!;

  group('dosis normalizada', () {
    testWidgets('con el producto pendiente se ve «1», no lo oído, y la unidad '
        'queda por comprobar', (tester) async {
      final w = await pumpDraftScreen(
        tester,
        screen: const VoicePlanDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'planificar el chaco titular con un litro por hectárea de '
                'Fungicida DEMO',
            endsOnStop: true,
          ),
        ],
      );
      final before = await dump(tester, w.database);
      await dictate(tester);
      expect(fieldText(tester, 'voz-dosis-1'), '1');
      expect(find.text('Dosis (L/ha)'), findsOneWidget);
      // La incertidumbre se conserva: el producto falta y la unidad no se
      // comprobó.
      expect(fieldState(tester, 'producto-1'), 'Falta');
      expect(
        tester.widget<Text>(find.byKey(const Key('voz-nota-dosis-1'))).data,
        'En L/ha; falta elegir el producto para comprobar su unidad.',
      );
      expect(need(tester), 'Necesita: se calcula con el área y la dosis.');
      expect(find.textContaining('no coincide'), findsNothing);
      expect(registerEnabled(tester), isFalse);
      expect(await dump(tester, w.database), before);

      // Elegido el producto (L), la dosis se comprueba y la necesidad es
      // dosis × área (1 L/ha × 1 ha).
      await pick(tester, 'voz-producto-1', 'Glifosato');
      expect(fieldText(tester, 'voz-dosis-1'), '1');
      expect(find.byKey(const Key('voz-nota-dosis-1')), findsNothing);
      expect(need(tester), 'Necesita 1 L');
      expect(registerEnabled(tester), isTrue);

      await doubleTapRegister(tester);
      expect(await rows(tester, w.database, 'application_plans'), hasLength(1));
      final items = await rows(tester, w.database, 'application_plan_items');
      expect(items.single['dose_base_per_ha'], 1000);
      expect(items.single['required_quantity_base'], 1000);
    });

    testWidgets('con el producto en kg y la dosis en L, se ve «1» pero no es '
        'válida ni se calcula la necesidad', (tester) async {
      await pumpDraftScreen(
        tester,
        screen: const VoicePlanDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'planificar el chaco titular con un litro por hectárea de '
                'Urea',
            endsOnStop: true,
          ),
        ],
        seed: (repo, h) => repo.addProduct(name: 'Urea', unit: 'KG'),
      );
      await dictate(tester);
      expect(fieldText(tester, 'voz-dosis-1'), '1');
      expect(find.text('Dosis (KG/ha)'), findsOneWidget);
      expect(fieldState(tester, 'dosis-1'), 'No válido');
      expect(
        tester.widget<Text>(find.byKey(const Key('voz-problema-dosis-1'))).data,
        'La cifra está en L/ha, pero el producto se mide en KG/ha: corrija la '
        'cifra o el producto.',
      );
      expect(need(tester), 'Necesita: se calcula con el área y la dosis.');
      expect(
        find.textContaining('la dosis no corresponde a la unidad del producto'),
        findsOneWidget,
      );
      expect(find.textContaining('no coincide'), findsNothing);
      expect(registerEnabled(tester), isFalse);

      // Escrita a mano, la cifra queda en la unidad que se ve (KG/ha).
      await tester.enterText(find.byKey(const Key('voz-dosis-1')), '1,5');
      await drain(tester);
      expect(fieldState(tester, 'dosis-1'), 'Corregido a mano');
      expect(find.byKey(const Key('voz-problema-dosis-1')), findsNothing);
      expect(need(tester), 'Necesita 1,5 KG');
      expect(registerEnabled(tester), isTrue);
    });
  });

  group('área y dosis por revisar', () {
    VoicePlanDraft reviewDraft(VoiceCatalog catalog) {
      final farm = catalog.farms.firstWhere((f) => f.name == 'Chaco titular');
      final product = catalog.products.firstWhere((p) => p.name == 'Glifosato');
      return VoicePlanDraft.start(catalog).copyWith(
        farm: DraftField.resolved(farm, origin: FieldOrigin.voice),
        area: const DraftField.toReview(
          15000,
          message: 'Se oyeron dos áreas distintas.',
        ),
        lines: [
          VoicePlanLine(
            key: 1,
            product: DraftField.resolved(product, origin: FieldOrigin.voice),
            dose: const DraftField.toReview(
              SpokenDose(2000, SpokenUnit.liter),
              message: 'Se oyeron dos dosis distintas.',
            ),
          ),
        ],
        nextLineKey: 2,
      );
    }

    testWidgets('se ven con su valor, bloquean y al confirmarlos la '
        'necesidad es dosis × área; la voz tardía no los cambia', (
      tester,
    ) async {
      final w = await pumpDraftScreen(
        tester,
        screen: VoicePlanDraftScreen(initialDraftForTest: reviewDraft),
        script: const [
          FakeTurn(
            segment: 'en tres hectáreas tres litros por hectárea de Glifosato',
            endsOnStop: true,
          ),
        ],
      );
      final before = await dump(tester, w.database);
      expect(fieldState(tester, 'area'), 'Revisar');
      expect(fieldState(tester, 'dosis-1'), 'Revisar');
      expect(fieldText(tester, 'voz-area'), '1,5');
      expect(fieldText(tester, 'voz-dosis-1'), '2');
      expect(
        tester.widget<Text>(find.byKey(const Key('voz-mensaje-area'))).data,
        'Se oyeron dos áreas distintas.',
      );
      expect(
        find.textContaining('Producto 1: revise la dosis por hectárea.'),
        findsOneWidget,
      );
      expect(find.textContaining('Revise el área.'), findsOneWidget);
      expect(registerEnabled(tester), isFalse);

      await tapKey(tester, 'voz-confirmar-area');
      expect(fieldState(tester, 'area'), 'Confirmado');
      expect(registerEnabled(tester), isFalse);
      await tapKey(tester, 'voz-confirmar-dosis-1');
      expect(fieldState(tester, 'dosis-1'), 'Confirmado');
      // 2 L/ha × 1,5 ha.
      expect(need(tester), 'Necesita 3 L');
      expect(registerEnabled(tester), isTrue);

      // Texto inyectado posterior: no pisa lo confirmado.
      await dictate(tester);
      expect(fieldText(tester, 'voz-area'), '1,5');
      expect(fieldText(tester, 'voz-dosis-1'), '2');
      expect(need(tester), 'Necesita 3 L');

      expect(await dump(tester, w.database), before);
      await doubleTapRegister(tester);
      final plans = await rows(tester, w.database, 'application_plans');
      expect(plans, hasLength(1));
      final items = await rows(tester, w.database, 'application_plan_items');
      expect(items.single['dose_base_per_ha'], 2000);
      expect(items.single['required_quantity_base'], 3000);
    });

    testWidgets('editar la dosis por revisar la deja «Corregido a mano»', (
      tester,
    ) async {
      await pumpDraftScreen(
        tester,
        screen: VoicePlanDraftScreen(initialDraftForTest: reviewDraft),
        script: const [],
      );
      await tester.enterText(find.byKey(const Key('voz-dosis-1')), '2,5');
      await drain(tester);
      expect(fieldState(tester, 'dosis-1'), 'Corregido a mano');
      expect(find.byKey(const Key('voz-confirmar-dosis-1')), findsNothing);
      // El área sigue por revisar y bloquea.
      expect(fieldState(tester, 'area'), 'Revisar');
      expect(registerEnabled(tester), isFalse);
    });
  });

  group('dictado que no cambia el borrador', () {
    testWidgets('«el producto uno selecciona…» no cambia nada y se indica '
        'cómo corregir', (tester) async {
      await pumpDraftScreen(
        tester,
        screen: const VoicePlanDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'planificar el chaco titular con dos litros por hectárea de '
                'Glifosato',
            endsOnStop: true,
          ),
          FakeTurn(
            segment: 'el producto uno selecciona Fungicida DEMO',
            endsOnStop: true,
          ),
        ],
      );
      await dictate(tester);
      expect(find.byKey(const Key('voz-como-corregir')), findsNothing);
      await dictate(tester);
      expect(find.byKey(const Key('voz-como-corregir')), findsOneWidget);
      expect(pickerShows('voz-producto-1', 'Glifosato'), isTrue);
      expect(find.byKey(const Key('voz-linea-2')), findsNothing);
    });
  });
}
