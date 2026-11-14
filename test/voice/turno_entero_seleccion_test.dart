import 'package:agroquimicos/presentation/voice/voice_purchase_port.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/port/voice_engine_diagnostics.dart';
import 'package:agroquimicos/voice/port/whole_turn_transcription_adapter.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/services.dart';
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

  test('con la configuración por defecto, lo que llega al canal nativo desde '
      'el puerto de la COMPRA es turno entero, small y beamSize 5; desde el '
      'puerto general, la ruta por frases', () async {
    const method = MethodChannel(
      LocalSpeechTranscriptionAdapter.methodChannelName,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final starts = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(method, (call) async {
      if (call.method == 'start') {
        starts.add((call.arguments as Map).cast<Object?, Object?>());
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
    // Frase de guion sintética; no hay audio ni texto reconocido.
    const request = TranscriptionRequest(
      locale: 'es-US',
      maxTurnDuration: Duration(minutes: 5),
      hints: ['Herbicida DEMO', 'bolivianos'],
    );

    final c = container();
    final purchase = c.read(purchaseSpeechPortFactoryProvider)();
    await use(purchase);
    await purchase.start(request);
    final general = c.read(speechPortFactoryProvider)();
    await use(general);
    await general.start(request);

    expect(starts, hasLength(2));
    expect(starts[0]['mode'], 'whole');
    expect(starts[0]['variant'], 'small');
    expect(starts[0]['beamSize'], 5);
    expect(starts[0]['review'], isFalse);
    // Ruta por frases: sin modo entero, sin variante ni haz (la revisión con
    // base depende de la capacidad del teléfono, probada aparte).
    expect(starts[1]['mode'], isNot('whole'));
    expect(starts[1]['variant'], isNull);
    expect(starts[1].containsKey('beamSize'), isFalse);
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
