// E1-D4: vincular un producto identificado por el sindicato usa el flujo de
// siempre (`bindProduct`) y no reescribe compras, aplicaciones ni
// inventario: mismas filas, mismos conteos y mismas sumas de comprobación
// antes y después. Tampoco pedir la identificación ni recibir la vista los
// toca. Datos sintéticos.
import 'dart:convert';

import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/data/sync/identification_request_store.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e1_identification_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

/// Tablas de operaciones e inventario que no pueden cambiar.
const _guarded = [
  'purchases',
  'purchase_items',
  'purchase_allocations',
  'provider_payments',
  'applications',
  'application_items',
  'application_consumptions',
  'inventory_lots',
  'inventory_movements',
  'transfers',
  'transfer_items',
  'transfer_lot_items',
  'account_transactions',
  'payment_allocations',
  'sync_outbox',
  'declared_needs',
];

Future<Map<String, (int, String)>> _fingerprint(DatabaseExecutor db) async {
  final dump = await dumpTables(db);
  return {
    for (final table in _guarded)
      table: (
        dump[table]!.length,
        crypto.sha256.convert(utf8.encode(jsonEncode(dump[table]))).toString(),
      ),
  };
}

void main() {
  sqfliteFfiInit();

  test('pedir, recibir la identificación y vincular no modifica compras, aplicaciones ni inventario', () async {
    final database = openDb(inMemoryDatabasePath);
    final repo = AgroRepository(database);
    final household = await seedHousehold(repo);
    await household.buy(household.titular, 10000);
    await household.buy(household.relative, 4000);
    await household.apply(household.titular, household.titularFarm, 2500);
    await OwnerBindingStore(database).bindExistingPerson(
      personId: household.titular,
      scope: memberA,
      installationRef: installationHere,
    );
    final db = await database.database;
    final before = await _fingerprint(db);
    expect(before['purchases']!.$1, 2);
    expect(before['applications']!.$1, 1);
    expect(before['inventory_movements']!.$1, greaterThan(0));

    final store = IdentificationRequestStore(database);
    final request = await store.create(
      productId: household.product,
      sharePhoto: false,
    );
    await store.markReceived(request.requestId);
    await store.applyServerView(
      serverView(request.requestId, localName: 'Glifosato', linked: true),
    );
    expect(await _fingerprint(db), before);

    final linked = (await store.byProduct(household.product))!;
    expect(linked.isLinked, isTrue);
    final bindings = CentralBindingStore(database);
    expect(await bindings.productBindings(), isEmpty);

    // El agricultor confirma: el vínculo usa la referencia identificada.
    final binding = await bindings.bindProduct(
      productId: household.product,
      central: centralProduct(
        ref: linked.serverProductRef!,
        name: linked.serverProductName!,
      ),
      tenantId: memberA.tenantId,
    );
    expect(binding.productRef, identifiedRef);
    expect(await _fingerprint(db), before);
    // El producto local tampoco cambia: ni nombre ni unidad.
    expect(
      (await db.query(
        'products',
        columns: ['name', 'unit', 'base_unit'],
        where: 'id=?',
        whereArgs: [household.product],
      )).single,
      {'name': 'Glifosato', 'unit': 'L', 'base_unit': 'ML'},
    );
  });
}
