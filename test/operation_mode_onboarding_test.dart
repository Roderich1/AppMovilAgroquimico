// MODE-02 (#25): elección comprensible de la modalidad tras activar, consulta
// y cambio posterior, y mensajes de transición, sin perder historial y sin
// red. App real; el transporte HTTP falla y cuenta cualquier petición.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/presentation/screens/operation_mode_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  const businessOnly = {'app_settings'};

  testWidgets('recién activado sin titular: elige la modalidad con su '
      'explicación, queda guardada y la interfaz la refleja, sin red', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final file = await tester.runAsync(() => tempDbPath('nueva'));
    final database = openDb(file!);
    final offline = OfflineTransport();
    final c = await pumpModeApp(tester, database, transport: offline);
    // Espera explícita: bajo carga, la redirección a /titular puede llegar
    // después de que el arnés deje de ver indicadores de carga.
    await waitFor(tester, find.byKey(const Key('owner-mode-help')));
    expect(
      c.read(installationAccessProvider),
      InstallationAccessState.activationPendingOwner,
    );
    expect(currentPath(c), '/titular');
    expect(find.byKey(const Key('owner-mode-help')), findsOneWidget);
    expect(
      find.text(operationModeExplanation(OperationMode.shared)),
      findsOneWidget,
    );
    expect(
      find.text(operationModeExplanation(OperationMode.personal)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('owner-create-new')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('owner-new-name')), 'Rosa');
    await tester.tap(find.byKey(const Key('owner-mode-personal')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('owner-confirm')));
    await tester.tap(find.byKey(const Key('owner-confirm')));
    await waitFor(tester, find.textContaining('Usa inventario propio'));

    expect(
      await tester.runAsync(() => OperationModeStore(database).current()),
      OperationMode.personal,
    );
    expect(c.read(operationModeProvider), OperationMode.personal);
    expect(find.textContaining('Usa inventario propio'), findsOneWidget);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    expect(find.text('Transferencias'), findsNothing);
    // La modalidad vigente se consulta en Más (piloto X01).
    c.read(routerProvider).go('/mas');
    await settle(tester);
    expect(find.text('Ahora: inventario propio'), findsOneWidget);
    expect(offline.requests, 0);
  });

  testWidgets('consulta posterior: muestra la vigente y qué cambia; el '
      'bloqueo nombra a quién y cómo resolverlo, sin tocar nada', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'bloqueo');
    await tester.runAsync(() => s.household.buy(s.household.relative, 3000));
    final offline = OfflineTransport();
    final c = await pumpModeApp(tester, s.database, transport: offline);
    final before = await tester.runAsync(
      () async => dumpTables(await s.database.database),
    );

    c.read(routerProvider).go('/mas');
    await settle(tester);
    await tester.tap(find.text('Modo de uso'));
    await settle(tester);
    expect(
      find.text('Modalidad actual: inventario compartido'),
      findsOneWidget,
    );
    expect(
      find.text(operationModeExplanation(OperationMode.shared)),
      findsOneWidget,
    );
    expect(
      find.text(operationModeExplanation(OperationMode.personal)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('mode-change')));
    await settle(tester);
    final blocked = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('mode-blocked')),
        matching: find.byType(Text),
      ),
    );
    expect(blocked.data, contains('Existencias de Hermana'));
    expect(blocked.data, contains('transfiéralas al titular'));
    expect(blocked.data, contains('No se borra ni se reasigna nada.'));
    expect(find.byKey(const Key('mode-confirm')), findsNothing);
    expect(
      await tester.runAsync(() async => dumpTables(await s.database.database)),
      before,
    );
    expect(c.read(operationModeProvider), OperationMode.shared);
    expect(offline.requests, 0);
  });

  testWidgets('propio → compartido con historial: confirma, avisa, conserva '
      'cada registro y habilita las transferencias, sin red', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'historial');
    final h = s.household;
    await tester.runAsync(() async {
      await h.buy(h.titular, 5000);
      await h.apply(h.titular, h.titularFarm, 2000);
      await OperationModeStore(s.database)
          .apply(OperationMode.personal, confirmed: true);
    });
    final offline = OfflineTransport();
    final c = await pumpModeApp(tester, s.database, transport: offline);
    final db = await tester.runAsync(() => s.database.database);
    final business = await tester.runAsync(
      () => dumpTables(db!, except: businessOnly),
    );
    final stock = await tester.runAsync(() => stockByPersonProduct(db!));

    c.read(routerProvider).push('/modo');
    await settle(tester);
    expect(find.text('Modalidad actual: inventario propio'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mode-change')));
    await settle(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('mode-consequence'))).data,
      contains('el historial sigue asociado al titular'),
    );
    await tester.tap(find.byKey(const Key('mode-confirm')));
    await settle(tester);

    expect(
      find.textContaining('Ahora usa inventario compartido'),
      findsOneWidget,
    );
    expect(
      find.text('Modalidad actual: inventario compartido'),
      findsOneWidget,
    );
    expect(c.read(operationModeProvider), OperationMode.shared);
    expect(
      await tester.runAsync(() => dumpTables(db!, except: businessOnly)),
      business,
    );
    expect(await tester.runAsync(() => stockByPersonProduct(db!)), stock);
    expect(
      (await tester.runAsync(
        () => settings(db!),
      ))![AppDatabase.operationModeKey],
      'SHARED',
    );
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    expect(find.text('Transferencias'), findsOneWidget);
    expect(offline.requests, 0);
  });
}
