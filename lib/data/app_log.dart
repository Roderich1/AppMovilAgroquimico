import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warning, error }

/// Registro local de diagnóstico.
///
/// Existe porque la aplicación no tenía ninguna forma de averiguar qué falló:
/// ante un "me dio error al guardar" no quedaba ni un rastro que consultar.
///
/// Deliberadamente **local**: no envía nada a ningún servidor. La aplicación no
/// declara el permiso de INTERNET y esa postura no se cambia por añadir
/// diagnóstico.
///
/// ## Qué NO se debe registrar
///
/// Nunca nombres de personas, importes, cantidades, teléfonos ni rutas de
/// fotografías. El log describe *qué operación* falló y *con qué error*, no los
/// datos del negocio. Ver docs/23_SECURITY_AUDIT.md.
class AppLog {
  AppLog._();

  static const _fileName = 'agrocuentas.log';
  static const _rotatedFileName = 'agrocuentas.log.1';
  static const _maxBytes = 512 * 1024;

  static File? _file;
  static bool _initialized = false;

  /// En release solo se persisten avisos y errores: el ruido de depuración no
  /// aporta y hace crecer el archivo sin motivo.
  static LogLevel get minimumLevel =>
      kReleaseMode ? LogLevel.warning : LogLevel.debug;

  /// Prepara el archivo de log e instala los manejadores globales de error.
  ///
  /// Es tolerante a fallos: si el almacenamiento no está disponible, la
  /// aplicación arranca igualmente y el log queda deshabilitado.
  static Future<void> init({Directory? directory}) async {
    try {
      final target = directory ?? await getApplicationDocumentsDirectory();
      await target.create(recursive: true);
      _file = File(p.join(target.path, _fileName));
      _initialized = true;
    } on Object {
      _file = null;
      _initialized = false;
    }

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      error(
        'Error no controlado en el árbol de widgets',
        error: details.exception,
        stackTrace: details.stack,
      );
    };
    PlatformDispatcher.instance.onError = (errorObject, stackTrace) {
      error(
        'Error no controlado fuera del árbol de widgets',
        error: errorObject,
        stackTrace: stackTrace,
      );
      return true;
    };
  }

  /// Solo para tests: reinicia el estado global entre casos.
  @visibleForTesting
  static void resetForTesting() {
    _file = null;
    _initialized = false;
  }

  @visibleForTesting
  static File? get currentFile => _file;

  static void debug(String message) => _write(LogLevel.debug, message);
  static void info(String message) => _write(LogLevel.info, message);
  static void warning(String message) => _write(LogLevel.warning, message);

  static void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _write(LogLevel.error, message, error: error, stackTrace: stackTrace);

  static void _write(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) return;

    final buffer = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' [${level.name.toUpperCase()}] ')
      ..write(message);
    if (error != null) buffer.write(' | error: $error');
    if (stackTrace != null) {
      // Unas pocas líneas bastan para ubicar el origen sin inflar el archivo.
      final frames = stackTrace.toString().split('\n').take(8).join(' <- ');
      buffer.write(' | stack: $frames');
    }
    final line = buffer.toString();

    if (!kReleaseMode) debugPrint(line);
    if (!_initialized) return;

    try {
      final file = _file!;
      if (file.existsSync() && file.lengthSync() > _maxBytes) {
        final rotated = File(p.join(file.parent.path, _rotatedFileName));
        if (rotated.existsSync()) rotated.deleteSync();
        file.renameSync(rotated.path);
      }
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
    } on Object {
      // El diagnóstico jamás debe tumbar la aplicación.
    }
  }

  /// Contenido del log, del más reciente al más antiguo, para exportarlo o
  /// mostrarlo cuando el usuario reporta un problema.
  static Future<String> readAll() async {
    final file = _file;
    if (file == null || !await file.exists()) return '';
    return file.readAsString();
  }
}
