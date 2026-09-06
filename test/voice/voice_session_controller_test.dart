import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/session/voice_continuity_policy.dart';
import 'package:agroquimicos/voice/session/voice_locale_policy.dart';
import 'package:agroquimicos/voice/session/voice_session_controller.dart';
import 'package:agroquimicos/voice/session/voice_session_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_speech_transcription_port.dart';

/// Máquina de estados de la sesión de dictado de `EVO-009`.
///
/// Todo se prueba contra el fake determinista: aquí no hay micrófono, ni hilo
/// nativo, ni teléfono. Lo que se verifica es la **política de sesión**
/// —continuidad, acumulación, edición, ciclo de vida y límites de reintento—,
/// no el reconocimiento, que es del motor y está medido en `ADR-002`.
void main() {
  /// Continuidad sin esperas: el backoff tiene su propia prueba con
  /// `fake_async`. Aquí interesa la decisión, no el reloj.
  const instant = VoiceContinuityPolicy(
    initialBackoff: Duration.zero,
    maxBackoff: Duration.zero,
  );

  late FakeSpeechTranscriptionPort port;
  late VoiceSessionController controller;

  VoiceSessionController build({
    List<FakeTurn>? script,
    bool repeatLast = true,
    VoiceContinuityPolicy continuity = instant,
    TranscriptionAvailability? availability,
  }) {
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: repeatLast);
    if (availability != null) port.availability = availability;
    controller = VoiceSessionController(port: port, continuity: continuity);
    addTearDown(controller.dispose);
    return controller;
  }

  /// Deja correr la cola de microtareas y los `Timer` de duración cero.
  ///
  /// La continuidad encadena turnos, así que hace falta más de una vuelta.
  Future<void> settle([int turns = 8]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('estado inicial', () {
    test('empieza en idle, sin texto y sin micrófono tomado', () {
      build();
      expect(controller.snapshot.status, VoiceSessionStatus.idle);
      expect(controller.snapshot.committedText, isEmpty);
      expect(controller.snapshot.partialText, isEmpty);
      expect(controller.snapshot.delivered, isNull);
      expect(port.microphoneReleased, isTrue);
    });

    test('el locale pedido es el del producto y el usado aún se desconoce', () {
      build();
      expect(controller.snapshot.requestedLocale, VoiceLocalePolicy.requested);
      expect(controller.snapshot.localeInUse, isNull);
    });
  });

  group('parcial y segmento final', () {
    test(
      'el parcial se muestra aparte y no entra en el texto de sesión',
      () async {
        build(
          script: [
            const FakeTurn(partials: ['reg', 'registrar'], endsOnStop: true),
          ],
        );
        await controller.startListening();
        await settle();

        expect(controller.snapshot.status, VoiceSessionStatus.listening);
        expect(controller.snapshot.partialText, 'registrar');
        expect(controller.snapshot.committedText, isEmpty);
      },
    );

    test('el segmento final se acumula y limpia el parcial', () async {
      build(
        script: [
          const FakeTurn(partials: ['reg'], segment: 'hola', endsOnStop: true),
        ],
      );
      await controller.startListening();
      await settle();
      await controller.stopListening();
      await settle();

      expect(controller.snapshot.committedText, 'hola');
      expect(controller.snapshot.partialText, isEmpty);
      expect(controller.snapshot.segmentCount, 1);
      expect(controller.snapshot.status, VoiceSessionStatus.preview);
    });

    test('varios segmentos se acumulan separados por un espacio', () async {
      build(
        script: const [
          FakeTurn(segment: 'primero'),
          FakeTurn(segment: 'segundo'),
          FakeTurn(segment: 'tercero', endsOnStop: true),
        ],
        repeatLast: false,
      );
      await controller.startListening();
      await settle();

      expect(controller.snapshot.committedText, 'primero segundo');
      expect(controller.snapshot.segmentCount, 2);
    });

    test('un segundo evento en el mismo turno no duplica el segmento', () async {
      build(script: [const FakeTurn(segment: 'uno', endsOnStop: true)]);
      await controller.startListening();
      await settle();
      // El motor repite el resultado del turno ya cerrado: Android lo hace tras
      // `onResults` en algunos aparatos. No puede sumarse dos veces.
      port.emitForTest(
        const TranscriptionSegment('uno', elapsed: Duration.zero),
      );
      await settle();

      expect(controller.snapshot.committedText, 'uno');
      expect(controller.snapshot.segmentCount, 1);
    });
  });

  group('continuidad controlada', () {
    test(
      'tras un segmento la sesión vuelve a escuchar sin perder texto',
      () async {
        build(
          script: const [
            FakeTurn(segment: 'primero'),
            FakeTurn(segment: 'segundo', endsOnStop: true),
          ],
          repeatLast: false,
        );
        await controller.startListening();
        await settle();

        expect(
          port.startRequests,
          hasLength(2),
          reason: 'el motor cierra el turno solo; la sesión debe reabrirlo',
        );
        expect(controller.snapshot.committedText, 'primero');
        expect(controller.snapshot.status, VoiceSessionStatus.listening);
      },
    );

    test('detener no reabre ningún turno', () async {
      build(script: [const FakeTurn(segment: 'uno', endsOnStop: true)]);
      await controller.startListening();
      await settle();
      await controller.stopListening();
      await settle();

      expect(port.startRequests, hasLength(1));
      expect(controller.snapshot.status, VoiceSessionStatus.preview);
      expect(port.microphoneReleased, isTrue);
    });

    test(
      'seguir hablando abre un turno nuevo y conserva lo acumulado',
      () async {
        build(
          script: const [
            FakeTurn(segment: 'uno', endsOnStop: true),
            FakeTurn(segment: 'dos', endsOnStop: true),
          ],
          repeatLast: false,
        );
        await controller.startListening();
        await settle();
        await controller.stopListening();
        await settle();

        await controller.startListening();
        await settle();
        await controller.stopListening();
        await settle();

        expect(controller.snapshot.committedText, 'uno dos');
        expect(controller.snapshot.segmentCount, 2);
      },
    );

    test(
      'noMatch repetido se detiene en el máximo y no entra en bucle',
      () async {
        build(script: const [FakeTurn(noMatch: true)]);
        await controller.startListening();
        await settle(20);

        expect(
          port.startRequests,
          hasLength(instant.maxConsecutiveUnproductive),
        );
        expect(controller.snapshot.status, VoiceSessionStatus.preview);
        expect(
          controller.snapshot.lastEndReason,
          TranscriptionEndReason.noMatch,
        );
        expect(port.microphoneReleased, isTrue);
      },
    );

    test('timeout repetido también se detiene en el máximo', () async {
      build(script: const [FakeTurn(timeout: true)]);
      await controller.startListening();
      await settle(20);

      expect(port.startRequests, hasLength(instant.maxConsecutiveUnproductive));
      expect(controller.snapshot.status, VoiceSessionStatus.preview);
    });

    test('ERROR_CLIENT repetido no reintenta indefinidamente', () async {
      build(
        script: const [
          FakeTurn(
            failWith: TranscriptionErrorCode.clientError,
            failDetail: 'android-error-5',
          ),
        ],
      );
      await controller.startListening();
      await settle(20);

      expect(port.startRequests, hasLength(instant.maxConsecutiveUnproductive));
      expect(controller.snapshot.status, VoiceSessionStatus.recoverableError);
      expect(controller.snapshot.errorCode, TranscriptionErrorCode.clientError);
    });

    test('un turno productivo reinicia el contador de improductivos', () async {
      build(
        script: const [
          FakeTurn(noMatch: true),
          FakeTurn(noMatch: true),
          FakeTurn(segment: 'sí hubo texto'),
          FakeTurn(noMatch: true),
          FakeTurn(noMatch: true),
          FakeTurn(segment: 'y más texto', endsOnStop: true),
        ],
        repeatLast: false,
      );
      await controller.startListening();
      await settle(20);

      expect(controller.snapshot.committedText, 'sí hubo texto');
      expect(controller.snapshot.status, VoiceSessionStatus.listening);
    });

    test('el backoff crece de forma acotada entre turnos improductivos', () {
      fakeAsync((async) {
        const policy = VoiceContinuityPolicy(
          initialBackoff: Duration(milliseconds: 400),
          maxBackoff: Duration(milliseconds: 1600),
          maxConsecutiveUnproductive: 4,
        );
        final localPort = FakeSpeechTranscriptionPort(
          script: const [FakeTurn(noMatch: true)],
        );
        final local = VoiceSessionController(
          port: localPort,
          continuity: policy,
        );

        local.startListening();
        async.flushMicrotasks();
        expect(localPort.startRequests, hasLength(1));

        // Primer reintento: 400 ms. Antes de eso no se toca el micrófono.
        async.elapse(const Duration(milliseconds: 399));
        async.flushMicrotasks();
        expect(localPort.startRequests, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(localPort.startRequests, hasLength(2));

        // Segundo: 800 ms.
        async.elapse(const Duration(milliseconds: 799));
        async.flushMicrotasks();
        expect(localPort.startRequests, hasLength(2));
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(localPort.startRequests, hasLength(3));

        // Tercero: 1600 ms, ya en el tope.
        async.elapse(const Duration(milliseconds: 1600));
        async.flushMicrotasks();
        expect(localPort.startRequests, hasLength(4));

        // Alcanzado el máximo, no hay un quinto turno por mucho que pase.
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(localPort.startRequests, hasLength(4));

        local.dispose();
        async.flushMicrotasks();
      });
    });

    test('el backoff nunca supera el tope configurado', () {
      const policy = VoiceContinuityPolicy(
        initialBackoff: Duration(milliseconds: 400),
        maxBackoff: Duration(milliseconds: 1600),
      );
      expect(policy.backoffFor(1), const Duration(milliseconds: 400));
      expect(policy.backoffFor(2), const Duration(milliseconds: 800));
      expect(policy.backoffFor(3), const Duration(milliseconds: 1600));
      expect(policy.backoffFor(9), const Duration(milliseconds: 1600));
    });
  });

  group('permiso', () {
    test('denegación temporal deja permissionDenied y no reintenta', () async {
      build(
        script: const [
          FakeTurn(failWith: TranscriptionErrorCode.permissionDenied),
        ],
      );
      await controller.startListening();
      await settle(20);

      expect(controller.snapshot.status, VoiceSessionStatus.permissionDenied);
      expect(port.startRequests, hasLength(1));
      expect(port.microphoneReleased, isTrue);
    });

    test('denegación permanente ofrece los ajustes del sistema', () async {
      build(
        script: const [
          FakeTurn(
            failWith: TranscriptionErrorCode.permissionPermanentlyDenied,
          ),
        ],
      );
      await controller.startListening();
      await settle();

      expect(
        controller.snapshot.status,
        VoiceSessionStatus.permissionPermanentlyDenied,
      );
      await controller.openSystemSettings();
      expect(port.openSettingsCalls, 1);
    });

    test(
      'el estado pasa por requestingPermission cuando el sistema pregunta',
      () async {
        build(script: [const FakeTurn(silent: true)]);
        final seen = <VoiceSessionStatus>[];
        controller.addListener(() => seen.add(controller.snapshot.status));

        final started = controller.startListening();
        port.emitForTest(
          const TranscriptionStageChanged(
            TranscriptionStage.awaitingPermission,
          ),
        );
        await started;
        await settle();

        expect(seen, contains(VoiceSessionStatus.requestingPermission));
      },
    );
  });

  group('idioma', () {
    test('recorre la lista de fallback y publica el que funciona', () async {
      build(
        script: const [
          FakeTurn(acceptsLocale: 'es-PE', segment: 'listo', endsOnStop: true),
        ],
      );
      await controller.startListening();
      await settle(20);

      expect(port.attemptedLocales.take(3), ['es-BO', 'es-419', 'es-PE']);
      expect(controller.snapshot.localeInUse, 'es-PE');
      expect(controller.snapshot.requestedLocale, 'es-BO');
      expect(controller.snapshot.localeIsFallback, isTrue);
    });

    test('no fija es-US: lo intenta sólo cuando le toca en la lista', () async {
      build(
        script: const [
          FakeTurn(acceptsLocale: 'es-US', segment: 'ok', endsOnStop: true),
        ],
      );
      await controller.startListening();
      await settle(30);

      expect(port.attemptedLocales.first, 'es-BO');
      expect(port.attemptedLocales, contains('es-US'));
      expect(controller.snapshot.localeInUse, 'es-US');
    });

    test('si ningún español sirve, el estado es languageUnavailable', () async {
      build(
        script: const [
          FakeTurn(failWith: TranscriptionErrorCode.localeUnavailable),
        ],
      );
      await controller.startListening();
      await settle(40);

      expect(
        controller.snapshot.status,
        VoiceSessionStatus.languageUnavailable,
      );
      expect(port.attemptedLocales, VoiceLocalePolicy.candidates);
      expect(
        controller.snapshot.offline.languageModelPossiblyMissing,
        isTrue,
        reason: 'error 13 significa que puede faltar el modelo del idioma',
      );
    });

    test('los idiomas instalados adelantan al candidato disponible', () async {
      build(
        script: const [FakeTurn(segment: 'ok', endsOnStop: true)],
        availability: const TranscriptionAvailability(
          recognizerAvailable: true,
          onDeviceApiReports: true,
          localeSupportKnown: true,
          installedLocales: ['es_MX', 'en-US'],
        ),
      );
      await controller.startListening();
      await settle();

      expect(port.attemptedLocales.first, 'es-MX');
    });
  });

  group('servicio no disponible', () {
    test(
      'sin reconocedor el estado es recognizerUnavailable y no reintenta',
      () async {
        build(
          script: const [
            FakeTurn(failWith: TranscriptionErrorCode.recognizerUnavailable),
          ],
        );
        await controller.startListening();
        await settle(20);

        expect(
          controller.snapshot.status,
          VoiceSessionStatus.recognizerUnavailable,
        );
        expect(port.startRequests, hasLength(1));
      },
    );

    test('el texto ya acumulado sobrevive a un fallo fatal', () async {
      build(
        script: const [
          FakeTurn(segment: 'lo dicho antes'),
          FakeTurn(failWith: TranscriptionErrorCode.recognizerUnavailable),
        ],
        repeatLast: false,
      );
      await controller.startListening();
      await settle(20);

      expect(controller.snapshot.committedText, 'lo dicho antes');
      expect(
        controller.snapshot.status,
        VoiceSessionStatus.recognizerUnavailable,
      );
    });

    test('reintentar tras un error recuperable reabre el micrófono', () async {
      build(
        script: const [
          FakeTurn(failWith: TranscriptionErrorCode.engineFailure),
          FakeTurn(failWith: TranscriptionErrorCode.engineFailure),
          FakeTurn(failWith: TranscriptionErrorCode.engineFailure),
          FakeTurn(segment: 'ahora sí', endsOnStop: true),
        ],
        repeatLast: false,
      );
      await controller.startListening();
      await settle(20);
      expect(controller.snapshot.status, VoiceSessionStatus.recoverableError);

      await controller.retry();
      await settle();

      expect(controller.snapshot.status, VoiceSessionStatus.listening);
      expect(controller.snapshot.errorCode, isNull);
    });
  });

  group('edición manual', () {
    test('una corrección manual sobrevive al siguiente segmento', () async {
      build(
        script: const [
          FakeTurn(segment: 'sinco litros'),
          FakeTurn(segment: 'de bellator', endsOnStop: true),
        ],
        repeatLast: false,
      );
      await controller.startListening();
      await settle();
      // La corrección ocurre entre dos turnos, que es el caso real: el usuario
      // ve «sinco», lo arregla y sigue dictando.
      controller.editText('cinco litros');
      await controller.stopListening();
      await settle();

      expect(controller.snapshot.committedText, 'cinco litros de bellator');
      expect(controller.snapshot.manuallyEdited, isTrue);
    });

    test(
      'el texto nuevo se añade al final y nunca reemplaza lo escrito',
      () async {
        build(
          script: const [
            FakeTurn(segment: 'uno'),
            FakeTurn(segment: 'dos', endsOnStop: true),
          ],
          repeatLast: false,
        );
        await controller.startListening();
        await settle();
        controller.editText('texto escrito a mano');
        await controller.stopListening();
        await settle();

        expect(
          controller.snapshot.committedText,
          startsWith('texto escrito a mano'),
        );
        expect(controller.snapshot.committedText, endsWith('dos'));
      },
    );

    test('borrar todo a mano deja la sesión sin texto pero viva', () async {
      build(script: [const FakeTurn(segment: 'algo', endsOnStop: true)]);
      await controller.startListening();
      await settle();
      await controller.stopListening();
      await settle();
      controller.editText('');

      expect(controller.snapshot.committedText, isEmpty);
      expect(controller.snapshot.hasText, isFalse);
      expect(controller.snapshot.status, VoiceSessionStatus.preview);
    });

    test(
      'deshacer devuelve el texto anterior al último añadido automático',
      () async {
        build(
          script: const [
            FakeTurn(segment: 'primero'),
            FakeTurn(segment: 'segundo', endsOnStop: true),
          ],
          repeatLast: false,
        );
        await controller.startListening();
        await settle();

        expect(controller.snapshot.canUndoAutoAppend, isTrue);
        controller.undoLastAutoAppend();

        expect(controller.snapshot.committedText, isEmpty);
        expect(controller.snapshot.canUndoAutoAppend, isFalse);
      },
    );

    test(
      'editar a mano desactiva deshacer para no borrar la corrección',
      () async {
        build(script: [const FakeTurn(segment: 'primero', endsOnStop: true)]);
        await controller.startListening();
        await settle();
        await controller.stopListening();
        await settle();

        controller.editText('primero corregido');
        expect(controller.snapshot.canUndoAutoAppend, isFalse);

        controller.undoLastAutoAppend();
        expect(controller.snapshot.committedText, 'primero corregido');
      },
    );
  });

  group('descartar y limpieza', () {
    test(
      'descartar borra el texto, libera el micrófono y deja cancelled',
      () async {
        build(script: [const FakeTurn(segment: 'algo', endsOnStop: true)]);
        await controller.startListening();
        await settle();
        await controller.discard();
        await settle();

        expect(controller.snapshot.status, VoiceSessionStatus.cancelled);
        expect(controller.snapshot.committedText, isEmpty);
        expect(controller.snapshot.partialText, isEmpty);
        expect(controller.snapshot.segmentCount, 0);
        expect(controller.snapshot.delivered, isNull);
        expect(port.microphoneReleased, isTrue);
        expect(port.calls, contains('cancel'));
      },
    );

    test('descartar no reabre ningún turno', () async {
      build(script: [const FakeTurn(segment: 'algo', endsOnStop: true)]);
      await controller.startListening();
      await settle();
      await controller.discard();
      await settle(20);

      expect(port.startRequests, hasLength(1));
    });

    test('tras descartar se puede empezar otra sesión limpia', () async {
      build(
        script: const [
          FakeTurn(segment: 'vieja', endsOnStop: true),
          FakeTurn(segment: 'nueva', endsOnStop: true),
        ],
        repeatLast: false,
      );
      await controller.startListening();
      await settle();
      await controller.discard();
      await settle();
      await controller.startListening();
      await settle();
      await controller.stopListening();
      await settle();

      expect(controller.snapshot.committedText, 'nueva');
    });
  });

  group('entregar el texto', () {
    test('entrega el texto de sesión y no ejecuta ninguna operación', () async {
      build(
        script: [const FakeTurn(segment: 'cincuenta litros', endsOnStop: true)],
      );
      await controller.startListening();
      await settle();
      await controller.stopListening();
      await settle();

      final result = controller.deliver();

      expect(result, isNotNull);
      expect(result!.text, 'cincuenta litros');
      expect(result.segments, 1);
      expect(controller.snapshot.delivered, isNotNull);
      // Entregar libera el micrófono y NO abre otro turno.
      expect(port.microphoneReleased, isTrue);
      expect(port.startRequests, hasLength(1));
    });

    test('no entrega nada cuando no hay texto', () async {
      build();
      expect(controller.deliver(), isNull);
      expect(controller.snapshot.delivered, isNull);
    });

    test('el texto entregado incluye las correcciones manuales', () async {
      build(script: [const FakeTurn(segment: 'sinco', endsOnStop: true)]);
      await controller.startListening();
      await settle();
      await controller.stopListening();
      await settle();
      controller.editText('cinco litros');

      final result = controller.deliver();
      expect(result!.text, 'cinco litros');
      expect(result.edited, isTrue);
    });

    test('seguir hablando después de entregar invalida la entrega', () async {
      build(
        script: const [
          FakeTurn(segment: 'uno', endsOnStop: true),
          FakeTurn(segment: 'dos', endsOnStop: true),
        ],
        repeatLast: false,
      );
      await controller.startListening();
      await settle();
      await controller.stopListening();
      await settle();
      controller.deliver();
      expect(controller.snapshot.delivered, isNotNull);

      await controller.startListening();
      await settle();

      expect(
        controller.snapshot.delivered,
        isNull,
        reason: 'el texto entregado ya no describe la sesión',
      );
    });
  });

  group('ciclo de vida', () {
    test(
      'pasar a segundo plano libera el micrófono y no reabre turnos',
      () async {
        build(script: [const FakeTurn(segment: 'algo')]);
        await controller.startListening();
        await settle();
        await controller.handleAppPaused();
        await settle(20);

        expect(port.microphoneReleased, isTrue);
        expect(controller.snapshot.status.microphoneMayBeOpen, isFalse);
      },
    );

    test('el texto acumulado sobrevive a segundo plano', () async {
      build(
        script: const [
          FakeTurn(segment: 'no se pierde'),
          FakeTurn(segment: 'segundo', endsOnStop: true),
        ],
        repeatLast: false,
      );
      await controller.startListening();
      await settle();
      await controller.handleAppPaused();
      await settle();

      expect(controller.snapshot.committedText, 'no se pierde');
      expect(controller.snapshot.status, VoiceSessionStatus.preview);
    });

    test('dispose durante la escucha suelta el micrófono', () async {
      build(script: [const FakeTurn(silent: true)]);
      await controller.startListening();
      await settle();
      expect(port.microphoneOpen, isTrue);

      controller.dispose();
      await settle();

      expect(port.microphoneReleased, isTrue);
      expect(port.calls, contains('cancel'));
    });

    test('dispose es idempotente', () async {
      build();
      controller.dispose();
      expect(controller.dispose, returnsNormally);
    });

    test(
      'un turno que no responde no deja el micrófono tomado al salir',
      () async {
        build(script: [const FakeTurn(silent: true)]);
        await controller.startListening();
        await settle();
        await controller.discard();
        await settle();

        expect(port.microphoneReleased, isTrue);
      },
    );
  });

  group('doble toque', () {
    test('dos toques seguidos abren un solo turno', () async {
      build(script: [const FakeTurn(silent: true)]);
      await Future.wait([
        controller.startListening(),
        controller.startListening(),
      ]);
      await settle();

      expect(port.startRequests, hasLength(1));
    });

    test('detener dos veces no rompe la sesión', () async {
      build(script: [const FakeTurn(segment: 'uno', endsOnStop: true)]);
      await controller.startListening();
      await settle();
      await controller.stopListening();
      await controller.stopListening();
      await settle();

      expect(controller.snapshot.status, VoiceSessionStatus.preview);
      expect(controller.snapshot.committedText, 'uno');
      expect(controller.snapshot.segmentCount, 1);
    });

    test('descartar dos veces deja la sesión limpia', () async {
      build(script: [const FakeTurn(segment: 'algo', endsOnStop: true)]);
      await controller.startListening();
      await settle();
      await controller.discard();
      await controller.discard();
      await settle();

      expect(controller.snapshot.status, VoiceSessionStatus.cancelled);
      expect(controller.snapshot.committedText, isEmpty);
    });
  });

  group('evidencia de modo offline', () {
    test('pedir offline no se muestra como offline comprobado', () async {
      build(script: [const FakeTurn(segment: 'algo', endsOnStop: true)]);
      await controller.startListening();
      await settle();

      expect(controller.snapshot.offline.offlineRequested, isTrue);
      expect(port.startRequests.first.preferOffline, isTrue);
      expect(
        controller.snapshot.offline.observedOffline,
        isFalse,
        reason: 'sin modo avión verificado no hay evidencia de offline',
      );
    });

    test('transcribir en modo avión sí es evidencia de offline', () async {
      build(
        script: const [FakeTurn(segment: 'algo', endsOnStop: true)],
        availability: const TranscriptionAvailability(
          recognizerAvailable: true,
          onDeviceApiReports: false,
          airplaneMode: AirplaneMode.on,
        ),
      );
      await controller.startListening();
      await settle();
      // La evidencia se anota al recibir texto, no al preguntar a la API.
      await controller.stopListening();
      await settle();

      expect(controller.snapshot.offline.observedOffline, isTrue);
      expect(
        controller.snapshot.offline.onDeviceApiReports,
        isFalse,
        reason: 'ADR-002: la API dijo false donde el offline sí funcionaba',
      );
    });

    test(
      'en API 31 la disponibilidad de idiomas queda como desconocida',
      () async {
        build(
          availability: const TranscriptionAvailability(
            recognizerAvailable: true,
            onDeviceApiReports: false,
            localeSupportKnown: false,
          ),
        );
        await controller.startListening();
        await settle();

        expect(controller.snapshot.offline.availabilityKnown, isFalse);
      },
    );
  });

  group('privacidad de diagnóstico', () {
    test('la fotografía de sesión no expone lo dictado', () async {
      build(
        script: [
          const FakeTurn(segment: 'compra de urea para José', endsOnStop: true),
        ],
      );
      await controller.startListening();
      await settle();

      final text = controller.snapshot.toString();
      expect(text, isNot(contains('urea')));
      expect(text, isNot(contains('José')));
      expect(text, contains('chars='));
    });
  });
}
