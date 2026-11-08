import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/session/voice_continuity_policy.dart';
import 'package:agroquimicos/voice/session/voice_session_controller.dart';
import 'package:agroquimicos/voice/session/voice_session_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_speech_transcription_port.dart';

/// #119 (F09-D1): «Reintento tras denegar micrófono queda atascado en
/// apertura».
///
/// Aceptación del issue: denegar, reintentar, denegación permanente, cancelar
/// durante la apertura y callback tardío, **sin estado indefinido ni escucha
/// ficticia**; conceder mediante el sistema y volver abre el motor sin perder
/// el texto.
///
/// Todo contra el fake determinista: sin micrófono, sin diálogo real y sin
/// teléfono. Lo que esto prueba es la política de sesión; el lado nativo se
/// prueba aparte (`*_adapter_test.dart`) y en el teléfono queda pendiente.
void main() {
  const instant = VoiceContinuityPolicy(
    initialBackoff: Duration.zero,
    maxBackoff: Duration.zero,
  );

  late FakeSpeechTranscriptionPort port;
  late VoiceSessionController controller;

  VoiceSessionController build(
    List<FakeTurn> script, {
    VoiceContinuityPolicy continuity = instant,
  }) {
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
    controller = VoiceSessionController(port: port, continuity: continuity);
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> settle([int turns = 12]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Estados en los que la pantalla dice que se está abriendo o escuchando.
  bool looksOpen(VoiceSessionStatus s) =>
      s.microphoneMayBeOpen || s == VoiceSessionStatus.requestingPermission;

  group('denegar y reintentar', () {
    test('denegar, reintentar y conceder: el motor se abre y el texto se '
        'conserva', () async {
      build(const [
        FakeTurn(awaitsPermission: true),
        FakeTurn(awaitsPermission: true, segment: 'dos litros'),
      ]);
      controller.editText('lo escrito a mano');

      await controller.startListening();
      await settle();
      expect(
        controller.snapshot.status,
        VoiceSessionStatus.requestingPermission,
      );
      port.denyPermission();
      await settle();
      expect(controller.snapshot.status, VoiceSessionStatus.permissionDenied);
      expect(port.microphoneReleased, isTrue);

      // Segundo toque: el sistema vuelve a preguntar y esta vez se concede.
      await controller.retry();
      await settle();
      expect(
        controller.snapshot.status,
        VoiceSessionStatus.requestingPermission,
        reason: 'el segundo toque vuelve a pedir el permiso',
      );
      port.grantPermission();
      await settle(30);

      expect(port.startRequests, hasLength(greaterThanOrEqualTo(2)));
      expect(controller.snapshot.committedText, 'lo escrito a mano dos litros');
      expect(looksOpen(controller.snapshot.status), isFalse);
      expect(port.microphoneReleased, isTrue);
    });

    test('denegación permanente: ajustes, volver y reintentar', () async {
      build(const [
        FakeTurn(awaitsPermission: true),
        FakeTurn(segment: 'cinco kilos'),
      ]);
      await controller.startListening();
      await settle();
      port.denyPermission(permanent: true);
      await settle();
      expect(
        controller.snapshot.status,
        VoiceSessionStatus.permissionPermanentlyDenied,
      );

      // Ir a los ajustes pone la app en segundo plano: no debe cambiar nada.
      expect(await controller.openSystemSettings(), isTrue);
      await controller.handleAppPaused();
      await settle();
      expect(
        controller.snapshot.status,
        VoiceSessionStatus.permissionPermanentlyDenied,
      );
      expect(port.calls, isNot(contains('cancel')));

      // De vuelta con el permiso concedido en los ajustes.
      await controller.retry();
      await settle(30);
      expect(controller.snapshot.committedText, 'cinco kilos');
      expect(controller.snapshot.errorCode, isNull);
    });
  });

  group('cancelar durante la apertura', () {
    test('mientras el sistema pregunta: se cancela, no se pide un final, y '
        'conceder después no abre nada', () async {
      build(const [FakeTurn(awaitsPermission: true, segment: 'no')]);
      controller.editText('texto previo');
      await controller.startListening();
      await settle();
      expect(
        controller.snapshot.status,
        VoiceSessionStatus.requestingPermission,
      );

      await controller.stopListening();
      await settle();

      expect(port.calls, contains('cancel'));
      expect(port.calls, isNot(contains('stop')));
      expect(controller.snapshot.status, VoiceSessionStatus.preview);
      expect(controller.snapshot.committedText, 'texto previo');
      expect(port.isTurnOpen, isFalse);

      // El diálogo se contesta tarde: el turno ya no existe.
      port.grantPermission();
      await settle();
      expect(controller.snapshot.status, VoiceSessionStatus.preview);
      expect(port.microphoneReleased, isTrue);
      expect(port.startRequests, hasLength(1));
    });

    test('con el motor sin contestar: detener cancela y no queda en '
        '«Deteniendo»', () async {
      build(const [FakeTurn(unresponsive: true)]);
      await controller.startListening();
      await settle();
      expect(controller.snapshot.status, VoiceSessionStatus.starting);

      await controller.stopListening();
      await settle();

      expect(controller.snapshot.status, VoiceSessionStatus.preview);
      expect(port.isTurnOpen, isFalse);
      expect(port.microphoneReleased, isTrue);
    });

    test(
      'un evento tardío de la apertura cancelada no reenciende nada',
      () async {
        build(const [FakeTurn(unresponsive: true)]);
        await controller.startListening();
        await settle();
        await controller.stopListening();
        await settle();

        port.emitForTest(
          const TranscriptionStageChanged(TranscriptionStage.listening),
        );
        port.emitForTest(
          const TranscriptionSegment('tarde', elapsed: Duration.zero),
        );
        await settle();

        expect(controller.snapshot.status, VoiceSessionStatus.preview);
        expect(controller.snapshot.committedText, isEmpty);
      },
    );
  });

  group('apertura sin respuesta', () {
    test(
      'termina en un error explicado, suelta el motor y deja reintentar',
      () {
        fakeAsync((async) {
          build(const [
            FakeTurn(unresponsive: true),
            FakeTurn(segment: 'ahora sí'),
          ]);
          final seen = <VoiceSessionStatus>[];
          controller.addListener(() => seen.add(controller.snapshot.status));

          controller.startListening();
          async.flushMicrotasks();
          expect(controller.snapshot.status, VoiceSessionStatus.starting);

          async.elapse(instant.openTimeout - const Duration(seconds: 1));
          expect(controller.snapshot.status, VoiceSessionStatus.starting);

          async.elapse(const Duration(seconds: 2));
          expect(
            controller.snapshot.status,
            VoiceSessionStatus.recoverableError,
          );
          expect(
            controller.snapshot.errorCode,
            TranscriptionErrorCode.engineFailure,
          );
          expect(
            controller.snapshot.errorDetail,
            VoiceSessionController.openTimeoutDetail,
          );
          expect(port.calls, contains('cancel'));
          expect(port.isTurnOpen, isFalse);
          expect(port.microphoneReleased, isTrue);

          // Nada se reabre por su cuenta.
          final starts = port.startRequests.length;
          async.elapse(const Duration(minutes: 2));
          expect(port.startRequests, hasLength(starts));

          controller.retry();
          async.elapse(const Duration(milliseconds: 10));
          expect(controller.snapshot.committedText, 'ahora sí');
        });
      },
    );

    test('una consulta de disponibilidad que no vuelve también vence', () {
      fakeAsync((async) {
        build(const [FakeTurn.ok]);
        port.availabilityHangs = true;
        controller.startListening();
        async.flushMicrotasks();
        expect(controller.snapshot.status, VoiceSessionStatus.starting);

        async.elapse(instant.openTimeout + const Duration(seconds: 1));
        expect(controller.snapshot.status, VoiceSessionStatus.recoverableError);
        expect(port.startRequests, isEmpty);
      });
    });

    test('esperar el permiso no tiene plazo (DEFECTO-005)', () {
      fakeAsync((async) {
        build(const [FakeTurn(awaitsPermission: true, segment: 'tres')]);
        controller.startListening();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 3));
        expect(
          controller.snapshot.status,
          VoiceSessionStatus.requestingPermission,
        );
        port.grantPermission();
        async.elapse(const Duration(milliseconds: 10));
        expect(controller.snapshot.committedText, 'tres');
      });
    });

    test('un motor que escucha no vence por este plazo', () {
      fakeAsync((async) {
        build(const [FakeTurn(silent: true)]);
        controller.startListening();
        async.flushMicrotasks();
        expect(controller.snapshot.status, VoiceSessionStatus.listening);
        async.elapse(instant.openTimeout * 2);
        expect(controller.snapshot.errorCode, isNull);
      });
    });
  });

  group('callback tardío', () {
    test(
      'un fallo suelto de un turno ya cerrado no decide el siguiente',
      () async {
        build(
          const [FakeTurn(segment: 'diez litros')],
          continuity: const VoiceContinuityPolicy(
            initialBackoff: Duration.zero,
            maxBackoff: Duration.zero,
            maxConsecutiveUnproductive: 1,
          ),
        );
        // Llega un error de un turno que ya terminó, sin cierre propio.
        port.emitForTest(
          const TranscriptionFailed(TranscriptionErrorCode.clientError),
        );
        await settle();

        await controller.startListening();
        await settle(30);

        expect(controller.snapshot.committedText, 'diez litros');
        expect(controller.snapshot.errorCode, isNull);
        expect(controller.snapshot.status, VoiceSessionStatus.preview);
      },
    );
  });
}
