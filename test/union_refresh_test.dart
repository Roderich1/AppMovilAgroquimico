import 'dart:async';
import 'dart:convert';

import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/local_data_providers.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/auth_v2_api.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/auth/refresh_guard.dart';
import 'package:agroquimicos/services/auth/remote_session_providers.dart';
import 'package:agroquimicos/services/auth/secure_session_store.dart';
import 'package:agroquimicos/services/sync/joint_purchase_api.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:agroquimicos/services/sync/union_refresh.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e2_joint_purchase_fixtures.dart';
import 'support/e12_activation_harness.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late SyncFixture fixture;
  late JointPurchaseStore store;
  late SyncAccessHolder access;
  late DateTime clock;
  final sent = <String>[];
  final date = DateTime.utc(2026, 11, 11, 18, 20);

  setUp(() async {
    sent.clear();
    fixture = await seedSyncFixture();
    store = JointPurchaseStore(fixture.database, clock: () => date);
    clock = date;
    access = SyncAccessHolder(clock: () => clock)
      ..accept('prueba', memberA.memberId, memberA.tenantId);
  });

  ProviderContainer scope(
    Future<http.Response> Function(http.Request) handler, {
    StoredSession? session,
    _Guard? guard,
    E12CommitPort? commit,
  }) {
    final client = MockClient((request) {
      sent.add(request.method);
      return handler(request);
    });
    final config = ApiEndpointConfig(Uri.parse('https://sindicato.example'));
    final httpClient = AuthHttpClient(config: config, client: client);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(fixture.database),
        repositoryProvider.overrideWithValue(fixture.repo),
        syncAccessHolderProvider.overrideWithValue(access),
        centralBindingStoreProvider.overrideWithValue(fixture.bindings),
        jointPurchaseStoreProvider.overrideWithValue(store),
        jointPurchaseApiProvider.overrideWithValue(
          JointPurchaseApi(json: httpClient),
        ),
        syncApiProvider.overrideWithValue(SyncApi(httpClient)),
        if (session != null) ...[
          installationRefProvider.overrideWithValue(e12InstallationRef),
          installationAccessProvider.overrideWith(
            () => FixedInstallationAccess(InstallationAccessState.activated),
          ),
          storedSessionReaderProvider.overrideWithValue(
            () async => SessionReadResult(
              SessionReadStatus.available,
              session: session,
            ),
          ),
          refreshGuardProvider.overrideWithValue(guard ?? _Guard()),
          secureSessionCommitProvider.overrideWithValue(
            commit ?? E12CommitPort(),
          ),
          apiEndpointConfigProvider.overrideWithValue(config),
          authV2ApiProvider.overrideWithValue(AuthV2Api(httpClient)),
        ],
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('renueva una sola vez, consulta y mantiene deshabilitado el acceso de envío', () async {
    await fixture.owners.recordActivatedInstallation(
      sessionScope: memberA,
      installationRef: e12InstallationRef,
    );
    await seedCalls(store, memberA, [callJson()]);
    final order = await store.confirm(
      callId: callId,
      lines: {litreRef: 25000},
      consentVersion: jointPurchaseOrderConsentVersion,
      consentAcceptedAt: date,
    );
    await store.markAuthPaused(order, 'AUTH_REQUIRED');
    clock = clock.add(const Duration(minutes: 11));
    final backend = E12Backend();
    final paths = <String>[];
    final entered = Completer<void>();
    final proceed = Completer<void>();
    final guard = _Guard();
    final commit = E12CommitPort();
    final container = scope(
      (request) async {
        paths.add(request.url.path);
        switch (request.url.path) {
          case '/api/v1/health':
            entered.complete();
            await proceed.future;
            return jsonResponse({
              'status': 'ok',
              'service': 'agrochemical-inventory-api',
            }, 200);
          case '/api/v1/auth/v2/refresh':
            expect(guard.quarantined, isTrue);
            final context = await backend.respond(
              http.Request(
                'GET',
                Uri.https('sindicato.example', '/api/v1/auth/v2/me'),
              ),
            );
            return jsonResponse({
              'contractVersion': 2,
              'accessToken': e12Access,
              'refreshToken': e12Refresh,
              'refreshTransport': 'BODY',
              'sessionExpiresAt': _expiry,
              'context': jsonDecode(context.body),
            }, 200);
          case '/api/v1/me/joint-purchase-calls':
            expect(commit.calls, 1);
            expect(guard.quarantined, isFalse);
            expect(request.headers['authorization'], 'Bearer $e12Access');
            return jsonResponse(
              listJson([callJson(name: 'Lista renovada')]),
              200,
            );
          default:
            fail('Se esperaba únicamente la renovación y la consulta');
        }
      },
      session: _stored(),
      guard: guard,
      commit: commit,
    );
    final refresh = container.read(unionRefreshProvider.notifier);
    final first = refresh.refresh({UnionFeed.calls}, inForeground: () => true);
    await entered.future;
    final second = refresh.refresh(
      {UnionFeed.calls},
      inForeground: () => true,
      reconnect: true,
    );
    proceed.complete();
    await Future.wait([first, second]);
    expect(paths, [
      '/api/v1/health',
      '/api/v1/auth/v2/refresh',
      '/api/v1/me/joint-purchase-calls',
    ]);
    expect((await store.call(callId))?.name, 'Lista renovada');
    expect((await store.op(order.operationId))?.sendStatus, 'AUTH_PAUSED');
    expect(access.current, isNull);
    expect(access.forUnionReads?.accessToken, e12Access);
    await fixture.database.replacement.replace(() async {});
    expect(access.forUnionReads, isNull);
  });

  for (final (name, session) in [
    ('otro titular', _stored(owner: memberB)),
    ('otro sindicato', _stored(owner: memberAOtherTenant)),
    ('otra instalación', _stored(clientId: e12RegistrationId)),
  ]) {
    test('no renueva con $name', () async {
      clock = clock.add(const Duration(minutes: 11));
      await fixture.owners.recordActivatedInstallation(
        sessionScope: memberA,
        installationRef: e12InstallationRef,
      );
      final container = scope(
        (_) => throw StateError('No debe usar la red'),
        session: session,
      );
      await container.read(unionRefreshProvider.notifier).refresh({
        UnionFeed.calls,
      }, inForeground: () => true);
      expect(sent, isEmpty);
      expect(
        container.read(unionRefreshProvider)[UnionFeed.calls]?.issue,
        UnionReadIssue.access,
      );
    });
  }

  test('reconexión y actualización manual comparten lectura sin reanudar un pedido', () async {
    await seedCalls(store, memberA, [callJson(name: 'Copia local')]);
    final order = await store.confirm(
      callId: callId,
      lines: {litreRef: 25000},
      consentVersion: jointPurchaseOrderConsentVersion,
      consentAcceptedAt: date,
    );
    await store.markAuthPaused(order, 'AUTH_REQUIRED');
    final requested = Completer<void>();
    final response = Completer<http.Response>();
    final container = scope((_) {
      if (!requested.isCompleted) requested.complete();
      return response.future;
    });
    final refresh = container.read(unionRefreshProvider.notifier);
    await refresh.refresh({UnionFeed.calls}, connected: false);
    expect(sent, isEmpty);
    expect((await store.call(callId))?.name, 'Copia local');
    expect(
      container.read(unionRefreshProvider)[UnionFeed.calls]?.issue,
      UnionReadIssue.offline,
    );

    final automatic = refresh.refresh({UnionFeed.calls}, reconnect: true);
    await requested.future;
    final manual = refresh.refresh({UnionFeed.calls}, manual: true);
    response.complete(
      jsonResponse(listJson([callJson(name: 'Lista nueva')]), 200),
    );
    await Future.wait([automatic, manual]);
    expect(sent, ['GET']);
    expect((await store.call(callId))?.name, 'Lista nueva');
    expect((await store.op(order.operationId))?.sendStatus, 'AUTH_PAUSED');
    expect(
      container.read(unionRefreshProvider)[UnionFeed.calls]?.lastRead,
      isNotNull,
    );
  });

  test('una respuesta anterior a una restauración no se aplica', () async {
    await seedCalls(store, memberA, [callJson(name: 'Copia local')]);
    final requested = Completer<void>();
    final response = Completer<http.Response>();
    final container = scope((_) {
      requested.complete();
      return response.future;
    });
    final refresh = container.read(unionRefreshProvider.notifier);
    final pending = refresh.refresh({UnionFeed.calls}, reconnect: true);
    await requested.future;
    await fixture.database.replacement.replace(() async {});
    response.complete(
      jsonResponse(listJson([callJson(name: 'Respuesta anterior')]), 200),
    );
    await pending;
    expect((await store.call(callId))?.name, 'Copia local');
  });

  test(
    'las referencias validadas quedan disponibles al reabrir sin conexión',
    () async {
      final holder = scope((_) async => jsonResponse(referencesJson(), 200));
      await holder.read(unionRefreshProvider.notifier).refresh({
        UnionFeed.references,
      }, reconnect: true);
      final reopened = scope((_) => throw StateError('Sin conexión'));
      await reopened.read(unionRefreshProvider.notifier).refresh({
        UnionFeed.references,
      }, connected: false);
      final status = reopened.read(unionRefreshProvider)[UnionFeed.references]!;
      expect(status.references?.product(litreRef)?.name, 'Herbicida central');
      expect(status.lastRead, isNotNull);
      expect(status.issue, UnionReadIssue.offline);
      expect(sent, ['GET']);
    },
  );

  test(
    'el primer ciclo conectado renueva referencias recientes marcadas sin red',
    () async {
      final container = scope((_) async => jsonResponse(referencesJson(), 200));
      final refresh = container.read(unionRefreshProvider.notifier);
      await refresh.refresh({UnionFeed.references});
      await refresh.refresh({UnionFeed.references}, connected: false);
      expect(
        container.read(unionRefreshProvider)[UnionFeed.references]?.issue,
        UnionReadIssue.offline,
      );
      await refresh.refresh({UnionFeed.references});
      expect(sent, ['GET', 'GET']);
      expect(
        container.read(unionRefreshProvider)[UnionFeed.references]?.issue,
        isNull,
      );
    },
  );

  test(
    'sin acceso vigente la actualización automática espera verificación',
    () async {
      access.clear();
      final holder = scope((_) => throw StateError('Sin acceso'));
      await holder.read(unionRefreshProvider.notifier).refresh({
        UnionFeed.calls,
      });
      expect(
        holder.read(unionRefreshProvider)[UnionFeed.calls]?.issue,
        UnionReadIssue.access,
      );
      expect(sent, isEmpty);
    },
  );
}

const _expiry = '2099-10-05T10:00:00.000Z';

StoredSession _stored({
  OwnerScope owner = memberA,
  String clientId = e12ClientId,
}) => StoredSession(
  refreshToken: 'refresh-anterior-de-prueba',
  installationClientId: clientId,
  registrationId: e12RegistrationId,
  accountId: e12AccountId,
  memberId: owner.memberId,
  tenantId: owner.tenantId,
  sessionId: e12SessionId,
  expiresAt: DateTime.parse(_expiry),
);

class _Guard implements RefreshGuard {
  bool quarantined = false;

  @override
  Future<bool> isQuarantined() async => quarantined;

  @override
  Future<void> quarantine() async => quarantined = true;

  @override
  Future<void> clear() async => quarantined = false;
}
