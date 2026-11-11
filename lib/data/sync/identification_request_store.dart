import 'dart:math';

import 'package:sqflite/sqflite.dart' show DatabaseExecutor, Transaction;

import '../../domain/sync/identification_view.dart';
import '../../domain/sync/operation_id.dart' show newOperationId;
import '../agro_repository.dart' show BusinessRuleException;
import '../app_database.dart';
import '../farmer_operation_gate.dart';

/// Estados de envío de los datos de una solicitud (E1 §5).
abstract final class IdentificationSendStatus {
  static const pendingSend = 'PENDING_SEND';
  static const received = 'RECEIVED';
  static const rejected = 'REJECTED';
  static const authPaused = 'AUTH_PAUSED';
}

/// Estados de envío de la foto de una solicitud (E1 §5).
abstract final class IdentificationPhotoStatus {
  static const none = 'NONE';
  static const pendingSend = 'PENDING_SEND';
  static const sent = 'SENT';
  static const failed = 'FAILED';
  static const removePending = 'REMOVE_PENDING';
  static const removed = 'REMOVED';
}

class IdentificationRequestException extends BusinessRuleException {
  IdentificationRequestException(super.message);
}

/// Una solicitud de identificación guardada en el teléfono.
class IdentificationRequest {
  const IdentificationRequest({
    required this.requestId,
    required this.productId,
    required this.tenantId,
    required this.sentName,
    required this.sentActiveIngredient,
    required this.sentUnit,
    required this.photoConsentVersion,
    required this.photoConsentAt,
    required this.photoSha256Consented,
    required this.sendStatus,
    required this.sendAttempts,
    required this.nextAttemptAt,
    required this.lastCode,
    required this.photoSendStatus,
    required this.photoAttempts,
    required this.photoNextAttemptAt,
    required this.photoLastCode,
    required this.serverStatus,
    required this.serverProductRef,
    required this.serverProductName,
    required this.serverProductUnit,
    required this.serverResolution,
    required this.serverNote,
    required this.serverCheckedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String requestId;
  final int productId;
  final String tenantId;
  final String sentName;
  final String? sentActiveIngredient;
  final String sentUnit;
  final String? photoConsentVersion;
  final String? photoConsentAt;
  final String? photoSha256Consented;
  final String sendStatus;
  final int sendAttempts;
  final String? nextAttemptAt;
  final String? lastCode;
  final String photoSendStatus;
  final int photoAttempts;
  final String? photoNextAttemptAt;
  final String? photoLastCode;
  final String? serverStatus;
  final String? serverProductRef;
  final String? serverProductName;
  final String? serverProductUnit;
  final String? serverResolution;
  final String? serverNote;
  final String? serverCheckedAt;
  final String createdAt;
  final String updatedAt;

  bool get isLinked =>
      serverStatus == 'LINKED' &&
      serverProductRef != null &&
      serverProductName != null;

  /// Un fallo de la foto que se reintentará (con fecha de reintento); sin
  /// ella, el fallo es definitivo.
  bool get photoRetryable =>
      photoSendStatus == IdentificationPhotoStatus.failed &&
      photoNextAttemptAt != null;

  /// La foto compartida con el sindicato (o por compartir): reemplazarla
  /// vuelve a preguntar si se envía la nueva (E1-D11).
  bool get photoShared => const {
    IdentificationPhotoStatus.pendingSend,
    IdentificationPhotoStatus.sent,
    IdentificationPhotoStatus.failed,
    IdentificationPhotoStatus.removePending,
    IdentificationPhotoStatus.removed,
  }.contains(photoSendStatus);

  static IdentificationRequest fromRow(
    Map<String, Object?> row, [
    String prefix = '',
  ]) => IdentificationRequest(
    requestId: row['${prefix}request_id']! as String,
    productId: row['${prefix}product_id']! as int,
    tenantId: row['${prefix}tenant_id']! as String,
    sentName: row['${prefix}sent_name']! as String,
    sentActiveIngredient: row['${prefix}sent_active_ingredient'] as String?,
    sentUnit: row['${prefix}sent_unit']! as String,
    photoConsentVersion: row['${prefix}photo_consent_version'] as String?,
    photoConsentAt: row['${prefix}photo_consent_at'] as String?,
    photoSha256Consented: row['${prefix}photo_sha256_consented'] as String?,
    sendStatus: row['${prefix}send_status']! as String,
    sendAttempts: row['${prefix}send_attempts']! as int,
    nextAttemptAt: row['${prefix}next_attempt_at'] as String?,
    lastCode: row['${prefix}last_code'] as String?,
    photoSendStatus: row['${prefix}photo_send_status']! as String,
    photoAttempts: row['${prefix}photo_attempts']! as int,
    photoNextAttemptAt: row['${prefix}photo_next_attempt_at'] as String?,
    photoLastCode: row['${prefix}photo_last_code'] as String?,
    serverStatus: row['${prefix}server_status'] as String?,
    serverProductRef: row['${prefix}server_product_ref'] as String?,
    serverProductName: row['${prefix}server_product_name'] as String?,
    serverProductUnit: row['${prefix}server_product_unit'] as String?,
    serverResolution: row['${prefix}server_resolution'] as String?,
    serverNote: row['${prefix}server_note'] as String?,
    serverCheckedAt: row['${prefix}server_checked_at'] as String?,
    createdAt: row['${prefix}created_at']! as String,
    updatedAt: row['${prefix}updated_at']! as String,
  );
}

/// Un producto local activo con su solicitud, si la tiene.
class ProductWithRequest {
  const ProductWithRequest(this.product, this.request);

  /// Las columnas de `products`, como `AgroRepository.products()`.
  final Map<String, Object?> product;
  final IdentificationRequest? request;
}

/// Solicitudes de identificación de productos locales (contrato E1 §5).
///
/// Canal propio, aparte de Sync v1 y de `sync_outbox` (E1-D2, E1-D12): una
/// fila por producto local con un `request_id` UUID v4 generado **una sola
/// vez** al crearla, de modo que un reenvío nunca duplica la solicitud
/// (E1-D3). Sólo guarda lo que se enviará (nombre, ingrediente, unidad y,
/// con consentimiento aparte, la huella de la foto autorizada) y la última
/// vista del sindicato. Nunca vincula nada por sí misma (E1-D4).
class IdentificationRequestStore {
  IdentificationRequestStore(
    this._database, {
    FarmerOperationGate gate = const FarmerOperationGate.unrestricted(),
    DateTime Function()? clock,
    Random? random,
  }) : _gate = gate,
       _clock = clock ?? DateTime.now,
       _random = random;

  final AppDatabase _database;
  final FarmerOperationGate _gate;
  final DateTime Function() _clock;
  final Random? _random;

  static const table = 'product_identification_requests';

  /// Longitud máxima de nombre e ingrediente (contrato E1 §4.1).
  static const maxTextLength = 120;

  String _now() => _clock().toUtc().toIso8601String();

  Future<T> _write<T>(Future<T> Function(Transaction txn) body) =>
      _database.replacement.write(() async {
        _gate.ensureAllowed();
        return (await _database.database).transaction(body);
      });

  /// Crea la solicitud de [productId] con los datos actuales del producto.
  /// Si [sharePhoto], registra el consentimiento `FOTO-1` con la fecha de
  /// ahora y la huella de la foto vigente: sólo esa foto se podrá enviar.
  Future<IdentificationRequest> create({
    required int productId,
    required bool sharePhoto,
  }) async {
    final requestId = newOperationId(_random);
    await _write((txn) async {
      final owner = await txn.query(
        'owner_bindings',
        columns: ['tenant_id'],
        where: 'ended_at IS NULL',
      );
      if (owner.isEmpty) {
        throw IdentificationRequestException(
          'Elija primero el titular de estos datos para pedir la '
          'identificación al sindicato.',
        );
      }
      final rows = await txn.query(
        'products',
        columns: ['name', 'active_ingredient', 'unit', 'photo_sha256'],
        where: 'id=?',
        whereArgs: [productId],
      );
      if (rows.isEmpty) {
        throw IdentificationRequestException('El producto local no existe.');
      }
      if ((await txn.query(
        'product_bindings',
        columns: ['product_id'],
        where: 'product_id=?',
        whereArgs: [productId],
      )).isNotEmpty) {
        throw IdentificationRequestException(
          'Este producto ya está vinculado con el sindicato.',
        );
      }
      if ((await txn.query(
        table,
        columns: ['request_id'],
        where: 'product_id=?',
        whereArgs: [productId],
      )).isNotEmpty) {
        throw IdentificationRequestException(
          'Ya se pidió la identificación de este producto.',
        );
      }
      final product = rows.single;
      final name = (product['name']! as String).trim();
      final ingredient = (product['active_ingredient'] as String?)?.trim();
      if (name.isEmpty || name.length > maxTextLength) {
        throw IdentificationRequestException(
          'El nombre del producto debe tener entre 1 y $maxTextLength '
          'caracteres. Corríjalo en Catálogos antes de pedir la '
          'identificación.',
        );
      }
      if (ingredient != null && ingredient.length > maxTextLength) {
        throw IdentificationRequestException(
          'El ingrediente activo supera $maxTextLength caracteres. Corríjalo '
          'en Catálogos antes de pedir la identificación.',
        );
      }
      final photoSha = product['photo_sha256'] as String?;
      if (sharePhoto && photoSha == null) {
        throw IdentificationRequestException(
          'El producto no tiene foto de la etiqueta.',
        );
      }
      final now = _now();
      await txn.insert(table, {
        'request_id': requestId,
        'product_id': productId,
        'tenant_id': owner.single['tenant_id']! as String,
        'sent_name': name,
        'sent_active_ingredient': (ingredient?.isEmpty ?? true)
            ? null
            : ingredient,
        'sent_unit': product['unit']! as String,
        'photo_consent_version': sharePhoto ? photoConsentVersion : null,
        'photo_consent_at': sharePhoto ? now : null,
        'photo_sha256_consented': sharePhoto ? photoSha : null,
        'send_status': IdentificationSendStatus.pendingSend,
        'photo_send_status': sharePhoto
            ? IdentificationPhotoStatus.pendingSend
            : IdentificationPhotoStatus.none,
        'created_at': now,
        'updated_at': now,
      });
    });
    return (await byId(requestId))!;
  }

  Future<List<IdentificationRequest>> all([DatabaseExecutor? executor]) async {
    final db = executor ?? await _database.database;
    return (await db.query(
      table,
      orderBy: 'created_at, request_id',
    )).map(IdentificationRequest.fromRow).toList();
  }

  Future<IdentificationRequest?> byId(String requestId) async {
    final rows = await (await _database.database).query(
      table,
      where: 'request_id=?',
      whereArgs: [requestId],
    );
    return rows.isEmpty ? null : IdentificationRequest.fromRow(rows.single);
  }

  Future<IdentificationRequest?> byProduct(
    int productId, [
    DatabaseExecutor? executor,
  ]) async {
    final db = executor ?? await _database.database;
    final rows = await db.query(
      table,
      where: 'product_id=?',
      whereArgs: [productId],
    );
    return rows.isEmpty ? null : IdentificationRequest.fromRow(rows.single);
  }

  /// Productos activos (como `AgroRepository.products()`) con su solicitud,
  /// en **una sola consulta**: la pantalla de vínculos no suma lecturas.
  Future<List<ProductWithRequest>> productsWithRequests() async {
    final columns = _columns
        .map((column) => 'r.$column AS r_$column')
        .join(', ');
    final rows = await (await _database.database).rawQuery(
      'SELECT p.*, $columns FROM products p '
      'LEFT JOIN $table r ON r.product_id = p.id '
      'WHERE p.active=1 ORDER BY p.name',
    );
    return [
      for (final row in rows)
        ProductWithRequest(
          {
            for (final entry in row.entries)
              if (!entry.key.startsWith('r_')) entry.key: entry.value,
          },
          row['r_request_id'] == null
              ? null
              : IdentificationRequest.fromRow(row, 'r_'),
        ),
    ];
  }

  static const List<String> _columns = [
    'request_id',
    'product_id',
    'tenant_id',
    'sent_name',
    'sent_active_ingredient',
    'sent_unit',
    'photo_consent_version',
    'photo_consent_at',
    'photo_sha256_consented',
    'send_status',
    'send_attempts',
    'next_attempt_at',
    'last_code',
    'photo_send_status',
    'photo_attempts',
    'photo_next_attempt_at',
    'photo_last_code',
    'server_status',
    'server_product_ref',
    'server_product_name',
    'server_product_unit',
    'server_resolution',
    'server_note',
    'server_checked_at',
    'created_at',
    'updated_at',
  ];

  /// Solicitudes de [tenantId] con trabajo pendiente: datos por enviar
  /// (también las pausadas por autorización si [includePaused]) o foto por
  /// enviar o retirar. La fecha de reintento la decide el emisor.
  Future<List<IdentificationRequest>> withPendingWork(
    String tenantId, {
    required bool includePaused,
  }) async {
    final rows = await (await _database.database).query(
      table,
      where:
          'tenant_id=? AND (send_status=? OR (send_status=? AND ?=1) OR '
          '(send_status=? AND (photo_send_status IN (?,?) OR '
          '(photo_send_status=? AND photo_next_attempt_at IS NOT NULL))))',
      whereArgs: [
        tenantId,
        IdentificationSendStatus.pendingSend,
        IdentificationSendStatus.authPaused,
        includePaused ? 1 : 0,
        IdentificationSendStatus.received,
        IdentificationPhotoStatus.pendingSend,
        IdentificationPhotoStatus.removePending,
        IdentificationPhotoStatus.failed,
      ],
      orderBy: 'created_at, request_id',
    );
    return rows.map(IdentificationRequest.fromRow).toList();
  }

  /// ¿Hay alguna solicitud de [tenantId]? Sin ninguna, no hay nada que
  /// consultar al sindicato.
  Future<bool> hasAny(String tenantId) async =>
      (await (await _database.database).query(
        table,
        columns: ['request_id'],
        where: 'tenant_id=?',
        whereArgs: [tenantId],
        limit: 1,
      )).isNotEmpty;

  /// «Enviar ahora»: lo pendiente queda listo para el próximo envío, sin
  /// esperar el reintento; lo pausado por autorización vuelve a la cola. Un
  /// rechazo o un fallo definitivo de la foto no cambian.
  Future<void> sendNow(String requestId) => _write((txn) async {
    final now = _now();
    await txn.rawUpdate(
      'UPDATE $table SET next_attempt_at=NULL, updated_at=?, '
      'send_status=CASE WHEN send_status=? THEN ? ELSE send_status END '
      'WHERE request_id=? AND send_status IN (?,?)',
      [
        now,
        IdentificationSendStatus.authPaused,
        IdentificationSendStatus.pendingSend,
        requestId,
        IdentificationSendStatus.pendingSend,
        IdentificationSendStatus.authPaused,
      ],
    );
    await txn.rawUpdate(
      'UPDATE $table SET photo_next_attempt_at=NULL, updated_at=? '
      'WHERE request_id=? AND (photo_send_status IN (?,?) OR '
      '(photo_send_status=? AND photo_next_attempt_at IS NOT NULL))',
      [
        now,
        requestId,
        IdentificationPhotoStatus.pendingSend,
        IdentificationPhotoStatus.removePending,
        IdentificationPhotoStatus.failed,
      ],
    );
  });

  // --- Transiciones de los datos ---------------------------------------

  Future<void> markReceived(String requestId) => _update(
    requestId,
    {
      'send_status': IdentificationSendStatus.received,
      'next_attempt_at': null,
      'last_code': null,
    },
    countAttempt: 'send_attempts',
    fromSendStatus: const [
      IdentificationSendStatus.pendingSend,
      IdentificationSendStatus.authPaused,
      IdentificationSendStatus.received,
    ],
  );

  /// Rechazo definitivo: no se reintenta.
  Future<void> markRejected(String requestId, String code) => _update(
    requestId,
    {
      'send_status': IdentificationSendStatus.rejected,
      'next_attempt_at': null,
      'last_code': code,
    },
    countAttempt: 'send_attempts',
    fromSendStatus: const [
      IdentificationSendStatus.pendingSend,
      IdentificationSendStatus.authPaused,
    ],
  );

  /// 401/403: se pausa hasta que el agricultor vuelva a enviar con acceso.
  Future<void> markAuthPaused(String requestId, String code) => _update(
    requestId,
    {
      'send_status': IdentificationSendStatus.authPaused,
      'next_attempt_at': null,
      'last_code': code,
    },
    countAttempt: 'send_attempts',
    fromSendStatus: const [
      IdentificationSendStatus.pendingSend,
      IdentificationSendStatus.authPaused,
    ],
  );

  /// Fallo transitorio: sigue pendiente y se reintenta en [retryAt].
  Future<void> scheduleRetry(String requestId, String code, DateTime retryAt) =>
      _update(
        requestId,
        {
          'send_status': IdentificationSendStatus.pendingSend,
          'next_attempt_at': retryAt.toUtc().toIso8601String(),
          'last_code': code,
        },
        countAttempt: 'send_attempts',
        fromSendStatus: const [
          IdentificationSendStatus.pendingSend,
          IdentificationSendStatus.authPaused,
        ],
      );

  // --- Transiciones de la foto -------------------------------------------

  Future<void> markPhotoSent(String requestId, String sha256) => _update(
    requestId,
    {
      'photo_send_status': IdentificationPhotoStatus.sent,
      'photo_next_attempt_at': null,
      'photo_last_code': null,
    },
    countAttempt: 'photo_attempts',
    fromPhotoStatus: const [
      IdentificationPhotoStatus.pendingSend,
      IdentificationPhotoStatus.failed,
    ],
    // Si la foto autorizada cambió durante el envío, no se marca como
    // enviada la nueva.
    whereConsentedSha: sha256,
  );

  /// Fallo de la foto: con [retryAt] se reintentará; sin él es definitivo.
  /// Los datos de la solicitud no cambian (E1-D12).
  Future<void> markPhotoFailed(
    String requestId,
    String code, {
    DateTime? retryAt,
  }) => _update(
    requestId,
    {
      'photo_send_status': IdentificationPhotoStatus.failed,
      'photo_next_attempt_at': retryAt?.toUtc().toIso8601String(),
      'photo_last_code': code,
    },
    countAttempt: 'photo_attempts',
    fromPhotoStatus: const [
      IdentificationPhotoStatus.pendingSend,
      IdentificationPhotoStatus.failed,
    ],
  );

  /// El retiro pendiente se reintentará en [retryAt].
  Future<void> schedulePhotoRemovalRetry(
    String requestId,
    String code,
    DateTime retryAt,
  ) => _update(
    requestId,
    {
      'photo_next_attempt_at': retryAt.toUtc().toIso8601String(),
      'photo_last_code': code,
    },
    countAttempt: 'photo_attempts',
    fromPhotoStatus: const [IdentificationPhotoStatus.removePending],
  );

  Future<void> markPhotoRemoved(String requestId) => _update(
    requestId,
    {
      'photo_send_status': IdentificationPhotoStatus.removed,
      'photo_next_attempt_at': null,
      'photo_last_code': null,
    },
    countAttempt: 'photo_attempts',
    fromPhotoStatus: const [IdentificationPhotoStatus.removePending],
  );

  Future<void> _update(
    String requestId,
    Map<String, Object?> values, {
    required String countAttempt,
    List<String>? fromSendStatus,
    List<String>? fromPhotoStatus,
    String? whereConsentedSha,
  }) => _write((txn) async {
    final where = StringBuffer('request_id=?');
    final args = <Object?>[requestId];
    if (fromSendStatus != null) {
      where.write(
        ' AND send_status IN (${List.filled(fromSendStatus.length, '?').join(',')})',
      );
      args.addAll(fromSendStatus);
    }
    if (fromPhotoStatus != null) {
      where.write(
        ' AND photo_send_status IN (${List.filled(fromPhotoStatus.length, '?').join(',')})',
      );
      args.addAll(fromPhotoStatus);
    }
    if (whereConsentedSha != null) {
      where.write(' AND photo_sha256_consented=?');
      args.add(whereConsentedSha);
    }
    final assignments = [
      for (final key in values.keys) '$key=?',
      '$countAttempt=$countAttempt+1',
      'updated_at=?',
    ].join(', ');
    await txn.rawUpdate('UPDATE $table SET $assignments WHERE $where', [
      ...values.values,
      _now(),
      ...args,
    ]);
  });

  // --- Vista del sindicato ----------------------------------------------

  /// Aplica una vista del sindicato a la solicitud local con el mismo
  /// `request_id`. Valida la lista cerrada antes de tocar nada: una clave
  /// desconocida lanza [IdentificationViewFormatException] sin escribir.
  /// Devuelve false si no hay solicitud local con ese id.
  Future<bool> applyServerView(Object? json) async =>
      applyParsedView(IdentificationServerView.fromJson(json));

  Future<bool> applyParsedView(IdentificationServerView view) =>
      _write((txn) async {
        final resolution = view.resolution;
        final changed = await txn.update(
          table,
          {
            'server_status': view.status,
            'server_product_ref': resolution?.productRef,
            'server_product_name': resolution?.productName,
            'server_product_unit': resolution?.unit,
            'server_resolution': resolution?.kind,
            'server_note': view.pendingNote,
            'server_checked_at': _now(),
            'updated_at': _now(),
          },
          where: 'request_id=?',
          whereArgs: [view.requestId],
        );
        return changed > 0;
      });

  // --- Foto local (desde AgroRepository, en su transacción) ---------------

  /// Tras guardar una foto nueva de [productId] con huella [newSha]:
  ///
  /// - [share] true: consentimiento `FOTO-1` nuevo con la fecha de ahora,
  ///   la nueva huella autorizada y la foto pendiente de envío.
  /// - [share] false o null (sólo en el teléfono): el sindicato conserva la
  ///   foto que ya tenía. Una foto autorizada que todavía no salió nunca
  ///   deja de estar pendiente, porque ya no existe.
  static Future<void> onPhotoReplaced(
    Transaction txn,
    int productId, {
    required String newSha,
    required bool? share,
    required String now,
  }) async {
    final rows = await txn.query(
      table,
      columns: ['photo_send_status', 'photo_attempts'],
      where: 'product_id=?',
      whereArgs: [productId],
    );
    if (rows.isEmpty) return;
    final status = rows.single['photo_send_status']! as String;
    if (share == true) {
      await txn.update(
        table,
        {
          'photo_consent_version': photoConsentVersion,
          'photo_consent_at': now,
          'photo_sha256_consented': newSha,
          'photo_send_status': IdentificationPhotoStatus.pendingSend,
          'photo_attempts': 0,
          'photo_next_attempt_at': null,
          'photo_last_code': null,
          'updated_at': now,
        },
        where: 'product_id=?',
        whereArgs: [productId],
      );
      return;
    }
    if (status == IdentificationPhotoStatus.pendingSend &&
        rows.single['photo_attempts'] == 0) {
      await txn.update(
        table,
        {
          'photo_send_status': IdentificationPhotoStatus.none,
          'photo_next_attempt_at': null,
          'updated_at': now,
        },
        where: 'product_id=?',
        whereArgs: [productId],
      );
    }
  }

  /// Tras quitar la foto local de [productId]: si pudo llegar al sindicato,
  /// queda el retiro pendiente (`REMOVE_PENDING`); si nunca salió, deja de
  /// estar pendiente.
  static Future<void> onPhotoRemoved(
    Transaction txn,
    int productId, {
    required String now,
  }) async {
    final rows = await txn.query(
      table,
      columns: ['photo_send_status', 'photo_attempts'],
      where: 'product_id=?',
      whereArgs: [productId],
    );
    if (rows.isEmpty) return;
    final status = rows.single['photo_send_status']! as String;
    final attempted = (rows.single['photo_attempts']! as int) > 0;
    final String next;
    if (status == IdentificationPhotoStatus.sent ||
        status == IdentificationPhotoStatus.failed ||
        status == IdentificationPhotoStatus.removePending ||
        (status == IdentificationPhotoStatus.pendingSend && attempted)) {
      next = IdentificationPhotoStatus.removePending;
    } else if (status == IdentificationPhotoStatus.pendingSend) {
      next = IdentificationPhotoStatus.none;
    } else {
      return;
    }
    await txn.update(
      table,
      {
        'photo_send_status': next,
        'photo_attempts': 0,
        'photo_next_attempt_at': null,
        'photo_last_code': null,
        'updated_at': now,
      },
      where: 'product_id=?',
      whereArgs: [productId],
    );
  }
}
