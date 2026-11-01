// F04-AV (MOB #168–#171): interfaz de los avisos sobre la app completa
// (arnés de F04, base en archivo, repositorio real, sin red).
//
// - Compra con número de lote y vencimiento opcionales.
// - Detalle de compra: corregir vencimiento y lote sin tocar cantidades.
// - Detalle del producto: nivel mínimo y plazo, visibles y configurables.
// - Inventario → «Avisos de inventario»: vencido, próximo, existencia baja
//   por responsable y total, sin fecha; tocar un aviso abre el producto sin
//   iniciar ninguna operación.
//
// Numeración de la tesis v1.22.1 (RF-42 a RF-44, CU-22), no la de
// docs/15_BUSINESS_RULES.md.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';
import 'support/f04_owner_pin.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Future<List<Row>> rows(WidgetTester tester, db, String table) async =>
      (await tester.runAsync(
        () async => (await db.database).query(table, orderBy: 'id'),
      ))!;

  /// Compra sintética en el día [day] de enero, con o sin datos de lote.
  Future<int> buy(
    AgroRepository repo,
    Household h,
    int person,
    int quantity, {
    String? expiry,
    String? lot,
    int day = 2,
  }) => repo.confirmPurchase(
    PurchaseDraft(
      supplierId: h.supplier,
      campaignId: h.campaign,
      purchaseDate: DateTime.utc(2026, 1, day, 12),
      items: [
        PurchaseItemDraft(
          productId: h.product,
          quantityBase: quantity,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 10000,
          allocations: [
            AllocationDraft(personId: person, quantityBase: quantity),
          ],
          expiryDay: expiry,
          lotNumber: lot,
        ),
      ],
    ),
  );

  testWidgets('compra con número de lote y vencimiento: llegan a cada lote', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'av-compra');
    await tester.runAsync(
      () =>
          OperationModeStore(s.database)
              .apply(OperationMode.personal, confirmed: true),
    );
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, field('Cantidad comprada'));
    await settle(tester);
    for (final (label, name) in [
      ('Proveedor', 'Proveedor'),
      ('Producto', 'Glifosato'),
    ]) {
      final picker = tester.widget<AdaptiveEntityPicker<Row>>(
        find.byWidgetPredicate(
          (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
        ),
      );
      picker.onChanged(
        picker.items.firstWhere((item) => picker.labelOf(item) == name),
      );
      await settle(tester);
    }
    await tester.enterText(field('Cantidad comprada'), '2');
    await tester.enterText(field('Precio BOB/L'), '45');
    await settle(tester);

    // Plegado y opcional: sin abrirlo, la compra sería «sin fecha».
    expect(
      find.text('Sin datos: el lote quedará «sin fecha registrada».'),
      findsOneWidget,
    );
    await tapKey(tester, 'purchase-lot-data-0');
    await tester.enterText(
      find.byKey(const Key('purchase-lot-number-0')),
      '  GLI-77 ',
    );
    await tapKey(tester, 'purchase-expiry-0');
    // El selector abre en hoy; se acepta tal cual.
    final dialog = find.byType(DatePickerDialog);
    expect(dialog, findsOneWidget);
    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(TextButton)).last,
    );
    await settle(tester);
    final todayDay = localDay(DateTime.now());
    expect(
      find.text('Vence el ${displayDay(todayDay)} · lote GLI-77'),
      findsWidgets,
    );

    await tapKey(tester, 'purchase-continue');
    expect(find.byKey(const Key('purchase-review-lot-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-paid-no')));
    await settle(tester);
    await tapKey(tester, 'purchase-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    final lots = await rows(tester, s.database, 'inventory_lots');
    expect(lots, hasLength(1));
    expect(lots.single['lot_number'], 'GLI-77');
    expect(lots.single['expiry_date'], todayDay);
  });

  /// PIN del titular vinculado del hogar, como credencial de la app.
  Future<LocalOwnerCredential> titularPin(
    WidgetTester tester,
    ({AppDatabase database, Household household}) s,
  ) async => (await tester.runAsync(() async {
    final binding = (await (await s.database.database).query(
      'owner_bindings',
      where: 'ended_at IS NULL',
    )).single;
    return (await TestOwnerPin.enrolled(
      OwnerBindingContext(
        bindingId: binding['id']! as int,
        personId: binding['person_id']! as int,
        scope: memberA,
      ),
    )).credential;
  }))!;

  testWidgets('detalle de compra: corregir el lote pide motivo y PIN, no '
      'cambia cantidades y queda auditado', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'av-corregir');
    late int purchaseId;
    await tester.runAsync(() async {
      purchaseId = await buy(
        AgroRepository(s.database),
        s.household,
        s.household.titular,
        5000,
      );
    });
    final movementsBefore = await rows(
      tester,
      s.database,
      'inventory_movements',
    );
    final credential = await titularPin(tester, s);
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: [
        localOwnerCredentialProvider.overrideWithValue(credential),
      ],
    );
    c.read(routerProvider).push('/compras/detalle/$purchaseId');
    Finder rich(String text) => find.textContaining(text, findRichText: true);
    await waitFor(tester, rich('Vencimiento: sin fecha registrada'));
    expect(rich('Vencimiento: sin fecha registrada'), findsOneWidget);
    expect(rich('Número de lote: sin registrar'), findsOneWidget);

    final itemId = (await rows(
      tester,
      s.database,
      'purchase_items',
    )).single['id'];
    await tapKey(tester, 'purchase-lot-data-correct-$itemId');
    // Sin cambios no se puede seguir: no se pide motivo ni PIN para nada.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('lot-data-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('lot-data-number')), 'L-9');
    await tester.pump();
    await tapKey(tester, 'lot-data-save');
    // Aprobación del titular: el cambio, el motivo y el PIN.
    expect(
      find.textContaining('Número de lote: sin número → L-9'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('approval-reason')),
      'Leído en el envase',
    );
    await tapKey(tester, 'approval-continue');
    await waitFor(tester, find.byKey(const Key('owner-pin-input')));
    await tester.enterText(find.byKey(const Key('owner-pin-input')), '284917');
    await tapKey(tester, 'owner-pin-submit');
    await waitFor(tester, rich('Número de lote: L-9'));
    expect(rich('Número de lote: L-9'), findsOneWidget);
    expect(
      rich('Correcciones: 1 (las cantidades no cambiaron)'),
      findsOneWidget,
    );

    // El historial muestra el valor anterior, el nuevo y el motivo.
    await tapKey(tester, 'purchase-lot-data-history-$itemId');
    expect(
      find.descendant(
        of: find.byKey(const Key('lot-data-corrections')),
        matching: find.textContaining(
          'vencimiento sin fecha → sin fecha; lote sin número → L-9. '
          'Motivo: Leído en el envase. Autorizó Titular con PIN; 1 lote '
          'cambiado.',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cerrar'));
    await settle(tester);

    expect(
      (await rows(tester, s.database, 'inventory_lots')).single['lot_number'],
      'L-9',
    );
    final corrections = await rows(tester, s.database, 'lot_data_corrections');
    expect(corrections.single['new_lot_number'], 'L-9');
    expect(corrections.single['reason'], 'Leído en el envase');
    expect(corrections.single['actor_method'], 'LOCAL_PIN');
    expect(
      await rows(tester, s.database, 'inventory_movements'),
      movementsBefore,
    );

    // Revertida la compra, se sigue consultando con su historial, pero ya no
    // ofrece corregir.
    await tester.runAsync(
      () =>
          AgroRepository(s.database)
              .reversePurchaseUnauditedForTesting(purchaseId, reason: 'error'),
    );
    c.read(routerProvider).pop();
    await settle(tester);
    c.read(routerProvider).push('/compras/detalle/$purchaseId');
    await waitFor(tester, rich('Número de lote: L-9'));
    expect(find.byKey(Key('purchase-lot-data-correct-$itemId')), findsNothing);
    expect(
      find.byKey(Key('purchase-lot-data-history-$itemId')),
      findsOneWidget,
    );
  });

  testWidgets('detalle del producto: nivel mínimo y plazo visibles y '
      'configurables; vacío es «sin nivel» y «valor inicial»', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'av-config');
    final h = s.household;
    await tester.runAsync(
      () => buy(AgroRepository(s.database), h, h.titular, 5000),
    );
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/inventario/${h.product}');
    await waitFor(tester, find.byKey(const Key('inventory-alert-settings')));
    expect(
      find.text('Sin nivel mínimo: no se avisa cuando queda poco.'),
      findsOneWidget,
    );
    expect(
      find.text('Aviso de vencimiento: 30 días antes (valor inicial).'),
      findsOneWidget,
    );
    final lotsTile = find.byKey(const Key('inventory-lots'));
    await tester.ensureVisible(lotsTile);
    await tester.tap(lotsTile);
    await settle(tester);
    expect(
      find.textContaining('sin fecha de vencimiento registrada'),
      findsOneWidget,
    );

    await tapKey(tester, 'inventory-alert-settings-edit');
    await tester.enterText(
      find.byKey(const Key('alert-settings-minimum')),
      '2,5',
    );
    await tester.enterText(find.byKey(const Key('alert-settings-days')), '400');
    await tapKey(tester, 'alert-settings-save');
    expect(
      find.text('Escriba un número entero de días, de 0 a 365.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('alert-settings-days')), '10');
    await tapKey(tester, 'alert-settings-save');
    await waitFor(tester, find.textContaining('Nivel mínimo: 2,5 L.'));
    expect(find.text('Aviso de vencimiento: 10 días antes.'), findsOneWidget);
    var product = (await rows(
      tester,
      s.database,
      'products',
    )).firstWhere((p) => p['id'] == h.product);
    expect(product['min_stock_base'], 2500);
    expect(product['alert_lead_days'], 10);

    await tapKey(tester, 'inventory-alert-settings-edit');
    await tester.enterText(find.byKey(const Key('alert-settings-minimum')), '');
    await tester.enterText(find.byKey(const Key('alert-settings-days')), '');
    await tapKey(tester, 'alert-settings-save');
    await waitFor(
      tester,
      find.text('Sin nivel mínimo: no se avisa cuando queda poco.'),
    );
    product = (await rows(
      tester,
      s.database,
      'products',
    )).firstWhere((p) => p['id'] == h.product);
    expect(product['min_stock_base'], isNull);
    expect(product['alert_lead_days'], isNull);
  });

  testWidgets('existencia baja: el total en su sección y el cero de un '
      'responsable con el total de la instalación al lado', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'av-bajo');
    final h = s.household;
    await tester.runAsync(() async {
      final repo = AgroRepository(s.database);
      final mancozeb = await repo.addProduct(name: 'Mancozeb', unit: 'KG');
      final atrazina = await repo.addProduct(name: 'Atrazina');
      Future<void> buyOf(int product, int person, int base) =>
          repo.confirmPurchase(
            PurchaseDraft(
              supplierId: h.supplier,
              campaignId: h.campaign,
              purchaseDate: DateTime.utc(2026, 1, 2, 12),
              items: [
                PurchaseItemDraft(
                  productId: product,
                  quantityBase: base,
                  currency: CurrencyCode.bob,
                  originalUnitPriceMinor: 10000,
                  allocations: [
                    AllocationDraft(personId: person, quantityBase: base),
                  ],
                ),
              ],
            ),
          );
      await buyOf(mancozeb, h.titular, 3000);
      await buyOf(mancozeb, h.relative, 1000);
      await repo.confirmApplication(
        ApplicationDraft(
          personId: h.relative,
          farmId: h.relativeFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.utc(2026, 1, 5, 12),
          lines: [
            ApplicationLineDraft(productId: mancozeb, quantityBase: 1000),
          ],
        ),
      );
      await buyOf(atrazina, h.titular, 1000);
      await repo.setProductAlertSettings(
        mancozeb,
        minStockBase: 2000,
        leadDays: null,
      );
      await repo.setProductAlertSettings(
        atrazina,
        minStockBase: 2000,
        leadDays: null,
      );
    });
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/inventario');
    await waitFor(tester, find.textContaining('bajo en el total'));
    expect(
      find.text(
        '1 bajo en el total · 2 bajos por responsable · '
        '2 sin fecha registrada',
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'inventory-alerts-entry');
    await waitFor(tester, find.byKey(const Key('alerts-low')));
    expect(
      find.text('Existencia baja en toda la instalación (1)'),
      findsOneWidget,
    );
    expect(find.text('Atrazina · Total de la instalación'), findsOneWidget);
    expect(
      find.text('Quedan 1 L en toda la instalación; nivel mínimo 2 L'),
      findsOneWidget,
    );
    expect(find.text('Existencia baja por responsable (2)'), findsOneWidget);
    // Cero de Hermana: no es falta de producto en la instalación.
    expect(find.text('Mancozeb · Hermana (responsable)'), findsOneWidget);
    expect(
      find.text(
        'Hermana no tiene existencias propias; nivel mínimo 2 KG. En toda '
        'la instalación: 3 KG',
      ),
      findsOneWidget,
    );
    expect(find.text('Atrazina · Titular (responsable)'), findsOneWidget);
  });

  testWidgets('inventario → avisos: vencido, próximo, existencia baja por '
      'responsable y total, sin fecha; tocar abre el producto sin operar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'av-vista');
    final h = s.household;
    final today = localDay(DateTime.now());
    final yesterday = previousLocalDay(today);
    var in10 = today;
    for (var i = 0; i < 10; i++) {
      in10 = nextLocalDay(in10);
    }
    await tester.runAsync(() async {
      final repo = AgroRepository(s.database);
      await buy(repo, h, h.titular, 3000, expiry: yesterday, lot: 'VIEJO');
      await buy(repo, h, h.titular, 2000, expiry: in10, lot: 'PRONTO', day: 3);
      await buy(repo, h, h.relative, 1000, day: 4);
      await repo.setProductAlertSettings(
        h.product,
        minStockBase: 2000,
        leadDays: null,
      );
    });
    final before = await tester.runAsync(
      () async => dumpTables(await s.database.database),
    );
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/inventario');
    await waitFor(tester, find.byKey(const Key('inventory-alerts-entry')));
    await waitFor(tester, find.textContaining('1 vencido'));
    expect(
      find.text(
        '1 vencido · 1 por vencer · 1 bajo por responsable · '
        '1 sin fecha registrada',
      ),
      findsOneWidget,
    );

    await tapKey(tester, 'inventory-alerts-entry');
    await waitFor(tester, find.byKey(const Key('alerts-expired')));
    expect(find.text('Vencidos (1)'), findsOneWidget);
    expect(find.text('Glifosato · lote VIEJO'), findsOneWidget);
    expect(
      find.text(
        'Venció el ${displayDay(yesterday)}, hace 1 día · Quedan 3 L · Titular',
      ),
      findsOneWidget,
    );
    expect(find.text('Próximos a vencer (1)'), findsOneWidget);
    expect(
      find.text(
        'Vence el ${displayDay(in10)}, en 10 días · Quedan 2 L · Titular · '
        'Aviso: 30 días antes (valor inicial)',
      ),
      findsOneWidget,
    );
    // Total 6 L > 2 L: sin aviso; Hermana 1 L ≤ 2 L: aviso; Titular 5 L no.
    // Total y responsables van en secciones distintas.
    expect(find.byKey(const Key('alerts-low')), findsNothing);
    expect(find.text('Existencia baja por responsable (1)'), findsOneWidget);
    expect(find.text('Glifosato · Hermana (responsable)'), findsOneWidget);
    expect(
      find.text(
        'Hermana tiene 1 L; nivel mínimo 2 L. En toda la instalación: 6 L',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Sin fecha de vencimiento registrada (1)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Glifosato · sin número de lote'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('alerts-clock-warning')), findsNothing);
    // El plazo inicial se explica y se dice dónde cambiarlo.
    expect(
      find.textContaining('El plazo inicial es de 30 días; puede cambiarlo'),
      findsOneWidget,
    );

    await tester.tap(find.text('Glifosato · Hermana (responsable)'));
    await waitFor(tester, find.byKey(const Key('inventory-alert-settings')));
    expect(find.byKey(const Key('inventory-alert-settings')), findsOneWidget);
    // Consultar y navegar no escribió nada.
    expect(
      await tester.runAsync(() async => dumpTables(await s.database.database)),
      before,
    );
  });
}
