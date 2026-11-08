import 'package:agroquimicos/presentation/voice/voice_draft_widgets.dart';
import 'package:agroquimicos/presentation/voice/voice_quantity_facts.dart';
import 'package:agroquimicos/voice/port/local_speech_transcription_adapter.dart';
import 'package:agroquimicos/voice/session/voice_session_controller.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:agroquimicos/voice_draft/purchase/purchase_interpreter.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// De extremo a extremo, sin teléfono (#166): eventos nativos simulados →
/// adaptador local → sesión → texto nuevo → intérprete → borrador.
///
/// Es el mismo cableado que la pantalla de compra por voz (`_onSession`):
/// sólo el texto cerrado y nuevo de la sesión llega al intérprete
/// ([VoiceSegmentFeed]), y el borrador aplica el resultado con
/// [VoiceDraftController.applyVoice], que conserva los campos manuales.
///
/// Comprueba que una revisión que llega después de una corrección manual no
/// la sobrescribe —tanto si llega a tiempo como si llega pasado el tope—, que
/// al intérprete llega una sola transcripción por frase y que lo que llega
/// tras descartar no toca el borrador. Frases propias de la prueba; ninguna
/// del holdout de #12.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(
    LocalSpeechTranscriptionAdapter.methodChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const bellator = CatalogEntry(
    id: 1,
    name: 'Bellator',
    unit: CatalogUnit.liter,
  );
  const catalog = VoiceCatalog(
    products: [bellator],
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
          'reviewModel': 'whisper-small-q5_1',
          'reviewVariant': 'small',
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

  /// La pantalla de compra, sin widgets: sesión, feed, intérprete y borrador.
  ({
    VoiceSessionController session,
    VoiceDraftController<VoicePurchaseDraft, int> draft,
    List<String> interpreted,
  })
  wire({Duration reviewTimeout = const Duration(seconds: 5)}) {
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
    session.addListener(() {
      final fresh = feed.take(session.snapshot.committedText, ready: true);
      if (fresh == null) return;
      interpreted.add(fresh);
      draft.applyVoice((current) {
        final r = interpretPurchase(fresh, current, catalog);
        return (r.draft, r.outcome);
      });
    });
    addTearDown(() async {
      session.dispose();
      draft.dispose();
      await port.dispose();
    });
    return (session: session, draft: draft, interpreted: interpreted);
  }

  /// La persona corrige a mano la cantidad de la única línea.
  void editQuantity(
    VoiceDraftController<VoicePurchaseDraft, int> draft,
    int base,
  ) {
    final key = draft.draft.lines.single.key;
    draft.editManually(
      (d) => d.updateLine(
        key,
        (l) => l.copyWith(
          quantity: DraftField.resolved(
            SpokenQuantity(base, SpokenUnit.liter),
            origin: FieldOrigin.manual,
          ),
        ),
      ),
    );
  }

  Future<void> listening(VoiceSessionController session) async {
    await session.startListening();
    await settle();
    expect(
      (calls.lastWhere((c) => c.method == 'start').arguments as Map)['review'],
      isTrue,
    );
    native({'type': 'stage', 'gen': gen(), 'stage': 'listening'});
    await settle();
  }

  test(
    'la revisión de una frase posterior no pisa la corrección manual',
    () async {
      final w = wire();
      await listening(w.session);

      native({
        'type': 'phrase',
        'gen': gen(),
        'seq': 0,
        'vosk': 'compra de cincuenta litros de bella thor',
        'review': true,
      });
      native({
        'type': 'segment',
        'gen': gen(),
        'seq': 0,
        'vosk': 'compra de cincuenta litros de bella thor',
        'review': 'Compra de cincuenta litros de Bellator.',
        'reviewMs': 2100,
      });
      await settle();
      expect(w.draft.draft.lines.single.quantityBase, 50000);

      editQuantity(w.draft, 30000);

      // La frase siguiente vuelve a nombrar la cantidad; su revisión llega
      // después de la corrección.
      native({
        'type': 'phrase',
        'gen': gen(),
        'seq': 1,
        'vosk':
            'sesenta litros de bella thor a ciento ochenta y seis '
            'bolivianos el litro',
        'review': true,
      });
      await settle();
      expect(w.draft.draft.lines.single.quantityBase, 30000);
      native({
        'type': 'segment',
        'gen': gen(),
        'seq': 1,
        'vosk':
            'sesenta litros de bella thor a ciento ochenta y seis '
            'bolivianos el litro',
        'review': 'Sesenta litros de Bellator a 186 bolivianos el litro.',
        'reviewMs': 2600,
      });
      await settle();

      final line = w.draft.draft.lines.single;
      expect(line.quantityBase, 30000, reason: 'la corrección manual se queda');
      expect(line.quantity.isManual, isTrue);
      expect(
        line.unitPriceMinor,
        18600,
        reason: 'lo no corregido sí se aplica',
      );
      expect(w.draft.keptManualFields, 1);
      // Una transcripción por frase al intérprete, ninguna de las dos motores.
      expect(w.interpreted, hasLength(2));
      expect(w.interpreted.first, 'Compra de cincuenta litros de Bellator.');
      expect(w.interpreted.last, isNot(contains('bella thor')));
    },
  );

  test('una revisión que llega pasado el tope no llega al borrador', () async {
    final w = wire(reviewTimeout: const Duration(milliseconds: 50));
    await listening(w.session);

    native({
      'type': 'phrase',
      'gen': gen(),
      'seq': 0,
      'vosk': 'compra de cincuenta litros de bellator',
      'review': true,
    });
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await settle();
    // Sin revisión a tiempo: el texto de Vosk, sin bloquear.
    expect(w.interpreted, ['compra de cincuenta litros de bellator']);
    expect(w.draft.draft.lines.single.quantityBase, 50000);

    editQuantity(w.draft, 30000);

    // La revisión tardía de la MISMA frase, con otra cantidad.
    native({
      'type': 'segment',
      'gen': gen(),
      'seq': 0,
      'vosk': 'compra de cincuenta litros de bellator',
      'review': 'Compra de sesenta litros de Bellator.',
      'reviewMs': 4800,
    });
    await settle();

    expect(w.interpreted, ['compra de cincuenta litros de bellator']);
    expect(w.session.snapshot.segmentCount, 1);
    expect(w.draft.draft.lines.single.quantityBase, 30000);
    expect(w.draft.draft.lines.single.quantity.isManual, isTrue);
    expect(w.draft.keptManualFields, 0, reason: 'ni siquiera se intentó');
  });

  test(
    'descartar el dictado: una revisión pendiente no toca el borrador',
    () async {
      final w = wire();
      await listening(w.session);
      native({
        'type': 'phrase',
        'gen': gen(),
        'seq': 0,
        'vosk': 'compra de cincuenta litros de bellator',
        'review': true,
      });
      await settle();
      final staleGen = gen();
      await w.session.discard();
      await settle();
      native({
        'type': 'segment',
        'gen': staleGen,
        'seq': 0,
        'vosk': 'compra de cincuenta litros de bellator',
        'review': 'Compra de cincuenta litros de Bellator.',
        'reviewMs': 3000,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await settle();
      expect(w.interpreted, isEmpty);
      expect(w.draft.draft.lines, isEmpty);
    },
  );
}
