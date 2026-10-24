// RF-13 (F04_RF13_RF03_ACTOR_Y_TARDIAS.md §3) con el respaldo: la auditoría
// privada viaja idéntica a otra instalación, se presenta como autorizada con
// un PIN que no es el de ese teléfono y la operación no se revierte otra vez.
// Un fallo al leerla no se confunde con «sin actor» (revisión de C, R1–R3).
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/presentation/widgets/owner_reversal_flow.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

class _FailingAuditRepository extends AgroRepository {
  _FailingAuditRepository(super.database);
  @override
  Future<Map<String, Object?>?> reversalAudit(String type, int operationId) =>
      Future.error(StateError('lectura fallida'));
}

Future<LocalOwnerCredential> _enrolled(OwnerBindingContext binding) async =>
    (await TestOwnerPin.enrolled(binding)).credential;

Future<OwnerBindingContext?> _bindingOf(AppDatabase database) async {
  final b = await OwnerBindingStore(database).activeBinding();
  return b == null
      ? null
      : OwnerBindingContext(
          bindingId: b.id,
          personId: b.personId,
          scope: b.scope,
        );
}

void main() {
  sqfliteFfiInit();
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_rf13_backup_');
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // Temporal.
    }
  });

  test('the audit travels identical, reads as another PIN, and the operation is not reversed again', () async {
    final source = openDb(p.join(workspace.path, 'origen.db'));
    addTearDown(source.close);
    await seedActivatedInstallation(source);
    late LocalOwnerCredential sourceCredential;
    final repo = AgroRepository(
      source,
      ownerCredential: () => sourceCredential,
    );
    final h = await seedHousehold(repo);
    await h.buy(h.titular, 5000);
    final applicationId = await h.apply(h.titular, h.titularFarm, 2000);
    final sourceBinding = (await _bindingOf(source))!;
    sourceCredential = await _enrolled(sourceBinding);
    await repo.reverseApplication(
      applicationId,
      reason: 'Dosis registrada por error',
      authorization: await sourceCredential.verify(
        pin: '284917',
        purpose: AuthorizationPurpose.reverseApplication,
        subjectRef: 'application:$applicationId',
        binding: sourceBinding,
      ),
    );
    final sourceDb = await source.database;
    final audit = await sourceDb.query('reversal_audit', orderBy: 'id');
    final effects = await sourceDb.query(
      'reversal_audit_effects',
      orderBy: 'id',
    );
    expect(audit, hasLength(1));
    expect(effects, isNotEmpty);

    final invoices = await Directory(p.join(workspace.path, 'facturas'))
        .create();
    final exported = await BackupService(
      source,
      invoicesDir: () async => invoices,
      exportDirectory: () async => workspace,
    ).export();

    final target = openDb(p.join(workspace.path, 'destino.db'));
    addTearDown(target.close);
    await target.database;
    await BackupService(
      target,
      invoicesDir: () async =>
          Directory(p.join(workspace.path, 'destino_facturas')),
    ).restore(exported.path);
    final targetDb = await target.database;
    expect(await targetDb.query('reversal_audit', orderBy: 'id'), audit);
    expect(
      await targetDb.query('reversal_audit_effects', orderBy: 'id'),
      effects,
    );

    // En el otro teléfono el titular configura su propio PIN.
    final targetBinding = await _bindingOf(target);
    expect(targetBinding, isNotNull);
    final targetCredential = await _enrolled(targetBinding!);
    final restored = await AgroRepository(target)
        .reversalAudit('APPLICATION', applicationId);
    expect(
      reversalActorLabel(
        restored,
        currentEnrolmentId: await targetCredential.currentEnrolmentId(),
      ),
      'Autorizada por el titular con un PIN que ya no está configurado en '
      'este teléfono (anterior o de otra instalación) · Dosis registrada por '
      'error',
    );
    expect(
      reversalActorLabel(
        audit.single,
        currentEnrolmentId: await sourceCredential.currentEnrolmentId(),
      ),
      'Autorizada por el titular con el PIN de este teléfono · Dosis '
      'registrada por error',
    );

    final before = await dumpTables(targetDb);
    await expectLater(
      AgroRepository(
        target,
        ownerCredential: () => targetCredential,
      ).reverseApplication(
        applicationId,
        reason: 'Otra vez',
        authorization: await targetCredential.verify(
          pin: '284917',
          purpose: AuthorizationPurpose.reverseApplication,
          subjectRef: 'application:$applicationId',
          binding: targetBinding,
        ),
      ),
      throwsA(
        isA<BusinessRuleException>().having(
          (e) => e.message,
          'message',
          contains('ya fue revertida'),
        ),
      ),
    );
    expect(await dumpTables(targetDb), before);
  });

  test(
    'labels: unreadable audit, no audit and unreadable enrolment are distinct',
    () {
      final audit = {'reason': 'x', 'credential_enrolment_ref': 'e1'};
      expect(
        reversalActorLabel(null, readFailed: true),
        'No se pudo leer quién autorizó esta reversión',
      );
      expect(reversalActorLabel(null), 'Actor no registrado');
      expect(
        reversalActorLabel(audit, enrolmentReadable: false),
        'Autorizada por el titular con su PIN (no se pudo comprobar en este '
        'teléfono) · x',
      );
      expect(
        reversalActorLabel(audit, currentEnrolmentId: null),
        contains('ya no está configurado'),
      );
    },
  );

  testWidgets('a failed audit read is shown as unreadable, not as no actor', (
    tester,
  ) async {
    late AppDatabase database;
    await tester.runAsync(() async {
      database = openDb(inMemoryDatabasePath);
      await database.database;
    });
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(
            _FailingAuditRepository(database),
          ),
          localOwnerCredentialProvider.overrideWithValue(
            TestOwnerPin.unenrolled(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ReversalActorText(operationType: 'PURCHASE', operationId: 1),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(
      find.text('No se pudo leer quién autorizó esta reversión'),
      findsOneWidget,
    );
    expect(find.text('Actor no registrado'), findsNothing);
  });
}
