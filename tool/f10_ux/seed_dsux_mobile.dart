// DS-UX Mobile: siembra el estado inicial de una sesión de usabilidad F10.
//
// HERRAMIENTA DE EVALUACIÓN (ver `dsux_fixture.dart` y `README.md`). No forma
// parte de la suite: `flutter test` sin argumentos sólo recorre `test/`. Se
// ejecuta sobre la base EXTRAÍDA de la copia `.f10ux` recién reinstalada y
// activada por el facilitador, con la app detenida:
//
//     F10_UX_DB=/ruta/absoluta/agroquimicos_v2.db \
//     F10_UX_SESSION_DATE=aaaa-mm-dd \
//     F10_UX_MODALIDAD=PROPIA|COMPARTIDA \
//     F10_UX_REFERENCES=/ruta/absoluta/references.json \
//       flutter test tool/f10_ux/seed_dsux_mobile.dart
//
// `F10_UX_REFERENCES` es el cuerpo literal de `GET /api/v1/sync/v1/references`
// del tenant de la cuenta sintética de la sesión; se valida con el mismo
// `CentralReferences.fromJson` que usa la app. El día de sesión es un día civil
// de America/La_Paz: el PC debe estar en esa zona (UTC−4), como el teléfono, o
// la siembra se niega. Al terminar imprime `DSUX_RESULT {...}`.

import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dsux_fixture.dart';

void main() {
  sqfliteFfiInit();

  test('siembra DS-UX en la base indicada por F10_UX_DB', () async {
    final env = Platform.environment;
    final path = env['F10_UX_DB'];
    expect(path, isNotNull, reason: 'Defina F10_UX_DB');
    expect(p.isAbsolute(path!), isTrue, reason: 'F10_UX_DB debe ser absoluta');
    expect(File(path).existsSync(), isTrue, reason: 'no existe $path');
    final referencesPath = env['F10_UX_REFERENCES'];
    expect(referencesPath, isNotNull, reason: 'Defina F10_UX_REFERENCES');
    expect(
      File(referencesPath!).existsSync(),
      isTrue,
      reason: 'no existe $referencesPath',
    );

    final sessionDay = parseSessionDay(env['F10_UX_SESSION_DATE']);
    final modality = DsuxModality.parse(env['F10_UX_MODALIDAD']);
    final parts = sessionDay.split('-').map(int.parse).toList();
    for (final offset in [
      campaignStartOffsetDays,
      0,
      campaignPlannedEndOffsetDays,
    ]) {
      final instant = DateTime(parts[0], parts[1], parts[2] + offset, 12);
      expect(
        instant.timeZoneOffset,
        const Duration(hours: -4),
        reason:
            'El PC no está en America/La_Paz (UTC−4) el $instant: los días '
            'civiles de la campaña no coincidirían con los del teléfono.',
      );
    }
    final references = CentralReferences.fromJson(
      jsonDecode(File(referencesPath).readAsStringSync())
          as Map<String, dynamic>,
    );

    final database = AppDatabase(factory: databaseFactoryFfi, path: path);
    final result = await seedDsux(
      database: database,
      sessionDay: sessionDay,
      modality: modality,
      references: references,
    );
    expect(result['integrity_check'], 'ok');
    expect(result['sync_outbox_after'], result['sync_outbox_before']);
    expect(
      result['sync_outbox_max_rowid_after'],
      result['sync_outbox_max_rowid_before'],
    );
    await database.close();
    result['db_bytes'] = File(path).lengthSync();
    result['wal_left'] = File('$path-wal').existsSync();
    expect(result['wal_left'], isFalse);
    // ignore: avoid_print
    print('DSUX_RESULT ${jsonEncode(result)}');
  });
}
