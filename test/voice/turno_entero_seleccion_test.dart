import 'package:agroquimicos/presentation/voice/voice_purchase_port.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/port/voice_engine_diagnostics.dart';
import 'package:agroquimicos/voice/port/whole_turn_transcription_adapter.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integración (F09, 2026-11-10): la **compra** por voz usa siempre el turno
/// entero con Whisper small y haz de 5, sin interruptores ni compilación de
/// diagnóstico. Aplicación y planificación siguen con el puerto de siempre
/// (Vosk + revisión por frases).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceExperiment.instance.reset();
    VoiceExperiment.instance.turnVariant = VoiceExperiment.defaultTurnVariant;
    VoiceExperiment.instance.turnDecoding = VoiceExperiment.defaultTurnDecoding;
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  Future<void> use(SpeechTranscriptionPort port) async {
    addTearDown(port.dispose);
  }

  test('configuración elegida: turno entero, small y haz de 5, sin '
      'diagnóstico', () {
    expect(purchaseVoiceWholeTurn, isTrue);
    expect(voiceDiagnosticsBuild, isFalse, reason: 'prueba fuera de diag');
    expect(VoiceExperiment.defaultTurnVariant, 'small');
    expect(VoiceExperiment.defaultTurnDecoding, WholeTurnDecoding.beam5);
  });

  test('la compra abre el puerto de turno entero con small y haz de 5; el '
      'puerto general (aplicación y planificación) sigue siendo el de '
      'siempre', () async {
    final c = container();
    final purchase = c.read(purchaseSpeechPortFactoryProvider)();
    final general = c.read(speechPortFactoryProvider)();
    await use(purchase);
    await use(general);
    expect(purchase, isA<WholeTurnTranscriptionAdapter>());
    expect(purchase.engineId, singleTranscriberTurnEngineId);
    final whole = purchase as WholeTurnTranscriptionAdapter;
    expect(whole.variant, 'small');
    expect(whole.decoding, WholeTurnDecoding.beam5);
    expect(general, isA<LocalSpeechTranscriptionAdapter>());
    expect(general.engineId, 'vosk-local');
  });

  test('reset() de los controles de diagnóstico no cambia la configuración '
      'de la compra', () {
    final e = VoiceExperiment.instance;
    e.policyB = true;
    e.compareContexts = true;
    e.reset();
    expect(e.policyB, isFalse);
    expect(e.compareContexts, isFalse);
    expect(e.turnVariant, 'small');
    expect(e.turnDecoding, WholeTurnDecoding.beam5);
  });

  test('la variante del próximo turno la lee el puerto al abrirlo (sólo se '
      'cambia desde la tarjeta de diagnóstico)', () async {
    final port = WholeTurnTranscriptionAdapter();
    await use(port);
    expect(port.variant, 'small');
    VoiceExperiment.instance.turnVariant = 'base';
    expect(port.variant, 'base');
  });
}
