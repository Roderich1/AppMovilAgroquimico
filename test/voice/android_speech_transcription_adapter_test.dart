import 'package:agroquimicos/voice/port/android_speech_transcription_adapter.dart';
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

  /// Monta el adaptador con el lado nativo simulado.
  AndroidSpeechTranscriptionAdapter build() {
    calls = <String>[];
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
    return AndroidSpeechTranscriptionAdapter();
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

      native({'type': 'route', 'route': 'systemDefault'});
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

      native({'type': 'route', 'route': 'cuántico'});
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });
  });
}
