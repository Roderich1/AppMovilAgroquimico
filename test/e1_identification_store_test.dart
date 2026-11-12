// Contrato E1 §5: almacén de solicitudes de identificación (una por producto,
// UUID v4 fijo), transiciones de estado, consentimiento de la foto separado y
// vista del sindicato con lista cerrada de claves. Datos sintéticos.
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/sync/identification_request_store.dart';
import 'package:agroquimicos/domain/sync/identification_view.dart';
import 'package:agroquimicos/domain/sync/operation_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e1_identification_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late SyncFixture fixture;
  late IdentificationRequestStore store;
  var now = DateTime.utc(2026, 11, 11, 18, 20);

  setUp(() async {
    now = DateTime.utc(2026, 11, 11, 18, 20);
    fixture = await seedSyncFixture();
    store = IdentificationRequestStore(fixture.database, clock: () => now);
  });

  group('crear', () {
    test(
      'una solicitud por producto, con UUID v4 y los datos actuales',
      () async {
        final request = await store.create(
          productId: fixture.unboundProductId,
          sharePhoto: false,
        );
        expect(uuidV4Lowercase.hasMatch(request.requestId), isTrue);
        expect(request.tenantId, memberA.tenantId);
        expect(request.sentName, 'Adherente local');
        expect(request.sentActiveIngredient, isNull);
        expect(request.sentUnit, 'L');
        expect(request.sendStatus, IdentificationSendStatus.pendingSend);
        expect(request.photoSendStatus, IdentificationPhotoStatus.none);
        expect(request.photoConsentVersion, isNull);
        expect(request.serverStatus, isNull);

        await expectLater(
          store.create(productId: fixture.unboundProductId, sharePhoto: false),
          throwsA(isA<IdentificationRequestException>()),
        );
        expect(await store.all(), hasLength(1));
      },
    );

    test('un producto ya vinculado no se pide', () async {
      await expectLater(
        store.create(productId: fixture.litreProductId, sharePhoto: false),
        throwsA(
          isA<IdentificationRequestException>().having(
            (e) => e.message,
            'message',
            contains('ya está vinculado'),
          ),
        ),
      );
    });

    test('sin titular no se crea', () async {
      final bare = openDb(await tempDbPath('sin_titular'));
      final product = await AgroRepository(bare).addProduct(name: 'Sin dueño');
      await expectLater(
        IdentificationRequestStore(bare)
            .create(productId: product, sharePhoto: false),
        throwsA(isA<IdentificationRequestException>()),
      );
    });

    test('compartir la foto exige que haya foto', () async {
      await expectLater(
        store.create(productId: fixture.unboundProductId, sharePhoto: true),
        throwsA(isA<IdentificationRequestException>()),
      );
      expect(await store.all(), isEmpty);
    });

    test(
      'con foto y casilla marcada registra FOTO-1, la fecha y la huella',
      () async {
        final photos = await photoWorkspace(fixture);
        final sha = await photos.savePhoto(fixture.unboundProductId);
        final request = await store.create(
          productId: fixture.unboundProductId,
          sharePhoto: true,
        );
        expect(request.photoConsentVersion, 'FOTO-1');
        expect(request.photoConsentAt, now.toIso8601String());
        expect(request.photoSha256Consented, sha);
        expect(request.photoSendStatus, IdentificationPhotoStatus.pendingSend);
      },
    );

    test('con foto y casilla sin marcar no comparte nada', () async {
      final photos = await photoWorkspace(fixture);
      await photos.savePhoto(fixture.unboundProductId);
      final request = await store.create(
        productId: fixture.unboundProductId,
        sharePhoto: false,
      );
      expect(request.photoConsentVersion, isNull);
      expect(request.photoSha256Consented, isNull);
      expect(request.photoSendStatus, IdentificationPhotoStatus.none);
    });
  });

  group('transiciones', () {
    late String id;
    setUp(() async {
      id = (await store.create(
        productId: fixture.unboundProductId,
        sharePhoto: false,
      )).requestId;
    });

    test('reintento → recibida; un rechazo no vuelve a pendiente con «Enviar ahora»', () async {
      await store.scheduleRetry(id, 'HTTP_503', now.add(Duration(minutes: 1)));
      var row = (await store.byId(id))!;
      expect(row.sendStatus, IdentificationSendStatus.pendingSend);
      expect(row.sendAttempts, 1);
      expect(row.nextAttemptAt, isNotNull);
      expect(row.lastCode, 'HTTP_503');

      await store.sendNow(id);
      expect((await store.byId(id))!.nextAttemptAt, isNull);

      await store.markReceived(id);
      row = (await store.byId(id))!;
      expect(row.sendStatus, IdentificationSendStatus.received);
      expect(row.sendAttempts, 2);
      expect(row.lastCode, isNull);

      // Desde RECEIVED ya no se rechaza ni se pausa.
      await store.markRejected(id, 'PAYLOAD_INVALID');
      await store.markAuthPaused(id, 'AUTH_REQUIRED');
      expect(
        (await store.byId(id))!.sendStatus,
        IdentificationSendStatus.received,
      );
    });

    test(
      'pausada por autorización vuelve a pendiente con «Enviar ahora»',
      () async {
        await store.markAuthPaused(id, 'AUTH_REQUIRED');
        expect(
          (await store.byId(id))!.sendStatus,
          IdentificationSendStatus.authPaused,
        );
        await store.sendNow(id);
        expect(
          (await store.byId(id))!.sendStatus,
          IdentificationSendStatus.pendingSend,
        );
      },
    );

    test('un rechazo es definitivo', () async {
      await store.markRejected(id, 'UNIT_UNSUPPORTED');
      await store.sendNow(id);
      final row = (await store.byId(id))!;
      expect(row.sendStatus, IdentificationSendStatus.rejected);
      expect(row.lastCode, 'UNIT_UNSUPPORTED');
      expect(
        await store.withPendingWork(memberA.tenantId, includePaused: true),
        isEmpty,
      );
    });
  });

  group('foto: reemplazo y retiro', () {
    late PhotoWorkspace photos;
    late String id;
    setUp(() async {
      photos = await photoWorkspace(fixture);
      await photos.savePhoto(fixture.unboundProductId);
      id = (await store.create(
        productId: fixture.unboundProductId,
        sharePhoto: true,
      )).requestId;
      await store.markReceived(id);
    });

    Future<void> markSent() async {
      final row = (await store.byId(id))!;
      await store.markPhotoSent(id, row.photoSha256Consented!);
    }

    test('«Enviar ahora» sobre una foto con reintento la deja vencida, no definitiva (emulador 2026-11-11)', () async {
      final withPhoto = id;
      await store.markPhotoFailed(
        withPhoto,
        'PHOTO_STORAGE_UNAVAILABLE',
        retryAt: now.add(const Duration(minutes: 5)),
      );
      expect((await store.byId(withPhoto))!.photoRetryable, isTrue);

      await store.sendNow(withPhoto);
      await store.sendNow(withPhoto); // doble toque
      final row = (await store.byId(withPhoto))!;
      expect(row.photoSendStatus, IdentificationPhotoStatus.failed);
      expect(row.photoRetryable, isTrue, reason: 'sigue siendo reintentable');
      expect(row.photoNextAttemptAt, isNotNull);
      expect(
        (await store.withPendingWork(
          memberA.tenantId,
          includePaused: false,
        )).map((r) => r.requestId),
        contains(withPhoto),
      );

      // Un fallo definitivo (sin fecha) sigue sin volver a la cola.
      await store.markPhotoFailed(withPhoto, 'IMAGE_INVALID');
      await store.sendNow(withPhoto);
      expect((await store.byId(withPhoto))!.photoRetryable, isFalse);
    });

    test('reemplazar y enviar: consentimiento nuevo con su fecha y la nueva huella', () async {
      await markSent();
      final first = (await store.byId(id))!;
      final sha = await photos.savePhoto(
        fixture.unboundProductId,
        seed: 1,
        shareWithUnion: true,
      );
      final row = (await store.byId(id))!;
      expect(row.photoSha256Consented, sha);
      expect(row.photoSendStatus, IdentificationPhotoStatus.pendingSend);
      expect(row.photoConsentVersion, 'FOTO-1');
      expect(
        row.photoConsentAt,
        isNot(first.photoConsentAt),
        reason: 'fecha del nuevo consentimiento, no la del primero',
      );
      expect(row.photoAttempts, 0);
    });

    test(
      'reemplazar sólo en el teléfono: el sindicato conserva la anterior',
      () async {
        await markSent();
        final before = (await store.byId(id))!;
        final sha = await photos.savePhoto(
          fixture.unboundProductId,
          seed: 1,
          shareWithUnion: false,
        );
        final row = (await store.byId(id))!;
        expect(row.photoSendStatus, IdentificationPhotoStatus.sent);
        expect(row.photoSha256Consented, before.photoSha256Consented);
        expect(row.photoSha256Consented, isNot(sha));
        expect(row.photoConsentAt, before.photoConsentAt);
      },
    );

    test('reemplazar una foto autorizada que nunca salió, sin enviar: deja de estar pendiente', () async {
      await photos.savePhoto(fixture.unboundProductId, seed: 1);
      expect(
        (await store.byId(id))!.photoSendStatus,
        IdentificationPhotoStatus.none,
      );
    });

    test('quitar una foto enviada deja el retiro pendiente', () async {
      await markSent();
      await photos.repo.removeProductPhoto(fixture.unboundProductId);
      final row = (await store.byId(id))!;
      expect(row.photoSendStatus, IdentificationPhotoStatus.removePending);
      expect(
        (await store.withPendingWork(
          memberA.tenantId,
          includePaused: false,
        )).single.requestId,
        id,
      );
      await store.markPhotoRemoved(id);
      expect(
        (await store.byId(id))!.photoSendStatus,
        IdentificationPhotoStatus.removed,
      );
    });

    test('quitar una foto que nunca salió no pide retirarla', () async {
      await photos.repo.removeProductPhoto(fixture.unboundProductId);
      expect(
        (await store.byId(id))!.photoSendStatus,
        IdentificationPhotoStatus.none,
      );
    });
  });

  group('vista del sindicato', () {
    late String id;
    setUp(() async {
      id = (await store.create(
        productId: fixture.unboundProductId,
        sharePhoto: false,
      )).requestId;
    });

    test(
      'LINKED guarda la referencia, el nombre y la unidad; no vincula',
      () async {
        expect(
          await store.applyServerView(serverView(id, linked: true)),
          isTrue,
        );
        final row = (await store.byId(id))!;
        expect(row.serverStatus, 'LINKED');
        expect(row.serverProductRef, identifiedRef);
        expect(row.serverProductName, 'Herbicida central');
        expect(row.serverProductUnit, 'L');
        expect(row.serverResolution, 'LINKED_EXISTING');
        expect(row.serverCheckedAt, isNotNull);
        expect(row.isLinked, isTrue);
        expect(
          (await fixture.bindings.productBindings()).map((b) => b.productId),
          isNot(contains(fixture.unboundProductId)),
        );
      },
    );

    test('la nota de la Directiva se guarda sin autor', () async {
      await store.applyServerView(serverView(id, note: 'Falta la foto'));
      expect((await store.byId(id))!.serverNote, 'Falta la foto');
    });

    test('una clave desconocida rechaza la vista entera', () async {
      for (final bad in <Map<String, Object?>>[
        serverView(id, extra: {'member_name': 'Persona'}),
        serverView(id, extra: {'id': 'ffffffff-ffff-4fff-8fff-ffffffffffff'}),
        {
          ...serverView(id),
          'photo': {
            'state': 'NONE',
            'sha256': null,
            'consent_version': null,
            'content_type': 'image/jpeg',
          },
        },
        {...serverView(id, linked: true), 'status': 'PENDING'},
        {...serverView(id), 'request_id': id.toUpperCase()},
        {...serverView(id), 'contractVersion': 2},
      ]) {
        await expectLater(
          store.applyServerView(bad),
          throwsA(isA<IdentificationViewFormatException>()),
          reason: '$bad',
        );
      }
      expect((await store.byId(id))!.serverStatus, isNull);
    });

    test('una vista de otra solicitud no toca nada', () async {
      expect(
        await store.applyServerView(
          serverView('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', linked: true),
        ),
        isFalse,
      );
      expect((await store.byId(id))!.serverStatus, isNull);
    });
  });

  test(
    'productsWithRequests: una consulta con productos y solicitudes',
    () async {
      await store.create(
        productId: fixture.unboundProductId,
        sharePhoto: false,
      );
      final items = await store.productsWithRequests();
      expect(
        items.map((i) => i.product['name']),
        (await fixture.repo.products()).map((p) => p['name']),
      );
      final keys = (await fixture.repo.products()).first.keys.toSet();
      for (final item in items) {
        expect(item.product.keys.toSet(), keys);
      }
      expect(
        {for (final item in items) item.product['id']: item.request?.sentName},
        {
          fixture.litreProductId: null,
          fixture.kiloProductId: null,
          fixture.unboundProductId: 'Adherente local',
        },
      );
    },
  );
}
