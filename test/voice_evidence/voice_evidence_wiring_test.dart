import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:agroquimicos/voice_evidence/voice_evidence_providers.dart';
import 'package:agroquimicos/voice_evidence/voice_evidence_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';
import '../voice/support/fake_speech_transcription_port.dart';
import '../support/purchase_form_driver.dart';

/// Cableado de la evidencia de dictado (#167) en «Nueva compra» con
/// «Completar por voz» (formulario único, F09), en la app real con base en
/// archivo y el puerto de voz fake (no prueba el reconocimiento real):
///
/// - con el almacén activo y consentimiento, registrar deja **una** entrada
///   CONFIRMED con la transcripción y los campos confirmados, y cancelar deja
///   una DISCARDED sin compra;
/// - sin consentimiento, nada;
/// - en una compilación normal (sumidero nulo), nada aunque haya
///   consentimiento.
void main() {
  sqfliteFfiInit();

  const dictation =
      'compra de diez litros de Glifosato a 50 bolivianos el litro, '
      'proveedor Agro Norte, todo para Hermana';

  Future<AppDatabase> open(
    WidgetTester tester,
    String name, {
    required bool evaluationBuild,
    required bool consent,
  }) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(
      () => s.household.repo.addSupplier(name: 'Agro Norte'),
    );
    if (consent) {
      await tester.runAsync(
        () =>
            VoiceEvidenceStore(s.database)
                .grantConsent(consentTextVersion: 'prueba'),
      );
    }
    final port = FakeSpeechTranscriptionPort(
      script: const [
        FakeTurn(
          segment: dictation,
          partials: ['compra de diez'],
          endsOnStop: true,
        ),
      ],
      repeatLast: false,
    );
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: <Override>[
        speechPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
        // La compra tiene su propio puerto (turno entero): el mismo simulado.
        wholeTurnPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
        if (evaluationBuild) recordVoiceEvidenceOverride,
      ],
    );
    // Como en la app: «Registrar por voz» y, apilada encima, la compra. Así
    // registrar o cancelar cierran la pantalla (y su `dispose` entrega).
    final router = c.read(routerProvider);
    router.go('/voz');
    await settle(tester);
    router.push('/compras/voz');
    await settle(tester);
    expect(find.byType(PurchaseFormScreen), findsOneWidget);
    expect(find.byKey(const Key('voz-panel')), findsOneWidget);
    return s.database;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> dictate(WidgetTester tester) async {
    await tapKey(tester, 'voz-hablar');
    await tapKey(tester, 'voz-terminar');
  }

  /// Registrar por el procedimiento habitual del formulario.
  Future<void> register(WidgetTester tester) async {
    await closePurchaseLine(tester);
    await tapKey(tester, 'purchase-continue');
    await tapKey(tester, 'purchase-paid-no');
    await tapKey(tester, 'purchase-confirm');
  }

  /// Cancelar el formulario: Atrás y «Descartar cambios».
  Future<void> cancel(WidgetTester tester) async {
    // Rediseño: el Volver del formulario es el botón redondo de la cabecera.
    await closePurchaseLine(tester);
    await tester.tap(find.byKey(const Key('purchase-close')));
    await settle(tester);
    await tester.tap(find.text('Descartar cambios'));
    await settle(tester);
  }

  /// La entrega es asíncrona (`unawaited` al cerrarse la pantalla) y su
  /// transacción corre en la zona de la prueba: sólo avanza con `pump`. Una
  /// lectura desde `runAsync` mientras sigue abierta esperaría su bloqueo sin
  /// que nadie bombee (interbloqueo de la prueba, no de la app). Por eso se
  /// deja terminar antes de leer.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      // También avanza el reloj: la salida de la ruta es una animación.
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Espera, con tope (60 vueltas), a que la pantalla de compra se cierre.
  /// Bajo carga (conjunto combinado del 2026-11-08, `+635 -1`) 20 vueltas
  /// fijas no bastaron; aislado pasaba siempre.
  Future<void> untilClosed(WidgetTester tester) async {
    await drain(tester);
    for (
      var i = 0;
      i < 60 && find.byType(PurchaseFormScreen).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<List<StoredVoiceEvidence>> evidence(
    WidgetTester tester,
    AppDatabase database,
  ) async {
    await drain(tester);
    return (await tester.runAsync(VoiceEvidenceStore(database).readAll))!;
  }

  Future<int> purchases(WidgetTester tester, AppDatabase database) async {
    await drain(tester);
    return (await tester.runAsync(
      () async => (await database.database).query('purchases'),
    ))!.length;
  }

  testWidgets('evaluación con consentimiento: registrar deja una entrada '
      'CONFIRMED con transcripción y campos confirmados', (tester) async {
    final db = await open(
      tester,
      'ev-confirma',
      evaluationBuild: true,
      consent: true,
    );
    await dictate(tester);
    // Mientras se revisa, nada guardado.
    expect(await evidence(tester, db), isEmpty);
    await register(tester);
    await untilClosed(tester);
    expect(find.byType(PurchaseFormScreen), findsNothing);
    expect(await purchases(tester, db), 1);

    final all = await evidence(tester, db);
    expect(all, hasLength(1));
    final entry = all.single;
    expect(entry.outcome.code, 'CONFIRMED');
    expect(entry.kind.code, 'PURCHASE');
    expect(entry.transcripts, [dictation]);
    expect(entry.proposed, isNotEmpty);
    expect(entry.confirmed, isNotNull);
    // Lo que se registra solo, sin que la persona mida nada: motor de la
    // compilación, modelo declarado por la disponibilidad (el fake se llama
    // «fake test») y tiempos observados desde la interfaz.
    expect(entry.engine, 'local');
    expect(entry.model, 'fake test');
    expect(entry.firstPartialMs, isNotNull);
    expect(entry.firstPartialMs, greaterThanOrEqualTo(0));
    expect(entry.finalMs, isNotNull);
    expect(entry.appCommit, isNull, reason: 'sin AGRO_APP_COMMIT en pruebas');
  });

  testWidgets('evaluación con consentimiento: cancelar deja una entrada '
      'DISCARDED y ninguna compra', (tester) async {
    final db = await open(
      tester,
      'ev-cancela',
      evaluationBuild: true,
      consent: true,
    );
    await dictate(tester);
    await cancel(tester);
    await untilClosed(tester);
    expect(find.byType(PurchaseFormScreen), findsNothing);
    expect(await purchases(tester, db), 0);
    final all = await evidence(tester, db);
    expect(all, hasLength(1));
    expect(all.single.outcome.code, 'DISCARDED');
    expect(all.single.confirmed, isNull);
  });

  testWidgets('evaluación sin consentimiento: registrar no guarda evidencia', (
    tester,
  ) async {
    final db = await open(
      tester,
      'ev-sin-permiso',
      evaluationBuild: true,
      consent: false,
    );
    await dictate(tester);
    await register(tester);
    await untilClosed(tester);
    expect(find.byType(PurchaseFormScreen), findsNothing);
    expect(await purchases(tester, db), 1);
    expect(await evidence(tester, db), isEmpty);
  });

  testWidgets('compilación normal: sumidero nulo, nada aunque haya '
      'consentimiento', (tester) async {
    final db = await open(
      tester,
      'ev-normal',
      evaluationBuild: false,
      consent: true,
    );
    await dictate(tester);
    await register(tester);
    await untilClosed(tester);
    expect(find.byType(PurchaseFormScreen), findsNothing);
    expect(await purchases(tester, db), 1);
    expect(await evidence(tester, db), isEmpty);
  });
}
