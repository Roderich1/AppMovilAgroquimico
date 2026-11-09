import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/presentation/voice/voice_purchase_draft_screen.dart';
import 'package:agroquimicos/voice/port/review_selection.dart';
import 'package:agroquimicos/voice/port/voice_engine_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/f04_mode_fixtures.dart';
import '../voice/support/fake_speech_transcription_port.dart';
import 'ui_draft_harness.dart';

/// «Usar la otra propuesta» en la pantalla de compra (diagnóstico,
/// política B). TEXTO INYECTADO: el motor es simulado y la otra propuesta se
/// pone a mano en la memoria del diagnóstico. No prueba el reconocimiento.
void main() {
  Future<void> seed(AgroRepository repo, Household h) async {
    await repo.addSupplier(name: 'Agro Norte');
    await repo.addProduct(name: 'Mancozeb');
  }

  const delivered = 'compré mancozeb a 45 bolivianos el litro';
  const other = 'compré tres litros de mancozeb a 45 bolivianos el litro';

  Future<UiDraftWorld> open(WidgetTester tester) async {
    final w = await pumpDraftScreen(
      tester,
      screen: const VoicePurchaseDraftScreen(),
      script: const [
        FakeTurn(
          segment: delivered,
          endsOnStop: true,
          turnId: 7,
          seq: 0,
          numericDisagreement: true,
          reviewSingleFields: {'quantity'},
        ),
      ],
      seed: seed,
    );
    addTearDown(VoiceExperiment.instance.reset);
    addTearDown(VoiceProposalsInspector.instance.clear);
    // Después de abrir la pantalla (que deja el experimento apagado).
    VoiceExperiment.instance
      ..debugAllowOutsideDiagnostics = true
      ..policyB = true;
    VoiceProposalsInspector.instance.addForTest(
      const EngineProposal(
        turn: 7,
        seq: 0,
        vosk: other,
        review: delivered,
        reviewOutcome: 'ok',
        verdict: ReviewVerdict.quantities,
        revised: true,
        discrepancies: [],
        policyBUsedReview: true,
      ),
    );
    await dictate(tester);
    await until(
      tester,
      () => find.byKey(const Key('voz-linea-1')).evaluate().isNotEmpty,
    );
    return w;
  }

  testWidgets('vista previa, sustitución sin duplicar, corrección a mano '
      'conservada y sin escribir nada', (tester) async {
    final w = await open(tester);
    final before = await dump(tester, w.database);
    expect(fieldText(tester, 'voz-cantidad-1'), '');

    // Corrección a mano del precio antes de cambiar de propuesta.
    await tester.enterText(find.byKey(const Key('voz-precio-1')), '47');
    await tester.pumpAndSettle();

    await tapKey(tester, 'voz-otra-propuesta-7:0');
    expect(find.byKey(const Key('voz-otra-propuesta-vista')), findsOneWidget);
    expect(find.textContaining('cantidad: 3'), findsOneWidget);
    expect(find.textContaining('corregido a mano'), findsOneWidget);
    expect(find.textContaining('No es necesariamente mejor'), findsOneWidget);

    await tapKey(tester, 'voz-otra-propuesta-usar');
    expect(fieldText(tester, 'voz-cantidad-1'), '3');
    expect(fieldText(tester, 'voz-precio-1'), '47');
    expect(find.byKey(const Key('voz-linea-2')), findsNothing);
    // Ya usada: no se vuelve a ofrecer (doble pulsación imposible).
    expect(find.byKey(const Key('voz-otra-propuesta-7:0')), findsNothing);
    expect(await dump(tester, w.database), before);
  });

  testWidgets('cancelar la vista previa no cambia nada', (tester) async {
    await open(tester);
    await tapKey(tester, 'voz-otra-propuesta-7:0');
    await tapKey(tester, 'voz-otra-propuesta-cancelar');
    expect(fieldText(tester, 'voz-cantidad-1'), '');
    expect(find.byKey(const Key('voz-otra-propuesta-7:0')), findsOneWidget);
  });

  testWidgets('con las propuestas borradas, la opción queda deshabilitada', (
    tester,
  ) async {
    await open(tester);
    VoiceProposalsInspector.instance.clear();
    await tester.pumpAndSettle();
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('voz-otra-propuesta-7:0')),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('propuestas borradas'), findsOneWidget);
  });
}
