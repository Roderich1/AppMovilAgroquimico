// F05-SYNC-08 (MOB #72): vínculo explícito de campañas y productos locales con
// las referencias centrales del tenant.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/data/sync/declared_need_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  test(
    'un vínculo confirmado se guarda y sigue vigente tras reabrir la app',
    () async {
      final path = await tempDbPath('binding');
      final fixture = await seedSyncFixture(path: path, bindCatalog: false);
      await fixture.bindings.bindProduct(
        productId: fixture.litreProductId,
        central: centralProduct(),
        tenantId: memberA.tenantId,
      );
      await fixture.database.close();

      final reopened = openDb(path);
      final binding = (await CentralBindingStore(
        reopened,
      ).productBindings()).single;
      expect(binding.productId, fixture.litreProductId);
      expect(binding.productRef, litreRef);
      expect(binding.isValid, isTrue);
    },
  );

  test(
    'nombres coincidentes no crean ningún vínculo sin confirmación',
    () async {
      final fixture = await seedSyncFixture(bindCatalog: false);
      // Producto local con el mismo nombre que el central.
      await fixture.repo.addProduct(name: 'Herbicida central', unit: 'L');
      await fixture.bindings.refreshFrom(referencesWith(), memberA.tenantId);
      expect(await fixture.bindings.productBindings(), isEmpty);
      expect(await fixture.bindings.campaignBindings(), isEmpty);
    },
  );

  test('L local con KG central se rechaza sin conversión', () async {
    final fixture = await seedSyncFixture(bindCatalog: false);
    await expectLater(
      fixture.bindings.bindProduct(
        productId: fixture.litreProductId,
        central: centralProduct(ref: kiloRef, unit: 'KG'),
        tenantId: memberA.tenantId,
      ),
      throwsA(
        isA<CentralBindingException>().having(
          (e) => e.message,
          'message',
          contains('No se convierte'),
        ),
      ),
    );
    expect(await fixture.bindings.productBindings(), isEmpty);
  });

  test('una unidad central sin equivalencia L/KG no se vincula', () async {
    final fixture = await seedSyncFixture(bindCatalog: false);
    await expectLater(
      fixture.bindings.bindProduct(
        productId: fixture.litreProductId,
        central: centralProduct(ref: unitRef, unit: 'unidad'),
        tenantId: memberA.tenantId,
      ),
      throwsA(isA<CentralBindingException>()),
    );
  });

  test(
    'una referencia central no se vincula a dos registros locales',
    () async {
      final fixture = await seedSyncFixture();
      await expectLater(
        fixture.bindings.bindProduct(
          productId: fixture.unboundProductId,
          central: centralProduct(),
          tenantId: memberA.tenantId,
        ),
        throwsA(isA<CentralBindingException>()),
      );
    },
  );

  test(
    'las referencias son del tenant del titular: otro tenant se rechaza',
    () async {
      final fixture = await seedSyncFixture(bindCatalog: false);
      await expectLater(
        fixture.bindings.bindProduct(
          productId: fixture.litreProductId,
          central: centralProduct(),
          tenantId: memberAOtherTenant.tenantId,
        ),
        throwsA(isA<CentralBindingException>()),
      );
    },
  );

  test('sin titular vinculado no se vincula con el sindicato', () async {
    final database = openDb(inMemoryDatabasePath);
    final repo = AgroRepository(database);
    final product = await repo.addProduct(name: 'Herbicida', unit: 'L');
    await expectLater(
      CentralBindingStore(database).bindProduct(
        productId: product,
        central: centralProduct(),
        tenantId: memberA.tenantId,
      ),
      throwsA(isA<CentralBindingException>()),
    );
    expect(await OwnerBindingStore(database).activeBinding(), isNull);
  });

  test('una campaña que no admite aportes no se vincula', () async {
    final fixture = await seedSyncFixture(bindCatalog: false);
    await expectLater(
      fixture.bindings.bindCampaign(
        campaignId: fixture.campaignId,
        central: centralCampaign(accepts: false),
        tenantId: memberA.tenantId,
      ),
      throwsA(isA<CentralBindingException>()),
    );
  });

  test('referencia desaparecida o campaña cerrada: el vínculo queda inválido, sin borrar nada, y bloquea un valor nuevo', () async {
    final fixture = await seedSyncFixture();
    await fixture.needs.declare(
      referenceDate: inCampaign,
      productId: fixture.litreProductId,
      quantityBase: 5000,
    );
    final before = await dumpTables(
      await fixture.database.database,
      except: {'campaign_bindings', 'product_bindings'},
    );

    final changed = await fixture.bindings.refreshFrom(
      referencesWith(campaignAccepts: false, includeLitre: false),
      memberA.tenantId,
    );
    expect(changed, 2);
    final campaign = (await fixture.bindings.campaignBindings()).single;
    expect(campaign.isValid, isFalse);
    expect(campaign.invalidReason, BindingInvalidReason.notAccepting);
    final product = (await fixture.bindings.productBindings()).firstWhere(
      (b) => b.productId == fixture.litreProductId,
    );
    expect(product.invalidReason, BindingInvalidReason.referenceMissing);
    // Ninguna operación local cambió.
    expect(
      await dumpTables(
        await fixture.database.database,
        except: {'campaign_bindings', 'product_bindings'},
      ),
      before,
    );

    final need = (await fixture.needs.needs()).single;
    await expectLater(
      fixture.needs.updateQuantity(need.id, 6000),
      throwsA(isA<BindingRequiredException>()),
    );
    // Retirar sigue permitido (Central admite CANCEL en campaña cerrada).
    await fixture.needs.withdraw(need.id);

    // Si vuelve a cumplir, el vínculo vuelve a estar vigente.
    await fixture.bindings.refreshFrom(referencesWith(), memberA.tenantId);
    expect((await fixture.bindings.campaignBindings()).single.isValid, isTrue);
  });

  test('un producto inactivo en el sindicato invalida el vínculo', () async {
    final fixture = await seedSyncFixture();
    await fixture.bindings.refreshFrom(
      referencesWith(litreActive: false),
      memberA.tenantId,
    );
    final product = (await fixture.bindings.productBindings()).firstWhere(
      (b) => b.productId == fixture.litreProductId,
    );
    expect(product.invalidReason, BindingInvalidReason.inactive);
  });

  test(
    'con una necesidad vigente el vínculo no se corrige ni se quita',
    () async {
      final fixture = await seedSyncFixture();
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 1000,
      );
      await expectLater(
        fixture.bindings.unbindProduct(fixture.litreProductId),
        throwsA(isA<CentralBindingException>()),
      );
      await expectLater(
        fixture.bindings.bindProduct(
          productId: fixture.litreProductId,
          central: centralProduct(ref: otherLitreRef),
          tenantId: memberA.tenantId,
        ),
        throwsA(isA<CentralBindingException>()),
      );
      // Un producto sin necesidades sí se desvincula.
      await fixture.bindings.unbindProduct(fixture.kiloProductId);
      expect(
        (await fixture.bindings.productBindings()).map((b) => b.productId),
        [fixture.litreProductId],
      );
    },
  );

  test(
    'sólo se guardan la referencia, el nombre, la unidad y el estado',
    () async {
      final fixture = await seedSyncFixture();
      final db = await fixture.database.database;
      final columns = {
        for (final row in await db.rawQuery(
          'PRAGMA table_info(product_bindings)',
        ))
          row['name'],
      };
      expect(columns, {
        'product_id',
        'tenant_id',
        'product_ref',
        'central_name',
        'central_unit',
        'base_unit',
        'status',
        'invalid_reason',
        'bound_at',
        'checked_at',
      });
      final campaignColumns = {
        for (final row in await db.rawQuery(
          'PRAGMA table_info(campaign_bindings)',
        ))
          row['name'],
      };
      expect(campaignColumns, {
        'campaign_id',
        'tenant_id',
        'campaign_ref',
        'central_name',
        'status',
        'invalid_reason',
        'bound_at',
        'checked_at',
      });
    },
  );

  test('sin vínculo vigente no se prepara ninguna publicación', () async {
    final fixture = await seedSyncFixture();
    await expectLater(
      fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.unboundProductId,
        quantityBase: 1000,
      ),
      throwsA(isA<BindingRequiredException>()),
    );
    expect(await fixture.outboxRows(), isEmpty);
    expect(
      await (await fixture.database.database).query('declared_needs'),
      isEmpty,
    );
  });
}
