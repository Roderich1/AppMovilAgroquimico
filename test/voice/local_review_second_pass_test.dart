import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Segunda pasada condicional (#166), con el adaptador real y el lado nativo
/// simulado con sus eventos (`phrase`, `partial`, `segment`, `ended`).
///
/// Comprueba las garantías que no dependen del modelo:
///
/// * activación por capacidad del teléfono (memoria, poca memoria, fallo de
///   carga) y por el modo de revisión;
/// * una única transcripción por frase, nunca mezcla de motores;
/// * tope por frase: sin revisión a tiempo queda el texto de Vosk, sin
///   bloquear, y la revisión tardía se descarta;
/// * cancelar descarta las revisiones pendientes; tras detener y cerrar, nada
///   entra.
///
/// No hay modelo, micrófono ni teléfono: el tiempo real de la revisión en un
/// teléfono es `NOT_MEASURED`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(
    LocalSpeechTranscriptionAdapter.methodChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const gib = 1024 * 1024 * 1024;

  late List<MethodCall> calls;

  Map<String, Object?> describeSmall({
    int? total = 6 * gib,
    bool lowRam = false,
    String? failure,
  }) => {
    'modelPresent': true,
    'engineName': 'Vosk (vosk-android 0.3.75)',
    'engineVersion': 'vosk-model-small-es-0.42',
    'reviewModel': 'whisper-small-q5_1',
    'reviewVariant': 'small',
    'reviewModelBytes': 190085487,
    'reviewAvailable': true,
    'reviewDetail': failure,
    'totalMemBytes': total,
    'lowRamDevice': lowRam,
    'airplaneMode': true,
  };

  LocalSpeechTranscriptionAdapter build({
    Map<String, Object?>? describe,
    Duration reviewTimeout =
        LocalSpeechTranscriptionAdapter.defaultReviewTimeout,
  }) {
    calls = <MethodCall>[];
    final reply = describe ?? describeSmall();
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      return call.method == 'describe' ? reply : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
    final adapter = LocalSpeechTranscriptionAdapter(
      facts: voiceQuantityFacts,
      reviewTimeout: reviewTimeout,
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  Map<Object?, Object?> startArgs([int n = 0]) =>
      calls.where((c) => c.method == 'start').elementAt(n).arguments
          as Map<Object?, Object?>;

  int gen() => startArgs()['gen'] as int;

  void native(Map<String, Object?> payload) {
    messenger.handlePlatformMessage(
      LocalSpeechTranscriptionAdapter.eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  void phrase(int seq, String vosk, {bool review = true}) => native({
    'type': 'phrase',
    'gen': gen(),
    'seq': seq,
    'vosk': vosk,
    'review': review,
  });

  void segment(int seq, String vosk, String? review, {int ms = 900}) => native({
    'type': 'segment',
    'gen': gen(),
    'seq': seq,
    'vosk': vosk,
    'review': review,
    'reviewMs': ms,
  });

  const request = TranscriptionRequest(
    locale: 'es-US',
    maxTurnDuration: Duration(minutes: 5),
    hints: ['Bellator', 'Glifosato'],
  );

  /// Abre un turno ya escuchando y devuelve los eventos que emite.
  List<TranscriptionEvent> listen(
    FakeAsync async,
    LocalSpeechTranscriptionAdapter adapter, {
    TranscriptionRequest r = request,
    bool checkFirst = true,
  }) {
    final events = <TranscriptionEvent>[];
    adapter.events.listen(events.add);
    if (checkFirst) adapter.checkAvailability('es-US');
    async.flushMicrotasks();
    adapter.start(r);
    async.flushMicrotasks();
    native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
    async.flushMicrotasks();
    return events;
  }

  List<String> texts(List<TranscriptionEvent> events) =>
      events.whereType<TranscriptionSegment>().map((s) => s.text).toList();

  group('activación por capacidad y por el modo de revisión', () {
    test('teléfono capaz: small se anuncia y se pide', () async {
      final adapter = build();
      final a = await adapter.checkAvailability('es-US');
      expect(a.reviewModel, 'whisper-small-q5_1');
      expect(a.reviewDetail, 'review-ok');
      await adapter.start(request);
      expect(startArgs()['review'], isTrue);
      expect(startArgs()['reviewTimeoutMs'], 5000);
    });

    for (final (name, describe, reason) in [
      (
        'memoria total por debajo del mínimo de small',
        describeSmall(total: 3 * gib),
        'review-ram-below:3400',
      ),
      (
        'el sistema se declara de poca memoria',
        describeSmall(lowRam: true),
        'review-low-ram-device',
      ),
      (
        'el modelo ya falló al cargarse (sin memoria)',
        describeSmall(failure: 'review-OutOfMemoryError'),
        'review-load-failed:review-OutOfMemoryError',
      ),
      (
        'memoria total desconocida',
        describeSmall(total: null),
        'review-ram-unknown',
      ),
    ]) {
      test('teléfono no capaz ($name): sólo Vosk, sin error y con su '
          'motivo', () async {
        final adapter = build(describe: describe);
        final a = await adapter.checkAvailability('es-US');
        expect(a.recognizerAvailable, isTrue);
        expect(a.reviewModel, isNull);
        expect(a.reviewDetail, reason);

        await adapter.start(request);
        expect(startArgs()['review'], isFalse);
      });
    }

    test('sin consulta previa, el turno pregunta antes de pedir revisión', () {
      fakeAsync((async) {
        final adapter = build(describe: describeSmall(total: 2 * gib));
        adapter.start(request);
        async.flushMicrotasks();
        final methods = calls.map((c) => c.method).toList();
        expect(methods.indexOf('describe'), lessThan(methods.indexOf('start')));
        expect(startArgs()['review'], isFalse);
      });
    });

    test('cancelar mientras se consulta la capacidad no abre nada', () {
      fakeAsync((async) {
        final adapter = build();
        adapter.start(request);
        adapter.cancel();
        async.flushMicrotasks();
        expect(calls.where((c) => c.method == 'start'), isEmpty);
        expect(adapter.isTurnOpen, isFalse);
      });
    });

    test('modo de revisión inactivo: no se pide aunque el teléfono pueda', () {
      fakeAsync((async) {
        final adapter = build();
        final events = listen(
          async,
          adapter,
          r: const TranscriptionRequest(locale: 'es-US', review: false),
        );
        expect(startArgs()['review'], isFalse);
        // Lo nativo entrega sin revisión: llega el texto de Vosk.
        segment(0, 'compré dos litros de glifosato', null, ms: 0);
        async.flushMicrotasks();
        expect(texts(events), ['compré dos litros de glifosato']);
      });
    });
  });

  group('una única transcripción por frase', () {
    test('llega la revisada o la de Vosk, nunca las dos ni una mezcla', () {
      fakeAsync((async) {
        final adapter = build();
        final events = listen(async, adapter);
        phrase(0, 'aplique medio litro de bella thor');
        phrase(1, 'compré dos litros de glifosato');
        segment(
          0,
          'aplique medio litro de bella thor',
          'Aplique medio litro de Bellator.',
        );
        // Cambiaría la cantidad: se queda Vosk.
        segment(
          1,
          'compré dos litros de glifosato',
          'Compré 3 litros de glifosato.',
        );
        // Un segundo resultado de la misma frase no entra.
        segment(0, 'aplique medio litro de bella thor', 'Otro texto.');
        async.flushMicrotasks();

        final segments = events.whereType<TranscriptionSegment>().toList();
        expect(segments.map((s) => s.text), [
          'Aplique medio litro de Bellator.',
          'compré dos litros de glifosato',
        ]);
        expect(segments.map((s) => s.sequence), [0, 1]);
        expect(segments.map((s) => s.revised), [true, false]);
        for (final s in segments) {
          // Ninguna frase lleva texto de los dos motores.
          expect(
            s.text.contains('bella thor') && s.text.contains('Bellator'),
            isFalse,
          );
        }
        // Los topes de las frases ya entregadas no disparan nada después.
        async.elapse(const Duration(seconds: 30));
        expect(events.whereType<TranscriptionSegment>(), hasLength(2));
      });
    });

    test(
      'fallo de la revisión: queda Vosk en el acto, sin esperar el tope',
      () {
        fakeAsync((async) {
          final adapter = build();
          final events = listen(async, adapter);
          phrase(0, 'compré dos litros de glifosato');
          segment(0, 'compré dos litros de glifosato', null, ms: 40);
          async.flushMicrotasks();
          expect(texts(events), ['compré dos litros de glifosato']);
          expect(
            events.whereType<TranscriptionSegment>().single.revised,
            isFalse,
          );
        });
      },
    );
  });

  group('tope por frase', () {
    test('sin revisión a tiempo se entrega Vosk; la tardía se descarta', () {
      fakeAsync((async) {
        final adapter = build(reviewTimeout: const Duration(seconds: 2));
        final events = listen(async, adapter);
        expect(startArgs()['reviewTimeoutMs'], 2000);

        phrase(0, 'compré dos litros de bellator');
        native({
          'type': 'partial',
          'gen': gen(),
          'text': 'compré dos litros de bellator',
          'reviewing': 1,
        });
        async.elapse(const Duration(milliseconds: 1999));
        expect(texts(events), isEmpty, reason: 'aún dentro del tope');

        async.elapse(const Duration(milliseconds: 1));
        expect(texts(events), ['compré dos litros de bellator']);
        expect(
          events.whereType<TranscriptionSegment>().single.revised,
          isFalse,
        );

        // El parcial nativo todavía incluye la frase vencida: no se muestra
        // dos veces ni sigue contando como «revisando».
        native({
          'type': 'partial',
          'gen': gen(),
          'text': 'compré dos litros de bellator y cinco',
          'reviewing': 1,
        });
        async.flushMicrotasks();
        final last = events.whereType<TranscriptionPartial>().last;
        expect(last.text, 'y cinco');
        expect(last.reviewing, 0);

        // Llega la revisión tarde: no sustituye ni se suma.
        segment(
          0,
          'compré dos litros de bellator',
          'Compré dos litros de Bellator.',
          ms: 4100,
        );
        async.flushMicrotasks();
        expect(texts(events), ['compré dos litros de bellator']);

        // Y la frase siguiente entra normal, en orden.
        phrase(1, 'y cinco kilos de mancozeb');
        segment(1, 'y cinco kilos de mancozeb', 'Y cinco kilos de Mancozeb.');
        async.flushMicrotasks();
        expect(texts(events), [
          'compré dos litros de bellator',
          'Y cinco kilos de Mancozeb.',
        ]);
        expect(
          events.whereType<TranscriptionSegment>().map((s) => s.sequence),
          [0, 1],
        );
      });
    });

    test('el tope de una frase entrega también las anteriores, en orden', () {
      fakeAsync((async) {
        final adapter = build(reviewTimeout: const Duration(seconds: 3));
        final events = listen(async, adapter);
        phrase(0, 'compré dos litros');
        async.elapse(const Duration(seconds: 1));
        phrase(1, 'de glifosato');
        async.elapse(const Duration(seconds: 2));
        expect(texts(events), ['compré dos litros']);
        async.elapse(const Duration(seconds: 1));
        expect(texts(events), ['compré dos litros', 'de glifosato']);
      });
    });
  });

  group('cancelar y detener', () {
    test('cancelar descarta las revisiones pendientes y sus topes', () {
      fakeAsync((async) {
        final adapter = build();
        final events = listen(async, adapter);
        phrase(0, 'compré dos litros de glifosato');
        adapter.cancel();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        segment(0, 'compré dos litros de glifosato', 'Compré dos litros.');
        async.flushMicrotasks();
        expect(texts(events), isEmpty);
        expect(
          events.whereType<TranscriptionTurnEnded>().single.reason,
          TranscriptionEndReason.cancelled,
        );
      });
    });

    test('detener: lo que llega antes del cierre entra; lo de después, no', () {
      fakeAsync((async) {
        final adapter = build();
        final events = listen(async, adapter);
        phrase(0, 'compré dos litros de glifosato');
        adapter.stop();
        async.flushMicrotasks();
        segment(
          0,
          'compré dos litros de glifosato',
          'Compré dos litros de glifosato.',
        );
        native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
        segment(0, 'compré dos litros de glifosato', 'Otra cosa.');
        async.flushMicrotasks();
        expect(texts(events), ['Compré dos litros de glifosato.']);
        expect(
          events.whereType<TranscriptionTurnEnded>().single.reason,
          TranscriptionEndReason.stoppedByUser,
        );
      });
    });

    test('detener con una revisión que no llegó: queda Vosk y se cierra', () {
      fakeAsync((async) {
        final adapter = build();
        final events = listen(async, adapter);
        phrase(0, 'compré dos litros de glifosato');
        adapter.stop();
        async.flushMicrotasks();
        native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
        segment(0, 'compré dos litros de glifosato', 'Revisión tardía.');
        async.flushMicrotasks();
        expect(texts(events), ['compré dos litros de glifosato']);
        expect(
          events.whereType<TranscriptionTurnEnded>().single.reason,
          TranscriptionEndReason.stoppedByUser,
        );
      });
    });

    test('un turno nuevo no hereda frases ni topes del anterior', () {
      fakeAsync((async) {
        final adapter = build(reviewTimeout: const Duration(seconds: 2));
        final events = listen(async, adapter);
        phrase(0, 'texto viejo');
        adapter.cancel();
        async.flushMicrotasks();
        adapter.start(request);
        async.flushMicrotasks();
        final second =
            calls.where((c) => c.method == 'start').last.arguments as Map;
        native({'type': 'stage', 'gen': second['gen'], 'stage': 'listening'});
        async.elapse(const Duration(seconds: 5));
        native({
          'type': 'segment',
          'gen': second['gen'],
          'seq': 0,
          'vosk': 'texto nuevo',
          'review': null,
          'reviewMs': 0,
        });
        async.flushMicrotasks();
        expect(texts(events), ['texto nuevo']);
      });
    });
  });
}
