// Mensajes de autorización observados en la tanda física de #18 (F10).
//
// - C38: al volver a autenticar con OTRA cuenta, la app cerraba esa sesión
//   sin vincularla (correcto), pero la pantalla sólo decía «Se requiere volver
//   a autenticar…»: no explicaba que la cuenta no es la del titular.
// - C40/C22: tras un 403, los envíos quedan «Pausado: autorización». Verificar
//   el acceso no los reanuda (por diseño: no hay reanudación automática); hace
//   falta «Sincronizar ahora», y ninguna pantalla lo decía.
// - C23: con el registro del dispositivo revocado, el mensaje no decía que
//   los datos se conservan ni cuál es el camino para recuperarlos.
//
// No cambia ninguna regla: ni refresh automático, ni cambio de titular, ni
// reanudación por verificar el acceso. Sólo lo que la app explica.
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:agroquimicos/services/sync/sync_worker.dart';
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

  group('mensajes', () {
    test('otra cuenta al volver a autenticar: dice por qué y qué hacer', () {
      final message = const RemoteSessionState(
        RemoteSessionPhase.requiresReauthentication,
        problem: RemoteSessionProblem.otherAccount,
      ).safeMessage;
      expect(message, contains('no es la vinculada a este teléfono'));
      expect(message, contains('titular'));
      expect(message, contains('No se envió nada'));
    });

    test('un contexto inactivo conserva el mensaje general', () {
      expect(
        const RemoteSessionState(
          RemoteSessionPhase.requiresReauthentication,
          problem: RemoteSessionProblem.contextMismatch,
        ).safeMessage,
        'Se requiere volver a autenticar para las funciones en línea. Sus '
        'datos locales siguen disponibles.',
      );
    });

    test('registro rechazado: los datos se conservan y cómo recuperarlos', () {
      final message = const RemoteSessionState(
        RemoteSessionPhase.registrationRejected,
      ).safeMessage;
      expect(message, contains('se conservan'));
      expect(message, contains('copia de seguridad'));
      expect(message, contains('instalación nueva'));
      expect(message, contains('libere'));
    });

    test('403: la acción explícita para reanudar es «Sincronizar ahora»', () {
      final message = blockerMessage(SyncBlocker.forbidden);
      expect(message, contains('nada se borró'));
      expect(message, contains('Sincronizar ahora'));
    });

    test('otra cuenta en sesión: por qué no se envía', () {
      final message = blockerMessage(SyncBlocker.ownerMismatch);
      expect(message, contains('titular'));
      expect(message, contains('no se envía nada'));
    });
  });

  testWidgets(
    'Sincronización explica lo pausado por autorización; abrirla no envía y '
    'sólo «Sincronizar ahora» lo reanuda',
    (tester) async {
      Future<void> settle() async {
        for (var round = 0; round < 6; round++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          for (var frame = 0; frame < 6; frame++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        }
      }

      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = (await tester.runAsync(
        () => seedSyncFixture(path: inMemoryDatabasePath),
      ))!;
      final operationId = (await tester.runAsync(() async {
        await fixture.needs.declare(
          referenceDate: inCampaign,
          productId: fixture.litreProductId,
          quantityBase: 12000,
        );
        // Lo que deja un 403 de Central.
        await fixture.outbox.pauseForAuthorization(fixture.ownerBindingId);
        return (await fixture.outbox.entries()).single.operationId;
      }))!;

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
      await settle();

      // Abrir la pantalla, con acceso verificado, no reanuda ni envía.
      expect(pushes, isEmpty);
      expect(
        find.textContaining('Envíos pausados por autorización'),
        findsOneWidget,
      );
      expect(find.textContaining('pulse «Sincronizar ahora»'), findsOneWidget);
      expect(
        (await tester.runAsync(fixture.outbox.entries))!.single.status,
        OutboxStatus.authPaused,
      );

      // La acción explícita sí lo reanuda, con el mismo ID.
      await tester.tap(find.text('Sincronizar ahora'));
      await settle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SyncStatusScreen)),
      );
      for (
        var i = 0;
        i < 20 && container.read(syncControllerProvider).busy;
        i++
      ) {
        await settle();
      }
      expect(pushes, [operationId]);
      expect(
        (await tester.runAsync(fixture.outbox.entries))!.single.status,
        OutboxStatus.acked,
      );
      expect(
        find.textContaining('Envíos pausados por autorización'),
        findsNothing,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
