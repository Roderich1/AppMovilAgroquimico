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
import 'package:agroquimicos/voice_draft/interpretation/voice_intent.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

/// Aplicación multiproducto por voz (#15, F09-VOZ-07). Frases propias.
void main() {
  sqfliteFfiInit();

  // Instante de la confirmación: el formulario usa DateTime.now() al enviar y
  // el gateway, su reloj (aquí fijo).
  final now = DateTime(2026, 10, 17, 9);
  const bellator = CatalogEntry(
    id: 1,
    name: 'Bellator',
    unit: CatalogUnit.liter,
  );
  const belator = CatalogEntry(id: 3, name: 'Belator', unit: CatalogUnit.liter);
  const expansive = CatalogEntry(
    id: 2,
    name: 'Expansive',
    unit: CatalogUnit.kilogram,
  );
  const sur = CatalogEntry(id: 12, name: 'Sur', areaM2: 30000);
  const ajeno = CatalogEntry(id: 13, name: 'Ajeno', areaM2: 10000);
  const jose = CatalogEntry(id: 20, name: 'José');
  const campaign = CatalogEntry(id: 30, name: 'Verano 2026');

  const catalog = VoiceCatalog(
    products: [bellator, belator, expansive],
    farms: [sur, ajeno],
    farmOwners: {12: jose},
    activeCampaign: campaign,
  );

  VoiceApplicationDraft interpret(
    String text, {
    VoiceApplicationDraft? current,
  }) => interpretApplication(
    text,
    current ?? VoiceApplicationDraft.start(catalog),
    catalog,
  ).draft;

  group('interpretación del dictado', () {
    test('dos números seguidos dejan la cantidad inválida (M-2)', () {
      final d = interpret(
        'apliqué uno cinco litros de Bellator en el chaco Sur',
      );
      expect(d.lines.single.quantity.status, FieldStatus.invalid);
      expect(d.lines.single.quantity.message, contains('dos números seguidos'));
    });

    test('varias líneas; el chaco fija quién aplica y propone su área', () {
      final d = interpret(
        'apliqué dos litros de Bellator y tres kilos de Expansive en el '
        'chaco Sur',
      );
      expect(d.farm.value, sur);
      expect(d.person, jose);
      expect(d.area.value, 30000);
      expect(d.area.origin, FieldOrigin.preset);
      expect(d.lines.map((l) => l.product.value?.id), [1, 2]);
      expect(d.lines.map((l) => l.quantityBase), [2000, 3000]);
      // Sin el stock leído todavía no se puede confirmar.
      expect(d.stockLoaded, isFalse);
      expect(d.blockers.join(' '), contains('stock'));
    });

    test('con el stock leído: proyección sin escribir y bloqueo si falta', () {
      var d = interpret(
        'apliqué dos litros de Bellator y tres kilos de Expansive en el '
        'chaco Sur',
      );
      d = d.withStock(jose.id, {1: 5000, 2: 1000});
      expect(d.stockAfter(d.lines[0]), 3000);
      expect(d.stockAfter(d.lines[1]), -2000);
      expect(d.blockers.join(' '), contains('stock suficiente'));
      d = d.withStock(jose.id, {1: 5000, 2: 3000});
      expect(d.blockers, isEmpty);
    });

    test('una lectura de stock de otro dueño se descarta', () {
      final d = interpret('apliqué dos litros de Bellator en el chaco Sur');
      expect(identical(d.withStock(999, {1: 9000}), d), isTrue);
    });

    test('un chaco cuyo dueño no puede aplicar bloquea', () {
      final d = interpret('apliqué dos litros de Bellator en el chaco Ajeno');
      expect(d.farm.value, ajeno);
      expect(d.person, isNull);
      expect(d.blockers.join(' '), contains('no puede registrar'));
    });

    test('un producto ambiguo queda visible y bloquea', () {
      final d = interpret('apliqué dos litros de belatorr en el chaco Sur');
      expect(d.lines.single.product.status, FieldStatus.ambiguous);
      expect(d.lines.single.product.candidates.toSet(), {bellator, belator});
      expect(d.blockers.join(' '), contains('elija el producto'));
    });

    test('kilos de un producto en litros bloquea', () {
      final d = interpret('apliqué dos kilos de Bellator en el chaco Sur')
          .withStock(jose.id, {1: 9000});
      expect(d.lines.single.quantityBase, isNull);
      expect(d.blockers.join(' '), contains('unidad'));
    });

    test('una dosis por hectárea no se toma como cantidad aplicada', () {
      final d = interpret(
        'apliqué dos litros por hectárea de Bellator en el chaco Sur',
      );
      expect(d.lines, isEmpty);
    });

    test('nombrar otra vez el producto corrige sólo su cantidad', () {
      var d = interpret('apliqué dos litros de Bellator en el chaco Sur');
      d = interpret('en realidad fueron tres litros de Bellator', current: d);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.quantityBase, 3000);
      expect(d.farm.value, sur);
    });

    test('la cantidad corregida a mano no la cambia un dictado posterior', () {
      var d = interpret('apliqué dos litros de Bellator en el chaco Sur');
      d = d.updateLine(
        d.lines.single.key,
        (l) => l.copyWith(
          quantity: const DraftField.resolved(
            SpokenAmount(1500, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      );
      final r = interpretApplication('cuatro litros de Bellator', d, catalog);
      expect(r.draft.lines.single.quantityBase, 1500);
      expect(r.outcome.keptManual, 1);
    });

    test(
      'aplicar una planificación pide elegir el plan y no elige ninguno',
      () {
        // D-F09-4: el detalle está en voice_plan_application_draft_test.dart.
        final start = VoiceApplicationDraft.start(catalog);
        final r = interpretApplication(
          'quiero aplicar la planificación del chaco Sur',
          start,
          catalog,
        );
        expect(r.planRequested, isTrue);
        expect(r.draft.plan, isNotNull);
        expect(r.draft.plan!.isResolved, isFalse);
        expect(r.draft.planData, isNull);
        expect(r.draft.blockers, isNotEmpty);
      },
    );

    test('otra operación no cambia el borrador', () {
      final start = VoiceApplicationDraft.start(catalog);
      final r = interpretApplication(
        'compré dos litros de Bellator',
        start,
        catalog,
      );
      expect(r.otherIntent, VoiceIntent.purchase);
      expect(identical(r.draft, start), isTrue);
    });
  });

  group('contra la base real: confirmApplication es la autoridad', () {
    late AppDatabase database;
    late Household household;
    late VoiceDraftGateway gateway;

    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      final repo = AgroRepository(database);
      household = await seedHousehold(repo);
      await household.buy(household.titular, 5000);
      gateway = VoiceDraftGateway(repo, clock: () => now);
    });

    const dictation =
        'apliqué dos litros de Glifosato en el chaco titular en media hectárea';

    Future<VoiceDraftController<VoiceApplicationDraft, int>> openDraft() async {
      final catalog = await gateway.applicationCatalog();
      final controller = VoiceDraftController<VoiceApplicationDraft, int>(
        initial: VoiceApplicationDraft.start(catalog),
        commit: gateway.confirmApplication,
      );
      addTearDown(controller.dispose);
      controller.applyVoice((current) {
        final r = interpretApplication(dictation, current, catalog);
        return (r.draft, r.outcome);
      });
      final owner = controller.draft.person!.id;
      final stock = await gateway.availableStock(owner);
      controller.editManually((c) => c.withStock(owner, stock));
      return controller;
    }

    test(
      'el borrador queda listo con persona, área y stock proyectado',
      () async {
        final controller = await openDraft();
        final d = controller.draft;
        expect(d.person!.id, household.titular);
        expect(d.area.value, 5000);
        expect(d.stockAfter(d.lines.single), 3000);
        expect(controller.blockers, isEmpty);
      },
    );

    test(
      'cancelar o liberar no crea aplicación ni toca stock ni plan',
      () async {
        final db = await database.database;
        final before = await dumpTables(db);
        final controller = await openDraft();
        controller.discard();
        expect(await controller.confirm(), isNull);
        expect(await dumpTables(db), before);
        final other = await openDraft();
        other.dispose();
        expect(await dumpTables(db), before);
      },
    );

    test(
      'dos confirmaciones: una sola aplicación y un solo descuento',
      () async {
        final db = await database.database;
        final controller = await openDraft();
        final results = await Future.wait([
          controller.confirm(),
          controller.confirm(),
        ]);
        expect(results.whereType<int>(), hasLength(1));
        expect(await db.query('applications'), hasLength(1));
        expect(await stockByPersonProduct(db), {
          (household.titular, household.product): 3000,
        });
      },
    );

    test('stock cambiado entre la vista previa y la confirmación', () async {
      final controller = await openDraft();
      // Otra operación consume el stock antes de confirmar.
      await household.apply(household.titular, household.titularFarm, 4000);
      final db = await database.database;
      final before = await dumpTables(db);
      expect(await controller.confirm(), isNull);
      expect(controller.phase, DraftPhase.editing);
      expect(controller.error, isNotNull);
      expect(await dumpTables(db), before);
    });

    test('mismo resultado que el formulario manual', () async {
      final controller = await openDraft();
      await controller.confirm();

      final manualDb = openDb(await tempDbPath('manual-application'));
      final manualRepo = AgroRepository(manualDb);
      final manual = await seedHousehold(manualRepo);
      await manual.buy(manual.titular, 5000);
      await manualRepo.confirmApplication(
        ApplicationDraft(
          personId: manual.titular,
          farmId: manual.titularFarm,
          campaignId: manual.campaign,
          appliedAt: now,
          notes: '',
          treatedAreaM2: 5000,
          lines: [
            ApplicationLineDraft(
              productId: manual.product,
              quantityBase: 2000,
              treatedAreaM2: 5000,
              doseBasePerHa: null,
              theoreticalQuantityBase: 0,
            ),
          ],
        ),
      );

      Future<List<Map<String, Object?>>> rows(AppDatabase d, String t) async =>
          [
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
        'inventory_movements',
        'account_transactions',
      ]) {
        expect(
          await rows(database, table),
          await rows(manualDb, table),
          reason: table,
        );
      }
    });

    test('PERSONAL: sólo los chacos del titular y nadie más aplica', () async {
      await OwnerBindingStore(database).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      await OperationModeStore(database)
          .apply(OperationMode.personal, confirmed: true);
      final catalog = await gateway.applicationCatalog();
      expect(catalog.farms.map((f) => f.id), [household.titularFarm]);
      expect(catalog.farmOwners.values.map((p) => p.id).toSet(), {
        household.titular,
      });
    });
  });
}
