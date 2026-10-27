// Presentación de los códigos técnicos de la outbox (C-03): cada familia de
// `last_code` tiene una frase en palabras del agricultor; el código no cambia
// ni se pierde (sigue en la fila y en el detalle técnico de Sincronización).
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/presentation/widgets/sync_status_banner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('syncCodeFamily', () {
    test('sin código o aceptación: nada que explicar', () {
      expect(syncCodeFamily(null), SyncCodeFamily.none);
      expect(syncCodeFamily('OK'), SyncCodeFamily.none);
      expect(syncCodeExplanation(null), isNull);
      expect(syncCodeExplanation('OK'), isNull);
    });

    test('red e incertidumbre (API, worker, ACK, 5xx)', () {
      for (final code in [
        'TIMEOUT',
        'NETWORK',
        'TRANSPORT',
        'INVALID_ACK',
        'UNAVAILABLE',
        'INVALID_RESPONSE',
        'OPERATION_NOT_FOUND',
        'TRANSIENT_UNAVAILABLE',
        'TEMPORARILY_UNAVAILABLE',
        'RATE_LIMITED',
        'OPERATION_IN_PROGRESS',
        'DEPENDENCY_PENDING',
        'HTTP_500',
        'HTTP_502',
        'HTTP_503',
      ]) {
        expect(syncCodeFamily(code), SyncCodeFamily.network, reason: code);
        expect(
          syncCodeExplanation(code),
          'Sin respuesta del sindicato; se volverá a intentar con el mismo '
          'envío',
          reason: code,
        );
      }
    });

    test('autorización (401/403): la intención espera, no es rechazo', () {
      for (final code in ['AUTH_REQUIRED', 'AUTH_CONTEXT_FORBIDDEN']) {
        expect(
          syncCodeFamily(code),
          SyncCodeFamily.authorization,
          reason: code,
        );
        expect(
          syncCodeExplanation(code),
          'Falta verificar el acceso',
          reason: code,
        );
      }
    });

    test('titularidad no reconocida: rechazo terminal, frase propia', () {
      for (final code in ['OWNERSHIP_NOT_PROVEN', 'PURPOSE_NOT_AUTHORIZED']) {
        expect(syncCodeFamily(code), SyncCodeFamily.ownership, reason: code);
        expect(
          syncCodeExplanation(code),
          'El sindicato no reconoció a esta cuenta como titular de estos '
          'datos; este envío no se aplicó',
          reason: code,
        );
        expect(
          syncCodeExplanation(code),
          isNot(contains('verificar el acceso')),
          reason: code,
        );
      }
    });

    test('referencias, unidad y cantidad', () {
      for (final code in [
        'REFERENCE_UNAVAILABLE',
        'UNIT_INCOMPATIBLE',
        'QUANTITY_INVALID',
      ]) {
        expect(syncCodeFamily(code), SyncCodeFamily.references, reason: code);
        expect(
          syncCodeExplanation(code),
          'El sindicato no reconoce el producto o la campaña vinculados: '
          'revise los vínculos',
          reason: code,
        );
      }
    });

    test('códigos de ACK CONFLICT: decide el propietario', () {
      for (final code in [
        'CAUSAL_FORK',
        'STALE_PREDECESSOR',
        'CANCELLED_PREDECESSOR',
        'RECONCILIATION_STALE',
      ]) {
        expect(syncCodeFamily(code), SyncCodeFamily.causality, reason: code);
        expect(
          syncCodeExplanation(code),
          'Hay otra versión en el sindicato: decida en Necesidades o Consumo',
          reason: code,
        );
      }
    });

    test('códigos de ACK REJECTED por causalidad: no hay nada que decidir', () {
      for (final code in [
        'IDEMPOTENCY_MISMATCH',
        'INVALID_PREDECESSOR',
        'INVALID_TRANSITION',
        'CAUSAL_FENCED',
      ]) {
        expect(
          syncCodeFamily(code),
          SyncCodeFamily.rejectedVersion,
          reason: code,
        );
        expect(
          syncCodeExplanation(code),
          'El sindicato ya tenía otra versión; este envío no se aplicó. Si '
          'hace falta, declare o publique de nuevo',
          reason: code,
        );
        expect(
          syncCodeExplanation(code),
          isNot(contains('decida')),
          reason: code,
        );
      }
    });

    test('estado de la campaña: conserva la explicación RF-03 §2.4', () {
      expect(syncCodeFamily('CAMPAIGN_SEALED'), SyncCodeFamily.campaignState);
      expect(syncCodeFamily('CAMPAIGN_NOT_OPEN'), SyncCodeFamily.campaignState);
      expect(
        syncCodeExplanation('CAMPAIGN_SEALED'),
        rejectionExplanation('CAMPAIGN_SEALED'),
      );
      expect(syncCodeExplanation('CAMPAIGN_SEALED'), contains('sellada'));
      expect(
        syncCodeExplanation('CAMPAIGN_NOT_OPEN'),
        rejectionExplanation('CAMPAIGN_NOT_OPEN'),
      );
    });

    test('request no admitido y versión del contrato', () {
      for (final code in [
        'INVALID_REQUEST',
        'FIELD_NOT_ALLOWED',
        'UNSUPPORTED_MEDIA_TYPE',
        'REQUEST_TOO_LARGE',
        'CONTRACT_VERSION_MISMATCH',
      ]) {
        expect(syncCodeFamily(code), SyncCodeFamily.request, reason: code);
        expect(syncCodeExplanation(code), contains('nada se borró'));
      }
    });

    test('un código desconocido tiene frase genérica, nunca el código', () {
      expect(syncCodeFamily('ALGO_NUEVO'), SyncCodeFamily.other);
      final text = syncCodeExplanation('ALGO_NUEVO')!;
      expect(text, contains('detalle técnico'));
      expect(text, isNot(contains('ALGO_NUEVO')));
    });

    test('ninguna frase contiene un código técnico ni «ACK»', () {
      for (final code in [
        'TIMEOUT',
        'HTTP_500',
        'AUTH_REQUIRED',
        'OWNERSHIP_NOT_PROVEN',
        'REFERENCE_UNAVAILABLE',
        'CAUSAL_FORK',
        'IDEMPOTENCY_MISMATCH',
        'CAMPAIGN_SEALED',
        'INVALID_REQUEST',
        'OTRO',
      ]) {
        final text = syncCodeExplanation(code)!;
        expect(text, isNot(contains(code)), reason: code);
        expect(text, isNot(contains('ACK')), reason: code);
        expect(text, isNot(contains('_')), reason: code);
      }
    });
  });

  group('fila de Sincronización', () {
    OutboxEntry entry(OutboxStatus status, String? code, {int attempts = 1}) =>
        OutboxEntry(
          id: 1,
          operationId: '7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
          ownerBindingId: 1,
          projectionType: ProjectionType.declaredNeed,
          action: SyncAction.publish,
          campaignRef: 'c',
          productRef: 'p',
          baseUnit: BaseUnit.ml,
          quantityBase: '1000',
          predecessorOperationId: null,
          predecessorKind: null,
          reconciliationReference: null,
          status: status,
          attempts: attempts,
          lastCode: code,
          createdAt: '2026-10-26T12:00:00.000Z',
        );

    test('pausa por autorización: una sola frase, sin repetir', () {
      final row = entry(OutboxStatus.authPaused, 'AUTH_CONTEXT_FORBIDDEN');
      expect(rowExplanation(row), isNull);
      final text = rowSubtitle(row);
      expect(text, contains('Pausado: el sindicato no autorizó esta cuenta'));
      expect(text, isNot(contains('Falta verificar el acceso')));
    });

    test('pendiente tras un 401: la explicación sí añade algo', () {
      final row = entry(OutboxStatus.pending, 'AUTH_REQUIRED');
      expect(rowExplanation(row), 'Falta verificar el acceso');
    });

    test('«Decidir…» sólo en conflicto; «Revisar…» en rechazos', () {
      expect(
        decisionLabel(entry(OutboxStatus.conflict, 'CAUSAL_FORK')),
        'Decidir…',
      );
      expect(
        decisionLabel(entry(OutboxStatus.rejected, 'IDEMPOTENCY_MISMATCH')),
        'Revisar…',
      );
      expect(
        decisionLabel(entry(OutboxStatus.failed, 'INVALID_REQUEST')),
        'Revisar…',
      );
      expect(
        needsDecision(entry(OutboxStatus.pending, null, attempts: 0)),
        isFalse,
      );
      expect(needsDecision(entry(OutboxStatus.acked, 'OK')), isFalse);
    });
  });

  group('outboxStatusPhrase', () {
    test('pendiente: guardada hasta el primer intento, enviada después', () {
      expect(
        outboxStatusPhrase(OutboxStatus.pending, attempts: 0),
        'Guardado, pendiente de envío',
      );
      expect(
        outboxStatusPhrase(OutboxStatus.pending, attempts: 0, feminine: true),
        'Guardada, pendiente de envío',
      );
      expect(
        outboxStatusPhrase(OutboxStatus.pending, attempts: 2),
        'Enviado, sin confirmación',
      );
      expect(
        outboxStatusPhrase(OutboxStatus.outcomeUnknown, attempts: 1),
        'Enviado, sin confirmación',
      );
    });

    test('aceptado, rechazado, conflicto y pausas, en palabras', () {
      expect(
        outboxStatusPhrase(OutboxStatus.acked, attempts: 1, feminine: true),
        'Aceptada por el sindicato',
      );
      expect(
        outboxStatusPhrase(OutboxStatus.rejected, attempts: 1),
        'Rechazado por el sindicato',
      );
      expect(
        outboxStatusPhrase(OutboxStatus.conflict, attempts: 1),
        'En conflicto: decida usted',
      );
      expect(
        outboxStatusPhrase(
          OutboxStatus.conflict,
          attempts: 1,
          conflictResolved: true,
        ),
        'Conflicto resuelto por usted; se enviará su decisión',
      );
      expect(
        outboxStatusPhrase(OutboxStatus.authPaused, attempts: 1),
        'Pausado: el sindicato no autorizó esta cuenta',
      );
      expect(
        outboxStatusPhrase(
          OutboxStatus.authPaused,
          attempts: 1,
          feminine: true,
        ),
        'Pausada: el sindicato no autorizó esta cuenta',
      );
      expect(
        outboxStatusPhrase(OutboxStatus.restorePaused, attempts: 0),
        'Pausado: llegó con un respaldo restaurado',
      );
      for (final status in OutboxStatus.values) {
        final text = outboxStatusPhrase(status, attempts: 1);
        expect(text, isNot(contains('_')), reason: status.code);
        expect(text, isNot(contains('ACK')), reason: status.code);
      }
    });

    test('los chips y el indicador conservan sus etiquetas cortas', () {
      expect(outboxStatusLabel(OutboxStatus.pending), 'Pendiente');
      expect(outboxStatusLabel(OutboxStatus.rejected), 'Rechazado');
      expect(outboxStatusLabel(OutboxStatus.conflict), 'Conflicto');
    });
  });
}
