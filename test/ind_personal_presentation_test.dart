import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/screens/applications_screen.dart';
import 'package:agroquimicos/presentation/screens/catalogs_screen.dart';
import 'package:agroquimicos/presentation/screens/farm_logbook_screen.dart';
import 'package:agroquimicos/presentation/screens/inventory_alerts_screen.dart';
import 'package:agroquimicos/presentation/screens/planning_screen.dart';
import 'package:agroquimicos/presentation/screens/purchase_detail_screen.dart';
import 'package:agroquimicos/presentation/screens/reports_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/services/reports/report_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  Future<void> pumpPersonalScreen(
    WidgetTester tester, {
    required AgroRepository repo,
    required Widget child,
    List<dynamic> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          activatedInstallationForTests(),
          ...extraOverrides,
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await settle(tester);
  }

  group('modo individual: lenguaje y omisión del titular en vistas', () {
    testWidgets(
      'detalle de compra propia omite "Para <titular>", "se cobra al aplicar" y "pagó <titular>", pero conserva terceros históricos',
      (tester) async {
        final s = await activatedHousehold(tester, 'ind_pres_purchase_detail');
        final h = s.household;
        final ownPurchaseId = await tester.runAsync(() async {
          final id = await h.repo.confirmPurchase(
            PurchaseDraft(
              supplierId: h.supplier,
              campaignId: h.campaign,
              purchaseDate: DateTime.utc(2026, 2, 10, 12),
              items: [
                PurchaseItemDraft(
                  productId: h.product,
                  quantityBase: 6000,
                  currency: CurrencyCode.bob,
                  originalUnitPriceMinor: 4000,
                  allocations: [
                    AllocationDraft(personId: h.titular, quantityBase: 6000),
                  ],
                ),
              ],
            ),
          );
          await h.repo.addProviderPayment(
            purchaseId: id,
            payerPersonId: h.titular,
            amountBobMinor: 24000,
            method: PaymentMethod.cash,
            date: DateTime.utc(2026, 2, 10, 12),
          );
          return id;
        });

        final sharedPurchaseId = await tester.runAsync(() async {
          final id = await h.repo.confirmPurchase(
            PurchaseDraft(
              supplierId: h.supplier,
              campaignId: h.campaign,
              purchaseDate: DateTime.utc(2026, 2, 11, 12),
              items: [
                PurchaseItemDraft(
                  productId: h.product,
                  quantityBase: 4000,
                  currency: CurrencyCode.bob,
                  originalUnitPriceMinor: 4000,
                  allocations: [
                    AllocationDraft(personId: h.titular, quantityBase: 3000),
                    AllocationDraft(personId: h.relative, quantityBase: 1000),
                  ],
                ),
              ],
            ),
          );
          // La hermana consume todo su saldo/stock antes de cambiar a individual.
          await h.repo.confirmApplication(
            ApplicationDraft(
              farmId: h.relativeFarm,
              personId: h.relative,
              campaignId: h.campaign,
              appliedAt: DateTime.utc(2026, 2, 12, 12),
              lines: [
                ApplicationLineDraft(productId: h.product, quantityBase: 1000),
              ],
            ),
          );
          await h.repo.addAccountPayment(
            personId: h.relative,
            campaignId: h.campaign,
            amountBobMinor: 4000,
          );
          return id;
        });

        await tester.runAsync(
          () =>
              OperationModeStore(s.database)
                  .apply(OperationMode.personal, confirmed: true),
        );

        await pumpPersonalScreen(
          tester,
          repo: h.repo,
          child: PurchaseDetailScreen(purchaseId: ownPurchaseId!),
        );
        await waitFor(tester, find.text('Pagos al proveedor'));

        expect(find.textContaining('Para Titular'), findsNothing);
        expect(find.textContaining('se cobra al aplicar'), findsNothing);
        expect(find.textContaining('pagó Titular'), findsNothing);
        expect(
          find.text('10/02/2026 · Efectivo · ${formatBob(24000).trim()}'),
          findsOneWidget,
        );

        await pumpPersonalScreen(
          tester,
          repo: h.repo,
          child: PurchaseDetailScreen(purchaseId: sharedPurchaseId!),
        );
        await waitFor(tester, find.text('Pagos al proveedor'));
        expect(find.textContaining('Para Hermana'), findsOneWidget);
      },
    );

    testWidgets(
      'aplicaciones: omite al titular en filas y reversión, ajusta buscador y conserva terceros históricos',
      (tester) async {
        final s = await activatedHousehold(tester, 'ind_pres_apps');
        final h = s.household;
        await tester.runAsync(() async {
          await h.buy(h.titular, 5000);
          await h.buy(h.relative, 5000);
          await h.repo.confirmApplication(
            ApplicationDraft(
              farmId: h.titularFarm,
              personId: h.titular,
              campaignId: h.campaign,
              appliedAt: DateTime.utc(2026, 3, 1, 12),
              lines: [
                ApplicationLineDraft(productId: h.product, quantityBase: 2000),
              ],
            ),
          );
          await h.repo.confirmApplication(
            ApplicationDraft(
              farmId: h.relativeFarm,
              personId: h.relative,
              campaignId: h.campaign,
              appliedAt: DateTime.utc(2026, 3, 2, 12),
              lines: [
                ApplicationLineDraft(productId: h.product, quantityBase: 5000),
              ],
            ),
          );
          await h.repo.addAccountPayment(
            personId: h.relative,
            campaignId: h.campaign,
            amountBobMinor: 50000,
          );
          await OperationModeStore(s.database)
              .apply(OperationMode.personal, confirmed: true);
        });

        await pumpPersonalScreen(
          tester,
          repo: h.repo,
          child: const ApplicationsScreen(),
        );
        await waitFor(tester, find.text('Chaco titular'));

        expect(find.text('Chaco titular'), findsOneWidget);
        expect(find.text('Titular · Chaco titular'), findsNothing);
        expect(find.text('Hermana · Chaco hermana'), findsOneWidget);
        expect(find.text('Buscar chaco o producto'), findsOneWidget);
        expect(find.text('Buscar persona o chaco'), findsNothing);

        final ownRow = find.ancestor(
          of: find.text('Chaco titular'),
          matching: find.byType(Padding),
        );
        await tester.tap(
          find.descendant(
            of: ownRow.first,
            matching: find.widgetWithText(TextButton, 'Revertir'),
          ),
        );
        await settle(tester);
        expect(find.byKey(const Key('approval-effects')), findsOneWidget);
        final effects = tester
            .widget<Text>(find.byKey(const Key('approval-effects')))
            .data!;
        expect(effects, isNot(contains('Titular')));
        expect(effects, isNot(contains('cargo correspondiente')));
        expect(effects, isNot(contains('responsable')));
        expect(effects, contains('se restará de los costos del chaco'));
      },
    );

    testWidgets(
      'planificación: omite al titular en sus planes y conserva otros dueños históricos',
      (tester) async {
        final s = await activatedHousehold(tester, 'ind_pres_plans');
        final h = s.household;
        await tester.runAsync(() async {
          await h.buy(h.relative, 5000);
          await h.repo.addPlanMulti(
            farmId: h.titularFarm,
            campaignId: h.campaign,
            areaM2: 10000,
            items: [PlanItemDraft(productId: h.product, doseBasePerHa: 1000)],
          );
          final relativePlanId = await h.repo.addPlanMulti(
            farmId: h.relativeFarm,
            campaignId: h.campaign,
            areaM2: 5000,
            items: [PlanItemDraft(productId: h.product, doseBasePerHa: 10000)],
          );
          await h.repo.confirmApplication(
            ApplicationDraft(
              farmId: h.relativeFarm,
              personId: h.relative,
              campaignId: h.campaign,
              planId: relativePlanId,
              appliedAt: DateTime.utc(2026, 3, 2, 12),
              lines: [
                ApplicationLineDraft(productId: h.product, quantityBase: 5000),
              ],
            ),
          );
          await h.repo.addAccountPayment(
            personId: h.relative,
            campaignId: h.campaign,
            amountBobMinor: 50000,
          );
          await OperationModeStore(s.database)
              .apply(OperationMode.personal, confirmed: true);
        });

        await pumpPersonalScreen(
          tester,
          repo: h.repo,
          child: const PlanningScreen(),
        );
        await waitFor(tester, find.text('Chaco titular'));

        expect(find.text('Chaco titular'), findsOneWidget);
        expect(find.text('Chaco titular · Titular'), findsNothing);

        await tester.tap(find.text('Mostrar planes aplicados'));
        await settle(tester);
        await waitFor(tester, find.text('Chaco hermana · Hermana'));
        expect(find.text('Chaco hermana · Hermana'), findsOneWidget);
      },
    );

    testWidgets(
      'reportes: oculta Estado de cuenta y ajusta subtítulo y aviso sensible',
      (tester) async {
        final s = await activatedHousehold(tester, 'ind_pres_reports');
        await tester.runAsync(
          () =>
              OperationModeStore(s.database)
                  .apply(OperationMode.personal, confirmed: true),
        );

        await pumpPersonalScreen(
          tester,
          repo: s.household.repo,
          child: const ReportsScreen(),
          extraOverrides: [
            reportStorageProvider.overrideWithValue(
              LocalReportStorage(directory: () async => Directory.systemTemp),
            ),
          ],
        );
        await waitFor(tester, find.text('Exportar PDF'));

        expect(
          find.text('Exporta inventario y costos a Excel o PDF.'),
          findsOneWidget,
        );
        expect(find.text('Estado de cuenta'), findsNothing);
        expect(find.text('Persona (obligatoria)'), findsNothing);

        final exportBtn = find.widgetWithText(FilledButton, 'Exportar PDF');
        await tester.ensureVisible(exportBtn);
        await tester.tap(exportBtn);
        await settle(tester);

        expect(
          find.textContaining('sensible: precios, costos y pagos.'),
          findsOneWidget,
        );
        expect(find.textContaining('nombres de personas'), findsNothing);
      },
    );

    testWidgets(
      'bitácora completa del chaco omite al titular en cabecera y filas',
      (tester) async {
        final s = await activatedHousehold(tester, 'ind_pres_logbook');
        final h = s.household;
        await tester.runAsync(() async {
          await h.buy(h.titular, 5000);
          await h.repo.confirmApplication(
            ApplicationDraft(
              farmId: h.titularFarm,
              personId: h.titular,
              campaignId: h.campaign,
              appliedAt: DateTime.utc(2026, 4, 1, 12),
              lines: [
                ApplicationLineDraft(productId: h.product, quantityBase: 2000),
              ],
            ),
          );
          await OperationModeStore(s.database)
              .apply(OperationMode.personal, confirmed: true);
        });

        await pumpPersonalScreen(
          tester,
          repo: h.repo,
          child: FarmLogbookScreen(farmId: h.titularFarm, logbook: true),
        );
        await waitFor(tester, find.byType(ExpansionTile));

        expect(
          find.text('Bitácora · ${formatHectares(10000)}'),
          findsOneWidget,
        );
        expect(find.textContaining('Bitácora · Titular'), findsNothing);
        expect(find.text('01/04/2026 · Campaña 1'), findsOneWidget);
        expect(
          find.textContaining('01/04/2026 · Campaña 1 · Titular'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'datos/catálogos: el titular muestra "Titular" y sus chacos omiten su nombre',
      (tester) async {
        final s = await activatedHousehold(tester, 'ind_pres_catalogs');
        await tester.runAsync(
          () =>
              OperationModeStore(s.database)
                  .apply(OperationMode.personal, confirmed: true),
        );

        await pumpPersonalScreen(
          tester,
          repo: s.household.repo,
          child: const CatalogsScreen(),
        );
        await waitFor(tester, find.text('Hermana'));

        expect(find.text('Titular'), findsNWidgets(2));
        expect(find.text('Administrador · Cobro por consumo'), findsNothing);
        expect(find.text('Familiar · Cobro por consumo'), findsOneWidget);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Chacos'));
        await settle(tester);
        expect(find.text('Chaco titular'), findsOneWidget);
        expect(find.text('Titular · ${formatHectares(10000)}'), findsNothing);
        expect(find.text(formatHectares(10000)), findsOneWidget);
        expect(find.text('Hermana · ${formatHectares(5000)}'), findsOneWidget);
      },
    );

    testWidgets(
      'ayuda de avisos y explicación de costo en aplicación usan lenguaje individual',
      (tester) async {
        final s = await activatedHousehold(tester, 'ind_pres_alerts_cost');
        final h = s.household;
        await tester.runAsync(() async {
          await h.buy(h.titular, 5000);
          await OperationModeStore(s.database)
              .apply(OperationMode.personal, confirmed: true);
        });

        await pumpPersonalScreen(
          tester,
          repo: h.repo,
          child: const InventoryAlertsScreen(),
        );
        await waitFor(tester, find.byKey(const Key('alerts-info')));
        await tester.tap(find.byKey(const Key('alerts-info')));
        await settle(tester);
        expect(
          find.text(
            'Lo que queda en el almacén es igual o menor al nivel mínimo.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('en otras manos'), findsNothing);

        final c = await pumpModeApp(tester, s.database);
        c.read(routerProvider).push('/aplicaciones/nueva');
        await waitFor(tester, find.byKey(const Key('application-continue')));
        await settle(tester);
        final farmPicker = tester
            .widget<AdaptiveEntityPicker<Map<String, Object?>>>(
              find.byWidgetPredicate(
                (w) =>
                    w is AdaptiveEntityPicker<Map<String, Object?>> &&
                    w.label == 'Chaco',
              ),
            );
        farmPicker.onChanged(farmPicker.items.first);
        await settle(tester);
        await tester.tap(find.byKey(const Key('application-continue')));
        await settle(tester);

        await tester.tap(find.byKey(const Key('application-add-product')));
        await settle(tester);
        final productPicker = tester
            .widget<AdaptiveEntityPicker<Map<String, Object?>>>(
              find.byWidgetPredicate(
                (w) =>
                    w is AdaptiveEntityPicker<Map<String, Object?>> &&
                    w.label == 'Producto',
              ),
            );
        productPicker.onChanged(productPicker.items.first);
        await settle(tester);
        await tester.enterText(
          find.byKey(const Key('application-line-quantity')),
          '2',
        );
        await settle(tester);
        await tester.tap(find.byKey(const Key('application-line-add')));
        await settle(tester);

        await tester.tap(find.byKey(const Key('application-continue')));
        await settle(tester);
        await waitFor(tester, find.byKey(const Key('application-cost-help')));
        await tester.tap(find.byKey(const Key('application-cost-help')));
        await settle(tester);
        final helpText = tester
            .widget<Text>(find.byKey(const Key('application-cost-help-text')))
            .data!;
        expect(helpText, contains('precio de sus compras'));
        expect(helpText, isNot(contains('de el titular')));
      },
    );
  });
}
