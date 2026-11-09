import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'port/android_speech_transcription_adapter.dart';
import 'port/local_speech_transcription_adapter.dart';
import 'port/review_selection.dart';
import 'port/speech_transcription_port.dart';

/// Cómo se construye el puerto de transcripción.
///
/// Es una **fábrica** y no una instancia compartida a propósito: cada visita a
/// la pantalla de voz crea su propio puerto y lo libera al salir. Con una
/// instancia de aplicación, salir y volver reutilizaría un puerto ya liberado, y
/// —peor— un reconocedor podría sobrevivir a la pantalla que lo abrió, que es
/// justo lo que `EVO-009-REQ-005` prohíbe.
///
/// Las pruebas lo sustituyen por el fake determinista; el resto de la aplicación
/// no conoce ninguna de las dos implementaciones.
typedef SpeechPortFactory = SpeechTranscriptionPort Function();

/// Motor de voz de la compilación: `local` (por defecto, #165/#166) es el
/// reconocimiento dentro de la app; `android` vuelve al reconocedor del sistema
/// de `ADR-002`. Se elige al compilar con `--dart-define=AGRO_VOICE_ENGINE=…`;
/// la app nunca cambia de uno a otro por su cuenta.
const voiceEngine = String.fromEnvironment(
  'AGRO_VOICE_ENGINE',
  defaultValue: 'local',
);

/// Tope de la revisión de cada frase, en milisegundos (#166). Pasado, la frase
/// se entrega como la oyó Vosk. Se cambia al compilar con
/// `--dart-define=AGRO_VOICE_REVIEW_TIMEOUT_MS=…`; por defecto, el p95 que #12
/// exige a la segunda pasada (5 000 ms).
const voiceReviewTimeoutMs = int.fromEnvironment(
  'AGRO_VOICE_REVIEW_TIMEOUT_MS',
  defaultValue: 5000,
);

/// Cómo se comprueban las cantidades de la segunda pasada. Lo inyecta
/// `main.dart` con el lector de la app; sin él, la revisión no se acepta.
final reviewFactsProvider = Provider<ReviewFacts?>((ref) => null);

/// Hechos con el papel de cada cifra (precio o cantidad), para clasificar las
/// diferencias por campo (diagnóstico y política B). La regla A no los usa.
final reviewFieldFactsProvider = Provider<ReviewFacts?>((ref) => null);

final speechPortFactoryProvider = Provider<SpeechPortFactory>((ref) {
  if (voiceEngine == 'android') return AndroidSpeechTranscriptionAdapter.new;
  final facts = ref.watch(reviewFactsProvider);
  final fieldFacts = ref.watch(reviewFieldFactsProvider);
  return () => LocalSpeechTranscriptionAdapter(
    facts: facts,
    fieldFacts: fieldFacts,
    reviewTimeout: const Duration(milliseconds: voiceReviewTimeoutMs),
  );
});
