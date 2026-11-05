import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'port/android_speech_transcription_adapter.dart';
import 'port/local_speech_transcription_adapter.dart';
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

final speechPortFactoryProvider = Provider<SpeechPortFactory>(
  (ref) => voiceEngine == 'android'
      ? AndroidSpeechTranscriptionAdapter.new
      : LocalSpeechTranscriptionAdapter.new,
);
