// REC-014 (#50): reversiones auditables (conciliación del 2026-10-19, §3.1).
// Cubre la doble reversión de una aplicación, el cargo original conservado con
// su `CREDIT_ADJUSTMENT` y su `reversal_of_id`, la compra consumida que no se
// revierte ni cambia nada, el motivo persistido y la confirmación al revertir
// compras y transferencias desde sus pantallas.
//
// No cubre al responsable de la reversión: la aplicación no lo registra y
// Roderich Rendón lo aceptó como límite académico (2026-10-19). La reversión
// de compras y de transferencias, y su doble intento, ya las cubren
// `f04_bug_02_reverse_purchase_after_transfer_test.dart` y
// `f04_bug_01_reverse_transfer_test.dart`; la confirmación al revertir una
// aplicación, `destructive_actions_test.dart`.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/purchases_screen.dart';
import 'package:agroquimicos/presentation/screens/transfers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late int ana, beto, tercero, supplier, campaign, farm, glifosato;

  /// Ana (cobro por uso), Beto (familiar) y un tercero (cobro al asignar).
  Future<void> people() async {
    repo = AgroRepository(database);
    db = await database.database;
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    beto = await repo.addPerson(name: 'Beto', role: PersonRole.family);
    tercero = await repo.addPerson(
      name: 'Tercero',
      role: PersonRole.thirdParty,
    );
    supplier = await repo.addSupplier(name: 'Agro Sur');
    campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato');
    farm = await repo.addFarm(ownerId: ana, name: 'Chaco Ana', areaM2: 10000);
  }

  Future<int> buy(Map<int, int> owners, int price, DateTime date) =>
      repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: date,
          invoiceNumber: 'F-${date.day}',
          items: [
            PurchaseItemDraft(
              productId: glifosato,
              quantityBase: owners.values.fold(0, (s, q) => s + q),
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: price,
              allocations: [
                for (final MapEntry(key: p, value: q) in owners.entries)
                  AllocationDraft(personId: p, quantityBase: q),
              ],
            ),
          ],
        ),
      );

  Matcher rejected(String message) => throwsA(
    isA<BusinessRuleException>().having((e) => e.message, 'message', message),
  );

  Future<List<Map<String, Object?>>> rows(
    String table, {
    String? where,
    List<Object?>? args,
  }) => db.query(table, where: where, whereArgs: args, orderBy: 'id');

  group('repositorio', () {
    late int purchase, application;

    /// 20 L a Bs 100,00: 15 L para Ana y 5 L para el tercero (cargo de
    /// Bs 500,00). Ana aplica 5 L (cargo por uso de Bs 500,00).
    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      await people();
      purchase = await buy(
        {ana: 15000, tercero: 5000},
        10000,
        DateTime.utc(2026, 1, 5),
      );
      application = await repo.confirmApplication(
        ApplicationDraft(
          personId: ana,
          farmId: farm,
          campaignId: campaign,
          appliedAt: DateTime.utc(2026, 1, 20),
          lines: [
            ApplicationLineDraft(productId: glifosato, quantityBase: 5000),
          ],
        ),
      );
    });

    test('revertir una aplicación conserva el cargo, lo compensa con un '
        'CREDIT_ADJUSTMENT vinculado y guarda el motivo', () async {
      final usage = await rows(
        'account_transactions',
        where: "type='USAGE_CHARGE'",
      );
      expect(usage, hasLength(1));
      final charge = usage.single;
      expect(charge['amount_bob_minor_signed'], 50000);
      final applicationBefore = (await rows(
        'applications',
        where: 'id=?',
        args: [application],
      )).single;
      final itemsBefore = await rows('application_items');
      final consumptionsBefore = await rows('application_consumptions');

      await repo.reverseApplicationUnauditedForTesting(
        application,
        reason: 'Dosis registrada dos veces',
      );

      // El cargo original sigue, idéntico.
      expect(
        await rows('account_transactions', where: 'id=?', args: [charge['id']]),
        [charge],
      );
      final credits = await db.query(
        'account_transactions',
        columns: [
          'person_id',
          'campaign_id',
          'amount_bob_minor_signed',
          'reference_type',
          'reference_id',
          'notes',
          'reversal_of_id',
        ],
        where: "type='CREDIT_ADJUSTMENT'",
      );
      expect(credits, hasLength(1));
      expect(credits.single, {
        'person_id': ana,
        'campaign_id': campaign,
        'amount_bob_minor_signed': -50000,
        'reference_type': 'APPLICATION_REVERSAL',
        'reference_id': application,
        'notes': 'Dosis registrada dos veces',
        'reversal_of_id': charge['id'],
      });
      final balance = (await db.rawQuery(
        'SELECT SUM(amount_bob_minor_signed) s FROM account_transactions '
        'WHERE person_id=?',
        [ana],
      )).single['s'];
      expect(balance, 0);

      // La aplicación se conserva como REVERSED, con su costo e ítems; sus
      // consumos quedan marcados, no borrados.
      final applicationAfter = (await rows(
        'applications',
        where: 'id=?',
        args: [application],
      )).single;
      expect(applicationAfter['reversed_at'], isNotNull);
      expect(applicationAfter, {
        ...applicationBefore,
        'status': 'REVERSED',
        'reversed_at': applicationAfter['reversed_at'],
      });
      expect(applicationAfter['total_cost_bob_minor'], 50000);
      expect(await rows('application_items'), itemsBefore);
      final consumptionsAfter = await rows('application_consumptions');
      expect(consumptionsBefore.single['reversed_at'], isNull);
      expect(consumptionsAfter.single['reversed_at'], isNotNull);
      expect(consumptionsAfter, [
        for (final c in consumptionsBefore)
          {...c, 'reversed_at': consumptionsAfter.single['reversed_at']},
      ]);

      final restitution = await rows(
        'inventory_movements',
        where: "type='APPLICATION_REVERSAL'",
      );
      expect(
        restitution.map(
          (m) => (
            m['owner_person_id'],
            m['quantity_signed'],
            m['reference_id'],
            m['notes'],
          ),
        ),
        [(ana, 5000, application, 'Dosis registrada dos veces')],
      );
      expect((await stockByPersonProduct(db))[(ana, glifosato)], 15000);
    });

    test('una aplicación ya revertida no se revierte otra vez', () async {
      await repo.reverseApplicationUnauditedForTesting(
        application,
        reason: 'Error',
      );
      final after = await dumpTables(db);

      await expectLater(
        repo.reverseApplicationUnauditedForTesting(
          application,
          reason: 'Otra vez',
        ),
        rejected('La aplicación ya fue revertida o no existe.'),
      );
      expect(await dumpTables(db), after);
      // Una sola restitución: 15 L, no 20 L.
      expect((await stockByPersonProduct(db))[(ana, glifosato)], 15000);
      expect(
        after['account_transactions']!.where(
          (t) => t['type'] == 'CREDIT_ADJUSTMENT',
        ),
        hasLength(1),
      );
    });

    test(
      'una compra con lotes consumidos no se revierte y no cambia nada',
      () async {
        final before = await dumpTables(db);
        await expectLater(
          repo.reversePurchaseUnauditedForTesting(purchase, reason: 'Error'),
          rejected(
            'La compra tiene lotes consumidos. Revierta primero las aplicaciones relacionadas.',
          ),
        );
        expect(await dumpTables(db), before);
        expect(
          (await rows(
            'purchases',
            where: 'id=?',
            args: [purchase],
          )).single['status'],
          'CONFIRMED',
        );
        expect(await stockByPersonProduct(db), {
          (ana, glifosato): 10000,
          (tercero, glifosato): 5000,
        });

        // Revertida la aplicación, la compra sí se revierte.
        await repo.reverseApplicationUnauditedForTesting(application);
        await repo.reversePurchaseUnauditedForTesting(purchase);
        expect(
          (await rows(
            'purchases',
            where: 'id=?',
            args: [purchase],
          )).single['status'],
          'REVERSED',
        );
        expect(await stockByPersonProduct(db), {
          (ana, glifosato): 0,
          (tercero, glifosato): 0,
        });
      },
    );

    test('el motivo queda en los movimientos y créditos de la reversión de una '
        'compra y de una transferencia', () async {
      // Segunda compra: 3 L para el tercero a Bs 90,00 (cargo de Bs 270,00).
      final second = await buy({tercero: 3000}, 9000, DateTime.utc(2026, 1, 6));
      final charge = (await db.rawQuery(
        '''SELECT t.* FROM account_transactions t
        JOIN purchase_allocations a ON t.reference_type='PURCHASE_ALLOCATION'
          AND t.reference_id=a.id
        JOIN purchase_items i ON i.id=a.purchase_item_id WHERE i.purchase_id=?''',
        [second],
      )).single;
      expect(charge['amount_bob_minor_signed'], 27000);

      await repo.reversePurchaseUnauditedForTesting(
        second,
        reason: 'Factura duplicada',
      );
      expect(
        (await rows(
          'inventory_movements',
          where: "type='PURCHASE_REVERSAL'",
        )).map((m) => (m['owner_person_id'], m['quantity_signed'], m['notes'])),
        [(tercero, -3000, 'Factura duplicada')],
      );
      final credit = (await rows(
        'account_transactions',
        where: "type='CREDIT_ADJUSTMENT'",
      )).single;
      expect(credit['reversal_of_id'], charge['id']);
      expect(credit['amount_bob_minor_signed'], -27000);
      expect(credit['notes'], 'Factura duplicada');

      final transfer = await repo.transferProductFifo(
        fromPersonId: ana,
        toPersonId: beto,
        productId: glifosato,
        quantityBase: 2000,
      );
      await repo.reverseTransferUnauditedForTesting(
        transfer,
        reason: 'Destino equivocado',
      );
      expect(
        (await rows(
          'inventory_movements',
          where: "type LIKE 'TRANSFER_REVERSAL_%'",
        )).map(
          (m) => (
            m['type'],
            m['owner_person_id'],
            m['quantity_signed'],
            m['notes'],
          ),
        ),
        [
          ('TRANSFER_REVERSAL_IN', ana, 2000, 'Destino equivocado'),
          ('TRANSFER_REVERSAL_OUT', beto, -2000, 'Destino equivocado'),
        ],
      );
    });
  });

  group('confirmación en pantalla', () {
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

    // RF-13: the titular is bound and has a PIN; the screens ask for the reason
    // and the PIN (docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md §1.1).
    late LocalOwnerCredential credential;
    Future<void> enrolTitular() async {
      final bound = await seedActivatedInstallation(database);
      final binding = OwnerBindingContext(
        bindingId: bound.id,
        personId: bound.personId,
        scope: memberA,
      );
      credential = (await TestOwnerPin.enrolled(binding)).credential;
      // El repositorio de las pantallas acepta sólo autorizaciones con el PIN
      // configurado en la instalación.
      repo = AgroRepository(database, ownerCredential: () => credential);
    }

    Future<void> approve(WidgetTester tester, String reason) async {
      await tester.enterText(find.byKey(const Key('approval-reason')), reason);
      await tester.tap(find.byKey(const Key('approval-continue')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('owner-pin-input')),
        '284917',
      );
      await tester.tap(find.byKey(const Key('owner-pin-submit')));
      await settle(tester, frames: 30);
    }

    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            localOwnerCredentialProvider.overrideWithValue(credential),
          ],
          child: MaterialApp(home: Scaffold(body: screen)),
        ),
      );
      await settle(tester);
    }

    /// Texto del detalle dentro del diálogo, no en la lista de fondo.
    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.textContaining(text),
    );

    Future<String?> status(WidgetTester tester, String table, int id) async =>
        (await tester.runAsync(
              () => db.query(table, where: 'id=?', whereArgs: [id]),
            ))!.single['status']
            as String?;

    testWidgets('revertir una compra pide confirmación; cancelar no cambia '
        'nada y confirmar la revierte', (tester) async {
      late int purchase;
      await tester.runAsync(() async {
        database = AppDatabase(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        await people();
        await enrolTitular();
        purchase = await buy(
          {ana: 6000, tercero: 4000},
          10000,
          DateTime.utc(2026, 1, 5),
        );
      });
      addTearDown(database.close);
      await pump(tester, const PurchasesScreen());

      Future<void> askToReverse() async {
        await tester.tap(find.byType(PopupMenuButton<String>));
        await settle(tester);
        await tester.tap(find.text('Revertir compra'));
        await settle(tester);
      }

      final before = (await tester.runAsync(() => dumpTables(db)))!;
      await askToReverse();
      expect(find.text('¿Revertir esta compra?'), findsOneWidget);
      expect(inDialog('Agro Sur · F-5'), findsOneWidget);
      expect(inDialog('Total 1.000,00'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(find.text('¿Revertir esta compra?'), findsNothing);
      expect(await tester.runAsync(() => dumpTables(db)), before);
      expect(await status(tester, 'purchases', purchase), 'CONFIRMED');

      await askToReverse();
      await approve(tester, 'Factura duplicada');
      expect(await status(tester, 'purchases', purchase), 'REVERSED');
      final stock = (await tester.runAsync(() => stockByPersonProduct(db)))!;
      expect(stock[(ana, glifosato)], 0);
      expect(stock[(tercero, glifosato)], 0);
      // RF-13: el motivo que escribe el titular queda en los movimientos y en
      // la auditoría, con el actor de la autorización.
      final notes = (await tester.runAsync(
        () => db.query(
          'inventory_movements',
          columns: ['notes'],
          where: "type='PURCHASE_REVERSAL'",
        ),
      ))!.map((m) => m['notes']).toSet();
      expect(notes, {'Factura duplicada'});
      final audit = (await tester.runAsync(() => db.query('reversal_audit')))!;
      expect(audit.single['reason'], 'Factura duplicada');
      expect(audit.single['actor_method'], 'LOCAL_PIN');
    });

    testWidgets('revertir una transferencia pide confirmación; cancelar no '
        'cambia nada y confirmar la revierte', (tester) async {
      late int transfer;
      await tester.runAsync(() async {
        database = AppDatabase(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        await people();
        await enrolTitular();
        await buy({ana: 10000}, 10000, DateTime.utc(2026, 1, 5));
        transfer = await repo.transferProductFifo(
          fromPersonId: ana,
          toPersonId: beto,
          productId: glifosato,
          quantityBase: 3000,
        );
      });
      addTearDown(database.close);
      await pump(tester, const TransfersScreen());

      final before = (await tester.runAsync(() => dumpTables(db)))!;
      await tester.tap(find.byIcon(Icons.undo));
      await settle(tester);
      expect(find.text('¿Revertir esta transferencia?'), findsOneWidget);
      expect(inDialog('Ana → Beto'), findsOneWidget);
      expect(inDialog('Costo 300,00'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(find.text('¿Revertir esta transferencia?'), findsNothing);
      expect(await tester.runAsync(() => dumpTables(db)), before);
      expect(await status(tester, 'transfers', transfer), 'CONFIRMED');

      await tester.tap(find.byIcon(Icons.undo));
      await settle(tester);
      await approve(tester, 'Transferencia equivocada');
      expect(await status(tester, 'transfers', transfer), 'REVERSED');
      final stock = (await tester.runAsync(() => stockByPersonProduct(db)))!;
      expect(stock[(ana, glifosato)], 10000);
      expect(stock[(beto, glifosato)], 0);
    });
  });
}
