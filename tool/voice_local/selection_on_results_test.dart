// Aplica la regla de selección REAL de la app (`chooseReviewedText`) a los
// pares Vosk/Whisper que produjo el motor en el emulador, para saber qué texto
// habría llegado a la sesión. Herramienta de evidencia, no prueba de CI:
//
//   AGRO_REF_RESULTS=<ref-results.jsonl> AGRO_REF_OUT=<salida.json> \
//     flutter test tool/voice_local/selection_on_results_test.dart
//
// Modo HOST (#166): aplica la misma regla a cada configuración de Whisper de
// `host_compare.py` (frase a frase, como el motor) y deja lo elegido para
// `host_compare.py --score-selection`.
//
//   AGRO_HOST_COMPARE=<host_compare.json> AGRO_REF_OUT=<seleccion.json> \
//     flutter test tool/voice_local/selection_on_results_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = Platform.environment['AGRO_REF_RESULTS'];
  final output = Platform.environment['AGRO_REF_OUT'];
  final host = Platform.environment['AGRO_HOST_COMPARE'];
  test('selección sobre resultados HOST', () {
    if (host == null || output == null) return;
    final data = jsonDecode(File(host).readAsStringSync()) as Map;
    final rows = (data['rows'] as List).cast<Map<String, Object?>>();
    final out = <String, Map<String, Object?>>{};
    for (final config in const ['base_hint', 'small_hint']) {
      final picks = <String, Object?>{};
      for (final row in rows) {
        final vosk = (row['vosk_segs'] as List).cast<String>();
        final review = (row['${config}_segs'] as List).cast<String>();
        final texts = <String>[];
        final verdicts = <String>[];
        for (var i = 0; i < vosk.length; i++) {
          final choice = chooseReviewedText(
            vosk[i],
            review[i],
            facts: voiceQuantityFacts,
          );
          texts.add(choice.text);
          verdicts.add(choice.verdict.name);
        }
        picks[row['file'] as String] = {
          'text': texts.join(' '),
          'verdicts': verdicts,
        };
      }
      out['app_$config'] = picks;
    }
    File(output).writeAsStringSync(jsonEncode(out));
  });
  test('selección sobre resultados del emulador', () {
    if (input == null || output == null) return;
    final out = <String, Object?>{};
    for (final line in File(input).readAsLinesSync()) {
      final row = jsonDecode(line) as Map<String, Object?>;
      final file = row['file'] as String;
      if (file.contains(':') || file == 'dos-turnos') continue;
      final texts = <String>[];
      final verdicts = <String>[];
      for (final e in (row['events'] as List).cast<Map<String, Object?>>()) {
        if (e['type'] != 'segment') continue;
        final choice = chooseReviewedText(
          e['vosk'] as String,
          e['review'] as String?,
          facts: voiceQuantityFacts,
        );
        texts.add(choice.text);
        verdicts.add(choice.verdict.name);
      }
      out[file] = {'text': texts.join(' '), 'verdicts': verdicts};
    }
    File(output).writeAsStringSync(jsonEncode(out));
  });
}
