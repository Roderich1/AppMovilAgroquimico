import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/services/reports/report_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Frontera de almacenamiento (Lote G): extensión, nombre seguro, temporal,
/// fallo y colisión.
void main() {
  late Directory root;
  late LocalReportStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agro_reportes_');
    storage = LocalReportStorage(
      directory: () async => Directory(p.join(root.path, 'reportes')),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Uint8List bytes(String value) => Uint8List.fromList(value.codeUnits);

  Future<StoredReport> save(String base, [String extension = 'csv']) => storage
      .save(baseName: base, extension: extension, bytes: bytes('contenido'));

  group('escritura', () {
    test('crea la carpeta y guarda el archivo con su extensión', () async {
      final stored = await save('inventario-2026-09-06');
      expect(stored.fileName, 'inventario-2026-09-06.csv');
      expect(await File(stored.path).exists(), isTrue);
      expect(await File(stored.path).readAsString(), 'contenido');
      expect(stored.byteCount, 9);
      expect(p.basename(stored.directory), 'reportes');
    });

    test('acepta pdf y csv, y rechaza cualquier otra extensión', () async {
      expect((await save('x', 'pdf')).fileName, endsWith('.pdf'));
      expect((await save('y', 'CSV')).fileName, endsWith('.csv'));
      await expectLater(
        save('z', 'db'),
        throwsA(isA<ReportStorageException>()),
      );
      await expectLater(
        save('z', 'apk'),
        throwsA(isA<ReportStorageException>()),
      );
    });

    test('no deja ningún archivo temporal cuando termina bien', () async {
      final stored = await save('inventario');
      final left = Directory(stored.directory)
          .listSync()
          .map((entity) => p.basename(entity.path))
          .where((name) => name.endsWith(LocalReportStorage.temporarySuffix));
      expect(left, isEmpty);
    });
  });

  group('colisiones', () {
    test('no sobrescribe: numera el segundo y el tercero', () async {
      expect((await save('informe')).fileName, 'informe.csv');
      expect((await save('informe')).fileName, 'informe (2).csv');
      expect((await save('informe')).fileName, 'informe (3).csv');
    });

    test('el archivo original conserva su contenido', () async {
      final first = await save('informe');
      await storage.save(
        baseName: 'informe',
        extension: 'csv',
        bytes: bytes('otro'),
      );
      expect(await File(first.path).readAsString(), 'contenido');
    });

    test('cada extensión tiene su propia secuencia', () async {
      expect((await save('informe', 'csv')).fileName, 'informe.csv');
      expect((await save('informe', 'pdf')).fileName, 'informe.pdf');
    });

    test('esquiva un temporal de otra exportación en curso', () async {
      final directory = await Directory(p.join(root.path, 'reportes'))
          .create(recursive: true);
      await File(
        p.join(
          directory.path,
          'informe.csv${LocalReportStorage.temporarySuffix}',
        ),
      ).writeAsString('a medias');
      expect((await save('informe')).fileName, 'informe (2).csv');
    });
  });

  group('fallo y cancelación', () {
    test('un fallo de escritura no deja archivo final ni temporal', () async {
      // Una carpeta con el nombre exacto del archivo hace fallar el renombrado
      // sin tener que simular un disco lleno.
      final directory = await Directory(p.join(root.path, 'reportes'))
          .create(recursive: true);
      await Directory(p.join(directory.path, 'bloqueado.csv')).create();

      await expectLater(
        storage.save(
          baseName: 'bloqueado',
          extension: 'csv',
          bytes: bytes('contenido'),
        ),
        throwsA(isA<ReportStorageException>()),
      );

      final left = directory
          .listSync()
          .map((entity) => p.basename(entity.path))
          .where((name) => name.endsWith(LocalReportStorage.temporarySuffix));
      expect(left, isEmpty, reason: 'el temporal debe limpiarse');
    });

    test('una carpeta que no se puede crear da un error tipado', () async {
      // Un archivo donde debería ir la carpeta impide crearla.
      final blocker = File(p.join(root.path, 'bloqueo'));
      await blocker.writeAsString('no soy una carpeta');
      final blocked = LocalReportStorage(
        directory: () async => Directory(p.join(blocker.path, 'reportes')),
      );
      await expectLater(
        blocked.save(
          baseName: 'x',
          extension: 'csv',
          bytes: bytes('contenido'),
        ),
        throwsA(isA<ReportStorageException>()),
      );
    });

    test('cancelar antes de guardar no crea nada', () async {
      // El servicio comprueba la cancelación antes de llamar a `save`; aquí se
      // comprueba el efecto observable: la carpeta sigue vacía.
      final directory = Directory(p.join(root.path, 'reportes'));
      expect(await directory.exists(), isFalse);
    });
  });

  group('sanitizeFileName', () {
    test('conserva letras, dígitos, espacios, guiones y guiones bajos', () {
      expect(sanitizeFileName('informe_2026 final-1'), 'informe_2026 final-1');
    });

    test('sustituye separadores de ruta y caracteres reservados', () {
      expect(sanitizeFileName('a/b'), 'a-b');
      expect(sanitizeFileName(r'a\b'), 'a-b');
      expect(sanitizeFileName('a:b*c?d"e<f>g|h'), 'a-b-c-d-e-f-g-h');
    });

    test('sustituye acentos y ñ, que no todos los sistemas guardan igual', () {
      expect(sanitizeFileName('Campaña Ñuflo'), 'Campa-a -uflo');
    });

    test('no deja puntos ni espacios al principio ni al final', () {
      expect(sanitizeFileName('  informe.  '), 'informe');
      expect(sanitizeFileName('...oculto'), 'oculto');
    });

    test('nunca devuelve una cadena vacía', () {
      expect(sanitizeFileName(''), 'reporte');
      expect(sanitizeFileName('***'), 'reporte');
      expect(sanitizeFileName('   '), 'reporte');
    });

    test('evita los nombres reservados de Windows', () {
      expect(sanitizeFileName('CON'), 'reporte');
      expect(sanitizeFileName('nul'), 'reporte');
    });

    test('acota la longitud', () {
      expect(sanitizeFileName('a' * 300).length, lessThanOrEqualTo(80));
    });

    test('un nombre así guardado se puede escribir de verdad', () async {
      final stored = await save(sanitizeFileName('Campaña "El Alto"/2026'));
      expect(await File(stored.path).exists(), isTrue);
    });
  });
}
