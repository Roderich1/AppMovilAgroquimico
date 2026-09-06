import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// UIBUG-045 — **MODELO A: un plan representa UNA aplicación planificada.**
///
/// Un plan no es una plantilla reutilizable. Al registrar su aplicación pasa
/// de `PLANNED` a `APPLIED` y no vuelve a poder aplicarse, ni siquiera si esa
/// aplicación se revierte más tarde: revertir corrige un movimiento real, no
/// devuelve la intención al futuro. Los planes aplicados se conservan para
/// trazabilidad, pero salen de la lista operativa.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;
  late int person, farm, campaign, product, supplier;

  Future<void> openFixture() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);
    person = await repo.addPerson(name: 'José', role: PersonRole.family);
    farm = await repo.addFarm(
      ownerId: person,
      name: 'JoseLimoncito',
      areaM2: 100000,
    );
    campaign = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    product = await repo.addProduct(name: 'Glifosato');
    supplier = await repo.addSupplier(name: 'Proveedor');
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
  }

  setUp(openFixture);
  tearDown(() => database.close());

  Future<int> newPlan() => repo.addPlanMulti(
    farmId: farm,
    campaignId: campaign,
    areaM2: 100000,
    items: [PlanItemDraft(productId: product, doseBasePerHa: 1000)],
  );

  Future<int> apply(int planId) async {
    final prefill = await repo.planForApplication(planId);
    return repo.confirmApplication(
      ApplicationDraft(
        personId: person,
        farmId: farm,
        campaignId: campaign,
        planId: planId,
        treatedAreaM2: 100000,
        appliedAt: DateTime.utc(2026, 3, 1),
        lines: [
          for (final row in prefill)
            ApplicationLineDraft(
              productId: row['product_id'] as int,
              quantityBase: row['required_quantity_base'] as int,
              treatedAreaM2: row['area_m2'] as int,
              doseBasePerHa: row['dose_base_per_ha'] as int,
              theoreticalQuantityBase: row['required_quantity_base'] as int,
            ),
        ],
      ),
    );
  }

  Future<String?> statusOf(int planId) async =>
      (await (await database.database).query(
            'application_plans',
            where: 'id=?',
            whereArgs: [planId],
          )).single['status']
          as String?;

  group('regla de un solo uso', () {
    test('un plan nuevo nace PLANNED', () async {
      expect(await statusOf(await newPlan()), 'PLANNED');
    });

    test('la primera aplicación funciona y deja el plan APPLIED', () async {
      final plan = await newPlan();
      final application = await apply(plan);
      expect(application, greaterThan(0));
      expect(await statusOf(plan), 'APPLIED');
    });

    test('el segundo intento se rechaza con un mensaje comprensible', () async {
      final plan = await newPlan();
      await apply(plan);
      await expectLater(
        apply(plan),
        throwsA(
          isA<BusinessRuleException>().having(
            (error) => error.toString(),
            'mensaje',
            allOf(contains('ya fue aplicado'), contains('plan nuevo')),
          ),
        ),
      );
    });

    test(
      'el segundo intento no crea ninguna aplicación ni gasta stock',
      () async {
        final plan = await newPlan();
        await apply(plan);
        final applicationsBefore = (await repo.applications()).length;
        final stockBefore =
            (await repo.inventorySummary()).single['available_base'];

        await expectLater(apply(plan), throwsA(isA<BusinessRuleException>()));

        expect((await repo.applications()).length, applicationsBefore);
        expect(
          (await repo.inventorySummary()).single['available_base'],
          stockBefore,
        );
      },
    );

    test('dos envíos simultáneos sólo producen una aplicación', () async {
      // Un doble toque lanza las dos llamadas antes de que la primera termine.
      final plan = await newPlan();
      final results = await Future.wait<Object>([
        apply(plan).then<Object>((id) => id).catchError((Object e) => e),
        apply(plan).then<Object>((id) => id).catchError((Object e) => e),
      ]);
      expect(results.whereType<int>(), hasLength(1));
      expect(results.whereType<Exception>(), hasLength(1));
      expect(
        (await repo.applications()).where((row) => row['plan_id'] == plan),
        hasLength(1),
      );
    });

    test(
      'la base rechaza por su cuenta una segunda aplicación del plan',
      () async {
        // Se salta el repositorio y se escribe directo: el índice único parcial
        // es la barrera que protege de cualquier camino futuro.
        final plan = await newPlan();
        await apply(plan);
        final db = await database.database;
        await expectLater(
          db.insert('applications', {
            'farm_id': farm,
            'person_id': person,
            'campaign_id': campaign,
            'plan_id': plan,
            'applied_at': '2026-03-02',
            'status': 'CONFIRMED',
          }),
          throwsA(isA<DatabaseException>()),
        );
      },
    );
  });

  group('reversión', () {
    test('revertir la aplicación NO devuelve el plan a pendiente', () async {
      final plan = await newPlan();
      final application = await apply(plan);
      await repo.reverseApplication(application, reason: 'Corrección');
      expect(await statusOf(plan), 'APPLIED');
    });

    test('tras revertir tampoco se puede reaplicar', () async {
      final plan = await newPlan();
      final application = await apply(plan);
      await repo.reverseApplication(application, reason: 'Corrección');
      await expectLater(apply(plan), throwsA(isA<BusinessRuleException>()));
    });
  });

  group('lista operativa e histórico', () {
    test('la lista por omisión sólo trae planes pendientes', () async {
      final applied = await newPlan();
      final pending = await newPlan();
      await apply(applied);

      final operational = await repo.plans();
      expect(operational.map((row) => row['plan_id']).toSet(), {pending});
    });

    test('el histórico conserva el plan aplicado', () async {
      final applied = await newPlan();
      final pending = await newPlan();
      await apply(applied);

      final all = await repo.plans(includeApplied: true);
      expect(all.map((row) => row['plan_id']).toSet(), {applied, pending});
      expect(
        all.firstWhere((row) => row['plan_id'] == applied)['plan_status'],
        'APPLIED',
      );
    });

    test('el estado sobrevive a cerrar y reabrir la base', () async {
      final directory = await Directory.systemTemp.createTemp('agro_plan_');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'plans.db');

      final first = AppDatabase(factory: databaseFactoryFfi, path: path);
      final firstRepo = AgroRepository(first);
      final personId = await firstRepo.addPerson(
        name: 'José',
        role: PersonRole.family,
      );
      final farmId = await firstRepo.addFarm(
        ownerId: personId,
        name: 'Chaco',
        areaM2: 100000,
      );
      final campaignId = await firstRepo.addCampaign(
        name: 'Verano',
        start: DateTime.utc(2026, 1, 1),
      );
      final productId = await firstRepo.addProduct(name: 'Glifosato');
      final supplierId = await firstRepo.addSupplier(name: 'Prov');
      await firstRepo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplierId,
          campaignId: campaignId,
          purchaseDate: DateTime.utc(2026, 2, 1),
          items: [
            PurchaseItemDraft(
              productId: productId,
              quantityBase: 200000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 1000,
              allocations: [
                AllocationDraft(personId: personId, quantityBase: 200000),
              ],
            ),
          ],
        ),
      );
      final planId = await firstRepo.addPlanMulti(
        farmId: farmId,
        campaignId: campaignId,
        areaM2: 100000,
        items: [PlanItemDraft(productId: productId, doseBasePerHa: 1000)],
      );
      final prefill = await firstRepo.planForApplication(planId);
      await firstRepo.confirmApplication(
        ApplicationDraft(
          personId: personId,
          farmId: farmId,
          campaignId: campaignId,
          planId: planId,
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
      await first.close();

      final second = AppDatabase(factory: databaseFactoryFfi, path: path);
      final secondRepo = AgroRepository(second);
      addTearDown(second.close);
      expect(await secondRepo.plans(), isEmpty);
      expect(
        (await secondRepo.plans(includeApplied: true)).single['plan_status'],
        'APPLIED',
      );
    });
  });

  group('migración a v6', () {
    /// Base v5 mínima con lo justo para ejercitar la migración.
    Future<String> legacyV5({required int applicationsPerPlan}) async {
      final directory = await Directory.systemTemp.createTemp('agro_v6_');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'v5.db');
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE application_plans (
              id INTEGER PRIMARY KEY AUTOINCREMENT, farm_id INTEGER NOT NULL,
              campaign_id INTEGER NOT NULL, planned_date TEXT,
              status TEXT NOT NULL DEFAULT 'DRAFT', notes TEXT)''');
            await db.execute('''CREATE TABLE applications (
              id INTEGER PRIMARY KEY AUTOINCREMENT, farm_id INTEGER NOT NULL,
              person_id INTEGER NOT NULL, campaign_id INTEGER NOT NULL,
              plan_id INTEGER, applied_at TEXT NOT NULL, status TEXT NOT NULL,
              total_cost_bob_minor INTEGER NOT NULL DEFAULT 0,
              treated_area_m2 INTEGER, notes TEXT, reversed_at TEXT)''');
            await db.execute(
              'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );

            // 1 · plan marcado con el vocabulario viejo.
            await db.insert('application_plans', {
              'id': 1,
              'farm_id': 1,
              'campaign_id': 1,
              'status': 'COMPLETED',
            });
            await db.insert('applications', {
              'plan_id': 1,
              'farm_id': 1,
              'person_id': 1,
              'campaign_id': 1,
              'applied_at': '2026-03-01',
              'status': 'CONFIRMED',
            });

            // 2 · plan que la regla anterior devolvió a PLANNED al revertir:
            // su aplicación sigue existiendo, así que ya se consumió.
            await db.insert('application_plans', {
              'id': 2,
              'farm_id': 1,
              'campaign_id': 1,
              'status': 'PLANNED',
            });
            for (var i = 0; i < applicationsPerPlan; i++) {
              await db.insert('applications', {
                'plan_id': 2,
                'farm_id': 1,
                'person_id': 1,
                'campaign_id': 1,
                'applied_at': '2026-03-0${i + 2}',
                'status': i == 0 ? 'REVERSED' : 'CONFIRMED',
              });
            }

            // 3 · plan realmente pendiente, sin aplicación.
            await db.insert('application_plans', {
              'id': 3,
              'farm_id': 1,
              'campaign_id': 1,
              'status': 'PLANNED',
            });
          },
        ),
      );
      await legacy.close();
      return path;
    }

    test('COMPLETED pasa a APPLIED y el pendiente real se conserva', () async {
      final path = await legacyV5(applicationsPerPlan: 1);
      final migrated = AppDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(migrated.close);
      final db = await migrated.database;

      final statuses = {
        for (final row in await db.query('application_plans'))
          row['id']: row['status'],
      };
      expect(statuses[1], 'APPLIED');
      // Reparado: tenía una aplicación, luego ya se había usado.
      expect(statuses[2], 'APPLIED');
      // Nunca se aplicó: sigue disponible.
      expect(statuses[3], 'PLANNED');
    });

    test(
      'la migración impone la unicidad cuando los datos lo permiten',
      () async {
        final path = await legacyV5(applicationsPerPlan: 1);
        final migrated = AppDatabase(factory: databaseFactoryFfi, path: path);
        addTearDown(migrated.close);
        final db = await migrated.database;

        final index = (await db.rawQuery('PRAGMA index_list(applications)'))
            .firstWhere(
              (row) => row['name'] == 'idx_application_plan_single_use',
            );
        expect(index['unique'], 1);
        expect(index['partial'], 1);
        expect(
          await db.query(
            'app_settings',
            where: 'key=?',
            whereArgs: [AppDatabase.planReuseAnomalyKey],
          ),
          isEmpty,
        );
      },
    );

    test(
      'con un plan aplicado dos veces conserva las filas y deja constancia',
      () async {
        // Bajo la regla anterior era posible aplicar, revertir y volver a
        // aplicar. Esas filas son datos del usuario: no se borran.
        final path = await legacyV5(applicationsPerPlan: 2);
        final migrated = AppDatabase(factory: databaseFactoryFfi, path: path);
        addTearDown(migrated.close);
        final db = await migrated.database;

        expect((await db.query('applications', where: 'plan_id=2')).length, 2);
        final index = (await db.rawQuery('PRAGMA index_list(applications)'))
            .firstWhere(
              (row) => row['name'] == 'idx_application_plan_single_use',
            );
        expect(index['unique'], 0);
        expect(
          (await db.query(
            'app_settings',
            where: 'key=?',
            whereArgs: [AppDatabase.planReuseAnomalyKey],
          )).single['value'],
          '1',
        );
      },
    );
  });
}
