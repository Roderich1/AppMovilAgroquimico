// F12-EST-07-MOB (MOB #164): la copia de la estimación en un teléfono Android
// real (SQLite de la plataforma, archivos de la app y pantalla). Las
// respuestas del servidor son SIMULADAS (transporte HTTP de prueba): este
// ensayo no usa un backend real. Datos sintéticos.
//
//   flutter test integration_test/f12_est_07_estimation_device_test.dart -d <id>
//
// Imprime «CAPTURA:<nombre>» y espera unos segundos en cada pantalla que se
// documenta, para que el guion del equipo tome la captura por adb.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/estimation_copy_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/estimation/farmer_estimation.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/presentation/screens/estimation_screen.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const _member = OwnerScope(
  memberId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  tenantId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
);
const _campaign = '7a0b5c1e-2d3f-4a4b-8c5d-6e7f8091a2b3';
const _notice =
    'Referencia calculada a partir de cifras publicadas; no es una necesidad '
    'ni una propuesta, no se suma a ellas y puede no estar actualizada.';

Map<String, Object?> _result(bool estimated, String validityKey) => {
  'product': {
    'product_ref': estimated
        ? '9c2d7e30-4f51-4c6d-8e7f-8091a2b3c4d5'
        : 'ad3e8f41-5062-4d7e-9f80-91a2b3c4d5e6',
    'name': estimated ? 'Herbicida de ensayo' : 'Fungicida de ensayo',
  },
  'base_unit': 'ML',
  'presentation_unit': 'L',
  'status': estimated ? 'ESTIMATED' : 'INSUFFICIENT_DATA',
  'reason_code': estimated ? null : 'SPAN_TOO_SHORT',
  'method': 'SES_NAIVE',
  'run_ref': 'be4f9052-6173-4e8f-a091-a2b3c4d5e6f7',
  'generated_at': '2026-11-02T22:04:26.082Z',
  'span_length': estimated ? 4 : 2,
  'estimate_base': estimated ? '111000.000000' : null,
  'validity_reason': estimated ? null : 'NO_FIGURE',
  validityKey: estimated ? 'CURRENT' : 'NOT_USABLE',
};

Map<String, Object?> _target() => {
  'campaign_ref': _campaign,
  'name': 'Objetivo sintético invierno 2019',
  'status': 'PLANIFICADA',
  'start_date': '2019-09-01T00:00:00.000Z',
  'end_date': null,
};

const _season = {
  'season_ref': 'cf50a163-7284-4f90-b1a2-b3c4d5e6f708',
  'key': 'INVIERNO',
  'definition': 'Temporada sintética INVIERNO',
  'duration_days': 180,
};

Map<String, Object?> _download() => {
  'contract_version': 1,
  'kind': 'ESTIMATION_DOWNLOAD',
  'profile': 'FARMER',
  'scope': {'tenant_ref': _member.tenantId},
  'subject': {'member_ref': _member.memberId, 'role': 'AGRICULTOR'},
  'downloaded_at': '2026-11-02T22:04:34.800Z',
  'target': _target(),
  'season': _season,
  'results': [
    _result(true, 'validity_at_download'),
    _result(false, 'validity_at_download'),
  ],
  'may_be_outdated': true,
  'notice': _notice,
  'storage': {
    'backup': 'EXCLUDED_FROM_PRIVATE_BACKUP',
    'discard_on': ['IDENTITY_CHANGE', 'SIGN_OUT'],
    'replace_only_with': 'NEWER_SAME_SUBJECT_AND_SCOPE',
  },
};

Map<String, Object?> _results() => {
  'contract_version': 1,
  'profile': 'FARMER',
  'scope': {'tenant_ref': _member.tenantId},
  'target': _target(),
  'season': _season,
  'evaluated_at': '2026-11-02T22:05:00.000Z',
  'results': [_result(true, 'validity'), _result(false, 'validity')],
  'notice': _notice,
};

/// Servidor SIMULADO: referencias, resultados y descarga, o un rechazo.
MockClient _central({int? resultsStatus, String? message}) =>
    MockClient((request) async {
      http.Response json(Object body, [int status = 200]) =>
          http.Response.bytes(utf8.encode(jsonEncode(body)), status);
      return switch (request.url.path) {
        '/api/v1/sync/v1/references' => json({
          'contractVersion': 1,
          'campaigns': [
            {
              'campaign_ref': _campaign,
              'name': 'Objetivo sintético invierno 2019',
              'status': 'PLANIFICADA',
              'start_date': '2019-09-01',
              'end_date': null,
              'accepts_contributions': false,
            },
          ],
          'products': [],
        }),
        '/api/v1/estimation/results' =>
          resultsStatus == null
              ? json(_results())
              : json({
                  'statusCode': resultsStatus,
                  'message': message,
                  'error': 'x',
                }, resultsStatus),
        '/api/v1/estimation/download' => json(_download()),
        _ => throw const SocketException('sin conexión (simulada)'),
      };
    });

final _offline = MockClient(
  (_) async => throw const SocketException('sin conexión (simulada)'),
);

Future<String> _dbPath(String name) async {
  final path = p.join(await getDatabasesPath(), 'est164_$name.db');
  await deleteDatabase(path);
  return path;
}

/// Hogar activado con el titular vinculado al Member sintético.
Future<(AppDatabase, OwnerBinding, int)> _phone(String name) async {
  final database = AppDatabase(path: await _dbPath(name));
  final repo = AgroRepository(database);
  final titular = await repo.addPerson(
    name: 'Titular sintético',
    role: PersonRole.family,
  );
  final binding = await OwnerBindingStore(database).bindExistingPerson(
    personId: titular,
    scope: _member,
    installationRef: installationReference(
      '11111111-1111-4111-8111-111111111111',
    ),
  );
  return (database, binding, titular);
}

EstimationIdentity _identity(OwnerBinding binding) => EstimationIdentity(
  memberId: _member.memberId,
  tenantId: _member.tenantId,
  bindingId: binding.id,
);

Future<void> _saveCopy(AppDatabase database, OwnerBinding binding) async {
  final store = EstimationCopyStore(database);
  final grant = await store.grant(_identity(binding));
  await store.save(grant, FarmerDownload.fromJson(_download()), _download());
}

Future<ProviderContainer> _app(
  WidgetTester tester,
  AppDatabase database,
  http.Client transport,
) async {
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      existingSessionStartupProvider.overrideWithValue(
        ExistingSessionStartupState.localSessionAvailable,
      ),
      installationAccessProvider.overrideWith(
        () => FixedInstallationAccess(
          InstallationAccessState.activated,
          scope: _member,
          bound: _member,
        ),
      ),
      apiEndpointConfigProvider.overrideWithValue(
        ApiEndpointConfig(Uri.parse('https://sindicato.example')),
      ),
      authHttpTransportProvider.overrideWithValue(transport),
      syncAccessHolderProvider.overrideWithValue(
        SyncAccessHolder()
          ..accept('token-sintetico', _member.memberId, _member.tenantId),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AgroApp()),
  );
  await _pump(tester);
  container.read(routerProvider).go('/inventario');
  await _pump(tester);
  await tester.tap(find.byKey(const Key('inventory-estimation-entry')));
  await _pump(tester);
  return container;
}

Future<void> _pump(WidgetTester tester, [int rounds = 30]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  await _pump(tester, 5);
  // ignore: avoid_print
  print('CAPTURA:$name');
  await Future<void>.delayed(const Duration(seconds: 6));
}

Future<void> _choose(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('estimation-online')));
  await _pump(tester);
  await tester.tap(find.byKey(const Key('estimation-campaign')));
  await _pump(tester);
  await tester.tap(find.text('Objetivo sintético invierno 2019').last);
  await _pump(tester);
}

Future<int> _rows(AppDatabase database) async =>
    (await (await database.database).query('estimation_copies')).length;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'sin conexión con copia: fechas, vigencia al descargar, aviso y ausencia sin cifra',
    (tester) async {
      final (database, binding, _) = await _phone('copia');
      await _saveCopy(database, binding);
      await _app(tester, database, _offline);
      expect(find.byKey(Key('estimation-copy-$_campaign')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('estimation-figure-copy-Herbicida de ensayo'),
              ),
            )
            .data,
        '111 L (111.000 mL)',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('estimation-figure-copy-Fungicida de ensayo'),
              ),
            )
            .data,
        'Sin cifra',
      );
      expect(find.text('Vigencia al descargar: Vigente'), findsOneWidget);
      expect(
        find.textContaining('Vigente al descargar; puede haber cambiado'),
        findsOneWidget,
      );
      await _capture(tester, '01-sin-conexion-con-copia');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await _pump(tester);
      expect(find.text(estimationReferenceText), findsOneWidget);
      await _capture(tester, '02-sin-conexion-con-copia-pie');
      await database.close();
    },
  );

  testWidgets('sin copia: «sin copia descargada», sin cifras', (tester) async {
    final (database, _, _) = await _phone('sin');
    await _app(tester, database, _offline);
    expect(find.text(estimationNoCopyText), findsOneWidget);
    expect(find.textContaining('111 L'), findsNothing);
    await _capture(tester, '03-sin-copia');
    await database.close();
  });

  testWidgets('con conexión simulada: consulta FARMER y descarga explícita', (
    tester,
  ) async {
    final (database, _, _) = await _phone('online');
    await _app(tester, database, _central());
    await _choose(tester);
    expect(find.text('Vigencia: Vigente'), findsOneWidget);
    expect(find.textContaining('naive'), findsNothing);
    await _capture(tester, '04-consulta-con-conexion');
    await tester.ensureVisible(find.byKey(const Key('estimation-download')));
    await tester.tap(find.byKey(const Key('estimation-download')));
    await _pump(tester);
    expect(find.text('Copia guardada en este teléfono.'), findsOneWidget);
    expect(await _rows(database), 1);
    await _capture(tester, '05-copia-guardada');
    await database.close();
  });

  testWidgets('un 409 de política borra la copia y no la ofrece', (
    tester,
  ) async {
    final (database, binding, _) = await _phone('politica');
    await _saveCopy(database, binding);
    await _app(
      tester,
      database,
      _central(resultsStatus: 409, message: 'POLICY_PENDING'),
    );
    await _choose(tester);
    expect(find.byKey(const Key('estimation-blocked')), findsOneWidget);
    expect(find.textContaining('111 L'), findsNothing);
    expect(await _rows(database), 0);
    await _capture(tester, '06-politica-pendiente');
    await database.close();
  });

  testWidgets(
    'respaldo y restauración en el teléfono: sin la copia, operaciones completas',
    (tester) async {
      final (source, binding, titular) = await _phone('respaldo');
      final repo = AgroRepository(source);
      final supplier = await repo.addSupplier(name: 'Proveedor sintético');
      final campaign = await repo.addCampaign(
        name: 'Campaña sintética',
        start: DateTime.utc(2026, 1, 1),
      );
      final product = await repo.addProduct(name: 'Glifosato sintético');
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: DateTime.utc(2026, 1, 2),
          items: [
            PurchaseItemDraft(
              productId: product,
              quantityBase: 5000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 10000,
              allocations: [
                AllocationDraft(personId: titular, quantityBase: 5000),
              ],
            ),
          ],
        ),
      );
      await _saveCopy(source, binding);
      final sourceDb = await source.database;
      final tables = [
        'persons',
        'purchases',
        'purchase_items',
        'inventory_lots',
        'inventory_movements',
        'owner_bindings',
      ];
      final expected = {
        for (final t in tables) t: await sourceDb.query(t, orderBy: 'id'),
      };
      final invoices = Directory(
        p.join(await getDatabasesPath(), 'est164_facturas'),
      )..createSync(recursive: true);
      final backup = (await BackupService(
        source,
        invoicesDir: () async => invoices,
      ).export()).path;
      expect(await _rows(source), 1, reason: 'el teléfono conserva su copia');

      final packed = ZipDecoder()
          .decodeBytes(File(backup).readAsBytesSync())
          .findFile('database.db')!;
      final bytes = packed.content as List<int>;
      expect(
        latin1
            .decode(bytes, allowInvalid: true)
            .contains('Herbicida de ensayo'),
        isFalse,
      );
      expect(
        latin1.decode(bytes, allowInvalid: true).contains(_campaign),
        isFalse,
      );

      final (target, targetBinding, _) = await _phone('destino');
      await _saveCopy(target, targetBinding);
      await BackupService(
        target,
        invoicesDir: () async => invoices,
      ).restore(backup);
      expect(await _rows(target), 0);
      final restored = await target.database;
      for (final t in tables) {
        expect(await restored.query(t, orderBy: 'id'), expected[t], reason: t);
      }
      // ignore: avoid_print
      print(
        'RESPALDO: ${p.basename(backup)} ${File(backup).lengthSync()} bytes; '
        'database.db sin filas ni bytes de la copia; restaurado sin copia; '
        '${tables.length} tablas de operaciones idénticas',
      );
      await _app(tester, target, _offline);
      expect(find.text(estimationNoCopyText), findsOneWidget);
      await _capture(tester, '07-tras-restaurar-sin-copia');
      await source.close();
      await target.close();
      await File(backup).delete();
    },
  );
}
