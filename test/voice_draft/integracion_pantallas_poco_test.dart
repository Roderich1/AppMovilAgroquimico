import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/voice/voice_plan_draft_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_purchase_draft_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/f04_mode_fixtures.dart';
import '../voice/support/fake_speech_transcription_port.dart';
import 'ui_draft_harness.dart';

/// Integración en las pantallas de las correcciones del POCO (2026-11-08):
/// el desacuerdo numérico entre los dos reconocedores llega al borrador como
/// campos «por revisar», y un precio dicho aparte sin línea clara se avisa.
/// Todo el texto lo inyecta el puerto falso: **no es reconocimiento real**.
/// Datos sintéticos.
void main() {
  Future<void> seed(AgroRepository repo, Household h) async {
    await repo.addSupplier(name: 'Agro Norte');
    await repo.addProduct(name: 'Mancozeb');
  }

  group('compra: desacuerdo numérico (texto inyectado)', () {
    testWidgets('con desacuerdo, cantidad y precio quedan por revisar, '
        'bloquean y confirmarlos los resuelve sin escribir nada', (
      tester,
    ) async {
      final w = await pumpDraftScreen(
        tester,
        screen: const VoicePurchaseDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'compré diez litros de Glifosato a cincuenta bolivianos '
                'el litro',
            endsOnStop: true,
            numericDisagreement: true,
          ),
        ],
        seed: seed,
      );
      final before = await dump(tester, w.database);
      await dictate(tester);
      await until(
        tester,
        () => find
            .byKey(const Key('voz-estado-cantidad-1'))
            .evaluate()
            .isNotEmpty,
      );
      expect(fieldState(tester, 'cantidad-1'), 'Revisar');
      expect(fieldState(tester, 'precio-1'), 'Revisar');
      expect(fieldText(tester, 'voz-cantidad-1'), '10');
      expect(registerEnabled(tester), isFalse);
      expect(
        find.textContaining('Los dos reconocedores oyeron cifras distintas'),
        findsWidgets,
      );

      await tapKey(tester, 'voz-confirmar-cantidad-1');
      await tapKey(tester, 'voz-confirmar-precio-1');
      expect(fieldState(tester, 'cantidad-1'), 'Confirmado');
      expect(fieldState(tester, 'precio-1'), 'Confirmado');
      // Confirmar no escribe: sólo «Registrar compra» escribe.
      expect(await dump(tester, w.database), before);
    });

    // POCO 2026-11-08 con `4e995ec`: la moneda por revisar no se podía dar
    // por buena (botón deshabilitado y ningún segmento marcado).
    testWidgets('la moneda por revisar se ve marcada y se confirma con el '
        'botón o tocando el mismo segmento, sin escribir nada', (tester) async {
      final w = await pumpDraftScreen(
        tester,
        screen: const VoicePurchaseDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'compré diez litros de Glifosato a cincuenta bolivianos '
                'el litro',
            endsOnStop: true,
            numericDisagreement: true,
          ),
        ],
        seed: seed,
      );
      final before = await dump(tester, w.database);
      await dictate(tester);
      await until(
        tester,
        () =>
            find.byKey(const Key('voz-estado-moneda-1')).evaluate().isNotEmpty,
      );
      expect(fieldState(tester, 'moneda-1'), 'Revisar');
      final segments = tester.widget<SegmentedButton<CurrencyCode>>(
        find.byKey(const Key('voz-moneda-1')),
      );
      expect(segments.selected, {CurrencyCode.bob});

      await tapKey(tester, 'voz-confirmar-moneda-1');
      expect(fieldState(tester, 'moneda-1'), 'Confirmado');
      expect(await dump(tester, w.database), before);
    });

    testWidgets('tocar el segmento ya marcado de una moneda por revisar la '
        'confirma; tocar el otro es corrección a mano', (tester) async {
      await pumpDraftScreen(
        tester,
        screen: const VoicePurchaseDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'compré diez litros de Glifosato a cincuenta bolivianos '
                'el litro',
            endsOnStop: true,
            numericDisagreement: true,
          ),
        ],
        seed: seed,
      );
      await dictate(tester);
      await until(
        tester,
        () =>
            find.byKey(const Key('voz-estado-moneda-1')).evaluate().isNotEmpty,
      );
      final moneda = find.byKey(const Key('voz-moneda-1'));
      await tester.ensureVisible(moneda);
      await tester.tap(find.descendant(of: moneda, matching: find.text('BOB')));
      await tester.pump();
      expect(fieldState(tester, 'moneda-1'), 'Confirmado');
      await tester.tap(find.descendant(of: moneda, matching: find.text('USD')));
      await tester.pump();
      expect(fieldState(tester, 'moneda-1'), 'Corregido a mano');
    });

    testWidgets('sin desacuerdo, lo mismo queda dictado', (tester) async {
      await pumpDraftScreen(
        tester,
        screen: const VoicePurchaseDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'compré diez litros de Glifosato a cincuenta bolivianos '
                'el litro',
            endsOnStop: true,
          ),
        ],
        seed: seed,
      );
      await dictate(tester);
      await until(
        tester,
        () => find
            .byKey(const Key('voz-estado-cantidad-1'))
            .evaluate()
            .isNotEmpty,
      );
      expect(fieldState(tester, 'cantidad-1'), 'Dictado');
      expect(fieldState(tester, 'precio-1'), 'Dictado');
    });

    testWidgets('un precio dicho aparte con dos líneas posibles se avisa y no '
        'cambia ninguna', (tester) async {
      await pumpDraftScreen(
        tester,
        screen: const VoicePurchaseDraftScreen(),
        script: const [
          FakeTurn(
            segment:
                'compré diez litros de Glifosato y cinco litros de '
                'Mancozeb',
            endsOnStop: true,
          ),
          FakeTurn(
            segment: 'a cincuenta bolivianos el litro',
            endsOnStop: true,
          ),
        ],
        seed: seed,
      );
      await dictate(tester);
      await dictate(tester);
      await until(
        tester,
        () =>
            find.byKey(const Key('voz-precio-sin-linea')).evaluate().isNotEmpty,
      );
      expect(find.byKey(const Key('voz-precio-sin-linea')), findsOneWidget);
      expect(fieldText(tester, 'voz-precio-1'), '');
      expect(fieldText(tester, 'voz-precio-2'), '');
    });
  });

  group('planificación: desacuerdo numérico (texto inyectado)', () {
    testWidgets('la dosis dictada con desacuerdo queda por revisar', (
      tester,
    ) async {
      await pumpDraftScreen(
        tester,
        screen: const VoicePlanDraftScreen(),
        script: const [
          FakeTurn(
            segment: 'dos litros por hectárea de Glifosato',
            endsOnStop: true,
            numericDisagreement: true,
          ),
        ],
      );
      await dictate(tester);
      await until(
        tester,
        () => find.byKey(const Key('voz-estado-dosis-1')).evaluate().isNotEmpty,
      );
      expect(fieldState(tester, 'dosis-1'), 'Revisar');
      expect(registerEnabled(tester), isFalse);
    });
  });
}
