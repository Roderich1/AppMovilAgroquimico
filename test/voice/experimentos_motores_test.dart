import 'package:agroquimicos/presentation/voice/voice_draft_widgets.dart';
import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/review_discrepancy.dart';
import 'package:agroquimicos/voice/port/review_policy_b.dart';
import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/port/voice_engine_diagnostics.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Experimentos de motores (F09, 2026-11-09): política B, comparación de
/// pistas de Whisper y métricas de captura en la línea de diagnóstico.
///
/// PARES SINTÉTICOS escritos a mano y lado nativo simulado: no prueban el
/// reconocimiento. Ninguna frase del holdout de #12.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<FactDiscrepancy> diff(String vosk, String review) =>
      classifyFactDifferences(
        voiceQuantityFacts(vosk),
        voiceQuantityFacts(review),
      );

  group('política B (sólo se calcula; no cambia lo entregado)', () {
    test('Whisper válido con un dato que sólo él oyó: usa Whisper y deja ese '
        'campo por revisar, sin volver a Vosk', () {
      const vosk = 'compre cinco litros de vicia de ciento veinte boliviana';
      const review =
          'Compré cinco litros de Herbicida DEMO a ciento veinte '
          'bolivianos.';
      final d = diff(vosk, review);
      expect(
        chooseReviewedText(vosk, review, facts: voiceQuantityFacts).verdict,
        ReviewVerdict.quantities,
      );
      final b = choosePolicyB(
        verdict: ReviewVerdict.quantities,
        late: false,
        discrepancies: d,
      );
      expect(b.useReview, isTrue);
      expect(b.reviewFields, {ReviewField.currency});
    });

    test('valor distinto: usa Whisper pero el número en conflicto queda por '
        'revisar', () {
      final b = choosePolicyB(
        verdict: ReviewVerdict.quantities,
        late: false,
        discrepancies: diff('compre veinte litros', 'Compré 120 litros.'),
      );
      expect(b.useReview, isTrue);
      expect(b.reviewFields, {ReviewField.quantity});
    });

    test('formato equivalente no se marca', () {
      final b = choosePolicyB(
        verdict: ReviewVerdict.format,
        late: false,
        discrepancies: diff(
          'compre un litro y medio de fungicida demo',
          'Compré 1.5 litros de Fungicida DEMO.',
        ),
      );
      expect(b.useReview, isTrue);
      expect(b.reviewFields, isEmpty);
    });

    test(
      'salida de Whisper inválida o fuera de tiempo: Vosk, con el motivo',
      () {
        for (final v in [
          ReviewVerdict.notRun,
          ReviewVerdict.empty,
          ReviewVerdict.nonSpeech,
          ReviewVerdict.degenerate,
          ReviewVerdict.timedOut,
        ]) {
          final b = choosePolicyB(
            verdict: v,
            late: false,
            discrepancies: const [],
          );
          expect(b.useReview, isFalse, reason: v.name);
          expect(b.reason, v.name);
        }
        final late = choosePolicyB(
          verdict: ReviewVerdict.accepted,
          late: true,
          discrepancies: const [],
        );
        expect(late.useReview, isFalse);
      },
    );
  });

  group('pista de dominio', () {
    const catalog = VoiceCatalog(
      products: [
        CatalogEntry(id: 1, name: 'Herbicida DEMO', unit: CatalogUnit.liter),
        CatalogEntry(id: 2, name: 'Glifosato 480', unit: CatalogUnit.liter),
      ],
      suppliers: [CatalogEntry(id: 10, name: 'Agroinsumos DEMO')],
      people: [],
      activeCampaign: CatalogEntry(id: 30, name: 'Invierno'),
    );

    test('se construye igual siempre, con los términos primero, sin repetir '
        'y sólo con el catálogo de la cuenta', () {
      final a = voiceDomainContextHints(catalog);
      expect(a, voiceDomainContextHints(catalog));
      expect(a.take(voiceDomainTerms.length), voiceDomainTerms);
      expect(a, containsAll(['Herbicida DEMO', 'Glifosato 480']));
      expect(a.map((t) => t.toLowerCase()).toSet(), hasLength(a.length));
      final other = voiceDomainContextHints(
        const VoiceCatalog(
          products: [],
          suppliers: [],
          people: [],
          activeCampaign: null,
        ),
      );
      expect(other, voiceDomainTerms);
    });

    test('los términos del dominio no llevan cifras ni frases', () {
      for (final t in voiceDomainTerms) {
        expect(t, matches(RegExp(r'^[a-záéíóúñ]+$')), reason: t);
        expect(voiceQuantityFacts(t).where((f) => f.startsWith('n')), isEmpty);
      }
    });
  });

  group('comparación de pistas en el adaptador', () {
    const method = MethodChannel(
      LocalSpeechTranscriptionAdapter.methodChannelName,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;
    late List<String> logged;

    setUp(() {
      logged = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logged.add(message);
      };
      addTearDown(() => debugPrint = previous);
      addTearDown(VoiceExperiment.instance.reset);
      addTearDown(VoiceProposalsInspector.instance.clear);
    });

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
      );
      addTearDown(adapter.dispose);
      return adapter;
    }

    void native(Map<String, Object?> payload) {
      messenger.handlePlatformMessage(
        LocalSpeechTranscriptionAdapter.eventChannelName,
        const StandardMethodCodec().encodeSuccessEnvelope(payload),
        (_) {},
      );
    }

    test('fuera de la compilación de diagnóstico no se pide ninguna '
        'comparación aunque el experimento esté encendido', () {
      fakeAsync((async) {
        VoiceExperiment.instance
          ..compareContexts = true
          ..comparisonHints = {'sin-pista': const []};
        final adapter = build();
        adapter.checkAvailability('es-US');
        async.flushMicrotasks();
        adapter.start(
          const TranscriptionRequest(
            locale: 'es-US',
            maxTurnDuration: Duration(minutes: 5),
          ),
        );
        async.flushMicrotasks();
        final start = calls.lastWhere((c) => c.method == 'start');
        expect((start.arguments as Map)['compare'], isEmpty);
      });
    });

    test('una comparación sólo deja códigos en el registro y no entrega '
        'ningún segmento', () {
      fakeAsync((async) {
        final adapter = build();
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
        final gen =
            (calls.lastWhere((c) => c.method == 'start').arguments
                as Map)['gen'];
        native({
          'type': 'comparison',
          'gen': gen,
          'seq': 0,
          'label': 'dominio',
          'text': 'Compré cinco litros de Herbicida DEMO.',
          'ms': 2600,
          'outcome': 'ok',
        });
        async.flushMicrotasks();
        expect(events.whereType<TranscriptionSegment>(), isEmpty);
        final line = logged.singleWhere(
          (l) => l.contains('voz diag comparar:'),
        );
        expect(line, contains('pista=dominio'));
        expect(line, contains('resultado=ok'));
        expect(line, contains('inferencia=2600ms'));
        expect(line.toLowerCase(), isNot(contains('herbicida')));
        expect(line.toLowerCase(), isNot(contains('cinco')));
      });
    });
  });

  test('la línea de diagnóstico separa nivel de habla y de silencio, y '
      'cuánto audio va a cada motor', () {
    final line = phraseDiagnosticLine(
      turn: 1,
      seq: 0,
      info: const {
        'audioMs': 8800,
        'rmsDbfs': -39,
        'speechRmsDbfs': -29,
        'silenceRmsDbfs': -50,
        'speechMs': 2100,
        'levelMethod': 'v50ms-p10-12dB',
        'turnCapturedMs': 9900,
        'reviewAudioMs': 8800,
        'closeToDeliverMs': 2800,
      },
      reviewMs: 2700,
      verdict: ReviewVerdict.accepted,
      revised: true,
      discrepancies: const [],
    );
    expect(line, contains('nivelTotal=-39dBFS'));
    expect(line, contains('nivelHabla=-29dBFS'));
    expect(line, contains('nivelSilencio=-50dBFS'));
    expect(line, contains('habla=2100ms'));
    expect(line, contains('metodo=v50ms-p10-12dB'));
    expect(line, contains('turnoCapturado=9900ms'));
    expect(line, contains('audioRevision=8800ms'));
    expect(line, contains('entrega=2800ms'));
  });

  test('el experimento vuelve a apagado con reset', () {
    VoiceExperiment.instance
      ..compareContexts = true
      ..comparisonHints = {
        'dominio': const ['litro'],
      };
    VoiceExperiment.instance.reset();
    expect(VoiceExperiment.instance.compareContexts, isFalse);
    expect(VoiceExperiment.instance.activeComparisons, isEmpty);
    expect(voiceDiagnosticsBuild, isFalse);
  });
}
