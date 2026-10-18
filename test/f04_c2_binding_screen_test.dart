// D-F04-C2, pantalla «Vincular con el sindicato»: «Fijar fin previsto…» es la
// única vía de la interfaz que escribe el período de una campaña. Se
// comprueba que la fecha elegida en el selector llega a
// `AgroRepository.setCampaignEnd` (una mutación que pasara otra fecha, o no
// la pasara, falla aquí), que el vínculo se revalida en el acto, que un fin
// anterior a hoy se advierte antes de confirmar, y que un fin que deja
// registros fuera se rechaza con su mensaje y sin escribir nada.
//
// Sin red: las referencias centrales se aplican con `refreshFrom`.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:agroquimicos/presentation/screens/central_binding_screen.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  /// Abre «Fijar fin previsto…» de la campaña y elige el día 15 del mes que
  /// propone el selector (el fin central, octubre de 2026).
  Future<void> pickDay15(WidgetTester tester, SyncFixture fixture) async {
    final row = find.byKey(Key('campaign-binding-${fixture.campaignId}'));
    expect(row, findsOneWidget);
    await tester.tap(
      find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
    );
    await settle(tester);
    await tester.tap(find.text('Fijar fin previsto…'));
    await settle(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(
      find.textContaining('sindicato: hasta el 31/10/2026'),
      findsOneWidget,
    );
    await tester.tap(find.text('15'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.text('Fijar fin previsto'), findsOneWidget);
    expect(
      find.textContaining('pasará a ir del 01/09/2026 al 15/10/2026'),
      findsOneWidget,
    );
  }

  testWidgets(
    'la fecha elegida llega a setCampaignEnd, el vínculo se revalida y un fin pasado se advierte',
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
      expect(find.textContaining('ese fin ya pasó'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Fijar'));
      await settle(tester);

      final row = await campaignRow(tester, fixture);
      expect(storedLocalDay(row['end_date']! as String), '2026-10-15');
      expect(row['status'], 'ACTIVE', reason: 'fijar el fin no cierra');
      final binding = (await tester.runAsync(
        fixture.bindings.campaignBindings,
      ))!.single;
      expect(binding.isValid, isTrue);
      expect(binding.invalidReason, isNull);
      expect(find.text('Fin previsto fijado.'), findsOneWidget);
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
      await tester.tap(find.widgetWithText(FilledButton, 'Fijar'));
      await settle(tester);

      expect(
        find.textContaining('tiene registros del 20/10/2026'),
        findsOneWidget,
      );
      expect(find.text('Fin previsto fijado.'), findsNothing);
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
