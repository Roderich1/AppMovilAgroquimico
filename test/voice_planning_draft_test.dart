import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/voice/voice_draft_gateway.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:agroquimicos/voice_draft/interpretation/voice_intent.dart';
import 'package:agroquimicos/voice_draft/plan/plan_interpreter.dart';
import 'package:agroquimicos/voice_draft/plan/voice_plan_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

/// Planificación por voz (#14, F09-VOZ-06). Frases propias de la prueba.
void main() {
  sqfliteFfiInit();

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
  const norte = CatalogEntry(id: 10, name: 'Norte', areaM2: 50000);
  const norteBajo = CatalogEntry(id: 11, name: 'Norte Bajo', areaM2: 20000);
  const sur = CatalogEntry(id: 12, name: 'Sur', areaM2: 30000);
  const campaign = CatalogEntry(id: 30, name: 'Verano 2026');

  const catalog = VoiceCatalog(
    products: [bellator, expansive],
    farms: [norte, norteBajo, sur],
    activeCampaign: campaign,
  );

  VoicePlanDraft interpret(String text, {VoicePlanDraft? current}) =>
      interpretPlan(
        text,
        current ?? VoicePlanDraft.start(catalog),
        catalog,
      ).draft;

  group('interpretación del dictado', () {
    test('chaco, área propuesta y dos productos con su dosis', () {
      final d = interpret(
        'Quiero planificar el chaco Sur con dos litros por hectárea de '
        'Bellator y un kilo por hectárea de Expansive',
      );
      expect(d.farm.value, sur);
      expect(d.area.value, 30000);
      expect(d.area.origin, FieldOrigin.preset);
      expect(d.campaign.value, campaign);
      expect(d.lines.map((l) => l.product.value?.id), [1, 2]);
      expect(d.lines.map((l) => l.doseBasePerHa), [2000, 1000]);
      // Necesita = área × dosis, como addPlanMulti.
      expect(d.lines.map((l) => l.requiredBase(d.area.value)), [6000, 3000]);
      expect(d.blockers, isEmpty);
    });

    test('el área dicha manda sobre la del chaco', () {
      final d = interpret(
        'planificar el chaco Sur en dos hectáreas, Bellator a dos litros por '
        'hectárea',
      );
      expect(d.area.value, 20000);
      expect(d.area.origin, FieldOrigin.voice);
      expect(d.lines.single.product.value, bellator);
    });

    test('un chaco con varias coincidencias queda ambiguo y bloquea', () {
      final d = interpret(
        'planificar el chaco nort con dos litros por hectárea de Bellator',
      );
      expect(d.farm.status, FieldStatus.ambiguous);
      expect(d.farm.candidates.map((e) => e.id).toSet(), {10, 11});
      expect(d.area.isResolved, isFalse);
      expect(d.blockers.join(' '), contains('chaco'));
    });

    test('un producto que no está en el catálogo queda faltante', () {
      final d = interpret(
        'planificar el chaco Sur con dos litros por hectárea de Paraquat',
      );
      expect(d.lines.single.product.status, FieldStatus.missing);
      expect(d.blockers, isNotEmpty);
    });

    test('litros por hectárea de un producto en kilos bloquea', () {
      final d = interpret(
        'planificar el chaco Sur con dos litros por hectárea de Expansive',
      );
      expect(d.lines.single.doseBasePerHa, isNull);
      expect(d.blockers.join(' '), contains('unidad'));
    });

    test('sin dosis no hay línea: el plan no inventa cantidades', () {
      final d = interpret('planificar el chaco Sur con Bellator');
      expect(d.lines, isEmpty);
      expect(d.blockers.join(' '), contains('producto'));
    });

    test('nombrar otra vez el producto corrige sólo su dosis', () {
      var d = interpret(
        'planificar el chaco Sur, Bellator a dos litros por hectárea',
      );
      d = interpret(
        'en realidad tres litros por hectárea de Bellator',
        current: d,
      );
      expect(d.lines, hasLength(1));
      expect(d.lines.single.doseBasePerHa, 3000);
      expect(d.farm.value, sur);
    });

    test('la dosis corregida a mano no la cambia un dictado posterior', () {
      var d = interpret(
        'planificar el chaco Sur, Bellator a dos litros por hectárea',
      );
      d = d.updateLine(
        d.lines.single.key,
        (l) => l.copyWith(
          dose: const DraftField.resolved(
            SpokenDose(1500, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      );
      final r = interpretPlan(
        'cuatro litros por hectárea de Bellator',
        d,
        catalog,
      );
      expect(r.draft.lines.single.doseBasePerHa, 1500);
      expect(r.outcome.keptManual, 1);
    });

    test('el área corregida a mano no la cambia otro chaco dictado', () {
      var d = interpret('planificar el chaco Sur');
      d = d.copyWith(
        area: const DraftField.resolved(12345, origin: FieldOrigin.manual),
      );
      d = interpret('mejor el chaco Norte', current: d);
      expect(d.farm.value, norte);
      expect(d.area.value, 12345);
    });

    test('otra operación no cambia el borrador', () {
      final start = VoicePlanDraft.start(catalog);
      final r = interpretPlan(
        'compré veinte litros de Bellator',
        start,
        catalog,
      );
      expect(r.otherIntent, VoiceIntent.purchase);
      expect(identical(r.draft, start), isTrue);
    });

    test('sin campaña activa no se puede crear el plan', () {
      final d = interpretPlan(
        'planificar el chaco Sur con dos litros por hectárea de Bellator',
        VoicePlanDraft.start(
          const VoiceCatalog(products: [bellator], farms: [sur]),
        ),
        catalog,
      ).draft;
      expect(d.blockers.join(' '), contains('campaña'));
    });
  });

  group('contra la base real', () {
    late AppDatabase database;
    late Household household;
    late VoiceDraftGateway gateway;

    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      final repo = AgroRepository(database);
      household = await seedHousehold(repo);
      await repo.addProduct(name: 'Bellator');
      gateway = VoiceDraftGateway(repo);
    });

    const dictation =
        'planificar el chaco titular con dos litros por hectárea de Bellator y '
        'cien mililitros por hectárea de Glifosato';

    Future<VoiceDraftController<VoicePlanDraft, int>> openDraft() async {
      final catalog = await gateway.planCatalog();
      final controller = VoiceDraftController<VoicePlanDraft, int>(
        initial: VoicePlanDraft.start(catalog),
        commit: gateway.confirmPlan,
      );
      addTearDown(controller.dispose);
      controller.applyVoice((current) {
        final r = interpretPlan(dictation, current, catalog);
        return (r.draft, r.outcome);
      });
      return controller;
    }

    test('el borrador queda listo con el chaco y su área', () async {
      final controller = await openDraft();
      expect(controller.blockers, isEmpty);
      expect(controller.draft.farm.value!.id, household.titularFarm);
      expect(controller.draft.area.value, 10000);
    });

    test('cancelar o liberar no crea plan ni toca inventario', () async {
      final db = await database.database;
      final before = await dumpTables(db);
      final controller = await openDraft();
      controller.discard();
      expect(await controller.confirm(), isNull);
      expect(await dumpTables(db), before);

      final other = await openDraft();
      other.dispose();
      expect(await dumpTables(db), before);
    });

    test('confirmar dos veces crea un solo plan', () async {
      final db = await database.database;
      final controller = await openDraft();
      final results = await Future.wait([
        controller.confirm(),
        controller.confirm(),
      ]);
      expect(results.whereType<int>(), hasLength(1));
      expect(await db.query('application_plans'), hasLength(1));
      expect(await controller.confirm(), isNull);
      expect(await db.query('application_plans'), hasLength(1));
    });

    test('crear el plan no cambia inventario ni necesidades', () async {
      final db = await database.database;
      const plans = {'application_plans', 'application_plan_items'};
      final before = await dumpTables(db, except: plans);
      final controller = await openDraft();
      await controller.confirm();
      expect(await dumpTables(db, except: plans), before);
    });

    test('mismo plan que el formulario manual', () async {
      final controller = await openDraft();
      await controller.confirm();

      final manualDb = openDb(await tempDbPath('manual-plan'));
      final manualRepo = AgroRepository(manualDb);
      final manual = await seedHousehold(manualRepo);
      final manualBellator = await manualRepo.addProduct(name: 'Bellator');
      await manualRepo.addPlanMulti(
        farmId: manual.titularFarm,
        campaignId: manual.campaign,
        areaM2: 10000,
        items: [
          PlanItemDraft(productId: manualBellator, doseBasePerHa: 2000),
          PlanItemDraft(productId: manual.product, doseBasePerHa: 100),
        ],
      );

      Future<List<Map<String, Object?>>> rows(AppDatabase d, String t) async =>
          [
            for (final row in await (await d.database).query(t, orderBy: 'id'))
              {
                for (final e in row.entries)
                  if (!e.key.endsWith('_at')) e.key: e.value,
              },
          ];
      for (final table in const [
        'application_plans',
        'application_plan_items',
      ]) {
        expect(await rows(database, table), await rows(manualDb, table));
      }
    });

    test('PERSONAL: sólo se ofrecen los chacos del titular', () async {
      await OwnerBindingStore(database).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      await OperationModeStore(database)
          .apply(OperationMode.personal, confirmed: true);
      final catalog = await gateway.planCatalog();
      expect(catalog.farms.map((f) => f.id), [household.titularFarm]);

      final d = interpretPlan(
        'planificar el chaco hermana con dos litros por hectárea de Bellator',
        VoicePlanDraft.start(catalog),
        catalog,
      ).draft;
      expect(d.farm.isResolved, isFalse);
      expect(d.blockers, isNotEmpty);
    });
  });
}
