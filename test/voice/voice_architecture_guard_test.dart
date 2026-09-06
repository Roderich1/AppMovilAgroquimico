import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas estructurales del subsistema de voz (`EVO-009`).
///
/// `ADR-003` y la política de EVOLUTION-3 no se sostienen con una promesa en un
/// comentario: si mañana alguien importa `AgroRepository` desde la pantalla de
/// voz para «rellenar el producto», nada se lo impediría y la revisión podría no
/// verlo. Estas pruebas leen los archivos y fallan.
///
/// No comprueban que el código sea correcto: comprueban que **no puede** hacer
/// determinadas cosas. Es la diferencia entre confiar y verificar.
void main() {
  final voiceDir = Directory('lib/voice');

  List<File> voiceFiles() => voiceDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList(growable: false);

  /// El archivo tal cual, comentarios incluidos.
  ///
  /// Lo usan las guardas donde el comentario también cuenta: una URL o un
  /// `import` no dejan de existir por estar comentados.
  String raw(File file) => file.readAsStringSync();

  /// El **código** del archivo, sin comentarios.
  ///
  /// Los comentarios de este subsistema explican precisamente qué NO puede
  /// hacer —«no importa `AgroRepository`», «Whisper queda como reserva»—, así
  /// que buscar sobre el texto crudo haría fallar la guarda por documentar bien.
  /// Lo que debe estar prohibido es la referencia real, no la palabra.
  String read(File file) =>
      raw(file)
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
          .replaceAll(RegExp(r'//[^\r\n]*'), '');

  /// Sólo el diagnóstico del proyecto está permitido desde `data/`.
  ///
  /// `AppLog` no es dominio: redacta por contrato y es donde vive la mitigación
  /// de `RISK-014`. Cualquier otro archivo de `data/` es base de datos o
  /// repositorio, y por eso la excepción se declara aquí, una sola vez.
  const allowedDataImport = '../../data/app_log.dart';

  test('el subsistema de voz existe y tiene archivos', () {
    expect(voiceDir.existsSync(), isTrue);
    expect(voiceFiles(), isNotEmpty);
  });

  group('no puede alcanzar la base de datos ni los repositorios', () {
    test('ningún archivo de voz importa SQLite', () {
      for (final file in voiceFiles()) {
        final source = read(file);
        for (final forbidden in const [
          'package:sqflite',
          'sqflite_common_ffi',
          'app_database.dart',
          'AppDatabase',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '${file.path} menciona $forbidden',
          );
        }
      }
    });

    test('ningún archivo de voz importa repositorios de escritura', () {
      for (final file in voiceFiles()) {
        final source = read(file);
        for (final forbidden in const [
          'agro_repository.dart',
          'AgroRepository',
          'backup_service.dart',
          'BackupService',
          'invoice_storage.dart',
          'typed_reads.dart',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '${file.path} menciona $forbidden',
          );
        }
      }
    });

    test('sólo se importa de data/ el registro de diagnóstico', () {
      final pattern = RegExp("import\\s+'([^']*data/[^']*)'");
      for (final file in voiceFiles()) {
        for (final match in pattern.allMatches(read(file))) {
          expect(
            match.group(1),
            allowedDataImport,
            reason: '${file.path} importa ${match.group(1)}',
          );
        }
      }
    });
  });

  group('no puede ejecutar ninguna operación de negocio', () {
    test('no llama a los casos de uso que escriben', () {
      for (final file in voiceFiles()) {
        final source = read(file);
        for (final forbidden in const [
          'confirmPurchase',
          'confirmApplication',
          'addAccountPayment',
          'registerTransfer',
          'reversePurchase',
          'closeCampaign',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '${file.path} llama a $forbidden',
          );
        }
      }
    });

    test('no nombra compras, aplicaciones, pagos, FIFO ni backup', () {
      for (final file in voiceFiles()) {
        final source = read(file).toLowerCase();
        // Se busca el identificador, no la palabra en prosa: los comentarios
        // explican precisamente que la voz NO hace estas cosas, y prohibirlos
        // ahí obligaría a documentar peor.
        for (final forbidden in const [
          'purchase',
          'application(',
          'payment',
          'fifo(',
          'backup(',
          'inventory',
          'supplier',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '${file.path} menciona el identificador $forbidden',
          );
        }
      }
    });

    test('no escribe SQL', () {
      for (final file in voiceFiles()) {
        final source = read(file);
        for (final forbidden in const [
          'rawQuery',
          'rawInsert',
          'rawUpdate',
          'rawDelete',
          'INSERT INTO',
          'UPDATE ',
          'DELETE FROM',
          'SELECT ',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '${file.path} contiene $forbidden',
          );
        }
      }
    });
  });

  group('el puerto se mantiene reemplazable', () {
    test('el contrato no depende de Flutter', () {
      final source = read(
        File('lib/voice/port/speech_transcription_port.dart'),
      );
      expect(source.contains('package:flutter/'), isFalse);
    });

    test('la sesión no depende de la interfaz', () {
      for (final name in const [
        'lib/voice/session/voice_session_controller.dart',
        'lib/voice/session/voice_session_state.dart',
        'lib/voice/session/voice_locale_policy.dart',
        'lib/voice/session/voice_continuity_policy.dart',
      ]) {
        final source = read(File(name));
        expect(
          source.contains('package:flutter/material.dart'),
          isFalse,
          reason: '$name importa la interfaz',
        );
        expect(
          source.contains('package:flutter/widgets.dart'),
          isFalse,
          reason: '$name importa la interfaz',
        );
      }
    });

    test('sólo el adaptador de Android conoce los canales de plataforma', () {
      for (final file in voiceFiles()) {
        if (file.path.endsWith('android_speech_transcription_adapter.dart')) {
          continue;
        }
        expect(
          read(file).contains('MethodChannel'),
          isFalse,
          reason:
              '${file.path} habla con la plataforma sin pasar por el puerto',
        );
      }
    });

    test(
      'nada del subsistema de voz se importa desde el dominio o los datos',
      () {
        final leaked = <String>[];
        for (final dir in const ['lib/domain', 'lib/data', 'lib/services']) {
          for (final file
              in Directory(dir)
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.dart'))) {
            if (read(file).contains('voice/')) leaked.add(file.path);
          }
        }
        expect(
          leaked,
          isEmpty,
          reason: 'la voz no puede ser dependencia de nadie',
        );
      },
    );
  });

  group('privacidad verificable', () {
    test('no se persiste audio ni transcripción', () {
      for (final file in voiceFiles()) {
        final source = raw(file);
        for (final forbidden in const [
          'dart:io',
          'path_provider',
          'File(',
          'writeAsString',
          'writeAsBytes',
          'SharedPreferences',
          'getTemporaryDirectory',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '${file.path} podría escribir en disco: $forbidden',
          );
        }
      }
    });

    test('no hay red en el subsistema de voz', () {
      for (final file in voiceFiles()) {
        final source = raw(file);
        for (final forbidden in const [
          'package:http',
          'HttpClient',
          'dart:html',
          'WebSocket',
          'https://',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '${file.path} contiene $forbidden',
          );
        }
      }
    });
  });

  group('permisos declarados', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');

    test('se declara RECORD_AUDIO y ningún otro permiso nuevo', () {
      final source = manifest.readAsStringSync();
      final permissions = RegExp(r'uses-permission android:name="([^"]+)"')
          .allMatches(source)
          .map((m) => m.group(1))
          .toList();
      expect(permissions, ['android.permission.RECORD_AUDIO']);
    });

    test('NO se declara INTERNET', () {
      final source = manifest.readAsStringSync();
      expect(source.contains('android.permission.INTERNET'), isFalse);
      expect(source.contains('ACCESS_NETWORK_STATE'), isFalse);
    });
  });

  group('el motor productivo es el que decidió ADR-002', () {
    test('no se empaqueta Whisper ni ningún modelo', () {
      for (final file in voiceFiles()) {
        final source = read(file).toLowerCase();
        expect(source.contains('whisper'), isFalse, reason: file.path);
        expect(source.contains('.bin'), isFalse, reason: file.path);
      }
    });

    test('el banco de pruebas sigue fuera de la aplicación', () {
      for (final file in voiceFiles()) {
        expect(
          read(file).contains('voice_benchmark'),
          isFalse,
          reason: '${file.path} depende del banco, que es descartable',
        );
      }
    });

    test('no se añadió ninguna dependencia para la voz', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final forbidden in const [
        'speech_to_text',
        'permission_handler',
        'record:',
        'whisper',
      ]) {
        expect(
          pubspec.contains(forbidden),
          isFalse,
          reason: 'pubspec.yaml declara $forbidden',
        );
      }
    });
  });
}
