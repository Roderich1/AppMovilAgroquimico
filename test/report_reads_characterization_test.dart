import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Caracterización de las lecturas que EVOLUTION-2 va a tipar (EVO-004).
///
/// `reports_test.dart` ya fija `productCostReport`, `farmCostReport`,
/// `inventorySummary` y `campaignCloseSummary`. Faltaban las tres consultas de
/// cuentas —`settlements`, `detailedStatement`, `personCampaignBalance`— y el
/// orden de `campaigns`/`topSettlements`, que son fuente de dos de los cinco
/// reportes obligatorios.
///
/// Estos tests describen el contrato ACTUAL: nombres de alias, orden, filtros,
/// nulos y valores enteros. Se escriben ANTES de introducir los modelos
/// tipados para que la paridad se mida contra un contrato observado, no contra
/// la implementación nueva.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late int admin, family, third;
  late int supplier, farm, campaign1, campaign2;
  late int glifosato;

  // ── Escenario ─────────────────────────────────────────────────────────────
  //
  // Campaña 1 (2026-01-01) y campaña 2 (2026-07-01).
  // Chaco de 10 ha del familiar.
  //
  // Compra en campaña 1: 20 L de Glifosato a Bs 100,00/L = Bs 2.000,00,
  //   repartida 15 L al familiar y 5 L al tercero.
  //   El tercero se carga por asignación: 5 × 100 = Bs 500,00.
  //   El familiar se carga por consumo, así que la compra no le carga nada.
  //
  // Aplicación en campaña 1: el familiar aplica 5 L -> cargo Bs 500,00.
  //
  // Pago en campaña 1: el familiar paga Bs 200,00 -> asiento de -20000.
  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);

    admin = await repo.addPerson(name: 'Administrador', role: PersonRole.admin);
    family = await repo.addPerson(
      name: 'Ana Familiar',
      role: PersonRole.family,
    );
    third = await repo.addPerson(
      name: 'Beto Tercero',
      role: PersonRole.thirdParty,
    );
    supplier = await repo.addSupplier(name: 'Proveedor');
    farm = await repo.addFarm(
      ownerId: family,
      name: 'Chaco Uno',
      areaM2: 100000,
    );
    campaign1 = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato');

    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign1,
        purchaseDate: DateTime.utc(2026, 1, 10),
        items: [
          PurchaseItemDraft(
            productId: glifosato,
            quantityBase: 20000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [
              AllocationDraft(personId: family, quantityBase: 15000),
              AllocationDraft(personId: third, quantityBase: 5000),
            ],
          ),
        ],
      ),
    );

    await repo.confirmApplication(
      ApplicationDraft(
        personId: family,
        farmId: farm,
        campaignId: campaign1,
        appliedAt: DateTime.utc(2026, 2, 1),
        treatedAreaM2: 100000,
        lines: [ApplicationLineDraft(productId: glifosato, quantityBase: 5000)],
      ),
    );

    await repo.addAccountPayment(
      personId: family,
      campaignId: campaign1,
      amountBobMinor: 20000,
      date: DateTime.utc(2026, 3, 1),
    );

    campaign2 = await repo.addCampaign(
      name: 'Campaña 2',
      start: DateTime.utc(2026, 7, 1),
    );
  });

  tearDown(() => database.close());

  group('settlements', () {
    test('expone los alias id/name/role/balance/charges/payments', () async {
      final rows = await repo.settlements();
      expect(rows.first.keys.toSet(), {
        'id',
        'name',
        'role',
        'balance',
        'charges',
        'payments',
      });
    });

    test('excluye al ADMIN y conserva familiares y terceros', () async {
      final rows = await repo.settlements();
      expect(rows.map((r) => r['id']), isNot(contains(admin)));
      expect(rows.map((r) => r['id']).toSet(), {family, third});
    });

    test('ordena por saldo descendente y luego por nombre', () async {
      // Familiar: cargo por consumo 50000 - pago 20000 = 30000.
      // Tercero: cargo por asignación 50000, sin pagos = 50000.
      final rows = await repo.settlements();
      expect(rows.map((r) => r['balance']).toList(), [50000, 30000]);
      expect(rows.map((r) => r['name']).toList(), [
        'Beto Tercero',
        'Ana Familiar',
      ]);
    });

    test('devuelve enteros, no decimales', () async {
      final row = (await repo.settlements()).firstWhere(
        (r) => r['id'] == family,
      );
      expect(row['balance'], isA<int>());
      expect(row['charges'], isA<int>());
      expect(row['payments'], isA<int>());
      // Cargos 50000, pagos 20000 (positivo por el `-SUM`), saldo 30000.
      expect(row['charges'], 50000);
      expect(row['payments'], 20000);
      expect(row['balance'], 30000);
    });

    test(
      'el filtro de campaña deja en cero a quien no operó en ella',
      () async {
        final rows = await repo.settlements(campaignId: campaign2);
        expect(rows, hasLength(2));
        for (final row in rows) {
          expect(row['balance'], 0);
          expect(row['charges'], 0);
          expect(row['payments'], 0);
        }
      },
    );
  });

  group('topSettlements', () {
    test('respeta el límite y el orden por saldo descendente', () async {
      final rows = await repo.topSettlements(limit: 1);
      expect(rows, hasLength(1));
      expect(rows.single['id'], third);
      expect(rows.single['balance'], 50000);
    });

    test('expone sólo id/name/role/balance', () async {
      final rows = await repo.topSettlements();
      expect(rows.first.keys.toSet(), {'id', 'name', 'role', 'balance'});
    });
  });

  group('detailedStatement', () {
    test('ordena por fecha y luego por id', () async {
      final rows = await repo.detailedStatement(family);
      final dates = rows.map((r) => '${r['transaction_date']}').toList();
      final sorted = [...dates]..sort();
      expect(dates, sorted);
    });

    test('trae importe firmado entero, concepto y chaco', () async {
      final rows = await repo.detailedStatement(family);
      // Cargo por consumo (+50000) y pago (-20000).
      expect(rows.map((r) => r['amount_bob_minor_signed']).toList(), [
        50000,
        -20000,
      ]);
      for (final row in rows) {
        expect(row['amount_bob_minor_signed'], isA<int>());
      }
      // El cargo por consumo nombra los productos aplicados y su chaco.
      expect(rows.first['concept'], 'Glifosato');
      expect(rows.first['farm_name'], 'Chaco Uno');
    });

    test('un pago sin notas cae al tipo y no tiene chaco', () async {
      final payment = (await repo.detailedStatement(family))
          .firstWhere((r) => r['type'] == 'PAYMENT');
      // `concept` es COALESCE(productos, producto, notes, type): sin notas
      // queda el literal del tipo, y `farm_name` es NULL.
      expect(payment['concept'], 'PAYMENT');
      expect(payment['farm_name'], isNull);
    });

    test('filtrar por una campaña sin movimientos devuelve vacío', () async {
      expect(
        await repo.detailedStatement(family, campaignId: campaign2),
        isEmpty,
      );
    });

    test('conserva las columnas de account_transactions', () async {
      final row = (await repo.detailedStatement(family)).first;
      expect(
        row.keys,
        containsAll(<String>[
          'id',
          'person_id',
          'campaign_id',
          'transaction_date',
          'type',
          'amount_bob_minor_signed',
          'reference_type',
          'reference_id',
          'notes',
          'reversal_of_id',
          'concept',
          'farm_name',
        ]),
      );
    });
  });

  group('personCampaignBalance', () {
    test('expone los cuatro totales como enteros', () async {
      final balance = await repo.personCampaignBalance(family, campaign1);
      expect(balance.keys.toSet(), {
        'opening_balance',
        'campaign_charges',
        'campaign_payments',
        'total_balance',
      });
      for (final value in balance.values) {
        expect(value, isA<int>());
      }
    });

    test('separa cargos, pagos y saldo de la campaña', () async {
      final balance = await repo.personCampaignBalance(family, campaign1);
      // No hay campaña anterior a la 1, así que el saldo inicial es cero.
      expect(balance['opening_balance'], 0);
      expect(balance['campaign_charges'], 50000);
      expect(balance['campaign_payments'], 20000);
      expect(balance['total_balance'], 30000);
    });

    test(
      'el saldo inicial de una campaña posterior arrastra la anterior',
      () async {
        final balance = await repo.personCampaignBalance(family, campaign2);
        // Todo lo de la campaña 1 (30000) empieza como saldo inicial de la 2.
        expect(balance['opening_balance'], 30000);
        expect(balance['campaign_charges'], 0);
        expect(balance['campaign_payments'], 0);
        expect(balance['total_balance'], 30000);
      },
    );
  });

  group('campaigns', () {
    test('ordena por fecha de inicio descendente', () async {
      final rows = await repo.campaigns();
      expect(rows.map((r) => r['id']).toList(), [campaign2, campaign1]);
    });

    test('trae nombre, estado y fechas; end_date puede ser nulo', () async {
      final row = (await repo.campaigns()).firstWhere(
        (r) => r['id'] == campaign1,
      );
      expect(row['name'], 'Campaña 1');
      expect(row['status'], 'ACTIVE');
      expect(row['start_date'], isA<String>());
      expect(row['end_date'], isNull);
    });
  });

  group('people', () {
    test('sólo personas activas, ordenadas por nombre', () async {
      final rows = await repo.people();
      expect(rows.map((r) => r['name']).toList(), [
        'Administrador',
        'Ana Familiar',
        'Beto Tercero',
      ]);
    });

    test('el teléfono puede ser nulo', () async {
      final row = (await repo.people()).firstWhere((r) => r['id'] == family);
      expect(row['phone'], isNull);
      expect(row['role'], 'FAMILY');
    });
  });
}
