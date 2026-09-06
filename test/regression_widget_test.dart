import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/plan_form_screen.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/presentation/screens/settlements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(AppDatabase, AgroRepository)> fixture() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repo = AgroRepository(database);
    final family = await repo.addPerson(name: 'José', role: PersonRole.family);
    await repo.addPerson(name: 'Administrador', role: PersonRole.admin);
    await repo.addFarm(ownerId: family, name: 'JoseLimoncito', areaM2: 800000);
    await repo.addCampaign(
      name: 'Invierno 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    await repo.addProduct(name: 'Glifosato');
    await repo.addSupplier(name: 'Chicho');
    return (database, repo);
  }

  testWidgets('seleccionar chaco precarga 80 ha y el área sigue editable', (
    tester,
  ) async {
    // Regression path: open form, select farm, verify the controller update.
    final (database, repo) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: PlanFormScreen()),
      ),
    );
    await settle(tester);
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pump();
    final areaField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Área planificada (ha)',
    );
    expect(areaField, findsOneWidget);
    final field = tester.widget<TextField>(areaField);
    expect(field.controller!.text, '80');
    await tester.enterText(areaField, '28');
    expect(field.controller!.text, '28');
  });

  testWidgets('editar y vaciar cantidad de compra no lanza FormatException', (
    tester,
  ) async {
    final (database, repo) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: PurchaseFormScreen()),
      ),
    );
    await settle(tester);
    // La cantidad de la línea es "Cantidad comprada"; las de las asignaciones
    // son "Cantidad" (UIBUG-038). Se apunta a la de la línea.
    final quantity = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Cantidad comprada',
    );
    expect(quantity, findsOneWidget);
    await tester.enterText(quantity, '420');
    await tester.pump();
    await tester.enterText(quantity, '');
    await tester.pump();
    await tester.enterText(quantity, '56,5');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('ningún refresh devuelve Future desde setState', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final unsafe = RegExp(
      r'setState\s*\(\s*\(\s*\)\s*=>\s*\w+\s*=\s*[^;]*(?:_load\(|repositoryProvider)',
    );
    for (final file in files) {
      expect(
        unsafe.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
  });

  testWidgets(
    'estado de cuenta abre y cierra 20 veces sin perder la pantalla',
    (tester) async {
      final repo = _SettlementFakeRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: Scaffold(body: SettlementsScreen())),
        ),
      );
      await settle(tester);

      // El menú de cada persona vive dentro de una Card; el de copias de
      // seguridad está en la cabecera de la pantalla, fuera de toda Card. Se
      // localiza por descendencia para no depender de que exista un único
      // PopupMenuButton en la pantalla.
      final personMenu = find.descendant(
        of: find.byType(Card),
        matching: find.byType(PopupMenuButton<String>),
      );
      expect(personMenu, findsOneWidget);
      for (var iteration = 0; iteration < 20; iteration++) {
        await tester.ensureVisible(personMenu.first);
        await tester.tap(personMenu.first);
        await settle(tester);
        await tester.tap(find.text('Ver detalle cronológico'));
        await settle(tester);
        expect(find.textContaining('Estado de cuenta'), findsOneWidget);
        await tester.tap(find.text('Cerrar'));
        await settle(tester);
        expect(find.text('Liquidación y cuentas'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );
}

class _SettlementFakeRepository extends AgroRepository {
  _SettlementFakeRepository()
    : super(
        AppDatabase(factory: databaseFactoryFfi, path: inMemoryDatabasePath),
      );

  @override
  Future<List<Map<String, Object?>>> settlements({int? campaignId}) async => [
    {
      'id': 1,
      'name': 'José',
      'role': 'FAMILY',
      'balance': -10000,
      'charges': 0,
      'payments': 10000,
    },
  ];

  @override
  Future<List<Map<String, Object?>>> farmCostReport({int? campaignId}) async =>
      [];

  @override
  Future<List<Map<String, Object?>>> productCostReport({
    int? campaignId,
  }) async => [];

  @override
  Future<List<Map<String, Object?>>> campaigns() async => [];

  @override
  Future<List<Map<String, Object?>>> detailedStatement(
    int personId, {
    int? campaignId,
  }) async => [
    // La fila reproduce lo que devuelve la consulta real: `t.*` más `concept`
    // y `farm_name`. Antes omitía `campaign_id`, `notes` y `reversal_of_id`,
    // que la consulta sí trae; el mapper tipado de EVO-004 lo detectó.
    {
      'id': 1,
      'person_id': personId,
      'campaign_id': campaignId,
      'transaction_date': '2026-06-01T00:00:00.000Z',
      'type': 'ADVANCE',
      'amount_bob_minor_signed': -10000,
      'reference_type': 'ADVANCE',
      'reference_id': null,
      'notes': null,
      'reversal_of_id': null,
      'concept': 'Adelanto',
      'farm_name': null,
    },
  ];
}
