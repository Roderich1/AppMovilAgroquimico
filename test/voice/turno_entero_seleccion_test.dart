import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/port/voice_engine_diagnostics.dart';
import 'package:agroquimicos/voice/port/whole_turn_transcription_adapter.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// El experimento «un solo transcriptor por turno» sólo alcanza a la compra
/// por voz, sólo en diagnóstico, y la elección no se pierde al entrar en la
/// pantalla (que reinicia los demás experimentos).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceExperiment.instance.reset();
    VoiceExperiment.instance.singleTranscriberTurn = false;
    VoiceExperiment.instance.turnVariant = 'base';
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  Future<void> use(SpeechTranscriptionPort port) async {
    addTearDown(port.dispose);
  }

  test('apagado: la compra usa el mismo puerto de siempre', () async {
    final c = container();
    final port = c.read(experimentSpeechPortFactoryProvider)();
    await use(port);
    expect(port, isA<LocalSpeechTranscriptionAdapter>());
    expect(port.engineId, 'vosk-local');
  });

  test(
    'encendido fuera de la compilación de diagnóstico: no cambia nada',
    () async {
      VoiceExperiment.instance.singleTranscriberTurn = true;
      expect(VoiceExperiment.instance.singleTranscriberTurnActive, isFalse);
      final c = container();
      final port = c.read(experimentSpeechPortFactoryProvider)();
      await use(port);
      expect(port, isA<LocalSpeechTranscriptionAdapter>());
    },
  );

  test('encendido (diagnóstico): la compra abre el puerto de turno entero; '
      'el puerto general sigue siendo el de siempre', () async {
    VoiceExperiment.instance.debugAllowOutsideDiagnostics = true;
    VoiceExperiment.instance.singleTranscriberTurn = true;
    final c = container();
    final purchase = c.read(experimentSpeechPortFactoryProvider)();
    final general = c.read(speechPortFactoryProvider)();
    await use(purchase);
    await use(general);
    expect(purchase, isA<WholeTurnTranscriptionAdapter>());
    expect(purchase.engineId, singleTranscriberTurnEngineId);
    // Aplicación y planificación piden este puerto: sin cambios.
    expect(general, isA<LocalSpeechTranscriptionAdapter>());
  });

  test(
    'reset() de los demás experimentos conserva la elección y la variante',
    () {
      final e = VoiceExperiment.instance;
      e.singleTranscriberTurn = true;
      e.turnVariant = 'small';
      e.policyB = true;
      e.reset();
      expect(e.policyB, isFalse);
      expect(e.singleTranscriberTurn, isTrue);
      expect(e.turnVariant, 'small');
    },
  );

  test('la variante del próximo turno la lee el puerto al abrirlo', () async {
    VoiceExperiment.instance.turnVariant = 'small';
    final port = WholeTurnTranscriptionAdapter();
    await use(port);
    expect(port.variant, 'small');
    VoiceExperiment.instance.turnVariant = 'base';
    expect(port.variant, 'base');
  });
}
