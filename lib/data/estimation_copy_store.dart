// Copia descargada de la estimación del consumo en SQLite (F12-EST-07-MOB,
// MOB #164; RF-40, RN-30, DAT-20, INT-09 v1; contrato
// `F12_EST_07_COPIA_MOBILE.md` del servicio).
//
// **Regla de acceso.** Una copia sólo se lee si:
// - hay un **contexto local** (`estimation_copy_access`: `context_id`
//   aleatorio y una generación) y la copia es de ese contexto;
// - la copia es de la identidad que la pide: el mismo Member y sindicato **y**
//   el mismo vínculo de titular, y su JSON es de esa identidad y campaña;
// - su campaña no se retiró (`estimation_copy_retirements`) después de
//   pedirse la descarga.
// Sin contexto o sin identidad no se lee nada: que exista una fila no
// autoriza a leerla, y tampoco que la identidad coincida.
//
// **Retirada y borrado, separados.** Cerrar la sesión o un 401, 403 o 409
// renuevan el contexto (otra `context_id`); un 404 registra la retirada de esa
// campaña. Esa escritura es pequeña y va primero, sola. El borrado físico va
// después ([purge]) y, si falla, queda pendiente: la copia ya no se lee, ni
// tras cerrar y volver a abrir la app, y el siguiente intento la borra. Una
// respuesta o escritura de una descarga pedida antes lleva el contexto o la
// generación anteriores y no se lee nunca.
//
// **Fuera del respaldo y de Sync v1.** Ver `AppDatabase.estimationCopiesSchema`.
import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../domain/estimation/farmer_estimation.dart';
import 'app_database.dart';

/// Identidad propietaria: Member, sindicato y vínculo de titular vigentes.
class EstimationIdentity {
  const EstimationIdentity({
    required this.memberId,
    required this.tenantId,
    required this.bindingId,
  });

  final String memberId;
  final String tenantId;
  final int bindingId;

  @override
  bool operator ==(Object other) =>
      other is EstimationIdentity &&
      other.memberId == memberId &&
      other.tenantId == tenantId &&
      other.bindingId == bindingId;

  @override
  int get hashCode => Object.hash(memberId, tenantId, bindingId);

  @override
  String toString() => 'EstimationIdentity(redacted)';
}

/// Lo vigente al pedir una descarga: sólo con esto se puede guardar.
class EstimationCopyGrant {
  const EstimationCopyGrant._(this.identity, this.contextId, this.generation);
  final EstimationIdentity identity;
  final String contextId;
  final int generation;
}

enum EstimationSaveOutcome {
  saved,

  /// Ya hay una copia igual o más reciente de esa campaña: se conserva.
  keptNewer,

  /// La sesión, el titular o el contexto cambiaron durante la descarga.
  accessChanged,

  /// La campaña se retiró (404) después de pedir la descarga.
  targetRetired,

  /// La respuesta no es de esta identidad o de este sindicato.
  otherSubject,
}

class StoredEstimationCopy {
  const StoredEstimationCopy({required this.download, required this.savedAt});

  final FarmerDownload download;

  /// Hora del teléfono al guardar; la fecha de descarga es la del servidor.
  final DateTime savedAt;
}

class EstimationCopyStore {
  EstimationCopyStore(
    this._database, {
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final AppDatabase _database;
  final DateTime Function() _clock;
  final Random _random;

  static const formatVersion = 1;

  /// Condición SQL de «legible en el contexto vigente», sobre la copia `c` y
  /// el contexto `a`.
  static const _readableInContext =
      'c.context_id = a.context_id AND c.generation <= a.generation '
      'AND NOT EXISTS (SELECT 1 FROM estimation_copy_retirements r '
      'WHERE r.context_id = a.context_id '
      'AND r.target_campaign_ref = c.target_campaign_ref '
      'AND r.generation >= c.generation)';

  Future<T> _write<T>(Future<T> Function(Transaction txn) body) => _database
      .replacement
      .write(() async => (await _database.database).transaction(body));

  String _newContextId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  static Future<({String id, int generation})?> _context(
    DatabaseExecutor db,
  ) async {
    final rows = await db.query('estimation_copy_access', where: 'id = 1');
    if (rows.isEmpty) return null;
    return (
      id: rows.single['context_id'] as String,
      generation: rows.single['generation'] as int,
    );
  }

  Future<void> _newContext(DatabaseExecutor db) => db.insert(
    'estimation_copy_access',
    {'id': 1, 'context_id': _newContextId(), 'generation': 0},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  /// Lo vigente al pedir la descarga de [identity]. Sin contexto, abre uno.
  Future<EstimationCopyGrant> grant(EstimationIdentity identity) =>
      _write((txn) async {
        var context = await _context(txn);
        if (context == null) {
          await _newContext(txn);
          context = (await _context(txn))!;
        }
        return EstimationCopyGrant._(identity, context.id, context.generation);
      });

  /// Guarda la descarga si, **dentro de la misma transacción**, el contexto es
  /// el de [grant], la campaña no se retiró después de pedirla, el titular
  /// vigente sigue siendo el de la identidad y la respuesta es de ese Member y
  /// sindicato. Sólo reemplaza a una copia legible por una descarga posterior.
  Future<EstimationSaveOutcome> save(
    EstimationCopyGrant grant,
    FarmerDownload download,
    Map<String, Object?> payload,
  ) => _write((txn) async {
    final identity = grant.identity;
    final context = await _context(txn);
    if (context == null || context.id != grant.contextId) {
      return EstimationSaveOutcome.accessChanged;
    }
    final retired = await txn.query(
      'estimation_copy_retirements',
      where: 'context_id=? AND target_campaign_ref=? AND generation>=?',
      whereArgs: [context.id, download.target.campaignRef, grant.generation],
    );
    if (retired.isNotEmpty) return EstimationSaveOutcome.targetRetired;
    final active = await txn.query('owner_bindings', where: 'ended_at IS NULL');
    if (active.length != 1 ||
        active.single['id'] != identity.bindingId ||
        active.single['member_id'] != identity.memberId ||
        active.single['tenant_id'] != identity.tenantId) {
      return EstimationSaveOutcome.accessChanged;
    }
    if (download.memberRef != identity.memberId ||
        download.tenantRef != identity.tenantId) {
      return EstimationSaveOutcome.otherSubject;
    }
    final existing = await _readableRows(
      txn,
      identity,
      campaignRef: download.target.campaignRef,
    );
    if (existing.isNotEmpty) {
      final previous = DateTime.tryParse(
        existing.single['downloaded_at'] as String,
      );
      if (previous != null && !download.downloadedAt.isAfter(previous)) {
        return EstimationSaveOutcome.keptNewer;
      }
    }
    await txn.insert('estimation_copies', {
      'member_ref': identity.memberId,
      'tenant_ref': identity.tenantId,
      'target_campaign_ref': download.target.campaignRef,
      'owner_binding_id': identity.bindingId,
      'context_id': grant.contextId,
      'generation': grant.generation,
      'format_version': formatVersion,
      'downloaded_at': download.downloadedAt.toIso8601String(),
      'saved_at': _clock().toUtc().toIso8601String(),
      'payload': jsonEncode(payload),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return EstimationSaveOutcome.saved;
  });

  static Future<List<Map<String, Object?>>> _readableRows(
    DatabaseExecutor db,
    EstimationIdentity identity, {
    String? campaignRef,
  }) => db.rawQuery(
    'SELECT c.* FROM estimation_copies c '
    'JOIN estimation_copy_access a ON a.id = 1 '
    'WHERE c.member_ref=? AND c.tenant_ref=? AND c.owner_binding_id=? '
    'AND c.format_version=? AND $_readableInContext'
    '${campaignRef == null ? '' : ' AND c.target_campaign_ref=?'} '
    'ORDER BY c.downloaded_at DESC, c.id DESC',
    [
      identity.memberId,
      identity.tenantId,
      identity.bindingId,
      formatVersion,
      if (campaignRef != null) campaignRef,
    ],
  );

  /// Las copias legibles de [identity], de la más reciente a la más antigua.
  /// Sin identidad o sin contexto no se lee nada. Una fila que no supera la
  /// validación del formato no se muestra.
  Future<List<StoredEstimationCopy>> readable(
    EstimationIdentity? identity,
  ) async {
    if (identity == null) return const [];
    final rows = await _readableRows(await _database.database, identity);
    final copies = <StoredEstimationCopy>[];
    for (final row in rows) {
      final copy = _decode(row, identity);
      if (copy != null) copies.add(copy);
    }
    return copies;
  }

  /// La copia legible de esa campaña para [identity], o null.
  Future<StoredEstimationCopy?> read(
    EstimationIdentity? identity,
    String campaignRef,
  ) async {
    for (final copy in await readable(identity)) {
      if (copy.download.target.campaignRef == campaignRef) return copy;
    }
    return null;
  }

  static StoredEstimationCopy? _decode(
    Map<String, Object?> row,
    EstimationIdentity identity,
  ) {
    try {
      final download = FarmerDownload.fromJson(
        jsonDecode(row['payload'] as String),
      );
      // La respuesta guardada tiene que ser de la fila: misma identidad y campaña.
      if (download.memberRef != identity.memberId ||
          download.tenantRef != identity.tenantId ||
          download.target.campaignRef != row['target_campaign_ref']) {
        return null;
      }
      return StoredEstimationCopy(
        download: download,
        savedAt: DateTime.parse(row['saved_at'] as String),
      );
    } on Object {
      return null;
    }
  }

  /// **Retirada** por cierre de sesión, cambio de identidad o rechazo de
  /// sesión, permiso o política: un contexto nuevo. Ninguna copia anterior
  /// vuelve a leerse y una descarga pedida antes ya no se guarda. No borra:
  /// eso es [purge]. Sin copias ni contexto, no escribe nada.
  Future<void> retireAll() async {
    final db = await _database.database;
    final present = await db.rawQuery(
      'SELECT 1 FROM estimation_copies UNION ALL '
      'SELECT 1 FROM estimation_copy_access LIMIT 1',
    );
    if (present.isEmpty) return;
    await _write(_newContext);
  }

  /// **Retirada** por un 404 de esa campaña: sus copias pedidas hasta ahora
  /// dejan de leerse, y una descarga posterior autorizada vuelve a valer
  /// (la generación sube). No borra: eso es [purge].
  Future<void> retireCampaign(String campaignRef) => _write((txn) async {
    final context = await _context(txn);
    if (context == null) return;
    await txn.insert('estimation_copy_retirements', {
      'context_id': context.id,
      'target_campaign_ref': campaignRef,
      'generation': context.generation,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.update('estimation_copy_access', {
      'generation': context.generation + 1,
    }, where: 'id = 1');
  });

  /// **Borrado físico** de lo que ya no es legible para [identity] (todo, si
  /// no hay identidad) y de las retiradas de contextos anteriores. Si no hay
  /// nada que borrar, no abre ninguna transacción. Si falla, la retirada ya
  /// estaba registrada: el borrado queda pendiente y se reintenta.
  Future<int> purge(EstimationIdentity? identity) async {
    final db = await _database.database;
    final (where, args) = identity == null
        ? ('1', const <Object?>[])
        : (
            'NOT EXISTS (SELECT 1 FROM estimation_copy_access a WHERE a.id = 1 '
                'AND c.member_ref=? AND c.tenant_ref=? AND c.owner_binding_id=? '
                'AND c.format_version=? AND $_readableInContext)',
            <Object?>[
              identity.memberId,
              identity.tenantId,
              identity.bindingId,
              formatVersion,
            ],
          );
    const staleRetirements =
        'context_id NOT IN (SELECT context_id FROM estimation_copy_access)';
    final pending = await db.rawQuery(
      'SELECT 1 FROM estimation_copies c WHERE $where UNION ALL '
      'SELECT 1 FROM estimation_copy_retirements WHERE $staleRetirements '
      'LIMIT 1',
      args,
    );
    if (pending.isEmpty) return 0;
    return _write((txn) async {
      final deleted = await txn.rawDelete(
        'DELETE FROM estimation_copies AS c WHERE $where',
        args,
      );
      await txn.delete('estimation_copy_retirements', where: staleRetirements);
      return deleted;
    });
  }
}
