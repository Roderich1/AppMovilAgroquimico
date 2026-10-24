import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart'
    show Database, DatabaseExecutor, Sqflite, Transaction;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../domain/campaign_calendar.dart';
import '../domain/installation_access.dart' show OwnerScope;
import '../domain/sync/operation_id.dart' show newOperationId;
import 'late_operation_codec.dart';
import '../services/auth/local_owner_credential.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/operation_mode.dart';
import '../domain/person_roles.dart';
import 'app_database.dart';
import 'farmer_operation_gate.dart';
import 'invoice_storage.dart';
import 'operation_mode_store.dart';
import 'sync/central_binding_store.dart' show CentralBindingStore;

class BusinessRuleException implements Exception {
  BusinessRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CampaignConflictException extends BusinessRuleException {
  CampaignConflictException(this.activeCampaignId, this.activeCampaignName)
    : super(
        'Está activa $activeCampaignName. Cierre esa campaña antes de activar otra.',
      );
  final int activeCampaignId;
  final String activeCampaignName;
}

/// Activar una sucesora que todavía no empezó cerraría la campaña actual antes
/// de tiempo: el día de hoy quedaría dentro de una campaña cerrada y sin
/// campaña operable (#125). No se aplica nada; la sucesora sigue planificada y
/// se podrá activar desde su día de inicio.
class CampaignActivationNotYetException extends BusinessRuleException {
  CampaignActivationNotYetException({
    required this.campaignName,
    required this.activeCampaignName,
    required this.activableFromDay,
  }) : super(
         '«$campaignName» empieza el ${displayDay(activableFromDay)}, después '
         'de hoy. Mientras «$activeCampaignName» esté activa no se puede '
         'activar cerrándola: el día de hoy quedaría dentro de una campaña '
         'cerrada. Se podrá activar desde el ${displayDay(activableFromDay)}; '
         'hasta entonces queda planificada.',
       );
  final String campaignName;
  final String activeCampaignName;

  /// Día local `aaaa-mm-dd` desde el que se admite la activación.
  final String activableFromDay;
}

/// Por qué la fecha efectiva de una operación no permite registrarla en la
/// campaña del borrador (RN-15, RN-16, RF-03).
enum CampaignDateProblem {
  /// Ninguna campaña contiene la fecha.
  none,

  /// Más de una campaña contiene la fecha: calendario solapado heredado.
  ambiguous,

  /// La fecha es de una campaña cerrada (Cap. III §3.11.13: requiere
  /// revisión). Su registro asociado está pendiente de decisión: D-F04-C1.
  closed,

  /// La fecha es de una campaña planificada, todavía no activa.
  planned,

  /// La fecha es posterior a hoy: una compra o aplicación ya realizada no
  /// puede tener una fecha futura (#121).
  future,
}

/// La operación no se registra: su fecha efectiva no clasifica en la campaña
/// activa. Nunca se asigna a otra campaña en silencio.
class CampaignDateException extends BusinessRuleException {
  CampaignDateException(this.problem, super.message);
  final CampaignDateProblem problem;
}

/// Un cambio del calendario de campañas solaparía períodos o dejaría
/// operaciones fuera del período de su campaña. No se aplica nada.
class CampaignCalendarException extends BusinessRuleException {
  CampaignCalendarException(super.message);
}

/// Se lanza cuando la modalidad propia (PERSONAL) no admite la operación.
class PersonalModeRestrictionException extends BusinessRuleException {
  PersonalModeRestrictionException(super.message);
}

/// Modalidad y titular vigentes, leídos dentro de la transacción que escribe.
typedef WriteContext = ({OperationMode mode, int? ownerPersonId});

/// RF-13: responsable y fecha efectiva de la operación revertida, tal como
/// estaban (la operación original no se reasigna).
typedef OriginalOperation = ({int? personId, String? effectiveDate});

/// RF-03: resultado de confirmar o rechazar un borrador tardío.
enum LateResolutionOutcome { confirmed, rejected, conflict }

/// Códigos de conflicto de una confirmación tardía que no se aplicó.
abstract final class LateConflict {
  /// El cupo temporal de los lotes no alcanza (§2.3).
  static const stockUnavailable = 'LATE_STOCK_UNAVAILABLE';

  /// La fecha ya no clasifica en la campaña capturada (§2.3, I4 de B).
  static const campaignChanged = 'LATE_CAMPAIGN_CHANGED';
}

class LateResolution {
  const LateResolution(
    this.outcome, {
    this.operationId,
    this.conflictCode,
    this.message,
  });

  final LateResolutionOutcome outcome;
  final int? operationId;
  final String? conflictCode;
  final String? message;
}

/// RF-13: las filas compensatorias que escribe o anula una reversión, para
/// referenciarlas en `reversal_audit_effects`.
class ReversalEffects {
  ReversalEffects() : _discard = false;
  ReversalEffects.discard() : _discard = true;

  final bool _discard;
  final List<(String, int)> _rows = [];

  List<(String, int)> get rows => List.unmodifiable(_rows);

  void add(String table, int rowId) {
    if (_discard) return;
    if (!AppDatabase.reversalEffectTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'not a reversal effect table');
    }
    _rows.add((table, rowId));
  }
}

class AgroRepository {
  /// [ownerCredential] da la credencial del titular de la instalación: las
  /// acciones autorizadas exigen que la autorización la haya emitido ella con
  /// el PIN vigente (`LocalOwnerCredential.accepts`), dentro de su
  /// transacción y sin esperar. Sin ella, ninguna autorización vale.
  AgroRepository(
    this.appDatabase, {
    FarmerOperationGate gate = const FarmerOperationGate.unrestricted(),
    LocalOwnerCredential? Function()? ownerCredential,
  }) : _gate = gate,
       _ownerCredential = ownerCredential ?? _noCredential;
  final AppDatabase appDatabase;
  final FarmerOperationGate _gate;
  final LocalOwnerCredential? Function() _ownerCredential;

  static LocalOwnerCredential? _noCredential() => null;

  Future<Database> get _db => appDatabase.database;
  String _date(DateTime date) => date.toUtc().toIso8601String();

  /// Toda escritura del agricultor pasa por aquí: primero la política de
  /// activación y después, **dentro de la misma transacción que escribe**, la
  /// modalidad y el titular vigentes. Leerlos antes, fuera de ella, dejaba que
  /// un cambio de modalidad (también transaccional) se confirmara entre la
  /// lectura y la escritura: una compra iniciada en compartido podía asignar
  /// existencias a un tercero después del paso a propio.
  ///
  /// La compuerta se consulta ya dentro de la exclusión de sustitución: una
  /// restauración no puede colarse entre esa autorización y la transacción, y
  /// mientras se restaura ninguna escritura entra.
  Future<T> _write<T>(
    Future<T> Function(Transaction txn, WriteContext context) body,
  ) => appDatabase.replacement.write(() async {
    _gate.ensureAllowed();
    return (await _db).transaction(
      (txn) async => body(txn, await _readWriteContext(txn)),
    );
  });

  Future<WriteContext> _readWriteContext(DatabaseExecutor txn) async {
    final mode = await OperationModeStore(appDatabase).current(txn);
    final owner = await txn.query(
      'owner_bindings',
      columns: ['person_id'],
      where: 'ended_at IS NULL',
    );
    final ownerPersonId = owner.isEmpty
        ? null
        : owner.single['person_id'] as int;
    if (mode == OperationMode.personal && ownerPersonId == null) {
      throw PersonalModeRestrictionException(
        'El inventario propio necesita un titular vinculado.',
      );
    }
    return (mode: mode, ownerPersonId: ownerPersonId);
  }

  /// En modo propio, la persona responsable sólo puede ser el titular.
  void _requireOwnerInPersonal(
    WriteContext context,
    Iterable<int> personIds,
    String message,
  ) {
    if (context.mode != OperationMode.personal) return;
    if (personIds.any((id) => id != context.ownerPersonId)) {
      throw PersonalModeRestrictionException(message);
    }
  }

  /// Las transferencias entre responsables no existen en modo propio
  /// (RF-06: el modo compartido habilita responsables y transferencias).
  void _rejectTransferInPersonal(WriteContext context) {
    if (context.mode == OperationMode.personal) {
      throw PersonalModeRestrictionException(
        'En inventario propio no hay transferencias entre responsables.',
      );
    }
  }

  Future<void> _requireOwnerFarmInPersonal(
    DatabaseExecutor txn,
    WriteContext context,
    int farmId,
  ) async {
    if (context.mode != OperationMode.personal) return;
    final farm = await txn.query(
      'farms',
      columns: ['owner_person_id'],
      where: 'id=?',
      whereArgs: [farmId],
    );
    if (farm.isNotEmpty &&
        farm.single['owner_person_id'] != context.ownerPersonId) {
      throw PersonalModeRestrictionException(
        'En inventario propio sólo se usan los chacos del titular.',
      );
    }
  }

  Future<int> addPerson({
    required String name,
    required PersonRole role,
    SettlementPolicy? policy,
    String? phone,
  }) {
    final effective =
        policy ??
        switch (role) {
          PersonRole.admin => SettlementPolicy.manual,
          PersonRole.family => SettlementPolicy.byActualUsage,
          PersonRole.thirdParty => SettlementPolicy.byPurchaseAllocation,
        };
    return _write(
      (txn, _) => txn.insert('persons', {
        'name': name.trim(),
        'role': role.code,
        'settlement_policy': effective.code,
        'phone': phone,
        'created_at': _date(DateTime.now()),
      }),
    );
  }

  Future<int> addFarm({
    required int ownerId,
    required String name,
    required int areaM2,
    String? location,
  }) => _write((txn, context) {
    _requireOwnerInPersonal(context, [
      ownerId,
    ], 'En inventario propio los chacos pertenecen al titular.');
    return txn.insert('farms', {
      'owner_person_id': ownerId,
      'name': name.trim(),
      'area_m2': areaM2,
      'location': location,
    });
  });

  /// Alta de campaña (RN-16: los períodos no se solapan).
  ///
  /// Las campañas se agregan en orden: la nueva empieza después del inicio
  /// de todas las existentes. Si la última sigue abierta, termina el día
  /// anterior al inicio de la nueva, siempre que eso no deje fuera ninguna de
  /// sus operaciones; si las dejaría, se rechaza sin cambios.
  Future<int> addCampaign({
    required String name,
    required DateTime start,
    DateTime? end,
  }) => _write((txn, _) async {
    final trimmed = name.trim();
    final startDay = localDay(start);
    final endDay = end == null ? null : localDay(end);
    if (endDay != null && endDay.compareTo(startDay) < 0) {
      throw CampaignCalendarException(
        'La fecha de fin no puede ser anterior a la de inicio.',
      );
    }
    final periods = await _campaignPeriods(txn);
    CampaignPeriod? latest;
    for (final period in periods) {
      if (latest == null || period.startDay.compareTo(latest.startDay) > 0) {
        latest = period;
      }
    }
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
    for (final period in periods) {
      if (period.id == latest?.id && period.endDay == null) continue;
      if (period.overlaps(proposed)) {
        throw CampaignCalendarException(
          'El período propuesto (${proposed.describe}) se solapa con '
          '«${period.name}» (${period.describe}).',
        );
      }
    }
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
      'start_date': _date(start),
      'end_date': end == null ? null : _date(end),
      'status': active == 0 ? 'ACTIVE' : 'PLANNED',
    });
  });

  /// Inicio que propone el alta: hoy, salvo que el orden del calendario
  /// exija uno posterior (después del inicio y del fin fijado de cada
  /// campaña). Es sólo una propuesta: el usuario la cambia y [addCampaign]
  /// vuelve a validar.
  Future<DateTime> suggestedCampaignStart() async {
    final periods = await _campaignPeriods(await _db);
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

  Future<List<CampaignPeriod>> _campaignPeriods(
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
  /// necesidades declaradas de F05 con todas sus versiones, que se publican
  /// con la referencia de esa campaña (revisión de B sobre #110).
  Future<String?> _lastOperationDay(
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

  /// Cierra el período abierto de [open] el día anterior a [nextStartDay].
  /// Las operaciones no cambian de campaña: si alguna cae en ese día o
  /// después, se rechaza.
  Future<void> _endOpenCampaignBefore(
    DatabaseExecutor executor,
    CampaignPeriod open,
    String nextStartDay,
    String nextName,
  ) async {
    final last = await _lastOperationDay(executor, open.id);
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
      {'end_date': _date(startOfLocalDay(previousLocalDay(nextStartDay)))},
      where: 'id=?',
      whereArgs: [open.id],
    );
    // D-F04-C2: el fin nuevo puede caber o no en la campaña central
    // vinculada; el vínculo se asienta en la misma transacción.
    await CentralBindingStore.revalidateCampaignPeriod(
      executor,
      open.id,
      now: _date(DateTime.now()),
    );
  }

  /// Fin previsto de una campaña activa o planificada (D-F04-C2): el período
  /// se fija **sin** cerrar la campaña ni cambiar su estado. Se rechaza, sin
  /// escribir nada, si el fin es anterior al inicio, si deja fuera algún
  /// registro fechado de la campaña (compras, aplicaciones, necesidades y sus
  /// versiones) o si solapa otra campaña. Una campaña cerrada o archivada no
  /// cambia su período. Después se vuelve a comprobar el vínculo central.
  Future<void> setCampaignEnd(int campaignId, {required DateTime end}) async {
    await _write((txn, _) async {
      final periods = await _campaignPeriods(txn);
      final current = periods.where((p) => p.id == campaignId).firstOrNull;
      if (current == null) throw BusinessRuleException('La campaña no existe.');
      if (current.status != 'ACTIVE' && current.status != 'PLANNED') {
        throw CampaignCalendarException(
          'El período de «${current.name}» no se cambia: la campaña está '
          '${current.status == 'CLOSED' ? 'cerrada' : 'archivada'}.',
        );
      }
      final endDay = localDay(end);
      if (endDay.compareTo(current.startDay) < 0) {
        throw CampaignCalendarException(
          'El fin (${displayDay(endDay)}) no puede ser anterior al inicio de '
          '«${current.name}» (${displayDay(current.startDay)}). No se cambió.',
        );
      }
      final last = await _lastOperationDay(txn, campaignId);
      if (last != null && last.compareTo(endDay) > 0) {
        throw CampaignCalendarException(
          '«${current.name}» tiene registros del ${displayDay(last)}, '
          'posteriores al fin elegido (${displayDay(endDay)}). Las operaciones '
          'no se cambian de campaña: no se cambió el fin.',
        );
      }
      final proposed = current.withEnd(endDay);
      for (final other in periods) {
        if (other.id != campaignId && other.overlaps(proposed)) {
          throw CampaignCalendarException(
            'El período propuesto (${proposed.describe}) se solapa con '
            '«${other.name}» (${other.describe}). No se cambió el fin.',
          );
        }
      }
      await txn.update(
        'campaigns',
        {'end_date': _date(startOfLocalDay(endDay))},
        where: 'id=?',
        whereArgs: [campaignId],
      );
      await CentralBindingStore.revalidateCampaignPeriod(
        txn,
        campaignId,
        now: _date(DateTime.now()),
      );
    });
  }

  Future<Map<String, Object?>?> activeCampaign() async {
    final rows = await (await _db).query(
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
    await _write((txn, _) async {
      final target = await txn.query(
        'campaigns',
        where: 'id=?',
        whereArgs: [campaignId],
        limit: 1,
      );
      if (target.isEmpty) throw BusinessRuleException('La campaña no existe.');
      if (target.single['status'] == 'ARCHIVED') {
        throw BusinessRuleException(
          'Una campaña archivada no puede activarse.',
        );
      }
      // **Una campaña cerrada es terminal** (UIBUG-059). Representa un periodo
      // contable ya rendido: reabrirlo dejaría que movimientos nuevos entraran
      // en un ejercicio dado por concluido, y que un cierre —que el usuario
      // confirma sabiendo que es irreversible— se deshiciera con dos toques.
      //
      // Esconder el botón no basta: esta comprobación protege también de una
      // pantalla desactualizada, de una doble ejecución y de cualquier camino
      // indirecto que aparezca en el futuro. Si hiciera falta una corrección
      // administrativa, sería otra funcionalidad explícita y auditable.
      if (target.single['status'] == 'CLOSED') {
        throw BusinessRuleException(
          'Una campaña cerrada no puede volver a activarse. '
          'Cree una campaña nueva para seguir operando.',
        );
      }
      final active = await txn.query(
        'campaigns',
        where: "status='ACTIVE' AND id<>?",
        whereArgs: [campaignId],
        limit: 1,
      );
      // #125: con otra campaña activa, una sucesora cuyo inicio aún no llegó
      // no se activa, con o sin `closeCurrent`: cerraría la actual antes de
      // tiempo y hoy quedaría en una campaña cerrada. Se decide aquí, en la
      // transacción y antes del conflicto, para que la pantalla no ofrezca
      // «Cerrar y activar» como salida. Sin otra activa no aplica: una
      // campaña ACTIVE con inicio futuro sigue siendo posible (excepción ya
      // documentada, que no se amplía ni se quita). El día de inicio cuenta
      // como ya llegado (inclusivo).
      if (active.isNotEmpty) {
        final targetStart = storedLocalDay(
          target.single['start_date']! as String,
        );
        if (targetStart.compareTo(localDay(DateTime.now())) > 0) {
          throw CampaignActivationNotYetException(
            campaignName: target.single['name']! as String,
            activeCampaignName: active.single['name']! as String,
            activableFromDay: targetStart,
          );
        }
      }
      if (active.isNotEmpty && !closeCurrent) {
        throw CampaignConflictException(
          active.single['id']! as int,
          active.single['name']! as String,
        );
      }
      // Activar sólo cambia estados: los períodos se fijan al dar de alta la
      // campaña (RN-16). Antes se borraba el fin de la activada y se ponía
      // «hoy» como fin de la cerrada, lo que solapaba el día del cambio.
      final periods = await _campaignPeriods(txn);
      final targetPeriod = periods.firstWhere((p) => p.id == campaignId);
      if (active.isNotEmpty) {
        final closing = periods.firstWhere((p) => p.id == active.single['id']);
        // Base anterior a esta regla: la campaña activa sigue abierta.
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
      final current = await _campaignPeriods(txn);
      final activated = current.firstWhere((p) => p.id == campaignId);
      for (final other in current) {
        if (other.id != campaignId && other.overlaps(activated)) {
          throw CampaignCalendarException(
            'El período de «${activated.name}» (${activated.describe}) se solapa '
            'con «${other.name}» (${other.describe}). No se activó.',
          );
        }
      }
      await txn.update(
        'campaigns',
        {'status': 'ACTIVE'},
        where: 'id=?',
        whereArgs: [campaignId],
      );
    });
  }

  /// Cierre sin sucesora. El fin **efectivo** lo confirma quien cierra
  /// ([end]; por defecto, hoy) también cuando el alta de la siguiente o
  /// «Fijar fin previsto…» ya habían fijado un fin (#122): ese fin previsto se
  /// muestra en el diálogo, pero no sustituye la validación ni se conserva en
  /// silencio. Las reglas son las mismas haya o no fin previsto: no antes del
  /// inicio; no después de hoy, o del inicio si la campaña todavía no empezó
  /// (excepción ya documentada, que no se amplía); ningún registro fechado de
  /// la campaña después del fin (compras, aplicaciones, necesidades y sus
  /// versiones); sin solapes. El vínculo central se revalida en la misma
  /// transacción. Un rechazo no escribe nada.
  Future<void> closeCampaign(int campaignId, {DateTime? end}) async {
    await _write((txn, _) async {
      final periods = await _campaignPeriods(txn);
      final period = periods
          .where((p) => p.id == campaignId && p.status == 'ACTIVE')
          .firstOrNull;
      if (period == null)
        throw BusinessRuleException('Solo una campaña activa puede cerrarse.');
      final endDay = localDay(end ?? DateTime.now());
      if (endDay.compareTo(period.startDay) < 0) {
        throw CampaignCalendarException(
          'El fin (${displayDay(endDay)}) no puede ser anterior al inicio '
          'de «${period.name}» (${displayDay(period.startDay)}). No se '
          'cerró.',
        );
      }
      // Un fin futuro dejaría los días entre hoy y ese fin como de una
      // campaña cerrada (revisión de B sobre #110): se admite hasta hoy, o
      // hasta el inicio si la campaña todavía no empezó. Vale igual si ya
      // había un fin previsto (#122): un 30/11 previsto no cierra el 17/10.
      final today = localDay(DateTime.now());
      final latestEnd = today.compareTo(period.startDay) < 0
          ? period.startDay
          : today;
      if (endDay.compareTo(latestEnd) > 0) {
        throw CampaignCalendarException(
          'El fin (${displayDay(endDay)}) no puede ser posterior al '
          '${displayDay(latestEnd)}: los días siguientes quedarían en una '
          'campaña cerrada. No se cerró.',
        );
      }
      final last = await _lastOperationDay(txn, campaignId);
      if (last != null && last.compareTo(endDay) > 0) {
        throw CampaignCalendarException(
          '«${period.name}» tiene operaciones del ${displayDay(last)}, '
          'posteriores al fin elegido (${displayDay(endDay)}). Las '
          'operaciones no se cambian de campaña: no se cerró.',
        );
      }
      final proposed = period.withEnd(endDay);
      for (final other in periods) {
        if (other.id != campaignId && other.overlaps(proposed)) {
          throw CampaignCalendarException(
            'El período propuesto (${proposed.describe}) se solapa con '
            '«${other.name}» (${other.describe}). No se cerró.',
          );
        }
      }
      await txn.update(
        'campaigns',
        {'status': 'CLOSED', 'end_date': _date(startOfLocalDay(endDay))},
        where: 'id=?',
        whereArgs: [campaignId],
      );
      // D-F04-C2: con el fin efectivo fijado, el vínculo central se vuelve a
      // comprobar en la misma transacción.
      await CentralBindingStore.revalidateCampaignPeriod(
        txn,
        campaignId,
        now: _date(DateTime.now()),
      );
    });
  }

  /// Estados en los que un plan todavía **no se ha consumido**.
  ///
  /// `DRAFT` es el valor por defecto histórico de la columna; `addPlanMulti`
  /// siempre escribe `PLANNED`. Se aceptan los dos para no dejar fuera a bases
  /// antiguas.
  static const pendingPlanStatuses = <String>{'PLANNED', 'DRAFT'};

  /// Estado de un plan ya consumido por su aplicación.
  static const appliedPlanStatus = 'APPLIED';

  /// Rechaza aplicar un plan que ya se usó (UIBUG-045).
  ///
  /// Mira **las dos** señales: el estado del plan y la existencia de una
  /// aplicación que lo referencie. Basta con una para rechazar, de modo que un
  /// estado desincronizado por cualquier motivo no abra la puerta a duplicar
  /// el movimiento.
  Future<void> _ensurePlanNotApplied(
    DatabaseExecutor executor,
    int planId,
  ) async {
    final rows = await executor.query(
      'application_plans',
      columns: ['status'],
      where: 'id=?',
      whereArgs: [planId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw BusinessRuleException('El plan indicado no existe.');
    }
    final status = rows.single['status'] as String?;
    final alreadyUsed =
        (Sqflite.firstIntValue(
              await executor.rawQuery(
                'SELECT COUNT(*) FROM applications WHERE plan_id=?',
                [planId],
              ),
            ) ??
            0) >
        0;
    if (alreadyUsed || !pendingPlanStatuses.contains(status)) {
      throw BusinessRuleException(
        'Este plan ya fue aplicado y no puede volver a aplicarse. '
        'Cree un plan nuevo si necesita repetir la aplicación.',
      );
    }
  }

  /// La fecha efectiva de una compra o aplicación no puede ser posterior a
  /// hoy (#121) y tiene que clasificar en la campaña del borrador, que es la
  /// activa (RN-15, RN-16, RF-03). Se lee dentro de la transacción que
  /// escribe, antes de escribir: un rechazo no deja nada. Nunca se elige otra
  /// campaña en silencio, y el mensaje nombra la campaña de la fecha sin
  /// invitar a registrar en otra.
  Future<void> _ensureEffectiveDateInCampaign(
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
    final periods = await _campaignPeriods(executor);
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

  Future<void> _ensureCampaignActive(
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

  Future<int> addProduct({
    required String name,
    String? activeIngredient,
    String unit = 'L',
  }) => _write(
    (txn, _) => txn.insert('products', {
      'name': name.trim(),
      'active_ingredient': activeIngredient,
      'unit': unit,
      'base_unit': unit == 'L' ? 'ML' : 'G',
    }),
  );

  Future<int> addSupplier({
    required String name,
    String? phone,
    String? notes,
  }) => _write(
    (txn, _) => txn.insert('suppliers', {
      'name': name.trim(),
      'phone': phone,
      'notes': notes,
    }),
  );

  Future<int> addPlan({
    required int farmId,
    required int campaignId,
    required int productId,
    required int areaM2,
    required int doseBasePerHa,
    DateTime? plannedDate,
  }) async {
    return addPlanMulti(
      farmId: farmId,
      campaignId: campaignId,
      areaM2: areaM2,
      items: [
        PlanItemDraft(productId: productId, doseBasePerHa: doseBasePerHa),
      ],
      plannedDate: plannedDate,
    );
  }

  Future<int> addPlanMulti({
    required int farmId,
    required int campaignId,
    required int areaM2,
    required List<PlanItemDraft> items,
    DateTime? plannedDate,
    String? notes,
  }) async {
    if (areaM2 <= 0 || items.isEmpty) {
      throw BusinessRuleException(
        'El plan necesita área y al menos un producto.',
      );
    }
    final productIds = items.map((item) => item.productId).toSet();
    if (productIds.length != items.length) {
      throw BusinessRuleException('No repita productos dentro del plan.');
    }
    if (items.any((item) => item.doseBasePerHa <= 0)) {
      throw BusinessRuleException('Todas las dosis deben ser mayores a cero.');
    }
    return _write((txn, context) async {
      await _requireOwnerFarmInPersonal(txn, context, farmId);
      await _ensureCampaignActive(txn, campaignId);
      final planId = await txn.insert('application_plans', {
        'farm_id': farmId,
        'campaign_id': campaignId,
        'planned_date': plannedDate == null ? null : _date(plannedDate),
        'status': 'PLANNED',
        'notes': notes,
      });
      for (final item in items) {
        final requiredBase = divideRoundedHalfUp(
          areaM2 * item.doseBasePerHa,
          10000,
        );
        await txn.insert('application_plan_items', {
          'plan_id': planId,
          'product_id': item.productId,
          'area_m2': areaM2,
          'dose_base_per_ha': item.doseBasePerHa,
          'required_quantity_base': requiredBase,
        });
      }
      return planId;
    });
  }

  Future<int> confirmPurchase(PurchaseDraft draft) async {
    final purchaseTotal = _validatePurchaseDraft(draft);
    return _write((txn, context) async {
      _requireOwnerInPersonal(context, [
        for (final item in draft.items)
          for (final allocation in item.allocations) allocation.personId,
      ], 'En inventario propio la compra se asigna sólo al titular.');
      await _ensureCampaignActive(txn, draft.campaignId);
      await _ensureEffectiveDateInCampaign(
        txn,
        draft.campaignId,
        draft.purchaseDate,
      );
      return _insertPurchase(txn, draft, purchaseTotal);
    });
  }

  /// Validaciones de una compra que no dependen de la base. Devuelve el total.
  int _validatePurchaseDraft(PurchaseDraft draft) {
    if (draft.items.isEmpty)
      throw BusinessRuleException('La compra necesita al menos un producto.');
    if (draft.items.map((item) => item.productId).toSet().length !=
        draft.items.length) {
      throw BusinessRuleException('No repita productos dentro de la compra.');
    }
    var purchaseTotal = 0;
    for (final item in draft.items) {
      if (item.quantityBase <= 0 || item.originalUnitPriceMinor <= 0) {
        throw BusinessRuleException(
          'Cantidad y precio deben ser mayores a cero.',
        );
      }
      if (item.currency == CurrencyCode.usd &&
          (item.exchangeRateScaled ?? 0) <= 0) {
        throw BusinessRuleException(
          'Una compra en USD requiere tipo de cambio.',
        );
      }
      if (item.currency == CurrencyCode.bob &&
          item.exchangeRateScaled != null) {
        throw BusinessRuleException(
          'Una compra en BOB no debe guardar tipo de cambio.',
        );
      }
      final allocated = item.allocations.fold<int>(
        0,
        (sum, value) => sum + value.quantityBase,
      );
      if (allocated != item.quantityBase) {
        throw BusinessRuleException(
          'La cantidad asignada debe coincidir con la cantidad comprada.',
        );
      }
      purchaseTotal += subtotalMinor(
        quantityBase: item.quantityBase,
        unitPriceMinor: item.originalUnitPriceMinor,
        fxScaled: item.exchangeRateScaled,
      );
    }

    return purchaseTotal;
  }

  /// Escribe una compra ya validada en [draft.campaignId] (ordinaria o, en
  /// RF-03, una tardía confirmada en su campaña cerrada).
  Future<int> _insertPurchase(
    Transaction txn,
    PurchaseDraft draft,
    int purchaseTotal,
  ) async {
    final purchaseId = await txn.insert('purchases', {
      'supplier_id': draft.supplierId,
      'campaign_id': draft.campaignId,
      'purchase_date': _date(draft.purchaseDate),
      'invoice_number': draft.invoiceNumber,
      'default_currency_code': draft.items.first.currency.code,
      'default_exchange_rate_scaled': draft.items.first.exchangeRateScaled,
      'exchange_rate_source': draft.exchangeRateSource?.code,
      'exchange_rate_note': draft.exchangeRateNote,
      'total_bob_minor': purchaseTotal,
      'status': 'CONFIRMED',
      'notes': draft.notes,
      'invoice_image_path': draft.invoiceImagePath,
    });
    for (final item in draft.items) {
      final unitBob = convertedUnitPriceBobMinor(
        item.originalUnitPriceMinor,
        item.exchangeRateScaled,
      );
      final originalSubtotal = divideRoundedHalfUp(
        item.quantityBase * item.originalUnitPriceMinor,
        baseUnitsPerMajor,
      );
      final bobSubtotal = subtotalMinor(
        quantityBase: item.quantityBase,
        unitPriceMinor: item.originalUnitPriceMinor,
        fxScaled: item.exchangeRateScaled,
      );
      final purchaseItemId = await txn.insert('purchase_items', {
        'purchase_id': purchaseId,
        'product_id': item.productId,
        'quantity_base': item.quantityBase,
        'currency_code': item.currency.code,
        'original_unit_price_minor': item.originalUnitPriceMinor,
        'exchange_rate_scaled': item.exchangeRateScaled,
        'converted_unit_price_bob_minor': unitBob,
        'original_subtotal_minor': originalSubtotal,
        'subtotal_bob_minor': bobSubtotal,
      });
      for (final allocation in item.allocations) {
        final person = (await txn.query(
          'persons',
          where: 'id = ?',
          whereArgs: [allocation.personId],
          limit: 1,
        )).single;
        final policy = person['settlement_policy']! as String;
        final allocationCost = costForBaseQuantity(
          allocation.quantityBase,
          unitBob,
        );
        final allocationId = await txn.insert('purchase_allocations', {
          'purchase_item_id': purchaseItemId,
          'person_id': allocation.personId,
          'quantity_base': allocation.quantityBase,
          'charge_policy_snapshot': policy,
          'amount_bob_minor_if_allocation_charge':
              policy == 'BY_PURCHASE_ALLOCATION' ? allocationCost : null,
        });
        final lotId = await txn.insert('inventory_lots', {
          'purchase_item_id': purchaseItemId,
          'product_id': item.productId,
          'owner_person_id': allocation.personId,
          'acquired_date': _date(draft.purchaseDate),
          'initial_quantity_base': allocation.quantityBase,
          'unit_cost_bob_minor_per_major_unit': unitBob,
          'currency_code': item.currency.code,
          'original_unit_price_minor': item.originalUnitPriceMinor,
          'exchange_rate_scaled': item.exchangeRateScaled,
        });
        await txn.insert('inventory_movements', {
          'lot_id': lotId,
          'product_id': item.productId,
          'owner_person_id': allocation.personId,
          'movement_date': _date(draft.purchaseDate),
          'type': 'PURCHASE_IN',
          'quantity_signed': allocation.quantityBase,
          'reference_type': 'PURCHASE_ALLOCATION',
          'reference_id': allocationId,
        });
        if (policy == 'BY_PURCHASE_ALLOCATION') {
          await txn.insert('account_transactions', {
            'person_id': allocation.personId,
            'campaign_id': draft.campaignId,
            'transaction_date': _date(draft.purchaseDate),
            'type': 'PURCHASE_ALLOCATION_CHARGE',
            'amount_bob_minor_signed': allocationCost,
            'reference_type': 'PURCHASE_ALLOCATION',
            'reference_id': allocationId,
          });
        }
      }
    }
    return purchaseId;
  }

  Future<int> addProviderPayment({
    required int purchaseId,
    required int payerPersonId,
    required int amountBobMinor,
    required String method,
    DateTime? date,
  }) async {
    if (amountBobMinor <= 0)
      throw BusinessRuleException('El pago debe ser mayor a cero.');
    return _write((txn, context) async {
      _requireOwnerInPersonal(context, [
        payerPersonId,
      ], 'En inventario propio el pago al proveedor lo registra el titular.');
      final purchase = (await txn.query(
        'purchases',
        where: 'id = ? AND reversed_at IS NULL',
        whereArgs: [purchaseId],
        limit: 1,
      ));
      if (purchase.isEmpty)
        throw BusinessRuleException('La compra no está activa.');
      final paid =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COALESCE(SUM(amount_bob_minor),0) FROM provider_payments WHERE purchase_id = ? AND reversed_at IS NULL',
              [purchaseId],
            ),
          ) ??
          0;
      final total = purchase.single['total_bob_minor']! as int;
      if (paid + amountBobMinor > total)
        throw BusinessRuleException('El pago supera el saldo de la compra.');
      return txn.insert('provider_payments', {
        'purchase_id': purchaseId,
        'payer_person_id': payerPersonId,
        'payment_date': _date(date ?? DateTime.now()),
        'amount_bob_minor': amountBobMinor,
        'method': method,
      });
    });
  }

  Future<int> confirmApplication(ApplicationDraft draft) async {
    if (draft.lines.isEmpty)
      throw BusinessRuleException(
        'La aplicación necesita al menos un producto.',
      );
    if (draft.lines.map((line) => line.productId).toSet().length !=
        draft.lines.length) {
      throw BusinessRuleException(
        'No repita productos dentro de la aplicación.',
      );
    }
    return _write((txn, context) async {
      _requireOwnerInPersonal(context, [
        draft.personId,
      ], 'En inventario propio la aplicación la realiza el titular.');
      await _requireOwnerFarmInPersonal(txn, context, draft.farmId);
      await _ensureCampaignActive(txn, draft.campaignId);
      await _ensureEffectiveDateInCampaign(
        txn,
        draft.campaignId,
        draft.appliedAt,
      );
      // **Un plan se aplica una sola vez** (UIBUG-045). La comprobación vive
      // dentro de la transacción, así que un doble toque o una llamada
      // repetida no pueden colarse entre la lectura y la escritura; el índice
      // único parcial de `applications(plan_id)` es la segunda barrera, por si
      // alguien llega por otro camino.
      if (draft.planId != null) {
        await _ensurePlanNotApplied(txn, draft.planId!);
      }
      return _insertApplication(txn, draft, lotsFor: _lotsAvailableNow);
    });
  }

  /// Lotes con saldo hoy, en orden FIFO (registro ordinario).
  Future<List<Map<String, Object?>>> _lotsAvailableNow(
    DatabaseExecutor txn,
    int productId,
    int personId,
  ) => txn.rawQuery(
    '''
          SELECT l.*, COALESCE(SUM(m.quantity_signed), 0) AS available
          FROM inventory_lots l JOIN inventory_movements m ON m.lot_id = l.id
          WHERE l.product_id = ? AND l.owner_person_id = ? AND l.reversed_at IS NULL
          GROUP BY l.id HAVING available > 0 ORDER BY l.acquired_date, l.id
        ''',
    [productId, personId],
  );

  /// Escribe una aplicación ya validada consumiendo de [lotsFor] (FIFO; cada
  /// fila trae su cupo en `available`).
  Future<int> _insertApplication(
    Transaction txn,
    ApplicationDraft draft, {
    required Future<List<Map<String, Object?>>> Function(
      DatabaseExecutor txn,
      int productId,
      int personId,
    )
    lotsFor,
  }) async {
    final person = (await txn.query(
      'persons',
      where: 'id = ?',
      whereArgs: [draft.personId],
      limit: 1,
    )).single;
    final policy = person['settlement_policy']! as String;
    final applicationId = await txn.insert('applications', {
      'farm_id': draft.farmId,
      'person_id': draft.personId,
      'campaign_id': draft.campaignId,
      'plan_id': draft.planId,
      'applied_at': _date(draft.appliedAt),
      'status': 'CONFIRMED',
      'treated_area_m2': draft.treatedAreaM2 ?? draft.lines.first.treatedAreaM2,
      'notes': draft.notes,
    });
    var totalCost = 0;
    for (final line in draft.lines) {
      if (line.quantityBase <= 0)
        throw BusinessRuleException(
          'La cantidad aplicada debe ser mayor a cero.',
        );
      final lots = await lotsFor(txn, line.productId, draft.personId);
      final available = lots.fold<int>(
        0,
        (sum, row) => sum + (row['available']! as int),
      );
      if (available < line.quantityBase)
        throw BusinessRuleException(
          'Stock insuficiente para confirmar la aplicación.',
        );
      final product = (await txn.query(
        'products',
        columns: ['unit'],
        where: 'id=?',
        whereArgs: [line.productId],
        limit: 1,
      )).single;
      final applicationItemId = await txn.insert('application_items', {
        'application_id': applicationId,
        'product_id': line.productId,
        'quantity_base': line.quantityBase,
        'cost_bob_minor': 0,
        'treated_area_m2': line.treatedAreaM2,
        'dose_base_per_ha': line.doseBasePerHa,
        'theoretical_quantity_base': line.theoreticalQuantityBase,
        'unit': product['unit'],
        'variance_quantity_base': line.theoreticalQuantityBase == null
            ? null
            : line.quantityBase - line.theoreticalQuantityBase!,
      });
      var remaining = line.quantityBase;
      var lineCost = 0;
      for (final lot in lots) {
        if (remaining == 0) break;
        final lotAvailable = lot['available']! as int;
        final take = remaining < lotAvailable ? remaining : lotAvailable;
        final cost = costForBaseQuantity(
          take,
          lot['unit_cost_bob_minor_per_major_unit']! as int,
        );
        await txn.insert('application_consumptions', {
          'application_item_id': applicationItemId,
          'inventory_lot_id': lot['id'],
          'quantity_consumed_base': take,
          'cost_bob_minor': cost,
        });
        await txn.insert('inventory_movements', {
          'lot_id': lot['id'],
          'product_id': line.productId,
          'owner_person_id': draft.personId,
          'movement_date': _date(draft.appliedAt),
          'type': 'APPLICATION_OUT',
          'quantity_signed': -take,
          'reference_type': 'APPLICATION',
          'reference_id': applicationId,
        });
        lineCost += cost;
        remaining -= take;
      }
      await txn.update(
        'application_items',
        {'cost_bob_minor': lineCost, 'fifo_estimated_cost_bob_minor': lineCost},
        where: 'id = ?',
        whereArgs: [applicationItemId],
      );
      totalCost += lineCost;
    }
    await txn.update(
      'applications',
      {'total_cost_bob_minor': totalCost},
      where: 'id = ?',
      whereArgs: [applicationId],
    );
    if (policy == 'BY_ACTUAL_USAGE') {
      await txn.insert('account_transactions', {
        'person_id': draft.personId,
        'campaign_id': draft.campaignId,
        'transaction_date': _date(draft.appliedAt),
        'type': 'USAGE_CHARGE',
        'amount_bob_minor_signed': totalCost,
        'reference_type': 'APPLICATION',
        'reference_id': applicationId,
      });
    }
    if (draft.planId != null) {
      // PLANNED -> APPLIED, y ahí se queda (UIBUG-045).
      await txn.update(
        'application_plans',
        {'status': appliedPlanStatus},
        where: 'id=?',
        whereArgs: [draft.planId],
      );
    }
    return applicationId;
  }

  // ---------------------------------------------------------------------
  // RF-03: operaciones tardías con revisión
  // (docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md §2)
  // ---------------------------------------------------------------------

  /// La campaña CERRADA a la que pertenece [effective], o la excepción de
  /// fecha de siempre (futura, ambigua, sin campaña, planificada). Una fecha
  /// de la campaña activa se registra por el camino ordinario.
  Future<CampaignPeriod> _closedCampaignFor(
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
      await _campaignPeriods(executor),
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

  /// Guarda una compra de una campaña cerrada como borrador pendiente, sin
  /// efectos (§2.1). Devuelve el `draft_ref`.
  Future<String> captureLatePurchase(
    PurchaseDraft draft, {
    required String reason,
  }) async {
    _validatePurchaseDraft(draft);
    final trimmed = _requireReason(reason);
    return _write((txn, context) async {
      _requireOwnerInPersonal(context, [
        for (final item in draft.items)
          for (final allocation in item.allocations) allocation.personId,
      ], 'En inventario propio la compra se asigna sólo al titular.');
      final campaign = await _closedCampaignFor(txn, draft.purchaseDate);
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

  /// Guarda una aplicación de una campaña cerrada como borrador pendiente,
  /// sin efectos (§2.1). Una aplicación tardía no se vincula a un plan.
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
    return _write((txn, context) async {
      _requireOwnerInPersonal(context, [
        draft.personId,
      ], 'En inventario propio la aplicación la realiza el titular.');
      await _requireOwnerFarmInPersonal(txn, context, draft.farmId);
      final campaign = await _closedCampaignFor(txn, draft.appliedAt);
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
      'effective_date': _date(effective),
      'captured_at': _date(DateTime.now()),
      'reason': reason,
      'payload': payload,
      'invoice_image_path': invoiceImagePath,
      'status': 'PENDING',
    });
    return ref;
  }

  /// Borradores tardíos, los pendientes primero.
  Future<List<Map<String, Object?>>> lateOperationDrafts() async =>
      (await _db).rawQuery(
        '''SELECT d.*, c.name campaign_name FROM late_operation_drafts d
        JOIN campaigns c ON c.id=d.campaign_id
        ORDER BY CASE d.status WHEN 'PENDING' THEN 0 ELSE 1 END, d.captured_at DESC, d.id DESC''',
      );

  /// Lotes elegibles para una aplicación del día [day] y su cupo temporal
  /// (§2.3, I1 de B): adquiridos ese día o antes, no anulados; el cupo es el
  /// mínimo del saldo al final del día efectivo y al final de cada día
  /// posterior con movimientos, ordenando por día efectivo y después por id.
  /// La operación tardía va al final de su día.
  Future<List<Map<String, Object?>>> _lotsAvailableAt(
    DatabaseExecutor txn,
    int productId,
    int personId,
    String day,
  ) async {
    final lots = await txn.query(
      'inventory_lots',
      where: 'product_id=? AND owner_person_id=? AND reversed_at IS NULL',
      whereArgs: [productId, personId],
      orderBy: 'acquired_date, id',
    );
    final eligible = <Map<String, Object?>>[];
    for (final lot in lots) {
      if (storedLocalDay(lot['acquired_date']! as String).compareTo(day) > 0) {
        continue;
      }
      final movements = await txn.query(
        'inventory_movements',
        columns: ['id', 'movement_date', 'quantity_signed'],
        where: 'lot_id=?',
        whereArgs: [lot['id']],
      );
      final ordered =
          movements
              .map(
                (m) => (
                  day: storedLocalDay(m['movement_date']! as String),
                  id: m['id']! as int,
                  quantity: m['quantity_signed']! as int,
                ),
              )
              .toList()
            ..sort((a, b) {
              final byDay = a.day.compareTo(b.day);
              return byDay != 0 ? byDay : a.id.compareTo(b.id);
            });
      // Saldo acumulado al final del día efectivo (todo lo de días ≤ day) y
      // mínimo del saldo al final de cada día posterior con movimientos.
      var balance = 0;
      var atDay = 0;
      int? laterMin;
      for (var i = 0; i < ordered.length; i++) {
        balance += ordered[i].quantity;
        final endOfDay =
            i == ordered.length - 1 || ordered[i + 1].day != ordered[i].day;
        if (!endOfDay) continue;
        if (ordered[i].day.compareTo(day) <= 0) {
          atDay = balance;
        } else {
          laterMin = laterMin == null || balance < laterMin
              ? balance
              : laterMin;
        }
      }
      final cap = laterMin == null || atDay < laterMin ? atDay : laterMin;
      if (cap > 0) eligible.add({...lot, 'available': cap});
    }
    return eligible;
  }

  /// Confirma un borrador tardío con la autorización del titular (§2.1 paso
  /// 5): revalida, aplica los efectos una vez en la campaña de la fecha y lo
  /// marca CONFIRMED, todo en una transacción. Si no puede aplicarse sin
  /// tocar operaciones posteriores o la campaña cambió, queda PENDING con su
  /// conflicto y no se escribe ningún efecto.
  Future<LateResolution> confirmLateOperation(
    String draftRef, {
    required OwnerAuthorization authorization,
  }) => _write((txn, context) async {
    // El vínculo vigente y el PIN vigente, leídos justo antes de consumir.
    final current = await _currentOwnerBinding(txn);
    final installation = _ownerCredential();
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
    Future<LateResolution> conflict(String code, String message) async {
      await txn.update(
        'late_operation_drafts',
        {'last_conflict_code': code, 'last_conflict_at': _date(DateTime.now())},
        where: "draft_ref=? AND status='PENDING'",
        whereArgs: [draftRef],
      );
      return LateResolution(
        LateResolutionOutcome.conflict,
        conflictCode: code,
        message: message,
      );
    }

    CampaignPeriod? period;
    try {
      period = await _closedCampaignFor(txn, effective);
    } on BusinessRuleException {
      period = null;
    }
    if (period == null || period.id != campaignId) {
      return conflict(
        LateConflict.campaignChanged,
        'La fecha ya no corresponde a la campaña con la que se registró. No '
        'se aplicó nada: rechace este borrador y regístrelo de nuevo si '
        'corresponde.',
      );
    }
    final int operationId;
    if (draft['kind'] == 'PURCHASE') {
      final purchase = decodeLatePurchase(
        draft['payload']! as String,
        invoiceImagePath: draft['invoice_image_path'] as String?,
      );
      final total = _validatePurchaseDraft(purchase);
      _requireOwnerInPersonal(context, [
        for (final item in purchase.items)
          for (final allocation in item.allocations) allocation.personId,
      ], 'En inventario propio la compra se asigna sólo al titular.');
      operationId = await _insertPurchase(txn, purchase, total);
    } else {
      final application = decodeLateApplication(draft['payload']! as String);
      _requireOwnerInPersonal(context, [
        application.personId,
      ], 'En inventario propio la aplicación la realiza el titular.');
      await _requireOwnerFarmInPersonal(txn, context, application.farmId);
      final day = localDay(application.appliedAt);
      for (final line in application.lines) {
        final lots = await _lotsAvailableAt(
          txn,
          line.productId,
          application.personId,
          day,
        );
        final cap = lots.fold<int>(
          0,
          (sum, l) => sum + (l['available']! as int),
        );
        if (cap < line.quantityBase) {
          return conflict(
            LateConflict.stockUnavailable,
            'Las existencias de esa fecha no alcanzan: parte ya se usó en '
            'operaciones posteriores o se adquirió después. No se aplicó nada. '
            'Puede registrar antes la compra tardía que falta (también con '
            'revisión) o rechazar este borrador.',
          );
        }
      }
      operationId = await _insertApplication(
        txn,
        application,
        lotsFor: (executor, productId, personId) =>
            _lotsAvailableAt(executor, productId, personId, day),
      );
    }
    await _resolveLateDraft(
      txn,
      draftRef,
      status: 'CONFIRMED',
      authorization: authorization,
      resultOperationId: operationId,
    );
    return LateResolution(
      LateResolutionOutcome.confirmed,
      operationId: operationId,
      message:
          'Confirmada en «${period.name}». Es una corrección privada de una '
          'campaña cerrada: el consolidado del sindicato (sellado o no) no se '
          'actualiza con ella.',
    );
  });

  /// Rechaza un borrador tardío con la autorización del titular: sin efectos.
  Future<LateResolution> rejectLateOperation(
    String draftRef, {
    required OwnerAuthorization authorization,
    String? note,
  }) => _write((txn, context) async {
    // El vínculo vigente y el PIN vigente, leídos justo antes de consumir.
    final current = await _currentOwnerBinding(txn);
    final installation = _ownerCredential();
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
        'resolved_at': _date(DateTime.now()),
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

  /// Período histórico explícito (§2.5): una campaña CLOSED, entera antes de
  /// hoy, sin solapes con ninguna campaña local ni con el período central de
  /// sus vínculos. No cambia la campaña activa ni el orden de las demás. No
  /// tiene campaign_ref: nunca se publica desde él.
  Future<int> addHistoricalCampaign({
    required String name,
    required DateTime start,
    required DateTime end,
  }) => _write((txn, _) async {
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
    for (final period in await _campaignPeriods(txn)) {
      if (period.overlaps(proposed)) {
        throw CampaignCalendarException(
          'El período ${proposed.describe} se solapa con «${period.name}» '
          '(${period.describe}).',
        );
      }
    }
    final central = await txn.query(
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
    return txn.insert('campaigns', {
      'name': trimmed,
      'start_date': _date(startOfLocalDay(startDay)),
      'end_date': _date(startOfLocalDay(endDay)),
      'status': 'CLOSED',
    });
  });

  Future<int> addAccountPayment({
    required int personId,
    int? campaignId,
    required int amountBobMinor,
    bool advance = false,
    DateTime? date,
    String? notes,
  }) async {
    if (amountBobMinor <= 0)
      throw BusinessRuleException('El importe debe ser mayor a cero.');
    return _write((txn, context) async {
      _requireOwnerInPersonal(context, [
        personId,
      ], 'En inventario propio sólo se registran pagos del titular.');
      final paymentId = await txn.insert('account_transactions', {
        'person_id': personId,
        'campaign_id': campaignId,
        'transaction_date': _date(date ?? DateTime.now()),
        'type': advance ? 'ADVANCE' : 'PAYMENT',
        'amount_bob_minor_signed': -amountBobMinor,
        'reference_type': advance ? 'ADVANCE' : 'PAYMENT',
        'notes': notes,
      });
      var remaining = amountBobMinor;
      final charges = await txn.rawQuery(
        '''SELECT t.id, t.amount_bob_minor_signed -
        COALESCE((SELECT SUM(a.amount_bob_minor) FROM payment_allocations a
          WHERE a.charge_transaction_id=t.id),0) outstanding
        FROM account_transactions t
        WHERE t.person_id=? AND t.amount_bob_minor_signed>0
        ORDER BY t.transaction_date, t.id''',
        [personId],
      );
      for (final charge in charges) {
        if (remaining == 0) break;
        final outstanding = charge['outstanding']! as int;
        if (outstanding <= 0) continue;
        final allocated = remaining < outstanding ? remaining : outstanding;
        await txn.insert('payment_allocations', {
          'payment_transaction_id': paymentId,
          'charge_transaction_id': charge['id'],
          'amount_bob_minor': allocated,
        });
        remaining -= allocated;
      }
      return paymentId;
    });
  }

  /// RF-13: revierte una aplicación con la autorización del titular, el
  /// motivo y la auditoría en la misma transacción
  /// (docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md §1).
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
    effects: (txn, context, recorder) => _reverseApplicationIn(
      txn,
      context,
      applicationId,
      reason.trim(),
      recorder,
    ),
  );

  /// Sólo pruebas: los efectos de la reversión sin auditoría ni autorización.
  /// El análisis estático impide usarlo desde la app.
  @visibleForTesting
  Future<void> reverseApplicationUnauditedForTesting(
    int applicationId, {
    String? reason,
  }) => _write(
    (txn, context) => _reverseApplicationIn(
      txn,
      context,
      applicationId,
      reason,
      ReversalEffects.discard(),
    ),
  );

  Future<OriginalOperation> _reverseApplicationIn(
    Transaction txn,
    WriteContext context,
    int applicationId,
    String? reason,
    ReversalEffects effects,
  ) async {
    {
      final rows = await txn.query(
        'applications',
        where: 'id = ? AND reversed_at IS NULL',
        whereArgs: [applicationId],
      );
      if (rows.isEmpty)
        throw BusinessRuleException(
          'La aplicación ya fue revertida o no existe.',
        );
      final application = rows.single;
      // Revertir devuelve existencias y cargos a quien aplicó. En modo propio
      // eso crearía actividad de otra persona (#26/#27).
      _requireOwnerInPersonal(
        context,
        [application['person_id']! as int],
        'En inventario propio sólo se revierten aplicaciones del titular. '
        'Para revertir la de otra persona, cambie a inventario compartido.',
      );
      final consumptions = await txn.rawQuery(
        '''SELECT c.*, i.product_id FROM application_consumptions c
        JOIN application_items i ON i.id = c.application_item_id WHERE i.application_id = ? AND c.reversed_at IS NULL''',
        [applicationId],
      );
      for (final consumption in consumptions) {
        effects.add(
          'inventory_movements',
          await txn.insert('inventory_movements', {
            'lot_id': consumption['inventory_lot_id'],
            'product_id': consumption['product_id'],
            'owner_person_id': application['person_id'],
            'movement_date': _date(DateTime.now()),
            'type': 'APPLICATION_REVERSAL',
            'quantity_signed': consumption['quantity_consumed_base'],
            'reference_type': 'APPLICATION_REVERSAL',
            'reference_id': applicationId,
            'notes': reason,
          }),
        );
        effects.add('application_consumptions', consumption['id']! as int);
      }
      await txn.update(
        'application_consumptions',
        {'reversed_at': _date(DateTime.now())},
        where: 'application_item_id IN (SELECT id FROM application_items WHERE application_id = ?)',
        whereArgs: [applicationId],
      );
      final charges = await txn.query(
        'account_transactions',
        where: "reference_type = 'APPLICATION' AND reference_id = ? AND type = 'USAGE_CHARGE'",
        whereArgs: [applicationId],
      );
      for (final charge in charges) {
        effects.add(
          'account_transactions',
          await txn.insert('account_transactions', {
            'person_id': charge['person_id'],
            'campaign_id': charge['campaign_id'],
            'transaction_date': _date(DateTime.now()),
            'type': 'CREDIT_ADJUSTMENT',
            'amount_bob_minor_signed':
                -(charge['amount_bob_minor_signed']! as int),
            'reference_type': 'APPLICATION_REVERSAL',
            'reference_id': applicationId,
            'notes': reason,
            'reversal_of_id': charge['id'],
          }),
        );
      }
      await txn.update(
        'applications',
        {'status': 'REVERSED', 'reversed_at': _date(DateTime.now())},
        where: 'id = ?',
        whereArgs: [applicationId],
      );
      // **El plan NO vuelve a PLANNED** (UIBUG-045). Revertir corrige un
      // movimiento que ocurrió de verdad; no devuelve la intención al futuro.
      // Reabrirlo en silencio dejaba un plan listo para volver a aplicarse sin
      // que nadie lo hubiera pedido, y borraba el rastro de que ya se usó. Si
      // hay que ejecutar otra vez la planificación, se crea un plan nuevo.
      return (
        personId: application['person_id'] as int?,
        effectiveDate: application['applied_at'] as String?,
      );
    }
  }

  /// RF-13: revierte una compra con la autorización del titular (§1).
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
    effects: (txn, context, recorder) =>
        _reversePurchaseIn(txn, purchaseId, reason.trim(), recorder),
  );

  /// Sólo pruebas: los efectos de la reversión sin auditoría ni autorización.
  @visibleForTesting
  Future<void> reversePurchaseUnauditedForTesting(
    int purchaseId, {
    String? reason,
  }) => _write(
    (txn, _) =>
        _reversePurchaseIn(txn, purchaseId, reason, ReversalEffects.discard()),
  );

  Future<OriginalOperation> _reversePurchaseIn(
    Transaction txn,
    int purchaseId,
    String? reason,
    ReversalEffects effects,
  ) async {
    {
      final consumed =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              '''SELECT COUNT(*) FROM application_consumptions c
        JOIN inventory_lots l ON l.id = c.inventory_lot_id JOIN purchase_items i ON i.id = l.purchase_item_id
        WHERE i.purchase_id = ? AND c.reversed_at IS NULL''',
              [purchaseId],
            ),
          ) ??
          0;
      if (consumed > 0)
        throw BusinessRuleException(
          'La compra tiene lotes consumidos. Revierta primero las aplicaciones relacionadas.',
        );
      final purchase = await txn.query(
        'purchases',
        where: 'id = ? AND reversed_at IS NULL',
        whereArgs: [purchaseId],
      );
      if (purchase.isEmpty)
        throw BusinessRuleException('La compra ya fue revertida o no existe.');
      final lots = await txn.rawQuery(
        'SELECT l.* FROM inventory_lots l JOIN purchase_items i ON i.id=l.purchase_item_id WHERE i.purchase_id=?',
        [purchaseId],
      );
      for (final lot in lots) {
        final available =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE lot_id=?',
                [lot['id']],
              ),
            ) ??
            0;
        // F04-BUG-02: el lote destino de una transferencia hereda el
        // `purchase_item_id` de su origen. Si esa transferencia ya se revirtió,
        // el lote quedó anulado y en saldo 0: no hay nada que restituir y no
        // debe bloquear la reversión. Un lote anulado con saldo distinto de 0
        // sería un estado inconsistente: se rechaza en lugar de ignorarlo.
        if (lot['reversed_at'] != null) {
          if (available != 0) {
            throw BusinessRuleException(
              'Un lote anulado de esta compra conserva saldo; revise sus '
              'movimientos antes de revertir.',
            );
          }
          continue;
        }
        if (available != lot['initial_quantity_base'])
          throw BusinessRuleException(
            'El lote fue transferido o ajustado; requiere reversión consistente previa.',
          );
        effects.add(
          'inventory_movements',
          await txn.insert('inventory_movements', {
            'lot_id': lot['id'],
            'product_id': lot['product_id'],
            'owner_person_id': lot['owner_person_id'],
            'movement_date': _date(DateTime.now()),
            'type': 'PURCHASE_REVERSAL',
            'quantity_signed': -available,
            'reference_type': 'PURCHASE_REVERSAL',
            'reference_id': purchaseId,
            'notes': reason,
          }),
        );
        await txn.update(
          'inventory_lots',
          {'reversed_at': _date(DateTime.now())},
          where: 'id=?',
          whereArgs: [lot['id']],
        );
        effects.add('inventory_lots', lot['id']! as int);
      }
      final allocationCharges = await txn.rawQuery(
        '''SELECT t.* FROM account_transactions t JOIN purchase_allocations a ON
        t.reference_type='PURCHASE_ALLOCATION' AND t.reference_id=a.id JOIN purchase_items i ON i.id=a.purchase_item_id
        WHERE i.purchase_id=?''',
        [purchaseId],
      );
      for (final charge in allocationCharges) {
        effects.add(
          'account_transactions',
          await txn.insert('account_transactions', {
            'person_id': charge['person_id'],
            'campaign_id': charge['campaign_id'],
            'transaction_date': _date(DateTime.now()),
            'type': 'CREDIT_ADJUSTMENT',
            'amount_bob_minor_signed':
                -(charge['amount_bob_minor_signed']! as int),
            'reference_type': 'PURCHASE_REVERSAL',
            'reference_id': purchaseId,
            'notes': reason,
            'reversal_of_id': charge['id'],
          }),
        );
      }
      for (final payment in await txn.query(
        'provider_payments',
        columns: ['id'],
        where: 'purchase_id=? AND reversed_at IS NULL',
        whereArgs: [purchaseId],
      )) {
        effects.add('provider_payments', payment['id']! as int);
      }
      await txn.update(
        'provider_payments',
        {'reversed_at': _date(DateTime.now())},
        where: 'purchase_id=? AND reversed_at IS NULL',
        whereArgs: [purchaseId],
      );
      await txn.update(
        'purchases',
        {'status': 'REVERSED', 'reversed_at': _date(DateTime.now())},
        where: 'id=?',
        whereArgs: [purchaseId],
      );
      // Una compra se asigna a varias personas: no tiene un único responsable.
      return (
        personId: null,
        effectiveDate: purchase.single['purchase_date'] as String?,
      );
    }
  }

  Future<int> transferStock({
    required int sourceLotId,
    required int destinationPersonId,
    required int quantityBase,
    DateTime? date,
    String? notes,
  }) async {
    // La compuerta y la modalidad se comprueban dentro de la transferencia,
    // en la misma transacción que escribe.
    final source = await (await _db).query(
      'inventory_lots',
      columns: ['product_id', 'owner_person_id'],
      where: 'id=? AND reversed_at IS NULL',
      whereArgs: [sourceLotId],
    );
    if (source.isEmpty) {
      throw BusinessRuleException('El lote de origen no está activo.');
    }
    final transferId = await transferProductFifo(
      fromPersonId: source.single['owner_person_id']! as int,
      toPersonId: destinationPersonId,
      productId: source.single['product_id']! as int,
      quantityBase: quantityBase,
      date: date,
      notes: notes,
    );
    final item = await (await _db).query(
      'transfer_lot_items',
      columns: ['destination_lot_id'],
      where: 'transfer_id=?',
      whereArgs: [transferId],
      orderBy: 'id',
      limit: 1,
    );
    return item.single['destination_lot_id']! as int;
  }

  Future<int> transferProductFifo({
    required int fromPersonId,
    required int toPersonId,
    required int productId,
    required int quantityBase,
    DateTime? date,
    String? notes,
  }) => transferProductsFifo(
    fromPersonId: fromPersonId,
    toPersonId: toPersonId,
    items: [
      TransferItemDraft(productId: productId, quantityBase: quantityBase),
    ],
    date: date,
    notes: notes,
  );

  Future<int> transferProductsFifo({
    required int fromPersonId,
    required int toPersonId,
    required List<TransferItemDraft> items,
    DateTime? date,
    String? notes,
  }) async {
    if (fromPersonId == toPersonId) {
      throw BusinessRuleException(
        'El origen y el destino deben ser diferentes.',
      );
    }
    final validItems = items.where((item) => item.quantityBase > 0).toList();
    if (validItems.isEmpty) {
      throw BusinessRuleException(
        'Seleccione al menos un producto para transferir.',
      );
    }
    if (validItems.map((item) => item.productId).toSet().length !=
        validItems.length) {
      throw BusinessRuleException(
        'No repita productos dentro de la transferencia.',
      );
    }
    return _write((txn, context) async {
      _rejectTransferInPersonal(context);
      final movementDate = _date(date ?? DateTime.now());
      final transferId = await txn.insert('transfers', {
        'product_id': validItems.first.productId,
        'from_person_id': fromPersonId,
        'to_person_id': toPersonId,
        'transfer_date': movementDate,
        'quantity_base': validItems.first.quantityBase,
        'total_cost_bob_minor': 0,
        'notes': notes,
      });
      var transferCost = 0;
      for (final item in validItems) {
        final lots = await txn.rawQuery(
          '''SELECT l.*, COALESCE(SUM(m.quantity_signed),0) available
          FROM inventory_lots l LEFT JOIN inventory_movements m ON m.lot_id=l.id
          WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
          GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date,l.id''',
          [fromPersonId, item.productId],
        );
        final available = lots.fold<int>(
          0,
          (sum, lot) => sum + (lot['available'] as int),
        );
        if (available < item.quantityBase) {
          throw BusinessRuleException(
            'Stock insuficiente en uno de los productos. No se transfirió ningún item.',
          );
        }
        final transferItemId = await txn.insert('transfer_items', {
          'transfer_id': transferId,
          'product_id': item.productId,
          'quantity_base': item.quantityBase,
          'total_cost_bob_minor': 0,
        });
        var remaining = item.quantityBase;
        var itemCost = 0;
        for (final source in lots) {
          if (remaining == 0) break;
          final lotAvailable = source['available'] as int;
          final take = remaining < lotAvailable ? remaining : lotAvailable;
          final cost = costForBaseQuantity(
            take,
            source['unit_cost_bob_minor_per_major_unit'] as int,
          );
          final destinationLotId = await txn.insert('inventory_lots', {
            'purchase_item_id': source['purchase_item_id'],
            'product_id': item.productId,
            'owner_person_id': toPersonId,
            'acquired_date': source['acquired_date'],
            'initial_quantity_base': take,
            'unit_cost_bob_minor_per_major_unit':
                source['unit_cost_bob_minor_per_major_unit'],
            'currency_code': source['currency_code'],
            'original_unit_price_minor': source['original_unit_price_minor'],
            'exchange_rate_scaled': source['exchange_rate_scaled'],
            'parent_lot_id': source['id'],
            'notes': notes,
          });
          for (final movement in <Map<String, Object?>>[
            {
              'lot_id': source['id'],
              'owner_person_id': fromPersonId,
              'quantity_signed': -take,
              'type': 'TRANSFER_OUT',
            },
            {
              'lot_id': destinationLotId,
              'owner_person_id': toPersonId,
              'quantity_signed': take,
              'type': 'TRANSFER_IN',
            },
          ]) {
            await txn.insert('inventory_movements', {
              ...movement,
              'product_id': item.productId,
              'movement_date': movementDate,
              'reference_type': 'TRANSFER',
              'reference_id': transferId,
              'notes': notes,
            });
          }
          await txn.insert('transfer_lot_items', {
            'transfer_id': transferId,
            'transfer_item_id': transferItemId,
            'source_lot_id': source['id'],
            'destination_lot_id': destinationLotId,
            'quantity_base': take,
            'cost_bob_minor': cost,
          });
          remaining -= take;
          itemCost += cost;
        }
        await txn.update(
          'transfer_items',
          {'total_cost_bob_minor': itemCost},
          where: 'id=?',
          whereArgs: [transferItemId],
        );
        transferCost += itemCost;
      }
      await txn.update(
        'transfers',
        {'total_cost_bob_minor': transferCost},
        where: 'id=?',
        whereArgs: [transferId],
      );
      return transferId;
    });
  }

  /// RF-13: revierte una transferencia con la autorización del titular (§1).
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
    effects: (txn, context, recorder) =>
        _reverseTransferIn(txn, context, transferId, reason.trim(), recorder),
  );

  /// Sólo pruebas: los efectos de la reversión sin auditoría ni autorización.
  @visibleForTesting
  Future<void> reverseTransferUnauditedForTesting(
    int transferId, {
    String? reason,
  }) => _write(
    (txn, context) => _reverseTransferIn(
      txn,
      context,
      transferId,
      reason,
      ReversalEffects.discard(),
    ),
  );

  Future<OriginalOperation> _reverseTransferIn(
    Transaction txn,
    WriteContext context,
    int transferId,
    String? reason,
    ReversalEffects effects,
  ) async {
    {
      // Revertir mueve existencias entre responsables: en modo propio no hay
      // transferencias, tampoco para deshacerlas (#26/#27).
      _rejectTransferInPersonal(context);
      final transfers = await txn.query(
        'transfers',
        where: "id=? AND status='CONFIRMED' AND reversed_at IS NULL",
        whereArgs: [transferId],
      );
      if (transfers.isEmpty) {
        throw BusinessRuleException(
          'La transferencia ya fue revertida o no existe.',
        );
      }
      final transfer = transfers.single;
      // F04-BUG-01: el producto de cada movimiento de reversión sale de su
      // lote, nunca de `transfers.product_id`, que solo guarda el primer
      // producto de una transferencia multiproducto.
      final items = await txn.rawQuery(
        '''SELECT i.*, source.product_id source_product_id,
        destination.product_id destination_product_id
        FROM transfer_lot_items i
        JOIN inventory_lots source ON source.id=i.source_lot_id
        JOIN inventory_lots destination ON destination.id=i.destination_lot_id
        WHERE i.transfer_id=? ORDER BY i.id''',
        [transferId],
      );
      for (final item in items) {
        final available =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE lot_id=?',
                [item['destination_lot_id']],
              ),
            ) ??
            0;
        if (available != item['quantity_base']) {
          throw BusinessRuleException(
            'El stock transferido ya tuvo movimientos. Reviértalos antes de continuar.',
          );
        }
      }
      final reversedAt = _date(DateTime.now());
      for (final item in items) {
        final quantity = item['quantity_base']! as int;
        for (final movement in <Map<String, Object?>>[
          {
            'lot_id': item['source_lot_id'],
            'product_id': item['source_product_id'],
            'owner_person_id': transfer['from_person_id'],
            'quantity_signed': quantity,
            'type': 'TRANSFER_REVERSAL_IN',
          },
          {
            'lot_id': item['destination_lot_id'],
            'product_id': item['destination_product_id'],
            'owner_person_id': transfer['to_person_id'],
            'quantity_signed': -quantity,
            'type': 'TRANSFER_REVERSAL_OUT',
          },
        ]) {
          effects.add(
            'inventory_movements',
            await txn.insert('inventory_movements', {
              ...movement,
              'movement_date': reversedAt,
              'reference_type': 'TRANSFER_REVERSAL',
              'reference_id': transferId,
              'notes': reason,
            }),
          );
        }
        await txn.update(
          'inventory_lots',
          {'reversed_at': reversedAt},
          where: 'id=?',
          whereArgs: [item['destination_lot_id']],
        );
        effects.add('inventory_lots', item['destination_lot_id']! as int);
      }
      await txn.update(
        'transfers',
        {'status': 'REVERSED', 'reversed_at': reversedAt},
        where: 'id=?',
        whereArgs: [transferId],
      );
      return (
        personId: transfer['from_person_id'] as int?,
        effectiveDate: transfer['transfer_date'] as String?,
      );
    }
  }

  /// El vínculo de titular vigente, leído en la transacción que escribe.
  Future<OwnerBindingContext?> _currentOwnerBinding(
    DatabaseExecutor txn,
  ) async {
    final rows = await txn.query(
      'owner_bindings',
      columns: ['id', 'person_id', 'member_id', 'tenant_id'],
      where: 'ended_at IS NULL',
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return OwnerBindingContext(
      bindingId: row['id']! as int,
      personId: row['person_id']! as int,
      scope: OwnerScope(
        memberId: row['member_id']! as String,
        tenantId: row['tenant_id']! as String,
      ),
    );
  }

  /// RF-13 (§1): consume la autorización contra el vínculo vigente, aplica los
  /// efectos y escribe la auditoría y sus referencias, todo en una
  /// transacción. Una reversión por operación (doble toque o reintento).
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
    await _write((txn, context) async {
      // El vínculo vigente y el PIN vigente, leídos justo antes de consumir.
      final current = await _currentOwnerBinding(txn);
      final installation = _ownerCredential();
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
        'recorded_at': _date(DateTime.now()),
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

  /// Auditoría de la reversión de una operación, o null si se revirtió antes
  /// de v11 («Actor no registrado») o no está revertida.
  Future<Map<String, Object?>?> reversalAudit(
    String type,
    int operationId,
  ) async {
    final rows = await (await _db).query(
      'reversal_audit',
      where: 'operation_type=? AND operation_id=?',
      whereArgs: [type, operationId],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> transfers({int limit = 50}) async =>
      (await _db).rawQuery(
        '''SELECT t.*, pr.name product_name, pr.unit,
        source.name from_person_name, destination.name to_person_name,
        (SELECT COUNT(*) FROM transfer_lot_items i WHERE i.transfer_id=t.id) lot_count,
        COALESCE((SELECT COUNT(*) FROM transfer_items ti WHERE ti.transfer_id=t.id),1) item_count,
        COALESCE((SELECT GROUP_CONCAT(p.name || '|' || ti.quantity_base || '|' || p.unit, ';')
          FROM transfer_items ti JOIN products p ON p.id=ti.product_id WHERE ti.transfer_id=t.id),
          pr.name || '|' || t.quantity_base || '|' || pr.unit) products_summary
        FROM transfers t JOIN products pr ON pr.id=t.product_id
        JOIN persons source ON source.id=t.from_person_id
        JOIN persons destination ON destination.id=t.to_person_id
        ORDER BY t.transfer_date DESC, t.id DESC LIMIT ?''',
        [limit],
      );

  Future<List<Map<String, Object?>>> availableProductsForOwner(
    int personId, {
    String query = '',
    int limit = 100,
  }) async => (await _db).rawQuery(
    '''SELECT p.id product_id, p.name product_name, p.unit,
        SUM(m.quantity_signed) available_base, COUNT(DISTINCT l.id) lot_count,
        (SELECT fl.unit_cost_bob_minor_per_major_unit FROM inventory_lots fl
          JOIN inventory_movements fm ON fm.lot_id=fl.id
          WHERE fl.owner_person_id=? AND fl.product_id=p.id AND fl.reversed_at IS NULL
          GROUP BY fl.id HAVING SUM(fm.quantity_signed)>0 ORDER BY fl.acquired_date,fl.id LIMIT 1) next_fifo_cost_minor
        FROM products p JOIN inventory_movements m ON m.product_id=p.id AND m.owner_person_id=?
        JOIN inventory_lots l ON l.id=m.lot_id
        WHERE p.name LIKE ? GROUP BY p.id HAVING available_base>0
        ORDER BY p.name LIMIT ?''',
    [personId, personId, '%${query.trim()}%', limit],
  );

  Future<List<Map<String, Object?>>> list(String table, {String? orderBy}) =>
      _db.then((db) => db.query(table, orderBy: orderBy ?? 'id DESC'));

  Future<void> renameCatalog(String table, int id, String name) async {
    const allowed = {'persons', 'farms', 'products', 'suppliers', 'campaigns'};
    if (!allowed.contains(table)) throw ArgumentError('Catálogo no permitido.');
    if (name.trim().isEmpty)
      throw BusinessRuleException('El nombre no puede estar vacío.');
    await _write(
      (txn, _) => txn.update(
        table,
        {'name': name.trim()},
        where: 'id=?',
        whereArgs: [id],
      ),
    );
  }

  Future<void> archiveCatalog(String table, int id) async {
    const activeTables = {'persons', 'farms', 'products', 'suppliers'};
    if (!activeTables.contains(table) && table != 'campaigns') {
      throw ArgumentError('Catálogo no permitido.');
    }
    await _write((txn, context) async {
      if (table == 'persons' && id == context.ownerPersonId) {
        throw BusinessRuleException(
          'El titular vinculado no se puede archivar.',
        );
      }
      await txn.update(
        table,
        activeTables.contains(table) ? {'active': 0} : {'status': 'CLOSED'},
        where: 'id=?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, Object?>>> people() async =>
      (await _db).query('persons', where: 'active=1', orderBy: 'name');

  /// Modalidad y titular vigentes, en una sola consulta.
  static const _contextColumns =
      '(SELECT value FROM app_settings WHERE key=?) context_mode, '
      '(SELECT person_id FROM owner_bindings WHERE ended_at IS NULL) '
      'context_owner';

  /// Modalidad y titular vigentes, sólo para presentar opciones. Cada
  /// escritura los vuelve a leer dentro de su propia transacción.
  Future<WriteContext> operatingContext() async {
    final row = (await (await _db).rawQuery('SELECT $_contextColumns', [
      AppDatabase.operationModeKey,
    ])).single;
    return (
      mode: OperationMode.fromCode(row['context_mode'] as String?),
      ownerPersonId: row['context_owner'] as int?,
    );
  }

  /// Personas activas que pueden cumplir [purpose] según el titular y la
  /// modalidad (`person_roles.dart`). Una sola consulta: personas, modalidad
  /// y titular se leen juntos.
  Future<List<Map<String, Object?>>> peopleFor(PersonPurpose purpose) async =>
      (await peopleAndContextFor(purpose)).people;

  /// Como [peopleFor], y además la modalidad y el titular con que se
  /// filtró, para que el formulario sepa si debe ocultar la elección de
  /// persona (#26). Sigue siendo una sola consulta.
  Future<({List<Map<String, Object?>> people, WriteContext context})>
  peopleAndContextFor(PersonPurpose purpose) async {
    final rows = await (await _db).rawQuery(
      'SELECT $_contextColumns, p.* FROM (SELECT 1) '
      'LEFT JOIN persons p ON p.active=1 ORDER BY p.name',
      [AppDatabase.operationModeKey],
    );
    final mode = OperationMode.fromCode(rows.first['context_mode'] as String?);
    final owner = rows.first['context_owner'] as int?;
    return (
      people: eligiblePeople(
        [
          for (final row in rows)
            if (row['id'] != null)
              {
                for (final entry in row.entries)
                  if (!entry.key.startsWith('context_')) entry.key: entry.value,
              },
        ],
        purpose,
        ownerPersonId: owner,
        mode: mode,
      ),
      context: (mode: mode, ownerPersonId: owner),
    );
  }

  Future<List<Map<String, Object?>>> products() async =>
      (await _db).query('products', where: 'active=1', orderBy: 'name');
  Future<List<Map<String, Object?>>> suppliers() async =>
      (await _db).query('suppliers', where: 'active=1', orderBy: 'name');
  Future<List<Map<String, Object?>>> campaigns() =>
      list('campaigns', orderBy: 'start_date DESC');
  Future<List<Map<String, Object?>>> farms() async => (await _db).rawQuery(
    'SELECT f.*, p.name owner_name FROM farms f JOIN persons p ON p.id=f.owner_person_id WHERE f.active=1 ORDER BY f.name',
  );

  /// Chacos que se pueden planificar o aplicar según la modalidad: en propio,
  /// sólo los del titular (#26). Una sola consulta con modalidad y titular.
  Future<({List<Map<String, Object?>> farms, WriteContext context})>
  farmsAndContext() async {
    final rows = await (await _db).rawQuery(
      'SELECT $_contextColumns, f.*, p.name owner_name FROM (SELECT 1) '
      'LEFT JOIN (farms f JOIN persons p ON p.id=f.owner_person_id) '
      'ON f.active=1 ORDER BY f.name',
      [AppDatabase.operationModeKey],
    );
    final mode = OperationMode.fromCode(rows.first['context_mode'] as String?);
    final owner = rows.first['context_owner'] as int?;
    return (
      farms: [
        for (final row in rows)
          if (row['id'] != null &&
              (mode != OperationMode.personal ||
                  row['owner_person_id'] == owner))
            {
              for (final entry in row.entries)
                if (!entry.key.startsWith('context_')) entry.key: entry.value,
            },
      ],
      context: (mode: mode, ownerPersonId: owner),
    );
  }

  Future<List<Map<String, Object?>>> purchases({int limit = 200}) async =>
      (await _db).rawQuery(
        '''SELECT p.*, s.name supplier_name, c.name campaign_name,
    COALESCE((SELECT SUM(amount_bob_minor) FROM provider_payments pp WHERE pp.purchase_id=p.id AND pp.reversed_at IS NULL),0) paid_bob_minor,
    (SELECT COUNT(*) FROM purchase_items i WHERE i.purchase_id=p.id) item_count
    FROM purchases p JOIN suppliers s ON s.id=p.supplier_id
    JOIN campaigns c ON c.id=p.campaign_id ORDER BY purchase_date DESC LIMIT ?''',
        [limit],
      );
  Future<List<Map<String, Object?>>> applications({
    int? campaignId,
    int? personId,
    int? farmId,
    int? productId,
    int? limit,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (campaignId != null) {
      conditions.add('a.campaign_id=?');
      args.add(campaignId);
    }
    if (personId != null) {
      conditions.add('a.person_id=?');
      args.add(personId);
    }
    if (farmId != null) {
      conditions.add('a.farm_id=?');
      args.add(farmId);
    }
    if (productId != null) {
      conditions.add(
        'EXISTS (SELECT 1 FROM application_items x WHERE x.application_id=a.id AND x.product_id=?)',
      );
      args.add(productId);
    }
    if (limit != null) args.add(limit);
    return (await _db).rawQuery(
      '''SELECT a.*, p.name person_name, f.name farm_name,
        c.name campaign_name,
        COALESCE(SUM(i.theoretical_quantity_base),0) theoretical_quantity_base,
        COALESCE(SUM(i.quantity_base),0) real_quantity_base,
        GROUP_CONCAT(DISTINCT pr.unit) units, COUNT(i.id) item_count,
        GROUP_CONCAT(pr.name || '|' || i.quantity_base || '|' || pr.unit, ';') items_summary
        FROM applications a JOIN persons p ON p.id=a.person_id JOIN farms f ON f.id=a.farm_id
        JOIN campaigns c ON c.id=a.campaign_id
        LEFT JOIN application_items i ON i.application_id=a.id LEFT JOIN products pr ON pr.id=i.product_id
        ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
        GROUP BY a.id ORDER BY applied_at DESC, a.id DESC ${limit == null ? '' : 'LIMIT ?'}''',
      args,
    );
  }

  /// Planes con sus productos.
  ///
  /// Por omisión devuelve **sólo los pendientes**: la vista operativa de
  /// Planificación no debe llenarse con años de planes ya consumidos
  /// (UIBUG-045). Los aplicados se conservan íntegros para trazabilidad y se
  /// piden con `includeApplied: true`.
  ///
  /// Cada fila trae `plan_status`, para que la pantalla sepa si ofrecer la
  /// acción de aplicar sin volver a consultar.
  Future<List<Map<String, Object?>>> plans({
    int limit = 400,
    bool includeApplied = false,
  }) async {
    final pending = pendingPlanStatuses.map((_) => '?').join(',');
    return (await _db).rawQuery(
      '''SELECT i.*, p.name product_name, p.unit, f.name farm_name, pe.name owner_name,
    c.name campaign_name, a.campaign_id, a.status plan_status, a.planned_date
    FROM application_plan_items i
    JOIN application_plans a ON a.id=i.plan_id JOIN products p ON p.id=i.product_id
    JOIN farms f ON f.id=a.farm_id JOIN persons pe ON pe.id=f.owner_person_id
    JOIN campaigns c ON c.id=a.campaign_id
    ${includeApplied ? '' : 'WHERE a.status IN ($pending)'}
    ORDER BY a.id DESC LIMIT ?''',
      [if (!includeApplied) ...pendingPlanStatuses, limit],
    );
  }

  Future<List<Map<String, Object?>>> planForApplication(int planId) async =>
      (await _db).rawQuery(
        '''SELECT a.id plan_id, a.campaign_id, a.farm_id,
        f.owner_person_id person_id, f.name farm_name, f.area_m2 farm_area_m2,
        i.area_m2, i.product_id, i.dose_base_per_ha,
        i.required_quantity_base, p.name product_name, p.unit
        FROM application_plans a JOIN farms f ON f.id=a.farm_id
        JOIN application_plan_items i ON i.plan_id=a.id
        JOIN products p ON p.id=i.product_id WHERE a.id=? ORDER BY i.id''',
        [planId],
      );
  Future<List<Map<String, Object?>>> stock() async => (await _db).rawQuery(
    '''SELECT l.id lot_id, l.owner_person_id, pr.name product_name, pr.unit, pe.name owner_name,
    SUM(m.quantity_signed) quantity_base, l.unit_cost_bob_minor_per_major_unit unit_cost
    FROM inventory_movements m JOIN inventory_lots l ON l.id=m.lot_id JOIN products pr ON pr.id=m.product_id
    JOIN persons pe ON pe.id=m.owner_person_id GROUP BY l.id HAVING quantity_base <> 0 ORDER BY l.acquired_date''',
  );

  // Cifras netas (#46, #51): comprado y consumido descuentan sus reversiones
  // y la asignación de una persona es su comprado neto más sus transferencias
  // netas, sin la restitución de una aplicación revertida. Se filtra por tipo,
  // no por signo, de modo que asignación − consumo = físico. Los `HAVING` por
  // `COUNT(m.id)` conservan la fila de quien tuvo movimientos aunque sumen 0.
  Future<List<Map<String, Object?>>> inventorySummary({int? limit}) async =>
      (await _db).rawQuery(
        '''SELECT p.id product_id, p.name product_name, p.unit,
        COALESCE(SUM(CASE WHEN m.type IN ('PURCHASE_IN','PURCHASE_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) purchased_base,
        COALESCE(-SUM(CASE WHEN m.type IN ('APPLICATION_OUT','APPLICATION_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) consumed_base,
        COALESCE(SUM(m.quantity_signed),0) available_base,
        COALESCE((SELECT SUM(pi.required_quantity_base) FROM application_plan_items pi
          JOIN application_plans ap ON ap.id=pi.plan_id JOIN campaigns c ON c.id=ap.campaign_id
          WHERE pi.product_id=p.id AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) committed_base,
        COALESCE(SUM(m.quantity_signed),0) - COALESCE((SELECT SUM(pi.required_quantity_base)
          FROM application_plan_items pi JOIN application_plans ap ON ap.id=pi.plan_id
          JOIN campaigns c ON c.id=ap.campaign_id WHERE pi.product_id=p.id
          AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) projected_base,
        COALESCE((SUM(m.quantity_signed*l.unit_cost_bob_minor_per_major_unit)+500)/1000,0) available_value_bob_minor,
        COUNT(DISTINCT CASE WHEN m.quantity_signed <> 0 THEN l.owner_person_id END) people_count
        FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id
        LEFT JOIN inventory_lots l ON l.id=m.lot_id GROUP BY p.id ORDER BY p.name
        ${limit == null ? '' : 'LIMIT ?'}''',
        limit == null ? null : [limit],
      );

  Future<List<Map<String, Object?>>> personStockSummary(int personId) async =>
      (await _db).rawQuery(
        '''SELECT p.id product_id, p.name product_name, p.unit,
        COALESCE(SUM(CASE WHEN m.type IN ('PURCHASE_IN','PURCHASE_REVERSAL','TRANSFER_IN','TRANSFER_OUT',
          'TRANSFER_REVERSAL_IN','TRANSFER_REVERSAL_OUT') THEN m.quantity_signed ELSE 0 END),0) assigned_base,
        COALESCE(-SUM(CASE WHEN m.type IN ('APPLICATION_OUT','APPLICATION_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) consumed_base,
        COALESCE(SUM(m.quantity_signed),0) available_base
        FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id AND m.owner_person_id=?
        GROUP BY p.id HAVING COUNT(m.id)>0 ORDER BY p.name''',
        [personId],
      );

  Future<Map<String, Object?>> inventoryProductHeader(int productId) async {
    final rows = await (await _db).rawQuery(
      '''SELECT p.id product_id, p.name product_name, p.unit,
      COALESCE(SUM(CASE WHEN m.type IN ('PURCHASE_IN','PURCHASE_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) purchased_base,
      COALESCE(-SUM(CASE WHEN m.type IN ('APPLICATION_OUT','APPLICATION_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) consumed_base,
      COALESCE(SUM(m.quantity_signed),0) physical_base,
      COALESCE((SUM(m.quantity_signed*l.unit_cost_bob_minor_per_major_unit)+500)/1000,0) value_bob_minor,
      COALESCE((SELECT SUM(pi.required_quantity_base) FROM application_plan_items pi
        JOIN application_plans ap ON ap.id=pi.plan_id JOIN campaigns c ON c.id=ap.campaign_id
        WHERE pi.product_id=p.id AND ap.status IN ('DRAFT','PLANNED') AND c.status='ACTIVE'),0) committed_base
      FROM products p LEFT JOIN inventory_movements m ON m.product_id=p.id
      LEFT JOIN inventory_lots l ON l.id=m.lot_id WHERE p.id=? GROUP BY p.id''',
      [productId],
    );
    if (rows.isEmpty) throw BusinessRuleException('El producto no existe.');
    return rows.single;
  }

  Future<List<Map<String, Object?>>> inventoryProductDistribution(
    int productId,
  ) async => (await _db).rawQuery(
    '''SELECT p.id person_id, p.name person_name,
        COALESCE(SUM(CASE WHEN m.type IN ('PURCHASE_IN','PURCHASE_REVERSAL','TRANSFER_IN','TRANSFER_OUT',
          'TRANSFER_REVERSAL_IN','TRANSFER_REVERSAL_OUT') THEN m.quantity_signed ELSE 0 END),0) assigned_base,
        COALESCE(-SUM(CASE WHEN m.type IN ('APPLICATION_OUT','APPLICATION_REVERSAL') THEN m.quantity_signed ELSE 0 END),0) consumed_base,
        COALESCE(SUM(m.quantity_signed),0) available_base
        FROM persons p LEFT JOIN inventory_movements m ON m.owner_person_id=p.id AND m.product_id=?
        GROUP BY p.id HAVING COUNT(m.id)>0
        ORDER BY p.name''',
    [productId],
  );

  Future<List<Map<String, Object?>>> inventoryProductLots(
    int productId, {
    int? personId,
    int? supplierId,
    int? campaignId,
  }) async {
    final conditions = <String>['l.product_id=?', 'l.reversed_at IS NULL'];
    final args = <Object?>[productId];
    if (personId != null) {
      conditions.add('l.owner_person_id=?');
      args.add(personId);
    }
    if (supplierId != null) {
      conditions.add('pu.supplier_id=?');
      args.add(supplierId);
    }
    if (campaignId != null) {
      conditions.add('pu.campaign_id=?');
      args.add(campaignId);
    }
    return (await _db).rawQuery(
      '''SELECT l.id lot_id, l.acquired_date, l.initial_quantity_base,
      l.unit_cost_bob_minor_per_major_unit unit_cost, l.currency_code,
      l.original_unit_price_minor, l.exchange_rate_scaled, l.parent_lot_id,
      pe.name owner_name, s.name supplier_name, c.name campaign_name,
      COALESCE(SUM(m.quantity_signed),0) available_base
      FROM inventory_lots l JOIN persons pe ON pe.id=l.owner_person_id
      JOIN purchase_items pi ON pi.id=l.purchase_item_id
      JOIN purchases pu ON pu.id=pi.purchase_id JOIN suppliers s ON s.id=pu.supplier_id
      JOIN campaigns c ON c.id=pu.campaign_id
      LEFT JOIN inventory_movements m ON m.lot_id=l.id
      WHERE ${conditions.join(' AND ')} GROUP BY l.id
      HAVING available_base<>0 ORDER BY l.acquired_date,l.id LIMIT 500''',
      args,
    );
  }

  Future<List<Map<String, Object?>>> personProfiles() async =>
      (await _db).rawQuery('''SELECT p.*,
        COALESCE((SELECT SUM(f.area_m2) FROM farms f WHERE f.owner_person_id=p.id AND f.active=1),0) area_m2,
        COALESCE((SELECT SUM(t.amount_bob_minor_signed) FROM account_transactions t WHERE t.person_id=p.id),0) balance,
        COALESCE((SELECT COUNT(DISTINCT m.product_id) FROM inventory_movements m
          WHERE m.owner_person_id=p.id GROUP BY m.owner_person_id HAVING SUM(m.quantity_signed)<>0),0) stock_products
        FROM persons p WHERE p.active=1 ORDER BY p.name''');

  Future<Map<String, Object?>> personProfile(int personId) async {
    final rows = await (await _db).rawQuery(
      '''SELECT p.*,
      COALESCE((SELECT SUM(f.area_m2) FROM farms f WHERE f.owner_person_id=p.id AND f.active=1),0) area_m2,
      COALESCE((SELECT SUM(t.amount_bob_minor_signed) FROM account_transactions t WHERE t.person_id=p.id),0) balance
      FROM persons p WHERE p.id=?''',
      [personId],
    );
    if (rows.isEmpty) throw BusinessRuleException('La persona no existe.');
    return rows.single;
  }

  Future<List<Map<String, Object?>>> farmsForPerson(int personId) async =>
      (await _db).query(
        'farms',
        where: 'owner_person_id=? AND active=1',
        whereArgs: [personId],
        orderBy: 'name',
      );

  Future<Map<String, Object?>> farmProfile(int farmId) async {
    final rows = await (await _db).rawQuery(
      '''SELECT f.*, p.name owner_name FROM farms f
      JOIN persons p ON p.id=f.owner_person_id WHERE f.id=?''',
      [farmId],
    );
    if (rows.isEmpty) throw BusinessRuleException('El chaco no existe.');
    return rows.single;
  }

  Future<List<Map<String, Object?>>> farmLogbook(
    int farmId, {
    int? campaignId,
    int? productId,
  }) async {
    final conditions = <String>['a.farm_id=?'];
    final args = <Object?>[farmId];
    if (campaignId != null) {
      conditions.add('a.campaign_id=?');
      args.add(campaignId);
    }
    if (productId != null) {
      conditions.add('i.product_id=?');
      args.add(productId);
    }
    return (await _db).rawQuery(
      '''SELECT a.id application_id, a.applied_at, a.status, a.notes,
      c.name campaign_name, pe.name person_name, i.id application_item_id,
      pr.id product_id, pr.name product_name, pr.unit, i.treated_area_m2,
      i.dose_base_per_ha, i.theoretical_quantity_base, i.quantity_base,
      i.cost_bob_minor,
      (SELECT GROUP_CONCAT('#' || ac.inventory_lot_id || ': ' || ac.quantity_consumed_base)
        FROM application_consumptions ac WHERE ac.application_item_id=i.id AND ac.reversed_at IS NULL) fifo_lots
      FROM applications a JOIN campaigns c ON c.id=a.campaign_id
      JOIN persons pe ON pe.id=a.person_id JOIN application_items i ON i.application_id=a.id
      JOIN products pr ON pr.id=i.product_id
      WHERE ${conditions.join(' AND ')} ORDER BY a.applied_at DESC,a.id DESC,i.id''',
      args,
    );
  }

  Future<Map<String, Object?>> campaignCloseSummary(int campaignId) async {
    final db = await _db;
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
      'receivable_bob_minor': await value(
        'SELECT COALESCE(SUM(amount_bob_minor_signed),0) FROM account_transactions WHERE campaign_id=?',
      ),
    };
  }

  Future<Map<String, Object?>> personCampaignBalance(
    int personId,
    int campaignId,
  ) async {
    final db = await _db;
    final campaign = (await db.query(
      'campaigns',
      columns: ['start_date'],
      where: 'id=?',
      whereArgs: [campaignId],
    )).single;
    final start = campaign['start_date'];
    final rows = await db.rawQuery(
      '''SELECT
      COALESCE(SUM(CASE WHEN c.start_date < ? THEN t.amount_bob_minor_signed ELSE 0 END),0) opening_balance,
      COALESCE(SUM(CASE WHEN t.campaign_id=? AND t.amount_bob_minor_signed>0 THEN t.amount_bob_minor_signed ELSE 0 END),0) campaign_charges,
      COALESCE(-SUM(CASE WHEN t.campaign_id=? AND t.amount_bob_minor_signed<0 THEN t.amount_bob_minor_signed ELSE 0 END),0) campaign_payments,
      COALESCE(SUM(t.amount_bob_minor_signed),0) total_balance
      FROM account_transactions t LEFT JOIN campaigns c ON c.id=t.campaign_id
      WHERE t.person_id=?''',
      [start, campaignId, campaignId, personId],
    );
    return rows.single;
  }

  Future<Map<String, Object?>> productStockInsight({
    required int personId,
    required int productId,
    required int campaignId,
  }) async {
    final db = await _db;
    final ownerAvailable =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE owner_person_id=? AND product_id=?',
            [personId, productId],
          ),
        ) ??
        0;
    final physicalTotal =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements WHERE product_id=?',
            [productId],
          ),
        ) ??
        0;
    final consumedCampaign =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COALESCE(-SUM(m.quantity_signed),0) FROM inventory_movements m
            JOIN applications a ON a.id=m.reference_id AND m.reference_type='APPLICATION'
            WHERE m.owner_person_id=? AND m.product_id=? AND m.type='APPLICATION_OUT'
            AND a.campaign_id=? AND a.reversed_at IS NULL''',
            [personId, productId, campaignId],
          ),
        ) ??
        0;
    final lots = await db.rawQuery(
      '''SELECT l.unit_cost_bob_minor_per_major_unit unit_cost, SUM(m.quantity_signed) available
      FROM inventory_lots l JOIN inventory_movements m ON m.lot_id=l.id
      WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
      GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date,l.id''',
      [personId, productId],
    );
    return {
      'owner_available_base': ownerAvailable,
      'physical_total_base': physicalTotal,
      'consumed_campaign_base': consumedCampaign,
      'next_fifo_cost_minor': lots.isEmpty ? 0 : lots.first['unit_cost'],
      'available_lots': lots.length,
    };
  }

  Future<int> estimateFifoCost({
    required int personId,
    required int productId,
    required int quantityBase,
  }) async {
    final lots = await (await _db).rawQuery(
      '''SELECT l.unit_cost_bob_minor_per_major_unit unit_cost, SUM(m.quantity_signed) available
      FROM inventory_lots l JOIN inventory_movements m ON m.lot_id=l.id
      WHERE l.owner_person_id=? AND l.product_id=? AND l.reversed_at IS NULL
      GROUP BY l.id HAVING available>0 ORDER BY l.acquired_date,l.id''',
      [personId, productId],
    );
    var remaining = quantityBase;
    var cost = 0;
    for (final lot in lots) {
      if (remaining <= 0) break;
      final available = lot['available']! as int;
      final take = remaining < available ? remaining : available;
      cost += costForBaseQuantity(take, lot['unit_cost']! as int);
      remaining -= take;
    }
    return cost;
  }

  Future<List<Map<String, Object?>>> settlements({int? campaignId}) async =>
      (await _db).rawQuery(
        '''SELECT p.id, p.name, p.role,
    COALESCE(SUM(t.amount_bob_minor_signed),0) balance,
    COALESCE(SUM(CASE WHEN t.amount_bob_minor_signed>0 THEN t.amount_bob_minor_signed ELSE 0 END),0) charges,
    COALESCE(-SUM(CASE WHEN t.amount_bob_minor_signed<0 THEN t.amount_bob_minor_signed ELSE 0 END),0) payments
    FROM persons p LEFT JOIN account_transactions t ON t.person_id=p.id ${campaignId == null ? '' : 'AND t.campaign_id=?'}
    WHERE p.role<>'ADMIN' GROUP BY p.id ORDER BY balance DESC, p.name''',
        [if (campaignId != null) campaignId],
      );

  Future<List<Map<String, Object?>>> topSettlements({int limit = 5}) async =>
      (await _db).rawQuery(
        '''SELECT p.id, p.name, p.role, COALESCE(SUM(t.amount_bob_minor_signed),0) balance
        FROM persons p LEFT JOIN account_transactions t ON t.person_id=p.id
        WHERE p.role<>'ADMIN' GROUP BY p.id ORDER BY balance DESC,p.name LIMIT ?''',
        [limit],
      );
  Future<List<Map<String, Object?>>> statement(
    int personId, {
    int? campaignId,
  }) async => (await _db).rawQuery(
    '''SELECT * FROM account_transactions
    WHERE person_id=? ${campaignId == null ? '' : 'AND campaign_id=?'} ORDER BY transaction_date,id''',
    [personId, if (campaignId != null) campaignId],
  );

  Future<List<Map<String, Object?>>> detailedStatement(
    int personId, {
    int? campaignId,
  }) async => (await _db).rawQuery(
    '''SELECT t.*,
    COALESCE(
      (SELECT GROUP_CONCAT(p.name, ', ') FROM application_items i JOIN products p ON p.id=i.product_id
       WHERE i.application_id=t.reference_id AND t.reference_type='APPLICATION'),
      (SELECT p.name FROM purchase_allocations a JOIN purchase_items i ON i.id=a.purchase_item_id
       JOIN products p ON p.id=i.product_id WHERE a.id=t.reference_id AND t.reference_type='PURCHASE_ALLOCATION'),
      t.notes, t.type) concept,
    (SELECT f.name FROM applications a JOIN farms f ON f.id=a.farm_id
     WHERE a.id=t.reference_id AND t.reference_type='APPLICATION') farm_name
    FROM account_transactions t WHERE t.person_id=?
    ${campaignId == null ? '' : 'AND t.campaign_id=?'} ORDER BY t.transaction_date,t.id''',
    [personId, if (campaignId != null) campaignId],
  );

  Future<List<Map<String, Object?>>> farmCostReport({int? campaignId}) async =>
      (await _db).rawQuery(
        '''SELECT f.id, f.name, f.area_m2, p.name owner_name,
        COALESCE(SUM(a.total_cost_bob_minor),0) total_cost_bob_minor
        FROM farms f JOIN persons p ON p.id=f.owner_person_id
        LEFT JOIN applications a ON a.farm_id=f.id AND a.reversed_at IS NULL
        ${campaignId == null ? '' : 'AND a.campaign_id=?'} GROUP BY f.id ORDER BY f.name''',
        campaignId == null ? null : [campaignId],
      );

  Future<List<Map<String, Object?>>> productCostReport({
    int? campaignId,
  }) async => (await _db).rawQuery(
    '''SELECT p.id, p.name, p.unit,
        COALESCE(SUM(CASE WHEN a.id IS NOT NULL THEN i.quantity_base ELSE 0 END),0) quantity_base,
        COALESCE(SUM(CASE WHEN a.id IS NOT NULL THEN i.cost_bob_minor ELSE 0 END),0) total_cost_bob_minor
        FROM products p LEFT JOIN application_items i ON i.product_id=p.id
        LEFT JOIN applications a ON a.id=i.application_id AND a.reversed_at IS NULL
        ${campaignId == null ? '' : 'AND a.campaign_id=?'} GROUP BY p.id ORDER BY p.name''',
    campaignId == null ? null : [campaignId],
  );

  Future<DashboardSummary> dashboard() async {
    final db = await _db;
    final purchases =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COALESCE(SUM(total_bob_minor),0) FROM purchases WHERE reversed_at IS NULL",
          ),
        ) ??
        0;
    final provider =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COALESCE(SUM(amount_bob_minor),0) FROM provider_payments WHERE reversed_at IS NULL",
          ),
        ) ??
        0;
    final family =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COALESCE(SUM(t.amount_bob_minor_signed),0) FROM account_transactions t JOIN persons p ON p.id=t.person_id WHERE p.role='FAMILY'",
          ),
        ) ??
        0;
    final third =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COALESCE(SUM(t.amount_bob_minor_signed),0) FROM account_transactions t JOIN persons p ON p.id=t.person_id WHERE p.role='THIRD_PARTY'",
          ),
        ) ??
        0;
    final received =
        -(Sqflite.firstIntValue(
              await db.rawQuery(
                "SELECT COALESCE(SUM(amount_bob_minor_signed),0) FROM account_transactions WHERE type IN ('PAYMENT','ADVANCE')",
              ),
            ) ??
            0);
    final stock =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(quantity_signed),0) FROM inventory_movements',
          ),
        ) ??
        0;
    return DashboardSummary(
      purchasesBobMinor: purchases,
      providerPaidMinor: provider,
      familyReceivableMinor: family,
      thirdPartyReceivableMinor: third,
      receivedMinor: received,
      stockBase: stock,
    );
  }

  /// Sólo copia un archivo: basta la compuerta, no hay contexto de modalidad.
  /// También queda excluida mientras se restaura, porque la restauración
  /// reemplaza la carpeta de fotografías.
  Future<String> storeInvoiceImage(String sourcePath) =>
      appDatabase.replacement.write(() async {
        _gate.ensureAllowed();
        // La carpeta la decide `invoice_storage.dart`, que es también donde la
        // busca `BackupService` para meterla en el respaldo y devolverla al
        // restaurar.
        final invoices = await resolveInvoicesDirectory();
        final extension = p.extension(sourcePath).isEmpty
            ? '.jpg'
            : p.extension(sourcePath);
        final target = p.join(
          invoices.path,
          'invoice_${DateTime.now().microsecondsSinceEpoch}$extension',
        );
        await File(sourcePath).copy(target);
        return target;
      });
}
