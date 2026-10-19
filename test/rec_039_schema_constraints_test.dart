// REC-003 (#39): restricciones que el motor SQLite impone por su cuenta,
// sin pasar por el repositorio. Pendientes desde la revisión del 2026-10-15
// (conciliación del 2026-10-19, `docs/evidence/REC_CONCILIACION_2026-10-19.md`
// §3.1).
//
// Alcance: el esquema **vigente** (versión `AppDatabase.schemaVersion`) creado
// desde cero, que es el que abre la aplicación. No prueba la base v6 de la
// línea base ni las versiones intermedias: la equivalencia de esquema tras
// migrar la cubre `schema_equivalence_test.dart`.
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

  setUp(() async {
    database = openDb(inMemoryDatabasePath);
    repo = AgroRepository(database);
    db = await database.database;
  });

  Future<int> count(String table, {String where = '1'}) async =>
      (await db.rawQuery('SELECT COUNT(*) n FROM $table WHERE $where'))
              .single['n']!
          as int;

  Matcher rejectedWith(String message) => throwsA(
    isA<DatabaseException>().having(
      (error) => error.toString(),
      'mensaje',
      contains(message),
    ),
  );

  test(
    'las claves foráneas están activas y el motor rechaza una inválida',
    () async {
      expect(AppDatabase.schemaVersion, 10);
      final pragma = await db.rawQuery('PRAGMA foreign_keys');
      expect(pragma.single.values.single, 1);

      final owner = await repo.addPerson(name: 'Ana', role: PersonRole.family);
      final valid = {
        'owner_person_id': owner,
        'name': 'Chaco Ana',
        'area_m2': 10000,
      };
      // La misma fila con una persona que no existe: la rechaza el motor.
      await expectLater(
        db.insert('farms', {...valid, 'owner_person_id': 999999}),
        rejectedWith('FOREIGN KEY constraint failed'),
      );
      expect(await count('farms'), 0);

      // Y con la persona real se acepta: el rechazo era sólo por la clave.
      await db.insert('farms', valid);
      expect(await count('farms'), 1);

      // Tampoco se puede borrar una persona que tiene un chaco.
      await expectLater(
        db.delete('persons', where: 'id=?', whereArgs: [owner]),
        rejectedWith('FOREIGN KEY constraint failed'),
      );
      expect(await count('persons'), 1);
    },
  );

  test(
    'un CHECK representativo de cada tabla de la base lo impone el motor',
    () async {
      final person = await repo.addPerson(name: 'Ana', role: PersonRole.family);
      final receiver = await repo.addPerson(
        name: 'Beto',
        role: PersonRole.family,
      );
      final supplier = await repo.addSupplier(name: 'Proveedor');
      final campaign = await repo.addCampaign(
        name: 'Verano',
        start: DateTime.utc(2026, 1, 1),
      );
      final product = await repo.addProduct(name: 'Glifosato');
      final purchase = await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: DateTime.utc(2026, 1, 5),
          items: [
            PurchaseItemDraft(
              productId: product,
              quantityBase: 1000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 10000,
              allocations: [
                AllocationDraft(personId: person, quantityBase: 1000),
              ],
            ),
          ],
        ),
      );
      final charge = await db.insert('account_transactions', {
        'person_id': person,
        'transaction_date': '2026-01-05T00:00:00.000Z',
        'type': 'MANUAL_CHARGE',
        'amount_bob_minor_signed': 5000,
      });
      final payment = await db.insert('account_transactions', {
        'person_id': person,
        'transaction_date': '2026-01-06T00:00:00.000Z',
        'type': 'PAYMENT',
        'amount_bob_minor_signed': -5000,
      });
      final transfer = await db.insert('transfers', {
        'product_id': product,
        'from_person_id': person,
        'to_person_id': receiver,
        'transfer_date': '2026-01-07T00:00:00.000Z',
        'quantity_base': 100,
        'total_cost_bob_minor': 1000,
      });

      // Por tabla: una fila válida y la misma fila con un solo campo fuera del
      // CHECK. La inválida no entra; la válida sí, de modo que el rechazo es
      // sólo por ese campo.
      final cases = <(String, Map<String, Object?>, Map<String, Object?>)>[
        (
          'persons',
          {
            'name': 'Carla',
            'role': 'FAMILY',
            'settlement_policy': 'BY_ACTUAL_USAGE',
            'created_at': '2026-01-01T00:00:00.000Z',
          },
          {'role': 'OWNER'},
        ),
        (
          'farms',
          {'owner_person_id': person, 'name': 'Chaco', 'area_m2': 10000},
          {'area_m2': 0},
        ),
        (
          'products',
          {'name': 'Atrazina', 'unit': 'KG', 'base_unit': 'G'},
          {'unit': 'GAL'},
        ),
        (
          'products',
          {'name': 'Paraquat', 'unit': 'L', 'base_unit': 'ML'},
          {'base_unit': 'OZ'},
        ),
        (
          'provider_payments',
          {
            'purchase_id': purchase,
            'payer_person_id': person,
            'payment_date': '2026-01-08T00:00:00.000Z',
            'amount_bob_minor': 500,
            'method': 'CASH',
          },
          {'amount_bob_minor': 0},
        ),
        (
          'payment_allocations',
          {
            'payment_transaction_id': payment,
            'charge_transaction_id': charge,
            'amount_bob_minor': 5000,
          },
          {'amount_bob_minor': -1},
        ),
        (
          'transfers',
          {
            'product_id': product,
            'from_person_id': receiver,
            'to_person_id': person,
            'transfer_date': '2026-01-09T00:00:00.000Z',
            'quantity_base': 100,
            'total_cost_bob_minor': 1000,
          },
          {'to_person_id': receiver},
        ),
        (
          'transfer_items',
          {
            'transfer_id': transfer,
            'product_id': product,
            'quantity_base': 100,
            'total_cost_bob_minor': 1000,
          },
          {'quantity_base': 0},
        ),
      ];
      for (final (table, valid, invalid) in cases) {
        final before = await count(table);
        await expectLater(
          db.insert(table, {...valid, ...invalid}),
          rejectedWith('CHECK constraint failed'),
          reason: '$table con $invalid',
        );
        expect(await count(table), before, reason: '$table con $invalid');
        await db.insert(table, valid);
        expect(await count(table), before + 1, reason: '$table válida');
      }
    },
  );

  test(
    'el motor no admite una segunda campaña ACTIVE insertada directamente',
    () async {
      await repo.addCampaign(name: 'Verano', start: DateTime.utc(2026, 1, 1));
      expect(await db.query('campaigns', columns: ['name', 'status']), [
        {'name': 'Verano', 'status': 'ACTIVE'},
      ]);
      final second = {
        'name': 'Invierno',
        'start_date': '2026-06-01T00:00:00.000Z',
      };

      await expectLater(
        db.insert('campaigns', {...second, 'status': 'ACTIVE'}),
        rejectedWith('UNIQUE constraint failed'),
      );
      expect(await db.query('campaigns', columns: ['name', 'status']), [
        {'name': 'Verano', 'status': 'ACTIVE'},
      ]);

      // La misma campaña como PLANNED sí entra: lo que se impide es la segunda
      // activa, no la fila.
      await db.insert('campaigns', {...second, 'status': 'PLANNED'});
      expect(await count('campaigns', where: "status='ACTIVE'"), 1);
      expect(await count('campaigns'), 2);
    },
  );
}
