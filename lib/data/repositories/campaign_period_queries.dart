import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import '../../domain/campaign_calendar.dart';
import 'repository_exceptions.dart';

/// Consultas y validaciones de calendario de campañas compartidas entre
/// [CampaignRepository] y las operaciones que validan fechas efectivas.
class CampaignPeriodQueries {
  const CampaignPeriodQueries();

  Future<List<CampaignPeriod>> campaignPeriods(
    DatabaseExecutor executor,
  ) async => [
    for (final row in await executor.query(
      'campaigns',
      columns: ['id', 'name', 'status', 'start_date', 'end_date'],
      orderBy: 'id',
    ))
      CampaignPeriod.fromRow(row),
  ];

  /// Último día local con un registro fechado de la campaña: compras y
  /// aplicaciones (revertidas incluidas, también son su historia) y
  /// necesidades declaradas de F05 con todas sus versiones.
  Future<String?> lastOperationDay(
    DatabaseExecutor executor,
    int campaignId,
  ) async {
    final rows = [
      ...await executor.query(
        'purchases',
        columns: ['purchase_date AS day'],
        where: 'campaign_id=?',
        whereArgs: [campaignId],
      ),
      ...await executor.query(
        'applications',
        columns: ['applied_at AS day'],
        where: 'campaign_id=?',
        whereArgs: [campaignId],
      ),
      ...await executor.query(
        'declared_needs',
        columns: ['reference_date AS day'],
        where: 'campaign_id=?',
        whereArgs: [campaignId],
      ),
      ...await executor.rawQuery(
        'SELECT v.reference_date AS day FROM declared_need_versions v '
        'JOIN declared_needs n ON n.id = v.declared_need_id '
        'WHERE n.campaign_id=?',
        [campaignId],
      ),
    ];
    String? last;
    for (final row in rows) {
      final day = storedLocalDay(row['day']! as String);
      if (last == null || day.compareTo(last) > 0) last = day;
    }
    return last;
  }

  /// Comprueba que [proposed] no se solape con los períodos en [periods].
  void assertNoOverlap(
    Iterable<CampaignPeriod> periods,
    CampaignPeriod proposed, {
    int? excludeId,
    int? skipOpenId,
    String subject = 'El período propuesto',
    bool parenthesizeProposed = true,
    String suffix = '',
  }) {
    final label = parenthesizeProposed
        ? '(${proposed.describe})'
        : proposed.describe;
    for (final other in periods) {
      if (excludeId != null && other.id == excludeId) continue;
      if (skipOpenId != null &&
          other.id == skipOpenId &&
          other.endDay == null) {
        continue;
      }
      if (other.overlaps(proposed)) {
        throw CampaignCalendarException(
          '$subject $label se solapa con «${other.name}» '
          '(${other.describe}).$suffix',
        );
      }
    }
  }

  /// Comprueba que [endDay] no sea anterior al inicio de [period] ni deje
  /// registros fechados fuera del período, y que no solape otras campañas.
  Future<void> validateCampaignEnd(
    DatabaseExecutor executor,
    List<CampaignPeriod> periods,
    CampaignPeriod period,
    String endDay, {
    required String actionLabel,
    required String recordsLabel,
  }) async {
    if (endDay.compareTo(period.startDay) < 0) {
      throw CampaignCalendarException(
        'El fin (${displayDay(endDay)}) no puede ser anterior al inicio de '
        '«${period.name}» (${displayDay(period.startDay)}). $actionLabel',
      );
    }
    final last = await lastOperationDay(executor, period.id);
    if (last != null && last.compareTo(endDay) > 0) {
      throw CampaignCalendarException(
        '«${period.name}» tiene $recordsLabel del ${displayDay(last)}, '
        'posteriores al fin elegido (${displayDay(endDay)}). Las operaciones '
        'no se cambian de campaña: ${actionLabel[0].toLowerCase()}${actionLabel.substring(1)}',
      );
    }
    assertNoOverlap(
      periods,
      period.withEnd(endDay),
      excludeId: period.id,
      suffix: ' $actionLabel',
    );
  }

  /// Comprueba que un período histórico [proposed] no se solape con ninguna
  /// campaña central vinculada.
  Future<void> assertNoCentralOverlap(
    DatabaseExecutor executor,
    CampaignPeriod proposed,
  ) async {
    final central = await executor.query(
      'campaign_bindings',
      columns: ['central_start_day', 'central_end_day', 'central_name'],
      where: 'central_start_day IS NOT NULL',
    );
    for (final row in central) {
      final other = CampaignPeriod(
        id: -2,
        name: row['central_name']! as String,
        status: 'CLOSED',
        startDay: row['central_start_day']! as String,
        endDay: row['central_end_day'] as String?,
      );
      if (other.overlaps(proposed)) {
        throw CampaignCalendarException(
          'El período ${proposed.describe} se solapa con la campaña del '
          'sindicato «${other.name}» (${other.describe}).',
        );
      }
    }
  }

  /// La fecha efectiva de una compra o aplicación no puede ser posterior a
  /// hoy (#121) y tiene que clasificar en la campaña del borrador, que es la
  /// activa (RN-15, RN-16, RF-03).
  Future<void> ensureEffectiveDateInCampaign(
    DatabaseExecutor executor,
    int campaignId,
    DateTime effective,
  ) async {
    final day = localDay(effective);
    final today = localDay(DateTime.now());
    if (day.compareTo(today) > 0) {
      throw CampaignDateException(
        CampaignDateProblem.future,
        'La fecha ${displayDay(day)} es posterior a hoy '
        '(${displayDay(today)}). Una compra o aplicación ya realizada no '
        'puede tener una fecha futura. No se registró nada.',
      );
    }
    final periods = await campaignPeriods(executor);
    final containing = campaignsContaining(periods, day);
    if (containing.length == 1 && containing.single.id == campaignId) return;
    final when = displayDay(day);
    if (containing.isEmpty) {
      final own = periods.where((p) => p.id == campaignId).firstOrNull;
      throw CampaignDateException(
        CampaignDateProblem.none,
        'La fecha $when no está dentro de ninguna campaña'
        '${own == null ? '' : ' («${own.name}» va ${own.describe})'}. '
        'Revise la fecha. No se registró nada.',
      );
    }
    if (containing.length > 1) {
      throw CampaignDateException(
        CampaignDateProblem.ambiguous,
        'La fecha $when está en más de una campaña '
        '(${containing.map((p) => '«${p.name}»').join(', ')}): sus períodos '
        'se solapan y no se puede saber a cuál corresponde. No se registró '
        'nada.',
      );
    }
    final other = containing.single;
    if (other.status == 'PLANNED') {
      throw CampaignDateException(
        CampaignDateProblem.planned,
        'La fecha $when corresponde a «${other.name}» (${other.describe}), '
        'que todavía no está activa. No se registra en otra campaña. No se '
        'registró nada.',
      );
    }
    throw CampaignDateException(
      CampaignDateProblem.closed,
      'La fecha $when corresponde a la campaña cerrada «${other.name}» '
      '(${other.describe}). Una operación de un período cerrado requiere '
      'revisión y no se registra en otra campaña. No se registró nada.',
    );
  }

  Future<void> ensureCampaignActive(
    DatabaseExecutor executor,
    int campaignId,
  ) async {
    final rows = await executor.query(
      'campaigns',
      columns: ['name'],
      where: "id=? AND status='ACTIVE'",
      whereArgs: [campaignId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw BusinessRuleException(
        'La campaña no está activa. Active una campaña para continuar.',
      );
    }
  }

  /// La campaña CERRADA a la que pertenece [effective], o la excepción de
  /// fecha correspondiente.
  Future<CampaignPeriod> closedCampaignFor(
    DatabaseExecutor executor,
    DateTime effective,
  ) async {
    final day = localDay(effective);
    final today = localDay(DateTime.now());
    if (day.compareTo(today) > 0) {
      throw CampaignDateException(
        CampaignDateProblem.future,
        'La fecha ${displayDay(day)} es posterior a hoy. Una operación ya '
        'realizada no puede tener una fecha futura. No se registró nada.',
      );
    }
    final containing = campaignsContaining(
      await campaignPeriods(executor),
      day,
    );
    if (containing.isEmpty) {
      throw CampaignDateException(
        CampaignDateProblem.none,
        'La fecha ${displayDay(day)} no está dentro de ninguna campaña. Puede '
        'crear un período histórico para ella. No se registró nada.',
      );
    }
    if (containing.length > 1) {
      throw CampaignDateException(
        CampaignDateProblem.ambiguous,
        'La fecha ${displayDay(day)} está en más de una campaña: no se puede '
        'saber a cuál corresponde. No se registró nada.',
      );
    }
    final period = containing.single;
    if (period.status == 'CLOSED') return period;
    if (period.status == 'PLANNED') {
      throw CampaignDateException(
        CampaignDateProblem.planned,
        'La fecha ${displayDay(day)} corresponde a «${period.name}», que '
        'todavía no está activa. No se registró nada.',
      );
    }
    throw BusinessRuleException(
      'La fecha ${displayDay(day)} pertenece a la campaña activa '
      '«${period.name}»: regístrela de la forma ordinaria.',
    );
  }
}
