import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas estructurales de los borradores de voz (`lib/voice_draft/`).
///
/// La interpretación y los borradores no pueden escribir: no ven la base, no
/// importan repositorios ni llaman a los casos de uso que escriben (ADR-003).
/// La confirmación llega inyectada desde `lib/presentation/voice/`, que es el
/// único puente con el dominio. Tampoco hay red, disco ni registro del texto
/// dictado.
void main() {
  final dir = Directory('lib/voice_draft');

  List<File> files() => dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList(growable: false);

  String code(File file) => file
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
      .replaceAll(RegExp(r'//[^\r\n]*'), '');

  void forbid(List<String> needles, String why) {
    for (final file in files()) {
      final source = code(file);
      for (final needle in needles) {
        expect(
          source.contains(needle),
          isFalse,
          reason: '${file.path} contiene «$needle»: $why',
        );
      }
    }
  }

  test('existe y tiene archivos', () => expect(files(), isNotEmpty));

  test('no ve la base de datos ni los repositorios', () {
    forbid(const [
      'package:sqflite',
      'sqflite_common_ffi',
      'app_database.dart',
      'AppDatabase',
      'agro_repository.dart',
      'AgroRepository',
      'typed_reads.dart',
      'backup_service.dart',
      "/data/",
    ], 'el borrador no puede alcanzar la persistencia');
  });

  test('no llama a ningún caso de uso que escribe', () {
    forbid(const [
      'confirmPurchase',
      'confirmApplication',
      'addPlanMulti',
      'addPlan(',
      'addProduct',
      'addSupplier',
      'addAccountPayment',
      'addProviderPayment',
      'transferStock',
      'reverse',
    ], 'la escritura sólo llega inyectada tras la confirmación');
  });

  test('no escribe SQL', () {
    forbid(const [
      'rawQuery',
      'rawInsert',
      'INSERT INTO',
      'UPDATE ',
      'DELETE FROM',
      'SELECT ',
    ], 'ADR-003: sin SQL desde lenguaje natural');
  });

  test('no usa red, disco ni registro del texto', () {
    forbid(const [
      'dart:io',
      'package:http',
      'HttpClient',
      'https://',
      'path_provider',
      'SharedPreferences',
      'app_log.dart',
      'AppLog',
      'print(',
      'debugPrint(',
    ], 'el texto dictado no sale de la memoria');
  });

  test('nada fuera de presentación importa los borradores de voz', () {
    for (final base in const ['lib/domain', 'lib/data', 'lib/services']) {
      for (final file
          in Directory(base)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync().contains('voice_draft/'),
          isFalse,
          reason: '${file.path} depende de la voz',
        );
      }
    }
  });

  test('la captura (lib/voice/) sigue sin conocer los borradores', () {
    for (final file
        in Directory('lib/voice')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      expect(
        file.readAsStringSync().contains('voice_draft'),
        isFalse,
        reason: file.path,
      );
    }
  });
}
