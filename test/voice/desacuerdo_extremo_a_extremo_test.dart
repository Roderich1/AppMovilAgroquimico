import 'package:agroquimicos/presentation/voice/voice_draft_widgets.dart';
import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/session/voice_session_controller.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/numeric_review.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// De extremo a extremo, sin teléfono: eventos nativos simulados → adaptador
/// local → sesión → texto nuevo → intérprete → campos por revisar.
///
/// TEXTO INYECTADO, NO RECONOCIMIENTO REAL: los textos de Vosk y de la
/// revisión los escribe la prueba. El cableado de [wire] es el fragmento que
/// se propone para `_onSession` de la pantalla de compra (la pantalla no se
/// toca aquí): si el contador de desacuerdos subió al tomar el texto nuevo,
/// dentro del mismo `applyVoice` se aplica [reviewPurchaseNumbers].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(
    LocalSpeechTranscriptionAdapter.methodChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const catalog = VoiceCatalog(
    products: [CatalogEntry(id: 1, name: 'Bellator', unit: CatalogUnit.liter)],
    suppliers: [CatalogEntry(id: 10, name: 'Agro Norte')],
    people: [CatalogEntry(id: 20, name: 'Ana')],
    activeCampaign: CatalogEntry(id: 30, name: 'Verano 2026'),
  );

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      if (call.method == 'describe') {
        return {
          'modelPresent': true,
          'engineName': 'Vosk (vosk-android 0.3.75)',
          'engineVersion': 'vosk-model-small-es-0.42',
          'reviewModel': 'whisper-base-q5_1',
          'reviewAvailable': true,
          'totalMemBytes': 6 * 1024 * 1024 * 1024,
          'lowRamDevice': false,
          'airplaneMode': true,
        };
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
  });

  void native(Map<String, Object?> payload) {
    messenger.handlePlatformMessage(
      LocalSpeechTranscriptionAdapter.eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  Future<void> settle([int turns = 12]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  int gen() =>
      (calls.lastWhere((c) => c.method == 'start').arguments as Map)['gen']
          as int;

  void phrase(int seq, String vosk) => native({
    'type': 'phrase',
    'gen': gen(),
    'seq': seq,
    'vosk': vosk,
    'review': true,
  });

  void segment(int seq, String vosk, String review, {int ms = 2000}) => native({
    'type': 'segment',
    'gen': gen(),
    'seq': seq,
    'vosk': vosk,
    'review': review,
    'reviewMs': ms,
  });

  /// La pantalla de compra sin widgets, con el fragmento propuesto.
  ({
    VoiceSessionController session,
    VoiceDraftController<VoicePurchaseDraft, int> draft,
    List<String> interpreted,
  })
  wire({
    Duration reviewTimeout = const Duration(seconds: 5),
    bool draftReady = true,
  }) {
    final port = LocalSpeechTranscriptionAdapter(
      facts: voiceQuantityFacts,
      reviewTimeout: reviewTimeout,
    );
    final session = VoiceSessionController(port: port);
    final draft = VoiceDraftController<VoicePurchaseDraft, int>(
      initial: VoicePurchaseDraft.start(catalog),
      commit: (_) async => 1,
    );
    final feed = VoiceSegmentFeed();
    final interpreted = <String>[];
    var seenDisagreements = 0;
    session.addListener(() {
      final snapshot = session.snapshot;
      // En la pantalla: borrador y catálogo cargados.
      final ready = draftReady;
      final fresh = feed.take(snapshot.committedText, ready: ready);
      final disagreed = snapshot.numericDisagreements > seenDisagreements;
      if (ready || snapshot.numericDisagreements < seenDisagreements) {
        seenDisagreements = snapshot.numericDisagreements;
      }
      if (fresh == null) return;
      interpreted.add(fresh);
      draft.applyVoice((current) {
        final r = interpretPurchase(fresh, current, catalog);
        final next = disagreed
            ? reviewPurchaseNumbers(
                current,
                r.draft,
                numericDisagreementMessage,
              )
            : r.draft;
        return (next, r.outcome);
      });
    });
    addTearDown(() async {
      session.dispose();
      draft.dispose();
      await port.dispose();
    });
    return (session: session, draft: draft, interpreted: interpreted);
  }

  Future<void> listening(VoiceSessionController session) async {
    await session.startListening();
    await settle();
    native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
    await settle();
  }

  const vosk = 'compré dos litros de bellator a veinte bolivianos el litro';
  const otherPrice =
      'Compré dos litros de Bellator a ciento veinte bolivianos el litro.';

  test('desacuerdo en el precio: queda Vosk y sus cifras quedan por revisar; '
      'la frase siguiente, sin desacuerdo, no marca nada', () async {
    final w = wire();
    await listening(w.session);

    phrase(0, vosk);
    segment(0, vosk, otherPrice);
    await settle();

    expect(w.interpreted, [vosk], reason: 'una sola transcripción, la de Vosk');
    var line = w.draft.draft.lines.single;
    expect(line.unitPriceMinor, isNull, reason: 'no se da por bueno');
    expect(line.price.value?.minorPerUnit, 2000, reason: 'pero se ve');
    expect(line.price.review, isTrue);
    expect(line.quantity.review, isTrue);
    expect(w.draft.canConfirm, isFalse);

    // La persona confirma el precio y corrige la cantidad.
    w.draft.editManually(
      (d) => d.updateLine(
        line.key,
        (l) => l.copyWith(
          price: l.price.confirmedByUser(),
          currency: l.currency.confirmedByUser(),
          quantity: const DraftField.resolved(
            SpokenQuantity(3000, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      ),
    );

    // Frase siguiente, los dos motores de acuerdo.
    phrase(1, 'el proveedor es agro norte');
    segment(1, 'el proveedor es agro norte', 'El proveedor es Agro Norte.');
    await settle();

    line = w.draft.draft.lines.single;
    expect(line.unitPriceMinor, 2000);
    expect(line.price.origin, FieldOrigin.confirmed);
    expect(line.quantityBase, 3000);
    expect(w.draft.draft.supplier.isResolved, isTrue);
    expect(w.session.snapshot.numericDisagreements, 1);
  });

  test('resultado posterior con desacuerdo tras una corrección manual: la '
      'corrección se queda', () async {
    final w = wire();
    await listening(w.session);
    phrase(0, 'compré dos litros de bellator');
    segment(0, 'compré dos litros de bellator', 'Compré 2 litros de Bellator.');
    await settle();
    final key = w.draft.draft.lines.single.key;
    w.draft.editManually(
      (d) => d.updateLine(
        key,
        (l) => l.copyWith(
          quantity: const DraftField.resolved(
            SpokenQuantity(3000, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      ),
    );

    phrase(1, 'cinco litros de bellator a veinte bolivianos el litro');
    segment(
      1,
      'cinco litros de bellator a veinte bolivianos el litro',
      'Seis litros de Bellator a veinte bolivianos el litro.',
    );
    await settle();

    final line = w.draft.draft.lines.single;
    expect(line.quantity.isManual, isTrue);
    expect(line.quantityBase, 3000);
    expect(line.price.review, isTrue, reason: 'lo que sí cambió, por revisar');
    expect(w.draft.keptManualFields, 1);
  });

  test(
    'tope vencido: no hay segunda lectura y nada queda por revisar',
    () async {
      final w = wire(reviewTimeout: const Duration(milliseconds: 50));
      await listening(w.session);
      phrase(0, vosk);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await settle();
      segment(0, vosk, otherPrice, ms: 4800);
      await settle();
      expect(w.interpreted, [vosk]);
      final line = w.draft.draft.lines.single;
      expect(line.price.review, isFalse);
      expect(line.unitPriceMinor, 2000);
      expect(w.session.snapshot.numericDisagreements, 0);
    },
  );

  test('descartar y volver a dictar: el desacuerdo anterior no marca lo '
      'nuevo', () async {
    final w = wire();
    await listening(w.session);
    phrase(0, vosk);
    segment(0, vosk, otherPrice);
    await settle();
    expect(w.session.snapshot.numericDisagreements, 1);

    await w.session.discard();
    await settle();
    expect(w.session.snapshot.numericDisagreements, 0);

    await listening(w.session);
    phrase(0, 'tipo de cambio seis coma nueve');
    segment(0, 'tipo de cambio seis coma nueve', 'Tipo de cambio 6,9.');
    await settle();
    expect(w.draft.draft.exchangeRate.isResolved, isTrue);
    expect(w.draft.draft.exchangeRate.review, isFalse);

    // Y un desacuerdo de la sesión nueva sí se ve, aunque el contador
    // vuelva a valer lo mismo que antes de descartar.
    phrase(1, vosk);
    segment(1, vosk, otherPrice);
    await settle();
    expect(w.session.snapshot.numericDisagreements, 1);
    expect(w.draft.draft.lines.last.price.review, isTrue);
    expect(w.draft.draft.exchangeRate.review, isFalse);
  });
}
