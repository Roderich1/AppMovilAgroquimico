// F12-EST-07-MOB (MOB #164): una copia invalidada no reaparece al cerrar y
// volver a abrir la app aunque su borrado haya fallado.
//
// El «arranque nuevo» es otro ProviderContainer y otra instancia de
// AppDatabase sobre el mismo archivo: no se conserva nada en memoria. El
// almacenamiento seguro simulado (`setMockInitialValues`) persiste entre
// arranques, como en el teléfono. Los fallos de SQLite se INYECTAN con
// disparadores que abortan la escritura.
import 'dart:async';
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/estimation_copy_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/estimation/estimation_providers.dart';
import 'package:agroquimicos/services/estimation/estimation_retirement_marker.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f12_estimation_fixtures.dart';

const _results = '/api/v1/estimation/results';
const _download = '/api/v1/estimation/download';

/// Central simulado: cada ruta responde lo que la prueba programe.
class _Central {
  final routes = <String, Future<http.Response> Function()>{};
  late final client = MockClient((request) async {
    final handler = routes[request.url.path];
    if (handler == null) {
      throw http.ClientException('sin conexión (simulada)');
    }
    return handler();
  });

  void json(String path, Object body, {int status = 200}) =>
      routes[path] = () async =>
          http.Response.bytes(utf8.encode(jsonEncode(body)), status);

  void reject(String path, int status, String message) => json(path, {
    'statusCode': status,
    'message': message,
    'error': 'x',
  }, status: status);
}

/// Una ejecución de la app sobre el archivo [path].
class _Run {
  _Run(this.database, this.container, this.central);
  final AppDatabase database;
  final ProviderContainer container;
  final _Central central;

  EstimationService get service => container.read(estimationServiceProvider);

  Future<void> close() async {
    container.dispose();
    await database.close();
  }
}

/// Almacenamiento seguro que no responde (fallo INYECTADO).
class _BrokenMarker implements EstimationRetirementMarker {
  @override
  Future<bool> isPending() =>
      Future.error(StateError('almacén seguro inyectado'));
  @override
  Future<void> setPending() =>
      Future.error(StateError('almacén seguro inyectado'));
  @override
  Future<void> clear() => Future.error(StateError('almacén seguro inyectado'));
}

/// Almacenamiento seguro que se lee pero no admite escribir (INYECTADO).
class _UnwritableMarker implements EstimationRetirementMarker {
  @override
  Future<bool> isPending() async => false;
  @override
  Future<void> setPending() => Future.error(StateError('escritura inyectada'));
  @override
  Future<void> clear() async {}
}

Future<_Run> _start(
  String path, {
  bool online = true,
  EstimationRetirementMarker? marker,
}) async {
  final database = AppDatabase(factory: databaseFactoryFfi, path: path);
  final central = _Central();
  final holder = SyncAccessHolder();
  if (online)
    holder.accept('token-sintetico', memberA.memberId, memberA.tenantId);
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      installationAccessProvider.overrideWith(
        () => FixedInstallationAccess(
          InstallationAccessState.activated,
          scope: memberA,
          bound: memberA,
        ),
      ),
      apiEndpointConfigProvider.overrideWithValue(
        ApiEndpointConfig(Uri.parse('https://sindicato.example')),
      ),
      authHttpTransportProvider.overrideWithValue(central.client),
      syncAccessHolderProvider.overrideWithValue(holder),
      if (marker != null)
        estimationRetirementMarkerProvider.overrideWithValue(marker),
    ],
  );
  container.read(installationAccessProvider);
  return _Run(database, container, central);
}

/// Base en archivo con el titular vinculado al Member A.
Future<String> _phone(String name) async {
  final path = await tempDbPath(name);
  final database = AppDatabase(factory: databaseFactoryFfi, path: path);
  await OwnerBindingStore(database).bindNewPerson(
    name: 'Titular',
    scope: memberA,
    installationRef: installationHere,
  );
  await database.close();
  return path;
}

Future<void> _downloadBoth(_Run run) async {
  run.central.json(_download, farmerDownloadJson());
  await run.service.download(campaignWinter);
  run.central.json(_download, farmerDownloadJson(campaign: campaignSummer));
  await run.service.download(campaignSummer);
}

/// Fallo INYECTADO: SQLite rechaza borrar copias.
Future<void> _breakDelete(AppDatabase database) async =>
    (await database.database).execute(
      'CREATE TRIGGER IF NOT EXISTS t_no_delete_copy BEFORE DELETE ON '
      "estimation_copies BEGIN SELECT RAISE(ABORT, 'borrado inyectado'); END",
    );

Future<void> _repairDelete(AppDatabase database) async =>
    (await database.database).execute(
      'DROP TRIGGER IF EXISTS t_no_delete_copy',
    );

Future<int> _rows(AppDatabase database) async =>
    (await (await database.database).query('estimation_copies')).length;

List<String> _campaigns(List<StoredEstimationCopy> copies) =>
    copies.map((c) => c.download.target.campaignRef).toList()..sort();

Future<void> _rejected(Future<Object?> call) =>
    expectLater(call, throwsA(isA<EstimationRejectedException>()));

void main() {
  sqfliteFfiInit();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('rechazo (409) con el borrado fallido: tras cerrar y abrir sin conexión la copia no se lee, aunque la fila siga', () async {
    final path = await _phone('reinicio_409');
    final first = await _start(path);
    await _downloadBoth(first);
    await _breakDelete(first.database);
    first.central.reject(_results, 409, 'POLICY_PENDING');
    await _rejected(first.service.results(campaignWinter));
    expect(await first.service.readableCopies(), isEmpty);
    await first.close();

    final second = await _start(path, online: false);
    expect(await second.service.readableCopies(), isEmpty);
    expect(
      await _rows(second.database),
      2,
      reason: 'sólo se impidió el acceso',
    );
    await second.close();
  });

  test('404 con el borrado fallido: tras reiniciar esa campaña no se lee; la otra sí', () async {
    final path = await _phone('reinicio_404');
    final first = await _start(path);
    await _downloadBoth(first);
    await _breakDelete(first.database);
    first.central.reject(_download, 404, 'TARGET_CAMPAIGN_NOT_FOUND');
    await _rejected(first.service.download(campaignSummer));
    await first.close();

    final second = await _start(path, online: false);
    expect(_campaigns(await second.service.readableCopies()), [campaignWinter]);
    expect(await _rows(second.database), 2);
    await second.close();
  });

  test('una respuesta pedida antes del rechazo no reactiva la copia, tampoco tras reiniciar', () async {
    final path = await _phone('reinicio_tardia');
    final first = await _start(path);
    await _downloadBoth(first);
    await _breakDelete(first.database);
    final release = Completer<void>();
    first.central.routes[_download] = () async {
      await release.future;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(
            farmerDownloadJson(downloadedAt: '2026-11-03T08:00:00.000Z'),
          ),
        ),
        200,
      );
    };
    final late = first.service.download(campaignWinter);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    first.central.reject(_results, 409, 'POLICY_PENDING');
    await _rejected(first.service.results(campaignWinter));
    release.complete();
    await late;
    expect(await first.service.readableCopies(), isEmpty);
    await first.close();

    final second = await _start(path, online: false);
    expect(await second.service.readableCopies(), isEmpty);
    await second.close();
  });

  test('con el almacenamiento recuperado, el siguiente arranque borra lo retirado; una descarga posterior autorizada vuelve a leerse', () async {
    final path = await _phone('reinicio_limpieza');
    final first = await _start(path);
    await _downloadBoth(first);
    await _breakDelete(first.database);
    first.central.reject(_results, 403, 'Forbidden resource');
    await _rejected(first.service.results(campaignWinter));
    await _repairDelete(first.database);
    await first.close();

    final second = await _start(path, online: false);
    expect(await second.service.readableCopies(), isEmpty);
    expect(await _rows(second.database), 0, reason: 'reintento de limpieza');
    await second.close();

    final third = await _start(path);
    third.central.json(
      _download,
      farmerDownloadJson(downloadedAt: '2026-11-03T09:00:00.000Z'),
    );
    await third.service.download(campaignWinter);
    await third.close();
    final fourth = await _start(path, online: false);
    expect(_campaigns(await fourth.service.readableCopies()), [campaignWinter]);
    await fourth.close();
  });

  test('si SQLite tampoco admite registrar la retirada, tras reiniciar no se muestra ninguna cifra', () async {
    final path = await _phone('reinicio_sin_escritura');
    final first = await _start(path);
    await _downloadBoth(first);
    final db = await first.database.database;
    // Fallo INYECTADO: ninguna escritura en las tablas de la copia.
    for (final table in ['estimation_copies', 'estimation_copy_access']) {
      for (final op in ['INSERT', 'UPDATE', 'DELETE']) {
        await db.execute(
          'CREATE TRIGGER t_no_${op.toLowerCase()}_$table BEFORE $op ON $table '
          "BEGIN SELECT RAISE(ABORT, 'escritura inyectada'); END",
        );
      }
    }
    first.central.reject(_results, 401, 'Unauthorized');
    await _rejected(first.service.results(campaignWinter));
    await first.close();

    final second = await _start(path, online: false);
    expect(await second.service.readableCopies(), isEmpty);
    expect(
      await _rows(second.database),
      2,
      reason: 'sólo se impidió el acceso',
    );
    await second.close();

    // El almacenamiento vuelve a funcionar: el arranque siguiente completa la
    // retirada, quita la marca y borra; una descarga autorizada vuelve a valer.
    final raw = await databaseFactoryFfi.openDatabase(path);
    for (final trigger in await raw.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 't_no_%'",
    )) {
      await raw.execute('DROP TRIGGER ${trigger['name']}');
    }
    await raw.close();
    final third = await _start(path, online: false);
    expect(await third.service.readableCopies(), isEmpty);
    expect(await _rows(third.database), 0);
    expect(
      await const SecureStorageEstimationRetirementMarker().isPending(),
      isFalse,
    );
    await third.close();
    final fourth = await _start(path);
    fourth.central.json(_download, farmerDownloadJson());
    await fourth.service.download(campaignWinter);
    expect(_campaigns(await fourth.service.readableCopies()), [campaignWinter]);
    await fourth.close();
  });

  test('sin contexto local admisible (almacén seguro ilegible) no se muestra ninguna cifra', () async {
    final path = await _phone('reinicio_marca_ilegible');
    final first = await _start(path);
    await _downloadBoth(first);
    await first.close();
    final second = await _start(path, marker: _BrokenMarker());
    expect(await second.service.readableCopies(), isEmpty);
    await expectLater(
      second.service.download(campaignWinter),
      throwsA(isA<EstimationUnavailableException>()),
    );
    await second.close();
  });

  test('si no se puede registrar la retirada ni dejar la marca, la lectura queda bloqueada en esa ejecución', () async {
    final path = await _phone('reinicio_doble_fallo');
    final first = await _start(path, marker: _UnwritableMarker());
    await _downloadBoth(first);
    final db = await first.database.database;
    for (final op in ['INSERT', 'UPDATE']) {
      await db.execute(
        'CREATE TRIGGER t_no_${op.toLowerCase()}_access BEFORE $op ON '
        "estimation_copy_access BEGIN SELECT RAISE(ABORT, 'inyectado'); END",
      );
    }
    first.central.reject(_results, 409, 'POLICY_PENDING');
    await expectLater(
      first.service.results(campaignWinter),
      throwsA(
        isA<EstimationRejectedException>().having(
          (e) => e.discarded,
          'discarded',
          isFalse,
        ),
      ),
    );
    expect(await first.service.readableCopies(), isEmpty);
    await first.close();
  });
}
