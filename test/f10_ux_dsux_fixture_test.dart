// DS-UX Mobile (F10 usabilidad, RNF-07): el generador `tool/f10_ux/` deja el
// estado inicial que fijan las tarjetas T1–T6 por las vías de la aplicación,
// con vínculos explícitos válidos, en modalidad propia y compartida; la
// ejecución nominal de T1 y T2 da 6 L de Glifosato Demo y 1,3 L de Bellator;
// el oráculo de T3 lee lo guardado de verdad; y el generador se niega sin
// escribir si la copia, la modalidad o Central no cumplen.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../tool/f10_ux/dsux_fixture.dart';
import 'support/f04_mode_fixtures.dart';

const _campaignRef = '6a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const _glyphosateRef = '7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const _bellatorRef = '8a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const _belatorRef = '9a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

final String _today = localDay(DateTime.now());

/// Referencias tal como las publica Central (F05-SYNC-07), leídas con el mismo
/// `fromJson` que la app.
CentralReferences _references({
  int centralStartOffset = -30,
  int? centralEndOffset,
  bool includeBellator = true,
}) => CentralReferences.fromJson({
  'contractVersion': 1,
  'campaigns': [
    {
      'campaign_ref': _campaignRef,
      'name': campaignName,
      'status': 'ABIERTA',
      'start_date': '${shiftDay(_today, centralStartOffset)}T00:00:00.000Z',
      'end_date': centralEndOffset == null
          ? null
          : '${shiftDay(_today, centralEndOffset)}T00:00:00.000Z',
      'accepts_contributions': true,
    },
  ],
  'products': [
    {
      'product_ref': _glyphosateRef,
      'name': glyphosate,
      'unit': 'L',
      'base_unit': 'ML',
      'is_active': true,
      'linkable': true,
    },
    if (includeBellator)
      {
        'product_ref': _bellatorRef,
        'name': bellator,
        'unit': 'L',
        'base_unit': 'ML',
        'is_active': true,
        'linkable': true,
      },
    // Producto aparte, sin asociar (W3 en la Web): no debe elegirse.
    {
      'product_ref': _belatorRef,
      'name': 'Belator',
      'unit': 'L',
      'base_unit': 'ML',
      'is_active': true,
      'linkable': true,
    },
  ],
});

/// Copia `.f10ux` recién activada: titular vinculado y modalidad elegida.
Future<(String, AppDatabase)> _activated(OperationMode mode) async {
  final path = await tempDbPath('dsux_${mode.code}');
  final database = openDb(path);
  await OwnerBindingStore(database).bindNewPerson(
    name: 'Titular',
    scope: memberA,
    installationRef: installationHere,
  );
  await OperationModeStore(database).apply(mode, confirmed: true);
  return (path, database);
}

Future<Map<String, int>> _ids(AppDatabase database, String table) async => {
  for (final row in await (await database.database).query(table))
    row['name']! as String: row['id']! as int,
};

Future<int> _balance(AppDatabase database, int productId) async =>
    ((await (await database.database).rawQuery(
          'SELECT COALESCE(SUM(quantity_signed),0) s FROM inventory_movements '
          'WHERE product_id = ?',
          [productId],
        )).single['s']
        as int?) ??
    0;

void main() {
  sqfliteFfiInit();

  test('oráculo de T3: lo guardado en T1 y T2 decide el saldo esperado', () {
    expect(nominalBalanceAfterT2, {glyphosate: 6000, bellator: 1300});
    for (final (purchase, application, expected) in [
      (500, 200, 1300),
      (0, 200, 800),
      (500, 0, 1500),
      (0, 0, 1000),
    ]) {
      expect(
        expectedBalanceBase(
          openingBase: openingStockBase[bellator]!,
          savedPurchasesBase: purchase,
          savedApplicationsBase: application,
        ),
        expected,
      );
    }
  });

  for (final modality in DsuxModality.values) {
    test('siembra ${modality.name.toUpperCase()}: estado inicial, vínculos, '
        'T1–T2 nominales, T4 y T6', () async {
      final (path, database) = await _activated(modality.mode);
      final result = await seedDsux(
        database: database,
        sessionDay: _today,
        modality: modality,
        references: _references(),
      );
      final db = await database.database;
      final repo = AgroRepository(database);
      final owner = (await repo.operatingContext()).ownerPersonId!;
      final products = await _ids(database, 'products');
      final farms = await _ids(database, 'farms');
      final persons = await _ids(database, 'persons');

      // Estado inicial.
      expect(result['integrity_check'], 'ok');
      expect(products.keys, unorderedEquals([glyphosate, bellator]));
      expect(farms.keys, unorderedEquals([northFarm, southFarm]));
      for (final farm in await db.query('farms')) {
        expect(farm['owner_person_id'], owner);
      }
      expect(
        persons.keys,
        modality == DsuxModality.compartida
            ? unorderedEquals(['Titular', relativeName])
            : ['Titular'],
      );
      expect(await _balance(database, products[glyphosate]!), 5000);
      expect(await _balance(database, products[bellator]!), 1000);
      final campaign = (await db.query('campaigns')).single;
      expect(campaign['name'], campaignName);
      expect(campaign['status'], 'ACTIVE');
      final period = CampaignPeriod.fromRow(campaign);
      expect(period.startDay, shiftDay(_today, -14));
      expect(period.endDay, shiftDay(_today, 30));
      expect(period.contains(_today), isTrue);
      for (final purchase in await db.query('purchases')) {
        expect(
          storedLocalDay(purchase['purchase_date']! as String),
          shiftDay(_today, -10),
        );
      }
      expect(
        await db.query('purchase_allocations', columns: ['person_id']),
        everyElement(containsPair('person_id', owner)),
      );
      // Vínculos explícitos y válidos, con Bellator (no «Belator»).
      final campaignBinding = (await db.query('campaign_bindings')).single;
      expect(campaignBinding['status'], 'VALID');
      expect(campaignBinding['campaign_ref'], _campaignRef);
      expect(
        {
          for (final row in await db.query('product_bindings'))
            row['product_id']! as int: row['product_ref'],
        },
        {
          products[glyphosate]!: _glyphosateRef,
          products[bellator]!: _bellatorRef,
        },
      );
      expect(result['sync_outbox_after'], result['sync_outbox_before']);
      expect(result['declared_needs'], 0);

      // T1 nominal (compra de hoy). En compartida, Bellator se asigna al
      // familiar para comprobar el saldo por persona del oráculo.
      final supplier = (await _ids(database, 'suppliers'))[supplierName]!;
      final bellatorHolder = modality == DsuxModality.compartida
          ? persons[relativeName]!
          : owner;
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign['id']! as int,
          purchaseDate: DateTime.now(),
          items: [
            for (final name in [glyphosate, bellator])
              PurchaseItemDraft(
                productId: products[name]!,
                quantityBase: nominalT1PurchaseBase[name]!,
                currency: CurrencyCode.bob,
                originalUnitPriceMinor: openingUnitPriceMinor[name]!,
                allocations: [
                  AllocationDraft(
                    personId: name == bellator ? bellatorHolder : owner,
                    quantityBase: nominalT1PurchaseBase[name]!,
                  ),
                ],
              ),
          ],
        ),
      );
      // T2 nominal (aplicación de hoy en Norte, por el titular).
      await repo.confirmApplication(
        ApplicationDraft(
          personId: owner,
          farmId: farms[northFarm]!,
          campaignId: campaign['id']! as int,
          appliedAt: DateTime.now(),
          lines: [
            for (final name in [glyphosate, bellator])
              ApplicationLineDraft(
                productId: products[name]!,
                quantityBase: nominalT2ApplicationBase[name]!,
              ),
          ],
        ),
      );
      expect(await _balance(database, products[glyphosate]!), 6000);
      expect(await _balance(database, products[bellator]!), 1300);

      // T3: el oráculo lee una copia y explica el saldo guardado.
      final oracle = await dsuxOracleFromFile(path);
      final bellatorOracle =
          (oracle['products']! as Map)[bellator]! as Map<String, Object?>;
      expect(bellatorOracle['opening_base'], 1000);
      expect(bellatorOracle['saved_purchases_base'], 500);
      expect(bellatorOracle['saved_applications_base'], 200);
      expect(bellatorOracle['expected_balance_base'], 1300);
      expect(bellatorOracle['balance_base'], 1300);
      expect(bellatorOracle['consistent'], isTrue);
      expect(
        bellatorOracle['by_person_base'],
        modality == DsuxModality.compartida
            ? {'Titular': 800, relativeName: 500}
            : {'Titular': 1300},
      );

      // T4: la necesidad se declara con los vínculos sembrados.
      final outboxBefore = (await db.query('sync_outbox')).length;
      await DeclaredNeedStore(database).declare(
        referenceDate: DateTime.now(),
        productId: products[glyphosate]!,
        quantityBase: 20000,
      );
      expect((await db.query('sync_outbox')).length, outboxBefore + 1);
      final needs = (await dsuxOracleFromFile(path))['declared_needs']! as List;
      expect(needs.single, containsPair('quantity_base', 20000));
      expect(needs.single, containsPair('campaign', campaignName));

      // T6: 5 L de Bellator nunca alcanza (máximo posible 1,5 L) y no guarda.
      final applications = (await db.query('applications')).length;
      await expectLater(
        repo.confirmApplication(
          ApplicationDraft(
            personId: owner,
            farmId: farms[northFarm]!,
            campaignId: campaign['id']! as int,
            appliedAt: DateTime.now(),
            lines: [
              ApplicationLineDraft(
                productId: products[bellator]!,
                quantityBase: 5000,
              ),
            ],
          ),
        ),
        throwsA(isA<BusinessRuleException>()),
      );
      expect((await db.query('applications')).length, applications);
      expect(await _balance(database, products[bellator]!), 1300);
    });
  }

  test('el fin local se acota al fin central si éste es anterior', () async {
    final (_, database) = await _activated(OperationMode.personal);
    await seedDsux(
      database: database,
      sessionDay: _today,
      modality: DsuxModality.propia,
      references: _references(centralEndOffset: 20),
    );
    final period = CampaignPeriod.fromRow(
      (await (await database.database).query('campaigns')).single,
    );
    expect(period.endDay, shiftDay(_today, 20));
    final binding = (await (await database.database).query('campaign_bindings'))
        .single;
    expect(binding['status'], 'VALID');
  });

  group('se niega sin escribir nada', () {
    Future<void> expectRefused(
      AppDatabase database, {
      DsuxModality modality = DsuxModality.propia,
      CentralReferences? references,
      String? sessionDay,
      Pattern? message,
    }) async {
      final db = await database.database;
      final before = await dumpTables(db);
      await expectLater(
        seedDsux(
          database: database,
          sessionDay: sessionDay ?? _today,
          modality: modality,
          references: references ?? _references(),
        ),
        throwsA(
          isA<DsuxRefused>().having(
            (e) => e.message,
            'message',
            message == null ? anything : contains(message),
          ),
        ),
      );
      expect(await dumpTables(db), before);
    }

    test('modalidad distinta de la elegida al activar', () async {
      final (_, database) = await _activated(OperationMode.shared);
      await expectRefused(database, message: 'modalidad');
    });

    test('copia con negocio previo', () async {
      final (_, database) = await _activated(OperationMode.personal);
      await AgroRepository(database).addProduct(name: 'Otro');
      await expectRefused(database, message: 'products ya tiene filas');
    });

    test('la campaña central empieza después de sesión − 14', () async {
      final (_, database) = await _activated(OperationMode.personal);
      await expectRefused(
        database,
        references: _references(centralStartOffset: -10),
        message: 'Central debe publicar',
      );
    });

    test(
      'falta un producto en Central («Belator» no sustituye a Bellator)',
      () async {
        final (_, database) = await _activated(OperationMode.personal);
        await expectRefused(
          database,
          references: _references(includeBellator: false),
          message: '«Bellator»',
        );
      },
    );

    test('la compra inicial sería futura', () async {
      final (_, database) = await _activated(OperationMode.personal);
      await expectRefused(
        database,
        sessionDay: shiftDay(_today, 11),
        message: 'sería futura',
      );
    });

    test('el día de sesión ya pasó', () async {
      final (_, database) = await _activated(OperationMode.personal);
      await expectRefused(
        database,
        sessionDay: shiftDay(_today, -1),
        message: 'ya pasó',
      );
    });
  });

  test('parámetros: día y modalidad se validan', () {
    expect(parseSessionDay('2026-10-20'), '2026-10-20');
    expect(() => parseSessionDay('2026-02-30'), throwsA(isA<DsuxRefused>()));
    expect(() => parseSessionDay('20/10/2026'), throwsA(isA<DsuxRefused>()));
    expect(DsuxModality.parse('compartida'), DsuxModality.compartida);
    expect(DsuxModality.parse('INDIVIDUAL'), DsuxModality.propia);
    expect(() => DsuxModality.parse('mixta'), throwsA(isA<DsuxRefused>()));
  });
}
