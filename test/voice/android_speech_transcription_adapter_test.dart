import 'package:agroquimicos/voice/port/android_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/native_event_hub.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// El adaptador real de Android, contra canales de plataforma simulados.
///
/// Hasta `DEFECTO-005` esta clase no tenía pruebas: el contrato se verificaba
/// contra el fake y el adaptador se daba por bueno. El defecto vivía justo en
/// esa grieta —la que advierte `RISK-007`— y sólo apareció en el teléfono.
///
/// Aquí no hay motor ni micrófono: se comprueba **la disciplina del turno**,
/// que es lo único que el adaptador aporta por encima del puente nativo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(
    AndroidSpeechTranscriptionAdapter.methodChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late List<MethodCall> sentCalls;

  /// Lo que el lado nativo contesta a `start`: `null` con el permiso ya
  /// concedido, `'awaitingPermission'` si va a mostrar el diálogo.
  Object? startReply;
  setUp(() => startReply = null);

  /// Monta el adaptador con el lado nativo simulado.
  AndroidSpeechTranscriptionAdapter build() {
    calls = <String>[];
    sentCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call.method);
      sentCalls.add(call);
      return call.method == 'start' ? startReply : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
    final adapter = AndroidSpeechTranscriptionAdapter();
    // Sin liberar, el adaptador seguiría enganchado al canal compartido y
    // recibiría los eventos de la prueba siguiente.
    addTearDown(adapter.dispose);
    return adapter;
  }

  /// Número de turno que se pidió en el `start` número [n] (desde 0).
  int gen([int n = 0]) {
    final starts = sentCalls.where((c) => c.method == 'start').toList();
    return (starts[n].arguments as Map)['gen'] as int;
  }

  /// Empuja un evento del lado nativo por el `EventChannel`.
  void native(Map<String, Object?> payload) {
    messenger.handlePlatformMessage(
      AndroidSpeechTranscriptionAdapter.eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  group('DEFECTO-005: el plazo del turno y el diálogo de permiso', () {
    // Medido en el HONOR JDY-LX3P: el usuario tardó dos minutos y medio en
    // contestar el diálogo de permiso. A los sesenta segundos venció el plazo
    // del turno, la continuidad reabrió otro y volvió a pedir el permiso.
    // Android contestó «Can request only one set of permissions at a time» y
    // entregó una denegación inmediata: la pantalla dijo «Permiso de micrófono
    // denegado» aunque el usuario acabó concediéndolo.
    //
    // El plazo existe para que un motor colgado no se quede con el micrófono.
    // Mientras se espera el permiso **no hay micrófono tomado**, así que no
    // tiene nada que proteger y no debe correr.

    test('esperar el permiso no agota el turno', () {
      fakeAsync((async) {
        final adapter = build();
        final events = <TranscriptionEvent>[];
        adapter.events.listen(events.add);

        adapter.start(
          const TranscriptionRequest(
            locale: 'es-US',
            maxTurnDuration: Duration(seconds: 60),
          ),
        );
        async.flushMicrotasks();

        native({'type': 'stage', 'stage': 'awaitingPermission'});
        async.flushMicrotasks();

        // El usuario se toma su tiempo leyendo el diálogo.
        async.elapse(const Duration(minutes: 3));

        expect(
          events.whereType<TranscriptionTimeout>(),
          isEmpty,
          reason: 'no hay micrófono que rescatar mientras se espera el permiso',
        );
        expect(events.whereType<TranscriptionTurnEnded>(), isEmpty);
        expect(adapter.isTurnOpen, isTrue);
        expect(
          calls,
          isNot(contains('cancel')),
          reason: 'cancelar aquí provocaba una segunda petición de permiso',
        );
      });
    });

    test('el plazo empieza a contar cuando el motor escucha de verdad', () {
      fakeAsync((async) {
        final adapter = build();
        final events = <TranscriptionEvent>[];
        adapter.events.listen(events.add);

        adapter.start(
          const TranscriptionRequest(
            locale: 'es-US',
            maxTurnDuration: Duration(seconds: 60),
          ),
        );
        async.flushMicrotasks();
        native({'type': 'stage', 'stage': 'awaitingPermission'});
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 3));

        // Permiso concedido: ahora sí hay micrófono abierto.
        native({'type': 'stage', 'stage': 'listening'});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(events.whereType<TranscriptionTimeout>(), isEmpty);

        async.elapse(const Duration(seconds: 31));
        expect(events.whereType<TranscriptionTimeout>(), hasLength(1));
        expect(
          events.whereType<TranscriptionTurnEnded>().single.reason,
          TranscriptionEndReason.timeout,
        );
        expect(calls, contains('cancel'));
      });
    });

    test('un turno que nunca contesta sí agota su plazo', () {
      fakeAsync((async) {
        final adapter = build();
        final events = <TranscriptionEvent>[];
        adapter.events.listen(events.add);

        adapter.start(
          const TranscriptionRequest(
            locale: 'es-US',
            maxTurnDuration: Duration(seconds: 60),
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 61));

        expect(events.whereType<TranscriptionTimeout>(), hasLength(1));
        expect(adapter.isTurnOpen, isFalse);
      });
    });
  });

  group('traducción del lado nativo', () {
    test('el camino y el locale viajan en la petición', () async {
      final adapter = build();
      final sent = <MethodCall>[];
      messenger.setMockMethodCallHandler(method, (call) async {
        sent.add(call);
        return null;
      });

      await adapter.start(
        const TranscriptionRequest(
          locale: 'es-BO',
          route: TranscriptionEngineRoute.systemDefault,
        ),
      );

      final args = sent.single.arguments as Map<Object?, Object?>;
      expect(args['locale'], 'es-BO');
      expect(args['route'], 'systemDefault');
      expect(args['preferOffline'], isTrue);
    });

    test('el reconocedor anunciado por el motor llega tipado', () async {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      // El motor anuncia el camino de un turno abierto (#119: fuera de un
      // turno no hay a quién atribuirlo).
      await adapter.start(const TranscriptionRequest(locale: 'es-US'));

      native({'type': 'route', 'gen': gen(), 'route': 'systemDefault'});
      await Future<void>.delayed(Duration.zero);

      expect(
        events.whereType<TranscriptionRouteInUse>().single.route,
        TranscriptionEngineRoute.systemDefault,
      );
    });

    test('un nombre de reconocedor desconocido no rompe la sesión', () async {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      await adapter.start(const TranscriptionRequest(locale: 'es-US'));

      native({'type': 'route', 'gen': gen(), 'route': 'cuántico'});
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<TranscriptionRouteInUse>(), isEmpty);
      expect(adapter.isTurnOpen, isTrue);
    });
  });

  // #119 (F09-D1): reintento tras denegar el micrófono que se quedaba en
  // «Abriendo el micrófono». Lo que aquí se comprueba es la parte de Dart;
  // el lado nativo lleva el número de turno de vuelta en cada evento.
  group('#119: número de turno y aperturas sin respuesta', () {
    const request = TranscriptionRequest(
      locale: 'es-US',
      maxTurnDuration: Duration(seconds: 60),
    );

    test('cada turno lleva un número único en el proceso', () async {
      final a = build();
      await a.start(request);
      await a.cancel();
      await a.start(request);
      expect(gen(1), greaterThan(gen()));

      // Otra pantalla, otro adaptador: tampoco repite número.
      final firstOfB = sentCalls.length;
      final b = AndroidSpeechTranscriptionAdapter();
      addTearDown(b.dispose);
      await b.start(request);
      final bGen =
          (sentCalls
                      .skip(firstOfB)
                      .firstWhere((c) => c.method == 'start')
                      .arguments
                  as Map)['gen']
              as int;
      expect(bGen, greaterThan(gen(1)));
    });

    test('detener, cancelar y liberar dicen qué turno', () async {
      final adapter = build();
      await adapter.start(request);
      final g = gen();
      await adapter.stop();
      await adapter.cancel();
      await adapter.dispose();
      for (final name in ['stop', 'cancel', 'dispose']) {
        final call = sentCalls.lastWhere((c) => c.method == name);
        expect((call.arguments as Map)['gen'], g, reason: name);
      }
    });

    test(
      'un resultado tardío del turno cancelado no entra en el reintento',
      () async {
        final adapter = build();
        final events = <TranscriptionEvent>[];
        adapter.events.listen(events.add);

        await adapter.start(request);
        final old = gen();
        native({'type': 'stage', 'gen': old, 'stage': 'listening'});
        await adapter.cancel();
        await adapter.start(request);
        final current = gen(1);

        // El sistema entrega tarde lo del turno cancelado.
        native({'type': 'final', 'gen': old, 'text': 'texto viejo'});
        native({'type': 'error', 'gen': old, 'code': 'clientError'});
        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<TranscriptionSegment>(), isEmpty);
        expect(events.whereType<TranscriptionFailed>(), isEmpty);
        expect(adapter.isTurnOpen, isTrue);

        native({'type': 'stage', 'gen': current, 'stage': 'listening'});
        native({'type': 'final', 'gen': current, 'text': 'texto nuevo'});
        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<TranscriptionSegment>().map((e) => e.text), [
          'texto nuevo',
        ]);
      },
    );

    test('un evento sin turno abierto no se emite', () async {
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);
      await adapter.start(request);
      final g = gen();
      await adapter.cancel();
      await Future<void>.delayed(Duration.zero);
      events.clear();

      // Una denegación que llega después de cancelar: sin turno, quedaría
      // pendiente en la sesión y haría fallar el turno siguiente.
      native({'type': 'error', 'gen': g, 'code': 'permissionDenied'});
      native({'type': 'stage', 'gen': g, 'stage': 'listening'});
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('con diálogo de permiso se sabe por la respuesta de start', () {
      fakeAsync((async) {
        startReply = 'awaitingPermission';
        final adapter = build();
        final events = <TranscriptionEvent>[];
        adapter.events.listen(events.add);
        adapter.start(request);
        async.flushMicrotasks();

        // Sin ningún evento nativo: la respuesta basta, y llega antes que la
        // pausa que provoca el diálogo.
        expect(
          events.whereType<TranscriptionStageChanged>().single.stage,
          TranscriptionStage.awaitingPermission,
        );
        async.elapse(const Duration(minutes: 3));
        expect(events.whereType<TranscriptionTimeout>(), isEmpty);
        expect(adapter.isTurnOpen, isTrue);
      });
    });

    test('denegar, reintentar y conceder abre el micrófono', () async {
      startReply = 'awaitingPermission';
      final adapter = build();
      final events = <TranscriptionEvent>[];
      adapter.events.listen(events.add);

      await adapter.start(request);
      native({'type': 'error', 'gen': gen(), 'code': 'permissionDenied'});
      await Future<void>.delayed(Duration.zero);
      expect(
        events.whereType<TranscriptionFailed>().single.code,
        TranscriptionErrorCode.permissionDenied,
      );
      expect(adapter.isTurnOpen, isFalse);

      await adapter.start(request);
      native({'type': 'stage', 'gen': gen(1), 'stage': 'listening'});
      await Future<void>.delayed(Duration.zero);
      expect(
        events.whereType<TranscriptionStageChanged>().last.stage,
        TranscriptionStage.listening,
      );
      expect(adapter.isTurnOpen, isTrue);
    });

    test(
      'la baja de una pantalla no deja sorda a la siguiente (canal compartido)',
      () async {
        // Flutter libera la ruta anterior al terminar su animación, cuando la
        // nueva ya puede estar suscrita. Con una suscripción por adaptador, la
        // baja de la vieja quitaba el manejador del canal a la nueva: ningún
        // evento llegaba y la sesión se quedaba «Abriendo el micrófono».
        final old = build();
        final fresh = AndroidSpeechTranscriptionAdapter();
        addTearDown(fresh.dispose);
        final events = <TranscriptionEvent>[];
        fresh.events.listen(events.add);

        await old.dispose();
        expect(
          NativeEventHub.listenersOf(
            AndroidSpeechTranscriptionAdapter.eventChannelName,
          ),
          1,
        );

        await fresh.start(request);
        final g =
            (sentCalls.lastWhere((c) => c.method == 'start').arguments
                as Map)['gen'];
        native({'type': 'stage', 'gen': g, 'stage': 'listening'});
        await Future<void>.delayed(Duration.zero);
        expect(
          events.whereType<TranscriptionStageChanged>().single.stage,
          TranscriptionStage.listening,
        );
      },
    );
  });
}
