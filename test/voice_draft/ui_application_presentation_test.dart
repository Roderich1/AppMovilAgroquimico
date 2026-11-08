import 'package:agroquimicos/presentation/voice/voice_application_draft_screen.dart';
import 'package:agroquimicos/voice_draft/application/application_interpreter.dart';
import 'package:agroquimicos/voice_draft/application/voice_application_draft.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../voice/support/fake_speech_transcription_port.dart';
import 'ui_draft_harness.dart';

/// Presentación del borrador de aplicación por voz tras la prueba del autor
/// en el POCO (2026-11-08). Todo el texto «dictado» lo inyecta el puerto
/// falso: no es reconocimiento real. Datos sintéticos.
void main() {
  const tenLiters = 'apliqué diez litros de Glifosato en el chaco titular';

  group('déficit del dueño del chaco', () {
    testWidgets('0 L con 10 L pedidos: «Faltan 10 L» y no se registra, aunque '
        'otra persona tenga stock', (tester) async {
      final w = await pumpDraftScreen(
        tester,
        screen: const VoiceApplicationDraftScreen(),
        script: const [FakeTurn(segment: tenLiters, endsOnStop: true)],
        // La hermana y el vecino tienen Glifosato; el titular, nada.
        seed: (repo, h) async {
          await h.buy(h.relative, 50000);
          await h.buy(h.thirdParty, 20000);
        },
      );
      await dictate(tester);
      await untilText(
        tester,
        'voz-stock-1',
        (t) => t.startsWith('Stock actual'),
      );
      final stock = tester
          .widget<Text>(find.byKey(const Key('voz-stock-1')))
          .data!;
      expect(stock, 'Stock actual 0 L · Faltan 10 L');
      expect(stock, isNot(contains('quedaría')));
      expect(stock, isNot(contains('insuficiente')));
      expect(
        find.textContaining(
          'no hay stock suficiente del dueño del chaco (faltan 10 L)',
        ),
        findsOneWidget,
      );
      expect(registerEnabled(tester), isFalse);
      expect(await rows(tester, w.database, 'applications'), isEmpty);
    });

    testWidgets('con stock suficiente: «quedaría N L» y se registra una vez', (
      tester,
    ) async {
      final w = await pumpDraftScreen(
        tester,
        screen: const VoiceApplicationDraftScreen(),
        script: const [FakeTurn(segment: tenLiters, endsOnStop: true)],
        seed: (repo, h) async {
          await h.buy(h.titular, 15000);
          await h.buy(h.relative, 50000);
        },
      );
      final before = await dump(tester, w.database);
      await dictate(tester);
      await untilText(
        tester,
        'voz-stock-1',
        (t) => t.startsWith('Stock actual'),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('voz-stock-1'))).data,
        'Stock actual 15 L · quedaría 5 L',
      );
      expect(find.textContaining('Faltan'), findsNothing);
      expect(find.textContaining('no hay stock suficiente'), findsNothing);
      expect(registerEnabled(tester), isTrue);
      // Cero escrituras antes de confirmar.
      expect(await dump(tester, w.database), before);

      await doubleTapRegister(tester);
      final applied = await rows(tester, w.database, 'application_items');
      expect(await rows(tester, w.database, 'applications'), hasLength(1));
      expect(applied.single['quantity_base'], 10000);
    });
  });

  group('elegir en el selector', () {
    testWidgets('tocar la misma opción confirma; otra corrige; la voz '
        'posterior no cambia ninguna', (tester) async {
      await pumpDraftScreen(
        tester,
        screen: const VoiceApplicationDraftScreen(),
        script: const [
          FakeTurn(
            segment: 'apliqué dos litros de Glifosato en el chaco titular',
            endsOnStop: true,
          ),
          FakeTurn(
            segment: 'en el chaco hermana apliqué un litro de Glifosato',
            endsOnStop: true,
          ),
        ],
        seed: (repo, h) async {
          await h.buy(h.titular, 5000);
          await repo.addProduct(name: 'Insecticida');
        },
      );
      await dictate(tester);
      await untilText(
        tester,
        'voz-stock-1',
        (t) => t.startsWith('Stock actual'),
      );
      expect(fieldState(tester, 'chaco'), 'Dictado');
      expect(fieldState(tester, 'producto-1'), 'Dictado');

      // Cerrar la hoja sin elegir no cambia nada.
      await openAndDismiss(tester, 'voz-producto-1');
      expect(fieldState(tester, 'producto-1'), 'Dictado');

      // La misma opción: «Confirmado», no «Corregido a mano».
      await pick(tester, 'voz-borrador-chaco', 'Chaco titular');
      expect(fieldState(tester, 'chaco'), 'Confirmado');
      await pick(tester, 'voz-producto-1', 'Glifosato');
      expect(fieldState(tester, 'producto-1'), 'Confirmado');
      expect(find.text('Corregido a mano'), findsNothing);
      // Confirmar el chaco no vuelve a leer ni cambia el stock.
      expect(
        tester.widget<Text>(find.byKey(const Key('voz-stock-1'))).data,
        'Stock actual 5 L · quedaría 3 L',
      );

      // Otra opción: «Corregido a mano».
      await pick(tester, 'voz-producto-1', 'Insecticida');
      expect(fieldState(tester, 'producto-1'), 'Corregido a mano');

      // Texto inyectado que nombra otro chaco: no cambia el confirmado ni el
      // corregido.
      await dictate(tester);
      expect(fieldState(tester, 'chaco'), 'Confirmado');
      expect(pickerShows('voz-borrador-chaco', 'Chaco titular'), isTrue);
      expect(fieldState(tester, 'producto-1'), 'Corregido a mano');
      expect(pickerShows('voz-producto-1', 'Insecticida'), isTrue);
    });
  });

  group('cantidad por revisar', () {
    /// Un borrador como el que dejará la voz cuando los dos reconocedores
    /// oigan cifras distintas: la cantidad, por revisar.
    VoiceApplicationDraft reviewDraft(VoiceCatalog catalog) {
      final farm = catalog.farms.firstWhere((f) => f.name == 'Chaco titular');
      final product = catalog.products.firstWhere((p) => p.name == 'Glifosato');
      return selectFarm(
        VoiceApplicationDraft.start(catalog).copyWith(
          farm: DraftField.resolved(farm, origin: FieldOrigin.voice),
          lines: [
            VoiceApplicationLine(
              key: 1,
              product: DraftField.resolved(product, origin: FieldOrigin.voice),
              quantity: const DraftField.toReview(
                SpokenAmount(2000, SpokenUnit.liter),
                message: 'Se oyeron dos cifras distintas.',
                heard: 'dos litros',
              ),
            ),
          ],
          nextLineKey: 2,
        ),
        catalog,
      );
    }

    testWidgets('muestra «Revisar», el valor y el motivo, y bloquea; '
        '«Confirmar este valor» la resuelve y la voz tardía no la pisa', (
      tester,
    ) async {
      final w = await pumpDraftScreen(
        tester,
        screen: VoiceApplicationDraftScreen(initialDraftForTest: reviewDraft),
        script: const [
          FakeTurn(segment: 'cuatro litros de Glifosato', endsOnStop: true),
        ],
        seed: (repo, h) => h.buy(h.titular, 5000),
      );
      await untilText(
        tester,
        'voz-stock-1',
        (t) => t.startsWith('Stock actual'),
      );
      final before = await dump(tester, w.database);
      expect(fieldState(tester, 'cantidad-1'), 'Revisar');
      expect(find.text('Ambiguo: elija'), findsNothing);
      expect(fieldText(tester, 'voz-cantidad-1'), '2');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('voz-mensaje-cantidad-1')))
            .data,
        'Se oyeron dos cifras distintas.',
      );
      expect(
        find.textContaining('Producto 1: revise la cantidad.'),
        findsOneWidget,
      );
      expect(registerEnabled(tester), isFalse);

      await tapKey(tester, 'voz-confirmar-cantidad-1');
      expect(fieldState(tester, 'cantidad-1'), 'Confirmado');
      expect(find.byKey(const Key('voz-confirmar-cantidad-1')), findsNothing);
      expect(registerEnabled(tester), isTrue);

      // Un resultado de voz posterior (texto inyectado) no cambia lo
      // confirmado; y se indica cómo corregir a mano.
      await dictate(tester);
      expect(fieldText(tester, 'voz-cantidad-1'), '2');
      expect(fieldState(tester, 'cantidad-1'), 'Confirmado');
      expect(
        find.text('No cambió el borrador: se conserva lo corregido a mano.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('voz-como-corregir')), findsOneWidget);

      // Nada escrito hasta confirmar; luego una sola aplicación con lo que
      // se ve.
      expect(await dump(tester, w.database), before);
      await doubleTapRegister(tester);
      expect(await rows(tester, w.database, 'applications'), hasLength(1));
      final items = await rows(tester, w.database, 'application_items');
      expect(items.single['quantity_base'], 2000);
    });

    testWidgets('editar el valor por revisar lo deja «Corregido a mano»', (
      tester,
    ) async {
      await pumpDraftScreen(
        tester,
        screen: VoiceApplicationDraftScreen(initialDraftForTest: reviewDraft),
        script: const [],
        seed: (repo, h) => h.buy(h.titular, 5000),
      );
      await untilText(
        tester,
        'voz-stock-1',
        (t) => t.startsWith('Stock actual'),
      );
      await tester.enterText(find.byKey(const Key('voz-cantidad-1')), '3');
      await drain(tester);
      expect(fieldState(tester, 'cantidad-1'), 'Corregido a mano');
      expect(find.byKey(const Key('voz-confirmar-cantidad-1')), findsNothing);
      expect(registerEnabled(tester), isTrue);
    });

    testWidgets('cancelar con un valor por revisar no escribe nada', (
      tester,
    ) async {
      final w = await pumpDraftScreen(
        tester,
        screen: VoiceApplicationDraftScreen(initialDraftForTest: reviewDraft),
        script: const [],
        seed: (repo, h) => h.buy(h.titular, 5000),
      );
      await untilText(
        tester,
        'voz-stock-1',
        (t) => t.startsWith('Stock actual'),
      );
      final before = await dump(tester, w.database);
      await tapKey(tester, 'voz-cancelar');
      expect(await dump(tester, w.database), before);
    });
  });

  group('dictado que no cambia el borrador', () {
    testWidgets('se indica cómo corregir a mano, sin prometer órdenes de voz', (
      tester,
    ) async {
      await pumpDraftScreen(
        tester,
        screen: const VoiceApplicationDraftScreen(),
        script: const [
          FakeTurn(segment: tenLiters, endsOnStop: true),
          FakeTurn(segment: 'eliminan el producto', endsOnStop: true),
        ],
        seed: (repo, h) => h.buy(h.titular, 15000),
      );
      await dictate(tester);
      // El último dictado cambió el borrador: sin indicación.
      expect(find.byKey(const Key('voz-como-corregir')), findsNothing);

      await dictate(tester);
      expect(
        find.text('No cambió el borrador: no se reconoció nada que completar.'),
        findsOneWidget,
      );
      final hint = tester
          .widget<Text>(find.byKey(const Key('voz-como-corregir')))
          .data!;
      expect(hint, contains('elija en el selector'));
      expect(hint, contains('«Quitar este producto»'));
      for (final promise in ['diga', 'dicte', 'selecciona', 'elimin']) {
        expect(hint.toLowerCase(), isNot(contains(promise)));
      }
      // El botón al que remite la indicación existe con ese nombre.
      expect(find.byTooltip('Quitar este producto'), findsOneWidget);
      // Y la línea sigue ahí: la voz no quitó nada.
      expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
    });
  });
}
