import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/port/voice_engine_diagnostics.dart';
import 'package:agroquimicos/voice/port/whole_turn_transcription_adapter.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Puerto experimental «un solo transcriptor por turno» (F09, 2026-11-09)
/// contra canales simulados: sin motor ni micrófono. Se comprueba qué pide al
/// motor, que un turno entrega como mucho un segmento, y que nada tardío,
/// cancelado o vacío llega a la sesión. Las frases son sintéticas.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(
    LocalSpeechTranscriptionAdapter.methodChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  String? startReply;
  Map<String, Object?>? describe;

  setUp(() {
    startReply = null;
    describe = null;
    VoiceExperiment.instance.reset();
    VoiceExperiment.instance.clearTurnMetrics();
    VoiceExperiment.instance.turnVariant = 'base';
  });

  WholeTurnTranscriptionAdapter build({String? variant}) {
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      return switch (call.method) {
        'start' => startReply,
        'describe' =>
          describe ??
              {
                'modelPresent': true,
                'engineName': 'Vosk (vosk-android 0.3.75)',
                'engineVersion': 'vosk-model-small-es-0.42',
                'reviewModel': 'whisper-base-q5_1',
                'reviewAvailable': true,
                'reviewVariants': ['base', 'small'],
                'reviewModels': {
                  'base': 'whisper-base-q5_1',
                  'small': 'whisper-small-q5_1',
                },
                'airplaneMode': true,
              },
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
    final adapter = WholeTurnTranscriptionAdapter(variant: variant);
    addTearDown(adapter.dispose);
    return adapter;
  }

  int gen([int n = 0]) {
    final starts = calls.where((c) => c.method == 'start').toList();
    return (starts[n].arguments as Map)['gen'] as int;
  }

  Map<Object?, Object?> startArgs([int n = 0]) =>
      (calls.where((c) => c.method == 'start').toList()[n].arguments as Map)
          .cast<Object?, Object?>();

  void native(Map<String, Object?> payload) {
    messenger.handlePlatformMessage(
      LocalSpeechTranscriptionAdapter.eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  Map<String, Object?> info({String variant = 'base'}) => {
    'audioMs': 7600,
    'speechMs': 2450,
    'speechRmsDbfs': -30.4,
    'loadMs': 0,
    'inferenceMs': 3600,
    'variant': variant,
    'model': 'whisper-$variant-q5_1',
    'closedBy': 'stoppedByUser',
  };

  const request = TranscriptionRequest(
    locale: 'es-US',
    maxTurnDuration: Duration(minutes: 5),
    hints: ['Fungicida DEMO', 'Agroinsumos DEMO (sintético)', 'bolivianos'],
  );

  test('se identifica como turno entero y escucha a través de las pausas', () {
    final adapter = build();
    expect(adapter.engineId, singleTranscriberTurnEngineId);
    expect(adapter.listensAcrossPauses, isTrue);
  });

  test('la disponibilidad depende de que la variante elegida esté en el '
      'APK; el modelo informado es el de esa variante', () async {
    final a = build(variant: 'small');
    final availability = await a.checkAvailability('es');
    expect(availability.recognizerAvailable, isTrue);
    expect(availability.engineVersion, 'whisper-small-q5_1');
    expect(availability.engineName, contains('small'));
    // Sin revisión aparte: la interfaz no ofrece «Revisar cada frase».
    expect(availability.reviewModel, isNull);

    describe = {
      'modelPresent': true,
      'reviewAvailable': true,
      'reviewVariants': ['base'],
      'reviewModels': {'base': 'whisper-base-q5_1'},
      'airplaneMode': false,
    };
    final missing = await build(variant: 'small').checkAvailability('es');
    expect(missing.recognizerAvailable, isFalse);
    expect(missing.detail, 'variant-missing:small');

    describe = {
      'modelPresent': true,
      'reviewAvailable': false,
      'reviewNativeLib': 'UnsatisfiedLinkError',
      'reviewVariants': <String>[],
      'airplaneMode': false,
    };
    final noLib = await build().checkAvailability('es');
    expect(noLib.recognizerAvailable, isFalse);
    expect(noLib.detail, 'UnsatisfiedLinkError');
  });

  test('abre el turno en modo entero con la variante del experimento, la '
      'pista del catálogo y los topes explícitos', () async {
    VoiceExperiment.instance.turnVariant = 'small';
    final adapter = build();
    await adapter.start(request);
    final args = startArgs();
    expect(args['mode'], 'whole');
    expect(args['variant'], 'small');
    expect(args['review'], isFalse);
    expect(args['turnMaxMs'], 30000);
    expect(args['turnTimeoutMs'], 45000);
    expect(
      args['hints'],
      'Fungicida DEMO, Agroinsumos DEMO (sintético), bolivianos.',
    );
    expect(adapter.isTurnOpen, isTrue);
  });

  test('un turno entrega un solo segmento con el texto entero y cierra por '
      'el usuario; la métrica no lleva texto', () async {
    final adapter = build();
    final events = <TranscriptionEvent>[];
    adapter.events.listen(events.add);
    await adapter.start(request);
    native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
    await adapter.stop();
    native({'type': 'stage', 'gen': gen(), 'stage': 'processing'});
    native({
      'type': 'turnText',
      'gen': gen(),
      'text': ' compré dos litros de fungicida demo ',
      'ms': 3600,
      'outcome': 'ok',
      'info': info(),
    });
    native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
    await Future<void>.delayed(Duration.zero);

    final segments = events.whereType<TranscriptionSegment>().toList();
    expect(segments, hasLength(1));
    expect(segments.single.text, 'compré dos litros de fungicida demo');
    expect(segments.single.turn, gen());
    expect(
      events.whereType<TranscriptionStageChanged>().map((e) => e.stage),
      containsAllInOrder([
        TranscriptionStage.listening,
        TranscriptionStage.processing,
      ]),
    );
    expect(
      events.whereType<TranscriptionTurnEnded>().single.reason,
      TranscriptionEndReason.stoppedByUser,
    );
    expect(adapter.isTurnOpen, isFalse);
    expect(calls.where((c) => c.method == 'stop'), hasLength(1));

    final metric = VoiceExperiment.instance.turnMetrics.single;
    expect(metric.variant, 'base');
    expect(metric.model, 'whisper-base-q5_1');
    expect(metric.outcome, 'ok');
    expect(metric.hadText, isTrue);
    expect(metric.inferenceMs, 3600);
    expect(metric.speechDbfs, -30);
    expect(metric.logLine, isNot(contains('fungicida')));
    expect(metric.logLine, contains('inferencia=3600ms'));
  });

  test(
    'texto vacío: sin segmento, el turno termina como «nada reconocido»',
    () async {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      await adapter.start(request);
      native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
      native({
        'type': 'turnText',
        'gen': gen(),
        'text': '',
        'ms': 900,
        'outcome': 'ok',
        'info': info(),
      });
      native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<TranscriptionSegment>(), isEmpty);
      expect(events.whereType<TranscriptionNoMatch>(), hasLength(1));
      expect(
        events.whereType<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.noMatch,
      );
      expect(VoiceExperiment.instance.turnMetrics.single.hadText, isFalse);
    },
  );

  test(
    'tope de transcripción agotado: termina por tiempo, sin texto',
    () async {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      await adapter.start(request);
      native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
      native({
        'type': 'turnText',
        'gen': gen(),
        'text': null,
        'ms': 45000,
        'outcome': 'aborted',
        'info': info(),
      });
      native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<TranscriptionSegment>(), isEmpty);
      expect(events.whereType<TranscriptionTimeout>(), hasLength(1));
      expect(
        events.whereType<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.timeout,
      );
      expect(VoiceExperiment.instance.turnMetrics.single.outcome, 'aborted');
    },
  );

  test('modelo no disponible: el error nativo cierra el turno con su código '
      'y la sesión queda recuperable', () async {
    final adapter = build(variant: 'small');
    final events = <TranscriptionEvent>[];
    adapter.events.listen(events.add);
    await adapter.start(request);
    native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
    native({
      'type': 'turnText',
      'gen': gen(),
      'text': null,
      'ms': 0,
      'outcome': 'unavailable',
      'info': {...info(variant: 'small'), 'detail': 'review-model-load'},
    });
    native({
      'type': 'error',
      'gen': gen(),
      'code': 'recognizerUnavailable',
      'detail': 'review-model-load',
    });
    native({'type': 'ended', 'gen': gen(), 'reason': 'error'});
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TranscriptionSegment>(), isEmpty);
    final failed = events.whereType<TranscriptionFailed>().single;
    expect(failed.code, TranscriptionErrorCode.recognizerUnavailable);
    expect(failed.detail, 'review-model-load');
    expect(
      events.whereType<TranscriptionTurnEnded>().single.reason,
      TranscriptionEndReason.error,
    );
    expect(adapter.isTurnOpen, isFalse);
    // Se puede volver a abrir un turno.
    await adapter.start(request);
    expect(adapter.isTurnOpen, isTrue);
    expect(gen(1), greaterThan(gen(0)));
  });

  test(
    'cancelar descarta el turno: su texto, aunque llegue después, no entra',
    () async {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      await adapter.start(request);
      final first = gen();
      native({'type': 'stage', 'gen': first, 'stage': 'listening'});
      await adapter.cancel();
      expect(
        calls
            .where((c) => c.method == 'cancel')
            .map((c) => (c.arguments as Map)['gen']),
        contains(first),
      );
      native({
        'type': 'turnText',
        'gen': first,
        'text': 'compré dos litros de fungicida demo',
        'ms': 3000,
        'outcome': 'ok',
        'info': info(),
      });
      native({'type': 'ended', 'gen': first, 'reason': 'stoppedByUser'});
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<TranscriptionSegment>(), isEmpty);
      expect(events.whereType<TranscriptionCancelled>(), hasLength(1));
      expect(
        events.whereType<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.cancelled,
      );
      // Un turno cancelado no deja métrica: no hubo transcripción aceptada.
      expect(VoiceExperiment.instance.turnMetrics, isEmpty);
    },
  );

  test('el texto de un turno anterior no modifica el turno actual', () async {
    final adapter = build();
    final events = <TranscriptionEvent>[];
    adapter.events.listen(events.add);
    await adapter.start(request);
    final first = gen(0);
    native({'type': 'stage', 'gen': first, 'stage': 'listening'});
    await adapter.stop();
    native({
      'type': 'turnText',
      'gen': first,
      'text': 'compré un litro de herbicida demo',
      'ms': 2000,
      'outcome': 'ok',
      'info': info(),
    });
    native({'type': 'ended', 'gen': first, 'reason': 'stoppedByUser'});
    await Future<void>.delayed(Duration.zero);

    await adapter.start(request);
    final second = gen(1);
    expect(second, isNot(first));
    native({'type': 'stage', 'gen': second, 'stage': 'listening'});
    // Un resultado repetido o tardío del primer turno: se ignora.
    native({
      'type': 'turnText',
      'gen': first,
      'text': 'compré un litro de herbicida demo',
      'ms': 2000,
      'outcome': 'ok',
      'info': info(),
    });
    native({'type': 'ended', 'gen': first, 'reason': 'stoppedByUser'});
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TranscriptionSegment>(), hasLength(1));
    expect(adapter.isTurnOpen, isTrue);
    expect(VoiceExperiment.instance.turnMetrics, hasLength(1));
  });

  test('dos turnos consecutivos: cada uno su segmento, en orden', () async {
    final adapter = build();
    final events = <TranscriptionEvent>[];
    adapter.events.listen(events.add);
    for (var i = 0; i < 2; i++) {
      await adapter.start(request);
      final g = gen(i);
      native({'type': 'stage', 'gen': g, 'stage': 'listening'});
      await adapter.stop();
      native({
        'type': 'turnText',
        'gen': g,
        'text': 'frase sintética $i',
        'ms': 1000,
        'outcome': 'ok',
        'info': info(),
      });
      native({'type': 'ended', 'gen': g, 'reason': 'stoppedByUser'});
      await Future<void>.delayed(Duration.zero);
    }
    expect(events.whereType<TranscriptionSegment>().map((s) => s.text), [
      'frase sintética 0',
      'frase sintética 1',
    ]);
    expect(events.whereType<TranscriptionTurnEnded>(), hasLength(2));
  });

  test('se alcanzó el audio máximo: lo oído se entrega y el cierre es por '
      'tiempo', () async {
    final adapter = build();
    final events = <TranscriptionEvent>[];
    adapter.events.listen(events.add);
    await adapter.start(request);
    native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
    native({'type': 'stage', 'gen': gen(), 'stage': 'processing'});
    native({
      'type': 'turnText',
      'gen': gen(),
      'text': 'frase sintética larga',
      'ms': 9000,
      'outcome': 'ok',
      'info': {...info(), 'closedBy': 'maxDuration', 'audioMs': 30000},
    });
    native({'type': 'ended', 'gen': gen(), 'reason': 'maxDuration'});
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TranscriptionSegment>(), hasLength(1));
    expect(events.whereType<TranscriptionTimeout>(), isEmpty);
    expect(
      events.whereType<TranscriptionTurnEnded>().single.reason,
      TranscriptionEndReason.timeout,
    );
    expect(VoiceExperiment.instance.turnMetrics.single.closedBy, 'maxDuration');
  });

  test('si el motor no cierra tras terminar, el puerto cancela y termina por '
      'tiempo pasado el tope más el margen', () {
    fakeAsync((async) {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      adapter.start(request);
      async.flushMicrotasks();
      native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
      async.flushMicrotasks();
      adapter.stop();
      async.flushMicrotasks();
      async.elapse(
        WholeTurnTranscriptionAdapter.defaultTranscriptionTimeout +
            WholeTurnTranscriptionAdapter.stopGraceMargin -
            const Duration(seconds: 1),
      );
      expect(adapter.isTurnOpen, isTrue);
      async.elapse(const Duration(seconds: 2));
      expect(adapter.isTurnOpen, isFalse);
      expect(events.whereType<TranscriptionTimeout>(), hasLength(1));
      expect(calls.where((c) => c.method == 'cancel'), isNotEmpty);
    });
  });

  test('la grabación tiene plazo: al vencer se pide terminar sola', () {
    fakeAsync((async) {
      final adapter = build();
      adapter.start(request);
      async.flushMicrotasks();
      native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 31));
      async.flushMicrotasks();
      expect(calls.where((c) => c.method == 'stop'), hasLength(1));
    });
  });

  test('las métricas tienen tope y se borran a mano', () {
    final experiment = VoiceExperiment.instance;
    for (var i = 0; i < VoiceExperiment.maxTurnMetrics + 5; i++) {
      experiment.noteTurn(
        SingleTranscriberTurnMetric(
          turn: i,
          variant: 'base',
          model: 'whisper-base-q5_1',
          outcome: 'ok',
          hadText: true,
          audioMs: 1000,
          speechMs: 500,
          speechDbfs: -30,
          loadMs: 0,
          inferenceMs: 400,
          closedBy: 'stoppedByUser',
        ),
      );
    }
    expect(experiment.turnMetrics, hasLength(VoiceExperiment.maxTurnMetrics));
    expect(experiment.turnMetrics.first.turn, 5);
    experiment.clearTurnMetrics();
    expect(experiment.turnMetrics, isEmpty);
  });

  group('small con haz de 5 (F09, 2026-11-10)', () {
    tearDown(
      () => VoiceExperiment.instance.turnDecoding =
          VoiceExperiment.defaultTurnDecoding,
    );

    test('por defecto: small y haz de 5; la anterior (voraz) sigue '
        'disponible para volver atrás', () {
      expect(VoiceExperiment.defaultTurnVariant, 'small');
      expect(VoiceExperiment.defaultTurnDecoding, WholeTurnDecoding.beam5);
      expect(WholeTurnDecoding.beam5.beamSize, 5);
      expect(WholeTurnDecoding.greedy.beamSize, 1);
    });

    test('el motor recibe el ancho del haz elegido', () async {
      VoiceExperiment.instance.turnVariant = 'small';
      VoiceExperiment.instance.turnDecoding = WholeTurnDecoding.beam5;
      await build().start(request);
      expect(startArgs()['beamSize'], 5);
      expect(startArgs()['variant'], 'small');

      VoiceExperiment.instance.turnDecoding = WholeTurnDecoding.greedy;
      await build().start(request);
      expect(startArgs()['beamSize'], 1);
    });

    test('la pista del turno entero tiene tope de 400 caracteres (menos de '
        '223 tokens) y no arrastra nada del turno anterior', () async {
      final many = [for (var i = 0; i < 80; i++) 'Producto sintético $i'];
      final adapter = build();
      await adapter.start(
        TranscriptionRequest(
          locale: 'es-US',
          maxTurnDuration: const Duration(minutes: 5),
          hints: many,
        ),
      );
      final hint = startArgs()['hints'] as String;
      expect(hint.length, lessThanOrEqualTo(401));
      expect(hint, startsWith('Producto sintético 0, '));
      native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
      await Future<void>.delayed(Duration.zero);
      await adapter.start(request);
      expect(
        startArgs(1)['hints'],
        'Fungicida DEMO, Agroinsumos DEMO (sintético), bolivianos.',
      );
    });

    test('la métrica dice el haz, el silencio al principio y al final y el '
        'audio perdido; sin texto', () async {
      final adapter = build();
      await adapter.start(request);
      await adapter.stop();
      native({
        'type': 'turnText',
        'gen': gen(),
        'text': 'compré fungicida demo',
        'ms': 9000,
        'outcome': 'ok',
        'info': {
          ...info(variant: 'small'),
          'beamSize': 5,
          'leadingQuietMs': 350,
          'trailingQuietMs': 1200,
          'droppedMs': 0,
        },
      });
      native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
      await Future<void>.delayed(Duration.zero);
      final m = VoiceExperiment.instance.turnMetrics.last;
      expect(m.beamSize, 5);
      expect(m.leadingQuietMs, 350);
      expect(m.trailingQuietMs, 1200);
      expect(m.logLine, contains('haz=5'));
      expect(m.logLine, contains('silencioFin=1200ms'));
      expect(m.logLine, contains('perdido=0ms'));
      expect(m.logLine, isNot(contains('fungicida')));
    });

    test('sin voz detectada (-1 del motor) el silencio queda «-»', () async {
      final adapter = build();
      await adapter.start(request);
      await adapter.stop();
      native({
        'type': 'turnText',
        'gen': gen(),
        'text': '',
        'ms': 100,
        'outcome': 'ok',
        'info': {...info(), 'leadingQuietMs': -1, 'trailingQuietMs': -1},
      });
      native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
      await Future<void>.delayed(Duration.zero);
      final m = VoiceExperiment.instance.turnMetrics.last;
      expect(m.leadingQuietMs, isNull);
      expect(m.logLine, contains('silencioInicio=-ms'));
    });
  });
}
