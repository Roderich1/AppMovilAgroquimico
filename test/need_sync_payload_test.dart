// MOB #34: el contenido que se envía al sindicato sólo lleva la whitelist
// F06 (cuatro campos; CANCEL sin cantidad) y nada privado ni contextual.
import 'dart:convert';

import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/domain/sync/sync_wire.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/f05_sync_fixtures.dart';

const op = '11111111-1111-4111-8111-111111111111';

OutboxEntry entryFor(SyncAction action) => OutboxEntry(
  id: 1,
  operationId: op,
  ownerBindingId: 1,
  projectionType: ProjectionType.declaredNeed,
  action: action,
  campaignRef: campaignRef,
  productRef: litreRef,
  baseUnit: BaseUnit.ml,
  quantityBase: action == SyncAction.cancel ? null : '2500',
  predecessorOperationId: action == SyncAction.publish
      ? null
      : '22222222-2222-4222-8222-222222222222',
  predecessorKind: action == SyncAction.publish ? null : PredecessorKind.value,
  reconciliationReference: null,
  status: OutboxStatus.pending,
  attempts: 0,
  createdAt: '2026-10-15T00:00:00.000Z',
);

void main() {
  group('envelope v1 (§4, F06 §2)', () {
    test(
      'seis claves; payload con exactamente la whitelist de cada acción',
      () {
        final publish = envelopeOf(entryFor(SyncAction.publish));
        expect(publish.keys, {
          'contractVersion',
          'operationId',
          'projectionType',
          'action',
          'causal',
          'payload',
        });
        expect(publish['contractVersion'], 1);
        expect((publish['payload']! as Map).keys, {
          'campaign_ref',
          'product_ref',
          'base_unit',
          'quantity_base',
        });
        // La cantidad viaja como decimal en texto, nunca como número JSON.
        expect((publish['payload']! as Map)['quantity_base'], '2500');
        expect((publish['causal']! as Map).keys, {
          'predecessorOperationId',
          'reconciliationReference',
        });
        final cancel = envelopeOf(entryFor(SyncAction.cancel));
        expect((cancel['payload']! as Map).keys, {
          'campaign_ref',
          'product_ref',
          'base_unit',
        });
      },
    );

    test('nada privado ni contextual viaja en el envelope', () {
      final text = jsonEncode(envelopeOf(entryFor(SyncAction.supersede)));
      for (final forbidden in [
        'tenant',
        'member',
        'account',
        'clientId',
        'person',
        'name',
        'notes',
        'cost',
        'token',
      ]) {
        expect(text.toLowerCase(), isNot(contains(forbidden.toLowerCase())));
      }
    });
  });
}
