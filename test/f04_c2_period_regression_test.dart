// D-F04-C2: demostración del fallo previo. Estas pruebas usan sólo la API que
// existía antes de la regla (bindCampaign, refreshFrom, campaignBindings y el
// constructor de CentralCampaign), para poder ejecutarlas tal cual sobre la
// base anterior (`main` ec69ae8): allí FALLAN, porque el vínculo se aceptaba
// o seguía vigente sin mirar las fechas. Sobre esta rama pasan.
//
// Pruebas de HOST (sqflite_common_ffi). No son DEVICE.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/data/sync/central_binding_store.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

CentralCampaign _central({String? endDate, String start = '2026-09-01'}) =>
    CentralCampaign(
      ref: campaignRef,
      name: 'Campaña sindicato 2026',
      status: 'ABIERTA',
      startDate: '${start}T00:00:00.000Z',
      endDate: endDate == null ? null : '${endDate}T00:00:00.000Z',
      acceptsContributions: true,
    );

void main() {
  sqfliteFfiInit();

  test(
    'ANTES: una campaña local sin fin se vinculaba con una central con fin',
    () async {
      final fixture = await seedSyncFixture(bindCatalog: false);
      await expectLater(
        fixture.bindings.bindCampaign(
          campaignId: fixture.campaignId,
          central: _central(endDate: '2026-12-31'),
          tenantId: memberA.tenantId,
        ),
        throwsA(isA<CentralBindingException>()),
      );
      expect(await fixture.bindings.campaignBindings(), isEmpty);
    },
  );

  test(
    'ANTES: una campaña local que empieza antes que la central se vinculaba',
    () async {
      final database = openDb(inMemoryDatabasePath);
      final repo = AgroRepository(database);
      await OwnerBindingStore(database).bindNewPerson(
        name: 'Titular sintético',
        scope: memberA,
        installationRef: installationHere,
      );
      final early = await repo.addCampaign(
        name: 'Empieza antes',
        start: DateTime(2026, 8, 1),
      );
      final bindings = CentralBindingStore(database);
      await expectLater(
        bindings.bindCampaign(
          campaignId: early,
          central: _central(),
          tenantId: memberA.tenantId,
        ),
        throwsA(isA<CentralBindingException>()),
      );
      expect(await bindings.campaignBindings(), isEmpty);
    },
  );

  test('ANTES: al refrescar, una campaña central que ganaba fin dejaba el vínculo vigente', () async {
    final fixture = await seedSyncFixture();
    expect((await fixture.bindings.campaignBindings()).single.isValid, isTrue);
    await fixture.bindings.refreshFrom(
      CentralReferences([_central(endDate: '2026-10-31')], const []),
      memberA.tenantId,
    );
    expect(
      (await fixture.bindings.campaignBindings()).single.isValid,
      isFalse,
      reason:
          'el período local (sin fin) ya no cabe en el central (hasta el '
          '31/10/2026): el vínculo no puede seguir vigente',
    );
  });
}
