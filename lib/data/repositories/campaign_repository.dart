import 'package:sqflite/sqflite.dart'
    show DatabaseExecutor, Sqflite, Transaction;

import '../../domain/campaign_calendar.dart';
import '../account_ledger_query.dart';
import '../sync/central_binding_store.dart' show CentralBindingStore;
import 'campaign_period_queries.dart';
import 'repository_exceptions.dart';
import 'repository_session.dart';

/// Sub-repositorio del ciclo de vida y calendario de campañas (RN-15, RN-16,
/// D-F04-C2) y su resumen de cierre.
class CampaignRepository {
  CampaignRepository(this._session);

  final RepositorySession _session;
  final CampaignPeriodQueries _queries = const CampaignPeriodQueries();

  Future<void> ensureEffectiveDateInCampaign(
    DatabaseExecutor executor,
    int campaignId,
    DateTime effective,
  ) => _queries.ensureEffectiveDateInCampaign(executor, campaignId, effective);

  Future<void> ensureCampaignActive(
    DatabaseExecutor executor,
    int campaignId,
  ) => _queries.ensureCampaignActive(executor, campaignId);

  Future<CampaignPeriod> closedCampaignFor(
    DatabaseExecutor executor,
    DateTime effective,
  ) => _queries.closedCampaignFor(executor, effective);

  /// Alta de campaña (RN-16: los períodos no se solapan).
  Future<int> addCampaign({
    required String name,
    required DateTime start,
    DateTime? end,
  }) => _session.write((txn, _) async {
    final trimmed = name.trim();
    final startDay = localDay(start);
    final endDay = end == null ? null : localDay(end);
    if (endDay != null && endDay.compareTo(startDay) < 0) {
      throw CampaignCalendarException(
        'La fecha de fin no puede ser anterior a la de inicio.',
      );
    }
    final periods = await _queries.campaignPeriods(txn);
    final latest = _latestPeriod(periods);
    if (latest != null && latest.startDay.compareTo(startDay) >= 0) {
      throw CampaignCalendarException(
        'La campaña nueva debe empezar después del '
        '${displayDay(latest.startDay)}, inicio de «${latest.name}». '
        'Las campañas se agregan en orden y sus períodos no se solapan.',
      );
    }
    final proposed = CampaignPeriod(
      id: -1,
      name: trimmed,
      status: 'PLANNED',
      startDay: startDay,
      endDay: endDay,
    );
    _queries.assertNoOverlap(periods, proposed, skipOpenId: latest?.id);
    if (latest != null && latest.endDay == null) {
      await _endOpenCampaignBefore(txn, latest, startDay, trimmed);
    }
    final active =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            "SELECT COUNT(*) FROM campaigns WHERE status='ACTIVE'",
          ),
        ) ??
        0;
    return txn.insert('campaigns', {
      'name': trimmed,
      'start_date': _session.date(start),
      'end_date': end == null ? null : _session.date(end),
      'status': active == 0 ? 'ACTIVE' : 'PLANNED',
    });
  });

  CampaignPeriod? _latestPeriod(List<CampaignPeriod> periods) {
    CampaignPeriod? latest;
    for (final period in periods) {
      if (latest == null || period.startDay.compareTo(latest.startDay) > 0) {
        latest = period;
      }
    }
    return latest;
  }

  /// Inicio que propone el alta: hoy, salvo que el orden del calendario
  /// exija uno posterior.
  Future<DateTime> suggestedCampaignStart() async {
    final periods = await _queries.campaignPeriods(await _session.db);
    var day = localDay(DateTime.now());
    var changed = true;
    while (changed) {
      changed = false;
      for (final period in periods) {
        for (final bound in [period.startDay, period.endDay]) {
          if (bound != null && bound.compareTo(day) >= 0) {
            day = nextLocalDay(bound);
            changed = true;
          }
        }
      }
    }
    return startOfLocalDay(day);
  }

  /// Cierra el período abierto de [open] el día anterior a [nextStartDay].
  Future<void> _endOpenCampaignBefore(
    DatabaseExecutor executor,
    CampaignPeriod open,
    String nextStartDay,
    String nextName,
  ) async {
    final last = await _queries.lastOperationDay(executor, open.id);
    if (last != null && last.compareTo(nextStartDay) >= 0) {
      throw CampaignCalendarException(
        '«${open.name}» tiene operaciones del ${displayDay(last)}, que no es '
        'anterior al inicio de «$nextName» (${displayDay(nextStartDay)}). '
        'Las operaciones no se cambian de campaña: el inicio de la campaña '
        'nueva tiene que ser posterior a esa fecha.',
      );
    }
    await executor.update(
      'campaigns',
      {
        'end_date': _session.date(
          startOfLocalDay(previousLocalDay(nextStartDay)),
        ),
      },
      where: 'id=?',
      whereArgs: [open.id],
    );
    await CentralBindingStore.revalidateCampaignPeriod(
      executor,
      open.id,
      now: _session.date(DateTime.now()),
    );
  }

  /// Fin previsto de una campaña activa o planificada (D-F04-C2).
  Future<void> setCampaignEnd(int campaignId, {required DateTime end}) =>
      _changePeriod(
        campaignId,
        (current) => current.withEnd(localDay(end)),
        actionLabel: 'No se cambió el fin.',
      );

  Future<void> setCampaignPeriod(
    CampaignPeriod before,
    CampaignPeriod proposed,
  ) => _changePeriod(
    before.id,
    (current) =>
        current.withDates(startDay: proposed.startDay, endDay: proposed.endDay),
    expected: before,
    actionLabel: 'No se cambió el período.',
  );

  Future<void> _changePeriod(
    int campaignId,
    CampaignPeriod Function(CampaignPeriod) propose, {
    CampaignPeriod? expected,
    required String actionLabel,
  }) => _session.write((txn, _) async {
    final periods = await _queries.campaignPeriods(txn);
    final current = periods.where((p) => p.id == campaignId).firstOrNull;
    if (current == null) throw BusinessRuleException('La campaña no existe.');
    if (!current.allowsPlannedEnd) {
      throw CampaignCalendarException(
        'El período de «${current.name}» no se cambia: la campaña está '
        '${current.status == 'CLOSED' ? 'cerrada' : 'archivada'}.',
      );
    }
    if (expected != null && !current.matchesPeriod(expected)) {
      throw CampaignCalendarException(
        'El período de «${current.name}» cambió. Vuelva a abrir la edición.',
      );
    }
    final proposed = propose(current);
    if (current.matchesPeriod(proposed)) return;
    await _queries.validatePeriod(
      txn,
      periods,
      current,
      proposed,
      actionLabel: actionLabel,
    );
    await _queries.writePeriodDates(txn, current, proposed);
    await CentralBindingStore.revalidateCampaignPeriod(
      txn,
      campaignId,
      now: _session.date(DateTime.now()),
    );
  });

  Future<Map<String, Object?>?> activeCampaign() async {
    final rows = await (await _session.db).query(
      'campaigns',
      where: "status='ACTIVE'",
      orderBy: 'start_date DESC,id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> activateCampaign(
    int campaignId, {
    bool closeCurrent = false,
  }) async {
    await _session.write((txn, _) async {
      final target = await _loadActivatableTarget(txn, campaignId);
      final active = await txn.query(
        'campaigns',
        where: "status='ACTIVE' AND id<>?",
        whereArgs: [campaignId],
        limit: 1,
      );
      if (active.isNotEmpty) {
        final targetStart = storedLocalDay(target['start_date']! as String);
        if (targetStart.compareTo(localDay(DateTime.now())) > 0) {
          throw CampaignActivationNotYetException(
            campaignName: target['name']! as String,
            activeCampaignName: active.single['name']! as String,
            activableFromDay: targetStart,
          );
        }
        if (!closeCurrent) {
          throw CampaignConflictException(
            active.single['id']! as int,
            active.single['name']! as String,
          );
        }
      }
      final periods = await _queries.campaignPeriods(txn);
      final targetPeriod = periods.firstWhere((p) => p.id == campaignId);
      if (active.isNotEmpty) {
        await _closeActiveBeforeActivating(
          txn,
          periods.firstWhere((p) => p.id == active.single['id']),
          targetPeriod,
        );
      }
      final current = await _queries.campaignPeriods(txn);
      final activated = current.firstWhere((p) => p.id == campaignId);
      _queries.assertNoOverlap(
        current,
        activated,
        excludeId: campaignId,
        subject: 'El período de «${activated.name}»',
        suffix: ' No se activó.',
      );
      await txn.update(
        'campaigns',
        {'status': 'ACTIVE'},
        where: 'id=?',
        whereArgs: [campaignId],
      );
    });
  }

  Future<Map<String, Object?>> _loadActivatableTarget(
    Transaction txn,
    int campaignId,
  ) async {
    final target = await txn.query(
      'campaigns',
      where: 'id=?',
      whereArgs: [campaignId],
      limit: 1,
    );
    if (target.isEmpty) throw BusinessRuleException('La campaña no existe.');
    final row = target.single;
    if (row['status'] == 'ARCHIVED') {
      throw BusinessRuleException('Una campaña archivada no puede activarse.');
    }
    if (row['status'] == 'CLOSED') {
      throw BusinessRuleException(
        'Una campaña cerrada no puede volver a activarse. '
        'Cree una campaña nueva para seguir operando.',
      );
    }
    return row;
  }

  Future<void> _closeActiveBeforeActivating(
    Transaction txn,
    CampaignPeriod closing,
    CampaignPeriod targetPeriod,
  ) async {
    if (closing.endDay == null) {
      if (targetPeriod.startDay.compareTo(closing.startDay) <= 0) {
        throw CampaignCalendarException(
          '«${targetPeriod.name}» empieza el '
          '${displayDay(targetPeriod.startDay)}, no después del inicio de '
          '«${closing.name}» (${displayDay(closing.startDay)}): sus '
          'períodos se solaparían. No se activó.',
        );
      }
      await _endOpenCampaignBefore(
        txn,
        closing,
        targetPeriod.startDay,
        targetPeriod.name,
      );
    }
    await txn.update(
      'campaigns',
      {'status': 'CLOSED'},
      where: 'id=?',
      whereArgs: [closing.id],
    );
  }

  /// Cierre sin sucesora.
  Future<void> closeCampaign(int campaignId, {DateTime? end}) async {
    await _session.write((txn, _) async {
      final periods = await _queries.campaignPeriods(txn);
      final period = periods
          .where((p) => p.id == campaignId && p.status == 'ACTIVE')
          .firstOrNull;
      if (period == null) {
        throw BusinessRuleException('Solo una campaña activa puede cerrarse.');
      }
      final endDay = localDay(end ?? DateTime.now());
      final today = localDay(DateTime.now());
      final latestEnd = today.compareTo(period.startDay) < 0
          ? period.startDay
          : today;
      if (endDay.compareTo(period.startDay) >= 0 &&
          endDay.compareTo(latestEnd) > 0) {
        throw CampaignCalendarException(
          'El fin (${displayDay(endDay)}) no puede ser posterior al '
          '${displayDay(latestEnd)}: los días siguientes quedarían en una '
          'campaña cerrada. No se cerró.',
        );
      }
      await _queries.validateCampaignEnd(
        txn,
        periods,
        period,
        endDay,
        actionLabel: 'No se cerró.',
        recordsLabel: 'operaciones',
      );
      await txn.update(
        'campaigns',
        {
          'status': 'CLOSED',
          'end_date': _session.date(startOfLocalDay(endDay)),
        },
        where: 'id=?',
        whereArgs: [campaignId],
      );
      await CentralBindingStore.revalidateCampaignPeriod(
        txn,
        campaignId,
        now: _session.date(DateTime.now()),
      );
    });
  }

  /// Período histórico cerrado anterior a hoy, sin solapes con ninguna campaña
  /// local ni con el período central de sus vínculos.
  Future<int> addHistoricalCampaign({
    required String name,
    required DateTime start,
    required DateTime end,
  }) => _session.write((txn, _) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw CampaignCalendarException('Indique el nombre del período.');
    }
    final startDay = localDay(start);
    final endDay = localDay(end);
    if (endDay.compareTo(startDay) < 0) {
      throw CampaignCalendarException(
        'La fecha de fin no puede ser anterior a la de inicio.',
      );
    }
    if (endDay.compareTo(localDay(DateTime.now())) >= 0) {
      throw CampaignCalendarException(
        'Un período histórico debe terminar antes de hoy.',
      );
    }
    final proposed = CampaignPeriod(
      id: -1,
      name: trimmed,
      status: 'CLOSED',
      startDay: startDay,
      endDay: endDay,
    );
    _queries.assertNoOverlap(
      await _queries.campaignPeriods(txn),
      proposed,
      subject: 'El período',
      parenthesizeProposed: false,
    );
    await _queries.assertNoCentralOverlap(txn, proposed);
    return txn.insert('campaigns', {
      'name': trimmed,
      'start_date': _session.date(startOfLocalDay(startDay)),
      'end_date': _session.date(startOfLocalDay(endDay)),
      'status': 'CLOSED',
    });
  });

  Future<List<Map<String, Object?>>> campaigns() async =>
      (await _session.db).query('campaigns', orderBy: 'start_date DESC');

  Future<Map<String, Object?>> campaignCloseSummary(int campaignId) async {
    final db = await _session.db;
    Future<int> value(String sql) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql, [campaignId])) ?? 0;
    return {
      'purchases_count': await value(
        'SELECT COUNT(*) FROM purchases WHERE campaign_id=? AND reversed_at IS NULL',
      ),
      'purchases_bob_minor': await value(
        'SELECT COALESCE(SUM(total_bob_minor),0) FROM purchases WHERE campaign_id=? AND reversed_at IS NULL',
      ),
      'applications_count': await value(
        'SELECT COUNT(*) FROM applications WHERE campaign_id=? AND reversed_at IS NULL',
      ),
      'applications_bob_minor': await value(
        'SELECT COALESCE(SUM(total_cost_bob_minor),0) FROM applications WHERE campaign_id=? AND reversed_at IS NULL',
      ),
      'pending_plans': await value(
        "SELECT COUNT(*) FROM application_plans WHERE campaign_id=? AND status IN ('DRAFT','PLANNED')",
      ),
      'receivable_bob_minor': (await readAccountLedger(
        db,
        withDetails: false,
      )).pendingForCampaign(campaignId),
    };
  }
}
