// UXJ-C (2026-11-05): «Vincular con el sindicato» con el motivo de cada
// incompatibilidad en la fila afectada, y «Consumo para el sindicato» con los
// estados «Pendiente», «Enviado» y «Requiere atención» derivados de la outbox.
// La publicación sigue siendo expresa (F04 §2.4): no hay envío automático.
// Casos: vínculo inválido, sesión sin autorización y campaña cerrada o
// sellada. Sin red: la API usa un MockClient o no se llama. Datos sintéticos.
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/data/sync/consumption_publisher.dart';
import 'package:agroquimicos/presentation/widgets/rdm_c_page.dart' show RdmCRow;
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/presentation/screens/central_binding_screen.dart';
import 'package:agroquimicos/presentation/screens/consumption_publish_screen.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';
import 'support/f06_consumption_fixtures.dart';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  Future<List<OutboxEntry>> consumption(ConsumptionFixture f) async =>
      (await f.sync.outboxEntries())
          .where((e) => e.projectionType == ProjectionType.consumptionTotal)
          .toList();

  OutboxEntry entryFor(List<OutboxEntry> entries, String productRef) =>
      entries.lastWhere((e) => e.productRef == productRef);

  /// Titular con 2,5 L de Herbicida y 1,5 KG de Fungicida aplicados y ya
  /// publicados (dos intenciones PENDING sin enviar).
  Future<ConsumptionFixture> publishedTwo() async {
    final f = await seedConsumptionFixture(path: inMemoryDatabasePath);
    await f.apply(f.ownerPersonId, {
      f.sync.litreProductId: 2500,
      f.sync.kiloProductId: 1500,
    });
    expect(await f.publisher.publish(await f.publisher.preview()), 2);
    return f;
  }

  // -------------------------------------------------------------------
  // Consumo para el sindicato.

  Future<ConsumptionFixture> pumpConsumption(
    WidgetTester tester,
    Future<ConsumptionFixture> Function() prepare,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = (await tester.runAsync(prepare))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(f.sync.database),
          repositoryProvider.overrideWithValue(f.sync.repo),
          syncOutboxStoreProvider.overrideWithValue(f.sync.outbox),
          consumptionPublisherProvider.overrideWithValue(f.publisher),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ConsumptionPublishScreen()),
        ),
      ),
    );
    await settle(tester);
    return f;
  }

  Finder row(String productRef) =>
      find.byKey(Key('consumption-$campaignRef-$productRef'));

  Finder rowText(String productRef, String text) =>
      find.descendant(of: row(productRef), matching: find.textContaining(text));

  testWidgets('estados Pendiente y Enviado derivados de la outbox', (
    tester,
  ) async {
    final f = await pumpConsumption(tester, () async {
      final f = await publishedTwo();
      final litre = entryFor(await consumption(f), litreRef);
      await f.sync.outbox.recordAccepted(
        await f.sync.outbox.markSending(litre),
        '2026-10-16T12:00:00.000Z',
      );
      // Un tercer producto con consumo y sin publicar.
      await f.apply(f.ownerPersonId, {f.extraLitreProductId: 400});
      return f;
    });
    expect(rowText(litreRef, '2,5 L · Enviado'), findsOneWidget);
    expect(rowText(litreRef, 'Aceptado por el sindicato'), findsOneWidget);
    expect(rowText(kiloRef, '1,5 KG · Pendiente'), findsOneWidget);
    expect(rowText(kiloRef, 'Guardado, pendiente de envío'), findsOneWidget);
    expect(rowText(extraLitreRef, '0,4 L · Pendiente'), findsOneWidget);
    expect(
      rowText(extraLitreRef, 'Nuevo: se publicará si pulsa «Publicar»'),
      findsOneWidget,
    );
    // Nada se envía solo: la vista no escribió nada nuevo.
    expect(await tester.runAsync(() => consumption(f)), hasLength(2));
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('publish-consumption')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
    'sesión sin verificar (401): Requiere atención y «Falta verificar el acceso»',
    (tester) async {
      await pumpConsumption(tester, () async {
        final f = await publishedTwo();
        final litre = entryFor(await consumption(f), litreRef);
        await f.sync.outbox.recordAuthRequired(
          await f.sync.outbox.markSending(litre),
        );
        return f;
      });
      expect(rowText(litreRef, '2,5 L · Requiere atención'), findsOneWidget);
      expect(rowText(litreRef, 'Falta verificar el acceso.'), findsOneWidget);
      expect(rowText(kiloRef, '1,5 KG · Pendiente'), findsOneWidget);
      expect(rowText(kiloRef, 'Falta verificar el acceso'), findsNothing);
    },
  );

  testWidgets(
    'cuenta no autorizada (403): la cola pausada se ve como Requiere atención',
    (tester) async {
      await pumpConsumption(tester, () async {
        final f = await publishedTwo();
        expect(
          await f.sync.outbox.pauseForAuthorization(f.sync.ownerBindingId),
          2,
        );
        return f;
      });
      for (final ref in [litreRef, kiloRef]) {
        expect(rowText(ref, 'Requiere atención'), findsOneWidget);
        expect(
          rowText(ref, 'Pausado: el sindicato no autorizó esta cuenta'),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'campaña cerrada o sellada: Requiere atención con el mensaje vigente y sin '
    'volver a publicar',
    (tester) async {
      final f = await pumpConsumption(tester, () async {
        final f = await publishedTwo();
        final entries = await consumption(f);
        // Dos códigos en la misma campaña sólo para cubrir los dos mensajes.
        await f.sync.outbox.recordTerminal(
          await f.sync.outbox.markSending(entryFor(entries, litreRef)),
          OutboxStatus.rejected,
          'CAMPAIGN_NOT_OPEN',
        );
        await f.sync.outbox.recordTerminal(
          await f.sync.outbox.markSending(entryFor(entries, kiloRef)),
          OutboxStatus.rejected,
          'CAMPAIGN_SEALED',
        );
        return f;
      });
      expect(rowText(litreRef, '2,5 L · Requiere atención'), findsOneWidget);
      expect(
        rowText(
          litreRef,
          'La campaña ya no admite publicaciones en el sindicato. Su '
          'registro privado se conserva.',
        ),
        findsOneWidget,
      );
      // m3 de B: el mensaje de CAMPAIGN_NOT_OPEN no dice «sellada».
      expect(rowText(litreRef, 'sellada'), findsNothing);
      expect(rowText(kiloRef, '1,5 KG · Requiere atención'), findsOneWidget);
      expect(
        rowText(kiloRef, 'Esta campaña está sellada en el sindicato'),
        findsOneWidget,
      );
      // Fallo terminal (F04 §2.4): «Publicar» no tiene nada que enviar.
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('publish-consumption')),
      );
      expect(button.onPressed, isNull);
      expect(await tester.runAsync(() => consumption(f)), hasLength(2));
    },
  );

  // -------------------------------------------------------------------
  // El publicador, sin pantalla.

  group('rechazo terminal por el estado de la campaña', () {
    test('no se vuelve a publicar ni con otra vista previa', () async {
      final f = await publishedTwo();
      final litre = entryFor(await consumption(f), litreRef);
      await f.sync.outbox.recordTerminal(
        await f.sync.outbox.markSending(litre),
        OutboxStatus.rejected,
        'CAMPAIGN_NOT_OPEN',
      );
      // Una aplicación posterior cambia el total: tampoco se publica.
      await f.apply(f.ownerPersonId, {f.sync.litreProductId: 500});
      final preview = await f.publisher.preview();
      final shown = preview.rows.singleWhere(
        (r) => r.target.productRef == litreRef,
      );
      expect(shown.change, ConsumptionChange.rejected);
      expect(shown.sends, isFalse);
      expect(shown.sendState, ConsumptionSendState.attention);
      expect(shown.lastRejection?.operationId, litre.operationId);
      expect(shown.quantityBase, 3000, reason: 'el total local se conserva');
      expect(await f.publisher.publish(preview), 0);
      expect(await consumption(f), hasLength(2));
    });

    test('si después las referencias muestran la campaña abierta, se puede '
        'publicar otra vez de forma expresa', () async {
      final f = await publishedTwo();
      final litre = entryFor(await consumption(f), litreRef);
      await f.sync.outbox.recordTerminal(
        await f.sync.outbox.markSending(litre),
        OutboxStatus.rejected,
        'CAMPAIGN_NOT_OPEN',
      );
      // Referencias leídas con la campaña todavía cerrada: sigue retenido.
      final later = CentralBindingStore(
        f.sync.database,
        clock: () => DateTime.now().add(const Duration(minutes: 1)),
      );
      await later.refreshFrom(
        referencesWith(campaignAccepts: false),
        memberA.tenantId,
      );
      var preview = await f.publisher.preview();
      expect(
        preview.rows.where((r) => r.target.productRef == litreRef),
        isEmpty,
        reason: 'vínculo no vigente: el par queda excluido, no se publica',
      );
      // Abierta otra vez: vuelve a ser una publicación nueva y expresa.
      await later.refreshFrom(referencesWith(), memberA.tenantId);
      preview = await f.publisher.preview();
      final shown = preview.rows.singleWhere(
        (r) => r.target.productRef == litreRef,
      );
      expect(shown.change, ConsumptionChange.publish);
      expect(shown.sendState, ConsumptionSendState.attention);
      expect(await f.publisher.publish(preview), 1);
      final again = entryFor(await consumption(f), litreRef);
      expect(again.operationId, isNot(litre.operationId));
      expect(again.status, OutboxStatus.pending);
    });

    test('un rechazo de otra familia se muestra y «Publicar» lo puede volver a '
        'enviar como decisión nueva', () async {
      final f = await publishedTwo();
      final litre = entryFor(await consumption(f), litreRef);
      await f.sync.outbox.recordTerminal(
        await f.sync.outbox.markSending(litre),
        OutboxStatus.rejected,
        'REFERENCE_UNAVAILABLE',
      );
      final preview = await f.publisher.preview();
      final shown = preview.rows.singleWhere(
        (r) => r.target.productRef == litreRef,
      );
      expect(shown.change, ConsumptionChange.publish);
      expect(shown.sendState, ConsumptionSendState.attention);
      expect(await f.publisher.publish(preview), 1);
    });
  });

  // -------------------------------------------------------------------
  // Vincular con el sindicato.

  Future<SyncFixture> pumpBinding(
    WidgetTester tester, {
    bool bindCatalog = true,
    CentralReferences? refreshWith,
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = (await tester.runAsync(() async {
      final seeded = await seedSyncFixture(
        path: inMemoryDatabasePath,
        bindCatalog: bindCatalog,
      );
      if (refreshWith != null) {
        await seeded.bindings.refreshFrom(refreshWith, memberA.tenantId);
      }
      return seeded;
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(fixture.database),
          repositoryProvider.overrideWithValue(fixture.repo),
          declaredNeedStoreProvider.overrideWithValue(fixture.needs),
          centralBindingStoreProvider.overrideWithValue(fixture.bindings),
          syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
          ...overrides,
        ],
        child: const MaterialApp(home: Scaffold(body: CentralBindingScreen())),
      ),
    );
    await settle(tester);
    return fixture;
  }

  testWidgets('texto inicial corto; el detalle está en las filas', (
    tester,
  ) async {
    await pumpBinding(tester);
    expect(find.text('Elija el equivalente del sindicato.'), findsOneWidget);
    expect(find.textContaining('Nada se vincula por nombre'), findsNothing);
    expect(
      find.text('Pulse «Actualizar» para ver las opciones del sindicato.'),
      findsOneWidget,
    );
    expect(find.textContaining('Herbicida central · vigente'), findsOneWidget);
  });

  testWidgets('vínculo inválido: el motivo está en la fila afectada', (
    tester,
  ) async {
    final fixture = await pumpBinding(
      tester,
      refreshWith: CentralReferences(
        [centralCampaign(endDate: '2026-10-31T00:00:00.000Z')],
        [
          // El producto central del vínculo en L pasó a KG.
          centralProduct(unit: 'KG'),
          centralProduct(
            ref: kiloRef,
            name: 'Fungicida central',
            unit: 'KG',
            active: false,
          ),
        ],
      ),
    );
    Finder productRow(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(RdmCRow));
    expect(
      find.descendant(
        of: productRow('Herbicida local (L)'),
        matching: find.textContaining(
          'Herbicida central · Requiere atención: La unidad del sindicato ya '
          'no es L ni KG, o ya no coincide con la local.\n'
          'Unidad del sindicato: KG; local: L.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: productRow('Fungicida local (KG)'),
        matching: find.textContaining(
          'Fungicida central · Requiere atención: El producto está inactivo '
          'en el sindicato.',
        ),
      ),
      findsOneWidget,
    );
    // Rediseño (sesión C): las campañas están en su pestaña.
    await tester.tap(find.byKey(const Key('binding-tab-campaigns')));
    await settle(tester);
    final campaign = find.byKey(Key('campaign-binding-${fixture.campaignId}'));
    for (final text in [
      'Requiere atención: El período local no cabe en el de la campaña del '
          'sindicato.',
      'fije un fin previsto hasta el 31/10/2026',
      'Aceptados con este vínculo: 0 · en cola, retenidos: 0.',
      'Fije el fin previsto o corrija el vínculo',
    ]) {
      expect(
        find.descendant(of: campaign, matching: find.textContaining(text)),
        findsOneWidget,
        reason: text,
      );
    }
    // Arriba sólo un aviso breve con el nombre de la campaña.
    expect(
      find.descendant(
        of: find.byKey(const Key('period-review')),
        matching: find.textContaining('Campaña local 2026: no se envían'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'sin opción compatible en el sindicato, la fila sin vincular dice por qué',
    (tester) async {
      final json = referencesJson();
      final campaign = Map<String, Object?>.of(
        (json['campaigns']! as List).single as Map<String, Object?>,
      );
      json['campaigns'] = [
        {...campaign, 'status': 'CERRADA', 'accepts_contributions': false},
      ];
      json['products'] = [
        for (final product in json['products']! as List)
          if ((product as Map)['product_ref'] != litreRef) product,
        {
          'product_ref': kiloRef,
          'name': 'Fungicida central',
          'unit': 'KG',
          'base_unit': 'G',
          'is_active': true,
          'linkable': true,
        },
      ];
      final access = SyncAccessHolder()
        ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode(json),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final fixture = await pumpBinding(
        tester,
        bindCatalog: false,
        overrides: [
          syncAccessHolderProvider.overrideWithValue(access),
          syncApiProvider.overrideWithValue(
            SyncApi(
              AuthHttpClient(
                config: ApiEndpointConfig(
                  Uri.parse('https://sindicato.example'),
                ),
                client: client,
              ),
            ),
          ),
        ],
      );
      expect(find.textContaining('Ningún producto'), findsNothing);
      await tester.tap(find.text('Actualizar'));
      await settle(tester);
      Finder productRow(String label) =>
          find.ancestor(of: find.text(label), matching: find.byType(RdmCRow));
      expect(
        find.descendant(
          of: productRow('Herbicida local (L)'),
          matching: find.textContaining(
            'Requiere vinculación\nNingún producto del sindicato es '
            'compatible: unidad central sin equivalencia L/KG; unidad '
            'distinta: no se convierte.',
          ),
        ),
        findsOneWidget,
      );
      // Con una opción compatible, sólo «Requiere vinculación».
      expect(
        find.descendant(
          of: productRow('Fungicida local (KG)'),
          matching: find.text('Requiere vinculación'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('binding-tab-campaigns')));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(Key('campaign-binding-${fixture.campaignId}')),
          matching: find.textContaining(
            'Ninguna campaña del sindicato es compatible',
          ),
        ),
        findsOneWidget,
      );
      // Leer las referencias no vincula nada.
      expect(
        (await tester.runAsync(fixture.bindings.productBindings))!,
        isEmpty,
      );
    },
  );
}
