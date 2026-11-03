// Copia descargada de la estimación del consumo en SQLite (F12-EST-07-MOB,
// MOB #164; RF-40, RN-30, DAT-20, INT-09 v1; contrato
// `F12_EST_07_COPIA_MOBILE.md` del servicio).
//
// **Regla de acceso.** Una copia sólo se lee para la identidad que la
// descargó: el mismo Member y sindicato **y** el mismo vínculo de titular.
// Quien llama pasa la identidad vigente de la instalación (activada, con la
// sesión segura del mismo ámbito que el titular); sin ella no se lee nada.
// Que exista una fila no autoriza a leerla.
//
// **Invalidación.** Cerrar la sesión, cambiar de titular o recibir un 401,
// 403 o 409 de política borran las copias; un 404 borra la de esa campaña.
// Cada invalidación borra además el identificador de acceso, en la misma
// transacción: una descarga pedida antes ya no se guarda aunque responda
// después, y la siguiente toma uno nuevo. En SQLite es atómico: si la
// transacción falla, no cambia nada y quien llama trata la copia como no
// legible mientras dure la sesión de la aplicación.
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
  const EstimationCopyGrant._(this.identity, this.accessId);
  final EstimationIdentity identity;
  final String accessId;
}

enum EstimationSaveOutcome {
  saved,

  /// Ya hay una copia igual o más reciente de esa campaña: se conserva.
  keptNewer,

  /// La sesión, el titular o el acceso cambiaron durante la descarga.
  accessChanged,

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

  Future<T> _write<T>(Future<T> Function(Transaction txn) body) => _database
      .replacement
      .write(() async => (await _database.database).transaction(body));

  String _newAccessId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  static Future<String?> _accessId(DatabaseExecutor db) async {
    final rows = await db.query('estimation_copy_access', where: 'id = 1');
    return rows.isEmpty ? null : rows.single['access_id'] as String;
  }

  Future<void> _renewAccess(DatabaseExecutor db) => db.insert(
    'estimation_copy_access',
    {'id': 1, 'access_id': _newAccessId()},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  /// Lo vigente al pedir la descarga de [identity].
  Future<EstimationCopyGrant> grant(EstimationIdentity identity) =>
      _write((txn) async {
        var accessId = await _accessId(txn);
        if (accessId == null) {
          await _renewAccess(txn);
          accessId = (await _accessId(txn))!;
        }
        return EstimationCopyGrant._(identity, accessId);
      });

  /// Guarda la descarga si, **dentro de la misma transacción**, el acceso es
  /// el de [grant], el titular vigente sigue siendo el de la identidad y la
  /// respuesta es de ese Member y sindicato. Sólo reemplaza por una descarga
  /// posterior de la misma identidad y campaña.
  Future<EstimationSaveOutcome> save(
    EstimationCopyGrant grant,
    FarmerDownload download,
    Map<String, Object?> payload,
  ) => _write((txn) async {
    final identity = grant.identity;
    if (await _accessId(txn) != grant.accessId) {
      return EstimationSaveOutcome.accessChanged;
    }
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
    final key = [
      identity.memberId,
      identity.tenantId,
      download.target.campaignRef,
    ];
    final existing = await txn.query(
      'estimation_copies',
      where: 'member_ref=? AND tenant_ref=? AND target_campaign_ref=?',
      whereArgs: key,
    );
    if (existing.isNotEmpty &&
        existing.single['owner_binding_id'] == identity.bindingId) {
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
      'format_version': formatVersion,
      'downloaded_at': download.downloadedAt.toIso8601String(),
      'saved_at': _clock().toUtc().toIso8601String(),
      'payload': jsonEncode(payload),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return EstimationSaveOutcome.saved;
  });

  /// Las copias legibles de [identity], de la más reciente a la más antigua.
  /// Sin identidad no se lee nada. Una fila que no supera la validación del
  /// formato no se muestra.
  Future<List<StoredEstimationCopy>> readable(
    EstimationIdentity? identity,
  ) async {
    if (identity == null) return const [];
    final db = await _database.database;
    final rows = await db.query(
      'estimation_copies',
      where: 'member_ref=? AND tenant_ref=? AND owner_binding_id=? AND format_version=?',
      whereArgs: [
        identity.memberId,
        identity.tenantId,
        identity.bindingId,
        formatVersion,
      ],
      orderBy: 'downloaded_at DESC, id DESC',
    );
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

  /// Cierre de sesión, cambio de identidad o titular, o rechazo de sesión,
  /// permiso o política: borra todas las copias y el acceso vigente (una
  /// descarga pedida antes ya no se guarda). Sin copias ni acceso, no abre
  /// ninguna transacción ni escribe nada.
  Future<void> discardAll() async {
    final db = await _database.database;
    final pending = await db.rawQuery(
      'SELECT 1 FROM estimation_copies UNION ALL '
      'SELECT 1 FROM estimation_copy_access LIMIT 1',
    );
    if (pending.isEmpty) return;
    await _write((txn) => AppDatabase.discardEstimationCopies(txn));
  }

  /// 404 de una campaña: borra su copia y el acceso vigente (una descarga en
  /// curso, de cualquier campaña, ya no se guarda).
  Future<void> discardCampaign(String campaignRef) => _write((txn) async {
    await txn.delete(
      'estimation_copies',
      where: 'target_campaign_ref=?',
      whereArgs: [campaignRef],
    );
    await txn.delete('estimation_copy_access');
  });

  /// Borra las filas que no son de [identity] (todas, si no hay identidad).
  /// Ya no eran legibles; esto sólo las elimina físicamente. Si no hay
  /// ninguna, no abre ninguna transacción.
  Future<int> discardForeign(EstimationIdentity? identity) async {
    final where = identity == null
        ? null
        : 'NOT (member_ref=? AND tenant_ref=? AND owner_binding_id=?)';
    final args = identity == null
        ? null
        : [identity.memberId, identity.tenantId, identity.bindingId];
    final db = await _database.database;
    final foreign = await db.query(
      'estimation_copies',
      columns: ['id'],
      where: where,
      whereArgs: args,
      limit: 1,
    );
    if (foreign.isEmpty) return 0;
    return _write(
      (txn) => txn.delete('estimation_copies', where: where, whereArgs: args),
    );
  }
}
