/// Puerto de voz de la **compra** (F09, integración del 2026-11-10).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../voice/voice_providers.dart';

/// **Configuración elegida para la compra por voz** (Roderich, 2026-11-10,
/// cierre del bloque F09): turno entero con un solo transcriptor, Whisper
/// small (multilingüe, q5_1) con haz de 5, español, sin traducción,
/// temperatura 0 y sin reintentos; revisión explícita antes de registrar. Es
/// una elección por precisión, no una superioridad demostrada. `false`
/// devuelve la compra a la ruta por frases (Vosk + revisión), como antes.
const purchaseVoiceWholeTurn = true;

/// Puerto de «Compra por voz». Aplicación y planificación siguen con
/// [speechPortFactoryProvider] (Vosk + revisión por frases), sin cambios.
final purchaseSpeechPortFactoryProvider = Provider<SpeechPortFactory>(
  (ref) => purchaseVoiceWholeTurn
      ? ref.watch(wholeTurnPortFactoryProvider)
      : ref.watch(speechPortFactoryProvider),
);
