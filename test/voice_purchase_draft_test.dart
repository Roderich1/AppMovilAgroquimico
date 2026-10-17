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
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

/// Compra por voz (#11, F09-VOZ-05; EVO-017).
///
/// Frases propias de la prueba; la partición `aceptacion` del corpus no se usa.
void main() {
  sqfliteFfiInit();

  // Instante de la confirmación (el formulario usa DateTime.now() al enviar).
  final confirmedAt = DateTime(2026, 10, 17, 15, 0);

  const bellator = CatalogEntry(
    id: 1,
    name: 'Bellator',
    unit: CatalogUnit.liter,
  );
  const germispa = CatalogEntry(
    id: 2,
    name: 'Germispa',
    unit: CatalogUnit.liter,
  );
  const germi = CatalogEntry(id: 3, name: 'Germi-100', unit: CatalogUnit.liter);
  const expansive = CatalogEntry(
    id: 4,
    name: 'Expansive',
    unit: CatalogUnit.kilogram,
  );
  const agroNorte = CatalogEntry(id: 10, name: 'Agro Norte');
  const jose = CatalogEntry(id: 20, name: 'José');
  const ana = CatalogEntry(id: 21, name: 'Ana');
  const campaign = CatalogEntry(id: 30, name: 'Verano 2026');

  const sharedCatalog = VoiceCatalog(
    products: [bellator, germispa, germi, expansive],
    suppliers: [agroNorte],
    people: [jose, ana],
    activeCampaign: campaign,
  );

  VoicePurchaseDraft interpret(
    String text, {
    VoicePurchaseDraft? current,
    VoiceCatalog catalog = sharedCatalog,
  }) => interpretPurchase(
    text,
    current ?? VoicePurchaseDraft.start(catalog),
    catalog,
  ).draft;

  group('interpretación del dictado', () {
    test('dos números seguidos dejan la cantidad inválida (M-2)', () {
      final d = interpret('compra de uno cinco litros de Bellator');
      final q = d.lines.single.quantity;
      expect(q.status, FieldStatus.invalid);
      expect(q.message, contains('dos números seguidos'));
      expect(q.heard, 'uno cinco litros');
      expect(d.blockers, isNotEmpty);
    });

    test('el ejemplo de EVO-017: cuatro líneas, proveedor y persona', () {
      final d = interpret(
        'Quiero registrar compra: cincuenta litros de Bellator a ciento '
        'ochenta y seis bolivianos el litro, cincuenta litros de Germispa a '
        'ciento ochenta y uno, cincuenta litros de Germi cien a setenta y '
        'cinco y doce kilos de Expansive a ciento ochenta. El proveedor es '
        'Agro Norte y todo queda asignado a José.',
      );
      expect(d.lines.map((l) => l.product.value?.id), [1, 2, 3, 4]);
      expect(d.lines.map((l) => l.quantityBase), [50000, 50000, 50000, 12000]);
      expect(d.supplier.value, agroNorte);
      expect(d.recipient.value, jose);
      expect(d.campaign.value, campaign);
      expect(d.campaign.origin, FieldOrigin.preset);

      // Sólo la primera dice «el litro» y «bolivianos».
      final first = d.lines.first;
      expect(first.price.isResolved, isTrue);
      expect(first.unitPriceMinor, 18600);
      expect(first.currency.value, CurrencyCode.bob);
      for (final line in d.lines.skip(1)) {
        expect(line.price.status, FieldStatus.ambiguous);
        expect(line.currency.status, FieldStatus.missing);
      }
      expect(d.blockers, isNotEmpty);
      expect(d.totalBobMinor, isNull);
    });

    test('dictado en varias partes y total calculado, no dictado', () {
      var d = interpret('compra de cincuenta litros de Bellator');
      d = interpret('a ciento ochenta y seis bolivianos el litro', current: d);
      // Sin producto en el segundo dictado no hay línea que completar: la
      // frase suelta no inventa nada.
      expect(d.lines, hasLength(1));
      expect(d.lines.single.price.status, FieldStatus.missing);

      d = interpret(
        'cincuenta litros de Bellator a ciento ochenta y seis bolivianos el '
        'litro, proveedor Agro Norte, todo para Ana',
        current: d,
      );
      expect(d.lines, hasLength(1));
      expect(d.blockers, isEmpty);
      expect(d.totalBobMinor, 50 * 18600);
    });

    test('nombrar otra vez un producto corrige sólo lo que se dice', () {
      var d = interpret(
        'compra de cincuenta litros de Bellator a 186 bolivianos el litro',
      );
      d = interpret('en realidad son cuarenta litros de Bellator', current: d);
      expect(d.lines, hasLength(1));
      expect(d.lines.single.quantityBase, 40000);
      expect(d.lines.single.unitPriceMinor, 18600);
    });

    test('una edición manual no la cambia un dictado posterior', () {
      var d = interpret('compra de cincuenta litros de Bellator');
      final key = d.lines.single.key;
      d = d.updateLine(
        key,
        (l) => l.copyWith(
          quantity: const DraftField.resolved(
            SpokenQuantity(30000, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      );
      final result = interpretPurchase(
        'sesenta litros de Bellator a 186 bolivianos el litro',
        d,
        sharedCatalog,
      );
      expect(result.draft.lines.single.quantityBase, 30000);
      expect(result.draft.lines.single.unitPriceMinor, 18600);
      expect(result.outcome.keptManual, 1);
    });

    test('un producto que no está en el catálogo queda faltante y bloquea', () {
      final d = interpret(
        'compra de veinte litros de Paraquat a 50 bolivianos el litro, '
        'proveedor Agro Norte, todo para Ana',
      );
      final line = d.lines.single;
      expect(line.product.status, FieldStatus.missing);
      expect(line.product.heard, 'paraquat');
      expect(line.product.message, contains('Catálogos'));
      expect(d.blockers.join(' '), contains('producto'));
    });

    test('un nombre aproximado se propone y no se elige solo', () {
      final d = interpret('compra de diez kilos de expansiv');
      expect(d.lines.single.product.status, FieldStatus.ambiguous);
      expect(d.lines.single.product.candidates, [expansive]);
      expect(d.blockers, isNotEmpty);
    });

    test('litros de un producto que se mide en kilos bloquea', () {
      final d = interpret(
        'compra de doce litros de Expansive a 180 bolivianos el kilo, '
        'proveedor Agro Norte, todo para Ana',
      );
      expect(d.lines.single.quantityBase, isNull);
      expect(d.blockers.join(' '), contains('kilos'));
    });

    test('en dólares exige tipo de cambio antes de confirmar', () {
      var d = interpret(
        'compra de diez litros de Bellator a 25 dólares el litro, proveedor '
        'Agro Norte, todo para Ana',
      );
      expect(d.blockers.join(' '), contains('tipo de cambio'));
      d = interpret('tipo de cambio 6,96', current: d);
      expect(d.exchangeRate.value, 6960000);
      expect(d.blockers, isEmpty);
      final domain = d.toDomain(at: confirmedAt);
      expect(domain.items.single.exchangeRateScaled, 6960000);
      expect(domain.exchangeRateSource, ExchangeRateSource.agreedWithSupplier);
    });

    test('un total dicho no se convierte en precio unitario', () {
      final d = interpret(
        'compra de diez litros de Bellator a 1860 bolivianos en total',
      );
      expect(d.lines.single.price.status, FieldStatus.invalid);
    });

    test('otra operación no toca el borrador', () {
      final start = VoicePurchaseDraft.start(sharedCatalog);
      final result = interpretPurchase(
        'apliqué dos litros de Bellator en el chaco norte',
        start,
        sharedCatalog,
      );
      expect(result.otherIntent, VoiceIntent.application);
      expect(identical(result.draft, start), isTrue);
    });

    test('un pago dictado no prepara nada (pagos por voz fuera de F09)', () {
      final result = interpretPurchase(
        'pago de quinientos bolivianos a Agro Norte',
        VoicePurchaseDraft.start(sharedCatalog),
        sharedCatalog,
      );
      expect(result.otherIntent, VoiceIntent.unsupported);
    });

    test('con una sola persona elegible (PERSONAL) se propone visible', () {
      const personal = VoiceCatalog(
        products: [bellator],
        suppliers: [agroNorte],
        people: [jose],
        activeCampaign: campaign,
      );
      final d = VoicePurchaseDraft.start(personal);
      expect(d.recipient.value, jose);
      expect(d.recipient.origin, FieldOrigin.preset);
    });

    test('sin campaña activa no se puede confirmar', () {
      final d = interpret(
        'compra de diez litros de Bellator a 25 bolivianos el litro, '
        'proveedor Agro Norte, todo para Ana',
        catalog: const VoiceCatalog(
          products: [bellator],
          suppliers: [agroNorte],
          people: [jose, ana],
        ),
      );
      expect(d.blockers.join(' '), contains('campaña'));
    });
  });

  group('contra la base real: sin efectos, escritura única y equivalencia', () {
    late AppDatabase database;
    late Household household;
    late VoiceDraftGateway gateway;
    late int agro;

    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      final repo = AgroRepository(database);
      household = await seedHousehold(repo);
      agro = await repo.addSupplier(name: 'Agro Norte');
      await repo.addProduct(name: 'Bellator');
      await repo.addProduct(name: 'Expansive', unit: 'KG');
      gateway = VoiceDraftGateway(repo, clock: () => confirmedAt);
    });

    const dictation =
        'compra de cincuenta litros de Bellator a 186 bolivianos el litro y '
        'doce kilos de Expansive a 180 bolivianos el kilo, proveedor Agro '
        'Norte, todo para Hermana';

    Future<VoiceDraftController<VoicePurchaseDraft, int>> openDraft() async {
      final catalog = await gateway.purchaseCatalog();
      final controller = VoiceDraftController<VoicePurchaseDraft, int>(
        initial: VoicePurchaseDraft.start(catalog),
        commit: gateway.confirmPurchase,
      );
      addTearDown(controller.dispose);
      controller.applyVoice((current) {
        final r = interpretPurchase(dictation, current, catalog);
        return (r.draft, r.outcome);
      });
      return controller;
    }

    test(
      'cancelar no deja compra, lote, movimiento ni catálogo nuevo',
      () async {
        final db = await database.database;
        final before = await dumpTables(db);
        final controller = await openDraft();
        expect(controller.canConfirm, isTrue);
        controller.discard();
        expect(await controller.confirm(), isNull);
        expect(await dumpTables(db), before);
      },
    );

    test('liberar la pantalla sin confirmar tampoco escribe', () async {
      final db = await database.database;
      final before = await dumpTables(db);
      final controller = await openDraft();
      controller.dispose();
      expect(await dumpTables(db), before);
    });

    test('doble toque: una sola compra', () async {
      final db = await database.database;
      final controller = await openDraft();
      final results = await Future.wait([
        controller.confirm(),
        controller.confirm(),
      ]);
      expect(results.whereType<int>(), hasLength(1));
      final purchases = await db.query('purchases');
      expect(purchases, hasLength(1));
      expect(controller.commitCalls, 1);
    });

    test('mismo resultado que el formulario manual', () async {
      final controller = await openDraft();
      final purchaseId = (await controller.confirm())!;

      // El `PurchaseDraft` que arma el formulario manual
      // (`purchase_form_screen.dart`, al enviar) con los mismos datos y en el
      // mismo instante: `purchaseDate: DateTime.now()` e
      // `invoiceNumber: invoiceNumber.text.trim()`, que con el campo vacío es
      // ''. Otra base en archivo: dos bases `:memory:` comparten instancia.
      final manualDb = openDb(await tempDbPath('manual'));
      final manualRepo = AgroRepository(manualDb);
      final manual = await seedHousehold(manualRepo);
      final manualAgro = await manualRepo.addSupplier(name: 'Agro Norte');
      final manualBellator = await manualRepo.addProduct(name: 'Bellator');
      final manualExpansive = await manualRepo.addProduct(
        name: 'Expansive',
        unit: 'KG',
      );
      expect(manualAgro, agro);
      await manualRepo.confirmPurchase(
        PurchaseDraft(
          supplierId: manualAgro,
          campaignId: manual.campaign,
          purchaseDate: confirmedAt,
          invoiceNumber: '',
          items: [
            PurchaseItemDraft(
              productId: manualBellator,
              quantityBase: 50000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 18600,
              allocations: [
                AllocationDraft(personId: manual.relative, quantityBase: 50000),
              ],
            ),
            PurchaseItemDraft(
              productId: manualExpansive,
              quantityBase: 12000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 18000,
              allocations: [
                AllocationDraft(personId: manual.relative, quantityBase: 12000),
              ],
            ),
          ],
        ),
      );

      final voiceDump = await _business(await database.database);
      final manualDump = await _business(await manualDb.database);
      expect(voiceDump, manualDump);
      expect(voiceDump['purchases']!.single['id'], purchaseId);
      expect(
        voiceDump['purchases']!.single['total_bob_minor'],
        50 * 18600 + 12 * 18000,
      );
    });

    test(
      'la fecha es la de la confirmación: el FIFO respeta el orden real',
      () async {
        // B-100-1 (revisión de A): compra manual a las 10:00 a Bs 100/L y
        // compra por voz a las 15:00 a Bs 200/L del mismo producto y persona.
        // Una aplicación de 5 L debe consumir primero el lote de las 10:00.
        final db = await database.database;
        final repo = AgroRepository(database);
        await household.buy(
          household.relative,
          5000,
          date: DateTime(2026, 10, 17, 10, 0),
        );
        final catalog = await gateway.purchaseCatalog();
        final controller = VoiceDraftController<VoicePurchaseDraft, int>(
          initial: VoicePurchaseDraft.start(catalog),
          commit: gateway.confirmPurchase,
        );
        addTearDown(controller.dispose);
        controller.applyVoice((current) {
          final r = interpretPurchase(
            'compra de cinco litros de Glifosato a 200 bolivianos el litro, '
            'proveedor Agro Norte, todo para Hermana',
            current,
            catalog,
          );
          return (r.draft, r.outcome);
        });
        await controller.confirm();

        final lots = await db.query('inventory_lots', orderBy: 'id');
        expect(
          lots.map((l) => l['acquired_date']).last,
          confirmedAt.toUtc().toIso8601String(),
        );

        await repo.confirmApplication(
          ApplicationDraft(
            personId: household.relative,
            farmId: household.relativeFarm,
            campaignId: household.campaign,
            appliedAt: DateTime(2026, 10, 17, 16, 0),
            lines: [
              ApplicationLineDraft(
                productId: household.product,
                quantityBase: 5000,
              ),
            ],
          ),
        );
        final remaining = {
          for (final row in await db.rawQuery(
            'SELECT l.original_unit_price_minor price, '
            'SUM(m.quantity_signed) left_base FROM inventory_lots l '
            'JOIN inventory_movements m ON m.lot_id = l.id '
            'WHERE l.owner_person_id = ? GROUP BY l.id',
            [household.relative],
          ))
            row['price']: row['left_base'],
        };
        expect(remaining, {10000: 0, 20000: 5000});
      },
    );

    test(
      'PERSONAL: la compra es del titular y una persona dictada se ignora',
      () async {
        await OwnerBindingStore(database).bindExistingPerson(
          personId: household.titular,
          scope: memberA,
          installationRef: installationHere,
        );
        await OperationModeStore(database)
            .apply(OperationMode.personal, confirmed: true);
        final catalog = await gateway.purchaseCatalog();
        expect(catalog.people.map((p) => p.id), [household.titular]);
        expect(catalog.personalOwner?.id, household.titular);
        expect(catalog.loadedMode, OperationMode.personal);

        // Como el formulario de #26, en propio no se elige persona: «todo para
        // Hermana» no cambia la persona y se informa; nada se escribe.
        final db = await database.database;
        final before = await dumpTables(db);
        final r = interpretPurchase(
          dictation,
          VoicePurchaseDraft.start(catalog),
          catalog,
        );
        expect(r.ignoredRecipient, 'hermana');
        expect(r.draft.recipient.value?.id, household.titular);
        expect(r.draft.recipient.origin, FieldOrigin.preset);
        expect(await dumpTables(db), before);

        final controller = VoiceDraftController<VoicePurchaseDraft, int>(
          initial: VoicePurchaseDraft.start(catalog),
          commit: gateway.confirmPurchase,
        );
        addTearDown(controller.dispose);
        controller.applyVoice((current) {
          final r = interpretPurchase(
            'compra de cincuenta litros de Bellator a 186 bolivianos el litro, '
            'proveedor Agro Norte',
            current,
            catalog,
          );
          return (r.draft, r.outcome);
        });
        expect(controller.draft.recipient.origin, FieldOrigin.preset);
        expect(await controller.confirm(), isNotNull);
        final lots = await db.query('inventory_lots');
        expect(lots.map((l) => l['owner_person_id']).toSet(), {
          household.titular,
        });
      },
    );
  });
}

/// Filas de negocio sin identificadores aleatorios ni marcas de tiempo.
Future<Map<String, List<Map<String, Object?>>>> _business(
  DatabaseExecutor db,
) async {
  const tables = [
    'purchases',
    'purchase_items',
    'purchase_allocations',
    'inventory_lots',
    'inventory_movements',
    'account_transactions',
    'products',
    'suppliers',
  ];
  return {
    for (final table in tables)
      table: [
        for (final row in await db.query(table, orderBy: 'id'))
          {
            for (final entry in row.entries)
              if (!entry.key.endsWith('_at') &&
                  !entry.key.contains('uuid') &&
                  !entry.key.contains('global_id'))
                entry.key: entry.value,
          },
      ],
  };
}
