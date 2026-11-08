import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// El adaptador del motor local contra canales simulados (#165, #166).
///
/// No hay motor ni micrófono: se comprueba la disciplina de turno, el número de
/// sesión que descarta resultados tardíos y la elección de una sola
/// transcripción por frase. La inferencia real se comprueba aparte, en el
/// emulador, con `LocalVoiceEngineReferenceTest`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(
    LocalSpeechTranscriptionAdapter.methodChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  String? startReply;
  setUp(() => startReply = null);

  LocalSpeechTranscriptionAdapter build({Map<String, Object?>? describe}) {
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
                'airplaneMode': true,
              },
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
    final adapter = LocalSpeechTranscriptionAdapter(facts: voiceQuantityFacts);
    // Sin liberar, el adaptador seguiría enganchado al canal compartido y
    // recibiría los eventos de la prueba siguiente.
    addTearDown(adapter.dispose);
    return adapter;
  }

  /// Número de turno que el adaptador pidió en su `start` número [n] (desde
  /// 0). Es único en el proceso, así que no se puede escribir a mano.
  int gen([int n = 0]) {
    final starts = calls.where((c) => c.method == 'start').toList();
    return (starts[n].arguments as Map)['gen'] as int;
  }

  void native(Map<String, Object?> payload) {
    messenger.handlePlatformMessage(
      LocalSpeechTranscriptionAdapter.eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  const request = TranscriptionRequest(
    locale: 'es-US',
    maxTurnDuration: Duration(minutes: 5),
    hints: ['Glifosato', 'Bellator', 'Ana Quispe'],
  );

  test(
    'escucha a través de las pausas y no usa el reconocedor del sistema',
    () {
      final adapter = build();
      expect(adapter.listensAcrossPauses, isTrue);
      expect(adapter.engineId, 'vosk-local');
    },
  );

  test(
    'la disponibilidad dice lo que trae el APK, sin prometer otro idioma',
    () async {
      final adapter = build();
      final a = await adapter.checkAvailability('es-US');
      expect(a.recognizerAvailable, isTrue);
      expect(a.installedLocales, ['es']);
      expect(a.reviewModel, 'whisper-base-q5_1');
      expect(a.airplaneMode, AirplaneMode.on);
    },
  );

  test('sin modelo en el APK: no disponible, con su motivo', () async {
    final adapter = build(describe: {'modelPresent': false});
    final a = await adapter.checkAvailability('es-US');
    expect(a.recognizerAvailable, isFalse);
    expect(a.detail, 'model-missing');
    expect(a.reviewModel, isNull);
  });

  test('pide el turno con número, pistas y revisión', () {
    fakeAsync((async) {
      final adapter = build();
      adapter.start(request);
      async.flushMicrotasks();
      final start = calls.singleWhere((c) => c.method == 'start');
      final args = start.arguments as Map;
      expect(args['gen'], isPositive);
      expect(args['hints'], 'Glifosato, Bellator, Ana Quispe.');
      expect(args['review'], isTrue);
    });
  });

  test('parciales, varias frases numeradas y un único cierre', () {
    fakeAsync((async) {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      adapter.start(request);
      async.flushMicrotasks();

      native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
      native({
        'type': 'partial',
        'gen': gen(),
        'text': 'compré dos',
        'reviewing': 0,
      });
      native({
        'type': 'partial',
        'gen': gen(),
        'text': 'compré dos litros de glifosato',
        'reviewing': 1,
      });
      native({
        'type': 'segment',
        'gen': gen(),
        'seq': 0,
        'vosk': 'aplique medio litro de bella thor',
        'review': 'Aplique medio litro de Bellator.',
        'reviewMs': 900,
      });
      native({
        'type': 'segment',
        'gen': gen(),
        'seq': 1,
        'vosk': 'compré dos litros',
        'review': 'Con 3 litros.',
        'reviewMs': 800,
      });
      native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
      async.flushMicrotasks();

      expect(
        events.whereType<TranscriptionRouteInUse>().single.route,
        TranscriptionEngineRoute.embedded,
      );
      final partials = events.whereType<TranscriptionPartial>().toList();
      expect(partials.map((p) => p.text), [
        'compré dos',
        'compré dos litros de glifosato',
      ]);
      expect(partials.last.reviewing, 1);
      final segments = events.whereType<TranscriptionSegment>().toList();
      // Una sola transcripción por frase: la revisada si no toca cantidades,
      // la de Vosk si las tocaría.
      expect(segments.map((s) => s.text), [
        'Aplique medio litro de Bellator.',
        'compré dos litros',
      ]);
      expect(segments.map((s) => s.sequence), [0, 1]);
      expect(segments.map((s) => s.revised), [true, false]);
      expect(
        events.whereType<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.stoppedByUser,
      );
      expect(adapter.isTurnOpen, isFalse);
    });
  });

  test('un resultado de un turno anterior o cancelado no entra', () {
    fakeAsync((async) {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      adapter.start(request);
      async.flushMicrotasks();
      native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
      adapter.cancel();
      async.flushMicrotasks();
      expect(events.whereType<TranscriptionCancelled>(), hasLength(1));

      adapter.start(request);
      async.flushMicrotasks();
      // Llega tarde la revisión del turno 1, y luego lo del turno 2.
      native({
        'type': 'segment',
        'gen': gen(),
        'seq': 0,
        'vosk': 'texto viejo',
        'review': null,
        'reviewMs': 0,
      });
      native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
      native({'type': 'stage', 'gen': gen(1), 'stage': 'listening'});
      native({
        'type': 'segment',
        'gen': gen(1),
        'seq': 0,
        'vosk': 'texto nuevo',
        'review': null,
        'reviewMs': 0,
      });
      async.flushMicrotasks();

      expect(events.whereType<TranscriptionSegment>().map((s) => s.text), [
        'texto nuevo',
      ]);
      expect(adapter.isTurnOpen, isTrue);
    });
  });

  test('detener sin ninguna frase es «sin habla», no texto', () {
    fakeAsync((async) {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      adapter.start(request);
      async.flushMicrotasks();
      native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
      adapter.stop();
      async.flushMicrotasks();
      native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
      async.flushMicrotasks();
      expect(events.whereType<TranscriptionSegment>(), isEmpty);
      expect(events.whereType<TranscriptionNoMatch>(), hasLength(1));
      expect(
        events.whereType<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.noMatch,
      );
    });
  });

  test('permiso denegado cierra el turno con su código', () {
    fakeAsync((async) {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      adapter.start(request);
      async.flushMicrotasks();
      native({'type': 'stage', 'gen': gen(), 'stage': 'awaitingPermission'});
      native({
        'type': 'error',
        'gen': gen(),
        'code': 'permissionDenied',
        'detail': null,
      });
      async.flushMicrotasks();
      expect(
        events.whereType<TranscriptionFailed>().single.code,
        TranscriptionErrorCode.permissionDenied,
      );
      expect(
        events.whereType<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.error,
      );
      expect(adapter.isTurnOpen, isFalse);
    });
  });

  test('con diálogo de permiso, la sesión lo sabe por la respuesta y no por el evento', () {
    // Medido en el emulador: el evento podía llegar después de la pausa que
    // provoca el diálogo, y la sesión cancelaba el turno antes de conceder.
    fakeAsync((async) {
      final adapter = build();
      startReply = 'awaitingPermission';
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      adapter.start(request);
      async.flushMicrotasks();
      expect(
        events.whereType<TranscriptionStageChanged>().single.stage,
        TranscriptionStage.awaitingPermission,
      );
      // Esperar el permiso no agota el turno.
      async.elapse(const Duration(minutes: 10));
      expect(adapter.isTurnOpen, isTrue);
    });
  });

  test('perder el foco cancela el turno abierto', () {
    fakeAsync((async) {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      adapter.start(request);
      async.flushMicrotasks();
      native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
      native({'type': 'cancelled'});
      async.flushMicrotasks();
      expect(
        events.whereType<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.cancelled,
      );
    });
  });

  test(
    'si el motor no cierra tras detener, se cancela y suelta el micrófono',
    () {
      fakeAsync((async) {
        final adapter = build();
        final events = <TranscriptionEvent>[];
        adapter.events.listen(events.add);
        adapter.start(request);
        async.flushMicrotasks();
        native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
        adapter.stop();
        async.flushMicrotasks();
        async.elapse(LocalSpeechTranscriptionAdapter.stopGrace);
        expect(calls.map((c) => c.method), contains('cancel'));
        expect(
          events.whereType<TranscriptionTurnEnded>().single.reason,
          TranscriptionEndReason.timeout,
        );
      });
    },
  );

  test(
    'el plazo del turno detiene (conserva lo dicho) y cuenta como timeout',
    () {
      fakeAsync((async) {
        final adapter = build();
        final events = <TranscriptionEvent>[];
        adapter.events.listen(events.add);
        adapter.start(request);
        async.flushMicrotasks();
        native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
        async.elapse(const Duration(minutes: 5));
        expect(calls.map((c) => c.method), contains('stop'));
        expect(calls.map((c) => c.method), isNot(contains('cancel')));
        native({
          'type': 'segment',
          'gen': gen(),
          'seq': 0,
          'vosk': 'dos litros',
          'review': null,
          'reviewMs': 0,
        });
        native({'type': 'ended', 'gen': gen(), 'reason': 'stoppedByUser'});
        async.flushMicrotasks();
        expect(events.whereType<TranscriptionSegment>(), hasLength(1));
        expect(
          events.whereType<TranscriptionTurnEnded>().single.reason,
          TranscriptionEndReason.timeout,
        );
      });
    },
  );
}
