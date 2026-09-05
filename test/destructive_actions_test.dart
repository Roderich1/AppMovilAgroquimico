import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/applications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// STAB-010: revertir ajusta inventario y saldos y no se puede deshacer desde
/// la interfaz. No debe ejecutarse con un solo toque accidental.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;

  Future<void> settle(WidgetTester tester, {int frames = 15}) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Escenario: se compran 20 L y se aplican 5 L, dejando 15 L de stock y un
  /// cargo por consumo de Bs 500,00.
  Future<void> seed() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);
    final family = await repo.addPerson(
      name: 'Familiar',
      role: PersonRole.family,
    );
    final supplier = await repo.addSupplier(name: 'Proveedor');
    final farm = await repo.addFarm(
      ownerId: family,
      name: 'Chaco',
      areaM2: 100000,
    );
    final campaign = await repo.addCampaign(
      name: 'Campaña',
      start: DateTime.utc(2026),
    );
    final product = await repo.addProduct(name: 'Glifosato');
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 10),
        items: [
          PurchaseItemDraft(
            productId: product,
            quantityBase: 20000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [
              AllocationDraft(personId: family, quantityBase: 20000),
            ],
          ),
        ],
      ),
    );
    await repo.confirmApplication(
      ApplicationDraft(
        personId: family,
        farmId: farm,
        campaignId: campaign,
        appliedAt: DateTime.utc(2026, 2),
        lines: [ApplicationLineDraft(productId: product, quantityBase: 5000)],
      ),
    );
  }

  Future<void> pumpApplications(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: ApplicationsScreen())),
      ),
    );
    await settle(tester);
  }

  testWidgets('revertir una aplicación pide confirmación antes de actuar', (
    tester,
  ) async {
    await tester.runAsync(seed);
    addTearDown(database.close);
    await pumpApplications(tester);

    await tester.tap(find.byIcon(Icons.undo));
    await settle(tester);

    expect(
      find.text('¿Revertir esta aplicación?'),
      findsOneWidget,
      reason: 'Un solo toque no debe revertir sin confirmación.',
    );
    // La confirmación debe ser informada, no un trámite: muestra el chaco y el
    // importe afectado. `formatBob` rinde el símbolo como sufijo en es_BO
    // ("500,00 Bs"), por eso se busca solo la parte numérica.
    expect(find.textContaining('Chaco'), findsWidgets);
    expect(find.textContaining('500,00'), findsWidgets);
  });

  testWidgets('cancelar la confirmación NO revierte la aplicación', (
    tester,
  ) async {
    await tester.runAsync(seed);
    addTearDown(database.close);
    await pumpApplications(tester);

    await tester.tap(find.byIcon(Icons.undo));
    await settle(tester);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);

    final applications = (await tester.runAsync(repo.applications))!;
    expect(
      applications.single['status'],
      'CONFIRMED',
      reason: 'Cancelar debe dejar la aplicación intacta.',
    );

    // El stock tampoco debe haberse movido: siguen consumidos 5 L de 20 L.
    final stock = (await tester.runAsync(repo.inventorySummary))!;
    expect(stock.single['available_base'], 15000);
  });

  testWidgets('confirmar sí revierte y devuelve el stock', (tester) async {
    await tester.runAsync(seed);
    addTearDown(database.close);
    await pumpApplications(tester);

    await tester.tap(find.byIcon(Icons.undo));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Revertir'));
    await settle(tester);

    final applications = (await tester.runAsync(repo.applications))!;
    expect(applications.single['status'], 'REVERSED');

    // Los 5 L consumidos vuelven al inventario: 20 000 disponibles.
    final stock = (await tester.runAsync(repo.inventorySummary))!;
    expect(stock.single['available_base'], 20000);
  });
}
