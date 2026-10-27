// Liberar lo pausado por una restauración y ver el ACK sin salir de la
// pantalla (F10; observado en el turno 2 del POCO, 2026-10-16).
//
// Tras «Liberar», el envío salía en un ciclo del worker lanzado sin esperar
// (`unawaited(kick())`). La pantalla releía la lista justo después de
// liberar, antes del ACK, y nunca más: el resumen ya decía «Sincronizado» y
// la fila seguía «Pendiente (sin confirmar)» hasta volver a entrar.
//
// La intención del ensayo no estaba PENDING antes de restaurar, sino
// OUTCOME_UNKNOWN: el worker la intentó sin red. También se comprueba aquí
// que pasa a RESTORE_PAUSED y vuelve a salir con la misma operación,
// cantidad y causalidad.
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
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

  /// Fila completa de la outbox sin estado ni fecha de cambio: operación,
  /// cantidad, versión y causalidad.
  Map<String, Object?> core(Map<String, Object?> row) => {
    for (final entry in row.entries)
      if (entry.key != 'status' && entry.key != 'updated_at')
        entry.key: entry.value,
  };

  testWidgets(
    'OUTCOME_UNKNOWN → RESTORE_PAUSED → Liberar: un único envío con la misma '
    'operación y la fila muestra el ACK sin salir de la pantalla',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = (await tester.runAsync(
        () => seedSyncFixture(path: inMemoryDatabasePath),
      ))!;

      // Declarada sin red: el worker la intentó y no supo el resultado.
      final (unknown, paused) = (await tester.runAsync(() async {
        await fixture.needs.declare(
          referenceDate: inCampaign,
          productId: fixture.litreProductId,
          quantityBase: 30000,
        );
        final sending = await fixture.outbox.markSending(
          (await fixture.outbox.entries()).single,
        );
        await fixture.outbox.recordRetry(
          sending,
          status: OutboxStatus.outcomeUnknown,
          code: 'NETWORK',
          nextAttemptAt: DateTime.now().toUtc(),
        );
        final db = await fixture.database.database;
        final unknown = (await db.query('sync_outbox')).single;
        // Lo que hace GuardedRestore dentro del tramo con rollback.
        await SyncOutboxStore.pauseAfterRestore(
          db,
          DateTime.now().toUtc().toIso8601String(),
        );
        final paused = (await db.query('sync_outbox')).single;
        return (unknown, paused);
      }))!;
      expect(unknown['status'], 'OUTCOME_UNKNOWN');
      expect(unknown['attempts'], 1);
      expect(paused['status'], 'RESTORE_PAUSED');
      expect(core(paused), core(unknown));

      final pushes = <String>[];
      final access = SyncAccessHolder()
        ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
      final client = MockClient((request) async {
        final id = (jsonDecode(request.body) as Map)['operationId'] as String;
        pushes.add(id);
        return http.Response(ackJson(id), 200);
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
      expect(pushes, isEmpty, reason: 'abrir la pantalla no envía nada');
      expect(
        find.textContaining('Pausado: llegó con un respaldo restaurado ·'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Liberar'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Liberar'));
      await settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SyncStatusScreen)),
      );
      // El ciclo lanzado al liberar avanza con el reloj de la prueba.
      for (
        var i = 0;
        i < 20 && container.read(syncControllerProvider).busy;
        i++
      ) {
        await settle(tester);
      }
      expect(container.read(syncControllerProvider).busy, isFalse);
      await settle(tester);

      expect(pushes, [unknown['operation_id']]);
      final acked = (await tester.runAsync(
        () async =>
            (await (await fixture.database.database).query('sync_outbox'))
                .single,
      ))!;
      expect(acked['status'], 'ACKED');
      expect(acked['operation_id'], unknown['operation_id']);
      expect(acked['quantity_base'], unknown['quantity_base']);
      // La fila, no sólo el resumen, muestra el ACK.
      expect(
        find.textContaining('Aceptado por el sindicato · creada'),
        findsOneWidget,
      );
      expect(find.textContaining('sin confirmación'), findsNothing);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
