// DS-UX Mobile: lectura de lo que la sesión guardó de verdad (oráculo de T3
// y de T4 tras la sesión, para auditar la hoja del facilitador).
//
// HERRAMIENTA DE EVALUACIÓN (ver `dsux_fixture.dart` y `README.md`). Sólo
// lectura: copia la base (y su `-wal`) a un directorio temporal y lee la copia;
// el archivo indicado no se abre ni se modifica. No corrige nada: si el saldo
// guardado difiere del nominal, eso es lo que el participante guardó.
//
//     F10_UX_DB=/ruta/absoluta/agroquimicos_v2.db \
//       flutter test tool/f10_ux/oracle_dsux_mobile.dart
//
// Imprime `DSUX_ORACLE {...}`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dsux_fixture.dart';

void main() {
  sqfliteFfiInit();

  test('lee el estado DS-UX guardado en F10_UX_DB', () async {
    final path = Platform.environment['F10_UX_DB'];
    expect(path, isNotNull, reason: 'Defina F10_UX_DB');
    expect(p.isAbsolute(path!), isTrue, reason: 'F10_UX_DB debe ser absoluta');
    expect(File(path).existsSync(), isTrue, reason: 'no existe $path');
    final before = File(path).lastModifiedSync();
    final oracle = await dsuxOracleFromFile(path);
    expect(
      File(path).lastModifiedSync(),
      before,
      reason: 'no se toca el original',
    );
    // ignore: avoid_print
    print('DSUX_ORACLE ${jsonEncode(oracle)}');
  });
}
