// Contrato E2-D14 y §5.6: confirmar, retirar y enviar no cambian ninguna
// fila de compras, aplicaciones, inventario, cuentas, necesidad declarada ni
// sync_outbox (recuentos y sumas de comprobación antes y después). Y la lista
// cerrada del parser: una clave desconocida rechaza la respuesta entera.
import 'dart:convert';
import 'dart:math';

import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/joint_purchase_api.dart';
import 'package:agroquimicos/services/sync/joint_purchase_sender.dart';
import 'package:agroquimicos/services/sync/sync_access.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e2_joint_purchase_fixtures.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f05_sync_fixtures.dart';

/// Tablas que una participación nunca debe tocar.
const _guarded = [
  'purchases',
  'purchase_items',
  'applications',
  'application_items',
  'inventory_lots',
  'inventory_movements',
  'account_transactions',
  'declared_needs',
  'declared_need_versions',
  'sync_outbox',
  'products',
  'campaigns',
];

void main() {
  sqfliteFfiInit();

  group('sin efectos fuera de su canal', () {
    test('confirmar + retirar + enviar no cambia recuentos ni sumas de comprobación', () async {
      final now = DateTime.utc(2026, 11, 11, 18, 20);
      final fixture = await seedSyncFixture();
      // Datos en las tablas vigiladas: una compra, una necesidad declarada.
      final repo = fixture.repo;
      final person =
          (await (await fixture.database.database).query('owner_bindings'))
                  .single['person_id']!
              as int;
      final supplier = await repo.addSupplier(name: 'Proveedor sintético');
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: fixture.campaignId,
          purchaseDate: DateTime(2026, 9, 15),
          items: [
            PurchaseItemDraft(
              productId: fixture.litreProductId,
              quantityBase: 5000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 1000,
              allocations: [
                AllocationDraft(personId: person, quantityBase: 5000),
              ],
            ),
          ],
        ),
      );
      await fixture.needs.declare(
        referenceDate: inCampaign,
        productId: fixture.litreProductId,
        quantityBase: 12000,
      );

      Future<Map<String, String>> snapshot() async {
        final db = await fixture.database.database;
        return {
          for (final table in _guarded)
            table: await () async {
              final rows = await db.query(table, orderBy: 'rowid');
              return '${rows.length}:'
                  '${crypto.sha256.convert(utf8.encode(jsonEncode(rows)))}';
            }(),
        };
      }

      final before = await snapshot();
      expect(before['purchases'], startsWith('1:'));
      expect(before['sync_outbox'], startsWith('1:'));

      final store = JointPurchaseStore(
        fixture.database,
        clock: () => now,
        random: Random(1),
      );
      final accepted = <String, Map<String, Object?>>{};
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return jsonResponse(
            listJson([callJson(participation: accepted[callId])]),
            200,
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final withdraw = request.url.path.endsWith('/withdraw');
        accepted[callId] = participationJson(
          lastSequence: body['sequence'] as int,
          withdrawn: withdraw,
        );
        return jsonResponse({
          'outcome': 'ACCEPTED',
          'participation': accepted[callId],
        }, 200);
      });
      final config = ApiEndpointConfig(Uri.parse('https://sindicato.example'));
      final api = JointPurchaseApi(
        json: AuthHttpClient(config: config, client: client),
      );
      final sender = JointPurchaseSender(
        store: store,
        owners: fixture.owners,
        api: () => api,
        clock: () => now,
      );
      final access = VerifiedAccess(
        accessToken: 'token-sintetico',
        scope: memberA,
        obtainedAt: now,
      );

      await sender.run(access, forceList: true);
      await store.markSeen(callId);
      await store.confirm(
        callId: callId,
        lines: {litreRef: 25000},
        consentVersion: jointPurchaseConsentVersion,
        consentAcceptedAt: now,
      );
      expect((await sender.run(access)).received, 1);
      await store.withdraw(callId);
      expect((await sender.run(access)).received, 1);

      expect(await snapshot(), before);
      expect(
        (await store.ops(callId)).map((op) => op.sendStatus),
        everyElement(JointPurchaseOpStatus.received),
      );
    });
  });

  group('parser con lista cerrada', () {
    test('acepta la forma exacta y normaliza los instantes a UTC', () {
      final calls = JointPurchaseCallView.listFromJson(
        listJson([
          callJson(
            participation: participationJson(lines: {kiloRef: 4500}),
            extra: const {'deadline_at': '2026-11-20T18:00:00-04:00'},
          ),
        ]),
      );
      expect(calls.single.deadlineAt, '2026-11-20T22:00:00.000Z');
      expect(calls.single.participation!.lines, {kiloRef: 4500});
      expect(calls.single.products.map((p) => p.baseUnit), ['ML', 'G']);
    });

    void rejects(Object? json, String reason) => expect(
      () => JointPurchaseCallView.listFromJson(json),
      throwsA(isA<JointPurchaseFormatException>()),
      reason: reason,
    );

    test(
      'en CLOSED se guarda la participación tal como entró al consolidado',
      () {
        Map<String, Object?> closing(bool included) => {
          'cutoff_at': deadline,
          'closed_at': deadline,
          'included': included,
          'lines': included
              ? [
                  {
                    'product_ref': litreRef,
                    'base_unit': 'ML',
                    'quantity_base': '25000',
                  },
                ]
              : <Object?>[],
        };
        final calls = JointPurchaseCallView.listFromJson(
          listJson([
            callJson(
              status: 'CLOSED',
              participation: participationJson(),
              closing: closing(true),
            ),
            callJson(
              id: otherCallId,
              status: 'CLOSED',
              participation: participationJson(withdrawn: true),
              closing: closing(false),
            ),
          ]),
        );
        expect(calls[0].acceptedForDisplay!.lines, {litreRef: 25000});
        expect(calls[1].closingIncluded, isFalse);
        expect(calls[1].acceptedForDisplay, isNull);
      },
    );

    test(
      'una clave desconocida en cualquier nivel rechaza la respuesta entera',
      () {
        rejects({
          ...listJson([callJson()]),
          'total': 3,
        }, 'raíz');
        rejects(
          listJson([
            callJson(),
            callJson(id: otherCallId, extra: const {'participants': []}),
          ]),
          'convocatoria',
        );
        rejects(
          listJson([
            callJson(
              participation: {...participationJson(), 'member_name': 'X'},
            ),
          ]),
          'participación',
        );
        final product = {
          'product_ref': litreRef,
          'name': 'Herbicida central',
          'unit': 'L',
          'base_unit': 'ML',
          'total_requested': '1000',
        };
        rejects(
          listJson([
            callJson(
              extra: {
                'products': [product],
              },
            ),
          ]),
          'producto',
        );
      },
    );

    test('rechaza formas inválidas del contrato', () {
      rejects(listJson([callJson(status: 'DRAFT')]), 'borrador');
      rejects({'calls': <Object?>[]}, 'sin contractVersion');
      rejects(
        listJson([
          callJson(extra: const {'call_id': 'NO-ES-UUID'}),
        ]),
        'id',
      );
      rejects(
        listJson([
          callJson(participation: participationJson(lines: {otherLitreRef: 1})),
        ]),
        'línea fuera de la convocatoria',
      );
      rejects(
        listJson([
          callJson(
            participation: {
              ...participationJson(),
              'lines': [
                {
                  'product_ref': litreRef,
                  'base_unit': 'ML',
                  'quantity_base': '0',
                },
              ],
            },
          ),
        ]),
        'cantidad cero',
      );
      rejects(
        listJson([
          callJson(
            participation: {
              ...participationJson(),
              'lines': [
                {
                  'product_ref': litreRef,
                  'base_unit': 'ML',
                  'quantity_base': 25000,
                },
              ],
            },
          ),
        ]),
        'cantidad no textual',
      );
      rejects(
        listJson([
          callJson(extra: const {'deadline_at': '2026-11-20 22:00'}),
        ]),
        'fecha sin zona',
      );
      rejects(listJson([callJson(), callJson()]), 'repetida');
      rejects(
        listJson([
          callJson(
            participation: {
              ...participationJson(),
              'lines': [
                {
                  'product_ref': litreRef,
                  'base_unit': 'G',
                  'quantity_base': '1',
                },
              ],
            },
          ),
        ]),
        'unidad base distinta de la del producto',
      );
      rejects({
        ...listJson([callJson()]),
        'consent': {'version': 'CONV-2', 'text': 'otro'},
      }, 'consentimiento distinto del de este teléfono');
      rejects(
        listJson([
          callJson(
            closing: {
              'cutoff_at': deadline,
              'closed_at': deadline,
              'included': true,
              'lines': <Object?>[],
            },
          ),
        ]),
        'consolidado en una convocatoria abierta',
      );
    });

    test(
      'errores: CALL_NOT_OPEN con reason y STALE_SEQUENCE con participación',
      () {
        final products = {litreRef: 'ML', kiloRef: 'G'};
        expect(
          JointPurchaseErrorBody.tryParse({
            'errorCode': 'CALL_NOT_OPEN',
            'reason': 'DEADLINE_PASSED',
          }, products)!.reason,
          'DEADLINE_PASSED',
        );
        expect(
          JointPurchaseErrorBody.tryParse({
            'errorCode': 'CALL_NOT_OPEN',
            'reason': 'OTRO',
          }, products),
          isNull,
        );
        expect(
          JointPurchaseErrorBody.tryParse({
            'errorCode': 'STALE_SEQUENCE',
            'participation': participationJson(lastSequence: 3),
          }, products)!.participation!.lastSequence,
          3,
        );
        expect(
          () => parseAcceptedResponse({
            'outcome': 'ACCEPTED',
            'participation': participationJson(),
            'echo': 'x',
          }, products),
          throwsA(isA<JointPurchaseFormatException>()),
        );
      },
    );
  });
}
