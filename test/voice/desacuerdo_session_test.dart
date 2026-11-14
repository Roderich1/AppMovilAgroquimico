import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/session/voice_continuity_policy.dart';
import 'package:agroquimicos/voice/session/voice_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_speech_transcription_port.dart';

/// Contador de desacuerdos numéricos en la sesión de dictado.
///
/// TEXTO INYECTADO, NO RECONOCIMIENTO REAL: el motor es el falso
/// determinista; la marca de desacuerdo la pone el guion de la prueba.
void main() {
  const instant = VoiceContinuityPolicy(
    initialBackoff: Duration.zero,
    maxBackoff: Duration.zero,
  );

  late FakeSpeechTranscriptionPort port;
  late VoiceSessionController controller;

  VoiceSessionController build(List<FakeTurn> script) {
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
    controller = VoiceSessionController(port: port, continuity: instant);
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> settle([int turns = 8]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('se acumula y sube en la misma actualización que el texto', () async {
    build(const [
      FakeTurn(segment: 'dos litros', numericDisagreement: true),
      FakeTurn(segment: 'de bellator'),
      FakeTurn(
        segment: 'a veinte bolivianos',
        numericDisagreement: true,
        endsOnStop: true,
      ),
    ]);
    // Cada notificación: (texto, contador) tal como los ve la pantalla.
    final seen = <(String, int)>[];
    controller.addListener(() {
      final s = controller.snapshot;
      final last = seen.isEmpty ? null : seen.last;
      if (s.committedText.isNotEmpty &&
          (last == null || last.$1 != s.committedText)) {
        seen.add((s.committedText, s.numericDisagreements));
      }
    });
    expect(controller.snapshot.numericDisagreements, 0);

    await controller.startListening();
    await settle();
    await controller.stopListening();
    await settle();

    expect(
      controller.snapshot.committedText,
      'dos litros de bellator a veinte bolivianos',
    );
    expect(controller.snapshot.numericDisagreements, 2);
    expect(seen, [
      ('dos litros', 1),
      ('dos litros de bellator', 1),
      ('dos litros de bellator a veinte bolivianos', 2),
    ]);
  });

  test('un segmento repetido, vacío o tardío no lo sube', () async {
    build(const [
      FakeTurn(
        segment: 'dos litros',
        numericDisagreement: true,
        endsOnStop: true,
      ),
    ]);
    await controller.startListening();
    await settle();
    await controller.stopListening();
    await settle();
    expect(controller.snapshot.numericDisagreements, 1);

    // Tras el cierre del turno: tardío, no entra.
    port.emitForTest(
      const TranscriptionSegment(
        'tres litros',
        elapsed: Duration.zero,
        numericDisagreement: true,
      ),
    );
    await settle();
    expect(controller.snapshot.committedText, 'dos litros');
    expect(controller.snapshot.numericDisagreements, 1);
  });

  test('deshacer y editar no lo corrompen', () async {
    build(const [
      FakeTurn(segment: 'dos litros', numericDisagreement: true),
      FakeTurn(segment: 'de bellator', endsOnStop: true),
    ]);
    await controller.startListening();
    await settle();
    await controller.stopListening();
    await settle();
    expect(controller.snapshot.numericDisagreements, 1);

    controller.undoLastAutoAppend();
    expect(controller.snapshot.committedText, 'dos litros');
    expect(
      controller.snapshot.numericDisagreements,
      1,
      reason: 'lo ya interpretado no se desinterpreta: no baja',
    );

    controller.editText('tres litros');
    expect(controller.snapshot.numericDisagreements, 1);
    expect(controller.snapshot.manuallyEdited, isTrue);
  });

  test('descartar empieza de cero: no pasa a la siguiente sesión', () async {
    build(const [
      FakeTurn(
        segment: 'dos litros',
        numericDisagreement: true,
        endsOnStop: true,
      ),
      FakeTurn(segment: 'tres litros', endsOnStop: true),
    ]);
    await controller.startListening();
    await settle();
    await controller.stopListening();
    await settle();
    expect(controller.snapshot.numericDisagreements, 1);

    await controller.discard();
    expect(controller.snapshot.committedText, isEmpty);
    expect(controller.snapshot.numericDisagreements, 0);

    await controller.startListening();
    await settle();
    await controller.stopListening();
    await settle();
    expect(controller.snapshot.committedText, 'tres litros');
    expect(controller.snapshot.numericDisagreements, 0);
  });

  test('el diagnóstico de la sesión lleva el contador, no el texto', () async {
    build(const [
      FakeTurn(
        segment: 'dos litros',
        numericDisagreement: true,
        endsOnStop: true,
      ),
    ]);
    await controller.startListening();
    await settle();
    await controller.stopListening();
    await settle();
    final text = controller.snapshot.toString();
    expect(text, contains('disagreements=1'));
    expect(text, isNot(contains('litros')));
  });
}
