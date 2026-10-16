// Cliente del respaldo privado remoto (F08-BKP-04, MOB #35) sobre
// `/api/v1/me/backups` del Backend (BE #39). El servidor deriva el titular de
// la sesión: el cliente nunca envía Member, tenant ni nombre de archivo.
//
// Backup no es Sync (F06 §8): este cliente no toca la outbox ni publica nada.
// No registra cuerpos, hashes ni credenciales.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../auth/api_endpoint_config.dart';
import '../auth/auth_api_exception.dart';

/// Metadatos de una copia remota propia, tal como los confirma el servidor.
class RemoteBackupEntry {
  const RemoteBackupEntry({
    required this.id,
    required this.sha256,
    required this.sizeBytes,
    required this.formatVersion,
    required this.schemaVersion,
    required this.createdAt,
  });

  final String id;
  final String sha256;
  final int sizeBytes;
  final int formatVersion;
  final int schemaVersion;
  final DateTime createdAt;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Valida el contrato cerrado del Backend; null si no lo cumple.
  static RemoteBackupEntry? validate(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    const keys = {
      'id',
      'sha256',
      'sizeBytes',
      'contentType',
      'formatVersion',
      'schemaVersion',
      'createdAt',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty) return null;
    final id = json['id'];
    final sha = json['sha256'];
    final size = json['sizeBytes'];
    final format = json['formatVersion'];
    final schema = json['schemaVersion'];
    final created = json['createdAt'];
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        sha is! String ||
        !_sha256.hasMatch(sha) ||
        size is! int ||
        size <= 0 ||
        format is! int ||
        schema is! int ||
        created is! String ||
        json['contentType'] != 'application/octet-stream') {
      return null;
    }
    final createdAt = DateTime.tryParse(created);
    if (createdAt == null) return null;
    return RemoteBackupEntry(
      id: id,
      sha256: sha,
      sizeBytes: size,
      formatVersion: format,
      schemaVersion: schema,
      createdAt: createdAt,
    );
  }
}

enum RemoteBackupErrorKind {
  /// Sin red o el servidor no respondió a tiempo: nada se confirmó.
  network,

  /// 401: la sesión venció; hay que verificar el acceso en línea.
  authRequired,

  /// 403: la cuenta o la instalación no tienen acceso a respaldos privados.
  forbidden,

  /// 404: la copia no existe o no es de esta cuenta (indistinguibles).
  notFound,

  /// 409: se alcanzó el número de copias en el servidor.
  quotaExceeded,

  /// 413: el respaldo supera el tamaño admitido.
  tooLarge,

  /// La copia no llegó íntegra (SHA-256 o tamaño distintos, transferencia
  /// cortada, o el servidor detectó que su copia está dañada).
  integrity,

  /// 503 u otra respuesta: el servicio no está disponible.
  unavailable,

  /// Respuesta que no cumple el contrato: no se confía en ella.
  invalidResponse,
}

class RemoteBackupException implements Exception {
  const RemoteBackupException(this.kind, {this.statusCode});

  final RemoteBackupErrorKind kind;
  final int? statusCode;

  /// Mensaje para el usuario, sin identificadores ni detalles técnicos.
  String get message => switch (kind) {
    RemoteBackupErrorKind.network =>
      'No hay conexión con el servidor. No se completó la operación.',
    RemoteBackupErrorKind.authRequired =>
      'La sesión venció. Verifique su acceso en línea y vuelva a intentarlo.',
    RemoteBackupErrorKind.forbidden =>
      'Esta cuenta no tiene acceso a respaldos privados en el servidor.',
    RemoteBackupErrorKind.notFound =>
      'Esa copia no existe o no pertenece a esta cuenta.',
    RemoteBackupErrorKind.quotaExceeded =>
      'Ya tiene el máximo de copias en el servidor. Elimine una antes de '
          'subir otra.',
    RemoteBackupErrorKind.tooLarge =>
      'El respaldo supera el tamaño que admite el servidor.',
    RemoteBackupErrorKind.integrity =>
      'La copia no llegó íntegra (la comprobación SHA-256 falló). No se usó '
          'y sus datos actuales se conservan.',
    RemoteBackupErrorKind.unavailable =>
      'El servicio de respaldos no está disponible ahora.',
    RemoteBackupErrorKind.invalidResponse =>
      'El servidor respondió de forma inesperada. No se dio por confirmada '
          'la operación.',
  };

  @override
  String toString() => message;
}

/// Cliente HTTP en streaming: los archivos no se cargan enteros en memoria.
class RemoteBackupApi {
  RemoteBackupApi({
    required ApiEndpointConfig config,
    required http.Client client,
    this.timeout = const Duration(minutes: 5),
  }) : _config = config,
       _client = client;

  final ApiEndpointConfig _config;
  final http.Client _client;
  final Duration timeout;

  static const _base = '/api/v1/me/backups';

  Future<List<RemoteBackupEntry>> list(String accessToken) async {
    final response = await _send(
      http.Request('GET', _endpoint(_base)),
      accessToken,
    );
    final body = await _jsonOf(response, expected: 200);
    final backups = body is Map<String, dynamic> && body.length == 1
        ? body['backups']
        : null;
    if (backups is! List) {
      throw const RemoteBackupException(RemoteBackupErrorKind.invalidResponse);
    }
    final entries = <RemoteBackupEntry>[];
    for (final item in backups) {
      final entry = RemoteBackupEntry.validate(item);
      if (entry == null) {
        throw const RemoteBackupException(
          RemoteBackupErrorKind.invalidResponse,
        );
      }
      entries.add(entry);
    }
    return entries;
  }

  /// Sube [file] y sólo devuelve la copia si el servidor confirma el mismo
  /// SHA-256 y tamaño que se enviaron.
  Future<RemoteBackupEntry> upload(
    File file, {
    required String sha256,
    required int formatVersion,
    required int schemaVersion,
    required String accessToken,
  }) async {
    final size = await file.length();
    final request = http.StreamedRequest('POST', _endpoint(_base))
      ..contentLength = size
      ..headers.addAll({
        'Content-Type': 'application/octet-stream',
        'X-Content-SHA256': sha256,
        'X-Backup-Format-Version': '$formatVersion',
        'X-Backup-Schema-Version': '$schemaVersion',
      });
    unawaited(
      file.openRead().pipe(request.sink).catchError((Object _) {
        // El envío falla por su lado; la respuesta (o su ausencia) decide.
      }),
    );
    final response = await _send(request, accessToken);
    final entry = RemoteBackupEntry.validate(
      await _jsonOf(response, expected: 201),
    );
    if (entry == null || entry.sha256 != sha256 || entry.sizeBytes != size) {
      throw const RemoteBackupException(RemoteBackupErrorKind.invalidResponse);
    }
    return entry;
  }

  /// Descarga [entry] a `<directory>/<id>.agrobackup`. Se escribe primero un
  /// `.part`, se cotejan el tamaño y el SHA-256 con los metadatos del
  /// servidor y sólo entonces se renombra. Ante cualquier discrepancia o
  /// corte no queda ningún archivo.
  Future<File> download(
    RemoteBackupEntry entry,
    Directory directory,
    String accessToken,
  ) async {
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, '${entry.id}.agrobackup'));
    final partial = File('${target.path}.part');
    try {
      final response = await _send(
        http.Request('GET', _endpoint('$_base/${entry.id}/content')),
        accessToken,
      );
      if (response.statusCode != 200) {
        await _jsonOf(response, expected: 200);
      }
      final declared = response.headers['x-content-sha256'];
      if (declared != entry.sha256 ||
          (response.contentLength != null &&
              response.contentLength != entry.sizeBytes)) {
        await response.stream.drain<void>().catchError((Object _) {});
        throw const RemoteBackupException(RemoteBackupErrorKind.integrity);
      }
      final sink = partial.openWrite();
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(timeout)) {
          received += chunk.length;
          if (received > entry.sizeBytes) {
            throw const RemoteBackupException(RemoteBackupErrorKind.integrity);
          }
          hasher.add(chunk);
          sink.add(chunk);
        }
        hasher.close();
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received != entry.sizeBytes || '${digest.value}' != entry.sha256) {
        throw const RemoteBackupException(RemoteBackupErrorKind.integrity);
      }
      if (await target.exists()) await target.delete();
      return await partial.rename(target.path);
    } on RemoteBackupException {
      await _deleteQuietly(partial);
      rethrow;
    } on Exception {
      await _deleteQuietly(partial);
      // Corte a mitad de la descarga: la copia no llegó completa.
      throw const RemoteBackupException(RemoteBackupErrorKind.integrity);
    }
  }

  /// Elimina una copia remota propia. No toca ningún archivo local.
  Future<void> delete(String id, String accessToken) async {
    final response = await _send(
      http.Request('DELETE', _endpoint('$_base/$id')),
      accessToken,
    );
    if (response.statusCode == 204) {
      await response.stream.drain<void>();
      return;
    }
    await _jsonOf(response, expected: 204);
  }

  Uri _endpoint(String path) {
    try {
      return _config.endpoint(path);
    } on AuthApiException {
      throw const RemoteBackupException(RemoteBackupErrorKind.invalidResponse);
    }
  }

  Future<http.StreamedResponse> _send(
    http.BaseRequest request,
    String accessToken,
  ) async {
    request.followRedirects = false;
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.headers['Accept'] =
        request.method == 'GET' && request.url.path.endsWith('/content')
        ? 'application/octet-stream, application/json'
        : 'application/json';
    try {
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        await response.stream.drain<void>().catchError((Object _) {});
        throw const RemoteBackupException(RemoteBackupErrorKind.unavailable);
      }
      return response;
    } on RemoteBackupException {
      rethrow;
    } on Exception {
      // ClientException, SocketException o timeout: sin respuesta fiable.
      throw const RemoteBackupException(RemoteBackupErrorKind.network);
    }
  }

  /// Cuerpo JSON de una respuesta [expected]; si el estado es otro, el error
  /// tipado que corresponde a su código cerrado.
  Future<Object?> _jsonOf(
    http.StreamedResponse response, {
    required int expected,
  }) async {
    final List<int> bytes;
    try {
      bytes = await response.stream.toBytes().timeout(timeout);
    } on Exception {
      throw const RemoteBackupException(RemoteBackupErrorKind.network);
    }
    Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      body = null;
    }
    if (response.statusCode == expected) return body;
    final code = body is Map<String, dynamic> ? body['errorCode'] : null;
    throw RemoteBackupException(switch ((response.statusCode, code)) {
      (401, _) => RemoteBackupErrorKind.authRequired,
      (403, _) => RemoteBackupErrorKind.forbidden,
      (404, _) => RemoteBackupErrorKind.notFound,
      (409, 'BACKUP_QUOTA_EXCEEDED') => RemoteBackupErrorKind.quotaExceeded,
      (413, _) => RemoteBackupErrorKind.tooLarge,
      (422, 'BACKUP_SHA256_MISMATCH') => RemoteBackupErrorKind.integrity,
      (500, 'BACKUP_INTEGRITY_FAILED') => RemoteBackupErrorKind.integrity,
      (400, 'BACKUP_TRANSFER_INCOMPLETE') => RemoteBackupErrorKind.integrity,
      _ => RemoteBackupErrorKind.unavailable,
    }, statusCode: response.statusCode);
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Limpieza: no cambia el resultado.
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
