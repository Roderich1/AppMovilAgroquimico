// REC-004 (#40): archivado lógico de los cuatro catálogos con operaciones
// asociadas y rechazo del renombrado en blanco. Los dos criterios que la
// tarjeta marcaba «pendiente de test» (conciliación del 2026-10-19, §3.1).
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late int carlos, ana, sur, norte, glifosato, atrazina, chacoCarlos, chacoAna;
  late int purchase, application;

  const catalogs = {'persons', 'farms', 'products', 'suppliers'};

  /// Carlos compra 10 L de Glifosato a Agro Sur y aplica 4 L en su chaco.
  /// Ana, Agro Norte, Atrazina y el chaco de Ana quedan sin operaciones.
  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    repo = AgroRepository(database);
    db = await database.database;
    carlos = await repo.addPerson(name: 'Carlos', role: PersonRole.family);
    ana = await repo.addPerson(name: 'Ana', role: PersonRole.family);
    sur = await repo.addSupplier(name: 'Agro Sur');
    norte = await repo.addSupplier(name: 'Agro Norte');
    glifosato = await repo.addProduct(name: 'Glifosato');
    atrazina = await repo.addProduct(name: 'Atrazina', unit: 'KG');
    chacoCarlos = await repo.addFarm(
      ownerId: carlos,
      name: 'Chaco Carlos',
      areaM2: 20000,
    );
    chacoAna = await repo.addFarm(
      ownerId: ana,
      name: 'Chaco Ana',
      areaM2: 30000,
    );
    final campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    purchase = await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: sur,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 5),
        items: [
          PurchaseItemDraft(
            productId: glifosato,
            quantityBase: 10000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [
              AllocationDraft(personId: carlos, quantityBase: 10000),
            ],
          ),
        ],
      ),
    );
    application = await repo.confirmApplication(
      ApplicationDraft(
        personId: carlos,
        farmId: chacoCarlos,
        campaignId: campaign,
        appliedAt: DateTime.utc(2026, 1, 20),
        lines: [ApplicationLineDraft(productId: glifosato, quantityBase: 4000)],
      ),
    );
  });

  Future<Map<String, Object?>> row(String table, int id) async =>
      (await db.query(table, where: 'id=?', whereArgs: [id])).single;

  test('archivar persona, chaco, producto y proveedor con operaciones los saca '
      'de las lecturas activas y conserva su historia', () async {
    final operationsBefore = await dumpTables(db, except: catalogs);
    final rowsBefore = {
      'persons': await row('persons', carlos),
      'farms': await row('farms', chacoCarlos),
      'products': await row('products', glifosato),
      'suppliers': await row('suppliers', sur),
    };

    await repo.archiveCatalog('persons', carlos);
    await repo.archiveCatalog('farms', chacoCarlos);
    await repo.archiveCatalog('products', glifosato);
    await repo.archiveCatalog('suppliers', sur);

    // Fuera de las lecturas activas; quedan los registros sin operaciones.
    List<Object?> names(List<Map<String, Object?>> rows) =>
        rows.map((r) => r['name']).toList();
    expect(names(await repo.people()), ['Ana']);
    expect(names(await repo.farms()), ['Chaco Ana']);
    expect(names(await repo.products()), ['Atrazina']);
    expect(names(await repo.suppliers()), ['Agro Norte']);
    expect((await repo.farms()).single['id'], chacoAna);
    expect((await repo.products()).single['id'], atrazina);
    expect((await repo.suppliers()).single['id'], norte);
    expect((await repo.people()).single['id'], ana);

    // Archivado lógico: la fila sigue, sólo cambia `active`.
    for (final MapEntry(key: table, value: before) in rowsBefore.entries) {
      final after = await row(table, before['id']! as int);
      expect(after, {...before, 'active': 0}, reason: table);
    }

    // Ninguna operación cambió: compras, lotes, movimientos, aplicaciones y
    // cuentas son idénticos fila por fila.
    expect(await dumpTables(db, except: catalogs), operationsBefore);

    // La historia sigue legible con sus nombres.
    final purchases = await repo.purchases();
    expect(purchases.single['id'], purchase);
    expect(purchases.single['supplier_name'], 'Agro Sur');
    final applications = await repo.applications();
    expect(applications.single['id'], application);
    expect(applications.single['person_name'], 'Carlos');
    expect(applications.single['farm_name'], 'Chaco Carlos');
    expect(applications.single['items_summary'], 'Glifosato|4000|L');
    // Y el saldo de Carlos: 10 L comprados − 4 L aplicados.
    expect((await stockByPersonProduct(db))[(carlos, glifosato)], 6000);
  });

  test('renombrar con un nombre en blanco se rechaza sin tocar nada', () async {
    final before = await dumpTables(db);
    final targets = {
      'persons': carlos,
      'farms': chacoCarlos,
      'products': glifosato,
      'suppliers': sur,
    };
    for (final MapEntry(key: table, value: id) in targets.entries) {
      for (final blank in ['', '   ']) {
        await expectLater(
          repo.renameCatalog(table, id, blank),
          throwsA(
            isA<BusinessRuleException>().having(
              (e) => e.message,
              'message',
              'El nombre no puede estar vacío.',
            ),
          ),
          reason: '$table «$blank»',
        );
      }
    }
    expect(await dumpTables(db), before);

    // Con un nombre real sí renombra, recortado.
    await repo.renameCatalog('products', glifosato, '  Glifosato 480  ');
    expect((await row('products', glifosato))['name'], 'Glifosato 480');
  });
}
