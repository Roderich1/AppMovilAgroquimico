// Gate de compatibilidad con páginas de 16 KB para APK y AAR.
//
// HERRAMIENTA DE SPIKE. No la usa la aplicación Agrocuentas ni su CI.
//
//   dart run tool/check_native_alignment.dart build/app/outputs/flutter-apk/*.apk
//   dart run tool/check_native_alignment.dart --json informe.json <apk...>
//
// Sale con código 1 si CUALQUIER librería nativa queda por debajo de 16384, que
// es lo que exige el gate: no basta con revisar `libvosk.so`.
//
// Comprueba SÓLO el ELF. Faltan, y no las sustituye:
//   * `zipalign -c -P 16 -v 4 <apk>` — alineamiento dentro del ZIP;
//   * arrancar en un aparato con `getconf PAGE_SIZE` = 16384 — ejecución real.

import 'dart:convert';
import 'dart:io';

import 'package:voice_benchmark/bench/native_alignment.dart';

Future<void> main(List<String> args) async {
  final paths = <String>[];
  String? jsonOut;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--json') {
      if (i + 1 >= args.length) {
        stderr.writeln('--json necesita una ruta de salida');
        exit(2);
      }
      jsonOut = args[++i];
      continue;
    }
    paths.add(args[i]);
  }

  if (paths.isEmpty) {
    stderr.writeln(
      'uso: dart run tool/check_native_alignment.dart [--json salida.json] '
      '<apk-o-aar> [...]',
    );
    exit(2);
  }

  final reports = <NativeAlignmentReport>[];
  var failed = false;

  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('no existe: $path');
      failed = true;
      continue;
    }
    final report = inspectArchive(file);
    reports.add(report);
    stdout.writeln(report.render());
    if (!report.passes) failed = true;
  }

  if (jsonOut != null) {
    File(jsonOut).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert([
        for (final report in reports) report.toJson(),
      ]),
    );
    stdout.writeln('informe JSON: $jsonOut');
  }

  if (failed) {
    stderr.writeln(
      'GATE 16 KB: FALLA. No construyas evidencia sobre un APK que no cargaría '
      'en un aparato con páginas de 16 KB.',
    );
    exit(1);
  }
  stdout.writeln('GATE 16 KB (ELF): pasa.');
}
