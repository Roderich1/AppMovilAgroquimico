// E4 §6.3 (sustituye a P-A C1, E2 §12): la persona responsable sólo indica
// quién coordina. Tras una sustitución el teléfono no pide una autorización
// nueva por responsable: lo que ve la Administración depende del
// consentimiento CONV-4, no de quién es la responsable. El contrato 4 ya no
// trae la versión de la responsabilidad ni la autorización de P-A; lo que el
// teléfono guardó de ellas se conserva como historia. Las autorizaciones de
// P-A que quedaron pendientes salen tal cual y el sindicato las rechaza de
// forma definitiva. Lo que antes cubría «autorizar a la nueva responsable»
// pasa a «Revisar quién puede ver mi participación» con CONV-4. Sin red real;
// datos sintéticos.
import 'dart:convert';
import 'dart:math';

import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/presentation/widgets/joint_purchase_access_review.dart';
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

const _products = {litreRef: 'ML', kiloRef: 'G'};

void main() {
  sqfliteFfiInit();

  group('contrato 4: sin versión de la responsabilidad ni autorización de P-A', () {
    test('la lista sólo trae el nombre de quien coordina; la versión de P-A se rechaza entera', () {
      final view = JointPurchaseCallView.fromJson(
        callJson(responsibleName: 'Nueva responsable sintética'),
      );
      expect(view.responsibleName, 'Nueva responsable sintética');
      expect(
        () => JointPurchaseCallView.fromJson(callJson(responsibleVersion: 2)),
        throwsA(isA<JointPurchaseFormatException>()),
      );
      expect(
        () => JointPurchaseCallView.fromJson(
          callJson(
            participation: participationJson(
              responsibleAuthorization: {'authorized': true, 'version': 1},
            ),
          ),
        ),
        throwsA(isA<JointPurchaseFormatException>()),
      );
    });

    test('una copia guardada con la autorización de P-A se sigue leyendo (historia), sin decidir nada', () {
      final stored = jsonEncode(
        participationJson(
          consentVersion: 'CONV-3',
          consentScope: 'RESPONSIBLE_ONLY',
          consentScopeVersion: 'CONV-3',
          responsibleAuthorization: {'authorized': true, 'version': 1},
        ),
      );
      final decoded = JointPurchaseParticipation.decode(stored)!;
      expect(decoded.responsibleAuthorized, isTrue);
      expect(decoded.responsibleAuthorizationVersion, 1);
      // Autorizada por P-A, pero con un alcance anterior: nadie ve el detalle.
      expect(decoded.coversDetail, isFalse);
      expect(decoded.hasLegacyScope, isTrue);
      // Al guardarla otra vez no se pierde.
      expect(jsonDecode(decoded.encode())['responsible_authorization'], {
        'authorized': true,
        'version': 1,
      });
    });
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
      now = DateTime.utc(2026, 11, 13, 15);
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
      required String responsible,
      Map<String, Object?>? participation,
      String status = 'OPEN',
    }) async {
      await seedCalls(store, memberA, [
        callJson(
          status: status,
          responsibleName: responsible,
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

    test('tras sustituir a la responsable no se pide autorización nueva: ADMINISTRATION sigue igual', () async {
      final before = await seeded(
        responsible: 'Responsable anterior',
        participation: participationJson(consentScope: 'ADMINISTRATION'),
      );
      final after = await seeded(
        responsible: 'Responsable sucesora',
        participation: participationJson(consentScope: 'ADMINISTRATION'),
      );
      expect(after.responsibleName, 'Responsable sucesora');
      expect(after.serverParticipation!.consentScope, 'ADMINISTRATION');
      expect(after.canReviewAccess, isFalse);
      expect(after.needsAccessReview, isFalse);
      // Quién ve los datos no depende de quién coordina.
      expect(
        jointPurchaseWhoCanSeeText(after),
        jointPurchaseWhoCanSeeText(before),
      );
      expect(jointPurchaseWhoCanSeeText(after), isNot(contains('responsable')));
      expect(await store.consentOps(callId), isEmpty);
    });

    test('la versión de la responsabilidad guardada en v19 se conserva al actualizar la lista', () async {
      await seeded(responsible: 'Responsable');
      final db = await fixture.database.database;
      await db.update(JointPurchaseStore.callsTable, {
        'responsible_version': 2,
      });
      await seeded(responsible: 'Responsable sucesora');
      expect(
        (await db.query(JointPurchaseStore.callsTable))
            .single['responsible_version'],
        2,
      );
    });

    test(
      'la primera confirmación ya no lleva la versión de la responsable',
      () async {
        await seeded(responsible: 'Responsable');
        final op = await store.confirm(
          callId: callId,
          lines: {litreRef: 1000},
          consentVersion: jointPurchaseConsentVersion,
          consentAcceptedAt: now,
        );
        expect(op.responsibleVersion, isNull);
        respond = (_) => throw http.ClientException('sin red');
        await sender.run(access());
        final put = requests.firstWhere((r) => r.method == 'PUT');
        final body = jsonDecode(put.body) as Map<String, dynamic>;
        expect(body.containsKey('responsible_version'), isFalse);
        expect(body['consent'], {
          'version': 'CONV-4',
          'accepted_at': now.toIso8601String(),
        });
      },
    );

    test('una autorización de P-A pendiente sale tal cual; CONSENT_VERSION_RETIRED la termina sin reintento y sin borrarla', () async {
      await seeded(
        responsible: 'Responsable sucesora',
        participation: participationJson(
          consentVersion: 'CONV-3',
          consentScope: 'RESPONSIBLE_ONLY',
          consentScopeVersion: 'CONV-3',
        ),
      );
      const id = '5e1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
      await (await fixture.database.database).insert(
        JointPurchaseStore.consentOpsTable,
        {
          'operation_id': id,
          'call_id': callId,
          'tenant_id': memberA.tenantId,
          'member_id': memberA.memberId,
          'sequence': 1,
          'scope': 'RESPONSIBLE_ONLY',
          'consent_version': 'CONV-3',
          'decided_at': '2026-11-12T09:00:00.000Z',
          'send_status': 'PENDING_SEND',
          'attempts': 0,
          'created_at': '2026-11-12T09:00:00.000Z',
          'updated_at': '2026-11-12T09:00:00.000Z',
          'responsible_version': 2,
          'authorize_responsible': 1,
        },
      );
      respond = (request) => request.method == 'POST'
          ? jsonResponse({'errorCode': 'CONSENT_VERSION_RETIRED'}, 409)
          : jsonResponse({'errorCode': 'TEMPORARILY_UNAVAILABLE'}, 503);
      final report = await sender.run(access());
      expect(report.rejected, 1);
      final post = requests.firstWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body), {
        'operation_id': id,
        'sequence': 1,
        'scope': 'RESPONSIBLE_ONLY',
        'consent': {
          'version': 'CONV-3',
          'decided_at': '2026-11-12T09:00:00.000Z',
        },
        'responsible_version': 2,
        'authorize_responsible': true,
      });
      final stored = (await store.consentOp(id))!;
      expect(stored.sendStatus, JointPurchaseOpStatus.rejected);
      expect(stored.lastCode, 'CONSENT_VERSION_RETIRED');
      requests.clear();
      now = now.add(const Duration(days: 1));
      await sender.run(access(), includePaused: true);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      // Sigue ofrecida la revisión con CONV-4 (lo antiguo no habilita a nadie).
      expect((await store.call(callId))!.needsAccessReview, isTrue);
    });

    testWidgets(
      'pantalla: la revisión muestra CONV-4 y su ayuda, casilla sin marcar, «Sus cantidades no cambian»; pendiente no es aplicada',
      (tester) async {
        await tester.runAsync(
          () => seeded(
            responsible: 'Responsable sucesora',
            participation: participationJson(
              consentVersion: 'CONV-3',
              consentScope: 'RESPONSIBLE_ONLY',
              consentScopeVersion: 'CONV-3',
            ),
          ),
        );
        final call = (await tester.runAsync(() => store.call(callId)))!;
        expect(call.needsAccessReview, isTrue);
        expect(
          jointPurchaseChips(call),
          contains(jointPurchaseAccessReviewChip),
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: JointPurchaseAccessReviewDialog()),
          ),
        );
        expect(find.text(jointPurchaseConsentText), findsOneWidget);
        expect(find.text(jointPurchaseConsentHelp), findsOneWidget);
        expect(find.text('Sus cantidades no cambian.'), findsOneWidget);
        // Ninguna mención a autorizar a la persona responsable.
        expect(find.textContaining('responsable'), findsNothing);
        CheckboxListTile box() => tester.widget<CheckboxListTile>(
          find.byKey(const Key('joint-access-review-check')),
        );
        FilledButton confirm() => tester.widget<FilledButton>(
          find.byKey(const Key('joint-access-review-confirm')),
        );
        expect(box().value, isFalse);
        expect(confirm().onPressed, isNull);
        await tester.tap(find.byKey(const Key('joint-access-review-check')));
        await tester.pump();
        expect(confirm().onPressed, isNotNull);

        await tester.runAsync(
          () => store.decideAccess(
            callId: callId,
            scope: JointPurchaseConsentScope.administration,
            decidedAt: now,
          ),
        );
        final pending = (await tester.runAsync(() => store.call(callId)))!;
        expect(
          jointPurchaseConsentPendingText(pending.pendingConsentOp!),
          contains('no está aplicada'),
        );
        expect(
          jointPurchaseWhoCanSeeText(pending),
          startsWith('Su participación se registró con un texto anterior.'),
        );
        expect(jointPurchaseChips(pending), [
          'Nueva',
          'Abierta',
          'Participación recibida',
          'Pendiente: quién ve sus datos',
        ]);
      },
    );

    test('en una convocatoria cerrada se revisa sin tocar el pedido', () async {
      await seeded(
        responsible: 'Responsable sucesora',
        status: 'CLOSED',
        participation: participationJson(consentScope: 'RESPONSIBLE_ONLY'),
      );
      final op = await store.decideAccess(
        callId: callId,
        scope: JointPurchaseConsentScope.administration,
        decidedAt: now,
      );
      expect(op, isNotNull);
      await expectLater(
        store.confirm(callId: callId, lines: {litreRef: 1}),
        throwsA(isA<JointPurchaseException>()),
      );
      expect(await store.ops(callId), isEmpty);
    });

    test('el error RESPONSIBLE_CHANGED de una app anterior se sigue leyendo sin datos ajenos', () {
      final body = JointPurchaseErrorBody.tryParse({
        'errorCode': 'RESPONSIBLE_CHANGED',
        'responsible_version': 3,
      }, _products);
      expect(body!.responsibleVersion, 3);
      expect(body.participation, isNull);
    });
  });
}
