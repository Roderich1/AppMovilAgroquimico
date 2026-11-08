import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Marca de desacuerdo numérico en el adaptador local, con el lado nativo
/// simulado por el canal de eventos (`phrase`, `segment`, `ended`).
///
/// TEXTO INYECTADO, NO RECONOCIMIENTO REAL: no hay modelo, micrófono ni
/// teléfono. Los textos de Vosk y de la revisión los escribe la prueba.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(
    LocalSpeechTranscriptionAdapter.methodChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  LocalSpeechTranscriptionAdapter build({
    Duration reviewTimeout = const Duration(seconds: 2),
  }) {
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      if (call.method != 'describe') return null;
      return {
        'modelPresent': true,
        'engineName': 'Vosk (vosk-android 0.3.75)',
        'engineVersion': 'vosk-model-small-es-0.42',
        'reviewModel': 'whisper-base-q5_1',
        'reviewAvailable': true,
        'totalMemBytes': 6 * 1024 * 1024 * 1024,
        'lowRamDevice': false,
        'airplaneMode': true,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
    final adapter = LocalSpeechTranscriptionAdapter(
      facts: voiceQuantityFacts,
      reviewTimeout: reviewTimeout,
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  int gen([int n = -1]) {
    final starts = calls.where((c) => c.method == 'start').toList();
    final call = n < 0 ? starts.last : starts[n];
    return (call.arguments as Map)['gen'] as int;
  }

  void native(Map<String, Object?> payload) {
    messenger.handlePlatformMessage(
      LocalSpeechTranscriptionAdapter.eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  void phrase(int seq, String vosk, {int? generation}) => native({
    'type': 'phrase',
    'gen': generation ?? gen(),
    'seq': seq,
    'vosk': vosk,
    'review': true,
  });

  void segment(int seq, String vosk, String? review, {int? generation}) =>
      native({
        'type': 'segment',
        'gen': generation ?? gen(),
        'seq': seq,
        'vosk': vosk,
        'review': review,
        'reviewMs': 900,
      });

  const request = TranscriptionRequest(
    locale: 'es-US',
    maxTurnDuration: Duration(minutes: 5),
  );

  List<TranscriptionEvent> open(
    FakeAsync async,
    LocalSpeechTranscriptionAdapter adapter, {
    List<TranscriptionEvent>? into,
  }) {
    final events = into ?? <TranscriptionEvent>[];
    if (into == null) adapter.events.listen(events.add);
    adapter.checkAvailability('es-US');
    async.flushMicrotasks();
    adapter.start(request);
    async.flushMicrotasks();
    native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
    async.flushMicrotasks();
    return events;
  }

  List<TranscriptionSegment> segments(List<TranscriptionEvent> events) =>
      events.whereType<TranscriptionSegment>().toList();

  const vosk = 'compré dos litros de glifosato a veinte bolivianos el litro';
  const otherValue =
      'Compré dos litros de glifosato a ciento veinte bolivianos el litro.';
  const sameValue = 'Compré 2 litros de glifosato a 20 bolivianos el litro.';

  test('otro valor: texto de Vosk y la marca en el segmento', () {
    fakeAsync((async) {
      final adapter = build();
      final events = open(async, adapter);
      phrase(0, vosk);
      segment(0, vosk, otherValue);
      async.flushMicrotasks();
      final s = segments(events).single;
      expect(s.text, vosk);
      expect(s.revised, isFalse);
      expect(s.numericDisagreement, isTrue);
      expect(s.toString(), isNot(contains('veinte')));
    });
  });

  test('mismo valor en otro formato o revisión aceptada: sin marca', () {
    fakeAsync((async) {
      final adapter = build();
      final events = open(async, adapter);
      phrase(0, vosk);
      segment(0, vosk, sameValue);
      phrase(1, 'un litro y medio de bellator');
      segment(1, 'un litro y medio de bellator', '1.5 litros de Bellator.');
      async.flushMicrotasks();
      final s = segments(events);
      expect(s.map((x) => x.text), [sameValue, 'un litro y medio de bellator']);
      expect(s.map((x) => x.revised), [true, false]);
      expect(s.map((x) => x.numericDisagreement), [false, false]);
    });
  });

  test('revisión fallida, vacía o degenerada: sin marca', () {
    fakeAsync((async) {
      final adapter = build();
      final events = open(async, adapter);
      segment(0, vosk, null);
      segment(1, vosk, '');
      segment(2, vosk, 'litros litros litros litros litros');
      segment(3, vosk, '[MÚSICA]');
      async.flushMicrotasks();
      expect(segments(events), hasLength(4));
      expect(
        segments(events).map((x) => x.numericDisagreement),
        everyElement(isFalse),
      );
    });
  });

  test('tope vencido: sale Vosk sin marca y la revisión tardía con otro valor '
      'se descarta', () {
    fakeAsync((async) {
      final adapter = build(reviewTimeout: const Duration(seconds: 2));
      final events = open(async, adapter);
      phrase(0, vosk);
      async.elapse(const Duration(seconds: 2));
      expect(segments(events).single.numericDisagreement, isFalse);

      segment(0, vosk, otherValue);
      async.flushMicrotasks();
      expect(segments(events), hasLength(1), reason: 'no entra ni se suma');
      expect(segments(events).single.numericDisagreement, isFalse);
    });
  });

  test('la marca no pasa a la frase siguiente ni al turno siguiente', () {
    fakeAsync((async) {
      final adapter = build();
      final events = open(async, adapter);
      phrase(0, vosk);
      segment(0, vosk, otherValue);
      phrase(1, 'de bellator');
      segment(1, 'de bellator', 'De Bellator.');
      async.flushMicrotasks();
      expect(segments(events).map((x) => x.numericDisagreement), [true, false]);

      // Turno nuevo (descartar y volver a hablar): lo que llegue del turno
      // anterior no entra, y la primera frase del nuevo empieza sin marca.
      final stale = gen();
      phrase(2, vosk, generation: stale);
      adapter.cancel();
      async.flushMicrotasks();
      open(async, adapter, into: events);
      segment(2, vosk, otherValue, generation: stale);
      segment(0, 'compré dos litros', 'Compré 2 litros.');
      async.flushMicrotasks();
      expect(segments(events).map((x) => x.numericDisagreement), [
        true,
        false,
        false,
      ]);
      expect(segments(events).last.text, 'Compré 2 litros.');
    });
  });

  test('el registro lleva el veredicto y el tiempo, nunca lo dictado', () {
    final lines = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    addTearDown(() => debugPrint = original);
    fakeAsync((async) {
      final adapter = build();
      open(async, adapter);
      phrase(0, vosk);
      segment(0, vosk, otherValue);
      async.flushMicrotasks();
    });
    final voice = lines.where((l) => l.contains('voz local: frase')).toList();
    expect(voice, isNotEmpty);
    expect(voice.join('\n'), contains('quantities revision=900ms'));
    for (final line in lines) {
      expect(line, isNot(contains('glifosato')));
      expect(line, isNot(contains('veinte')));
    }
  });
}
