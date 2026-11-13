import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/screens/application_form_screen.dart';
import 'package:agroquimicos/presentation/screens/plan_form_screen.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';
import '../voice/support/fake_speech_transcription_port.dart';
import '../support/purchase_form_driver.dart';
import '../support_rdm2/a_purchase_sheet.dart';

typedef Row = Map<String, Object?>;

/// Formulario único (F09): los accesos de voz abren el formulario normal con
/// el panel visible y sin abrir el micrófono, y los casos del POCO (P1–P4,
/// antes probados en la pantalla de voz) siguen igual dentro del formulario.
/// Texto inyectado sintético: integración, no precisión.
void main() {
  sqfliteFfiInit();

  late FakeSpeechTranscriptionPort port;

  Future<({AppDatabase database, ProviderContainer c})> open(
    WidgetTester tester,
    String name, [
    List<FakeTurn> script = const [],
  ]) async {
    await tester.binding.setSurfaceSize(const Size(800, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(() async {
      final repo = s.household.repo;
      await repo.addSupplier(name: 'Agro insumos DEMO');
      await repo.addProduct(name: 'Herbicida DEMO');
      await repo.addProduct(name: 'Fungicida DEMO');
      await repo.addProduct(name: 'Insecticida DEMO');
    });
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: [
        speechPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
        wholeTurnPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
      ],
    );
    return (database: s.database, c: c);
  }

  // Ronda 2 (sesión A): con la hoja abierta la página sigue detrás, a la
  // vista; se toca lo alcanzable (la hoja, o la página tras cerrarla).
  Future<void> tapKey(WidgetTester tester, String key) async {
    await prepareReachableKey(tester, key);
    await tester.ensureVisible(reachable(find.byKey(Key(key))));
    await tester.pump();
    await tester.tap(reachable(find.byKey(Key(key))));
    await settle(tester);
  }

  Future<void> back(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  testWidgets('Registrar por voz → cada opción abre el formulario normal con '
      'el panel visible y el micrófono cerrado', (tester) async {
    final w = await open(tester, 'acc-entrada');
    w.c.read(routerProvider).go('/voz');
    await settle(tester);
    for (final (key, form) in [
      ('voz-entrada-compra', PurchaseFormScreen),
      ('voz-entrada-plan', PlanFormScreen),
      ('voz-entrada-aplicacion', ApplicationFormScreen),
    ]) {
      await tapKey(tester, key);
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.byType(form), findsOneWidget, reason: key);
      expect(find.byKey(const Key('voz-panel')), findsOneWidget, reason: key);
      expect(port.startRequests, isEmpty, reason: '$key: no se abre solo');
      // Sin pantallas de voz aparte: el panel no tiene campos propios.
      expect(find.byKey(const Key('voz-registrar')), findsNothing);
      await back(tester, w.c);
    }
  });

  testWidgets('el botón del formulario muestra y oculta el panel sin salir '
      'ni descartar lo escrito', (tester) async {
    final w = await open(tester, 'acc-boton');
    w.c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, find.byKey(const Key('compra-completar-voz')));
    await settle(tester);
    await openPurchaseLine(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (x) => x is TextField && x.decoration?.labelText == 'Cantidad comprada',
      ),
      '3',
    );
    await settle(tester);
    await tapKey(tester, 'form-dictar');
    expect(find.byKey(const Key('voz-panel')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing, reason: 'no descarta nada');
    await tapKey(tester, 'form-dictar');
    expect(find.byKey(const Key('voz-panel')), findsNothing);
    expect(find.byType(PurchaseFormScreen), findsOneWidget);
  });

  testWidgets('inventario propio: la persona dictada se ignora y se avisa; '
      'la compra es del titular', (tester) async {
    final w = await open(tester, 'acc-propio', const [
      FakeTurn(
        segment:
            'compra de diez litros de Glifosato a 50 bolivianos el litro, '
            'todo para Hermana',
        endsOnStop: true,
      ),
    ]);
    await switchModeBehindScreen(
      tester,
      w.c,
      w.database,
      OperationMode.personal,
    );
    w.c.read(routerProvider).push('/compras/voz');
    await waitFor(tester, find.byKey(const Key('voz-panel')));
    await settle(tester);
    await tapKey(tester, 'voz-hablar');
    await tapKey(tester, 'voz-terminar');
    expect(
      find.textContaining('el destinatario dictado no se usó'),
      findsOneWidget,
    );
    // En la hoja del producto: todo para el titular.
    await openPurchaseLine(tester);
    expect(
      find.byKey(const Key('purchase-personal-allocation-0')),
      findsOneWidget,
    );
  });

  group('casos del POCO (P1–P4) dentro del formulario', () {
    Future<AppDatabase> dictateInForm(WidgetTester tester, String text) async {
      final w = await open(tester, 'p-${text.hashCode}', [
        FakeTurn(segment: text, endsOnStop: true),
      ]);
      w.c.read(routerProvider).push('/compras/voz');
      await waitFor(tester, find.byKey(const Key('voz-panel')));
      await settle(tester);
      await tapKey(tester, 'voz-hablar');
      await tapKey(tester, 'voz-terminar');
      return w.database;
    }

    // Rediseño: producto y campos están en la hoja del producto 1.
    Future<String?> product(WidgetTester tester) async {
      await openPurchaseLine(tester);
      return tester
          .widgetList<AdaptiveEntityPicker<Row>>(
            find.byWidgetPredicate(
              (x) => x is AdaptiveEntityPicker<Row> && x.label == 'Producto',
            ),
          )
          .first
          .value?['name']
          ?.toString();
    }

    Future<String> field(WidgetTester tester, String label) async {
      await openPurchaseLine(tester);
      return tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (x) => x is TextField && x.decoration?.labelText == label,
            ),
          )
          .controller!
          .text;
    }

    Future<int> purchases(WidgetTester tester, AppDatabase db) async =>
        (await tester.runAsync(
          () async => (await db.database).query('purchases'),
        ))!.length;

    testWidgets('«Hoy compré fungicida demo»: línea incompleta a la vista; '
        'continuar la rechaza', (tester) async {
      final db = await dictateInForm(tester, 'Hoy compré fungicida demo');
      expect(await product(tester), 'Fungicida DEMO');
      expect(await field(tester, 'Cantidad comprada'), '');
      expect(reachable(find.text('Falta: cantidad')), findsOneWidget);
      await closePurchaseLine(tester);
      await tapKey(tester, 'purchase-continue');
      expect(find.text('¿Qué compró?'), findsOneWidget);
      expect(await purchases(tester, db), 0);
    });

    testWidgets('«No compré fungicida demo»: el formulario no cambia', (
      tester,
    ) async {
      final db = await dictateInForm(tester, 'No compré fungicida demo');
      expect(await product(tester), isNull);
      await closePurchaseLine(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('voz-panel-mensaje'))).data,
        contains('No cambió el formulario'),
      );
      expect(await purchases(tester, db), 0);
    });

    testWidgets(
      '«con un total de 100Bs»: «Total de la línea» da 50 por litro',
      (tester) async {
        final db = await dictateInForm(
          tester,
          'Compré dos litros de Fungicida DEMO con un total de 100Bs',
        );
        expect(await field(tester, 'Precio por L'), '');
        expect(
          reachable(find.textContaining('Se dijo un importe total: 100 Bs')),
          findsOneWidget,
        );
        await tapKey(tester, 'voz-opcion-price@1-0');
        expect(await field(tester, 'Precio por L'), '50');
        expect(await purchases(tester, db), 0);
      },
    );

    testWidgets('«Compréfungicida DEMO.» (verbo pegado): línea incompleta a la '
        'vista', (tester) async {
      final db = await dictateInForm(tester, 'Compréfungicida DEMO.');
      expect(await product(tester), 'Fungicida DEMO');
      expect(reachable(find.text('Falta: cantidad')), findsOneWidget);
      expect(await purchases(tester, db), 0);
    });
  });
}
