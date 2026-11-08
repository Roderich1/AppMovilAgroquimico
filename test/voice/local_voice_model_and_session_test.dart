import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/native_event_hub.dart';
import 'package:agroquimicos/voice/session/voice_session_controller.dart';
import 'package:agroquimicos/voice/session/voice_session_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// El motor local visto desde la sesión, con el adaptador real y el lado
/// nativo simulado (#165, #119).
///
/// * Modelo ausente o inválido: la captura dice «no disponible», no abre el
///   micrófono y la escritura a mano sigue (criterio de #165: «Dado un
///   teléfono donde Vosk no puede cargarse…»).
/// * Dos pantallas a la vez sobre el mismo canal.
/// * Una pausa que parte el dictado en dos frases (POCO, §2.2): las dos llegan
///   al texto de sesión.
///
/// No hay modelo ni micrófono: lo que el lado nativo contestaría se simula con
/// sus códigos reales (`LocalVoiceModels.ModelException`, `ensureVosk`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(
    LocalSpeechTranscriptionAdapter.methodChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  /// Respuestas sucesivas a `prepare`; la última se repite. `null` es «listo».
  late List<String?> prepareReplies;
  late Map<String, Object?> describe;

  setUp(() {
    calls = <MethodCall>[];
    prepareReplies = [null];
    describe = {
      'modelPresent': true,
      'engineName': 'Vosk (vosk-android 0.3.75)',
      'engineVersion': 'vosk-model-small-es-0.42',
      'reviewModel': 'whisper-base-q5_1',
      'reviewAvailable': true,
      'airplaneMode': false,
    };
    var prepared = 0;
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'prepare':
          final i = prepared < prepareReplies.length
              ? prepared
              : prepareReplies.length - 1;
          prepared++;
          return prepareReplies[i];
        case 'describe':
          return describe;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
  });

  LocalSpeechTranscriptionAdapter adapter() {
    final a = LocalSpeechTranscriptionAdapter(facts: voiceQuantityFacts);
    addTearDown(a.dispose);
    return a;
  }

  void native(Map<String, Object?> payload) {
    messenger.handlePlatformMessage(
      LocalSpeechTranscriptionAdapter.eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  Future<void> settle([int turns = 12]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  int lastGen() =>
      (calls.lastWhere((c) => c.method == 'start').arguments as Map)['gen']
          as int;

  Iterable<String> methods() => calls.map((c) => c.method);

  group('modelo ausente o inválido', () {
    test('sin modelo en el APK: no disponible, sin micrófono, y se puede '
        'escribir', () async {
      describe = {'modelPresent': false};
      final session = VoiceSessionController(port: adapter());
      addTearDown(session.dispose);

      await session.startListening();
      await settle();

      expect(session.snapshot.status, VoiceSessionStatus.recognizerUnavailable);
      expect(session.snapshot.errorDetail, 'model-missing');
      expect(methods(), isNot(contains('start')));
      session.editText('dos litros de glifosato');
      expect(session.deliver()?.text, 'dos litros de glifosato');
    });

    for (final code in const [
      'model-integrity',
      'model-copy',
      'model-load:IOException',
      'native-lib',
    ]) {
      test('modelo declarado pero inválido ($code): no disponible antes de '
          'abrir el micrófono', () async {
        prepareReplies = [code];
        final port = adapter();
        final a = await port.checkAvailability('es-US');
        expect(a.recognizerAvailable, isFalse);
        expect(a.detail, code);
        expect(a.installedLocales, isEmpty);
        expect(
          a.reviewModel,
          isNull,
          reason: 'sin Vosk no hay segunda pasada que ofrecer',
        );

        final session = VoiceSessionController(port: port);
        addTearDown(session.dispose);
        await session.startListening();
        await settle();
        expect(
          session.snapshot.status,
          VoiceSessionStatus.recognizerUnavailable,
        );
        expect(methods(), isNot(contains('start')));
        expect(session.snapshot.status.microphoneMayBeOpen, isFalse);
      });
    }

    test('una preparación fallida se reintenta: una copia interrumpida puede '
        'salir bien después', () async {
      prepareReplies = ['model-copy', null];
      final port = adapter();
      final a = await port.checkAvailability('es-US');
      expect(a.recognizerAvailable, isTrue);
      expect(a.detail, isNull);
      expect(methods().where((m) => m == 'prepare'), hasLength(2));
    });

    test('si el modelo falla al cargar ya en el turno, el turno termina con '
        'su código y nada queda abierto', () async {
      final port = adapter();
      final session = VoiceSessionController(port: port);
      addTearDown(session.dispose);
      await session.startListening();
      await settle();
      expect(methods(), contains('start'));

      // Lo que manda `LocalVoiceEngine.start` cuando `ensureVosk` falla.
      native({
        'type': 'error',
        'gen': lastGen(),
        'code': 'recognizerUnavailable',
        'detail': 'model-load:IOException',
      });
      native({'type': 'ended', 'gen': lastGen(), 'reason': 'error'});
      await settle();

      expect(session.snapshot.status, VoiceSessionStatus.recognizerUnavailable);
      expect(session.snapshot.errorDetail, 'model-load:IOException');
      expect(port.isTurnOpen, isFalse);
      session.editText('a mano');
      expect(session.deliver()?.text, 'a mano');
    });
  });

  group('#119 en el motor local', () {
    test('la baja de la pantalla anterior no deja sorda a la nueva', () async {
      final old = adapter();
      final fresh = adapter();
      final session = VoiceSessionController(port: fresh);
      addTearDown(session.dispose);

      // Flutter libera la ruta anterior después de montar la nueva.
      await old.dispose();
      expect(
        NativeEventHub.listenersOf(
          LocalSpeechTranscriptionAdapter.eventChannelName,
        ),
        1,
      );

      await session.startListening();
      await settle();
      native({'type': 'stage', 'gen': lastGen(), 'stage': 'listening'});
      await settle();
      expect(session.snapshot.status, VoiceSessionStatus.listening);

      // Y su `dispose` llevó su propio número, no el del turno nuevo.
      final disposeCall = calls.firstWhere((c) => c.method == 'dispose');
      expect((disposeCall.arguments as Map)['gen'], isNot(lastGen()));
    });

    test('denegar, reintentar y conceder con el motor local', () async {
      final port = adapter();
      final session = VoiceSessionController(port: port);
      addTearDown(session.dispose);

      await session.startListening();
      await settle();
      final first = lastGen();
      native({'type': 'stage', 'gen': first, 'stage': 'awaitingPermission'});
      await settle();
      expect(session.snapshot.status, VoiceSessionStatus.requestingPermission);
      native({
        'type': 'error',
        'gen': first,
        'code': 'permissionDenied',
        'detail': null,
      });
      await settle();
      expect(session.snapshot.status, VoiceSessionStatus.permissionDenied);

      await session.retry();
      await settle();
      final second = lastGen();
      expect(second, greaterThan(first));
      // Una denegación repetida del primer turno no cuenta para el segundo.
      native({
        'type': 'error',
        'gen': first,
        'code': 'permissionDenied',
        'detail': null,
      });
      native({'type': 'stage', 'gen': second, 'stage': 'listening'});
      await settle();
      expect(session.snapshot.status, VoiceSessionStatus.listening);
      expect(session.snapshot.errorCode, isNull);
    });
  });

  group('POCO §2.2: una pausa parte el dictado en dos frases', () {
    test('las dos frases llegan al texto de sesión, en orden', () async {
      final port = adapter();
      final session = VoiceSessionController(port: port);
      addTearDown(session.dispose);
      await session.startListening();
      await settle();
      final g = lastGen();
      native({'type': 'stage', 'gen': g, 'stage': 'listening'});
      // La forma de lo que Vosk cerró en el POCO: la pausa cortó antes del
      // producto, y la segunda frase no trae cantidad ni verbo. Textos
      // sintéticos, no los dictados en el ensayo.
      native({
        'type': 'segment',
        'gen': g,
        'seq': 0,
        'vosk': 'aplique trescientos mililitros',
        'review': null,
        'reviewMs': 0,
      });
      native({
        'type': 'segment',
        'gen': g,
        'seq': 1,
        'vosk': 'de cipermetrina',
        // `degenerate`: la revisión se descarta y queda Vosk.
        'review': 'de de de de de de de de de de de de de',
        'reviewMs': 2914,
      });
      await settle();
      await session.stopListening();
      native({'type': 'ended', 'gen': g, 'reason': 'stoppedByUser'});
      await settle();

      expect(
        session.snapshot.committedText,
        'aplique trescientos mililitros de cipermetrina',
      );
      expect(session.snapshot.segmentCount, 2);
      expect(session.snapshot.status, VoiceSessionStatus.preview);
    });
  });
}
