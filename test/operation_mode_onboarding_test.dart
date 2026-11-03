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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';

/// Diagnóstico de una espera agotada: acceso, modalidad del controlador y ruta.
String _state(ProviderContainer c) =>
    'acceso=${c.read(installationAccessProvider)?.name}, '
    'modalidad=${c.read(operationModeProvider)?.name}, ruta=${currentPath(c)}';

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
    // después de que el arnés deje de ver indicadores de carga. Si no llega,
    // falla con el estado en vez de seguir (waitFor no falla al agotarse).
    await waitUntil(
      tester,
      'la elección del titular',
      () => find.byKey(const Key('owner-mode-help')).evaluate().isNotEmpty,
      state: () => _state(c),
    );
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
    // Estado final del alta, no sólo un texto: vínculo y acceso activado,
    // modalidad propia en el controlador y el aviso en pantalla. Sin esto, la
    // CI de main (run 41566802912) leyó la base antes de que el alta guardara
    // la modalidad y el alta pendiente dejó la base bloqueada en el cierre.
    await waitUntil(
      tester,
      'el alta del titular con inventario propio',
      () =>
          c.read(installationAccessProvider) ==
              InstallationAccessState.activated &&
          c.read(operationModeProvider) == OperationMode.personal &&
          find.textContaining('Usa inventario propio').evaluate().isNotEmpty,
      state: () => _state(c),
    );

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

    // Evaluar, guardar, recargar la modalidad y releerla usan E/S real sin
    // indicador de carga: `settle` no las espera. Se espera a que la pantalla
    // termine cada paso, con límite y diagnóstico.
    final consequence = find.byKey(const Key('mode-consequence'));
    final changeButton = find.byKey(const Key('mode-change'));
    final current = find.byKey(const Key('mode-current'));
    bool changing() =>
        changeButton.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(changeButton).onPressed == null;
    String? currentText() =>
        current.evaluate().isEmpty ? null : tester.widget<Text>(current).data;
    String screenState() {
      final notices = [
        for (final finder in [
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          ),
          find.descendant(
            of: find.byKey(const Key('mode-blocked')),
            matching: find.byType(Text),
          ),
        ])
          for (final element in finder.evaluate())
            (element.widget as Text).data,
      ];
      return 'cambio en curso: ${changing()}; modalidad mostrada: '
          '${currentText()}; avisos: $notices';
    }

    // Los teardown corren en orden inverso: éste, antes de desechar el
    // contenedor del arnés. Si la prueba falla con el guardado a medias
    // («Cambiar…» inactivo), espera (con límite) a que `_change` termine para
    // que no lea un contenedor ya desechado. No espera la relectura final.
    addTearDown(
      () => waitUntil(
        tester,
        'el cambio de modalidad antes de desechar el contenedor',
        () => !changing(),
        state: screenState,
      ),
    );

    final db = await tester.runAsync(() => s.database.database);
    final business = await tester.runAsync(
      () => dumpTables(db!, except: businessOnly),
    );
    final stock = await tester.runAsync(() => stockByPersonProduct(db!));

    c.read(routerProvider).push('/modo');
    await settle(tester);
    expect(find.text('Modalidad actual: inventario propio'), findsOneWidget);

    await tester.tap(changeButton);
    await waitUntil(
      tester,
      'la evaluación del cambio (diálogo de confirmación)',
      () => consequence.evaluate().isNotEmpty,
      state: screenState,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('mode-consequence'))).data,
      contains('el historial sigue asociado al titular'),
    );
    await tester.tap(find.byKey(const Key('mode-confirm')));
    // Terminado: el botón vuelve a estar activo (fin del cambio, bien o mal)
    // y la modalidad mostrada ya no es la de antes (relectura hecha).
    await waitUntil(
      tester,
      'el cambio de modalidad (guardar, recargar y releer)',
      () =>
          !changing() &&
          currentText() != null &&
          currentText() != 'Modalidad actual: inventario propio',
      state: screenState,
    );

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
