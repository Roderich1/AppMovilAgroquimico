import 'package:agroquimicos/presentation/voice/voice_proposals_view.dart';
import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/review_discrepancy.dart';
import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/port/voice_engine_diagnostics.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Diagnóstico de la selección entre motores (F09, POCO 2026-11-09).
///
/// TEXTO INYECTADO, NO RECONOCIMIENTO REAL: el lado nativo se simula por el
/// canal de eventos; los textos de Vosk y de la revisión son sintéticos.
/// Comprueba que:
/// * la regla de selección **no cambia** (mismo texto y misma marca);
/// * el registro sólo lleva códigos y números, nunca lo dictado;
/// * fuera de la compilación de diagnóstico no se guarda ninguna propuesta;
/// * la vista muestra las dos propuestas y su interpretación, y al cerrarla
///   las borra.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(
    LocalSpeechTranscriptionAdapter.methodChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late List<String> logged;

  setUp(() {
    logged = <String>[];
    addTearDown(VoiceProposalsInspector.instance.clear);
  });

  /// Captura el registro (sólo en las pruebas que no son de widgets).
  void captureLog() {
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logged.add(message);
    };
    addTearDown(() => debugPrint = previous);
  }

  LocalSpeechTranscriptionAdapter build() {
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      if (call.method != 'describe') return null;
      return {
        'modelPresent': true,
        'reviewModel': 'whisper-base-q5_1',
        'reviewAvailable': true,
        'totalMemBytes': 6 * 1024 * 1024 * 1024,
        'lowRamDevice': false,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
    final adapter = LocalSpeechTranscriptionAdapter(
      facts: voiceQuantityFacts,
      reviewTimeout: const Duration(seconds: 2),
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  int gen() =>
      ((calls.lastWhere((c) => c.method == 'start').arguments as Map)['gen'])
          as int;

  void native(Map<String, Object?> payload) {
    messenger.handlePlatformMessage(
      LocalSpeechTranscriptionAdapter.eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  const info = <String, Object?>{
    'audioMs': 3400,
    'closedBy': 'stoppedByUser',
    'rmsDbfs': -31,
    'peakDbfs': -7,
    'floorDbfs': -62,
    'loudestDbfs': -18,
    'clipPermille': 0,
    'voiceDetected': true,
    'leadingQuietMs': 650,
    'trailingQuietMs': 50,
    'droppedMs': 0,
    'reviewOutcome': 'ok',
    'loadMs': 0,
    'queuedMs': 2,
  };

  // Sintéticos: la forma de lo que Vosk entregó en el POCO y una revisión
  // SUPUESTA (lo que Whisper propuso de verdad no se conoce).
  const vosk = 'compre cinco litros de vicia de ciento veinte boliviana intro';
  const review =
      'Compré cinco litros de Herbicida DEMO a ciento veinte bolivianos el '
      'litro.';
  const contentWords = [
    'vicia',
    'herbicida',
    'cinco',
    'ciento',
    'veinte',
    'boliviana',
    'litro',
    'compre',
  ];

  List<TranscriptionEvent> open(
    FakeAsync async,
    LocalSpeechTranscriptionAdapter adapter,
  ) {
    final events = <TranscriptionEvent>[];
    adapter.events.listen(events.add);
    adapter.checkAvailability('es-US');
    async.flushMicrotasks();
    adapter.start(
      const TranscriptionRequest(
        locale: 'es-US',
        maxTurnDuration: Duration(minutes: 5),
      ),
    );
    async.flushMicrotasks();
    native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
    async.flushMicrotasks();
    return events;
  }

  test('la regla no cambia y el registro explica la diferencia sin '
      'contenido', () {
    captureLog();
    fakeAsync((async) {
      final adapter = build();
      final events = open(async, adapter);
      native({
        'type': 'phrase',
        'gen': gen(),
        'seq': 0,
        'vosk': vosk,
        'review': true,
      });
      native({'type': 'phraseInfo', 'gen': gen(), 'seq': 0, 'info': info});
      native({
        'type': 'segment',
        'gen': gen(),
        'seq': 0,
        'vosk': vosk,
        'review': review,
        'reviewMs': 2816,
      });
      async.flushMicrotasks();

      final s = events.whereType<TranscriptionSegment>().single;
      expect(s.text, vosk);
      expect(s.revised, isFalse);
      expect(s.numericDisagreement, isTrue);

      final line = logged.singleWhere((l) => l.contains('voz diag:'));
      expect(line, contains('frase=0'));
      expect(line, contains('audio=3400ms'));
      expect(line, contains('cierre=stoppedByUser'));
      expect(line, contains('silencioFinal=50ms'));
      expect(line, contains('revision=ok'));
      expect(line, contains('inferencia=2816ms'));
      expect(line, contains('elegido=vosk'));
      expect(line, contains('motivo=quantities'));
      expect(
        line,
        contains('diferencias=currency:missing@revision,unit:missing@revision'),
      );
      for (final l in logged) {
        for (final w in contentWords) {
          expect(l.toLowerCase(), isNot(contains(w)), reason: l);
        }
      }
      // Fuera de la compilación de diagnóstico no se guarda nada.
      expect(voiceDiagnosticsBuild, isFalse);
      expect(VoiceProposalsInspector.instance.items, isEmpty);
    });
  });

  test('una revisión tardía queda en el registro como tal y no cambia lo '
      'entregado', () {
    captureLog();
    fakeAsync((async) {
      final adapter = build();
      final events = open(async, adapter);
      native({
        'type': 'phrase',
        'gen': gen(),
        'seq': 0,
        'vosk': vosk,
        'review': true,
      });
      async.elapse(const Duration(seconds: 3));
      native({'type': 'phraseInfo', 'gen': gen(), 'seq': 0, 'info': info});
      native({
        'type': 'segment',
        'gen': gen(),
        'seq': 0,
        'vosk': vosk,
        'review': review,
        'reviewMs': 5600,
      });
      async.flushMicrotasks();
      final s = events.whereType<TranscriptionSegment>().single;
      expect(s.text, vosk);
      expect(s.numericDisagreement, isFalse);
      final line = logged.singleWhere((l) => l.contains('voz diag:'));
      expect(line, contains('elegido=vosk(tardio)'));
      expect(line, contains('motivo=timedOut'));
    });
  });

  test('cancelar deja constancia sin contenido', () {
    captureLog();
    fakeAsync((async) {
      final adapter = build();
      open(async, adapter);
      adapter.cancel();
      async.flushMicrotasks();
      expect(
        logged.where((l) => l.contains('voz diag:') && l.contains('cancelado')),
        hasLength(1),
      );
    });
  });

  test('la línea de diagnóstico no copia textos ni claves desconocidas', () {
    final line = phraseDiagnosticLine(
      turn: 3,
      seq: 1,
      info: const {
        'closedBy': 'compre cinco litros',
        'reviewOutcome': 'ok',
        'text': 'herbicida demo',
        'audioMs': 'veinte',
      },
      reviewMs: 2400,
      verdict: ReviewVerdict.accepted,
      revised: true,
      discrepancies: const [],
    );
    expect(line, contains('cierre=-'));
    expect(line, contains('audio=-'));
    expect(line, contains('elegido=revision'));
    for (final w in contentWords) {
      expect(line.toLowerCase(), isNot(contains(w)));
    }
  });

  group('vista de diagnóstico', () {
    const herbicida = CatalogEntry(
      id: 1,
      name: 'Herbicida DEMO',
      unit: CatalogUnit.liter,
    );
    const catalog = VoiceCatalog(
      products: [herbicida],
      suppliers: [CatalogEntry(id: 10, name: 'Agroinsumos DEMO (sintético)')],
      people: [],
      activeCampaign: CatalogEntry(id: 30, name: 'Campaña'),
    );

    Widget app() => MaterialApp(
      home: Scaffold(
        body: VoiceProposalsButton(
          enabled: true,
          describe: (t) => describePurchaseProposal(t, catalog),
        ),
      ),
    );

    testWidgets('fuera de la compilación de diagnóstico no se dibuja', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceProposalsButton(
              describe: (t) => describePurchaseProposal(t, catalog),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('voz-diagnostico-propuestas')), findsNothing);
    });

    testWidgets('muestra las dos propuestas, la regla, la diferencia y la '
        'interpretación de cada una; cerrar las borra', (tester) async {
      VoiceProposalsInspector.instance.addForTest(
        EngineProposal(
          turn: 1,
          seq: 0,
          vosk: vosk,
          review: review,
          reviewOutcome: 'ok',
          verdict: ReviewVerdict.quantities,
          revised: false,
          discrepancies: classifyFactDifferences(
            voiceQuantityFacts(vosk),
            voiceQuantityFacts(review),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const Key('voz-diagnostico-propuestas')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('voz-diagnostico-vista')), findsOneWidget);
      expect(find.text('Vosk: «$vosk»'), findsOneWidget);
      expect(find.text('Whisper: «$review»'), findsOneWidget);
      expect(find.text('Se usó: Vosk'), findsOneWidget);
      expect(
        find.textContaining('moneda: sólo la oyó Whisper'),
        findsOneWidget,
      );
      expect(
        find.textContaining('fuera del catálogo («vicia»)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Herbicida DEMO; cantidad 5 L; precio 120 por L'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('voz-diagnostico-cerrar')));
      await tester.pumpAndSettle();
      expect(VoiceProposalsInspector.instance.items, isEmpty);
      expect(find.byKey(const Key('voz-diagnostico-vista')), findsNothing);
    });
  });
}
