// P-A C1 (E2 §12): la persona responsable cambió. El teléfono lee el
// contrato 3 (la autorización de la responsable actual), no supone que una
// aceptación anterior la cubra, ofrece una acción propia para autorizarla
// (casillas sin marcar, sin ampliar por sí sola), la ata a la versión de la
// responsabilidad que mostró y distingue pendiente de aplicada. Las
// cantidades nunca autorizan a nadie. Sin red real; datos sintéticos.
import 'dart:convert';
import 'dart:math';

import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/presentation/widgets/joint_purchase_responsible_review.dart';
import 'package:agroquimicos/presentation/widgets/joint_purchase_texts.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/joint_purchase_api.dart';
import 'package:agroquimicos/services/sync/joint_purchase_sender.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e2_joint_purchase_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';


Map<String, Object?> _restricted({int version = 1, int scopeSequence = 0}) =>
    participationJson(
      consentScope: JointPurchaseConsentScope.responsibleOnly,
      consentScopeSequence: scopeSequence,
      responsibleAuthorization: {'authorized': false, 'version': version},
    );

Map<String, Object?> _authorized(
  int version, {
  String scope = JointPurchaseConsentScope.responsibleOnly,
  int scopeSequence = 1,
}) => participationJson(
  consentScope: scope,
  consentScopeSequence: scopeSequence,
  responsibleAuthorization: {'authorized': true, 'version': version},
);

void main() {
  sqfliteFfiInit();

  group('contrato 3: autorización de la responsable actual', () {
    test('se lee de la participación y del responsable, con lista cerrada', () {
      final view = JointPurchaseCallView.fromJson(
        callJson(
          responsibleVersion: 2,
          responsibleName: 'Nueva responsable sintética',
          participation: _restricted(),
        ),
      );
      expect(view.responsibleVersion, 2);
      expect(view.participation!.responsibleAuthorized, isFalse);
      expect(view.participation!.responsibleAuthorizationVersion, 1);
      expect(view.participation!.needsResponsibleAuthorization, isTrue);
      // Sin el dato (copia o respuesta anterior) no se supone nada.
      final unknown = JointPurchaseCallView.fromJson(
        callJson(participation: participationJson()),
      );
      expect(unknown.participation!.responsibleAuthorized, isNull);
      expect(unknown.participation!.needsResponsibleAuthorization, isFalse);
      // Formas inválidas: se rechaza la respuesta entera.
      for (final bad in [
        {'authorized': true, 'version': null},
        {'authorized': 'no', 'version': 1},
        {'authorized': false, 'version': 0},
        {'authorized': false, 'version': 1, 'extra': 1},
      ]) {
        expect(
          () => JointPurchaseCallView.fromJson(
            callJson(
              participation: participationJson(responsibleAuthorization: bad),
            ),
          ),
          throwsA(isA<JointPurchaseFormatException>()),
          reason: '$bad',
        );
      }
      expect(
        () => JointPurchaseCallView.fromJson(
          callJson(
            extra: const {
              'responsible': {'name': 'X', 'version': 0},
            },
          ),
        ),
        throwsA(isA<JointPurchaseFormatException>()),
      );
    });

    test(
      'el error RESPONSIBLE_CHANGED trae la versión vigente y la participación',
      () {
        final body = JointPurchaseErrorBody.tryParse(
          {
            'errorCode': 'RESPONSIBLE_CHANGED',
            'responsible_version': 3,
            'participation': _restricted(version: 2),
          },
          {litreRef: 'ML', kiloRef: 'G'},
        );
        expect(body!.responsibleVersion, 3);
        expect(body.participation!.responsibleAuthorized, isFalse);
      },
    );
  });

  group('teléfono', () {
    late SyncFixture fixture;
    late JointPurchaseStore store;
    late JointPurchaseSender sender;
    late List<http.Request> requests;
    late http.Response Function(http.Request request) respond;
    late DateTime now;
    final config = ApiEndpointConfig(Uri.parse('https://sindicato.example'));
    VerifiedAccess access() => VerifiedAccess(
      accessToken: 'token-sintetico',
      scope: memberA,
      obtainedAt: now,
    );

    setUp(() async {
      now = DateTime.utc(2026, 11, 12, 15);
      fixture = await seedSyncFixture();
      store = JointPurchaseStore(
        fixture.database,
        clock: () => now,
        random: Random(11),
      );
      requests = [];
      respond = (_) =>
          jsonResponse({'errorCode': 'TEMPORARILY_UNAVAILABLE'}, 503);
      final client = MockClient((request) async {
        requests.add(request);
        return respond(request);
      });
      final api = JointPurchaseApi(
        json: AuthHttpClient(config: config, client: client),
        clock: () => now,
      );
      sender = JointPurchaseSender(
        store: store,
        owners: fixture.owners,
        api: () => api,
        random: Random(13),
        clock: () => now,
      );
    });

    Future<JointPurchaseCall> seeded({
      required int version,
      Map<String, Object?>? participation,
      String status = 'OPEN',
    }) async {
      await seedCalls(store, memberA, [
        callJson(
          status: status,
          responsibleVersion: version,
          responsibleName: 'Responsable v$version',
          participation: participation,
          closing: status == 'CLOSED'
              ? {
                  'cutoff_at': deadline,
                  'closed_at': deadline,
                  'included': true,
                  'lines': [
                    {
                      'product_ref': litreRef,
                      'base_unit': 'ML',
                      'quantity_base': '25000',
                    },
                  ],
                }
              : null,
        ),
      ]);
      return (await store.call(callId))!;
    }

    test('restringida: no se amplía sin autorizarla; autorizar es una decisión propia atada a la versión mostrada', () async {
      final call = await seeded(version: 2, participation: _restricted());
      expect(call.needsResponsibleReview, isTrue);
      expect(call.responsibleVersion, 2);
      await expectLater(
        store.decideConsent(
          callId: callId,
          scope: JointPurchaseConsentScope.collaborators,
          decidedAt: now,
        ),
        throwsA(isA<JointPurchaseException>()),
      );
      final op = (await store.decideConsent(
        callId: callId,
        scope: JointPurchaseConsentScope.responsibleOnly,
        decidedAt: now,
        authorizeResponsible: true,
      ))!;
      expect(op.authorizeResponsible, isTrue);
      expect(op.responsibleVersion, 2);
      expect(op.wireBody, {
        'operation_id': op.operationId,
        'sequence': 1,
        'scope': 'RESPONSIBLE_ONLY',
        'consent': {'version': 'CONV-3', 'decided_at': now.toIso8601String()},
        'responsible_version': 2,
        'authorize_responsible': true,
      });
      // Repetir lo mismo pendiente no crea otra decisión.
      final again = await store.decideConsent(
        callId: callId,
        scope: JointPurchaseConsentScope.responsibleOnly,
        decidedAt: now,
        authorizeResponsible: true,
      );
      expect(again!.operationId, op.operationId);
      final pending = (await store.call(callId))!;
      expect(pending.pendingConsentOp?.authorizeResponsible, isTrue);
      expect(
        pending.needsResponsibleReview,
        isTrue,
        reason: 'pendiente no es aplicada',
      );
      expect(pending.authorizationOutdated, isFalse);
      // La responsable vuelve a cambiar antes de enviarla: hay que revisar de nuevo.
      await seeded(version: 3, participation: _restricted());
      expect((await store.call(callId))!.authorizationOutdated, isTrue);
      // Modificar cantidades no lleva autorización ni la cambia.
      final quantity = await store.confirm(
        callId: callId,
        lines: {litreRef: 30000},
      );
      expect(quantity.responsibleVersion, isNull);
      expect(quantity.consentVersion, isNull);
    });

    test('envío: aplicada sólo con la respuesta del sindicato; RESPONSIBLE_CHANGED la rechaza sin reintentar y adopta lo vigente', () async {
      await seeded(version: 2, participation: _restricted());
      final op = (await store.decideConsent(
        callId: callId,
        scope: JointPurchaseConsentScope.collaborators,
        decidedAt: now,
        authorizeResponsible: true,
      ))!;
      // Sin conexión: sigue pendiente, mismo cuerpo.
      respond = (_) => throw http.ClientException('sin red');
      await sender.run(access());
      expect(
        (await store.consentOp(op.operationId))!.sendStatus,
        JointPurchaseOpStatus.pendingSend,
      );
      // La responsable cambió en el sindicato antes de que llegara.
      respond = (request) {
        if (request.method == 'GET') {
          return jsonResponse(
            listJson([
              callJson(
                responsibleVersion: 3,
                responsibleName: 'Responsable v3',
                participation: _restricted(version: 1),
              ),
            ]),
            200,
          );
        }
        return jsonResponse({
          'errorCode': 'RESPONSIBLE_CHANGED',
          'responsible_version': 3,
          'participation': _restricted(version: 1),
        }, 409);
      };
      now = now.add(const Duration(hours: 1));
      await store.sendNow(callId);
      final report = await sender.run(access());
      expect(report.rejected, 1);
      final sent = requests.where((r) => r.url.path.endsWith('/consent')).last;
      expect(sent.headers['x-joint-purchase-contract'], '3');
      expect(
        jsonDecode(sent.body),
        containsPair('authorize_responsible', true),
      );
      expect(jsonDecode(sent.body), containsPair('responsible_version', 2));
      final rejected = (await store.consentOp(op.operationId))!;
      expect(
        [rejected.sendStatus, rejected.lastCode],
        [JointPurchaseOpStatus.rejected, 'RESPONSIBLE_CHANGED'],
      );
      final call = (await store.call(callId))!;
      expect(call.responsibleVersion, 3);
      expect(call.needsResponsibleReview, isTrue);
      expect(call.authorizationOutdated, isTrue);
      expect(
        call.serverParticipation!.consentScope,
        JointPurchaseConsentScope.responsibleOnly,
      );

      // Revisa de nuevo para la v3 y el sindicato la aplica.
      final again = (await store.decideConsent(
        callId: callId,
        scope: JointPurchaseConsentScope.responsibleOnly,
        decidedAt: now,
        authorizeResponsible: true,
      ))!;
      expect(again.responsibleVersion, 3);
      expect(again.sequence, greaterThan(op.sequence));
      respond = (request) => request.method == 'GET'
          ? jsonResponse(
              listJson([
                callJson(
                  responsibleVersion: 3,
                  participation: _authorized(3, scopeSequence: again.sequence),
                ),
              ]),
              200,
            )
          : jsonResponse({
              'outcome': 'ACCEPTED',
              'participation': _authorized(3, scopeSequence: again.sequence),
            }, 200);
      await sender.run(access());
      final applied = (await store.call(callId))!;
      expect(applied.needsResponsibleReview, isFalse);
      expect(applied.authorizationOutdated, isFalse);
      expect(
        (await store.consentOp(again.operationId))!.sendStatus,
        JointPurchaseOpStatus.received,
      );
    });

    test(
      'una respuesta atrasada no restablece una autorización anterior',
      () async {
        await seeded(
          version: 2,
          participation: _authorized(2, scopeSequence: 2),
        );
        // Llega tarde una respuesta de una decisión anterior (orden 1).
        final late = JointPurchaseParticipation.fromJson(
          _restricted(version: 1, scopeSequence: 1),
          products: {litreRef: 'ML', kiloRef: 'G'},
        );
        await seedCalls(store, memberA, [
          callJson(
            responsibleVersion: 2,
            participation: _authorized(2, scopeSequence: 2),
          ),
        ]);
        final before = (await store.call(callId))!.serverParticipation!;
        final op = (await store.decideConsent(
          callId: callId,
          scope: JointPurchaseConsentScope.collaborators,
          decidedAt: now,
        ))!;
        await store.markConsentStale(op, late);
        final after = (await store.call(callId))!.serverParticipation!;
        expect(after.responsibleAuthorized, before.responsibleAuthorized);
        expect(after.consentScopeSequence, 2);
      },
    );

    test('la primera confirmación lleva la versión de la responsable que se mostró', () async {
      await seeded(version: 4);
      final op = await store.confirm(
        callId: callId,
        lines: {litreRef: 1000},
        consentVersion: jointPurchaseConsentVersion,
        consentAcceptedAt: now,
      );
      expect(op.responsibleVersion, 4);
      respond = (_) => throw http.ClientException('sin red');
      await sender.run(access());
      final put = requests.firstWhere((r) => r.method == 'PUT');
      expect(jsonDecode(put.body), containsPair('responsible_version', 4));
    });

    testWidgets(
      'pantalla: aviso, casillas sin marcar, autorizar sólo a ella no amplía, pendiente no es aplicada',
      (tester) async {
        await tester.runAsync(
          () => seeded(version: 2, participation: _restricted()),
        );
        final call = (await tester.runAsync(() => store.call(callId)))!;
        var changed = 0;
        Future<void> pump(JointPurchaseCall shown) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => JointPurchaseResponsibleReview(
                  call: shown,
                  onChanged: () => changed++,
                ),
              ),
            ),
          ),
        );
        await pump(call);
        expect(
          find.text(jointPurchaseResponsibleChangedText(call)),
          findsOneWidget,
        );
        expect(
          jointPurchaseWhoCanSeeText(call),
          contains('Por ahora nadie de la Directiva'),
        );
        // El diálogo: dos casillas sin marcar; sólo la primera habilita autorizar.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: JointPurchaseResponsibleDialog(call: call)),
          ),
        );
        CheckboxListTile box(String key) =>
            tester.widget<CheckboxListTile>(find.byKey(Key(key)));
        FilledButton confirm() => tester.widget<FilledButton>(
          find.byKey(const Key('joint-responsible-confirm')),
        );
        expect(box('joint-responsible-check').value, isFalse);
        expect(box('joint-responsible-collaborators').value, isFalse);
        expect(box('joint-responsible-collaborators').onChanged, isNull);
        expect(confirm().onPressed, isNull);
        await tester.tap(find.byKey(const Key('joint-responsible-check')));
        await tester.pump();
        expect(confirm().onPressed, isNotNull);
        expect(box('joint-responsible-collaborators').value, isFalse);
        expect(box('joint-responsible-collaborators').onChanged, isNotNull);
        // Pendiente de envío: se dice y no se anuncia como aplicada.
        await tester.runAsync(
          () => store.decideConsent(
            callId: callId,
            scope: JointPurchaseConsentScope.responsibleOnly,
            decidedAt: now,
            authorizeResponsible: true,
          ),
        );
        final pending = (await tester.runAsync(() => store.call(callId)))!;
        await pump(pending);
        expect(
          find.byKey(const Key('joint-responsible-pending')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('joint-responsible-authorize')),
          findsNothing,
        );
        expect(changed, 0);
        // En una cancelada no se ofrece nada.
        await tester.runAsync(
          () => seeded(
            version: 2,
            status: 'CANCELLED',
            participation: _restricted(),
          ),
        );
        final cancelled = (await tester.runAsync(() => store.call(callId)))!;
        expect(cancelled.needsResponsibleReview, isFalse);
      },
    );

    test(
      'en una convocatoria cerrada se puede autorizar sin tocar el pedido',
      () async {
        await seeded(
          version: 2,
          status: 'CLOSED',
          participation: _restricted(),
        );
        final call = (await store.call(callId))!;
        expect(call.needsResponsibleReview, isTrue);
        final op = await store.decideConsent(
          callId: callId,
          scope: JointPurchaseConsentScope.responsibleOnly,
          decidedAt: now,
          authorizeResponsible: true,
        );
        expect(op, isNotNull);
        await expectLater(
          store.confirm(callId: callId, lines: {litreRef: 1}),
          throwsA(isA<JointPurchaseException>()),
        );
      },
    );
  });
}
