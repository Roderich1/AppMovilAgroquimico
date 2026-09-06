import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_speech_transcription_port.dart';

/// Contrato de `SpeechTranscriptionPort`.
///
/// Se prueba contra el fake determinista. Lo que se verifica aquí es el **ciclo
/// de vida del turno** —quién abre el micrófono, quién lo suelta y qué eventos
/// llegan en qué orden—, no el reconocimiento, que pertenece al motor y está
/// medido en `ADR-002` sobre hardware físico.
///
/// Todo adaptador nuevo debe pasar este archivo antes de sustituir al de
/// Android. Es la defensa contra `RISK-007`: que el fake y el dispositivo se
/// comporten distinto.
void main() {
  late FakeSpeechTranscriptionPort port;
  late List<TranscriptionEvent> seen;

  void listen(FakeSpeechTranscriptionPort target) {
    port = target;
    seen = <TranscriptionEvent>[];
    port.events.listen(seen.add);
    addTearDown(port.dispose);
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  const request = TranscriptionRequest(locale: 'es-BO');

  List<T> eventsOf<T>() => seen.whereType<T>().toList();

  group('turno normal', () {
    test('emite parciales, luego el segmento y cierra el turno', () async {
      listen(FakeSpeechTranscriptionPort(script: const [FakeTurn.ok]));
      await port.start(request);
      await settle();

      expect(eventsOf<TranscriptionPartial>().map((e) => e.text), [
        'registrar',
        'registrar compra',
      ]);
      expect(
        eventsOf<TranscriptionSegment>().single.text,
        'registrar compra de cincuenta litros',
      );
      expect(
        eventsOf<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.segment,
      );
    });

    test('anuncia el locale que aceptó, no el que se le pidió', () async {
      listen(
        FakeSpeechTranscriptionPort(
          script: const [FakeTurn(segment: 'ok', acceptsLocale: 'es-US')],
        ),
      );
      await port.start(request.withLocale('es-US'));
      await settle();

      expect(eventsOf<TranscriptionLocaleInUse>().single.locale, 'es-US');
    });

    test('al terminar deja el micrófono libre', () async {
      listen(FakeSpeechTranscriptionPort(script: const [FakeTurn.ok]));
      await port.start(request);
      await settle();

      expect(port.microphoneReleased, isTrue);
    });

    test('todo turno abierto termina con exactamente un cierre', () async {
      listen(FakeSpeechTranscriptionPort(script: const [FakeTurn.ok]));
      await port.start(request);
      await settle();

      expect(eventsOf<TranscriptionTurnEnded>(), hasLength(1));
    });
  });

  group('doble inicio', () {
    test('no abre una segunda captura y avisa que está ocupado', () async {
      listen(
        FakeSpeechTranscriptionPort(script: const [FakeTurn(silent: true)]),
      );
      await port.start(request);
      await port.start(request);
      await settle();

      expect(port.startRequests, hasLength(1));
      expect(
        eventsOf<TranscriptionFailed>().single.code,
        TranscriptionErrorCode.busy,
      );
    });

    test('el turno original sigue vivo tras el segundo toque', () async {
      listen(
        FakeSpeechTranscriptionPort(
          script: const [FakeTurn(segment: 'uno', endsOnStop: true)],
        ),
      );
      await port.start(request);
      await port.start(request);
      await port.stop();
      await settle();

      expect(eventsOf<TranscriptionSegment>(), hasLength(1));
    });
  });

  group('sin resultado', () {
    test('noMatch cierra el turno sin texto', () async {
      listen(
        FakeSpeechTranscriptionPort(script: const [FakeTurn(noMatch: true)]),
      );
      await port.start(request);
      await settle();

      expect(eventsOf<TranscriptionNoMatch>(), hasLength(1));
      expect(eventsOf<TranscriptionSegment>(), isEmpty);
      expect(
        eventsOf<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.noMatch,
      );
      expect(port.microphoneReleased, isTrue);
    });

    test('timeout cierra el turno y libera el micrófono', () async {
      listen(
        FakeSpeechTranscriptionPort(script: const [FakeTurn(timeout: true)]),
      );
      await port.start(request);
      await settle();

      expect(eventsOf<TranscriptionTimeout>(), hasLength(1));
      expect(port.microphoneReleased, isTrue);
    });
  });

  group('errores', () {
    test('un fallo cierra el turno y suelta el micrófono', () async {
      listen(
        FakeSpeechTranscriptionPort(
          script: const [
            FakeTurn(
              failWith: TranscriptionErrorCode.engineFailure,
              failDetail: 'android-error-8',
            ),
          ],
        ),
      );
      await port.start(request);
      await settle();

      final failure = eventsOf<TranscriptionFailed>().single;
      expect(failure.code, TranscriptionErrorCode.engineFailure);
      expect(failure.detail, 'android-error-8');
      expect(
        eventsOf<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.error,
      );
      expect(port.microphoneReleased, isTrue);
    });

    test('un locale no soportado falla sin abrir la escucha', () async {
      listen(
        FakeSpeechTranscriptionPort(
          script: const [FakeTurn(acceptsLocale: 'es-US', segment: 'x')],
        ),
      );
      await port.start(request.withLocale('es-BO'));
      await settle();

      expect(
        eventsOf<TranscriptionFailed>().single.code,
        TranscriptionErrorCode.localeUnavailable,
      );
      expect(eventsOf<TranscriptionStageChanged>(), isEmpty);
    });

    test('los códigos de permiso e idioma son fatales; el resto no', () {
      expect(TranscriptionErrorCode.permissionDenied.isFatal, isTrue);
      expect(
        TranscriptionErrorCode.permissionPermanentlyDenied.isFatal,
        isTrue,
      );
      expect(TranscriptionErrorCode.recognizerUnavailable.isFatal, isTrue);
      expect(TranscriptionErrorCode.localeUnavailable.isFatal, isTrue);
      expect(TranscriptionErrorCode.clientError.isFatal, isFalse);
      expect(TranscriptionErrorCode.engineFailure.isFatal, isFalse);
      expect(TranscriptionErrorCode.networkRequired.isFatal, isFalse);
    });
  });

  group('demora e interrupción', () {
    test('un turno con demora no entrega nada antes de tiempo', () async {
      listen(
        FakeSpeechTranscriptionPort(
          script: const [
            FakeTurn(segment: 'tarde', delay: Duration(milliseconds: 40)),
          ],
        ),
      );
      await port.start(request);
      await settle();
      expect(eventsOf<TranscriptionSegment>(), isEmpty);
      expect(port.isTurnOpen, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(eventsOf<TranscriptionSegment>(), hasLength(1));
    });

    test('cancelar durante la demora no entrega el resultado', () async {
      listen(
        FakeSpeechTranscriptionPort(
          script: const [
            FakeTurn(segment: 'tarde', delay: Duration(milliseconds: 40)),
          ],
        ),
      );
      await port.start(request);
      await port.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(eventsOf<TranscriptionSegment>(), isEmpty);
      expect(port.microphoneReleased, isTrue);
    });
  });

  group('cancelación', () {
    test('descarta el turno sin producir segmento', () async {
      listen(
        FakeSpeechTranscriptionPort(
          script: const [FakeTurn(segment: 'x', endsOnStop: true)],
        ),
      );
      await port.start(request);
      await port.cancel();
      await settle();

      expect(eventsOf<TranscriptionSegment>(), isEmpty);
      expect(eventsOf<TranscriptionCancelled>(), hasLength(1));
      expect(
        eventsOf<TranscriptionTurnEnded>().single.reason,
        TranscriptionEndReason.cancelled,
      );
      expect(port.microphoneReleased, isTrue);
    });

    test('cancelar sin turno abierto no rompe nada', () async {
      listen(FakeSpeechTranscriptionPort());
      await port.cancel();
      await settle();

      expect(eventsOf<TranscriptionTurnEnded>(), isEmpty);
      expect(port.microphoneReleased, isTrue);
    });
  });

  group('servicio muerto', () {
    test('sin callback el turno queda abierto y cancelar lo cierra', () async {
      listen(
        FakeSpeechTranscriptionPort(script: const [FakeTurn(silent: true)]),
      );
      await port.start(request);
      await settle();

      expect(port.isTurnOpen, isTrue);
      expect(eventsOf<TranscriptionTurnEnded>(), isEmpty);

      await port.cancel();
      expect(port.microphoneReleased, isTrue);
    });

    test(
      'dispose sobre un turno muerto libera igualmente el micrófono',
      () async {
        final target = FakeSpeechTranscriptionPort(
          script: const [FakeTurn(silent: true)],
        );
        listen(target);
        await port.start(request);
        await port.dispose();

        expect(port.microphoneReleased, isTrue);
      },
    );
  });

  group('dispose', () {
    test('es idempotente', () async {
      listen(FakeSpeechTranscriptionPort());
      await port.dispose();
      await port.dispose();

      expect(port.calls.where((c) => c == 'dispose'), hasLength(1));
    });

    test('arrancar tras dispose es un error de programación', () async {
      listen(FakeSpeechTranscriptionPort());
      await port.dispose();

      expect(() => port.start(request), throwsStateError);
    });
  });

  group('privacidad de los eventos', () {
    test('ningún evento imprime lo dictado en su descripción', () async {
      listen(
        FakeSpeechTranscriptionPort(
          script: const [
            FakeTurn(
              partials: ['compra de urea'],
              segment: 'compra de urea para José',
            ),
          ],
        ),
      );
      await port.start(request);
      await settle();

      for (final event in seen) {
        expect(event.toString(), isNot(contains('urea')));
        expect(event.toString(), isNot(contains('José')));
      }
    });

    test('la disponibilidad tampoco expone contenido', () async {
      listen(FakeSpeechTranscriptionPort());
      final availability = await port.checkAvailability('es-BO');

      expect(availability.toString(), contains('recognizer='));
      expect(availability.toString(), isNot(contains('urea')));
    });
  });
}
