import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'port/android_speech_transcription_adapter.dart';
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

final speechPortFactoryProvider = Provider<SpeechPortFactory>(
  (ref) => AndroidSpeechTranscriptionAdapter.new,
);
