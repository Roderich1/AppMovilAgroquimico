import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/port/fake_transcription_port.dart';
import 'package:voice_benchmark/port/speech_transcription_port.dart';

/// Contrato de `SpeechTranscriptionPort`.
///
/// Se prueba contra el fake, que comparte con los adaptadores reales la misma
/// máquina de estados (`BaseSpeechTranscriptionPort`). Por eso estas pruebas
/// valen para el motor de Android y para Whisper: lo que se verifica aquí es el
/// ciclo de vida, no el reconocimiento.
void main() {
  late FakeSpeechTranscriptionPort port;
  late List<TranscriptionEvent> seen;

  setUp(() {
    port = FakeSpeechTranscriptionPort();
    seen = <TranscriptionEvent>[];
    port.events.listen(seen.add);
  });

  tearDown(() async => port.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('sesión normal', () {
    test('emite parciales y luego el resultado final', () async {
      await port.start(const TranscriptionRequest());
      await settle();

      expect(seen.whereType<TranscriptionPartial>().map((e) => e.text), [
        'registrar',
        'registrar compra',
      ]);

      await port.stop();
      await settle();

      final result = seen.whereType<TranscriptionFinal>().single;
      expect(result.text, 'registrar compra de cincuenta litros');
      expect(port.state, TranscriptionState.preview);
    });

    test('al terminar deja el micrófono libre', () async {
      await port.start(const TranscriptionRequest());
      await port.stop();
      await settle();

      expect(port.microphoneReleased, isTrue);
    });
  });

  group('doble inicio', () {
    test('no abre una segunda captura y avisa que está ocupado', () async {
      await port.start(const TranscriptionRequest());
      await port.start(const TranscriptionRequest());
      await settle();

      expect(port.startCount, 1, reason: 'el motor sólo debe arrancar una vez');
      expect(
        seen.whereType<TranscriptionFailed>().single.code,
        TranscriptionErrorCode.busy,
      );
    });

    test('la sesión original sigue viva tras el segundo toque', () async {
      await port.start(const TranscriptionRequest());
      await port.start(const TranscriptionRequest());
      await port.stop();
      await settle();

      expect(seen.whereType<TranscriptionFinal>(), hasLength(1));
    });
  });

  group('cancelación', () {
    test('descarta la sesión sin producir resultado final', () async {
      await port.start(const TranscriptionRequest());
      await port.cancel();
      await settle();

      expect(seen.whereType<TranscriptionFinal>(), isEmpty);
      expect(port.state, TranscriptionState.cancelled);
      expect(port.microphoneReleased, isTrue);
      expect(port.calls, contains('cancel'));
    });

    test('cancelar sin sesión abierta no toca el motor', () async {
      await port.cancel();
      await settle();

      expect(port.calls, isNot(contains('cancel')));
      expect(port.state, TranscriptionState.cancelled);
    });
  });

  group('permisos', () {
    test('denegación temporal deja la sesión en denied', () async {
      port.scenario = FakeScenario.permissionDenied;
      await port.start(const TranscriptionRequest());
      await settle();

      expect(
        seen.whereType<TranscriptionFailed>().single.code,
        TranscriptionErrorCode.permissionDenied,
      );
      expect(port.state, TranscriptionState.denied);
      expect(port.microphoneReleased, isTrue);
    });

    test('denegación permanente también libera el micrófono', () async {
      port.scenario = const FakeScenario(
        failWith: TranscriptionErrorCode.permissionPermanentlyDenied,
      );
      await port.start(const TranscriptionRequest());
      await settle();

      expect(port.state, TranscriptionState.denied);
      expect(port.microphoneReleased, isTrue);
    });
  });

  group('servicio y locale', () {
    test('servicio ausente deja la sesión en unavailable', () async {
      port.scenario = FakeScenario.serviceUnavailable;
      await port.start(const TranscriptionRequest());
      await settle();

      expect(port.state, TranscriptionState.unavailable);
    });

    test(
      'locale no disponible es un estado distinto de un error genérico',
      () async {
        port.scenario = const FakeScenario(
          failWith: TranscriptionErrorCode.localeUnavailable,
        );
        await port.start(const TranscriptionRequest(locale: 'es-BO'));
        await settle();

        expect(
          seen.whereType<TranscriptionFailed>().single.code,
          TranscriptionErrorCode.localeUnavailable,
        );
        expect(port.state, TranscriptionState.unavailable);
      },
    );

    test(
      'la disponibilidad distingue el locale pedido del realmente usado',
      () async {
        port.scenario = const FakeScenario(
          availability: TranscriptionAvailability(
            available: true,
            onDeviceAvailable: true,
            requestedLocale: 'es-BO',
            effectiveLocale: 'es-ES',
            installedLocales: ['es-ES'],
            supportedLocales: ['es-ES', 'es-US'],
            requiresNetwork: false,
          ),
        );
        final availability = await port.checkAvailability('es-BO');

        expect(availability.localeIsFallback, isTrue);
        expect(availability.effectiveLocale, 'es-ES');
      },
    );
  });

  group('modo avión', () {
    test('un motor que necesitaba red falla con networkRequired', () async {
      port.scenario = FakeScenario.airplaneMode;
      await port.start(const TranscriptionRequest());
      await settle();

      expect(
        seen.whereType<TranscriptionFailed>().single.code,
        TranscriptionErrorCode.networkRequired,
      );
      expect(port.microphoneReleased, isTrue);
    });
  });

  group('timeout', () {
    test(
      'una sesión que nunca termina se corta y suelta el micrófono',
      () async {
        port.scenario = const FakeScenario(
          partials: ['algo'],
          autoFinalize: false,
        );
        await port.start(
          const TranscriptionRequest(maxDuration: Duration(milliseconds: 30)),
        );
        await port.stop();
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(
          seen.whereType<TranscriptionFailed>().single.code,
          TranscriptionErrorCode.timeout,
        );
        expect(port.microphoneReleased, isTrue);
        expect(port.calls, contains('cancel'));
      },
    );
  });

  group('lifecycle', () {
    test('pasar a segundo plano cancela y libera el micrófono', () async {
      await port.start(const TranscriptionRequest());
      await port.simulateBackground();
      await settle();

      expect(port.state, TranscriptionState.cancelled);
      expect(port.microphoneReleased, isTrue);
      expect(seen.whereType<TranscriptionFinal>(), isEmpty);
    });

    test(
      'una interrupción del sistema termina la sesión sin resultado',
      () async {
        await port.start(const TranscriptionRequest());
        port.simulateInterruption();
        await settle();

        expect(port.state, TranscriptionState.error);
        expect(port.microphoneReleased, isTrue);
        expect(seen.whereType<TranscriptionFinal>(), isEmpty);
      },
    );

    test('dispose libera recursos y es idempotente', () async {
      await port.start(const TranscriptionRequest());
      await port.dispose();
      await port.dispose();

      expect(
        port.calls.where((c) => c == 'dispose'),
        hasLength(1),
        reason: 'liberar dos veces no debe llegar dos veces al motor',
      );
      expect(port.microphoneReleased, isTrue);
    });

    test(
      'start después de dispose falla en vez de reabrir el micrófono',
      () async {
        await port.dispose();

        expect(
          () => port.start(const TranscriptionRequest()),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('los eventos posteriores a dispose no se publican', () async {
      await port.start(const TranscriptionRequest());
      await port.dispose();
      final before = seen.length;
      port.simulateInterruption();
      await settle();

      expect(seen.length, before);
    });
  });

  group('privacidad de los eventos', () {
    test('el texto dictado nunca aparece al describir un evento', () {
      const secreto = 'pago para Juan Pérez de dos mil bolivianos';

      expect(
        const TranscriptionPartial(secreto, elapsed: Duration.zero).toString(),
        isNot(contains('Juan')),
      );
      expect(
        const TranscriptionFinal(secreto, elapsed: Duration.zero).toString(),
        isNot(contains('bolivianos')),
      );
    });

    test('un fallo describe el código técnico, no la frase', () {
      const failure = TranscriptionFailed(
        TranscriptionErrorCode.engineFailure,
        detail: 'android-error-5',
      );

      expect(failure.toString(), contains('android-error-5'));
      expect(failure.toString(), isNot(contains('compra')));
    });
  });
}
