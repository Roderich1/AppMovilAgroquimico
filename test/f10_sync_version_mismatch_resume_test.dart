// Reanudar lo pausado por una versión no compatible (422
// CONTRACT_VERSION_MISMATCH; F05 §7 y matriz C25: «pausar versión; upgrade
// gobernado; no automático; conservar ID/versión original»).
//
// Antes de la corrección (D-01, revisión del 2026-10-26 sobre a68285c) no
// existía ninguna salida del estado VERSION_MISMATCH: tras actualizar la
// aplicación, la cola seguía bloqueada para siempre y la pantalla no ofrecía
// nada. Aquí: abrir la pantalla no reanuda nada; la tarjeta aparece sólo
// cuando hay filas pausadas por versión; «Reintentar con esta versión»,
// confirmado, reenvía la misma operación con la misma cantidad y
// causalidad, y la fila muestra el ACK.
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  /// Identidad y contenido de la intención: operación, proyección, acción,
  /// referencias, cantidad y causalidad. Lo que el ACK cambia (estado,
  /// intentos, código, fechas de confirmación) queda fuera.
  Map<String, Object?> core(Map<String, Object?> row) => {
    for (final key in const [
      'id',
      'operation_id',
      'owner_binding_id',
      'projection_type',
      'action',
      'campaign_ref',
      'product_ref',
      'base_unit',
      'quantity_base',
      'predecessor_operation_id',
      'predecessor_kind',
      'reconciliation_reference',
      'created_at',
    ])
      key: row[key],
  };

  testWidgets(
    'VERSION_MISMATCH → «Reintentar con esta versión»: un único envío con la '
    'misma operación y la fila muestra el ACK sin salir de la pantalla',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = (await tester.runAsync(
        () => seedSyncFixture(path: inMemoryDatabasePath),
      ))!;

      // Declarada y enviada con la versión anterior: Central respondió 422.
      final paused = (await tester.runAsync(() async {
        await fixture.needs.declare(
          referenceDate: inCampaign,
          productId: fixture.litreProductId,
          quantityBase: 30000,
        );
        final sending = await fixture.outbox.markSending(
          (await fixture.outbox.entries()).single,
        );
        await fixture.outbox.recordVersionMismatch(sending);
        final db = await fixture.database.database;
        return (await db.query('sync_outbox')).single;
      }))!;
      expect(paused['status'], 'VERSION_MISMATCH');
      expect(paused['attempts'], 1);

      final pushes = <Map<String, dynamic>>[];
      final access = SyncAccessHolder()
        ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        pushes.add(body);
        return http.Response(ackJson(body['operationId'] as String), 200);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(fixture.database),
            repositoryProvider.overrideWithValue(fixture.repo),
            declaredNeedStoreProvider.overrideWithValue(fixture.needs),
            centralBindingStoreProvider.overrideWithValue(fixture.bindings),
            syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
            syncAccessHolderProvider.overrideWithValue(access),
            syncApiProvider.overrideWithValue(
              SyncApi(
                AuthHttpClient(
                  config: ApiEndpointConfig(
                    Uri.parse('https://sindicato.example'),
                  ),
                  client: client,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SyncStatusScreen())),
        ),
      );
      await settle(tester);
      expect(pushes, isEmpty, reason: 'abrir la pantalla no reanuda nada');
      expect(find.textContaining('Pausado: versión ·'), findsOneWidget);
      // Lenguaje del agricultor: ni «VERSION_MISMATCH» ni «422» en la tarjeta.
      expect(find.byKey(const Key('version-mismatch')), findsOneWidget);
      expect(
        find.text('Envíos pausados por una versión distinta de la aplicación'),
        findsOneWidget,
      );
      final action = find.widgetWithText(
        TextButton,
        'Reintentar con esta versión',
      );
      expect(action, findsOneWidget);

      // Confirmación explícita antes de reanudar.
      await tester.tap(action);
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reintentar'));
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SyncStatusScreen)),
      );
      // El ciclo lanzado al reanudar avanza con el reloj de la prueba.
      for (
        var i = 0;
        i < 20 && container.read(syncControllerProvider).busy;
        i++
      ) {
        await settle(tester);
      }
      expect(container.read(syncControllerProvider).busy, isFalse);
      await settle(tester);

      expect(pushes, hasLength(1));
      expect(pushes.single['operationId'], paused['operation_id']);
      // La versión de contrato del envelope no cambia (v1, F05 C25).
      expect(pushes.single['contractVersion'], 1);
      expect(
        (pushes.single['payload'] as Map)['quantity_base'],
        paused['quantity_base'],
      );
      final acked = (await tester.runAsync(
        () async =>
            (await (await fixture.database.database).query('sync_outbox'))
                .single,
      ))!;
      expect(acked['status'], 'ACKED');
      expect(core(acked), core(paused));
      // La fila, no sólo el resumen, muestra el ACK; la tarjeta desaparece.
      expect(find.textContaining('Sincronizado · creada'), findsOneWidget);
      expect(find.textContaining('Pausado: versión'), findsNothing);
      expect(find.byKey(const Key('version-mismatch')), findsNothing);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
