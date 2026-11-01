// F04-AV (MOB #168–#171): avisos de existencias y vencimiento.
//
// Numeración de la tesis v1.22.1 (Cap. III y Apéndice A): RU-22, RN-31,
// RN-32, RF-42 a RF-44, DAT-22, CU-22 y SC-CU22-01 a 05. No son las RN-31 y
// RN-32 de docs/15_BUSINESS_RULES.md (reglas de transferencias).
//
// Datos sintéticos. El reloj se inyecta: ninguna prueba depende del día en
// que se ejecuta.
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/late_operation_codec.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/inventory_alerts.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

class _WorkspacePathProvider extends PathProviderPlatform {
  _WorkspacePathProvider(this.directory);
  final String directory;
  @override
  Future<String?> getDownloadsPath() async => directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

/// Hoy, a mediodía local: el día civil no depende de la zona horaria.
final today = DateTime(2026, 11, 10, 12);

/// Hogar con un segundo producto y compras con o sin vencimiento.
class _Farm {
  _Farm(this.database, this.repo, this.h, this.herbicide, this.pin);
  final AppDatabase database;
  final AgroRepository repo;
  final Household h;
  final int herbicide;

  /// PIN del titular (el familiar «Titular» del hogar), si se pidió.
  final TestOwnerPin? pin;

  Future<OwnerAuthorization> authorize(
    int purchaseItemId, {
    AuthorizationPurpose purpose = AuthorizationPurpose.correctLotData,
  }) => pin!.credential.verify(
    pin: '284917',
    purpose: purpose,
    subjectRef: AgroRepository.lotDataSubjectRef(purchaseItemId),
    binding: pin!.binding,
  );

  /// Corrección autorizada con el PIN del titular.
  Future<LotDataCorrectionResult> correct(
    int purchaseItemId, {
    String? expiry,
    String? lot,
    String reason = 'Leído en el envase',
  }) async => repo.correctLotData(
    purchaseItemId,
    expiryDay: expiry,
    lotNumber: lot,
    reason: reason,
    authorization: await authorize(purchaseItemId),
  );

  /// Compra de [quantity] (unidad base) para [person] el [day] de enero.
  Future<int> buy(
    int person,
    int quantity, {
    int? product,
    String? expiry,
    String? lot,
    int day = 2,
  }) => repo.confirmPurchase(
    PurchaseDraft(
      supplierId: h.supplier,
      campaignId: h.campaign,
      purchaseDate: DateTime.utc(2026, 1, day),
      items: [
        PurchaseItemDraft(
          productId: product ?? h.product,
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

  Future<List<Map<String, Object?>>> lots() async =>
      (await database.database).query('inventory_lots', orderBy: 'id');

  Future<InventoryAlerts> alerts([DateTime? now]) =>
      repo.inventoryAlerts(now: now ?? today);
}

/// Con [withPin], el familiar «Titular» queda vinculado como titular de la
/// instalación y con PIN, para las correcciones.
Future<_Farm> _farm({
  String path = inMemoryDatabasePath,
  bool withPin = false,
}) async {
  final database = openDb(path);
  TestOwnerPin? pin;
  final repo = AgroRepository(database, ownerCredential: () => pin?.credential);
  final h = await seedHousehold(repo);
  final herbicide = await repo.addProduct(name: 'Atrazina', unit: 'KG');
  if (withPin) {
    final bound = await OwnerBindingStore(database).bindExistingPerson(
      personId: h.titular,
      scope: memberA,
      installationRef: installationHere,
    );
    pin = await TestOwnerPin.enrolled(
      OwnerBindingContext(
        bindingId: bound.id,
        personId: bound.personId,
        scope: memberA,
      ),
    );
  }
  return _Farm(database, repo, h, herbicide, pin);
}

int _purchaseItemOf(List<Map<String, Object?>> lots, int lotIndex) =>
    lots[lotIndex]['purchase_item_id']! as int;

void main() {
  sqfliteFfiInit();

  group('#168 datos: esquema v12, compra, transferencia, corrección', () {
    test(
      'una base v11 con lotes migra sin cambiar filas: «sin fecha registrada»',
      () async {
        final path = await tempDbPath('v11');
        final seed = await _farm(path: path);
        await seed.buy(seed.h.titular, 5000);
        await seed.database.close();
        await downgradeToV11(path);
        final old = await databaseFactoryFfi.openDatabase(path);
        expect(
          (await old.rawQuery('PRAGMA user_version')).single.values.single,
          11,
        );
        final before = await dumpTables(old);
        expect(before.containsKey('lot_data_corrections'), isFalse);
        await old.close();

        final migrated = openDb(path);
        final db = await migrated.database;
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          AppDatabase.schemaVersion,
        );
        final after = await dumpTables(db);
        expect(withoutV12(after), before);
        for (final lot in after['inventory_lots']!) {
          expect(lot['expiry_date'], isNull);
          expect(lot['lot_number'], isNull);
        }
        for (final product in after['products']!) {
          expect(product['min_stock_base'], isNull);
          expect(product['alert_lead_days'], isNull);
        }
        expect(after['lot_data_corrections'], isEmpty);
        // El lote existente se presenta como «sin fecha registrada».
        final alerts = await AgroRepository(migrated)
            .inventoryAlerts(now: today);
        expect(alerts.unknownDate.single.lot.remainingBase, 5000);
        expect(alerts.expired, isEmpty);
        expect(alerts.near, isEmpty);
      },
    );

    test('la migración es idempotente si las columnas ya existen', () async {
      final path = await tempDbPath('idem');
      final seed = await _farm(path: path);
      await seed.buy(seed.h.titular, 5000, expiry: '2027-01-31', lot: 'A1');
      await seed.database.close();
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('PRAGMA user_version = 11');
      await db.close();
      final reopened = openDb(path);
      final lots = await (await reopened.database).query('inventory_lots');
      expect(lots.single['expiry_date'], '2027-01-31');
      expect(lots.single['lot_number'], 'A1');
    });

    test(
      'la compra guarda vencimiento y número de lote en cada lote de la línea',
      () async {
        final f = await _farm();
        await f.repo.confirmPurchase(
          PurchaseDraft(
            supplierId: f.h.supplier,
            campaignId: f.h.campaign,
            purchaseDate: DateTime.utc(2026, 1, 2),
            items: [
              PurchaseItemDraft(
                productId: f.h.product,
                quantityBase: 9000,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: 10000,
                allocations: [
                  AllocationDraft(personId: f.h.titular, quantityBase: 5000),
                  AllocationDraft(personId: f.h.relative, quantityBase: 4000),
                ],
                expiryDay: '2027-03-15',
                lotNumber: 'GLI-2026-07',
              ),
              PurchaseItemDraft(
                productId: f.herbicide,
                quantityBase: 2000,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: 10000,
                allocations: [
                  AllocationDraft(personId: f.h.titular, quantityBase: 2000),
                ],
              ),
            ],
          ),
        );
        final lots = await f.lots();
        expect(lots, hasLength(3));
        expect(
          [for (final l in lots) l['expiry_date']],
          ['2027-03-15', '2027-03-15', null],
        );
        expect(
          [for (final l in lots) l['lot_number']],
          ['GLI-2026-07', 'GLI-2026-07', null],
        );
      },
    );

    test('una fecha o un número de lote mal formados no se guardan', () async {
      final f = await _farm();
      for (final expiry in ['2027-02-30', '15/03/2027', '2027-3-5']) {
        await expectLater(
          f.buy(f.h.titular, 1000, expiry: expiry),
          throwsA(isA<BusinessRuleException>()),
          reason: expiry,
        );
      }
      await expectLater(
        f.buy(f.h.titular, 1000, lot: ' A1 '),
        throwsA(isA<BusinessRuleException>()),
      );
      await expectLater(
        f.buy(f.h.titular, 1000, lot: 'X' * 41),
        throwsA(isA<BusinessRuleException>()),
      );
      expect(await f.lots(), isEmpty);
      expect(AgroRepository.normalizeLotNumber('  A1 '), 'A1');
      expect(AgroRepository.normalizeLotNumber('   '), isNull);
    });

    test('la transferencia conserva vencimiento y número de lote y no altera el FIFO', () async {
      final f = await _farm();
      // El lote más antiguo vence después que el más nuevo: el FIFO sigue
      // por fecha de adquisición, no por vencimiento.
      await f.buy(
        f.h.titular,
        3000,
        expiry: '2027-06-30',
        lot: 'VIEJO',
        day: 2,
      );
      await f.buy(
        f.h.titular,
        3000,
        expiry: '2026-12-01',
        lot: 'NUEVO',
        day: 5,
      );
      await f.repo.transferProductsFifo(
        fromPersonId: f.h.titular,
        toPersonId: f.h.relative,
        items: [TransferItemDraft(productId: f.h.product, quantityBase: 4000)],
        date: DateTime.utc(2026, 1, 6),
      );
      final lots = await f.lots();
      final destination = lots
          .where((l) => l['parent_lot_id'] != null)
          .toList();
      expect(destination, hasLength(2));
      expect(destination[0]['parent_lot_id'], lots[0]['id']);
      expect(destination[0]['initial_quantity_base'], 3000);
      expect(destination[0]['expiry_date'], '2027-06-30');
      expect(destination[0]['lot_number'], 'VIEJO');
      expect(destination[1]['parent_lot_id'], lots[1]['id']);
      expect(destination[1]['initial_quantity_base'], 1000);
      expect(destination[1]['expiry_date'], '2026-12-01');
      expect(destination[1]['lot_number'], 'NUEVO');
    });

    test('corregir con PIN cambia sólo esos datos en los lotes de procedencia demostrada y deja auditoría', () async {
      final f = await _farm(withPin: true);
      await f.buy(f.h.titular, 5000);
      // Dos niveles de transferencia: titular → hermana → vecino.
      await f.repo.transferProductsFifo(
        fromPersonId: f.h.titular,
        toPersonId: f.h.relative,
        items: [TransferItemDraft(productId: f.h.product, quantityBase: 2000)],
        date: DateTime.utc(2026, 1, 6),
      );
      await f.repo.transferProductsFifo(
        fromPersonId: f.h.relative,
        toPersonId: f.h.thirdParty,
        items: [TransferItemDraft(productId: f.h.product, quantityBase: 500)],
        date: DateTime.utc(2026, 1, 7),
      );
      final db = await f.database.database;
      final before = await dumpTables(db);
      final item = _purchaseItemOf(await f.lots(), 0);

      final done = await f.correct(
        item,
        expiry: '2026-12-20',
        lot: 'L-77',
        reason: 'Leído en la etiqueta',
      );
      expect(done.correctedLots, 3);
      expect(done.unprovenLots, 0);

      final after = await dumpTables(db);
      // Ninguna cantidad, costo ni movimiento cambia.
      for (final table in before.keys) {
        if (table == 'inventory_lots' ||
            inventoryAlertsTablesV12.contains(table)) {
          continue;
        }
        expect(after[table], before[table], reason: table);
      }
      strip(Map<String, Object?> row) => {...row}
        ..remove('expiry_date')
        ..remove('lot_number');
      expect(
        after['inventory_lots']!.map(strip).toList(),
        before['inventory_lots']!.map(strip).toList(),
      );
      for (final lot in after['inventory_lots']!) {
        expect(lot['expiry_date'], '2026-12-20');
        expect(lot['lot_number'], 'L-77');
      }
      final correction = after['lot_data_corrections']!.single;
      expect(correction['previous_expiry_date'], isNull);
      expect(correction['new_lot_number'], 'L-77');
      expect(correction['reason'], 'Leído en la etiqueta');
      expect(correction['actor_person_id'], f.h.titular);
      expect(correction['actor_member_id'], memberA.memberId);
      expect(correction['actor_method'], 'LOCAL_PIN');
      expect(correction['credential_enrolment_ref'], await f.pin!.enrolment());
      expect(correction['unproven_lot_count'], 0);
      expect(
        after['lot_data_correction_lots']!.map((r) => r['lot_id']),
        after['inventory_lots']!.map((r) => r['id']),
      );
      final history = await f.repo.lotDataCorrections(item);
      expect(history.single['actor_name'], 'Titular');
      expect(history.single['lot_count'], 3);

      // Volver a «sin fecha» también es una corrección, con otro PIN.
      await f.correct(item, expiry: null, lot: 'L-77');
      expect((await f.lots()).first['expiry_date'], isNull);
      expect(await f.repo.lotDataCorrections(item), hasLength(2));

      // Sin cambios no se registra nada.
      await expectLater(
        f.correct(item, expiry: null, lot: 'L-77'),
        throwsA(isA<BusinessRuleException>()),
      );
      expect(await f.repo.lotDataCorrections(item), hasLength(2));

      // La auditoría no se modifica ni se borra.
      for (final table in inventoryAlertsTablesV12) {
        await expectLater(
          db.update(table, {'id': 999}),
          throwsA(isA<DatabaseException>()),
          reason: table,
        );
        await expectLater(
          db.delete(table),
          throwsA(isA<DatabaseException>()),
          reason: table,
        );
      }
    });

    test(
      'sin PIN válido, sin motivo o con otra autorización no se corrige nada',
      () async {
        final f = await _farm(withPin: true);
        await f.buy(f.h.titular, 5000);
        final item = _purchaseItemOf(await f.lots(), 0);
        final db = await f.database.database;
        final before = await dumpTables(db);
        // Autorización de otro propósito.
        await expectLater(
          f.repo.correctLotData(
            item,
            expiryDay: '2027-01-01',
            lotNumber: null,
            reason: 'x',
            authorization: await f.authorize(
              item,
              purpose: AuthorizationPurpose.reversePurchase,
            ),
          ),
          throwsA(isA<OwnerAuthorizationRejected>()),
        );
        // Sin motivo.
        await expectLater(
          f.repo.correctLotData(
            item,
            expiryDay: '2027-01-01',
            lotNumber: null,
            reason: '  ',
            authorization: await f.authorize(item),
          ),
          throwsA(isA<BusinessRuleException>()),
        );
        // Una autorización sólo vale una vez.
        final once = await f.authorize(item);
        await f.repo.correctLotData(
          item,
          expiryDay: '2027-01-01',
          lotNumber: null,
          reason: 'x',
          authorization: once,
        );
        await expectLater(
          f.repo.correctLotData(
            item,
            expiryDay: '2027-02-01',
            lotNumber: null,
            reason: 'x',
            authorization: once,
          ),
          throwsA(isA<OwnerAuthorizationRejected>()),
        );
        expect(await f.repo.lotDataCorrections(item), hasLength(1));
        expect(before['lot_data_corrections'], isEmpty);
        // PIN equivocado: no se emite autorización.
        await expectLater(
          f.pin!.credential.verify(
            pin: '000000',
            purpose: AuthorizationPurpose.correctLotData,
            subjectRef: AgroRepository.lotDataSubjectRef(item),
            binding: f.pin!.binding,
          ),
          throwsA(anything),
        );
      },
    );

    test(
      'un lote de la línea sin procedencia demostrada no se cambia y se cuenta',
      () async {
        final f = await _farm(withPin: true);
        await f.buy(f.h.titular, 5000);
        final db = await f.database.database;
        final purchaseLot = (await f.lots()).single;
        // Lote con la misma línea y padre, pero sin fila en transfer_lot_items
        // (como un dato antiguo o incompleto): su procedencia no se demuestra.
        final orphan = await db.insert('inventory_lots', {
          ...({...purchaseLot}..remove('id')),
          'owner_person_id': f.h.relative,
          'parent_lot_id': purchaseLot['id'],
          'initial_quantity_base': 100,
        });
        final done = await f.correct(
          purchaseLot['purchase_item_id']! as int,
          expiry: '2027-03-03',
        );
        expect(done.correctedLots, 1);
        expect(done.unprovenLots, 1);
        final lots = {for (final l in await f.lots()) l['id']: l};
        expect(lots[purchaseLot['id']]!['expiry_date'], '2027-03-03');
        expect(lots[orphan]!['expiry_date'], isNull);
        expect(
          (await db.query('lot_data_corrections')).single['unproven_lot_count'],
          1,
        );
      },
    );

    test(
      'una compra revertida no admite correcciones; su historial se consulta',
      () async {
        final f = await _farm(withPin: true);
        final purchase = await f.buy(f.h.titular, 5000);
        final item = _purchaseItemOf(await f.lots(), 0);
        await f.correct(item, lot: 'ANTES');
        expect(await f.repo.canCorrectLotData(item), isTrue);
        await f.repo.reversePurchaseUnauditedForTesting(
          purchase,
          reason: 'error',
        );
        expect(await f.repo.canCorrectLotData(item), isFalse);
        await expectLater(
          f.correct(item, lot: 'DESPUES'),
          throwsA(
            isA<BusinessRuleException>().having(
              (e) => e.toString(),
              'mensaje',
              contains('se puede consultar, pero no corregir'),
            ),
          ),
        );
        expect((await f.lots()).single['lot_number'], 'ANTES');
        expect(await f.repo.lotDataCorrections(item), hasLength(1));
        final detail = await f.repo.purchaseDetail(purchase);
        expect(detail!.items.single['lot_number'], 'ANTES');
        expect(detail.items.single['lot_data_corrections'], 1);
      },
    );

    test(
      'el borrador de una compra tardía conserva vencimiento y número de lote',
      () {
        final draft = PurchaseDraft(
          supplierId: 1,
          campaignId: 2,
          purchaseDate: DateTime.utc(2026, 1, 2),
          items: const [
            PurchaseItemDraft(
              productId: 3,
              quantityBase: 1000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 500,
              allocations: [AllocationDraft(personId: 4, quantityBase: 1000)],
              expiryDay: '2027-01-31',
              lotNumber: 'B-9',
            ),
            PurchaseItemDraft(
              productId: 5,
              quantityBase: 1000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 500,
              allocations: [AllocationDraft(personId: 4, quantityBase: 1000)],
            ),
          ],
        );
        final raw = encodeLatePurchase(draft);
        // Una línea sin estos datos no los menciona: su JSON es el de antes.
        expect(raw.split('expiryDay').length - 1, 1);
        final decoded = decodeLatePurchase(raw);
        expect(decoded.items[0].expiryDay, '2027-01-31');
        expect(decoded.items[0].lotNumber, 'B-9');
        expect(decoded.items[1].expiryDay, isNull);
        expect(decoded.items[1].lotNumber, isNull);
      },
    );
  });

  group('#168 respaldo y restauración', () {
    late Directory workspace;
    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('agro_av_');
      PathProviderPlatform.instance = _WorkspacePathProvider(workspace.path);
    });
    tearDown(() async {
      try {
        await workspace.delete(recursive: true);
      } on FileSystemException {
        // En Windows SQLite puede retener el archivo; es temporal.
      }
    });

    test('un respaldo .agrobackup devuelve fechas, lotes, niveles y correcciones idénticos', () async {
      final source = await _farm(
        path: p.join(workspace.path, 'origen.db'),
        withPin: true,
      );
      await source.buy(
        source.h.titular,
        5000,
        expiry: '2026-11-20',
        lot: 'R-1',
      );
      await source.buy(source.h.relative, 2000, product: source.herbicide);
      await source.repo.setProductAlertSettings(
        source.h.product,
        minStockBase: 6000,
        leadDays: 15,
      );
      await source.correct(
        _purchaseItemOf(await source.lots(), 1),
        expiry: '2027-02-01',
      );
      final invoices = Directory(p.join(workspace.path, 'facturas'))
        ..createSync();
      final service = BackupService(
        source.database,
        invoicesDir: () async => invoices,
      );
      final backup = (await service.export()).path;
      final sourceDb = await source.database.database;
      final expected = {
        for (final table in [
          'inventory_lots',
          'products',
          'lot_data_corrections',
        ])
          table: await sourceDb.query(table, orderBy: 'id'),
      };
      final expectedAlerts = await source.alerts();

      final target = openDb(p.join(workspace.path, 'destino.db'));
      await AgroRepository(target).addProduct(name: 'Se reemplaza');
      await BackupService(
        target,
        invoicesDir: () async => invoices,
      ).restore(backup);
      final restored = await target.database;
      for (final entry in expected.entries) {
        expect(
          await restored.query(entry.key, orderBy: 'id'),
          entry.value,
          reason: entry.key,
        );
      }
      final alerts = await AgroRepository(target).inventoryAlerts(now: today);
      // El origen tiene un lote próximo (R-1, 10 días con plazo 15) y la
      // existencia baja del titular (5 L ≤ 6 L): se exige que no estén vacíos.
      expect(expectedAlerts.near.single.lot.lotNumber, 'R-1');
      expect(expectedAlerts.lowStock, isNotEmpty);
      expect(
        alerts.near.map((a) => a.lot.lotId),
        expectedAlerts.near.map((a) => a.lot.lotId),
      );
      expect(
        alerts.lowStock.map((a) => (a.line.personId, a.line.netBase)),
        expectedAlerts.lowStock.map((a) => (a.line.personId, a.line.netBase)),
      );
    });

    test(
      'restaurar un respaldo v11 lo migra con lotes «sin fecha registrada»',
      () async {
        final sourcePath = p.join(workspace.path, 'v11.db');
        final source = await _farm(path: sourcePath);
        await source.buy(source.h.titular, 5000);
        await source.database.close();
        await downgradeToV11(sourcePath);

        final target = openDb(p.join(workspace.path, 'destino.db'));
        final validation = await BackupService(target).validate(sourcePath);
        expect(validation.isValid, isTrue, reason: validation.problem);
        expect(validation.schemaVersion, 11);
        await BackupService(target).restore(sourcePath);
        final db = await target.database;
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          AppDatabase.schemaVersion,
        );
        expect(
          (await db.query('inventory_lots')).single['expiry_date'],
          isNull,
        );
        final alerts = await AgroRepository(target).inventoryAlerts(now: today);
        expect(alerts.unknownDate, hasLength(1));
      },
    );
  });

  group('#169 cálculo (SC-CU22-01 a 05)', () {
    test('SC-CU22-01: vencido con cantidad, próximo con días restantes, fuera de plazo sin aviso', () async {
      final f = await _farm();
      await f.buy(f.h.titular, 1000, expiry: '2026-11-09', lot: 'V'); // ayer
      await f.buy(
        f.h.titular,
        2000,
        expiry: '2026-11-10',
        lot: 'H',
        day: 3,
      ); // hoy
      await f.buy(
        f.h.titular,
        3000,
        expiry: '2026-12-10',
        lot: 'P30',
        day: 4,
      ); // +30
      await f.buy(
        f.h.titular,
        4000,
        expiry: '2026-12-11',
        lot: 'F31',
        day: 5,
      ); // +31
      final a = await f.alerts();
      expect(a.expired.single.lot.lotNumber, 'V');
      expect(a.expired.single.lot.remainingBase, 1000);
      expect(a.expired.single.days, 1);
      expect(a.near.map((x) => (x.lot.lotNumber, x.days)), [
        ('H', 0),
        ('P30', 30),
      ]);
      expect(a.near.every((x) => x.lot.leadDaysIsDefault), isTrue);
      expect(a.near.first.lot.leadDays, AppDatabase.defaultAlertLeadDays);
      // F31 vence fuera del plazo de 30 días: no avisa.
      final all = [...a.expired, ...a.near, ...a.unknownDate];
      expect(all.map((x) => x.lot.lotNumber), isNot(contains('F31')));
    });

    test('el plazo definido por el titular reemplaza al inicial', () async {
      final f = await _farm();
      await f.buy(f.h.titular, 1000, expiry: '2026-12-10');
      await f.repo.setProductAlertSettings(
        f.h.product,
        minStockBase: null,
        leadDays: 10,
      );
      expect((await f.alerts()).near, isEmpty);
      await f.repo.setProductAlertSettings(
        f.h.product,
        minStockBase: null,
        leadDays: 30,
      );
      final near = (await f.alerts()).near.single;
      expect(near.lot.leadDays, 30);
      expect(near.lot.leadDaysIsDefault, isFalse);
      await f.repo.setProductAlertSettings(
        f.h.product,
        minStockBase: null,
        leadDays: null,
      );
      expect((await f.alerts()).near.single.lot.leadDaysIsDefault, isTrue);
    });

    test('SC-CU22-02: sin fecha registrada no es vigente ni vencido', () async {
      final f = await _farm();
      await f.buy(f.h.titular, 1000);
      final a = await f.alerts();
      expect(a.unknownDate.single.status, ExpiryStatus.unknown);
      expect(a.unknownDate.single.days, isNull);
      expect(a.expired, isEmpty);
      expect(a.near, isEmpty);
    });

    test('un lote agotado, transferido entero o revertido no avisa', () async {
      final f = await _farm();
      await f.buy(f.h.titular, 1000, expiry: '2026-11-01');
      await f.h.apply(f.h.titular, f.h.titularFarm, 1000);
      // Transferido entero: el lote de origen queda en 0 y avisa sólo el de
      // destino, con la fecha heredada.
      await f.buy(f.h.titular, 700, expiry: '2026-11-02', lot: 'T', day: 3);
      await f.repo.transferProductsFifo(
        fromPersonId: f.h.titular,
        toPersonId: f.h.relative,
        items: [TransferItemDraft(productId: f.h.product, quantityBase: 700)],
        date: DateTime.utc(2026, 1, 6),
      );
      final reversed = await f.buy(
        f.h.titular,
        500,
        expiry: '2026-11-01',
        day: 4,
      );
      await f.repo.reversePurchaseUnauditedForTesting(
        reversed,
        reason: 'error',
      );
      final a = await f.alerts();
      expect(a.expired.single.lot.ownerName, 'Hermana');
      expect(a.expired.single.lot.lotNumber, 'T');
      expect(a.expired.single.lot.remainingBase, 700);
      expect(a.unknownDate, isEmpty);
    });

    test('SC-CU22-03: existencia baja con ≤ nivel; sin nivel no hay aviso y se indica', () async {
      final f = await _farm();
      await f.buy(f.h.titular, 5000);
      var a = await f.alerts();
      expect(a.lowStock, isEmpty);
      expect(a.productsWithoutLevel.map((p) => p.productName), [
        'Atrazina',
        'Glifosato',
      ]);

      await f.repo.setProductAlertSettings(
        f.h.product,
        minStockBase: 4999,
        leadDays: null,
      );
      expect((await f.alerts()).lowStock, isEmpty, reason: '5000 > 4999');
      await f.repo.setProductAlertSettings(
        f.h.product,
        minStockBase: 5000,
        leadDays: null,
      );
      a = await f.alerts();
      expect(a.lowStock.where((l) => l.line.isTotal).single.line.netBase, 5000);
      expect(a.productsWithoutLevel.map((p) => p.productName), ['Atrazina']);

      // Un nivel 0 avisa sólo al agotarse; sin nivel, agotado no avisa.
      await f.repo.setProductAlertSettings(
        f.h.product,
        minStockBase: 0,
        leadDays: null,
      );
      expect((await f.alerts()).lowStock, isEmpty);
      await f.h.apply(f.h.titular, f.h.titularFarm, 5000);
      expect(
        (await f.alerts()).lowStock.where((l) => l.line.isTotal),
        hasLength(1),
      );
      await f.repo.setProductAlertSettings(
        f.h.product,
        minStockBase: null,
        leadDays: null,
      );
      expect((await f.alerts()).lowStock, isEmpty);
    });

    test(
      'SC-CU22-04: en compartido, por responsable y para el total',
      () async {
        final f = await _farm();
        await f.buy(f.h.titular, 6000);
        await f.buy(f.h.relative, 2000, day: 3);
        await f.repo.setProductAlertSettings(
          f.h.product,
          minStockBase: 3000,
          leadDays: null,
        );
        final a = await f.alerts();
        expect(a.shared, isTrue);
        // Total 8000 > 3000: sin aviso. Hermana 2000 ≤ 3000: aviso. Titular
        // 6000: sin aviso.
        expect(a.lowStock.single.line.personName, 'Hermana');
        expect(a.lowStock.single.line.netBase, 2000);
        expect(a.lowStock.single.minStockBase, 3000);
        // El aviso del responsable lleva el total de la instalación.
        expect(a.lowStock.single.installationNetBase, 8000);
      },
    );

    test('aviso de cero para quien tuvo movimientos, con el total aparte; '
        'quien nunca tuvo el producto no avisa', () async {
      final f = await _farm();
      await f.buy(f.h.titular, 6000);
      await f.buy(f.h.relative, 1000, day: 3);
      await f.h.apply(f.h.relative, f.h.relativeFarm, 1000);
      await f.repo.setProductAlertSettings(
        f.h.product,
        minStockBase: 2000,
        leadDays: null,
      );
      var a = await f.alerts();
      final zero = a.lowStock.single;
      expect(zero.line.personName, 'Hermana');
      expect(zero.line.netBase, 0);
      // No hay falta de producto en la instalación: el total es 6 L.
      expect(zero.installationNetBase, 6000);
      expect(a.lowStock.where((l) => l.line.isTotal), isEmpty);
      // El vecino nunca tuvo Glifosato: sin aviso.
      expect(
        a.lowStock.where((l) => l.line.personId == f.h.thirdParty),
        isEmpty,
      );

      // Cuando se acaba en toda la instalación, avisa el total, con 0.
      await f.h.apply(f.h.titular, f.h.titularFarm, 6000);
      a = await f.alerts();
      final total = a.lowStock.firstWhere((l) => l.line.isTotal);
      expect(total.line.netBase, 0);
      expect(total.installationNetBase, 0);
    });

    test('en propio sólo hay un ámbito: el total del titular', () async {
      final path = await tempDbPath('propio');
      final f = await _farm(path: path);
      await OwnerBindingStore(f.database).bindExistingPerson(
        personId: f.h.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      await OperationModeStore(f.database)
          .apply(OperationMode.personal, confirmed: true);
      await f.buy(f.h.titular, 1000);
      await f.repo.setProductAlertSettings(
        f.h.product,
        minStockBase: 2000,
        leadDays: null,
      );
      final a = await f.alerts();
      expect(a.shared, isFalse);
      expect(a.lowStock.single.line.isTotal, isTrue);
    });

    test(
      'CU-22 E2: un movimiento con fecha posterior a hoy advierte del reloj',
      () async {
        final f = await _farm();
        await f.buy(f.h.titular, 1000, day: 10);
        expect((await f.alerts()).clockLooksBehind, isFalse);
        // El teléfono dice 1 de enero de 2026, antes de la compra del día 10
        // (en cualquier zona horaria).
        final behind = await f.alerts(DateTime(2026, 1, 1, 12));
        expect(behind.clockLooksBehind, isTrue);
        expect(behind.lastMovementDay, localDay(DateTime.utc(2026, 1, 10)));
      },
    );

    test(
      'SC-CU22-05: consultar no cambia nada y nada queda bloqueado',
      () async {
        final f = await _farm();
        await f.buy(f.h.titular, 2000, expiry: '2026-11-01', lot: 'VENCIDO');
        await f.buy(
          f.h.titular,
          2000,
          expiry: '2027-12-01',
          lot: 'BUENO',
          day: 3,
        );
        await f.repo.setProductAlertSettings(
          f.h.product,
          minStockBase: 5000,
          leadDays: null,
        );
        final db = await f.database.database;
        final before = await dumpTables(db);
        final a = await f.alerts();
        expect(a.expired, hasLength(1));
        expect(a.lowStock, isNotEmpty);
        expect(await dumpTables(db), before);

        // Aplicar sigue el FIFO de siempre: consume primero el lote más
        // antiguo, aunque esté vencido; el aviso no lo impide ni lo reordena.
        await f.h.apply(f.h.titular, f.h.titularFarm, 1500);
        final consumed = await db.rawQuery('''SELECT l.lot_number, -SUM(m.quantity_signed) q FROM inventory_movements m
        JOIN inventory_lots l ON l.id=m.lot_id WHERE m.type='APPLICATION_OUT'
        GROUP BY l.id''');
        expect(consumed, [
          {'lot_number': 'VENCIDO', 'q': 1500},
        ]);
        // Transferir y comprar tampoco se bloquean.
        await f.repo.transferProductsFifo(
          fromPersonId: f.h.titular,
          toPersonId: f.h.relative,
          items: [TransferItemDraft(productId: f.h.product, quantityBase: 500)],
          date: DateTime.utc(2026, 1, 6),
        );
        await f.buy(f.h.titular, 100, day: 7);
      },
    );

    test(
      'la configuración rechaza valores fuera de rango y no toca existencias',
      () async {
        final f = await _farm();
        await f.buy(f.h.titular, 1000);
        final db = await f.database.database;
        final movements = await db.query('inventory_movements');
        await expectLater(
          f.repo.setProductAlertSettings(
            f.h.product,
            minStockBase: -1,
            leadDays: null,
          ),
          throwsA(isA<BusinessRuleException>()),
        );
        for (final days in [-1, 366]) {
          await expectLater(
            f.repo.setProductAlertSettings(
              f.h.product,
              minStockBase: null,
              leadDays: days,
            ),
            throwsA(isA<BusinessRuleException>()),
          );
        }
        await expectLater(
          f.repo.setProductAlertSettings(999, minStockBase: 1, leadDays: 1),
          throwsA(isA<BusinessRuleException>()),
        );
        await f.repo.setProductAlertSettings(
          f.h.product,
          minStockBase: 0,
          leadDays: 0,
        );
        final settings = await f.repo.productAlertSettings(f.h.product);
        expect(settings.minStockBase, 0);
        expect(settings.leadDays, 0);
        expect(await db.query('inventory_movements'), movements);
      },
    );
  });

  group('cálculo puro', () {
    test('clasificación por días de calendario, sin depender del horario', () {
      expect(
        classifyExpiry(expiryDay: null, today: '2026-03-08', leadDays: 30),
        ExpiryStatus.unknown,
      );
      expect(
        classifyExpiry(
          expiryDay: '2026-03-07',
          today: '2026-03-08',
          leadDays: 30,
        ),
        ExpiryStatus.expired,
      );
      expect(
        classifyExpiry(
          expiryDay: '2026-03-08',
          today: '2026-03-08',
          leadDays: 0,
        ),
        ExpiryStatus.near,
      );
      expect(
        classifyExpiry(
          expiryDay: '2026-03-09',
          today: '2026-03-08',
          leadDays: 0,
        ),
        ExpiryStatus.later,
      );
      expect(daysBetween('2026-02-28', '2026-03-01'), 1);
      expect(daysBetween('2028-02-28', '2028-03-01'), 2);
      expect(isCivilDay('2026-02-29'), isFalse);
      expect(isCivilDay('2028-02-29'), isTrue);
    });

    test('plazo en palabras y rango del selector con fechas antiguas', () {
      expect(leadDaysText(0), 'el mismo día del vencimiento');
      expect(leadDaysText(1), '1 día antes');
      expect(leadDaysText(30), '30 días antes');
      final now = DateTime(2026, 11, 10);
      final normal = expiryPickerRange(null, now);
      expect(normal.initial, DateTime(2026, 11, 10));
      expect(normal.first, DateTime(2016));
      // Una fecha guardada fuera del rango habitual sigue siendo la inicial.
      final old = expiryPickerRange(DateTime(2001, 5, 3), now);
      expect(old.first, DateTime(2001, 5, 3));
      expect(old.initial, DateTime(2001, 5, 3));
      final far = expiryPickerRange(DateTime(2060, 1, 1), now);
      expect(far.last, DateTime(2060, 1, 1));
    });
  });
}
