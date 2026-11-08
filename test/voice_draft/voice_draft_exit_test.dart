import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/voice/voice_application_draft_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_draft_gateway.dart';
import 'package:agroquimicos/presentation/voice/voice_entry_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_plan_draft_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_purchase_draft_screen.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:agroquimicos/voice_draft/application/voice_application_draft.dart';
import 'package:agroquimicos/voice_draft/plan/voice_plan_draft.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import '../support/f04_mode_ui_harness.dart';
import '../voice/support/fake_speech_transcription_port.dart';

/// #120 (F09-D2): tras registrar bien aparecía «¿Descartar el borrador? No se
/// registró…». Navegación real del router (Operaciones → Registrar por voz →
/// borrador) en las tres pantallas, con el puerto de voz fake:
///
/// - confirmar sale con el mensaje de éxito y sin ese diálogo;
/// - un doble toque escribe una vez y saca **una** pantalla;
/// - cancelar no escribe y sale sin preguntar; «Atrás» con borrador sí
///   pregunta;
/// - un fallo al registrar no sale ni se presenta como éxito, y el borrador
///   sigue editable.
void main() {
  sqfliteFfiInit();

  late FakeSpeechTranscriptionPort port;

  final operations = <_Operation>[
    _Operation(
      name: 'compra',
      path: voicePurchasePath,
      screen: VoicePurchaseDraftScreen,
      dictation:
          'compra de diez litros de Glifosato a 50 bolivianos el litro, '
          'proveedor Agro Norte, todo para Hermana',
      table: 'purchases',
      success: 'Compra registrada',
      // «¿Ya pagaste al proveedor?» se responde siempre.
      complete: (tester) => _tapKey(tester, 'voz-pago-no'),
    ),
    _Operation(
      name: 'planificación',
      path: voicePlanPath,
      screen: VoicePlanDraftScreen,
      dictation:
          'planificar el chaco titular con un litro por hectárea de Glifosato',
      table: 'application_plans',
      success: 'Plan creado',
    ),
    _Operation(
      name: 'aplicación',
      path: voiceApplicationPath,
      screen: VoiceApplicationDraftScreen,
      dictation: 'apliqué dos litros de Glifosato en el chaco titular',
      table: 'applications',
      success: 'Aplicación registrada',
    ),
  ];

  Future<AppDatabase> open(
    WidgetTester tester,
    _Operation op,
    String name, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(500, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(() async {
      await s.household.repo.addSupplier(name: 'Agro Norte');
      await s.household.buy(s.household.titular, 5000);
    });
    port = FakeSpeechTranscriptionPort(
      script: [FakeTurn(segment: op.dictation, endsOnStop: true)],
      repeatLast: false,
    );
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: [
        speechPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
        ...overrides,
      ],
    );
    // Pila real: Operaciones → entrada de voz → borrador.
    final router = c.read(routerProvider);
    router.go('/operaciones');
    await settle(tester);
    router.push(voiceEntryPath);
    await settle(tester);
    router.push(op.path);
    await settle(tester);
    expect(find.byType(op.screen), findsOneWidget);
    await _tapKey(tester, 'voz-boton-microfono');
    await _tapKey(tester, 'voz-boton-microfono');
    // El tramo cerrado llega por el puerto fake de forma asíncrona.
    await waitFor(tester, find.byKey(const Key('voz-linea-1')));
    expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
    await op.complete?.call(tester);
    return s.database;
  }

  Future<int> count(WidgetTester tester, AppDatabase db, String table) async =>
      (await tester.runAsync(
        () async => (await (await db.database).query(table)).length,
      ))!;

  bool registerEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('voz-registrar')))
          .onPressed !=
      null;

  for (final op in operations) {
    group(op.name, () {
      testWidgets('confirmar sale con el éxito y sin el diálogo de descarte', (
        tester,
      ) async {
        final db = await open(tester, op, '120-ok-${op.table}');
        final before = await count(tester, db, op.table);
        expect(registerEnabled(tester), isTrue);
        await _tapKey(tester, 'voz-registrar');
        await _finishTransition(tester);

        expect(find.text('¿Descartar el borrador?'), findsNothing);
        expect(find.textContaining(op.success), findsOneWidget);
        expect(find.byType(op.screen), findsNothing);
        expect(find.byType(VoiceEntryScreen), findsOneWidget);
        expect(await count(tester, db, op.table), before + 1);
        expect(port.microphoneOpen, isFalse);
      });

      testWidgets('doble toque: una escritura y una sola salida', (
        tester,
      ) async {
        final db = await open(tester, op, '120-doble-${op.table}');
        final before = await count(tester, db, op.table);
        final register = find.byKey(const Key('voz-registrar'));
        await tester.ensureVisible(register);
        await tester.pump();
        await tester.tap(register);
        await tester.tap(register, warnIfMissed: false);
        await settle(tester);
        await _finishTransition(tester);

        expect(await count(tester, db, op.table), before + 1);
        expect(find.text('¿Descartar el borrador?'), findsNothing);
        // Sólo salió el borrador: la entrada de voz sigue a la vista.
        expect(find.byType(op.screen), findsNothing);
        expect(find.byType(VoiceEntryScreen), findsOneWidget);
      });

      testWidgets('cancelar no escribe y sale sin preguntar', (tester) async {
        final db = await open(tester, op, '120-cancelar-${op.table}');
        final before = (await tester.runAsync(
          () async => dumpTables(await db.database),
        ))!;
        await _tapKey(tester, 'voz-cancelar');
        await _finishTransition(tester);
        expect(find.text('¿Descartar el borrador?'), findsNothing);
        expect(find.byType(op.screen), findsNothing);
        expect(find.byType(VoiceEntryScreen), findsOneWidget);
        expect(
          (await tester.runAsync(() async => dumpTables(await db.database)))!,
          before,
        );
        expect(port.microphoneOpen, isFalse);
      });

      testWidgets('«Atrás» con un borrador sin registrar sí pregunta', (
        tester,
      ) async {
        final db = await open(tester, op, '120-atras-${op.table}');
        final before = await count(tester, db, op.table);
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.text('¿Descartar el borrador?'), findsOneWidget);
        await tester.tap(find.text('Cancelar').last);
        await settle(tester);
        expect(find.byType(op.screen), findsOneWidget);

        await tester.binding.handlePopRoute();
        await settle(tester);
        await tester.tap(find.text('Descartar'));
        await settle(tester);
        expect(find.text('¿Descartar el borrador?'), findsNothing);
        expect(find.byType(VoiceEntryScreen), findsOneWidget);
        expect(await count(tester, db, op.table), before);
      });

      testWidgets('un fallo al registrar no sale ni se presenta como éxito', (
        tester,
      ) async {
        final db = await open(
          tester,
          op,
          '120-fallo-${op.table}',
          overrides: [
            voiceDraftGatewayProvider.overrideWith(
              (ref) => _FailingGateway(ref.watch(repositoryProvider)),
            ),
          ],
        );
        final before = await count(tester, db, op.table);
        await _tapKey(tester, 'voz-registrar');

        expect(find.byKey(const Key('voz-error-registro')), findsOneWidget);
        expect(find.textContaining(op.success), findsNothing);
        expect(find.text('¿Descartar el borrador?'), findsNothing);
        expect(find.byType(op.screen), findsOneWidget);
        expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
        expect(await count(tester, db, op.table), before);
        // Sigue editable: se puede volver a intentar a mano.
        expect(registerEnabled(tester), isTrue);
        // Y «Atrás» vuelve a preguntar: el borrador no se registró.
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.text('¿Descartar el borrador?'), findsOneWidget);
      });
    });
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

final class _Operation {
  const _Operation({
    required this.name,
    required this.path,
    required this.screen,
    required this.dictation,
    required this.table,
    required this.success,
    this.complete,
  });

  final String name;
  final String path;
  final Type screen;
  final String dictation;
  final String table;
  final String success;
  final Future<void> Function(WidgetTester tester)? complete;
}

/// La escritura falla (por ejemplo, la base rechaza la operación). Lee como
/// el gateway real; sólo la confirmación lanza.
final class _FailingGateway extends VoiceDraftGateway {
  _FailingGateway(super.repo);

  @override
  Future<int> confirmPurchase(VoicePurchaseDraft draft) async =>
      throw StateError('fallo simulado');

  @override
  Future<int> confirmPlan(VoicePlanDraft draft) async =>
      throw StateError('fallo simulado');

  @override
  Future<int> confirmApplication(VoiceApplicationDraft draft) async =>
      throw StateError('fallo simulado');
}

/// Deja terminar la animación de salida de la ruta: mientras dura, la
/// pantalla que sale sigue en el árbol.
Future<void> _finishTransition(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
