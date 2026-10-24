// Fotografías de compras tardías (RF-03, columna
// `late_operation_drafts.invoice_image_path` del esquema v11): viajan en el
// respaldo y se reapuntan al restaurar, igual que las de las compras. Sobre
// la tabla v11 real (composición F03/F04 + F08), también en un borrador ya
// resuelto: `trg_late_drafts_resolved_immutable` no protege esa columna.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  sqfliteFfiInit();
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_f08_drafts_');
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // Temporal.
    }
  });

  /// Borrador tardío insertado con todas las columnas obligatorias de v11.
  /// [confirmed] lo deja resuelto (CONFIRMED) por el titular vinculado.
  Future<void> insertDraft(
    AppDatabase database,
    String photoPath, {
    required int campaignId,
    required String ref,
    ({int personId, int bindingId})? confirmed,
  }) async {
    final db = await database.database;
    await db.insert('late_operation_drafts', {
      'draft_ref': ref,
      'kind': 'PURCHASE',
      'campaign_id': campaignId,
      'effective_date': '2025-06-01',
      'captured_at': '2026-10-23T12:00:00.000Z',
      'reason': 'Factura encontrada tarde (sintético)',
      'payload': jsonEncode({'sintetico': true}),
      'invoice_image_path': photoPath,
      if (confirmed != null) ...{
        'status': 'CONFIRMED',
        'resolved_at': '2026-10-23T12:05:00.000Z',
        'result_operation_id': 1,
        'resolver_person_id': confirmed.personId,
        'resolver_binding_id': confirmed.bindingId,
        'resolver_member_id': memberA.memberId,
        'resolver_tenant_id': memberA.tenantId,
        'resolver_method': 'LOCAL_PIN',
        'resolver_enrolment_ref': 'enrolamiento-sintetico',
      },
    });
  }

  test('las fotos de borradores pendientes y confirmados viajan en el respaldo y se reapuntan al restaurar', () async {
    final sourceInvoices = await Directory(
      p.join(workspace.path, 'origen_facturas'),
    ).create();
    final source = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(workspace.path, 'origen.db'),
    );
    addTearDown(source.close);
    final repo = AgroRepository(source);
    await repo.addProduct(name: 'Producto');
    final campaign = await repo.addCampaign(
      name: 'Campaña histórica',
      start: DateTime.utc(2025),
      end: DateTime.utc(2025, 12, 31),
    );
    final titular = await repo.addPerson(
      name: 'Titular sintético',
      role: PersonRole.admin,
    );
    final binding = await OwnerBindingStore(source).bindExistingPerson(
      personId: titular,
      scope: memberA,
      installationRef: installationHere,
      confirmAdministrator: true,
    );
    final pendingPhoto = File(p.join(sourceInvoices.path, 'tardia_1.jpg'));
    await pendingPhoto.writeAsBytes(List<int>.generate(500, (i) => i % 256));
    final confirmedPhoto = File(p.join(sourceInvoices.path, 'tardia_2.jpg'));
    await confirmedPhoto.writeAsBytes(List<int>.generate(700, (i) => i % 7));
    await insertDraft(
      source,
      pendingPhoto.path,
      campaignId: campaign,
      ref: '00000000-0000-4000-8000-000000000001',
    );
    await insertDraft(
      source,
      confirmedPhoto.path,
      campaignId: campaign,
      ref: '00000000-0000-4000-8000-000000000002',
      confirmed: (personId: titular, bindingId: binding.id),
    );

    final exported = await BackupService(
      source,
      invoicesDir: () async => sourceInvoices,
      exportDirectory: () async => workspace,
    ).export();
    expect(exported.attachmentCount, 2);
    expect(exported.warnings, isEmpty);

    // Otro teléfono, con otra carpeta de facturas.
    final targetInvoices = Directory(
      p.join(workspace.path, 'destino_facturas'),
    );
    final target = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(workspace.path, 'destino.db'),
    );
    addTearDown(target.close);
    await target.database;
    final result = await BackupService(
      target,
      invoicesDir: () async => targetInvoices,
    ).restore(exported.path);
    expect(result.restoredAttachments, 2);
    final rows = await (await target.database).query(
      'late_operation_drafts',
      orderBy: 'draft_ref',
    );
    expect(rows.map((r) => r['status']), ['PENDING', 'CONFIRMED']);
    expect(rows.map((r) => r['invoice_image_path']), [
      p.join(targetInvoices.path, 'tardia_1.jpg'),
      p.join(targetInvoices.path, 'tardia_2.jpg'),
    ]);
    for (final name in ['tardia_1.jpg', 'tardia_2.jpg']) {
      expect(
        await File(p.join(targetInvoices.path, name)).readAsBytes(),
        await File(p.join(sourceInvoices.path, name)).readAsBytes(),
      );
    }
    // El resto del borrador resuelto no cambió.
    expect(rows.last['resolver_enrolment_ref'], 'enrolamiento-sintetico');
    expect(rows.last['result_operation_id'], 1);
  });

  test(
    'sin la tabla (bases anteriores a v11) la exportación no cambia',
    () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        path: p.join(workspace.path, 'v10.db'),
      );
      addTearDown(database.close);
      await AgroRepository(database).addProduct(name: 'Producto');
      await dropReviewAuditSchemaV11(await database.database);
      final exported = await BackupService(
        database,
        exportDirectory: () async => workspace,
      ).export();
      expect(exported.attachmentCount, 0);
    },
  );
}
