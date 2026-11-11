// Contrato E2 §5 en pantalla: el detalle exige el consentimiento CONV-1 con
// casilla antes de guardar; lo guardado dice «Pendiente de envío» y nunca
// «recibida» hasta que el servidor la acepta; el aviso de Inicio aparece
// mientras la convocatoria abierta no se abrió y desaparece al abrirla. Sin
// red; datos sintéticos.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/presentation/screens/joint_purchase_detail_screen.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e2_joint_purchase_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart' as ui;
import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var round = 0; round < rounds; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  Future<({SyncFixture fixture, JointPurchaseStore store, ProviderContainer c})>
  pumpDetail(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = (await tester.runAsync(
      () => seedSyncFixture(path: inMemoryDatabasePath),
    ))!;
    final store = JointPurchaseStore(fixture.database);
    await tester.runAsync(() async {
      await seedCalls(store, memberA, [callJson()]);
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 12000,
      );
    });
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(fixture.database),
        repositoryProvider.overrideWithValue(fixture.repo),
        declaredNeedStoreProvider.overrideWithValue(fixture.needs),
        centralBindingStoreProvider.overrideWithValue(fixture.bindings),
        syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
        jointPurchaseStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: JointPurchaseDetailScreen(callId: callId)),
        ),
      ),
    );
    await settle(tester);
    return (fixture: fixture, store: store, c: container);
  }

  Future<void> enterQuantities(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('joint-participate')));
    await settle(tester, rounds: 2);
    expect(find.text('Cantidades que solicita'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('joint-quantity-$litreRef')),
      '25',
    );
    await tester.tap(find.text('Continuar'));
    await settle(tester, rounds: 2);
  }

  testWidgets(
    'detalle: datos, referencia de la necesidad declarada sin sumar y consentimiento obligatorio',
    (tester) async {
      final s = await pumpDetail(tester);
      expect(find.text('Compra conjunta de herbicida'), findsOneWidget);
      expect(find.text('Campaña: Campaña sindicato 2026'), findsOneWidget);
      expect(
        find.textContaining('(según la hora del sindicato)'),
        findsOneWidget,
      );
      expect(find.text('Responsable: Responsable sintético'), findsOneWidget);
      expect(find.text('Herbicida central (L)'), findsOneWidget);
      expect(find.text('Fungicida central (KG)'), findsOneWidget);
      expect(
        find.text('Su necesidad declarada para esta campaña: 12 L'),
        findsOneWidget,
      );
      // Abrirla la marcó como vista.
      expect(
        (await tester.runAsync(() => s.store.call(callId)))!.isNew,
        isFalse,
      );

      // Sin la casilla no se puede confirmar; cancelar no guarda nada.
      await enterQuantities(tester);
      expect(find.text(jointPurchaseConsentText), findsOneWidget);
      expect(find.text('Entiendo y acepto'), findsOneWidget);
      final confirm = find.byKey(const Key('joint-consent-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.text('Cancelar'));
      await settle(tester, rounds: 2);
      expect(await tester.runAsync(() => s.store.ops(callId)), isEmpty);
      expect(
        find.text('Todavía no participa en esta convocatoria.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'confirmar: «Pendiente de envío» y sólo tras el servidor «Participación recibida»',
    (tester) async {
      final s = await pumpDetail(tester);
      await enterQuantities(tester);
      await tester.tap(find.byKey(const Key('joint-consent-check')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('joint-consent-confirm')));
      await settle(tester);

      final ops = (await tester.runAsync(() => s.store.ops(callId)))!;
      expect(ops.single.lines, {litreRef: 25000});
      expect(ops.single.consentVersion, 'CONV-1');
      expect(find.text('Pendiente de envío'), findsOneWidget);
      expect(
        find.text('Pendiente de envío: 25 L de Herbicida central'),
        findsOneWidget,
      );
      expect(find.textContaining('recibida'), findsNothing);
      expect(find.text('Modificar'), findsOneWidget);
      expect(find.text('Retirar participación'), findsOneWidget);
      expect(find.text('Enviar ahora'), findsOneWidget);

      // El servidor la acepta (como haría el emisor).
      await tester.runAsync(
        () => s.store.markReceived(
          ops.single,
          JointPurchaseParticipation.fromJson(
            participationJson(lines: {litreRef: 25000}),
          ),
        ),
      );
      s.c.read(jointPurchaseRevisionProvider.notifier).bump();
      await settle(tester);
      expect(find.text('Participación recibida'), findsOneWidget);
      expect(
        find.text('El sindicato tiene: 25 L de Herbicida central'),
        findsOneWidget,
      );
      expect(find.textContaining('Pendiente de envío'), findsNothing);
    },
  );

  testWidgets('convocatoria cerrada: botones desactivados con explicación', (
    tester,
  ) async {
    final s = await pumpDetail(tester);
    await tester.runAsync(
      () => seedCalls(s.store, memberA, [callJson(status: 'CLOSED')]),
    );
    s.c.read(jointPurchaseRevisionProvider.notifier).bump();
    await settle(tester);
    expect(
      find.text('Convocatoria cerrada: ya no admite cambios.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('joint-participate')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'Inicio: aviso «Nueva convocatoria» hasta abrirla; Más tiene la entrada',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final h = await ui.activatedHousehold(tester, 'e2_inicio');
      await tester.runAsync(
        () => seedCalls(JointPurchaseStore(h.database), memberA, [
          callJson(deadlineAt: '2099-12-31T22:00:00.000Z'),
        ]),
      );
      final offline = ui.OfflineTransport();
      final c = await ui.pumpModeApp(tester, h.database, transport: offline);
      expect(
        find.textContaining(
          'Nueva convocatoria: Compra conjunta de herbicida · cierra el ',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('joint-purchase-notice')));
      await ui.settle(tester);
      expect(find.text('Su participación'), findsOneWidget);
      c.read(routerProvider).pop();
      await ui.settle(tester);
      expect(find.textContaining('Nueva convocatoria'), findsNothing);
      expect(offline.requests, 0);

      c.read(routerProvider).go('/mas');
      await ui.settle(tester);
      expect(find.text('Compras conjuntas'), findsOneWidget);
      expect(
        find.text('Convocatorias del sindicato y su participación'),
        findsOneWidget,
      );
    },
  );
}
