import 'dart:async';

import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/local_data_providers.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
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
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late SyncFixture fixture;
  late JointPurchaseStore store;
  late SyncAccessHolder access;
  final sent = <String>[];
  final date = DateTime.utc(2026, 11, 11, 18, 20);

  setUp(() async {
    sent.clear();
    fixture = await seedSyncFixture();
    store = JointPurchaseStore(fixture.database, clock: () => date);
    access = SyncAccessHolder()
      ..accept('prueba', memberA.memberId, memberA.tenantId);
  });

  ProviderContainer scope(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = MockClient((request) {
      sent.add(request.method);
      return handler(request);
    });
    final httpClient = AuthHttpClient(
      config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
      client: client,
    );
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
      ],
    );
    addTearDown(container.dispose);
    return container;
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
