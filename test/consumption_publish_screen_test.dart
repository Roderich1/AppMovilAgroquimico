// F06 (MOB #33): publicar el consumo exige una vista previa y una
// confirmación expresa; cancelar no escribe nada.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/presentation/screens/consumption_publish_screen.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  Future<ConsumptionFixture> pump(
    WidgetTester tester,
    Future<void> Function(ConsumptionFixture f) prepare,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = (await tester.runAsync(() async {
      final fixture = await seedConsumptionFixture(path: inMemoryDatabasePath);
      await prepare(fixture);
      return fixture;
    }))!;
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

  Future<List<OutboxEntry>> consumption(
    WidgetTester tester,
    ConsumptionFixture f,
  ) async =>
      (await tester.runAsync(f.sync.outboxEntries))!
          .where((e) => e.projectionType == ProjectionType.consumptionTotal)
          .toList();

  testWidgets('vista previa, confirmación expresa y cancelar sin escribir', (
    tester,
  ) async {
    final f = await pump(tester, (f) async {
      await f.apply(f.ownerPersonId, {
        f.sync.litreProductId: 2500,
        f.sync.kiloProductId: 1500,
        f.sync.unboundProductId: 100,
      });
      await f.apply(f.familyPersonId, {f.sync.litreProductId: 9000});
    });
    expect(find.text('Herbicida local · Campaña local 2026'), findsOneWidget);
    expect(find.textContaining('2,5 L · Nuevo'), findsOneWidget);
    expect(find.textContaining('1,5 KG · Nuevo'), findsOneWidget);
    expect(find.textContaining('familiares o terceros'), findsOneWidget);
    expect(
      find.textContaining(
        'Adherente local (Campaña local 2026): el producto no está vinculado',
      ),
      findsOneWidget,
    );
    expect(await consumption(tester, f), isEmpty);

    await tester.tap(find.byKey(const Key('publish-consumption')));
    await settle(tester);
    expect(
      find.textContaining('• Herbicida local (Campaña local 2026): 2,5 L'),
      findsOneWidget,
    );
    expect(
      find.textContaining('sustituye al anterior; no se suma'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await settle(tester);
    expect(await consumption(tester, f), isEmpty);

    await tester.tap(find.byKey(const Key('publish-consumption')));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Publicar'));
    await settle(tester);
    final entries = await consumption(tester, f);
    expect(entries.map((e) => e.quantityBase).toSet(), {'2500', '1500'});
    expect(find.textContaining('Sin cambios'), findsNWidgets(2));
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('publish-consumption')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('sin consumo propio vinculado no hay nada que publicar', (
    tester,
  ) async {
    await pump(tester, (f) async {
      await f.apply(f.familyPersonId, {f.sync.litreProductId: 9000});
    });
    expect(
      find.text('No hay consumo propio en campañas y productos vinculados.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('publish-consumption')),
    );
    expect(button.onPressed, isNull);
  });
}
