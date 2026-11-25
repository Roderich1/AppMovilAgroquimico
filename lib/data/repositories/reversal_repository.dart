import 'package:sqflite/sqflite.dart' show Transaction;

import '../../domain/sync/operation_id.dart' show newOperationId;
import '../../services/auth/local_owner_credential.dart';
import 'repository_exceptions.dart';
import 'repository_session.dart';
import 'repository_types.dart';
import 'reversal_operations.dart';

/// Sub-repositorio de reversiones auditadas RF-13 (aplicaciones, compras y
/// transferencias) y consulta de auditoría.
class ReversalRepository {
  ReversalRepository(this._session) : _ops = ReversalOperations(_session);

  final RepositorySession _session;
  final ReversalOperations _ops;

  /// RF-13: revierte una aplicación con la autorización del titular.
  Future<void> reverseApplication(
    int applicationId, {
    required String reason,
    required OwnerAuthorization authorization,
  }) => _authorizedReversal(
    type: 'APPLICATION',
    operationId: applicationId,
    purpose: AuthorizationPurpose.reverseApplication,
    reason: reason,
    authorization: authorization,
    effects: (txn, context, recorder) => _ops.reverseApplicationIn(
      txn,
      context,
      applicationId,
      reason.trim(),
      recorder,
    ),
  );

  /// Sólo pruebas: los efectos de la reversión sin auditoría ni autorización.
  Future<void> reverseApplicationUnauditedForTesting(
    int applicationId, {
    String? reason,
  }) => _session.write(
    (txn, context) => _ops.reverseApplicationIn(
      txn,
      context,
      applicationId,
      reason,
      ReversalEffects.discard(),
    ),
  );

  /// RF-13: revierte una compra con la autorización del titular.
  Future<void> reversePurchase(
    int purchaseId, {
    required String reason,
    required OwnerAuthorization authorization,
  }) => _authorizedReversal(
    type: 'PURCHASE',
    operationId: purchaseId,
    purpose: AuthorizationPurpose.reversePurchase,
    reason: reason,
    authorization: authorization,
    effects: (txn, context, recorder) => _ops.reversePurchaseIn(
      txn,
      context,
      purchaseId,
      reason.trim(),
      recorder,
    ),
  );

  /// Sólo pruebas: los efectos de la reversión sin auditoría ni autorización.
  Future<void> reversePurchaseUnauditedForTesting(
    int purchaseId, {
    String? reason,
  }) => _session.write(
    (txn, context) => _ops.reversePurchaseIn(
      txn,
      context,
      purchaseId,
      reason,
      ReversalEffects.discard(),
    ),
  );

  /// RF-13: revierte una transferencia con la autorización del titular.
  Future<void> reverseTransfer(
    int transferId, {
    required String reason,
    required OwnerAuthorization authorization,
  }) => _authorizedReversal(
    type: 'TRANSFER',
    operationId: transferId,
    purpose: AuthorizationPurpose.reverseTransfer,
    reason: reason,
    authorization: authorization,
    effects: (txn, context, recorder) => _ops.reverseTransferIn(
      txn,
      context,
      transferId,
      reason.trim(),
      recorder,
    ),
  );

  /// Sólo pruebas: los efectos de la reversión sin auditoría ni autorización.
  Future<void> reverseTransferUnauditedForTesting(
    int transferId, {
    String? reason,
  }) => _session.write(
    (txn, context) => _ops.reverseTransferIn(
      txn,
      context,
      transferId,
      reason,
      ReversalEffects.discard(),
    ),
  );

  /// RF-13 (§1): consume la autorización contra el vínculo vigente, aplica los
  /// efectos y escribe la auditoría y sus referencias en una transacción.
  Future<void> _authorizedReversal({
    required String type,
    required int operationId,
    required AuthorizationPurpose purpose,
    required String reason,
    required OwnerAuthorization authorization,
    required Future<OriginalOperation> Function(
      Transaction txn,
      WriteContext context,
      ReversalEffects effects,
    )
    effects,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw BusinessRuleException('Indique el motivo de la reversión.');
    }
    await _session.write((txn, context) async {
      final current = await _session.currentOwnerBinding(txn);
      final installation = _session.currentCredential();
      consumeOwnerAuthorization(
        authorization,
        installation: installation,
        purpose: purpose,
        subjectRef: '${type.toLowerCase()}:$operationId',
        current: current,
        now: DateTime.now(),
      );
      final recorder = ReversalEffects();
      final original = await effects(txn, context, recorder);
      final auditId = await txn.insert('reversal_audit', {
        'reversal_ref': newOperationId(),
        'operation_type': type,
        'operation_id': operationId,
        'original_person_id': original.personId,
        'original_effective_date': original.effectiveDate,
        'reason': trimmed,
        'actor_person_id': authorization.personId,
        'actor_binding_id': authorization.bindingId,
        'actor_member_id': authorization.scope.memberId,
        'actor_tenant_id': authorization.scope.tenantId,
        'actor_method': authorization.method,
        'credential_enrolment_ref': authorization.enrolmentId,
        'recorded_at': _session.date(DateTime.now()),
      });
      for (final (table, rowId) in recorder.rows) {
        await txn.insert('reversal_audit_effects', {
          'audit_id': auditId,
          'table_name': table,
          'row_id': rowId,
        });
      }
    });
  }

  /// Auditoría de la reversión de una operación.
  Future<Map<String, Object?>?> reversalAudit(
    String type,
    int operationId,
  ) async {
    final rows = await (await _session.db).query(
      'reversal_audit',
      where: 'operation_type=? AND operation_id=?',
      whereArgs: [type, operationId],
    );
    return rows.isEmpty ? null : rows.single;
  }
}
