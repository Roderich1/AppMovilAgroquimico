// F05 Mobile: cantidades exactas (F06 §2) y planificación causal de las
// intenciones (contrato F05 §5–§6; MOB #30/#31).

import 'package:agroquimicos/domain/numeric_input.dart';
import 'package:agroquimicos/domain/sync/intention_planner.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:flutter_test/flutter_test.dart';

OutboxEntry entry({
  required SyncAction action,
  String operationId = '11111111-1111-4111-8111-111111111111',
  OutboxStatus status = OutboxStatus.acked,
  int attempts = 1,
  String? quantity = '1000',
  String? predecessor,
  PredecessorKind? predecessorKind,
  String? reference,
  String? resolvedHead,
  PredecessorKind? resolvedHeadKind,
}) => OutboxEntry(
  id: 1,
  operationId: operationId,
  ownerBindingId: 1,
  projectionType: ProjectionType.declaredNeed,
  action: action,
  campaignRef: '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
  productRef: '2a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
  baseUnit: BaseUnit.ml,
  quantityBase: action == SyncAction.cancel ? null : quantity,
  predecessorOperationId: predecessor,
  predecessorKind: predecessorKind,
  reconciliationReference: reference,
  status: status,
  attempts: attempts,
  resolutionHeadOperationId: resolvedHead,
  resolutionHeadKind: resolvedHeadKind,
  resolvedAt: resolvedHead == null ? null : '2026-10-15T00:00:00.000Z',
  createdAt: '2026-10-15T00:00:00.000Z',
);

const p = '11111111-1111-4111-8111-111111111111';
const q = '22222222-2222-4222-8222-222222222222';
const head = '33333333-3333-4333-8333-333333333333';
const ref = '44444444-4444-4444-8444-444444444444';

void main() {
  group('cantidad en unidades base sin coma flotante (F06 §2)', () {
    final cases = <String, int>{
      '0': 0,
      '1': 1000,
      '1,5': 1500,
      '12,25': 12250,
      '1.500': 1500000,
      '1.500,25': 1500250,
      '1,2340': 1234,
      '0,001': 1,
      '9.007.199.254.740,993': 9007199254740993,
    };
    for (final c in cases.entries) {
      test('«${c.key}» → ${c.value}', () {
        final result = parseBaseQuantity(c.key);
        expect(result.base, c.value);
        expect(result.message, isNull);
      });
    }

    test('el valor exacto no pasa por double (supera 2^53)', () {
      // 9 007 199 254 740,993 L = 9 007 199 254 740 993 ML: no representable
      // como double, sí como entero.
      expect(parseBaseQuantity('9.007.199.254.740,993').base, 9007199254740993);
    });

    test('un cuarto decimal distinto de cero se rechaza, no se redondea', () {
      final result = parseBaseQuantity('1,2345');
      expect(result.base, isNull);
      expect(result.message, contains('tres decimales'));
    });

    test('ambiguo, mal formado, vacío y desbordado se rechazan', () {
      for (final raw in ['1,500', '1.5', '-1', 'abc', '', '9223372036854776']) {
        expect(parseBaseQuantity(raw).base, isNull, reason: raw);
      }
    });

    test('el máximo int64 es exacto', () {
      expect(parseBaseQuantity('9223372036854775,807').base, maxBaseQuantity);
      expect(parseBaseQuantity('9223372036854775,808').base, isNull);
    });
  });

  group('planificación causal (F05 §6)', () {
    test(
      'sin intención previa: PUBLISH sin antecesor; retirar no envía nada',
      () {
        final plan = planIntention(null, const ValueIntent(5000));
        expect(plan, isA<EnqueuePlan>());
        final intention = (plan as EnqueuePlan).intention;
        expect(intention.action, SyncAction.publish);
        expect(intention.causal.predecessorOperationId, isNull);
        expect(intention.quantityBase, '5000');
        expect(
          planIntention(null, const CancelIntent()),
          isA<NothingToSendPlan>(),
        );
      },
    );

    test('tras un valor aceptado: SUPERSEDE o CANCEL contra él', () {
      final prior = entry(action: SyncAction.publish, operationId: p);
      final value =
          (planIntention(prior, const ValueIntent(0)) as EnqueuePlan).intention;
      expect(value.action, SyncAction.supersede);
      expect(value.causal.predecessorOperationId, p);
      expect(value.quantityBase, '0');
      final cancel =
          (planIntention(prior, const CancelIntent()) as EnqueuePlan).intention;
      expect(cancel.action, SyncAction.cancel);
      expect(cancel.quantityBase, isNull);
      expect(cancel.causal.predecessorOperationId, p);
    });

    test('tras una retirada: sólo PUBLISH; otra retirada no se envía', () {
      final prior = entry(
        action: SyncAction.cancel,
        operationId: q,
        predecessor: p,
        predecessorKind: PredecessorKind.value,
      );
      final value =
          (planIntention(prior, const ValueIntent(7)) as EnqueuePlan).intention;
      expect(value.action, SyncAction.publish);
      expect(value.causal.predecessorOperationId, q);
      expect(value.causal.predecessorKind, PredecessorKind.cancel);
      expect(
        planIntention(prior, const CancelIntent()),
        isA<NothingToSendPlan>(),
      );
    });

    test('una intención en vuelo no se modifica: la nueva la continúa', () {
      for (final status in [
        OutboxStatus.sending,
        OutboxStatus.outcomeUnknown,
        OutboxStatus.authPaused,
        OutboxStatus.restorePaused,
      ]) {
        final prior = entry(
          action: SyncAction.publish,
          operationId: p,
          status: status,
          attempts: status == OutboxStatus.restorePaused ? 0 : 1,
        );
        final plan = planIntention(prior, const ValueIntent(9));
        expect(plan, isA<EnqueuePlan>(), reason: status.code);
        expect(
          (plan as EnqueuePlan).intention.causal.predecessorOperationId,
          p,
        );
      }
    });

    test(
      'una pendiente que nunca salió se reescribe con el mismo antecesor',
      () {
        final unsent = entry(
          action: SyncAction.supersede,
          status: OutboxStatus.pending,
          attempts: 0,
          predecessor: p,
          predecessorKind: PredecessorKind.value,
        );
        final rewrite = planIntention(unsent, const ValueIntent(42));
        expect(rewrite, isA<RewritePlan>());
        final intention = (rewrite as RewritePlan).intention;
        expect(intention.action, SyncAction.supersede);
        expect(intention.causal.predecessorOperationId, p);
        expect(intention.quantityBase, '42');
        final cancel = planIntention(unsent, const CancelIntent());
        expect((cancel as RewritePlan).intention.action, SyncAction.cancel);
      },
    );

    test('el primer PUBLISH nunca enviado se descarta al retirar', () {
      final unsent = entry(
        action: SyncAction.publish,
        status: OutboxStatus.pending,
        attempts: 0,
      );
      expect(planIntention(unsent, const CancelIntent()), isA<DiscardPlan>());
    });

    test('una republicación nunca enviada se descarta: queda la retirada', () {
      final unsent = entry(
        action: SyncAction.publish,
        status: OutboxStatus.pending,
        attempts: 0,
        predecessor: q,
        predecessorKind: PredecessorKind.cancel,
      );
      expect(planIntention(unsent, const CancelIntent()), isA<DiscardPlan>());
    });

    test('un conflicto sin resolver exige la decisión del propietario', () {
      final conflict = entry(
        action: SyncAction.supersede,
        status: OutboxStatus.conflict,
        predecessor: p,
        predecessorKind: PredecessorKind.value,
      );
      expect(
        planIntention(conflict, const ValueIntent(1)),
        isA<ResolveConflictFirstPlan>(),
      );
    });

    test(
      'un conflicto resuelto se continúa desde el head que mostró Central',
      () {
        final resolved = entry(
          action: SyncAction.supersede,
          status: OutboxStatus.conflict,
          predecessor: p,
          predecessorKind: PredecessorKind.value,
          resolvedHead: head,
          resolvedHeadKind: PredecessorKind.cancel,
        );
        final plan = planIntention(resolved, const ValueIntent(3));
        final intention = (plan as EnqueuePlan).intention;
        expect(intention.action, SyncAction.publish);
        expect(intention.causal.predecessorOperationId, head);
        expect(intention.causal.reconciliationReference, isNull);
      },
    );

    test(
      'resolución sobre una retirada en disputa: PUBLISH o reafirmar CANCEL',
      () {
        const disputed = CausalContext(
          predecessorOperationId: head,
          predecessorKind: PredecessorKind.cancel,
          reconciliationReference: ref,
        );
        expect(
          actionFor(const ValueIntent(1), disputed)!.action,
          SyncAction.publish,
        );
        final reaffirm = actionFor(const CancelIntent(), disputed)!;
        expect(reaffirm.action, SyncAction.cancel);
        expect(reaffirm.causal.reconciliationReference, ref);
      },
    );
  });
}
