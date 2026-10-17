// Criterio 5 de GATE-F04 (#28) en Catálogos: el alta pide el día de inicio y
// el cierre de una campaña abierta pide el día de fin (RN-16; «las fechas
// concretas son configuración»). El repositorio valida; esto comprueba que la
// pantalla pasa la fecha y muestra el período. Pruebas de HOST.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/presentation/screens/catalogs_screen.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  Future<(AgroRepository, int)> open(
    WidgetTester tester, {
    bool withSuccessor = false,
    DateTime? activeStart,
  }) async {
    await tester.binding.setSurfaceSize(const Size(393, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (database, repo, active) = (await tester.runAsync(() async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      final repo = AgroRepository(database);
      final active = await repo.addCampaign(
        name: 'Campana Activa',
        start: activeStart ?? DateTime(2026, 1, 1),
      );
      if (withSuccessor) {
        await repo.addCampaign(
          name: 'Campana Siguiente',
          start: DateTime.now().add(const Duration(days: 30)),
        );
      }
      return (database, repo, active);
    }))!;
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
    return (repo, active);
  }

  Future<Map<String, Object?>> row(
    WidgetTester tester,
    AgroRepository repo,
    String name,
  ) async => (await tester.runAsync(
    () async => (await repo.campaigns()).firstWhere((r) => r['name'] == name),
  ))!;

  Future<void> openMenuOf(WidgetTester tester, String name) async {
    final tile = find.ancestor(
      of: find.text(name),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
    );
    await settle(tester);
  }

  final today = DateTime.now();

  testWidgets('el alta propone hoy como inicio y la anterior termina el día '
      'previo', (tester) async {
    final (repo, _) = await open(tester);
    await tester.tap(find.text('Agregar campaña'));
    await settle(tester);
    expect(find.text('Empieza el'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('campaign-start')),
        matching: find.text(formatDate(today.toIso8601String())),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('campaign-name')), 'Nueva');
    await tester.tap(find.text('Guardar'));
    await settle(tester);

    final created = await row(tester, repo, 'Nueva');
    expect(storedLocalDay(created['start_date']! as String), localDay(today));
    expect(created['status'], 'PLANNED');
    final previous = await row(tester, repo, 'Campana Activa');
    expect(
      storedLocalDay(previous['end_date']! as String),
      previousLocalDay(localDay(today)),
    );
  });

  testWidgets('cerrar una campaña abierta pide el fin (hoy por defecto) y lo '
      'guarda', (tester) async {
    final (repo, _) = await open(tester);
    await openMenuOf(tester, 'Campana Activa');
    await tester.tap(find.text('Cerrar'));
    await settle(tester);
    expect(find.text('Termina el'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('campaign-close-end')),
        matching: find.text(formatDate(today.toIso8601String())),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cerrar definitivamente'));
    await settle(tester);

    final closed = await row(tester, repo, 'Campana Activa');
    expect(closed['status'], 'CLOSED');
    expect(storedLocalDay(closed['end_date']! as String), localDay(today));
  });

  testWidgets('si el alta de la siguiente ya fijó el fin, el cierre lo '
      'muestra y no lo cambia', (tester) async {
    final (repo, _) = await open(tester, withSuccessor: true);
    final before = await row(tester, repo, 'Campana Activa');
    await openMenuOf(tester, 'Campana Activa');
    await tester.tap(find.text('Cerrar'));
    await settle(tester);
    expect(find.text('Termina el'), findsNothing);
    expect(
      find.textContaining('hasta ${formatDate(before['end_date'])}'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cerrar definitivamente'));
    await settle(tester);
    final closed = await row(tester, repo, 'Campana Activa');
    expect(closed['status'], 'CLOSED');
    expect(closed['end_date'], before['end_date']);
  });

  testWidgets('una campaña activa que todavía no empezó se cierra desde el '
      'diálogo: propone como fin su día de inicio', (tester) async {
    final start = DateTime.now().add(const Duration(days: 10));
    final (repo, _) = await open(tester, activeStart: start);
    await openMenuOf(tester, 'Campana Activa');
    await tester.tap(find.text('Cerrar'));
    await settle(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('campaign-close-end')),
        matching: find.text(formatDate(start.toIso8601String())),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cerrar definitivamente'));
    await settle(tester);
    final closed = await row(tester, repo, 'Campana Activa');
    expect(closed['status'], 'CLOSED');
    expect(storedLocalDay(closed['end_date']! as String), localDay(start));
  });
}
