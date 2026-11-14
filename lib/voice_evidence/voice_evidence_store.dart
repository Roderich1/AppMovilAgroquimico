/// Almacén local de la evidencia de dictado (F09-VOZ-13, MOB #167).
///
/// Reglas que viven aquí:
///
/// 1. **Sin consentimiento no se guarda nada.** El consentimiento se lee en
///    la misma transacción que escribe: una retirada simultánea gana.
/// 2. El consentimiento es explícito, sólo para la evaluación de la voz, con
///    la versión del texto aceptado y la fecha. No se deduce de ningún otro
///    permiso.
/// 3. Retirar el consentimiento borra toda la evidencia y el propio
///    consentimiento, con `secure_delete` para no dejar los textos en
///    páginas libres del archivo. También se puede borrar la evidencia sin
///    retirar el consentimiento, o una sola entrada.
/// 4. Nada de audio, y nada de lo dictado en ningún log.
/// 5. Este almacén no conoce Sync v1 ni el respaldo: la exclusión de ambos
///    está en `BackupService` (que descarta las tablas en el archivo y al
///    restaurar) y en que Sync v1 sólo lee `sync_outbox`.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import 'voice_evidence.dart';

/// Finalidad única del consentimiento.
const voiceEvidencePurpose = 'F09_VOICE_EVALUATION';

final class VoiceEvidenceConsent {
  const VoiceEvidenceConsent({
    required this.consentTextVersion,
    required this.grantedAt,
  });

  /// Versión del texto de consentimiento que la persona aceptó.
  final String consentTextVersion;

  /// Fecha y hora UTC en que lo dio.
  final DateTime grantedAt;
}

/// Una entrada guardada, tal como la lee el evaluador.
final class StoredVoiceEvidence {
  const StoredVoiceEvidence({
    required this.id,
    required this.recordedAt,
    required this.consentGrantedAt,
    required this.kind,
    required this.outcome,
    required this.transcripts,
    required this.proposed,
    required this.corrections,
    this.confirmed,
    this.sheetRef,
    this.engine,
    this.model,
    this.appCommit,
    this.firstPartialMs,
    this.finalMs,
  });

  final int id;
  final DateTime recordedAt;
  final DateTime consentGrantedAt;
  final VoiceEvidenceKind kind;
  final VoiceEvidenceOutcome outcome;
  final List<String> transcripts;
  final List<EvidenceField> proposed;

  /// Correcciones tal como se guardaron (JSON).
  final List<Map<String, Object?>> corrections;
  final List<EvidenceField>? confirmed;
  final String? sheetRef;
  final String? engine;
  final String? model;
  final String? appCommit;
  final int? firstPartialMs;
  final int? finalMs;
}

class VoiceEvidenceStore implements VoiceEvidenceSink {
  VoiceEvidenceStore(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  static const _consentTable = 'voice_evidence_consent';
  static const _table = 'voice_evidence';
  static const _maxSheetRef = 100;

  String _now() => _clock().toUtc().toIso8601String();

  /// El consentimiento vigente, o `null`.
  Future<VoiceEvidenceConsent?> consent() async =>
      _readConsent(await _database.database);

  static Future<VoiceEvidenceConsent?> _readConsent(DatabaseExecutor db) async {
    final rows = await db.query(
      _consentTable,
      where: 'id=1 AND purpose=?',
      whereArgs: [voiceEvidencePurpose],
    );
    if (rows.isEmpty) return null;
    return VoiceEvidenceConsent(
      consentTextVersion: rows.single['consent_text_version']! as String,
      grantedAt: DateTime.parse(rows.single['granted_at']! as String),
    );
  }

  /// Registra el consentimiento explícito. Si ya había uno, se conserva el
  /// existente (con su fecha) y se devuelve.
  Future<VoiceEvidenceConsent> grantConsent({
    required String consentTextVersion,
  }) async {
    final version = consentTextVersion.trim();
    if (version.isEmpty || version.length > 100) {
      throw ArgumentError.value(
        consentTextVersion,
        'consentTextVersion',
        'debe identificar el texto aceptado (1 a 100 caracteres)',
      );
    }
    final db = await _database.database;
    return db.transaction((txn) async {
      final existing = await _readConsent(txn);
      if (existing != null) return existing;
      final grantedAt = _now();
      await txn.insert(_consentTable, {
        'id': 1,
        'purpose': voiceEvidencePurpose,
        'consent_text_version': version,
        'granted_at': grantedAt,
      });
      return VoiceEvidenceConsent(
        consentTextVersion: version,
        grantedAt: DateTime.parse(grantedAt),
      );
    });
  }

  /// Retira el consentimiento y borra toda la evidencia. Devuelve cuántas
  /// entradas se borraron. Sin consentimiento previo no hace nada más que
  /// borrar lo que hubiera.
  Future<int> revokeConsent() => _secureDelete((txn) async {
    final erased = await txn.delete(_table);
    await txn.delete(_consentTable);
    return erased;
  });

  /// Borra toda la evidencia y conserva el consentimiento.
  Future<int> eraseAll() => _secureDelete((txn) => txn.delete(_table));

  /// Borra una entrada. Devuelve `true` si existía.
  Future<bool> erase(int id) async =>
      await _secureDelete(
        (txn) => txn.delete(_table, where: 'id=?', whereArgs: [id]),
      ) ==
      1;

  /// Borra con `secure_delete` activado: SQLite sobrescribe con ceros el
  /// contenido borrado en lugar de dejarlo en páginas libres. Se restaura el
  /// valor anterior al terminar.
  Future<int> _secureDelete(
    Future<int> Function(Transaction txn) delete,
  ) async {
    final db = await _database.database;
    final previous =
        Sqflite.firstIntValue(await db.rawQuery('PRAGMA secure_delete')) ?? 0;
    await db.rawQuery('PRAGMA secure_delete = 1');
    try {
      return await db.transaction(delete);
    } finally {
      await db.rawQuery('PRAGMA secure_delete = $previous');
    }
  }

  /// Entrega una entrada. Nunca lanza.
  @override
  Future<VoiceEvidenceRecordResult> record(VoiceEvidenceEntry entry) async {
    if (!_coherent(entry)) return VoiceEvidenceRecordResult.rejected;
    try {
      final db = await _database.database;
      return await db.transaction((txn) async {
        final consent = await _readConsent(txn);
        if (consent == null) return VoiceEvidenceRecordResult.noConsent;
        final started = entry.dictationStartedAt;
        if (started != null && consent.grantedAt.isAfter(started.toUtc())) {
          return VoiceEvidenceRecordResult.consentAfterDictation;
        }
        await txn.insert(_table, {
          'format_version': 1,
          'consent_granted_at': consent.grantedAt.toIso8601String(),
          'recorded_at': _now(),
          'kind': entry.kind.code,
          'outcome': entry.outcome.code,
          'sheet_ref': entry.sheetRef?.trim(),
          'transcripts': jsonEncode(entry.transcripts),
          'proposed_fields': jsonEncode([
            for (final f in entry.proposed) f.toJson(),
          ]),
          'corrections': jsonEncode([
            for (final c in entry.corrections) c.toJson(),
          ]),
          'confirmed_fields': entry.confirmed == null
              ? null
              : jsonEncode([for (final f in entry.confirmed!) f.toJson()]),
          'engine': entry.engine,
          'model': entry.model,
          'app_commit': entry.appCommit,
          'first_partial_ms': entry.firstPartialMs,
          'final_ms': entry.finalMs,
        });
        return VoiceEvidenceRecordResult.stored;
      });
    } on Object {
      // Sin registrar el contenido: podría incluir lo dictado.
      return VoiceEvidenceRecordResult.failed;
    }
  }

  static bool _coherent(VoiceEvidenceEntry entry) {
    final confirmed = entry.outcome == VoiceEvidenceOutcome.confirmed;
    if (confirmed != (entry.confirmed != null)) return false;
    final sheet = entry.sheetRef?.trim();
    if (sheet != null && (sheet.isEmpty || sheet.length > _maxSheetRef)) {
      return false;
    }
    if ((entry.firstPartialMs ?? 0) < 0 || (entry.finalMs ?? 0) < 0) {
      return false;
    }
    return true;
  }

  /// Toda la evidencia, para el evaluador y dentro de la finalidad del
  /// consentimiento. Sin consentimiento vigente no devuelve nada.
  Future<List<StoredVoiceEvidence>> readAll() async {
    final db = await _database.database;
    if (await _readConsent(db) == null) return const [];
    final rows = await db.query(_table, orderBy: 'id');
    return [for (final row in rows) _fromRow(row)];
  }

  /// Cuántas entradas hay (para mostrarlo antes de borrar).
  Future<int> count() async {
    final db = await _database.database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_table'),
        ) ??
        0;
  }

  static StoredVoiceEvidence _fromRow(Map<String, Object?> row) {
    List<EvidenceField> fields(String json) => [
      for (final f in jsonDecode(json) as List)
        EvidenceField.fromJson((f as Map).cast<String, Object?>()),
    ];
    final confirmed = row['confirmed_fields'] as String?;
    return StoredVoiceEvidence(
      id: row['id']! as int,
      recordedAt: DateTime.parse(row['recorded_at']! as String),
      consentGrantedAt: DateTime.parse(row['consent_granted_at']! as String),
      kind: VoiceEvidenceKind.fromCode(row['kind']! as String),
      outcome: VoiceEvidenceOutcome.fromCode(row['outcome']! as String),
      transcripts: [
        for (final t in jsonDecode(row['transcripts']! as String) as List)
          t as String,
      ],
      proposed: fields(row['proposed_fields']! as String),
      corrections: [
        for (final c in jsonDecode(row['corrections']! as String) as List)
          (c as Map).cast<String, Object?>(),
      ],
      confirmed: confirmed == null ? null : fields(confirmed),
      sheetRef: row['sheet_ref'] as String?,
      engine: row['engine'] as String?,
      model: row['model'] as String?,
      appCommit: row['app_commit'] as String?,
      firstPartialMs: row['first_partial_ms'] as int?,
      finalMs: row['final_ms'] as int?,
    );
  }

  /// Tablas de este almacén (para las comprobaciones de exclusión).
  static Set<String> get tables => AppDatabase.voiceEvidenceTables;
}
