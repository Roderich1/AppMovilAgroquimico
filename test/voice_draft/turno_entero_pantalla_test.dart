import 'package:agroquimicos/presentation/voice/voice_turn_experiment.dart';
import 'package:agroquimicos/voice/port/voice_engine_diagnostics.dart';
import 'package:agroquimicos/voice/session/voice_session_controller.dart';
import 'package:agroquimicos/voice/ui/voice_capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../voice/support/fake_speech_transcription_port.dart';

/// Tarjeta de diagnóstico de la compra en turno entero: sólo aparece en la
/// compilación de diagnóstico, el selector de modelo elige la variante del
/// próximo turno y las métricas se muestran sin texto. (El interruptor del
/// experimento ya no existe: la compra usa siempre el turno entero.)
void main() {
  setUp(() {
    VoiceExperiment.instance.reset();
    VoiceExperiment.instance.turnVariant = 'base';
    VoiceExperiment.instance.clearTurnMetrics();
  });

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('la tarjeta sólo aparece en diagnóstico; el selector cambia la '
      'variante y las métricas se listan sin texto', (tester) async {
    final session = VoiceSessionController(port: FakeSpeechTranscriptionPort());
    addTearDown(session.dispose);

    // Recorrido normal (sin diagnóstico): no aparece.
    await tester.pumpWidget(
      wrap(VoiceSingleTranscriberPanel(session: session)),
    );
    expect(find.byKey(const Key('voz-experimento-panel')), findsNothing);

    VoiceExperiment.instance.noteTurn(
      const SingleTranscriberTurnMetric(
        turn: 7,
        variant: 'small',
        model: 'whisper-small-q5_1',
        outcome: 'ok',
        hadText: true,
        audioMs: 7600,
        speechMs: 2450,
        speechDbfs: -30,
        loadMs: 1820,
        inferenceMs: 9410,
        closedBy: 'stoppedByUser',
      ),
    );
    await tester.pumpWidget(
      wrap(VoiceSingleTranscriberPanel(session: session, enabled: true)),
    );
    expect(find.byKey(const Key('voz-experimento-panel')), findsOneWidget);
    expect(find.byKey(const Key('voz-experimento-turno-7')), findsOneWidget);
    expect(
      find.textContaining(
        'Turno 7 · small · texto · audio 7,6 s (habla 2,5 s) '
        '· carga 1820 ms · transcripción 9410 ms',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Whisper small'));
    await tester.pump();
    expect(VoiceExperiment.instance.turnVariant, 'small');
    await tester.tap(find.text('Whisper base'));
    await tester.pump();
    expect(VoiceExperiment.instance.turnVariant, 'base');

    await tester.tap(find.byKey(const Key('voz-experimento-borrar-metricas')));
    await tester.pump();
    expect(VoiceExperiment.instance.turnMetrics, isEmpty);
    expect(find.byKey(const Key('voz-experimento-turno-7')), findsNothing);
  });

  testWidgets('el panel de escucha de siempre no cambia de etiquetas con el '
      'puerto por frases', (tester) async {
    final session = VoiceSessionController(port: FakeSpeechTranscriptionPort());
    addTearDown(session.dispose);
    await tester.pumpWidget(wrap(VoiceListeningPanel(session: session)));
    expect(find.text('Hablar'), findsOneWidget);
    expect(find.byKey(const Key('voz-cancelar-turno')), findsNothing);
  });

  test('describeTurnMetric nombra el resultado sin inventar aciertos', () {
    const base = SingleTranscriberTurnMetric(
      turn: 1,
      variant: 'base',
      model: 'whisper-base-q5_1',
      outcome: 'aborted',
      hadText: false,
      audioMs: 30000,
      speechMs: 12000,
      speechDbfs: null,
      loadMs: 0,
      inferenceMs: 45000,
      closedBy: 'maxDuration',
    );
    final line = describeTurnMetric(base);
    expect(line, contains('tope agotado'));
    expect(line, contains('cortado a los 30 s'));
    expect(line, isNot(contains('correcto')));
  });
}
