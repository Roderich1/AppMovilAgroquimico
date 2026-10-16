// F05 Mobile: validación estricta de ACK, errores, consulta owner-scoped,
// Retry-After y referencias centrales (contrato F05 §7–§11; C30).
import 'dart:convert';

import 'package:agroquimicos/domain/sync/central_references.dart';
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

Map<String, dynamic> decode(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

void main() {
  group('ACK (§7, C30)', () {
    test('aceptación válida', () {
      final ack = SyncAck.validate(decode(ackJson(op)), op)!;
      expect(ack.outcome, AckOutcome.applied);
      expect(ack.serverAcceptedAt, '2026-10-15T12:00:00.000Z');
      expect(
        SyncAck.validate(
          decode(ackJson(op, outcome: 'ALREADY_APPLIED')),
          op,
        )!.outcome,
        AckOutcome.alreadyApplied,
      );
    });

    test('ACK incompleto, ajeno o contradictorio no autoriza retirar', () {
      final valid = decode(ackJson(op));
      final cases = <String, Map<String, dynamic>>{
        'otra intención': {
          ...valid,
          'operationId': '99999999-9999-4999-8999-999999999999',
        },
        'falta una clave': Map.of(valid)..remove('code'),
        'clave extra': {...valid, 'extra': 1},
        'disposition contradictoria': {
          ...valid,
          'disposition': 'KEEP_FOR_RETRY',
        },
        'aceptación sin hora': {...valid, 'serverAcceptedAt': null},
        'hora mal formada': {...valid, 'serverAcceptedAt': '2026-10-15 12:00'},
        'código ajeno al outcome': {...valid, 'code': 'CAUSAL_FORK'},
        'versión distinta': {...valid, 'contractVersion': 2},
        'outcome desconocido': {...valid, 'outcome': 'DONE'},
        'referencia en una aceptación': {
          ...valid,
          'reconciliationReference': '66666666-6666-4666-8666-666666666666',
        },
      };
      for (final c in cases.entries) {
        expect(SyncAck.validate(c.value, op), isNull, reason: c.key);
      }
      expect(SyncAck.validate('no es un objeto', op), isNull);
      expect(SyncAck.validate(null, op), isNull);
    });

    test(
      'CONFLICT exige referencia UUID v4; REJECTED y RETRYABLE no la llevan',
      () {
        expect(
          SyncAck.validate(
            decode(ackJson(op, outcome: 'CONFLICT')),
            op,
          )!.reconciliationReference,
          isNotNull,
        );
        final noReference = decode(ackJson(op, outcome: 'CONFLICT'))
          ..['reconciliationReference'] = null;
        expect(SyncAck.validate(noReference, op), isNull);
        expect(
          SyncAck.validate(
            decode(ackJson(op, outcome: 'REJECTED', code: 'CAMPAIGN_NOT_OPEN')),
            op,
          )!.code,
          'CAMPAIGN_NOT_OPEN',
        );
        expect(
          SyncAck.validate(
            decode(
              ackJson(op, outcome: 'RETRYABLE', code: 'DEPENDENCY_PENDING'),
            ),
            op,
          )!.outcome,
          AckOutcome.retryable,
        );
      },
    );
  });

  group('errores (§9) y Retry-After (§11)', () {
    test('cuerpo cerrado de cuatro claves con su disposition', () {
      expect(
        SyncRequestError.validate(
          decode(errorJson('AUTH_REQUIRED', 'KEEP_FOR_RETRY')),
        )!.errorCode,
        'AUTH_REQUIRED',
      );
      expect(
        SyncRequestError.validate(
          decode(errorJson('AUTH_REQUIRED', 'MOVE_TO_TERMINAL_FAILURE')),
        ),
        isNull,
      );
      expect(SyncRequestError.validate({'message': 'proxy'}), isNull);
    });

    test(
      'Retry-After en segundos o fecha HTTP; ilegible no habilita bucle',
      () {
        final now = DateTime.utc(2026, 10, 15, 12);
        expect(parseRetryAfter('30', now), const Duration(seconds: 30));
        expect(
          parseRetryAfter('Thu, 15 Oct 2026 12:01:00 GMT', now),
          const Duration(minutes: 1),
        );
        expect(
          parseRetryAfter('Thu, 15 Oct 2026 11:00:00 GMT', now),
          Duration.zero,
        );
        expect(parseRetryAfter('pronto', now), isNull);
        expect(parseRetryAfter('-5', now), isNull);
        expect(parseRetryAfter(null, now), isNull);
      },
    );
  });

  group('consulta owner-scoped (§9)', () {
    test('exactamente {ack, contribution}, sin cantidades', () {
      final body = {
        'ack': decode(ackJson(op, outcome: 'ALREADY_APPLIED')),
        'contribution': {
          'status': 'CONTESTED',
          'headOperationId': '33333333-3333-4333-8333-333333333333',
          'reconciliationReference': '44444444-4444-4444-8444-444444444444',
        },
      };
      final view = OperationView.validate(body, op)!;
      expect(view.contribution!.status, 'CONTESTED');
      expect(view.contribution!.headKind, PredecessorKind.value);
      expect(OperationView.validate({...body, 'quantity': 1}, op), isNull);
      expect(
        OperationView.validate({
          ...body,
          'contribution': {...body['contribution']!, 'quantityBase': '1'},
        }, op),
        isNull,
      );
    });
  });

  group('referencias centrales (F05-SYNC-07)', () {
    test('whitelist cerrada; base_unit sólo para L/KG', () {
      final references = CentralReferences.fromJson(referencesJson());
      expect(references.campaigns.single.acceptsContributions, isTrue);
      expect(references.product(litreRef)!.baseUnit, BaseUnit.ml);
      expect(references.product(unitRef)!.linkable, isFalse);
    });

    test('un campo extra, una base incoherente o una referencia no canónica se rechazan enteros', () {
      Map<String, Object?> mutated(
        void Function(Map<String, Object?> json) change,
      ) {
        final json =
            jsonDecode(jsonEncode(referencesJson())) as Map<String, Object?>;
        change(json);
        return json;
      }

      final bad = [
        mutated((j) => j['extra'] = true),
        mutated(
          (j) => ((j['products']! as List).first as Map)['currentStock'] = 5,
        ),
        mutated(
          (j) => ((j['products']! as List).first as Map)['base_unit'] = 'G',
        ),
        mutated((j) => ((j['products']! as List)[1] as Map)['linkable'] = true),
        mutated(
          (j) => ((j['campaigns']! as List).first as Map)['campaign_ref'] =
              campaignRef.toUpperCase(),
        ),
        mutated((j) => j['contractVersion'] = 2),
      ];
      for (final json in bad) {
        expect(
          () => CentralReferences.fromJson(json.cast<String, dynamic>()),
          throwsA(isA<CentralReferencesFormatException>()),
        );
      }
    });
  });
}
