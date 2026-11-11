// E1 §5.2–§5.6 en la pantalla «Vincular con el sindicato»: pedir la
// identificación muestra exactamente lo que se enviará; la fila nunca dice
// «Enviado» mientras la solicitud sólo existe en el teléfono; al actualizar
// las referencias se envía y se lee el estado; cuando el sindicato la
// identifica, «Vincular» usa la confirmación de siempre y `bindProduct`.
// Sin red: MockClient. Datos sintéticos.
import 'dart:convert';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/identification_request_store.dart';
import 'package:agroquimicos/presentation/screens/central_binding_screen.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/identification_api.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e1_identification_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

const _base = '/api/v1/catalog/identification-requests';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var round = 0; round < rounds; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  http.Response json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  testWidgets(
    'pedir identificación, recibir «Identificado como» y vincular con confirmación',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = (await tester.runAsync(
        () => seedSyncFixture(path: inMemoryDatabasePath, bindCatalog: false),
      ))!;
      final store = IdentificationRequestStore(fixture.database);
      final access = SyncAccessHolder()
        ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
      final config = ApiEndpointConfig(Uri.parse('https://sindicato.example'));
      var linked = false;
      final identificationCalls = <String>[];
      final known = <String>{};
      final identificationClient = MockClient((request) async {
        identificationCalls.add('${request.method} ${request.url.path}');
        if (request.method == 'GET' && request.url.path == _base) {
          return json({
            'contractVersion': 1,
            'requests': [
              for (final id in known) serverView(id, linked: linked),
            ],
          }, 200);
        }
        final id = request.url.path.split('/').last;
        known.add(id);
        return json(serverView(id), 201);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(fixture.database),
            repositoryProvider.overrideWithValue(fixture.repo),
            declaredNeedStoreProvider.overrideWithValue(fixture.needs),
            centralBindingStoreProvider.overrideWithValue(fixture.bindings),
            syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
            identificationRequestStoreProvider.overrideWithValue(store),
            syncAccessHolderProvider.overrideWithValue(access),
            syncApiProvider.overrideWithValue(
              SyncApi(
                AuthHttpClient(
                  config: config,
                  client: MockClient((_) async => json(referencesJson(), 200)),
                ),
              ),
            ),
            identificationApiProvider.overrideWithValue(
              IdentificationApi(
                json: AuthHttpClient(
                  config: config,
                  client: identificationClient,
                ),
                config: config,
                client: identificationClient,
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CentralBindingScreen()),
          ),
        ),
      );
      await settle(tester);

      final row = find.byKey(
        Key('product-binding-${fixture.unboundProductId}'),
      );
      expect(row, findsOneWidget);
      await tester.tap(
        find.descendant(
          of: row,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settle(tester, rounds: 3);
      await tester.tap(find.text('Pedir identificación al sindicato'));
      await settle(tester, rounds: 3);

      // Exactamente lo que se enviará; sin foto, sin casilla de la foto.
      expect(find.text('Nombre: Adherente local'), findsOneWidget);
      expect(find.text('Ingrediente activo: sin dato'), findsOneWidget);
      expect(find.text('Unidad: L'), findsOneWidget);
      expect(find.byKey(const Key('identification-share-photo')), findsNothing);
      expect(identificationCalls, isEmpty);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Pedir identificación'),
      );
      await settle(tester);

      final created = (await tester.runAsync(
        () => store.byProduct(fixture.unboundProductId),
      ))!;
      expect(created.sendStatus, IdentificationSendStatus.pendingSend);
      expect(identificationCalls, isEmpty, reason: 'crear no envía nada');
      expect(find.text('Pendiente de envío'), findsOneWidget);
      expect(find.text('Enviar ahora'), findsOneWidget);
      expect(find.textContaining('Enviado'), findsNothing);
      expect(find.textContaining('Recibida'), findsNothing);
      // Ya pedida: la opción no se repite.
      await tester.tap(
        find.descendant(
          of: row,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await settle(tester, rounds: 3);
      expect(find.text('Pedir identificación al sindicato'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester, rounds: 3);

      // «Actualizar»: referencias, envío y lectura del estado.
      linked = true;
      await tester.tap(find.text('Actualizar'));
      await settle(tester, rounds: 16);
      expect(identificationCalls, [
        'PUT $_base/${created.requestId}',
        'GET $_base',
      ]);
      expect(
        find.text('Identificado como “Herbicida central”'),
        findsOneWidget,
      );
      expect(
        find.text('Identificado por el sindicato como “Herbicida central” (L)'),
        findsOneWidget,
      );
      // Nunca se vincula solo.
      expect(
        (await tester.runAsync(fixture.bindings.productBindings))!,
        isEmpty,
      );

      await tester.tap(
        find.descendant(
          of: row,
          matching: find.widgetWithText(FilledButton, 'Vincular'),
        ),
      );
      await settle(tester, rounds: 3);
      expect(
        find.textContaining('Vincular «Adherente local» de este teléfono'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Vincular').last);
      await settle(tester);
      final bindings = (await tester.runAsync(
        fixture.bindings.productBindings,
      ))!;
      expect(bindings.single.productId, fixture.unboundProductId);
      expect(bindings.single.productRef, identifiedRef);
      expect(find.text('Producto vinculado.'), findsOneWidget);
    },
  );
}
