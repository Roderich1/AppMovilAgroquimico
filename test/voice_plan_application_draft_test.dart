import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/voice/voice_draft_gateway.dart';
import 'package:agroquimicos/voice_draft/application/application_interpreter.dart';
import 'package:agroquimicos/voice_draft/application/voice_application_draft.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

/// Aplicar un plan pendiente por voz (D-F09-4, EVO-018; #15/#16).
///
/// Selección explícita, sólo planes pendientes de la campaña activa y del
/// chaco elegido, nada cambia antes de confirmar y la escritura es la del
/// formulario con `planId`. Frases propias de la prueba.
void main() {
  sqfliteFfiInit();

  final now = DateTime(2026, 10, 17, 9);
  const bellator = CatalogEntry(
    id: 1,
    name: 'Bellator',
    unit: CatalogUnit.liter,
  );
  const expansive = CatalogEntry(
    id: 2,
    name: 'Expansive',
    unit: CatalogUnit.kilogram,
  );
  const glifosato = CatalogEntry(
    id: 3,
    name: 'Glifosato',
    unit: CatalogUnit.liter,
  );
  const sur = CatalogEntry(id: 12, name: 'Sur', areaM2: 30000);
  const norte = CatalogEntry(id: 13, name: 'Norte', areaM2: 20000);
  const jose = CatalogEntry(id: 20, name: 'José');
  const campaign = CatalogEntry(id: 30, name: 'Verano 2026');

  PendingPlan plan(int id, int farmId, {int campaignId = 30}) => PendingPlan(
    id: id,
    campaignId: campaignId,
    farmId: farmId,
    areaM2: 20000,
    plannedDate: '2026-10-20',
    items: const [
      PendingPlanItem(
        product: bellator,
        doseBasePerHa: 1500,
        requiredBase: 3000,
      ),
      PendingPlanItem(
        product: expansive,
        doseBasePerHa: 500,
        requiredBase: 1000,
      ),
    ],
  );

  VoiceCatalog catalogWith(List<PendingPlan> plans) => VoiceCatalog(
    products: const [bellator, expansive, glifosato],
    farms: const [sur, norte],
    farmOwners: const {12: jose, 13: jose},
    activeCampaign: campaign,
    pendingPlans: plans,
  );

  VoiceApplicationDraft dictate(
    String text,
    VoiceCatalog catalog, {
    VoiceApplicationDraft? current,
  }) => interpretApplication(
    text,
    current ?? VoiceApplicationDraft.start(catalog),
    catalog,
  ).draft;

  group('selección explícita del plan', () {
    test(
      'con varios planes del chaco se ofrecen todos y no se elige ninguno',
      () {
        final catalog = catalogWith([
          plan(101, 12),
          plan(102, 12),
          plan(103, 13),
        ]);
        final r = interpretApplication(
          'quiero aplicar la planificación del chaco Sur',
          VoiceApplicationDraft.start(catalog),
          catalog,
        );
        expect(r.planRequested, isTrue);
        final d = r.draft;
        expect(d.farm.value, sur);
        expect(d.plan!.status, FieldStatus.ambiguous);
        expect(d.plan!.candidates.map((e) => e.id), [101, 102]);
        expect(d.planData, isNull);
        expect(d.lines, isEmpty);
        expect(d.blockers.join(' '), contains('Elija el plan'));
      },
    );

    test('con un solo plan tampoco se elige solo', () {
      final catalog = catalogWith([plan(101, 12)]);
      final d = dictate('aplicar el plan del chaco Sur', catalog);
      expect(d.plan!.status, FieldStatus.ambiguous);
      expect(d.plan!.candidates.map((e) => e.id), [101]);
      expect(d.planData, isNull);
    });

    test('sin planes pendientes en el chaco lo dice y bloquea', () {
      final catalog = catalogWith([plan(103, 13)]);
      final d = dictate('aplicar la planificación del chaco Sur', catalog);
      expect(d.plan!.status, FieldStatus.missing);
      expect(d.plan!.message, contains('No hay planes pendientes'));
      expect(d.blockers, isNotEmpty);
    });

    test('un plan de otro chaco no se ofrece ni se puede seleccionar', () {
      final catalog = catalogWith([plan(103, 13)]);
      var d = dictate('aplicar la planificación del chaco Sur', catalog);
      final before = d;
      d = selectPlan(d, 103, catalog);
      expect(identical(d, before), isTrue);
      expect(d.planData, isNull);
    });

    test('un plan de otra campaña no se ofrece ni se puede seleccionar', () {
      final catalog = catalogWith([plan(104, 12, campaignId: 99)]);
      var d = dictate('aplicar la planificación del chaco Sur', catalog);
      expect(d.plan!.status, FieldStatus.missing);
      d = selectPlan(d, 104, catalog);
      expect(d.planData, isNull);
    });

    test(
      'al seleccionar, las líneas son las del plan y se escribe con su planId',
      () {
        final catalog = catalogWith([plan(101, 12), plan(102, 12)]);
        var d = dictate('aplicar la planificación del chaco Sur', catalog);
        d = selectPlan(d, 102, catalog).withStock(jose.id, {1: 9000, 2: 9000});
        expect(d.plan!.isResolved, isTrue);
        expect(d.plan!.isManual, isTrue);
        expect(d.area.value, 20000);
        expect(d.lines.map((l) => l.product.value), [bellator, expansive]);
        expect(d.lines.map((l) => l.plannedBase), [3000, 1000]);
        expect(d.lines.map((l) => l.quantityBase), [3000, 1000]);
        expect(d.lines.map((l) => l.differenceBase), [0, 0]);
        expect(d.blockers, isEmpty);

        final domain = d.toDomain(at: now);
        expect(domain.planId, 102);
        expect(domain.personId, jose.id);
        expect(domain.farmId, sur.id);
        expect(domain.lines.map((l) => l.doseBasePerHa), [1500, 500]);
        expect(domain.lines.map((l) => l.theoreticalQuantityBase), [
          3000,
          1000,
        ]);
      },
    );

    test('corregir por voz la cantidad real no toca lo planeado', () {
      final catalog = catalogWith([plan(101, 12)]);
      var d = dictate('aplicar la planificación del chaco Sur', catalog);
      d = selectPlan(d, 101, catalog);
      d = dictate(
        'de Bellator en realidad usamos cuatro litros de Bellator',
        catalog,
        current: d,
      );
      final line = d.lines.firstWhere((l) => l.product.value == bellator);
      expect(line.quantityBase, 4000);
      expect(line.plannedBase, 3000);
      expect(line.differenceBase, 1000);
    });

    test('lo corregido a mano no lo cambia un dictado tardío', () {
      final catalog = catalogWith([plan(101, 12)]);
      var d = dictate('aplicar la planificación del chaco Sur', catalog);
      d = selectPlan(d, 101, catalog);
      final key = d.lines.first.key;
      d = d.updateLine(
        key,
        (l) => l.copyWith(
          quantity: const DraftField.resolved(
            SpokenAmount(2500, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      );
      final r = interpretApplication('cinco litros de Bellator', d, catalog);
      expect(r.draft.lines.first.quantityBase, 2500);
      expect(r.outcome.keptManual, 1);
    });

    test('un producto que no está en el plan bloquea', () {
      final catalog = catalogWith([plan(101, 12)]);
      var d = dictate('aplicar la planificación del chaco Sur', catalog);
      d = selectPlan(
        d,
        101,
        catalog,
      ).withStock(jose.id, {1: 9000, 2: 9000, 3: 9000});
      d = dictate('y dos litros de Glifosato', catalog, current: d);
      expect(d.blockers.join(' '), contains('no está en el plan'));
    });

    test('cambiar de chaco quita el plan elegido y ofrece los del nuevo', () {
      final catalog = catalogWith([plan(101, 12), plan(103, 13)]);
      var d = dictate('aplicar la planificación del chaco Sur', catalog);
      d = selectPlan(d, 101, catalog);
      d = selectFarm(
        d.copyWith(
          farm: const DraftField.resolved(norte, origin: FieldOrigin.manual),
        ),
        catalog,
      );
      expect(d.planData, isNull);
      expect(d.plan!.candidates.map((e) => e.id), [103]);
    });

    test('quitar el plan vuelve a una aplicación libre', () {
      final catalog = catalogWith([plan(101, 12)]);
      var d = dictate('aplicar la planificación del chaco Sur', catalog);
      d = clearPlan(selectPlan(d, 101, catalog));
      expect(d.plan, isNull);
      expect(d.lines.every((l) => !l.fromPlan), isTrue);
      expect(
        d.withStock(jose.id, {1: 9000, 2: 9000}).toDomain(at: now).planId,
        isNull,
      );
    });
  });

  group('contra la base real', () {
    late AppDatabase database;
    late Household household;
    late VoiceDraftGateway gateway;
    late AgroRepository repo;
    late int bellatorId;
    late int planId;

    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      repo = AgroRepository(database);
      household = await seedHousehold(repo);
      bellatorId = await repo.addProduct(name: 'Bellator');
      await household.buy(household.titular, 5000);
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: household.supplier,
          campaignId: household.campaign,
          purchaseDate: DateTime(2026, 1, 2),
          items: [
            PurchaseItemDraft(
              productId: bellatorId,
              quantityBase: 5000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 20000,
              allocations: [
                AllocationDraft(
                  personId: household.titular,
                  quantityBase: 5000,
                ),
              ],
            ),
          ],
        ),
      );
      planId = await repo.addPlanMulti(
        farmId: household.titularFarm,
        campaignId: household.campaign,
        areaM2: 10000,
        items: [
          PlanItemDraft(productId: household.product, doseBasePerHa: 2000),
          PlanItemDraft(productId: bellatorId, doseBasePerHa: 1000),
        ],
      );
      gateway = VoiceDraftGateway(repo, clock: () => now);
    });

    Future<VoiceDraftController<VoiceApplicationDraft, int>>
    openWithPlan() async {
      final catalog = await gateway.applicationCatalog();
      final controller = VoiceDraftController<VoiceApplicationDraft, int>(
        initial: VoiceApplicationDraft.start(catalog),
        commit: gateway.confirmApplication,
      );
      addTearDown(controller.dispose);
      controller.applyVoice((current) {
        final r = interpretApplication(
          'aplicar la planificación del chaco titular',
          current,
          catalog,
        );
        return (r.draft, r.outcome);
      });
      controller.editManually((c) => selectPlan(c, planId, catalog));
      final owner = controller.draft.person!.id;
      final stock = await gateway.availableStock(owner);
      controller.editManually((c) => c.withStock(owner, stock));
      return controller;
    }

    test(
      'el catálogo ofrece sólo planes pendientes de la campaña activa',
      () async {
        // Un plan de una campaña no activa, insertado como fixture.
        final db = await database.database;
        final other = await repo.addCampaign(
          name: 'Campaña 2',
          start: DateTime.utc(2027, 1, 1),
        );
        await db.insert('application_plans', {
          'farm_id': household.titularFarm,
          'campaign_id': other,
          'status': 'PLANNED',
        });
        final catalog = await gateway.applicationCatalog();
        expect(catalog.pendingPlans.map((p) => p.id), [planId]);
        expect(catalog.pendingPlans.single.campaignId, household.campaign);
      },
    );

    test(
      'dictar, elegir el plan y cancelar o liberar no cambia nada',
      () async {
        final db = await database.database;
        final before = await dumpTables(db);
        final controller = await openWithPlan();
        expect(controller.canConfirm, isTrue);
        controller.discard();
        expect(await controller.confirm(), isNull);
        expect(await dumpTables(db), before);
        final other = await openWithPlan();
        other.dispose();
        expect(await dumpTables(db), before);
      },
    );

    test(
      'doble confirmación: una sola aplicación y el plan consumido una vez',
      () async {
        final db = await database.database;
        final controller = await openWithPlan();
        final results = await Future.wait([
          controller.confirm(),
          controller.confirm(),
        ]);
        expect(results.whereType<int>(), hasLength(1));
        expect(await db.query('applications'), hasLength(1));
        final applied = await db.query(
          'application_plans',
          where: 'id=?',
          whereArgs: [planId],
        );
        expect(applied.single['status'], AgroRepository.appliedPlanStatus);
        // Un callback tardío después de confirmar no entra.
        expect(
          controller.applyVoice((d) => throw StateError('no debe correr')),
          isFalse,
        );
      },
    );

    test(
      'plan ya aplicado antes de confirmar: falla sin efectos y sigue editable',
      () async {
        final controller = await openWithPlan();
        // Otra acción aplica el plan antes que la voz.
        await repo.confirmApplication(
          controller.draft.toDomain(at: now.add(const Duration(minutes: 1))),
        );
        final db = await database.database;
        final before = await dumpTables(db);
        expect(await controller.confirm(), isNull);
        expect(controller.phase, DraftPhase.editing);
        expect(controller.error, isNotNull);
        expect(await dumpTables(db), before);
      },
    );

    test(
      'mismo resultado que el formulario abierto desde «Aplicar este plan»',
      () async {
        final controller = await openWithPlan();
        await controller.confirm();

        final manualDb = openDb(await tempDbPath('manual-plan-application'));
        final manualRepo = AgroRepository(manualDb);
        final manual = await seedHousehold(manualRepo);
        final manualBellator = await manualRepo.addProduct(name: 'Bellator');
        await manual.buy(manual.titular, 5000);
        await manualRepo.confirmPurchase(
          PurchaseDraft(
            supplierId: manual.supplier,
            campaignId: manual.campaign,
            purchaseDate: DateTime(2026, 1, 2),
            items: [
              PurchaseItemDraft(
                productId: manualBellator,
                quantityBase: 5000,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: 20000,
                allocations: [
                  AllocationDraft(personId: manual.titular, quantityBase: 5000),
                ],
              ),
            ],
          ),
        );
        final manualPlan = await manualRepo.addPlanMulti(
          farmId: manual.titularFarm,
          campaignId: manual.campaign,
          areaM2: 10000,
          items: [
            PlanItemDraft(productId: manual.product, doseBasePerHa: 2000),
            PlanItemDraft(productId: manualBellator, doseBasePerHa: 1000),
          ],
        );
        // Lo que arma `application_form_screen.dart` con `planId`: persona y
        // chaco del plan, área del plan, real = requerida, dosis del plan,
        // teórica = área × dosis, notas vacías y `DateTime.now()` al enviar.
        await manualRepo.confirmApplication(
          ApplicationDraft(
            personId: manual.titular,
            farmId: manual.titularFarm,
            campaignId: manual.campaign,
            appliedAt: now,
            notes: '',
            treatedAreaM2: 10000,
            planId: manualPlan,
            lines: [
              ApplicationLineDraft(
                productId: manual.product,
                quantityBase: 2000,
                treatedAreaM2: 10000,
                doseBasePerHa: 2000,
                theoreticalQuantityBase: 2000,
              ),
              ApplicationLineDraft(
                productId: manualBellator,
                quantityBase: 1000,
                treatedAreaM2: 10000,
                doseBasePerHa: 1000,
                theoreticalQuantityBase: 1000,
              ),
            ],
          ),
        );

        Future<List<Map<String, Object?>>> rows(
          AppDatabase d,
          String t,
        ) async => [
          for (final row in await (await d.database).query(t, orderBy: 'id'))
            {
              for (final e in row.entries)
                if (!e.key.endsWith('_at') &&
                    !e.key.contains('uuid') &&
                    !e.key.contains('operation'))
                  e.key: e.value,
            },
        ];
        for (final table in const [
          'applications',
          'application_items',
          'application_consumptions',
          'application_plans',
          'application_plan_items',
          'inventory_movements',
          'account_transactions',
        ]) {
          expect(
            await rows(database, table),
            await rows(manualDb, table),
            reason: table,
          );
        }
      },
    );

    test('SHARED ofrece los planes del chaco de cada persona', () async {
      final relativePlan = await repo.addPlanMulti(
        farmId: household.relativeFarm,
        campaignId: household.campaign,
        areaM2: 5000,
        items: [
          PlanItemDraft(productId: household.product, doseBasePerHa: 1000),
        ],
      );
      final shared = await gateway.applicationCatalog();
      expect(
        shared
            .plansFor(household.relativeFarm, household.campaign)
            .map((p) => p.id),
        [relativePlan],
      );
      expect(
        shared
            .plansFor(household.titularFarm, household.campaign)
            .map((p) => p.id),
        [planId],
      );
      // F04 no deja pasar a propio con planes ajenos pendientes: en PERSONAL
      // un plan de otra persona no puede llegar a ofrecerse.
      await OwnerBindingStore(database).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      await expectLater(
        OperationModeStore(database)
            .apply(OperationMode.personal, confirmed: true),
        throwsA(isA<ModeTransitionException>()),
      );
    });

    test('PERSONAL ofrece sólo el chaco y los planes del titular', () async {
      await OwnerBindingStore(database).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      await OperationModeStore(database)
          .apply(OperationMode.personal, confirmed: true);
      final personal = await gateway.applicationCatalog();
      expect(personal.farms.map((f) => f.id), [household.titularFarm]);
      expect(personal.pendingPlans.map((p) => p.id), [planId]);
    });
  });
}
