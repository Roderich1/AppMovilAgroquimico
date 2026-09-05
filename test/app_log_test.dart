import 'dart:io';

import 'package:agroquimicos/data/app_log.dart';
import 'package:flutter_test/flutter_test.dart';

/// STAB-009: sin registro local no había forma de diagnosticar un fallo
/// reportado por el usuario.
void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_log_');
    AppLog.resetForTesting();
    await AppLog.init(directory: workspace);
  });

  tearDown(() async {
    AppLog.resetForTesting();
    await workspace.delete(recursive: true);
  });

  test('registra el mensaje, el nivel y el error', () async {
    AppLog.error('Fallo al confirmar compra', error: StateError('sin campaña'));

    final content = await AppLog.readAll();
    expect(content, contains('[ERROR]'));
    expect(content, contains('Fallo al confirmar compra'));
    expect(content, contains('sin campaña'));
  });

  test('cada entrada lleva marca de tiempo ISO-8601', () async {
    AppLog.warning('Aviso');
    final line = (await AppLog.readAll()).trim();
    // Formato: 2026-09-05T10:11:12.345 [WARNING] Aviso
    expect(
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}').hasMatch(line),
      isTrue,
      reason:
          'Sin marca de tiempo el log no sirve para diagnosticar. '
          'Línea: $line',
    );
  });

  test('acumula varias entradas en orden', () async {
    AppLog.info('primera');
    AppLog.info('segunda');
    final lines = (await AppLog.readAll()).trim().split('\n');
    expect(lines, hasLength(2));
    expect(lines.first, contains('primera'));
    expect(lines.last, contains('segunda'));
  });

  test('incluye una traza acotada, no la pila completa', () async {
    AppLog.error(
      'Con traza',
      error: Exception('x'),
      stackTrace: StackTrace.current,
    );
    final content = await AppLog.readAll();
    expect(content, contains('stack:'));
    // La entrada se mantiene en una sola línea para poder leer el archivo.
    expect(content.trim().split('\n'), hasLength(1));
  });

  test('sin inicializar no lanza ni escribe', () async {
    AppLog.resetForTesting();
    // No debe lanzar aunque no haya archivo configurado.
    AppLog.error('sin destino', error: Exception('y'));
    expect(await AppLog.readAll(), isEmpty);
  });

  test('un fallo de escritura no propaga la excepción', () async {
    // Se elimina el directorio bajo los pies del logger.
    await workspace.delete(recursive: true);
    expect(() => AppLog.error('tras borrar el directorio'), returnsNormally);
    // Se recrea para que el tearDown no falle.
    await workspace.create(recursive: true);
  });
}
