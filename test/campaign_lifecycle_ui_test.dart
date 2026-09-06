import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/screens/catalogs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// UIBUG-059 en la pantalla: una campaña cerrada se ve como cerrada y no
/// ofrece "Activar". El repositorio la rechaza igualmente
/// (`campaign_lifecycle_test.dart`); esto comprueba que la interfaz tampoco
/// invite a intentarlo.
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

  /// Deja tres campañas, una en cada estado relevante.
  Future<(AppDatabase, AgroRepository)> fixture() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repo = AgroRepository(database);
    final closed = await repo.addCampaign(
      name: 'Campana Vieja',
      start: DateTime.utc(2025, 1, 1),
    );
    await repo.closeCampaign(closed);
    await repo.addCampaign(name: 'Campana Activa', start: DateTime.utc(2026));
    await repo.addCampaign(
      name: 'Campana Planificada',
      start: DateTime.utc(2027),
    );
    return (database, repo);
  }

  Future<void> openCampaigns(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (database, repo) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: CatalogsScreen())),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Campañas'));
    await settle(tester);
  }

  /// Abre el menú ⋮ de la fila cuyo título es [name].
  Future<void> openMenuOf(WidgetTester tester, String name) async {
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
    );
    await settle(tester);
  }

  testWidgets('una campaña cerrada se muestra como cerrada', (tester) async {
    await openCampaigns(tester);
    expect(find.textContaining('Cerrada · '), findsOneWidget);
  });

  testWidgets('el menú de una campaña cerrada NO ofrece Activar', (
    tester,
  ) async {
    await openCampaigns(tester);
    await openMenuOf(tester, 'Campana Vieja');

    expect(find.text('Activar'), findsNothing);
    // Sí conserva lo que sigue teniendo sentido sobre un periodo terminado.
    expect(find.text('Editar'), findsOneWidget);
    // Y no ofrece cerrarla otra vez.
    expect(find.text('Cerrar'), findsNothing);
  });

  testWidgets('una campaña planificada sí ofrece Activar', (tester) async {
    await openCampaigns(tester);
    await openMenuOf(tester, 'Campana Planificada');
    expect(find.text('Activar'), findsOneWidget);
  });

  testWidgets('la campaña activa ofrece Cerrar y no Activar', (tester) async {
    await openCampaigns(tester);
    await openMenuOf(tester, 'Campana Activa');
    expect(find.text('Cerrar'), findsOneWidget);
    expect(find.text('Activar'), findsNothing);
  });

  testWidgets('cerrar avisa de que la acción no se puede deshacer', (
    tester,
  ) async {
    await openCampaigns(tester);
    await openMenuOf(tester, 'Campana Activa');
    await tester.tap(find.text('Cerrar'));
    await settle(tester);

    expect(find.textContaining('¿Cerrar Campana Activa?'), findsOneWidget);
    expect(find.textContaining('NO se puede volver a activar'), findsOneWidget);
    expect(find.text('Cerrar definitivamente'), findsOneWidget);
  });
}
