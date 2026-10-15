import 'dart:async';

/// Se lanza cuando una escritura llega mientras se sustituye la base.
class DatabaseReplacementInProgressException implements Exception {
  const DatabaseReplacementInProgressException();

  String get message =>
      'Se está restaurando un respaldo. Espere a que termine y vuelva a '
      'intentarlo.';

  @override
  String toString() => message;
}

/// Exclusión entre las escrituras locales y la sustitución completa de la
/// base (restaurar un respaldo).
///
/// - Mientras se sustituye la base no entra ninguna escritura nueva: falla de
///   inmediato con [DatabaseReplacementInProgressException].
/// - Las escrituras que ya estaban en curso terminan antes de que empiece la
///   sustitución, así que no escriben en la base nueva con la autorización de
///   la anterior ni faltan en la copia de seguridad previa.
/// - Las lecturas que lleguen esperan a que termine, para no reabrir el
///   archivo a medio copiar.
/// - Lo que se ejecuta dentro de la sustitución (la restauración, la
///   comprobación de propiedad y el recálculo de la autorización) pasa.
///
/// Dart ejecuta un solo hilo: entre la comprobación de [write] y el cuerpo de
/// la escritura no hay espera, de modo que una sustitución no puede colarse
/// entre la autorización que comprueba el cuerpo y su transacción.
class DatabaseReplacementGuard {
  final Object _replacementKey = Object();
  final Object _writeKey = Object();
  Object? _token;
  Completer<void>? _finished;
  int _activeWrites = 0;
  Completer<void>? _drained;

  bool get isReplacing => _token != null;

  bool get _insideReplacement =>
      _token != null && identical(Zone.current[_replacementKey], _token);

  bool get _insideWrite => Zone.current[_writeKey] == true;

  /// Ejecuta [body] como escritura. Se rechaza si hay una sustitución en
  /// curso, salvo que la escritura forme parte de ella.
  Future<T> write<T>(Future<T> Function() body) {
    if (_token != null && !_insideReplacement) {
      return Future<T>.error(const DatabaseReplacementInProgressException());
    }
    _activeWrites++;
    return runZoned(() async {
      try {
        return await body();
      } finally {
        _activeWrites--;
        if (_activeWrites == 0) {
          _drained?.complete();
          _drained = null;
        }
      }
    }, zoneValues: {_writeKey: true});
  }

  /// Ejecuta [body] en exclusiva: espera a que terminen las escrituras en
  /// curso y rechaza las nuevas hasta que [body] termine, bien o mal. Dentro
  /// de una sustitución, [body] se ejecuta en ella.
  Future<T> replace<T>(Future<T> Function() body) async {
    if (_insideReplacement) return body();
    if (_insideWrite) {
      throw StateError('No se puede sustituir la base desde una escritura.');
    }
    if (_token != null) throw const DatabaseReplacementInProgressException();
    final token = Object();
    final finished = Completer<void>();
    _token = token;
    _finished = finished;
    try {
      if (_activeWrites > 0) {
        await (_drained ??= Completer<void>()).future;
      }
      return await runZoned(body, zoneValues: {_replacementKey: token});
    } finally {
      _token = null;
      _finished = null;
      finished.complete();
    }
  }

  /// Las lecturas esperan a que termine una sustitución en curso. Las
  /// escrituras ya admitidas y la propia sustitución no esperan.
  Future<void> whenReadable() async {
    while (_token != null && !_insideReplacement && !_insideWrite) {
      await _finished!.future;
    }
  }
}
