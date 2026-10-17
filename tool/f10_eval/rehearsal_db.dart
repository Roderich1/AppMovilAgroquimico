// Ensayo de herramienta (fuera de toda serie de medición): crea en el host una
// base vacía con un titular sintético en modalidad propia, para comprobar
// `seed_dsv_mobile.dart` antes de usarlo sobre la base del dispositivo.
//
//     F10_DSV_DB=/ruta/absoluta/ensayo.db flutter test tool/f10_eval/rehearsal_db.dart
//
// No escribe en el dispositivo ni en ningún entorno del servidor.

import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('crea la base de ensayo', () async {
    final path = Platform.environment['F10_DSV_DB']!;
    expect(p.isAbsolute(path), isTrue);
    expect(File(path).existsSync(), isFalse, reason: 'no se sobrescribe');
    final database = AppDatabase(factory: databaseFactoryFfi, path: path);
    await OwnerBindingStore(database).bindNewPerson(
      name: 'Titular de ensayo',
      scope: const OwnerScope(memberId: '00000000-0000-4000-8000-0000000000a1', tenantId: '00000000-0000-4000-8000-0000000000b1'),
      installationRef: 'ensayo-installation',
    );
    final db = await database.database;
    await db.insert('app_settings', {
      'key': AppDatabase.operationModeKey,
      'value': 'PERSONAL',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await database.close();
  });
}
