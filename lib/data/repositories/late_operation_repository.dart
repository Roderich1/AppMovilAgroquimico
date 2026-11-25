import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Transaction;

import '../../domain/campaign_calendar.dart';
import '../../domain/models.dart';
import '../../domain/sync/operation_id.dart' show newOperationId;
import '../../services/auth/local_owner_credential.dart';
import '../late_operation_codec.dart';
import 'application_plan_repository.dart';
import 'campaign_repository.dart';
import 'purchase_repository.dart';
import 'repository_exceptions.dart';
import 'repository_session.dart';
import 'repository_types.dart';
import 'stock_fifo_queries.dart';

/// Sub-repositorio de operaciones tardías con revisión (RF-03).
class LateOperationRepository {
  LateOperationRepository(
    this._session,
    this._campaigns,
    this._purchases,
    this._applications,
    this._fifoQueries,
  );

  final RepositorySession _session;
  final CampaignRepository _campaigns;
  final PurchaseRepository _purchases;
  final ApplicationPlanRepository _applications;
  final StockFifoQueries _fifoQueries;

  /// Guarda una compra de una campaña cerrada como borrador pendiente (§2.1).
  Future<String> captureLatePurchase(
    PurchaseDraft draft, {
    required String reason,
  }) async {
    _purchases.validatePurchaseDraft(draft);
    final trimmed = _requireReason(reason);
    return _session.write((txn, context) async {
      _session.requireOwnerInPersonal(context, [
        for (final item in draft.items)
          for (final allocation in item.allocations) allocation.personId,
      ], 'En el modo individual la compra se asigna sólo al titular.');
      final campaign = await _campaigns.closedCampaignFor(
        txn,
        draft.purchaseDate,
      );
      final stored = PurchaseDraft(
        supplierId: draft.supplierId,
        campaignId: campaign.id,
        purchaseDate: draft.purchaseDate,
        invoiceNumber: draft.invoiceNumber,
        exchangeRateSource: draft.exchangeRateSource,
        exchangeRateNote: draft.exchangeRateNote,
        notes: draft.notes,
        items: draft.items,
      );
      return _insertLateDraft(
        txn,
        kind: 'PURCHASE',
        campaignId: campaign.id,
        effective: draft.purchaseDate,
        reason: trimmed,
        payload: encodeLatePurchase(stored),
        invoiceImagePath: draft.invoiceImagePath,
      );
    });
  }

  /// Guarda una aplicación de una campaña cerrada como borrador pendiente (§2.1).
  Future<String> captureLateApplication(
    ApplicationDraft draft, {
    required String reason,
  }) async {
    if (draft.lines.isEmpty) {
      throw BusinessRuleException(
        'La aplicación necesita al menos un producto.',
      );
    }
    if (draft.lines.map((line) => line.productId).toSet().length !=
        draft.lines.length) {
      throw BusinessRuleException(
        'No repita productos dentro de la aplicación.',
      );
    }
    if (draft.lines.any((line) => line.quantityBase <= 0)) {
      throw BusinessRuleException(
        'La cantidad aplicada debe ser mayor a cero.',
      );
    }
    if (draft.planId != null) {
      throw BusinessRuleException(
        'Una aplicación tardía no se vincula a un plan.',
      );
    }
    final trimmed = _requireReason(reason);
    return _session.write((txn, context) async {
      _session.requireOwnerInPersonal(context, [
        draft.personId,
      ], 'En el modo individual la aplicación la realiza el titular.');
      await _session.requireOwnerFarmInPersonal(txn, context, draft.farmId);
      final campaign = await _campaigns.closedCampaignFor(txn, draft.appliedAt);
      final stored = ApplicationDraft(
        personId: draft.personId,
        farmId: draft.farmId,
        campaignId: campaign.id,
        appliedAt: draft.appliedAt,
        lines: draft.lines,
        treatedAreaM2: draft.treatedAreaM2,
        notes: draft.notes,
      );
      return _insertLateDraft(
        txn,
        kind: 'APPLICATION',
        campaignId: campaign.id,
        effective: draft.appliedAt,
        reason: trimmed,
        payload: encodeLateApplication(stored),
      );
    });
  }

  String _requireReason(String reason) {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw BusinessRuleException('Indique el motivo.');
    return trimmed;
  }

  Future<String> _insertLateDraft(
    Transaction txn, {
    required String kind,
    required int campaignId,
    required DateTime effective,
    required String reason,
    required String payload,
    String? invoiceImagePath,
  }) async {
    final ref = newOperationId();
    await txn.insert('late_operation_drafts', {
      'draft_ref': ref,
      'kind': kind,
      'campaign_id': campaignId,
      'effective_date': _session.date(effective),
      'captured_at': _session.date(DateTime.now()),
      'reason': reason,
      'payload': payload,
      'invoice_image_path': invoiceImagePath,
      'status': 'PENDING',
    });
    return ref;
  }

  /// Borradores tardíos, los pendientes primero.
  Future<List<Map<String, Object?>>> lateOperationDrafts() async =>
      (await _session.db).rawQuery(
        '''SELECT d.*, c.name campaign_name FROM late_operation_drafts d
        JOIN campaigns c ON c.id=d.campaign_id
        ORDER BY CASE d.status WHEN 'PENDING' THEN 0 ELSE 1 END, d.captured_at DESC, d.id DESC''',
      );

  /// Confirma un borrador tardío con la autorización del titular (§2.1 paso 5).
  Future<LateResolution> confirmLateOperation(
    String draftRef, {
    required OwnerAuthorization authorization,
  }) => _session.write((txn, context) async {
    final current = await _session.currentOwnerBinding(txn);
    final installation = _session.currentCredential();
    consumeOwnerAuthorization(
      authorization,
      installation: installation,
      purpose: AuthorizationPurpose.confirmLateOperation,
      subjectRef: 'late:$draftRef',
      current: current,
      now: DateTime.now(),
    );
    final draft = await _pendingLateDraft(txn, draftRef);
    final effective = DateTime.parse(draft['effective_date']! as String);
    final campaignId = draft['campaign_id']! as int;
    CampaignPeriod? period;
    try {
      period = await _campaigns.closedCampaignFor(txn, effective);
    } on BusinessRuleException {
      period = null;
    }
    if (period == null || period.id != campaignId) {
      return _recordLateConflict(
        txn,
        draftRef,
        LateConflict.campaignChanged,
        'La fecha ya no corresponde a la campaña con la que se registró. No '
        'se aplicó nada: rechace este borrador y regístrelo de nuevo si '
        'corresponde.',
      );
    }
    if (draft['kind'] == 'PURCHASE') {
      final operationId = await _confirmLatePurchase(txn, context, draft);
      await _resolveLateDraft(
        txn,
        draftRef,
        status: 'CONFIRMED',
        authorization: authorization,
        resultOperationId: operationId,
      );
      return _confirmedResolution(period.name, operationId);
    }
    final resolution = await _confirmLateApplication(
      txn,
      context,
      draftRef,
      draft,
    );
    if (resolution.conflict != null) return resolution.conflict!;
    await _resolveLateDraft(
      txn,
      draftRef,
      status: 'CONFIRMED',
      authorization: authorization,
      resultOperationId: resolution.operationId,
    );
    return _confirmedResolution(period.name, resolution.operationId!);
  });

  LateResolution _confirmedResolution(
    String campaignName,
    int operationId,
  ) => LateResolution(
    LateResolutionOutcome.confirmed,
    operationId: operationId,
    message:
        'Confirmada en «$campaignName». Es una corrección privada de una '
        'campaña cerrada: el consolidado del sindicato (sellado o no) no se '
        'actualiza con ella.',
  );

  Future<LateResolution> _recordLateConflict(
    Transaction txn,
    String draftRef,
    String code,
    String message,
  ) async {
    await txn.update(
      'late_operation_drafts',
      {
        'last_conflict_code': code,
        'last_conflict_at': _session.date(DateTime.now()),
      },
      where: "draft_ref=? AND status='PENDING'",
      whereArgs: [draftRef],
    );
    return LateResolution(
      LateResolutionOutcome.conflict,
      conflictCode: code,
      message: message,
    );
  }

  Future<int> _confirmLatePurchase(
    Transaction txn,
    WriteContext context,
    Map<String, Object?> draft,
  ) async {
    final purchase = decodeLatePurchase(
      draft['payload']! as String,
      invoiceImagePath: draft['invoice_image_path'] as String?,
    );
    final total = _purchases.validatePurchaseDraft(purchase);
    _session.requireOwnerInPersonal(context, [
      for (final item in purchase.items)
        for (final allocation in item.allocations) allocation.personId,
    ], 'En el modo individual la compra se asigna sólo al titular.');
    return _purchases.insertPurchase(txn, purchase, total);
  }

  Future<({int? operationId, LateResolution? conflict})>
  _confirmLateApplication(
    Transaction txn,
    WriteContext context,
    String draftRef,
    Map<String, Object?> draft,
  ) async {
    final application = decodeLateApplication(draft['payload']! as String);
    _session.requireOwnerInPersonal(context, [
      application.personId,
    ], 'En el modo individual la aplicación la realiza el titular.');
    await _session.requireOwnerFarmInPersonal(txn, context, application.farmId);
    final day = localDay(application.appliedAt);
    for (final line in application.lines) {
      final lots = await _fifoQueries.lotsAvailableAt(
        txn,
        line.productId,
        application.personId,
        day,
      );
      final cap = lots.fold<int>(0, (sum, l) => sum + (l['available']! as int));
      if (cap < line.quantityBase) {
        return (
          operationId: null,
          conflict: await _recordLateConflict(
            txn,
            draftRef,
            LateConflict.stockUnavailable,
            'Las existencias de esa fecha no alcanzan: parte ya se usó en '
            'operaciones posteriores o se adquirió después. No se aplicó nada. '
            'Puede registrar antes la compra tardía que falta (también con '
            'revisión) o rechazar este borrador.',
          ),
        );
      }
    }
    final operationId = await _applications.insertApplication(
      txn,
      application,
      lotsFor: (executor, productId, personId) =>
          _fifoQueries.lotsAvailableAt(executor, productId, personId, day),
    );
    return (operationId: operationId, conflict: null);
  }

  /// Rechaza un borrador tardío con la autorización del titular: sin efectos.
  Future<LateResolution> rejectLateOperation(
    String draftRef, {
    required OwnerAuthorization authorization,
    String? note,
  }) => _session.write((txn, context) async {
    final current = await _session.currentOwnerBinding(txn);
    final installation = _session.currentCredential();
    consumeOwnerAuthorization(
      authorization,
      installation: installation,
      purpose: AuthorizationPurpose.rejectLateOperation,
      subjectRef: 'late:$draftRef',
      current: current,
      now: DateTime.now(),
    );
    await _pendingLateDraft(txn, draftRef);
    await _resolveLateDraft(
      txn,
      draftRef,
      status: 'REJECTED',
      authorization: authorization,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
    );
    return const LateResolution(LateResolutionOutcome.rejected);
  });

  Future<Map<String, Object?>> _pendingLateDraft(
    DatabaseExecutor txn,
    String draftRef,
  ) async {
    final rows = await txn.query(
      'late_operation_drafts',
      where: 'draft_ref=?',
      whereArgs: [draftRef],
    );
    if (rows.isEmpty) throw BusinessRuleException('El borrador no existe.');
    if (rows.single['status'] != 'PENDING') {
      throw BusinessRuleException('Este borrador ya fue resuelto.');
    }
    return rows.single;
  }

  Future<void> _resolveLateDraft(
    Transaction txn,
    String draftRef, {
    required String status,
    required OwnerAuthorization authorization,
    int? resultOperationId,
    String? note,
  }) async {
    final updated = await txn.update(
      'late_operation_drafts',
      {
        'status': status,
        'resolved_at': _session.date(DateTime.now()),
        'resolution_note': note,
        'resolver_person_id': authorization.personId,
        'resolver_binding_id': authorization.bindingId,
        'resolver_member_id': authorization.scope.memberId,
        'resolver_tenant_id': authorization.scope.tenantId,
        'resolver_method': authorization.method,
        'resolver_enrolment_ref': authorization.enrolmentId,
        'result_operation_id': resultOperationId,
      },
      where: "draft_ref=? AND status='PENDING'",
      whereArgs: [draftRef],
    );
    if (updated != 1) {
      throw BusinessRuleException('Este borrador ya fue resuelto.');
    }
  }
}
