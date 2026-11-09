import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/port/review_discrepancy.dart';
import 'package:agroquimicos/voice/port/review_policy_b.dart';
import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/port/voice_engine_diagnostics.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/numeric_review.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Política experimental B frente a la regla A (F09, 2026-11-09, aprobada
/// por el autor para probarla en diagnóstico).
///
/// PARES SINTÉTICOS escritos a mano y lado nativo simulado: **no prueban el
/// reconocimiento**. Las formas imitan lo observado en el POCO; las frases
/// distintas del herbicida son propias. Ninguna del holdout de #12.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<FactDiscrepancy> diff(String vosk, String review) =>
      classifyFactDifferences(voiceFieldFacts(vosk), voiceFieldFacts(review));
  List<String> codes(String vosk, String review) =>
      diff(vosk, review).map((d) => d.code).toList();

  group('comparador por campo', () {
    test('«120V de litro» es un precio ilegible, no una cantidad; la «V» no '
        'es moneda ni se limpia', () {
      expect(
        voiceFieldFacts(
          'Compres 5 litros de Herbicida DEMO, 120V de '
          'litro.',
        ),
        isNot(contains(startsWith('c'))),
      );
      expect(
        codes(
          'compre cinco litros de servicio a ciento veinte buen liberan el '
              'litro',
          'Compres 5 litros de Herbicida DEMO, 120V de litro.',
        ),
        ['price:extractionFailed'],
      );
    });

    test(
      'cantidad y precio en la misma frase: cada diferencia en su campo',
      () {
        expect(
          codes(
            'compré dos litros de fungicida demo a veinte bolivianos el litro',
            'Compré 2 litros de Fungicida DEMO a 120 bolivianos el litro.',
          ),
          ['price:differentValue'],
        );
        expect(
          codes(
            'compré dos litros de fungicida demo a veinte bolivianos el litro',
            'Compré 3 litros de Fungicida DEMO a 20 bolivianos el litro.',
          ),
          ['quantity:differentValue'],
        );
      },
    );

    test('moneda y unidad del precio que sólo trae Whisper: ausentes, no '
        'distintas', () {
      expect(
        codes(
          'compre cinco litros de herbicidas demo a ciento veinte en el hidra',
          'Compres 5 litros de Herbicida DEMO a 120 bolivianos del litro.',
        ),
        ['currency:missing@revision', 'unit:missing@revision'],
      );
    });

    test('varias líneas: la diferencia queda en el precio de la segunda', () {
      expect(
        codes(
          'compré dos litros de fungicida demo a veinte bolivianos el litro y '
              'tres kilos de mancozeb demo a treinta bolivianos el kilo',
          'Compré 2 litros de Fungicida DEMO a 20 bolivianos el litro y 3 '
              'kilos de Mancozeb DEMO a 40 bolivianos el kilo.',
        ),
        ['price:differentValue'],
      );
    });
  });

  group('política B en el adaptador (diagnóstico)', () {
    const method = MethodChannel(
      LocalSpeechTranscriptionAdapter.methodChannelName,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    setUp(() {
      VoiceExperiment.instance
        ..debugAllowOutsideDiagnostics = true
        ..policyB = true;
      addTearDown(VoiceExperiment.instance.reset);
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
        fieldFacts: voiceFieldFacts,
        reviewTimeout: const Duration(seconds: 2),
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

    List<TranscriptionSegment> dictate(
      FakeAsync async,
      String vosk,
      String? review, {
      Duration delay = Duration.zero,
    }) {
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
          (calls.lastWhere((c) => c.method == 'start').arguments as Map)['gen'];
      native({'type': 'stage', 'gen': gen, 'stage': 'listening'});
      native({
        'type': 'phrase',
        'gen': gen,
        'seq': 0,
        'vosk': vosk,
        'review': true,
      });
      async.flushMicrotasks();
      async.elapse(delay);
      native({
        'type': 'segment',
        'gen': gen,
        'seq': 0,
        'vosk': vosk,
        'review': review,
        'reviewMs': 2700,
      });
      async.flushMicrotasks();
      return events.whereType<TranscriptionSegment>().toList();
    }

    test('Whisper completo y Vosk sin moneda ni unidad: llega Whisper; sólo '
        'moneda y precio por revisar como «un solo motor»', () {
      fakeAsync((async) {
        const review =
            'Compres 5 litros de Herbicida DEMO a 120 bolivianos del litro.';
        final s = dictate(
          async,
          'compre cinco litros de herbicidas demo a ciento veinte en el hidra',
          review,
        ).single;
        expect(s.text, review);
        expect(s.revised, isTrue);
        expect(s.numericDisagreement, isTrue);
        expect(s.reviewConflictFields, isEmpty);
        expect(s.reviewSingleFields, {'currency', 'unit'});
      });
    });

    test('Vosk completo y Whisper sin precio: llega Whisper, el precio queda '
        'pendiente y no se inserta el de Vosk', () {
      fakeAsync((async) {
        const review = 'Compré 2 litros de Fungicida DEMO.';
        final s = dictate(
          async,
          'compré dos litros de fungicida demo a veinte bolivianos el litro',
          review,
        ).single;
        expect(s.text, review);
        expect(s.reviewSingleFields, contains('price'));
      });
    });

    test('valor contradictorio: llega Whisper y ese campo queda como '
        'conflicto', () {
      fakeAsync((async) {
        final s = dictate(
          async,
          'compré dos litros de fungicida demo a veinte bolivianos el litro',
          'Compré 2 litros de Fungicida DEMO a 120 bolivianos el litro.',
        ).single;
        expect(s.revised, isTrue);
        expect(s.reviewConflictFields, {'price'});
        expect(s.reviewSingleFields, isEmpty);
      });
    });

    test('salida degenerada: llega Vosk, sin marcas', () {
      fakeAsync((async) {
        const vosk = 'compré dos litros de fungicida demo';
        final s = dictate(
          async,
          vosk,
          'demo demo demo demo demo demo demo demo demo demo demo demo',
        ).single;
        expect(s.text, vosk);
        expect(s.revised, isFalse);
        expect(s.numericDisagreement, isFalse);
      });
    });

    test('revisión tardía: llega Vosk por tope y lo tardío se descarta', () {
      fakeAsync((async) {
        const vosk = 'compré dos litros de fungicida demo';
        final s = dictate(
          async,
          vosk,
          'Compré 2 litros de Fungicida DEMO.',
          delay: const Duration(seconds: 3),
        );
        expect(s.map((x) => x.text), [vosk]);
        expect(s.single.revised, isFalse);
      });
    });

    test('sin la política B, la regla A de siempre', () {
      fakeAsync((async) {
        VoiceExperiment.instance.policyB = false;
        const vosk =
            'compre cinco litros de herbicidas demo a ciento veinte en el hidra';
        final s = dictate(
          async,
          vosk,
          'Compres 5 litros de Herbicida DEMO a 120 bolivianos del litro.',
        ).single;
        expect(s.text, vosk);
        expect(s.numericDisagreement, isTrue);
        expect(s.reviewSingleFields, isEmpty);
      });
    });
  });

  group('marcas por campo en el borrador', () {
    const fungicida = CatalogEntry(
      id: 2,
      name: 'Fungicida DEMO',
      unit: CatalogUnit.liter,
    );
    const catalog = VoiceCatalog(
      products: [fungicida],
      suppliers: [],
      people: [],
      activeCampaign: CatalogEntry(id: 30, name: 'Campaña'),
    );

    test('sólo la moneda queda «Revisar»; la cantidad que coincidió no', () {
      final before = VoicePurchaseDraft.start(catalog);
      final after = interpretPurchase(
        'Compré 2 litros de Fungicida DEMO a 20 bolivianos el litro.',
        before,
        catalog,
      ).draft;
      final marked = reviewPurchaseNumbers(
        before,
        after,
        singleSourceMessage,
        only: purchaseFieldsFor({'currency'}),
      );
      final l = marked.lines.single;
      expect(l.currency.review, isTrue);
      expect(l.quantity.review, isFalse);
      expect(l.price.review, isFalse);
    });

    test('lo corregido a mano no se marca', () {
      final before = VoicePurchaseDraft.start(catalog);
      var after = interpretPurchase(
        'Compré 2 litros de Fungicida DEMO a 20 bolivianos el litro.',
        before,
        catalog,
      ).draft;
      after = after.updateLine(
        after.lines.single.key,
        (l) => l.copyWith(
          price: const DraftField.resolved(
            SpokenPrice(2500, perUnit: CatalogUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      );
      final marked = reviewPurchaseNumbers(
        before,
        after,
        numericDisagreementMessage,
        only: purchaseFieldsFor({'price'}),
      );
      expect(marked.lines.single.price.review, isFalse);
      expect(marked.lines.single.unitPriceMinor, 2500);
    });

    test('la unidad del precio se revisa en el precio; una cifra sin papel, '
        'en cantidad y precio', () {
      expect(purchaseFieldsFor({'unit'}), {'price'});
      expect(purchaseFieldsFor({'number'}), {'quantity', 'price'});
      expect(purchaseFieldsFor({'area'}), isEmpty);
    });
  });

  group('A frente a B con las mismas propuestas sintéticas', () {
    const herbicida = CatalogEntry(
      id: 1,
      name: 'Herbicida DEMO',
      unit: CatalogUnit.liter,
    );
    const fungicida = CatalogEntry(
      id: 2,
      name: 'Fungicida DEMO',
      unit: CatalogUnit.liter,
    );
    const mancozeb = CatalogEntry(
      id: 3,
      name: 'Mancozeb DEMO',
      unit: CatalogUnit.kilogram,
    );
    const catalog = VoiceCatalog(
      products: [herbicida, fungicida, mancozeb],
      suppliers: [],
      people: [],
      activeCampaign: CatalogEntry(id: 30, name: 'Campaña'),
    );

    // (Vosk, Whisper, verdad: producto, milésimas, centavos por unidad, moneda)
    const cases = <(String, String, int, int, int, CurrencyCode)>[
      // Whisper completo, Vosk sin moneda ni unidad (POCO, forma imitada).
      (
        'compre cinco litros de herbicidas demo a ciento veinte en el hidra',
        'Compré 5 litros de Herbicida DEMO a 120 bolivianos el litro.',
        1,
        5000,
        12000,
        CurrencyCode.bob,
      ),
      // Los dos bien.
      (
        'compré dos litros de fungicida demo a cuarenta bolivianos el litro',
        'Compré 2 litros de Fungicida DEMO a 40 bolivianos el litro.',
        2,
        2000,
        4000,
        CurrencyCode.bob,
      ),
      // Whisper incorrecto en el precio (simulado): B no debe aceptarlo solo.
      (
        'compré tres kilos de mancozeb demo a treinta bolivianos el kilo',
        'Compré 3 kilos de Mancozeb DEMO a 13 bolivianos el kilo.',
        3,
        3000,
        3000,
        CurrencyCode.bob,
      ),
      // Whisper incompleto (simulado): sin precio.
      (
        'compré dos litros de fungicida demo a veinte bolivianos el litro',
        'Compré 2 litros de Fungicida DEMO.',
        2,
        2000,
        2000,
        CurrencyCode.bob,
      ),
      // Whisper con cifra ilegible.
      (
        'compré cuatro litros de herbicida demo a cincuenta bolivianos el '
            'litro',
        'Compré 4 litros de Herbicida DEMO, 50V el litro.',
        1,
        4000,
        5000,
        CurrencyCode.bob,
      ),
    ];

    ({int correct, int pending, int wrongSilent}) score(
      VoicePurchaseLine l,
      (String, String, int, int, int, CurrencyCode) truth,
    ) {
      var correct = 0;
      var pending = 0;
      var wrongSilent = 0;
      void field(bool resolved, bool review, bool matches) {
        if (!resolved || review) {
          pending++;
        } else if (matches) {
          correct++;
        } else {
          wrongSilent++;
        }
      }

      field(
        l.product.isResolved,
        l.product.review,
        l.product.value?.id == truth.$3,
      );
      field(
        l.quantity.isResolved,
        l.quantity.review,
        l.quantity.value?.thousandths == truth.$4,
      );
      field(l.price.isResolved, l.price.review, l.unitPriceMinor == truth.$5);
      field(
        l.currency.isResolved,
        l.currency.review,
        l.currency.value == truth.$6,
      );
      return (correct: correct, pending: pending, wrongSilent: wrongSilent);
    }

    VoicePurchaseLine runA(String vosk, String review) {
      final choice = chooseReviewedText(
        vosk,
        review,
        facts: voiceQuantityFacts,
      );
      final before = VoicePurchaseDraft.start(catalog);
      final after = interpretPurchase(choice.text, before, catalog).draft;
      final d = choice.numericDisagreement
          ? reviewPurchaseNumbers(before, after, numericDisagreementMessage)
          : after;
      return d.lines.single;
    }

    VoicePurchaseLine runB(String vosk, String review) {
      final choice = chooseReviewedText(
        vosk,
        review,
        facts: voiceQuantityFacts,
      );
      final ds = diff(vosk, review);
      final b = choosePolicyB(
        verdict: choice.verdict,
        late: false,
        discrepancies: ds,
      );
      final before = VoicePurchaseDraft.start(catalog);
      final text = b.useReview ? review : vosk;
      var d = interpretPurchase(text, before, catalog).draft;
      final conflict = {
        for (final x in ds)
          if (x.kind != DiscrepancyKind.missing &&
              x.kind != DiscrepancyKind.extractionFailed &&
              x.kind != DiscrepancyKind.equivalentFormat)
            x.field.name,
      };
      final single = {
        for (final x in ds)
          if (x.kind == DiscrepancyKind.missing ||
              x.kind == DiscrepancyKind.extractionFailed)
            x.field.name,
      };
      d = reviewPurchaseNumbers(
        before,
        reviewPurchaseNumbers(
          before,
          d,
          numericDisagreementMessage,
          only: purchaseFieldsFor(conflict),
        ),
        singleSourceMessage,
        only: purchaseFieldsFor(single).difference(purchaseFieldsFor(conflict)),
      );
      return d.lines.single;
    }

    test('B nunca deja más campos incorrectos sin aviso que A, y en total no '
        'tiene menos campos correctos', () {
      var a = (correct: 0, pending: 0, wrongSilent: 0);
      var b = (correct: 0, pending: 0, wrongSilent: 0);
      for (final c in cases) {
        final sa = score(runA(c.$1, c.$2), c);
        final sb = score(runB(c.$1, c.$2), c);
        expect(sb.wrongSilent, lessThanOrEqualTo(sa.wrongSilent), reason: c.$2);
        a = (
          correct: a.correct + sa.correct,
          pending: a.pending + sa.pending,
          wrongSilent: a.wrongSilent + sa.wrongSilent,
        );
        b = (
          correct: b.correct + sb.correct,
          pending: b.pending + sb.pending,
          wrongSilent: b.wrongSilent + sb.wrongSilent,
        );
        // ignore: avoid_print
        print('caso ${cases.indexOf(c) + 1}: A $sa | B $sb');
      }
      // ignore: avoid_print
      print('TOTAL A $a | B $b');
      expect(b.wrongSilent, 0);
      expect(b.correct, greaterThanOrEqualTo(a.correct));
    });
  });

  group('«de/del litro» detrás del importe', () {
    const herbicida = CatalogEntry(
      id: 1,
      name: 'Herbicida DEMO',
      unit: CatalogUnit.liter,
    );
    const mancozeb = CatalogEntry(
      id: 3,
      name: 'Mancozeb DEMO',
      unit: CatalogUnit.kilogram,
    );
    const catalog = VoiceCatalog(
      products: [herbicida, mancozeb],
      suppliers: [],
      people: [],
      activeCampaign: CatalogEntry(id: 30, name: 'Campaña'),
    );
    VoicePurchaseLine line(String t) => interpretPurchase(
      t,
      VoicePurchaseDraft.start(catalog),
      catalog,
    ).draft.lines.single;

    test('con moneda: conserva 120 y BOB y pregunta «¿120 Bs por L?»', () {
      for (final t in const [
        'Compres 5 litros de Herbicida DEMO a 120 bolivianos del litro.',
        'compré cinco litros de herbicida demo a ciento veinte bolivianos de '
            'litro',
      ]) {
        final l = line(t);
        expect(l.price.status, FieldStatus.ambiguous, reason: t);
        expect(l.price.value?.minorPerUnit, 12000, reason: t);
        expect(l.price.message, contains('¿120 Bs por L?'), reason: t);
        expect(l.currency.value, CurrencyCode.bob, reason: t);
        expect(l.unitPriceMinor, isNull, reason: t);
      }
    });

    test('sin moneda: pregunta «¿120 por L?» y la moneda sigue pendiente, sin '
        'suponer BOB', () {
      final l = line(
        'compré cinco litros de herbicida demo a 120 boliganos de litro',
      );
      expect(l.price.message, contains('¿120 por L?'));
      expect(l.price.message, contains('La moneda sigue pendiente'));
      expect(l.currency.status, FieldStatus.missing);
    });

    test('unidad del precio distinta de la del producto: no se pregunta por '
        'ella', () {
      final l = line(
        'compré tres kilos de mancozeb demo a 30 bolivianos del litro',
      );
      expect(l.price.status, FieldStatus.ambiguous);
      expect(l.price.message, isNot(contains('por L?')));
      expect(l.price.message, contains('no es la del producto'));
    });

    test('«de» de una cantidad no se vuelve «por»', () {
      final l = line('compré cinco litros de herbicida demo');
      expect(l.quantity.value?.thousandths, 5000);
      expect(l.price.status, FieldStatus.missing);
    });

    test('«en el litro» y total siguen igual', () {
      expect(
        line(
          'compré cinco litros de herbicida demo a 120 bolivianos en el litro',
        ).price.message,
        contains('¿120 Bs por L?'),
      );
      expect(
        line(
          'compré cinco litros de herbicida demo por 600 bolivianos en total',
        ).price.value?.total,
        isTrue,
      );
    });
  });
}
