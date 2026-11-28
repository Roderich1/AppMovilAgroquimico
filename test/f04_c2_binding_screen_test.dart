// D-F04-C2, pantalla «Vincular con el sindicato». Se comprueba que la
// fecha elegida en la acción independiente de fin previsto llega a
// `AgroRepository.setCampaignPeriod` (una mutación que pasara otra fecha, o no
// la pasara, falla aquí), que el vínculo se revalida en el acto, que un fin
// anterior a hoy se advierte antes de confirmar, y que un fin que deja
// registros fuera se rechaza con su mensaje y sin escribir nada.
//
// Las referencias se prueban con un servidor simulado.
import 'dart:async';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:agroquimicos/presentation/screens/central_binding_screen.dart';
import 'package:agroquimicos/presentation/widgets/union_updates.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:agroquimicos/services/sync/union_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e2_joint_purchase_fixtures.dart' show jsonResponse;
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

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

  /// Campaña local vinculada a una central sin fin; después la central gana
  /// fin (31/10/2026) y el vínculo queda incompatible por el fin abierto.
  Future<SyncFixture> pumpIncompatible(
    WidgetTester tester, {
    DateTime? needOn,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = (await tester.runAsync(() async {
      final seeded = await seedSyncFixture(path: inMemoryDatabasePath);
      if (needOn != null) {
        await seeded.needs.declare(
          referenceDate: needOn,
          productId: seeded.litreProductId,
          quantityBase: 1000,
        );
      }
      await seeded.bindings.refreshFrom(
        CentralReferences([
          centralCampaign(endDate: '2026-10-31T00:00:00.000Z'),
        ], referencesWith().products),
        memberA.tenantId,
      );
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
        ],
        child: const MaterialApp(home: Scaffold(body: CentralBindingScreen())),
      ),
    );
    await settle(tester);
    // Rediseño (sesión C): las campañas están en su pestaña.
    await tester.tap(find.byKey(const Key('binding-tab-campaigns')));
    await settle(tester);
    return fixture;
  }

  /// Lecturas de la base siempre dentro de `runAsync`: fuera de él, el
  /// trabajo real del motor deja la zona de prueba a medias y el siguiente
  /// `tap` nunca termina.
  Future<Map<String, Object?>> campaignRow(
    WidgetTester tester,
    SyncFixture fixture,
  ) async => (await tester.runAsync(
    () async => (await (await fixture.database.database).query(
      'campaigns',
      where: 'id=?',
      whereArgs: [fixture.campaignId],
    )).single,
  ))!;

  testWidgets(
    'el selector propone el fin y guarda la fecha elegida con el vínculo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = (await tester.runAsync(
        () => seedSyncFixture(bindCatalog: false),
      ))!;
      addTearDown(fixture.database.close);
      final access = SyncAccessHolder()
        ..acceptForReads(
          'token-de-prueba',
          memberA.memberId,
          memberA.tenantId,
          () => true,
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(fixture.database),
            repositoryProvider.overrideWithValue(fixture.repo),
            centralBindingStoreProvider.overrideWithValue(fixture.bindings),
            syncAccessHolderProvider.overrideWithValue(access),
            unionRefreshProvider.overrideWith(_CampaignReferences.new),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CentralBindingScreen()),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('binding-tab-campaigns')));
      await settle(tester);

      Future<void> openCombinedAction() async {
        final row = find.byKey(Key('campaign-binding-${fixture.campaignId}'));
        await tester.tap(
          find.descendant(
            of: row,
            matching: find.byType(PopupMenuButton<String>),
          ),
        );
        await settle(tester);
        await tester.tap(find.text('Vincular…'));
        await settle(tester);
        expect(find.text('Fijar fin previsto y vincular'), findsOneWidget);
        expect(find.textContaining('Cerrada ·'), findsNothing);
        expect(find.textContaining('Ciclo anterior'), findsNothing);
        await tester.tap(find.text('Fijar fin previsto y vincular'));
        await settle(tester);
        expect(find.text('03/02/2027'), findsOneWidget);
      }

      await openCombinedAction();
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect((await campaignRow(tester, fixture))['end_date'], isNull);
      expect(await tester.runAsync(fixture.bindings.campaignBindings), isEmpty);

      await openCombinedAction();
      await tester.tap(find.byKey(const Key('campaign-period-end')));
      await settle(tester);
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.lastDate, DateTime(2027, 2, 3));
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('Aceptar'));
      await settle(tester);
      expect(find.text('02/02/2027'), findsOneWidget);
      await tester.tap(find.text('Confirmar fecha y vínculo'));
      await settle(tester);

      final local = await campaignRow(tester, fixture);
      expect(local['status'], 'ACTIVE');
      expect(storedLocalDay(local['end_date']! as String), '2027-02-02');
      final bindings = (await tester.runAsync(
        fixture.bindings.campaignBindings,
      ))!;
      expect(bindings.single.isValid, isTrue);
      expect(bindings.single.campaignRef, campaignRef);
      expect(access.current, isNull);
    },
  );

  testWidgets('Valle Claro ajusta ambos extremos al vincularse', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = (await tester.runAsync(() async {
      final seeded = await seedSyncFixture(bindCatalog: false);
      final initial = CampaignPeriod.fromRow(
        (await seeded.repo.campaigns()).single,
      );
      await seeded.repo.setCampaignPeriod(
        initial,
        initial.withDates(startDay: '2026-11-03', endDay: '2027-03-02'),
      );
      return seeded;
    }))!;
    addTearDown(fixture.database.close);
    final access = SyncAccessHolder()
      ..acceptForReads(
        'prueba',
        memberA.memberId,
        memberA.tenantId,
        () => true,
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(fixture.database),
          repositoryProvider.overrideWithValue(fixture.repo),
          centralBindingStoreProvider.overrideWithValue(fixture.bindings),
          syncAccessHolderProvider.overrideWithValue(access),
          unionRefreshProvider.overrideWith(
            () => _CampaignReferences(start: '2026-11-06T00:00:00.000Z'),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: CentralBindingScreen())),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('binding-tab-campaigns')));
    await settle(tester);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('Vincular…'));
    await settle(tester);
    expect(find.textContaining('Cerrada ·'), findsNothing);
    expect(find.textContaining('Ciclo anterior'), findsNothing);
    await tester.tap(find.text('Ajustar fechas y vincular'));
    await settle(tester);
    expect(find.text('06/11/2026'), findsOneWidget);
    expect(find.text('03/02/2027'), findsOneWidget);

    await tester.tap(find.byKey(const Key('campaign-period-confirm')));
    await settle(tester);
    final row = await campaignRow(tester, fixture);
    expect(storedLocalDay(row['start_date']! as String), '2026-11-06');
    expect(storedLocalDay(row['end_date']! as String), '2027-02-03');
    expect(row['status'], 'ACTIVE');
    expect(
      (await tester.runAsync(fixture.bindings.campaignBindings))!
          .single
          .isValid,
      isTrue,
    );
  });

  testWidgets(
    'al volver internet consulta y vincula un producto con acceso de lectura',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = (await tester.runAsync(seedSyncFixture))!;
      addTearDown(fixture.database.close);
      final access = SyncAccessHolder()
        ..acceptForReads(
          'prueba',
          memberA.memberId,
          memberA.tenantId,
          () => true,
        );
      final connectivity = StreamController<bool>();
      addTearDown(connectivity.close);
      final methods = <String>[];
      final client = MockClient((request) async {
        methods.add(request.method);
        expect(request.url.path, '/api/v1/sync/v1/references');
        final products = [
          centralProduct(),
          centralProduct(ref: kiloRef, name: 'Producto en kilos', unit: 'KG'),
          centralProduct(
            ref: unitRef,
            name: 'Producto sin equivalencia',
            unit: 'unidad',
          ),
          centralProduct(ref: otherLitreRef, name: 'Compatible en litros'),
          centralProduct(
            ref: 'b1000001-0000-4000-8000-000000000009',
            name: 'Inactivo en litros',
            active: false,
          ),
        ];
        return jsonResponse({
          ...referencesJson(),
          'products': [
            for (final product in products)
              {
                'product_ref': product.ref,
                'name': product.name,
                'unit': product.unit,
                'base_unit': product.baseUnit?.code,
                'is_active': product.isActive,
                'linkable': product.linkable,
              },
          ],
        }, 200);
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(fixture.database),
            repositoryProvider.overrideWithValue(fixture.repo),
            centralBindingStoreProvider.overrideWithValue(fixture.bindings),
            syncAccessHolderProvider.overrideWithValue(access),
            unionAutoRefreshEnabledProvider.overrideWithValue(true),
            unionConnectivityProvider.overrideWith(
              (ref) => connectivity.stream,
            ),
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
          child: const MaterialApp(
            home: Scaffold(
              body: UnionUpdates(
                feeds: {UnionFeed.references},
                child: CentralBindingScreen(),
              ),
            ),
          ),
        ),
      );
      connectivity.add(false);
      await settle(tester);
      expect(methods, isEmpty);
      expect(find.textContaining('Sin conexión'), findsOneWidget);

      connectivity.add(true);
      await settle(tester);
      expect(methods, ['GET']);
      expect(find.textContaining('Actualizado a las'), findsOneWidget);

      final row = find.byKey(
        Key('product-binding-${fixture.unboundProductId}'),
      );
      await tester.tap(
        find.descendant(
          of: row,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Vincular…'));
      await settle(tester);
      expect(find.text('Compatible en litros (L)'), findsOneWidget);
      for (final name in [
        'Herbicida central (L)',
        'Producto en kilos (KG)',
        'Producto sin equivalencia (unidad)',
        'Inactivo en litros (L)',
      ]) {
        expect(find.text(name), findsNothing);
      }
      await tester.tap(find.text('Compatible en litros (L)'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Vincular'));
      await settle(tester);
      final bindings = (await tester.runAsync(
        fixture.bindings.productBindings,
      ))!;
      expect(
        bindings
            .singleWhere((b) => b.productId == fixture.unboundProductId)
            .productRef,
        otherLitreRef,
      );
      expect(access.current, isNull);
      expect(methods, ['GET']);
    },
  );

  /// Abre «Editar período…» de la campaña y elige el día 15 del mes que
  /// propone el selector (el fin central, octubre de 2026).
  Future<void> pickDay15(WidgetTester tester, SyncFixture fixture) async {
    final row = find.byKey(Key('campaign-binding-${fixture.campaignId}'));
    expect(row, findsOneWidget);
    await tester.tap(
      find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
    );
    await settle(tester);
    await tester.tap(find.text('Editar período…'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('campaign-period-end')));
    await settle(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('15'));
    await tester.pump();
    await tester.tap(find.text('Aceptar'));
    await settle(tester);
    expect(find.text('15/10/2026'), findsOneWidget);
  }

  testWidgets(
    'la fecha elegida llega al editor del período, el vínculo se revalida y un fin pasado se advierte',
    (tester) async {
      final fixture = await pumpIncompatible(tester);
      expect(find.byKey(const Key('period-review')), findsOneWidget);
      expect(
        find.textContaining('fije un fin previsto hasta el 31/10/2026'),
        findsWidgets,
      );
      expect((await campaignRow(tester, fixture))['end_date'], isNull);

      await pickDay15(tester, fixture);
      // El 15/10/2026 ya pasó: la confirmación lo advierte (hallazgo menor
      // de la revisión de A).
      expect(
        find.text('La fecha de hoy queda fuera del período propuesto.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar período'));
      await settle(tester);

      final row = await campaignRow(tester, fixture);
      expect(storedLocalDay(row['end_date']! as String), '2026-10-15');
      expect(row['status'], 'ACTIVE', reason: 'fijar el fin no cierra');
      final binding = (await tester.runAsync(
        fixture.bindings.campaignBindings,
      ))!.single;
      expect(binding.isValid, isTrue);
      expect(binding.invalidReason, isNull);
      expect(find.text('Período actualizado.'), findsOneWidget);
      expect(find.byKey(const Key('period-review')), findsNothing);
      expect(
        find.textContaining(
          'Campaña local 2026 (del 01/09/2026 al 15/10/2026)',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'un fin que deja registros fuera se rechaza con el mensaje y sin escrituras',
    (tester) async {
      final fixture = await pumpIncompatible(
        tester,
        needOn: DateTime(2026, 10, 20),
      );
      final before = await tester.runAsync(
        () async => dumpTables(await fixture.database.database),
      );

      await pickDay15(tester, fixture);
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar período'));
      await settle(tester);

      expect(
        find.textContaining('tiene registros del 20/10/2026'),
        findsOneWidget,
      );
      expect(find.text('Período actualizado.'), findsNothing);
      expect(
        await tester.runAsync(
          () async => dumpTables(await fixture.database.database),
        ),
        before,
        reason: 'un rechazo no escribe nada',
      );
      final binding = (await tester.runAsync(
        fixture.bindings.campaignBindings,
      ))!.single;
      expect(binding.invalidReason, BindingInvalidReason.periodIncompatible);
      expect(find.byKey(const Key('period-review')), findsOneWidget);
    },
  );
}

class _CampaignReferences extends UnionRefresh {
  _CampaignReferences({this.start = '2026-09-01T00:00:00.000Z'});

  final String start;

  @override
  Map<UnionFeed, UnionReadStatus> build() => {
    UnionFeed.references: (
      lastRead: null,
      issue: null,
      busy: false,
      references: CentralReferences([
        centralCampaign(startDate: start, endDate: '2027-02-03T00:00:00.000Z'),
        centralCampaign(ref: otherCampaignRef, name: 'Cerrada', accepts: false),
        centralCampaign(
          ref: 'b1000000-0000-4000-8000-000000000001',
          name: 'Ciclo anterior',
          startDate: '2026-07-01T00:00:00.000Z',
          endDate: '2026-08-31T00:00:00.000Z',
        ),
      ], const []),
    ),
  };
}
