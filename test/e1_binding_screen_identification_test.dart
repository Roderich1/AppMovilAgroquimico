// E1 §5.2–§5.6 en la pantalla «Vincular con el sindicato»: pedir la
// identificación muestra exactamente lo que se enviará; la fila nunca dice
// «Enviado» mientras la solicitud sólo existe en el teléfono; al actualizar
// las referencias se envía y se lee el estado; cuando el sindicato la
// identifica, «Vincular» usa la confirmación de siempre y `bindProduct`.
// Sin red: MockClient. Datos sintéticos.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/identification_request_store.dart';
import 'package:agroquimicos/presentation/screens/central_binding_screen.dart';
import 'package:agroquimicos/presentation/widgets/identification_clarification_sheet.dart';
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
    'boro: responde con su primera foto, reintenta y deja el ingrediente vacío',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = (await tester.runAsync(
        () => seedSyncFixture(path: inMemoryDatabasePath, bindCatalog: false),
      ))!;
      final workspace = (await tester.runAsync(() => photoWorkspace(fixture)))!;
      final source = File('${workspace.root.path}/etiqueta.jpg');
      final store = IdentificationRequestStore(
        fixture.database,
        documents: () async => workspace.documents,
      );
      final request = (await tester.runAsync(() async {
        await source.writeAsBytes(labelJpeg(width: 320, height: 240));
        await (await fixture.database.database).update(
          'products',
          {'name': 'boro', 'unit': 'KG', 'active_ingredient': null},
          where: 'id=?',
          whereArgs: [fixture.unboundProductId],
        );
        final request = await store.create(
          productId: fixture.unboundProductId,
          sharePhoto: false,
        );
        await store.markReceived(request.requestId);
        return request;
      }))!;
      final access = SyncAccessHolder()
        ..accept('token-sintetico', memberA.memberId, memberA.tenantId);
      final config = ApiEndpointConfig(Uri.parse('https://sindicato.example'));
      final staged = <Map<String, dynamic>>[];
      final uploads = <String>[];
      var received = false;
      Map<String, Object?> view() => serverView(
        request.requestId,
        localName: 'boro',
        unit: 'KG',
        note: received ? null : 'Adjunte la foto de la etiqueta',
        photoState: received ? 'STORED' : 'NONE',
        photoSha: received ? staged.last['photo_sha256'] as String : null,
        consentVersion: received ? 'FOTO-1' : null,
      );
      final client = MockClient((call) async {
        if (call.method == 'GET')
          return json({
            'contractVersion': 1,
            'requests': [view()],
          }, 200);
        if (call.url.path.endsWith('/clarification-response')) {
          staged.add(jsonDecode(call.body) as Map<String, dynamic>);
          return json({'received': received, 'request': view()}, 200);
        }
        expect(call.url.path, endsWith('/photo'));
        uploads.add(
          call.headers['X-Identification-Response-Id'] ??
              call.headers['x-identification-response-id']!,
        );
        expect(call.bodyBytes, isNotEmpty);
        if (uploads.length == 1)
          return json({'errorCode': 'PHOTO_STORAGE_UNAVAILABLE'}, 503);
        received = true;
        return json(view(), 201);
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
            clarificationPhotoPickerProvider.overrideWithValue(
              (_) async => source.path,
            ),
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
                json: AuthHttpClient(config: config, client: client),
                config: config,
                client: client,
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CentralBindingScreen()),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Actualizar'));
      await settle(tester);
      expect(
        find.text('Nota del sindicato: Adjunte la foto de la etiqueta'),
        findsOneWidget,
      );
      await tester.tap(find.text('Completar información'));
      await settle(tester);
      expect(find.text('Unidad: KG'), findsOneWidget);
      await tester.tap(find.text('Tomar foto'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('clarification-send')));
      await settle(tester, rounds: 3);
      expect(staged, isEmpty);
      await tester.tap(find.byKey(const Key('clarification-photo-consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('clarification-send')));
      await settle(tester, rounds: 28);
      expect(staged.single['active_ingredient'], isNull);
      expect(staged.single['local_name'], 'boro');
      expect(staged.single['unit'], 'KG');
      expect(staged.single['note_at'], '2026-11-12T09:00:00.000Z');
      expect(staged.single['photo_consent'], containsPair('version', 'FOTO-1'));
      expect(uploads, hasLength(1));
      final failed = await tester.runAsync(() => store.byId(request.requestId));
      expect(failed?.clarificationReply?.error, 'PHOTO_STORAGE_UNAVAILABLE');
      final retryMessage = find.text(
        'El envío de la respuesta con foto falló. Puede reintentar.',
      );
      for (var poll = 0; poll < 12 && !tester.any(retryMessage); poll++) {
        await settle(tester, rounds: 5);
      }
      expect(retryMessage, findsOneWidget);

      await tester.tap(find.text('Actualizar'));
      await settle(tester);
      expect(uploads, hasLength(1));
      await tester.tap(find.text('Reintentar respuesta'));
      await settle(tester, rounds: 22);
      expect(uploads, [
        staged.first['operation_id'],
        staged.first['operation_id'],
      ]);
      expect(staged.last, staged.first);
      expect(
        find.text('Nota del sindicato: Adjunte la foto de la etiqueta'),
        findsNothing,
      );
      expect(find.text('Foto enviada'), findsOneWidget);
      expect(await tester.runAsync(fixture.bindings.productBindings), isEmpty);
    },
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
      // Rediseño (sesión C): rótulo y valor en filas separadas de la hoja.
      Finder sent(String key, String value) => find.descendant(
        of: find.byKey(Key('identification-sent-$key')),
        matching: find.text(value),
        matchRoot: true,
      );
      expect(find.text('Nombre'), findsOneWidget);
      expect(sent('name', 'Adherente local'), findsOneWidget);
      expect(find.text('Ingrediente activo'), findsOneWidget);
      expect(sent('ingredient', 'sin dato'), findsOneWidget);
      expect(find.text('Unidad'), findsOneWidget);
      expect(sent('unit', 'L'), findsOneWidget);
      expect(find.byKey(const Key('identification-share-photo')), findsNothing);
      expect(identificationCalls, isEmpty);
      await tester.tap(find.byKey(const Key('identification-confirm')));
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
