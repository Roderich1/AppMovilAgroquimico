// Pantallas F05: necesidad declarada, vinculación con el sindicato y estado
// de sincronización. Sin red: la API usa un MockClient o no se llama.
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/presentation/screens/central_binding_screen.dart';
import 'package:agroquimicos/presentation/screens/declared_needs_screen.dart';
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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

  Future<SyncFixture> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    bool bindCatalog = true,
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = (await tester.runAsync(
      () =>
          seedSyncFixture(path: inMemoryDatabasePath, bindCatalog: bindCatalog),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(fixture.database),
          repositoryProvider.overrideWithValue(fixture.repo),
          declaredNeedStoreProvider.overrideWithValue(fixture.needs),
          centralBindingStoreProvider.overrideWithValue(fixture.bindings),
          syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
          ...overrides,
        ],
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
    await settle(tester);
    return fixture;
  }

  testWidgets(
    'declarar exige una confirmación explícita con producto, cantidad y campaña',
    (tester) async {
      final fixture = await pumpScreen(tester, const DeclaredNeedsScreen());
      expect(
        find.text('Todavía no declaró ninguna necesidad.'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Declarar'));
      await settle(tester);
      expect(find.text('Campaña: Campaña local 2026'), findsOneWidget);
      await tester.tap(find.text('Producto'));
      await settle(tester);
      await tester.tap(find.text('Herbicida local').last);
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cantidad total'),
        '25',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await settle(tester);

      expect(
        find.text(
          'Declarar al sindicato: 25 L de Herbicida local para Campaña local 2026.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Declarar').last);
      await settle(tester);

      expect(find.text('Herbicida local · Campaña local 2026'), findsOneWidget);
      expect(find.textContaining('25 L · Pendiente'), findsOneWidget);
      final rows = (await tester.runAsync(fixture.outboxEntries))!;
      expect(rows.single.quantityBase, '25000');
      expect(rows.single.status, OutboxStatus.pending);
    },
  );

  // Reproducido en el POCO el 2026-10-15: el ACK llegó por el ciclo del
  // temporizador y la lista siguió «Pendiente» hasta volver a entrar.
  testWidgets(
    'un ciclo del worker en segundo plano actualiza el estado de la lista',
    (tester) async {
      final access = SyncAccessHolder();
      final client = MockClient((request) async {
        final id = (jsonDecode(request.body) as Map)['operationId'] as String;
        return http.Response(ackJson(id), 200);
      });
      final fixture = await pumpScreen(
        tester,
        const DeclaredNeedsScreen(),
        overrides: [
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
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DeclaredNeedsScreen)),
      );
      // Sin acceso verificado: la declaración queda pendiente.
      await tester.tap(find.widgetWithText(FilledButton, 'Declarar'));
      await settle(tester);
      await tester.tap(find.text('Producto'));
      await settle(tester);
      await tester.tap(find.text('Herbicida local').last);
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Cantidad total'),
        '25',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Declarar').last);
      await settle(tester);
      // El ciclo que disparó la propia pantalla termina sin acceso.
      await tester.runAsync(() async {
        while (container.read(syncControllerProvider).busy) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await settle(tester);
      expect(find.textContaining('25 L · Pendiente'), findsOneWidget);

      // Llega el acceso y el temporizador dispara un ciclo fuera de la pantalla.
      access.accept('token-sintetico', memberA.memberId, memberA.tenantId);
      final report = await tester.runAsync(
        () => container.read(syncControllerProvider.notifier).kick(),
      );
      expect(report?.accepted, 1);
      await settle(tester);

      final rows = (await tester.runAsync(fixture.outboxEntries))!;
      expect(rows.single.status, OutboxStatus.acked);
      expect(find.textContaining('25 L · Sincronizado'), findsOneWidget);
    },
  );

  testWidgets('cancelar la confirmación no declara nada', (tester) async {
    final fixture = await pumpScreen(tester, const DeclaredNeedsScreen());
    await tester.tap(find.widgetWithText(FilledButton, 'Declarar'));
    await settle(tester);
    await tester.tap(find.text('Producto'));
    await settle(tester);
    await tester.tap(find.text('Fungicida local').last);
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Cantidad total'),
      '0',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
    await settle(tester);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect((await tester.runAsync(fixture.outboxRows))!, isEmpty);
  });

  testWidgets('sin productos vinculados se pide vincular antes de declarar', (
    tester,
  ) async {
    await pumpScreen(tester, const DeclaredNeedsScreen(), bindCatalog: false);
    await tester.tap(find.widgetWithText(FilledButton, 'Declarar'));
    await settle(tester);
    expect(
      find.text(
        'Vincule primero sus productos con el sindicato para declarar.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'vincular: la elección es explícita; la unidad incompatible no se ofrece',
    (tester) async {
      final access = SyncAccessHolder()
        ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
      final client = MockClient(
        // Central responde JSON en UTF-8 («Campaña»).
        (_) async => http.Response(
          jsonEncode(referencesJson()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final fixture = await pumpScreen(
        tester,
        const CentralBindingScreen(),
        bindCatalog: false,
        overrides: [
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
      );
      expect(find.text('Requiere vinculación'), findsNWidgets(4));
      await tester.tap(find.text('Actualizar'));
      await settle(tester);
      // Nada se vinculó por leer las referencias.
      expect(
        (await tester.runAsync(fixture.bindings.productBindings))!,
        isEmpty,
      );

      final row = find.ancestor(
        of: find.text('Herbicida local (L)'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(
          of: row,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Vincular…'));
      await settle(tester);
      expect(find.text('Unidad central sin equivalencia L/KG'), findsOneWidget);
      await tester.tap(find.text('Herbicida central (L)'));
      await settle(tester);
      expect(
        find.textContaining('Vincular «Herbicida local» de este teléfono'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Vincular'));
      await settle(tester);

      final bindings = (await tester.runAsync(
        fixture.bindings.productBindings,
      ))!;
      expect(bindings.single.productId, fixture.litreProductId);
      expect(bindings.single.productRef, litreRef);
      expect(
        find.textContaining('Herbicida central · vigente'),
        findsOneWidget,
      );
    },
  );

  testWidgets('sin conexión se informa el motivo y los vínculos se conservan', (
    tester,
  ) async {
    final access = SyncAccessHolder()
      ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
    final client = MockClient(
      (_) async => throw http.ClientException('sin red'),
    );
    final fixture = await pumpScreen(
      tester,
      const CentralBindingScreen(),
      overrides: [
        syncAccessHolderProvider.overrideWithValue(access),
        syncApiProvider.overrideWithValue(
          SyncApi(
            AuthHttpClient(
              config: ApiEndpointConfig(Uri.parse('https://sindicato.example')),
              client: client,
            ),
          ),
        ),
      ],
    );
    await tester.tap(find.text('Actualizar'));
    await settle(tester);
    expect(
      find.textContaining('Los vínculos existentes se conservan'),
      findsOneWidget,
    );
    expect(
      (await tester.runAsync(fixture.bindings.productBindings))!,
      hasLength(2),
    );
    expect(find.textContaining('Herbicida central · vigente'), findsOneWidget);
  });

  testWidgets(
    'estado de sincronización: estados distinguibles y la intención propia',
    (tester) async {
      late SyncFixture seeded;
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      seeded = (await tester.runAsync(() async {
        final f = await seedSyncFixture(path: inMemoryDatabasePath);
        await f.needs.declare(
          referenceDate: inCampaign,
          productId: f.litreProductId,
          quantityBase: 1500,
        );
        await f.needs.declare(
          referenceDate: inCampaign,
          productId: f.kiloProductId,
          quantityBase: 700,
        );
        final kilo = (await f.outboxEntries()).last;
        await f.outbox.recordTerminal(
          await f.outbox.markSending(kilo),
          OutboxStatus.rejected,
          'REFERENCE_UNAVAILABLE',
        );
        return f;
      }))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(seeded.database),
            syncOutboxStoreProvider.overrideWithValue(
              SyncOutboxStore(seeded.database),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SyncStatusScreen())),
        ),
      );
      await settle(tester);
      expect(find.text('Pendiente: 1'), findsOneWidget);
      expect(find.text('Rechazado: 1'), findsOneWidget);
      expect(find.text('Todavía sin confirmación'), findsOneWidget);
      // C-04: cada fila dice qué producto y qué campaña (nombres locales).
      expect(find.text('Herbicida local · Campaña local 2026'), findsOneWidget);
      expect(find.text('Fungicida local · Campaña local 2026'), findsOneWidget);
      expect(
        find.textContaining('Necesidad declarada · Publicar · 1,5 L'),
        findsOneWidget,
      );
      // C-03: estados en palabras y explicación por familia; el código
      // técnico no está en el texto principal.
      expect(
        find.textContaining('Guardado, pendiente de envío'),
        findsOneWidget,
      );
      expect(find.textContaining('Rechazado por el sindicato'), findsOneWidget);
      expect(
        find.textContaining(
          'El sindicato no reconoce el producto o la campaña vinculados: '
          'revise los vínculos',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('REFERENCE_UNAVAILABLE'), findsNothing);
      // C-05: desde el rechazo se puede ir a decidir; la pendiente no lo
      // ofrece.
      expect(find.widgetWithText(TextButton, 'Decidir…'), findsOneWidget);
      // El código sigue disponible, plegado en «Detalle técnico».
      expect(find.text('Detalle técnico'), findsOneWidget);
      await tester.tap(find.text('Detalle técnico'));
      await settle(tester);
      expect(
        find.textContaining('Código: REFERENCE_UNAVAILABLE · Intentos: 1'),
        findsOneWidget,
      );
    },
  );
}
