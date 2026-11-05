// Aplica la regla de selección REAL de la app (`chooseReviewedText`) a los
// pares Vosk/Whisper que produjo el motor en el emulador, para saber qué texto
// habría llegado a la sesión. Herramienta de evidencia, no prueba de CI:
//
//   AGRO_REF_RESULTS=<ref-results.jsonl> AGRO_REF_OUT=<salida.json> \
//     flutter test tool/voice_local/selection_on_results_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = Platform.environment['AGRO_REF_RESULTS'];
  final output = Platform.environment['AGRO_REF_OUT'];
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
        );
        texts.add(choice.text);
        verdicts.add(choice.verdict.name);
      }
      out[file] = {'text': texts.join(' '), 'verdicts': verdicts};
    }
    File(output).writeAsStringSync(jsonEncode(out));
  });
}
