// Contrato E2 §5 y E4 §4 en pantalla: el detalle exige el consentimiento CONV-4 con
// casilla antes de guardar; lo guardado dice «Pendiente de envío» y nunca
// «recibida» hasta que el servidor la acepta; el aviso de Inicio aparece
// mientras la convocatoria abierta no se abrió y desaparece al abrirla. La
// lista separa las recientes del «Historial» (E2 §10.1), que se consulta por
// páginas con conexión y avisa sin ella. Sin red real; datos sintéticos.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/presentation/screens/joint_purchase_detail_screen.dart';
import 'package:agroquimicos/presentation/screens/joint_purchases_screen.dart';
import 'package:agroquimicos/presentation/widgets/joint_purchase_texts.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/joint_purchase_api.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
      expect(ops.single.consentVersion, 'CONV-4');
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

  // E4 §4 y §6.5: el agricultor sabe, por función, quién ve su nombre y sus
  // cantidades según el alcance APLICADO en el sindicato (reescrita desde
  // E2 §10.3/§10.6: la responsabilidad ya no da acceso, D-01).
  const legacyScope =
      'Su participación se registró con un texto anterior. Con las reglas '
      'actuales, nadie de la Directiva ni de la Administración ve su nombre ni '
      'sus cantidades hasta que usted revise quién puede ver su participación. '
      'Mientras tanto, los totales de los productos que pidió pueden no '
      'mostrarse.';
  for (final (label, participation, expected) in [
    (
      'sin participación: lo que regirá al participar',
      null,
      'Si participa, la Administración habilitada de su sindicato podrá ver su '
          'nombre y sus cantidades, y la Directiva sólo los totales por '
          'producto, sin su nombre.',
    ),
    (
      'aceptada con CONV-4: Administración ve el detalle; Directiva, totales',
      participationJson(consentScope: 'ADMINISTRATION'),
      'La Administración habilitada de su sindicato puede ver su nombre y sus '
          'cantidades. La Directiva sólo ve los totales por producto, sin su '
          'nombre.',
    ),
    (
      'autorización retirada: nadie ve el detalle; cuenta en los totales',
      participationJson(consentScope: 'TOTALS_ONLY', consentScopeSequence: 1),
      'Usted retiró la autorización: nadie de la Directiva ni de la '
          'Administración ve su nombre ni sus cantidades. Sus cantidades '
          'siguen contando en los totales por producto, que se muestran sin '
          'nombres.',
    ),
    (
      'aceptada con CONV-3: alcance anterior, nadie ve el detalle',
      participationJson(
        consentVersion: 'CONV-3',
        consentScope: 'RESPONSIBLE_ONLY',
        consentScopeVersion: 'CONV-3',
      ),
      legacyScope,
    ),
    (
      'ampliada antes de E4: tampoco habilita a nadie',
      participationJson(
        consentVersion: 'CONV-3',
        consentScope: 'COLLABORATORS',
        consentScopeVersion: 'CONV-3',
        consentScopeSequence: 1,
      ),
      legacyScope,
    ),
    (
      'aceptada con CONV-2 (antes de §10.6): alcance anterior',
      participationJson(consentVersion: 'CONV-2'),
      legacyScope,
    ),
    (
      'aceptada con CONV-1: alcance anterior, sin retroactividad',
      participationJson(consentVersion: jointPurchaseLegacyConsentVersion),
      legacyScope,
    ),
    (
      'retirada: no cuenta ni aparece en el detalle',
      participationJson(withdrawn: true, consentScope: 'ADMINISTRATION'),
      'Su participación está retirada: no se cuenta en los totales ni aparece '
          'en el detalle de la Administración.',
    ),
  ]) {
    testWidgets('quién ve sus datos: $label', (tester) async {
      final s = await pumpDetail(tester);
      await tester.runAsync(
        () => seedCalls(s.store, memberA, [
          callJson(participation: participation),
        ]),
      );
      s.c.read(jointPurchaseRevisionProvider.notifier).bump();
      await settle(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('joint-who-can-see'))).data,
        expected,
      );
      // La ayuda de CONV-4 se dice siempre; nunca «anónimo».
      expect(
        tester.widget<Text>(find.byKey(const Key('joint-consent-help'))).data,
        jointPurchaseConsentHelp,
      );
      expect(find.textContaining('anónim'), findsNothing);
    });
  }

  testWidgets('cancelada con alcance anterior: no invita a revisar (verificación E4, D2)', (
    tester,
  ) async {
    final s = await pumpDetail(tester);
    await tester.runAsync(
      () => seedCalls(s.store, memberA, [
        callJson(
          status: 'CANCELLED',
          participation: participationJson(
            consentVersion: 'CONV-3',
            consentScope: 'RESPONSIBLE_ONLY',
            consentScopeVersion: 'CONV-3',
          ),
        ),
      ]),
    );
    s.c.read(jointPurchaseRevisionProvider.notifier).bump();
    await settle(tester);
    final text =
        tester.widget<Text>(find.byKey(const Key('joint-who-can-see'))).data!;
    expect(text, contains('está cancelada y ya no admite cambios'));
    expect(text, isNot(contains('revise')));
  });

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
    // E4 §6.1: la responsabilidad sólo indica quién coordina (quién ve los
    // datos lo dice otro texto, según el consentimiento del agricultor).
    expect(
      tester.widget<Text>(find.byKey(const Key('joint-not-a-debt'))).data,
      'Participar no es una compra ni genera una deuda: la persona '
      'responsable coordina la compra y la entrega.',
    );
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('joint-participate')))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'Inicio: aviso «Nueva convocatoria» hasta abrirla; Sindicato tiene la '
    'entrada',
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

      // Rediseño (2026-11-12): la entrada vive en la pestaña Sindicato.
      c.read(routerProvider).go('/sindicato');
      await ui.settle(tester);
      expect(find.byKey(const Key('union-joint-purchases')), findsOneWidget);
    },
  );

  // --- E2 §10.1: historial en la misma pantalla ---------------------------

  const oldId = 'fb1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const olderId = '0b1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const oldestId = '1b1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const recentClosedId = 'ab1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
  const cursor = 'WyIyMDI2LTAyLTAxVDEyOjAwOjAwLjAwMFoiLCIwYiJd';

  /// Pantalla «Compras conjuntas» suelta, con acceso vigente de memberA y el
  /// sindicato sintético [server]. Guardado: una abierta, una cerrada
  /// reciente, una anterior con un rechazo, y `older_count` 3.
  Future<({JointPurchaseStore store, List<http.Request> requests})> pumpList(
    WidgetTester tester,
    http.Response Function(http.Request) Function() server,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = (await tester.runAsync(
      () => seedSyncFixture(path: inMemoryDatabasePath),
    ))!;
    final store = JointPurchaseStore(
      fixture.database,
      clock: () => DateTime.utc(2026, 11, 11, 18, 20),
    );
    await tester.runAsync(() async {
      await seedCalls(store, memberA, [
        callJson(),
        callJson(
          id: recentClosedId,
          name: 'Compra cerrada reciente',
          status: 'CLOSED',
          participation: participationJson(),
          closedAt: '2026-11-05T22:00:00.000Z',
        ),
      ], olderCount: 3);
      await store.saveHistory(
        memberA,
        JointPurchaseHistoryPage.fromJson(
          historyJson([oldCallJson(oldId, finishedAt: '2026-04-01T12:00:00Z')]),
        ).calls,
      );
      await (await fixture.database.database).insert(
        JointPurchaseStore.opsTable,
        {
          'operation_id': '9e1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
          'call_id': oldId,
          'tenant_id': memberA.tenantId,
          'member_id': memberA.memberId,
          'sequence': 2,
          'kind': 'CONFIRM',
          'lines_json': '[{"product_ref":"$litreRef","quantity_base":"1"}]',
          'consent_version': 'CONV-1',
          'consent_accepted_at': '2026-03-01T00:00:00.000Z',
          'send_status': JointPurchaseOpStatus.rejected,
          'attempts': 1,
          'last_code': 'QUANTITY_INVALID',
          'created_at': '2026-03-01T00:00:00.000Z',
          'updated_at': '2026-03-01T00:00:00.000Z',
        },
      );
    });
    final requests = <http.Request>[];
    final api = JointPurchaseApi(
      json: AuthHttpClient(
        config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
        client: MockClient((request) async {
          requests.add(request);
          return server()(request);
        }),
      ),
    );
    final holder = SyncAccessHolder()
      ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(fixture.database),
        repositoryProvider.overrideWithValue(fixture.repo),
        declaredNeedStoreProvider.overrideWithValue(fixture.needs),
        centralBindingStoreProvider.overrideWithValue(fixture.bindings),
        syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
        jointPurchaseStoreProvider.overrideWithValue(store),
        jointPurchaseApiProvider.overrideWithValue(api),
        syncAccessHolderProvider.overrideWithValue(holder),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: JointPurchasesScreen())),
      ),
    );
    await settle(tester);
    return (store: store, requests: requests);
  }

  Finder inHistory(Finder finder) => find.descendant(
    of: find.byKey(const Key('joint-history-section')),
    matching: finder,
  );

  testWidgets(
    'lista: abiertas y recientes arriba; anteriores en «Historial» con su rechazo y las que faltan',
    (tester) async {
      await pumpList(
        tester,
        () =>
            (_) => fail('no debe pedir nada'),
      );
      expect(find.text('Compra conjunta de herbicida'), findsOneWidget);
      expect(find.text('Compra cerrada reciente'), findsOneWidget);
      expect(
        inHistory(find.text('Compra conjunta de herbicida')),
        findsNothing,
      );
      expect(inHistory(find.text('Compra cerrada reciente')), findsNothing);
      expect(inHistory(find.text('Compra anterior $oldId')), findsOneWidget);
      // El rechazo sigue visible con su convocatoria anterior.
      expect(
        inHistory(find.text('Rechazada: una cantidad no es válida')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Hay 2 convocatorias anteriores que no están en este teléfono.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('joint-history-query')), findsOneWidget);
      expect(find.byKey(const Key('joint-history-more')), findsNothing);
    },
  );

  testWidgets(
    '«Consultar historial» por páginas: «Ver más», error y fin, sin borrar nada',
    (tester) async {
      var step = 0;
      final s = await pumpList(
        tester,
        () => (request) {
          expect(request.url.path, '/api/v1/me/joint-purchase-calls/history');
          return switch (step) {
            0 => jsonResponse(
              historyJson([
                oldCallJson(olderId, finishedAt: '2026-02-01T12:00:00Z'),
              ], nextCursor: cursor),
              200,
            ),
            1 => jsonResponse({'errorCode': 'UNAVAILABLE'}, 503),
            _ => jsonResponse(
              historyJson([
                oldCallJson(
                  oldestId,
                  status: 'CANCELLED',
                  finishedAt: '2026-01-01T12:00:00Z',
                ),
              ]),
              200,
            ),
          };
        },
      );

      await tester.tap(find.byKey(const Key('joint-history-query')));
      await settle(tester);
      expect(s.requests.single.url.queryParameters, {'limit': '20'});
      expect(inHistory(find.text('Compra anterior $olderId')), findsOneWidget);
      expect(inHistory(find.text('Compra anterior $oldId')), findsOneWidget);
      expect(
        find.text('Hay 1 convocatoria anterior que no está en este teléfono.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('joint-history-more')), findsOneWidget);

      step = 1;
      await tester.tap(find.byKey(const Key('joint-history-more')));
      await settle(tester);
      expect(s.requests.last.url.queryParameters['before'], cursor);
      expect(
        find.text(
          'No se pudo leer el historial del sindicato. Lo guardado en el '
          'teléfono se conserva; inténtelo más tarde.',
        ),
        findsOneWidget,
      );
      // El cursor se conserva para volver a intentarlo.
      expect(find.byKey(const Key('joint-history-more')), findsOneWidget);

      step = 2;
      await tester.tap(find.byKey(const Key('joint-history-more')));
      await settle(tester);
      expect(s.requests.last.url.queryParameters['before'], cursor);
      expect(inHistory(find.text('Compra anterior $oldestId')), findsOneWidget);
      expect(find.byKey(const Key('joint-history-more')), findsNothing);
      expect(find.byKey(const Key('joint-history-end')), findsOneWidget);
      expect(find.byKey(const Key('joint-history-missing')), findsNothing);
      // Lo de la vista por defecto sigue ahí.
      expect(find.text('Compra conjunta de herbicida'), findsOneWidget);
      expect(
        (await tester.runAsync(() => s.store.overviewForActiveOwner()))!.older
            .map((c) => c.callId),
        [oldId, olderId, oldestId],
      );
    },
  );

  testWidgets(
    '«Consultar historial» sin conexión: avisa y lo guardado se sigue viendo',
    (tester) async {
      await pumpList(
        tester,
        () =>
            (_) => throw http.ClientException('sin red (prueba)'),
      );
      await tester.tap(find.byKey(const Key('joint-history-query')));
      await settle(tester);
      expect(find.text(jointPurchaseHistoryOfflineText), findsOneWidget);
      expect(inHistory(find.text('Compra anterior $oldId')), findsOneWidget);
      expect(
        find.text(
          'Hay 2 convocatorias anteriores que no están en este teléfono.',
        ),
        findsOneWidget,
      );
    },
  );

  // --- E4 §4.2: quién ve sus datos, aparte de las cantidades ---------------
  // (reescritas desde P-C, E2 §10.6: ampliar y reducir se retiran del flujo)

  testWidgets(
    'E4: modificar no pide consentimiento; revisar una participación anterior con CONV-4, casilla sin marcar, queda «pendiente», no aplicada',
    (tester) async {
      final s = await pumpDetail(tester);
      await tester.runAsync(
        () => seedCalls(s.store, memberA, [
          callJson(
            participation: participationJson(
              consentVersion: 'CONV-3',
              consentScope: 'RESPONSIBLE_ONLY',
              consentScopeVersion: 'CONV-3',
            ),
          ),
        ]),
      );
      s.c.read(jointPurchaseRevisionProvider.notifier).bump();
      await settle(tester);
      // Las opciones retiradas no aparecen.
      expect(find.byKey(const Key('joint-consent-widen')), findsNothing);
      expect(find.byKey(const Key('joint-consent-reduce')), findsNothing);
      expect(
        find.byKey(const Key('joint-responsible-authorize')),
        findsNothing,
      );
      expect(find.byKey(const Key('joint-access-retract')), findsNothing);
      // Modificar: sin diálogo de consentimiento; quién ve los datos no cambia.
      await enterQuantities(tester);
      expect(find.text(jointPurchaseConsentText), findsNothing);
      final ops = (await tester.runAsync(() => s.store.ops(callId)))!;
      expect(ops.single.consentVersion, isNull);
      expect(await tester.runAsync(() => s.store.consentOps(callId)), isEmpty);

      // Revisar: diálogo con el texto CONV-4, su ayuda y una casilla SIN marcar.
      await tester.tap(find.byKey(const Key('joint-access-review')));
      await settle(tester, rounds: 2);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('joint-access-review-text')))
            .data,
        jointPurchaseConsentText,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('joint-access-review-help')))
            .data,
        jointPurchaseConsentHelp,
      );
      expect(find.text('Sus cantidades no cambian.'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('joint-access-review-check')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('joint-access-review-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('joint-access-review-check')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('joint-access-review-confirm')));
      await settle(tester);

      final decisions = (await tester.runAsync(
        () => s.store.consentOps(callId),
      ))!;
      expect(decisions.single.scope, 'ADMINISTRATION');
      expect(decisions.single.consentVersion, 'CONV-4');
      expect(decisions.single.sendStatus, 'PENDING_SEND');
      // Las cantidades pendientes no cambiaron.
      expect((await tester.runAsync(() => s.store.ops(callId)))!.single.lines, {
        litreRef: 25000,
      });
      // Lo vigente sigue siendo lo aplicado en el sindicato.
      expect(
        tester.widget<Text>(find.byKey(const Key('joint-who-can-see'))).data,
        startsWith('Su participación se registró con un texto anterior.'),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('joint-consent-pending')))
            .data,
        'Pendiente de envío: autorizar a la Administración a ver su nombre y '
        'sus cantidades. Hasta que el sindicato la reciba, no está aplicada y '
        'rige lo que se indica arriba.',
      );
      expect(find.text('Enviar ahora'), findsOneWidget);
      // Ahora la acción ofrecida es retirarla.
      expect(find.byKey(const Key('joint-access-review')), findsNothing);
      expect(find.byKey(const Key('joint-access-retract')), findsOneWidget);
    },
  );

  testWidgets(
    'E4: retirar la autorización, casilla sin marcar; pendiente no se anuncia como efectiva; aplicada, se dice y la participación sigue',
    (tester) async {
      final s = await pumpDetail(tester);
      await tester.runAsync(
        () => seedCalls(s.store, memberA, [
          callJson(
            participation: participationJson(consentScope: 'ADMINISTRATION'),
          ),
        ]),
      );
      s.c.read(jointPurchaseRevisionProvider.notifier).bump();
      await settle(tester);
      expect(find.byKey(const Key('joint-access-review')), findsNothing);
      await tester.tap(find.byKey(const Key('joint-access-retract')));
      await settle(tester, rounds: 2);
      expect(find.text(jointPurchaseAccessRetractDetail), findsOneWidget);
      expect(find.text('Sus cantidades no cambian.'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('joint-access-retract-check')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('joint-access-retract-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('joint-access-retract-check')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('joint-access-retract-confirm')));
      await settle(tester);
      final pending = (await tester.runAsync(() => s.store.consentOps(callId)))!
          .single;
      expect(pending.scope, 'TOTALS_ONLY');
      expect(pending.sequence, 1);
      expect(await tester.runAsync(() => s.store.ops(callId)), isEmpty);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('joint-consent-pending')))
            .data,
        contains('no está aplicada'),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('joint-who-can-see'))).data,
        startsWith('La Administración habilitada de su sindicato puede ver'),
      );

      // El sindicato la acepta (como haría el emisor).
      await tester.runAsync(
        () => s.store.markConsentReceived(
          pending,
          JointPurchaseParticipation.fromJson(
            participationJson(
              consentScope: 'TOTALS_ONLY',
              consentScopeSequence: 1,
            ),
          ),
        ),
      );
      s.c.read(jointPurchaseRevisionProvider.notifier).bump();
      await settle(tester);
      expect(find.byKey(const Key('joint-consent-pending')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('joint-who-can-see'))).data,
        startsWith('Usted retiró la autorización'),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('joint-consent-result'))).data,
        contains('aplicada en el sindicato'),
      );
      // La participación sigue y se puede volver a autorizar.
      expect(
        find.text('El sindicato tiene: 25 L de Herbicida central'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('joint-access-review')), findsOneWidget);
    },
  );

  testWidgets(
    'E4: en una convocatoria cerrada se revisa; en una cancelada no se decide nada',
    (tester) async {
      final s = await pumpDetail(tester);
      await tester.runAsync(
        () => seedCalls(s.store, memberA, [
          callJson(
            status: 'CLOSED',
            participation: participationJson(consentScope: 'RESPONSIBLE_ONLY'),
            closing: {
              'cutoff_at': deadline,
              'closed_at': deadline,
              'included': true,
              'lines': [
                {
                  'product_ref': litreRef,
                  'base_unit': 'ML',
                  'quantity_base': '25000',
                },
              ],
            },
          ),
        ]),
      );
      s.c.read(jointPurchaseRevisionProvider.notifier).bump();
      await settle(tester);
      // Cerrada: no admite cambios de cantidades, pero sí la revisión.
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('joint-participate')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('joint-access-review')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.text(
          'Incluida en el consolidado al cierre: 25 L de Herbicida central',
        ),
        findsOneWidget,
      );

      await tester.runAsync(
        () => seedCalls(s.store, memberA, [
          callJson(
            status: 'CANCELLED',
            participation: participationJson(consentScope: 'RESPONSIBLE_ONLY'),
          ),
        ]),
      );
      s.c.read(jointPurchaseRevisionProvider.notifier).bump();
      await settle(tester);
      expect(find.byKey(const Key('joint-access-review')), findsNothing);
      expect(find.byKey(const Key('joint-access-retract')), findsNothing);
    },
  );

  testWidgets(
    'E4: una decisión anterior pendiente se dice como pendiente y retirada; el rechazo definitivo se explica',
    (tester) async {
      final s = await pumpDetail(tester);
      await tester.runAsync(() async {
        await seedCalls(s.store, memberA, [
          callJson(
            participation: participationJson(
              consentVersion: 'CONV-3',
              consentScope: 'RESPONSIBLE_ONLY',
              consentScopeVersion: 'CONV-3',
            ),
          ),
        ]);
        await (await s.fixture.database.database).insert(
          JointPurchaseStore.consentOpsTable,
          {
            'operation_id': '5e1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
            'call_id': callId,
            'tenant_id': memberA.tenantId,
            'member_id': memberA.memberId,
            'sequence': 1,
            'scope': 'COLLABORATORS',
            'consent_version': 'CONV-3',
            'decided_at': '2026-11-12T09:00:00.000Z',
            'send_status': 'PENDING_SEND',
            'attempts': 0,
            'created_at': '2026-11-12T09:00:00.000Z',
            'updated_at': '2026-11-12T09:00:00.000Z',
            'responsible_version': 1,
            'authorize_responsible': 1,
          },
        );
      });
      s.c.read(jointPurchaseRevisionProvider.notifier).bump();
      await settle(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('joint-consent-pending')))
            .data,
        startsWith(
          'Pendiente de envío: una decisión preparada con un texto anterior',
        ),
      );
      // La revisión sigue ofrecida: lo pendiente no habilita a nadie.
      expect(find.byKey(const Key('joint-access-review')), findsOneWidget);

      final legacy = (await tester.runAsync(() => s.store.consentOps(callId)))!
          .single;
      await tester.runAsync(
        () => s.store.markConsentRejected(legacy, 'CONSENT_VERSION_RETIRED'),
      );
      s.c.read(jointPurchaseRevisionProvider.notifier).bump();
      await settle(tester);
      expect(find.byKey(const Key('joint-consent-pending')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('joint-consent-result'))).data,
        'El sindicato no aplicó una decisión preparada con un texto anterior: '
        'esa opción ya no existe. Rige lo que se indica arriba.',
      );
    },
  );
}
