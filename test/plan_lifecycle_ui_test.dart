import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/planning_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// UIBUG-045 en la pantalla: la lista operativa muestra pendientes y un plan
/// consumido no ofrece la acción de aplicar.
///
/// Va en su propio archivo porque el fixture toca SQLite de verdad y hay que
/// construirlo dentro de `tester.runAsync`: hacerlo en un `setUp` compartido
/// con las pruebas de dominio cuelga el proceso, porque el reloj simulado del
/// binding de widgets no deja avanzar la E/S real.
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

  /// Deja el repositorio con un plan pendiente y, si [applyIt], otro ya
  /// consumido por su aplicación.
  Future<(AppDatabase, AgroRepository)> fixture({
    required bool pending,
    required bool applied,
  }) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repo = AgroRepository(database);
    final person = await repo.addPerson(name: 'José', role: PersonRole.family);
    final farm = await repo.addFarm(
      ownerId: person,
      name: 'JoseLimoncito',
      areaM2: 100000,
    );
    final campaign = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    final product = await repo.addProduct(name: 'Glifosato');
    final supplier = await repo.addSupplier(name: 'Proveedor');
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 2, 1),
        items: [
          PurchaseItemDraft(
            productId: product,
            quantityBase: 200000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 1000,
            allocations: [
              AllocationDraft(personId: person, quantityBase: 200000),
            ],
          ),
        ],
      ),
    );

    Future<int> newPlan() => repo.addPlanMulti(
      farmId: farm,
      campaignId: campaign,
      areaM2: 100000,
      items: [PlanItemDraft(productId: product, doseBasePerHa: 1000)],
    );

    if (applied) {
      final plan = await newPlan();
      final prefill = await repo.planForApplication(plan);
      await repo.confirmApplication(
        ApplicationDraft(
          personId: person,
          farmId: farm,
          campaignId: campaign,
          planId: plan,
          appliedAt: DateTime.utc(2026, 3, 1),
          lines: [
            for (final row in prefill)
              ApplicationLineDraft(
                productId: row['product_id'] as int,
                quantityBase: row['required_quantity_base'] as int,
              ),
          ],
        ),
      );
    }
    if (pending) await newPlan();
    return (database, repo);
  }

  Future<void> pumpPlanning(
    WidgetTester tester, {
    required bool pending,
    required bool applied,
  }) async {
    await tester.binding.setSurfaceSize(const Size(393, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (database, repo) = (await tester.runAsync(
      () => fixture(pending: pending, applied: applied),
    ))!;
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: PlanningScreen())),
      ),
    );
    await settle(tester);
  }

  testWidgets('un plan aplicado no aparece en la lista operativa', (
    tester,
  ) async {
    await pumpPlanning(tester, pending: false, applied: true);
    expect(find.text('No hay planes pendientes.'), findsOneWidget);
    expect(find.text('Aplicar este plan'), findsNothing);
  });

  testWidgets('el histórico lo muestra marcado y sin acción de aplicar', (
    tester,
  ) async {
    await pumpPlanning(tester, pending: false, applied: true);

    await tester.tap(find.text('Mostrar planes aplicados'));
    await settle(tester);

    expect(find.text('Aplicado'), findsOneWidget);
    // Conservado para trazabilidad, pero sin ofrecer volver a aplicarlo.
    expect(find.text('Aplicar este plan'), findsNothing);
  });

  testWidgets('un plan pendiente sí ofrece la acción de aplicar', (
    tester,
  ) async {
    await pumpPlanning(tester, pending: true, applied: false);

    await tester.tap(find.byType(ExpansionTile));
    await settle(tester);
    expect(find.text('Aplicar este plan'), findsOneWidget);
  });

  testWidgets('con ambos planes la lista operativa sólo trae el pendiente', (
    tester,
  ) async {
    await pumpPlanning(tester, pending: true, applied: true);

    expect(find.byType(ExpansionTile), findsOneWidget);
    expect(find.text('Aplicado'), findsNothing);

    await tester.tap(find.text('Mostrar planes aplicados'));
    await settle(tester);
    expect(find.byType(ExpansionTile), findsNWidgets(2));
    expect(find.text('Aplicado'), findsOneWidget);
  });
}
