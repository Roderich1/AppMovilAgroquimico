import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// UIBUG-059 — **una campaña cerrada es terminal.**
///
/// Decisión del propietario: en operación normal el ciclo es monótono. Una
/// campaña `CLOSED` representa un periodo contable ya rendido y no puede
/// volver a activarse desde la aplicación. La protección vive en el
/// repositorio, no sólo en la pantalla, para que también cubra una interfaz
/// desactualizada, una doble ejecución o cualquier camino indirecto futuro.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late AgroRepository repo;

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);
  });
  tearDown(() => database.close());

  Future<String?> statusOf(int id) async =>
      (await (await database.database).query(
            'campaigns',
            where: 'id=?',
            whereArgs: [id],
          )).single['status']
          as String?;

  test('la primera campaña nace ACTIVE y opera con normalidad', () async {
    final campaign = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    expect(await statusOf(campaign), 'ACTIVE');
    expect((await repo.activeCampaign())!['id'], campaign);

    // Y admite movimientos: es la campaña de trabajo.
    final person = await repo.addPerson(name: 'José', role: PersonRole.family);
    final farm = await repo.addFarm(
      ownerId: person,
      name: 'Chaco',
      areaM2: 100000,
    );
    final product = await repo.addProduct(name: 'Glifosato');
    expect(
      await repo.addPlanMulti(
        farmId: farm,
        campaignId: campaign,
        areaM2: 100000,
        items: [PlanItemDraft(productId: product, doseBasePerHa: 1000)],
      ),
      greaterThan(0),
    );
  });

  test('sólo puede haber una campaña activa', () async {
    final first = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    final second = await repo.addCampaign(
      name: 'Invierno',
      start: DateTime.utc(2026, 6, 1),
    );
    expect(await statusOf(first), 'ACTIVE');
    expect(await statusOf(second), 'PLANNED');

    // Activar la segunda sin decir qué hacer con la primera es un conflicto
    // explícito, no un cambio silencioso.
    await expectLater(
      repo.activateCampaign(second),
      throwsA(isA<CampaignConflictException>()),
    );

    await repo.activateCampaign(second, closeCurrent: true);
    expect(await statusOf(first), 'CLOSED');
    expect(await statusOf(second), 'ACTIVE');
    expect(
      (await repo.campaigns()).where((row) => row['status'] == 'ACTIVE'),
      hasLength(1),
    );
  });

  test('cerrar una campaña activa funciona y la deja CLOSED', () async {
    final campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    await repo.closeCampaign(campaign);
    expect(await statusOf(campaign), 'CLOSED');
    expect(await repo.activeCampaign(), isNull);
  });

  group('CLOSED es terminal', () {
    late int closed;

    setUp(() async {
      closed = await repo.addCampaign(
        name: 'Verano',
        start: DateTime.utc(2026, 1, 1),
      );
      await repo.closeCampaign(closed);
    });

    test('el repositorio rechaza reactivarla', () async {
      await expectLater(
        repo.activateCampaign(closed),
        throwsA(
          isA<BusinessRuleException>().having(
            (error) => error.toString(),
            'mensaje',
            allOf(contains('cerrada'), contains('campaña nueva')),
          ),
        ),
      );
      expect(await statusOf(closed), 'CLOSED');
    });

    test(
      'tampoco con closeCurrent, que era la vía de cambio de campaña',
      () async {
        await expectLater(
          repo.activateCampaign(closed, closeCurrent: true),
          throwsA(isA<BusinessRuleException>()),
        );
        expect(await statusOf(closed), 'CLOSED');
      },
    );

    test('un intento repetido no la reabre ni deja dos activas', () async {
      final other = await repo.addCampaign(
        name: 'Invierno',
        start: DateTime.utc(2026, 6, 1),
      );
      await repo.activateCampaign(other);

      for (var attempt = 0; attempt < 3; attempt++) {
        await expectLater(
          repo.activateCampaign(closed, closeCurrent: true),
          throwsA(isA<BusinessRuleException>()),
        );
      }
      expect(await statusOf(closed), 'CLOSED');
      expect(await statusOf(other), 'ACTIVE');
      expect(
        (await repo.campaigns()).where((row) => row['status'] == 'ACTIVE'),
        hasLength(1),
      );
    });

    test('cerrar de nuevo una campaña cerrada se rechaza', () async {
      await expectLater(
        repo.closeCampaign(closed),
        throwsA(isA<BusinessRuleException>()),
      );
    });

    test('deja de admitir movimientos nuevos', () async {
      final person = await repo.addPerson(
        name: 'José',
        role: PersonRole.family,
      );
      final farm = await repo.addFarm(
        ownerId: person,
        name: 'Chaco',
        areaM2: 100000,
      );
      final product = await repo.addProduct(name: 'Glifosato');
      await expectLater(
        repo.addPlanMulti(
          farmId: farm,
          campaignId: closed,
          areaM2: 100000,
          items: [PlanItemDraft(productId: product, doseBasePerHa: 1000)],
        ),
        throwsA(isA<BusinessRuleException>()),
      );
    });
  });

  test('sigue CLOSED tras cerrar y reabrir la aplicación', () async {
    final directory = await Directory.systemTemp.createTemp('agro_campaign_');
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'campaigns.db');

    final first = AppDatabase(factory: databaseFactoryFfi, path: path);
    final firstRepo = AgroRepository(first);
    final campaign = await firstRepo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    await firstRepo.closeCampaign(campaign);
    await first.close();

    final second = AppDatabase(factory: databaseFactoryFfi, path: path);
    final secondRepo = AgroRepository(second);
    addTearDown(second.close);
    expect((await secondRepo.campaigns()).single['status'], 'CLOSED');
    await expectLater(
      secondRepo.activateCampaign(campaign),
      throwsA(isA<BusinessRuleException>()),
    );
  });

  test('una campaña archivada sigue sin poder activarse', () async {
    // Regla anterior, que se conserva: sólo cambia que ahora CLOSED también
    // está protegida.
    final campaign = await repo.addCampaign(
      name: 'Verano',
      start: DateTime.utc(2026, 1, 1),
    );
    await repo.archiveCatalog('campaigns', campaign);
    await expectLater(
      repo.activateCampaign(campaign),
      throwsA(isA<BusinessRuleException>()),
    );
  });
}
