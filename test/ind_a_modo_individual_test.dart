// Sesión A del rediseño individual (2026-11-13, láminas I-10 a I-24):
// compra, aplicación, plan y voz en MODO INDIVIDUAL, con sus efectos en la
// base (no sólo la pantalla), y la regresión del modo con varias personas.
// App real (base en archivo, router, repositorio y controlador de acceso).
// Los dictados son texto inyectado por el puerto falso, no reconocimiento.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';
import 'support/ind_a_household.dart';
import 'support/purchase_form_driver.dart';
import 'voice/support/fake_speech_transcription_port.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  Future<void> choose(WidgetTester tester, String label, String name) async {
    final w = tester.widget<AdaptiveEntityPicker<Row>>(picker(label).last);
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == name));
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await preparePurchaseKey(tester, key);
    await tester.ensureVisible(find.byKey(Key(key)).last);
    await tester.pump();
    await tester.tap(find.byKey(Key(key)).last);
    await settle(tester);
  }

  Future<List<Row>> rows(
    WidgetTester tester,
    AppDatabase database,
    String sql,
  ) async => (await tester.runAsync(
    () async => (await database.database).rawQuery(sql),
  ))!;

  Future<
    ({
      AppDatabase database,
      IndAHousehold h,
      ProviderContainer c,
      FakeSpeechTranscriptionPort port,
    })
  >
  open(
    WidgetTester tester,
    String name,
    String route,
    Finder ready, {
    List<FakeTurn> script = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await personalHousehold(tester, name);
    final port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
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
    expect(c.read(operationModeProvider), OperationMode.personal);
    c.read(routerProvider).push(route);
    await waitFor(tester, ready);
    await settle(tester);
    return (database: s.database, h: s.household, c: c, port: port);
  }

  Future<void> fillTwoProducts(WidgetTester tester) async {
    await choose(tester, 'Proveedor', 'Agroinsumos');
    await openPurchaseLine(tester);
    expect(find.text('¿Para quién es?'), findsNothing);
    expect(picker('Persona'), findsNothing);
    expect(find.textContaining('Para el titular'), findsNothing);
    await choose(tester, 'Producto', 'Herbicida');
    await tester.enterText(field('Cantidad comprada'), '12');
    await tester.enterText(field('Precio por L'), '118');
    await settle(tester);
    await tapKey(tester, 'purchase-line-next');
    await choose(tester, 'Producto', 'Fungicida');
    await tester.enterText(field('Cantidad comprada'), '4');
    await tester.enterText(field('Precio por L'), '150');
    await settle(tester);
    await closePurchaseLine(tester);
  }

  group('compra individual', () {
    testWidgets('dos productos a crédito: todo al titular, sin pago y un solo '
        'registro aunque se toque dos veces', (tester) async {
      final w = await open(
        tester,
        'ind-a-compra-credito',
        '/compras/nueva',
        find.byKey(const Key('purchase-add-line')),
      );
      final before = await rows(
        tester,
        w.database,
        'SELECT COUNT(*) n FROM purchases',
      );
      await fillTwoProducts(tester);
      // Lámina I-10: la campaña en el rótulo; la tarjeta no repite al titular.
      expect(find.text('Paso 1 de 2 · Invierno 2026'), findsOneWidget);
      expect(find.textContaining('titular'), findsNothing);
      await tapKey(tester, 'purchase-continue');
      // Lámina I-12.
      expect(find.textContaining('entra a su almacén'), findsOneWidget);
      expect(find.textContaining('Para:'), findsNothing);
      await tapKey(tester, 'purchase-paid-no');
      final debt = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((t) => t.startsWith('Esta compra quedará por pagar'));
      expect(debt, contains('2.016,00'));
      expect(debt, contains('con Agroinsumos'));
      // Doble toque: el segundo no registra otra compra.
      await tester.ensureVisible(find.byKey(const Key('purchase-confirm')));
      await tester.tap(find.byKey(const Key('purchase-confirm')));
      await tester.tap(
        find.byKey(const Key('purchase-confirm')),
        warnIfMissed: false,
      );
      await settle(tester);

      final after = await rows(
        tester,
        w.database,
        'SELECT COUNT(*) n FROM purchases',
      );
      expect(after.single['n'], (before.single['n']! as int) + 1);
      final last = await rows(
        tester,
        w.database,
        'SELECT pa.person_id, pa.quantity_base, pi.product_id '
        'FROM purchase_allocations pa '
        'JOIN purchase_items pi ON pi.id = pa.purchase_item_id '
        'WHERE pi.purchase_id = (SELECT MAX(id) FROM purchases) '
        'ORDER BY pi.product_id',
      );
      expect(last, [
        {
          'person_id': w.h.titular,
          'quantity_base': 12000,
          'product_id': w.h.herbicida,
        },
        {
          'person_id': w.h.titular,
          'quantity_base': 4000,
          'product_id': w.h.fungicida,
        },
      ]);
      // A crédito: ningún pago al proveedor.
      expect(
        await rows(tester, w.database, 'SELECT * FROM provider_payments'),
        isEmpty,
      );
    });

    testWidgets('pagada al contado: el pago es del titular por el total', (
      tester,
    ) async {
      final w = await open(
        tester,
        'ind-a-compra-pagada',
        '/compras/nueva',
        find.byKey(const Key('purchase-add-line')),
      );
      await fillTwoProducts(tester);
      await tapKey(tester, 'purchase-continue');
      await tapKey(tester, 'purchase-paid-yes');
      await tapKey(tester, 'purchase-confirm');
      final payments = await rows(
        tester,
        w.database,
        'SELECT payer_person_id, amount_bob_minor FROM provider_payments',
      );
      expect(payments, [
        {'payer_person_id': w.h.titular, 'amount_bob_minor': 201600},
      ]);
    });
  });

  testWidgets('aplicación individual: sin persona ni «Quién aplicó», reduce '
      'las existencias del titular', (tester) async {
    final w = await open(
      tester,
      'ind-a-aplicacion',
      '/aplicaciones/nueva',
      find.byKey(const Key('application-step')),
    );
    expect(find.byKey(const Key('application-personal-owner')), findsNothing);
    expect(find.textContaining('Quién aplicó'), findsNothing);
    expect(field('Superficie tratada'), findsOneWidget);
    await choose(tester, 'Chaco', 'Chaco Norte');
    // Superficie tratada distinta de la del chaco (3 ha).
    await tester.enterText(field('Superficie tratada'), '1');
    await settle(tester);
    await tapKey(tester, 'application-continue');
    await tapKey(tester, 'application-add-product');
    await choose(tester, 'Producto', 'Herbicida');
    await tester.enterText(
      find.byKey(const Key('application-line-quantity')),
      '2',
    );
    await settle(tester);
    await tapKey(tester, 'application-line-add');
    await tapKey(tester, 'application-continue');
    // Lámina I-22.
    expect(
      find.textContaining('superficie tratada: 1 ha de 3 ha'),
      findsOneWidget,
    );
    expect(find.text('SALE DE SU ALMACÉN'), findsOneWidget);
    expect(find.text('Tiene 26 L · le quedarán 24 L'), findsOneWidget);
    expect(
      find.textContaining(
        'Se suma a los costos de Chaco Norte en esta '
        'campaña. No es una deuda.',
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'application-confirm');
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    final apps = await rows(
      tester,
      w.database,
      'SELECT person_id, farm_id FROM applications',
    );
    expect(apps, [
      {'person_id': w.h.titular, 'farm_id': w.h.farm},
    ]);
    final stock = await tester.runAsync(
      () => AgroRepository(w.database).personStockSummary(w.h.titular),
    );
    final herbicida = stock!.firstWhere(
      (r) => r['product_id'] == w.h.herbicida,
    );
    expect(herbicida['available_base'], 24000);
  });

  testWidgets('plan individual: «Revise el plan», fecha prevista y sin '
      'descontar existencias ni generar deuda', (tester) async {
    final w = await open(
      tester,
      'ind-a-plan',
      '/planificacion/nueva',
      find.byKey(const Key('plan-header')),
    );
    Future<List<Row>> stockRows() =>
        rows(tester, w.database, 'SELECT * FROM inventory_movements');
    final movementsBefore = await stockRows();
    final paymentsBefore = await rows(
      tester,
      w.database,
      'SELECT * FROM provider_payments',
    );
    await choose(tester, 'Chaco', 'Chaco Norte');
    await choose(tester, 'Agregar producto', 'Fungicida');
    await tester.tap(find.byTooltip('Agregar al plan'));
    await settle(tester);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.labelText ?? '').startsWith('Dosis'),
      ),
      '2',
    );
    await settle(tester);
    expect(find.text('Tiene 14 L · alcanza'), findsOneWidget);
    expect(find.text('Cantidad prevista'), findsOneWidget);
    expect(find.byKey(const Key('plan-confirm')), findsNothing);
    await tapKey(tester, 'plan-continue');
    // Lámina I-24: nada guardado todavía.
    expect(find.text('Revise el plan'), findsOneWidget);
    expect(find.text('PREVISTO EN PLANES'), findsOneWidget);
    expect(find.text('Fungicida · 6 L'), findsOneWidget);
    expect(
      await rows(tester, w.database, 'SELECT * FROM application_plans'),
      isEmpty,
    );
    // Atrás vuelve al formulario sin perder nada.
    await tapKey(tester, 'plan-back');
    expect(find.text('¿Qué piensa aplicar?'), findsOneWidget);
    expect(find.text('Tiene 14 L · alcanza'), findsOneWidget);
    await tapKey(tester, 'plan-continue');
    await tapKey(tester, 'plan-confirm');
    final plans = await rows(
      tester,
      w.database,
      'SELECT farm_id, planned_date, status FROM application_plans',
    );
    expect(plans, [
      {'farm_id': w.h.farm, 'planned_date': null, 'status': 'PLANNED'},
    ]);
    final items = await rows(
      tester,
      w.database,
      'SELECT product_id, required_quantity_base FROM application_plan_items',
    );
    expect(items, [
      {'product_id': w.h.fungicida, 'required_quantity_base': 6000},
    ]);
    // Un plan no mueve existencias ni crea pagos o deudas.
    expect(await stockRows(), movementsBefore);
    expect(
      await rows(tester, w.database, 'SELECT * FROM provider_payments'),
      paymentsBefore,
    );
  });

  group('voz individual', () {
    testWidgets('un nombre dictado no crea ni asigna persona; aviso sin '
        'repetir lo dicho', (tester) async {
      final w = await open(
        tester,
        'ind-a-voz-nombre',
        '/compras/nueva',
        find.byKey(const Key('compra-completar-voz')),
        script: const [
          FakeTurn(
            segment:
                'compra a Agroinsumos de cuatro litros de Fungicida a 150 '
                'bolivianos el litro, todo para Beto Mamani',
            endsOnStop: true,
          ),
        ],
      );
      final personsBefore = await rows(
        tester,
        w.database,
        'SELECT id FROM persons ORDER BY id',
      );
      await tapKey(tester, 'compra-completar-voz');
      await tapKey(tester, 'voz-hablar');
      // Lámina I-13: guía del formulario, Cancelar y Terminar.
      expect(find.text('Escuchando'), findsOneWidget);
      expect(find.text('Diga producto, cantidad y precio'), findsOneWidget);
      expect(find.byKey(const Key('voz-cancelar-dictado')), findsOneWidget);
      await tapKey(tester, 'voz-terminar');
      expect(
        find.textContaining(
          'Parte del dictado no corresponde a este formulario',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Beto'), findsNothing);
      expect(find.byKey(const Key('voz-dictar-mas')), findsOneWidget);
      expect(find.byKey(const Key('voz-deshacer')), findsOneWidget);
      expect(
        await rows(tester, w.database, 'SELECT id FROM persons ORDER BY id'),
        personsBefore,
      );
      // Guardar: la línea dictada es del titular.
      await tapKey(tester, 'purchase-continue');
      await tapKey(tester, 'purchase-paid-no');
      await tapKey(tester, 'purchase-confirm');
      final alloc = await rows(
        tester,
        w.database,
        'SELECT pa.person_id FROM purchase_allocations pa '
        'JOIN purchase_items pi ON pi.id = pa.purchase_item_id '
        'WHERE pi.purchase_id = (SELECT MAX(id) FROM purchases)',
      );
      expect(alloc, [
        {'person_id': w.h.titular},
      ]);
    });

    testWidgets('«Procesando tu voz» y Cancelar: el resultado tardío no llega '
        'al formulario', (tester) async {
      final w = await open(
        tester,
        'ind-a-voz-cancelar',
        '/compras/nueva',
        find.byKey(const Key('compra-completar-voz')),
        script: const [FakeTurn(silent: true)],
      );
      await tapKey(tester, 'compra-completar-voz');
      await tapKey(tester, 'voz-hablar');
      w.port.emitForTest(
        const TranscriptionStageChanged(TranscriptionStage.processing),
      );
      await settle(tester);
      expect(find.text('Procesando tu voz'), findsOneWidget);
      expect(
        find.text('Los datos aparecerán en el formulario para que los revise.'),
        findsOneWidget,
      );
      await tapKey(tester, 'voz-cancelar-dictado');
      // Llega tarde un resultado: no se aplica.
      w.port.emitForTest(
        const TranscriptionSegment(
          'cuatro litros de Fungicida a 150 bolivianos el litro',
          elapsed: Duration.zero,
        ),
      );
      await settle(tester);
      await closePurchaseLine(tester);
      expect(find.text('Fungicida'), findsNothing);
      expect(find.textContaining('Dictado cancelado'), findsWidgets);
    });

    testWidgets('un cambio de modalidad con el dictado en curso lo cancela', (
      tester,
    ) async {
      final w = await open(
        tester,
        'ind-a-voz-modo',
        '/compras/nueva',
        find.byKey(const Key('compra-completar-voz')),
        script: const [FakeTurn(silent: true)],
      );
      await tapKey(tester, 'compra-completar-voz');
      await tapKey(tester, 'voz-hablar');
      expect(find.text('Escuchando'), findsOneWidget);
      await switchModeBehindScreen(
        tester,
        w.c,
        w.database,
        OperationMode.shared,
      );
      expect(find.text('Escuchando'), findsNothing);
      expect(find.textContaining('Dictado cancelado'), findsWidgets);
      w.port.emitForTest(
        const TranscriptionSegment(
          'cuatro litros de Fungicida a 150 bolivianos el litro',
          elapsed: Duration.zero,
        ),
      );
      await settle(tester);
      await closePurchaseLine(tester);
      expect(find.text('Fungicida'), findsNothing);
      // Y la compra no se puede confirmar con lo cargado en el otro modo.
      await tapKey(tester, 'voz-panel-cerrar');
      final continueButton = tester.widget<ButtonStyleButton>(
        find.descendant(
          of: find.byKey(const Key('purchase-continue')),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          matchRoot: true,
        ),
      );
      expect(continueButton.onPressed, isNull);
    });
  });

  group('modo con varias personas: sin cambios', () {
    testWidgets('compra: «¿Para quién es?», «Para:» en la revisión, rótulo '
        'sin campaña y aviso de siempre', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'ind-a-compartido-compra');
      final c = await pumpModeApp(tester, s.database);
      expect(c.read(operationModeProvider), OperationMode.shared);
      c.read(routerProvider).push('/compras/nueva');
      await waitFor(tester, find.byKey(const Key('purchase-add-line')));
      await settle(tester);
      expect(find.text('Paso 1 de 2'), findsOneWidget);
      await openPurchaseLine(tester);
      expect(find.text('¿Para quién es?'), findsOneWidget);
      await choose(tester, 'Producto', 'Glifosato');
      await tester.enterText(field('Cantidad comprada'), '2');
      await tester.enterText(field('Precio por L'), '50');
      await settle(tester);
      await tapKey(tester, 'purchase-alloc-single-0');
      await choose(tester, 'Persona', 'Hermana');
      await closePurchaseLine(tester);
      await tapKey(tester, 'purchase-continue');
      expect(find.text('Para: Hermana'), findsOneWidget);
      expect(find.textContaining('entra a su almacén'), findsNothing);
      await tapKey(tester, 'purchase-paid-no');
      expect(
        find.text(
          'La compra queda sin pago. Puede anotarlo después en '
          'Operaciones, Compras.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('aplicación y plan: persona, «Área tratada», «Guardar plan» '
        'directo y textos de siempre', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'ind-a-compartido-ap');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).push('/aplicaciones/nueva');
      await waitFor(tester, find.byKey(const Key('application-step')));
      await settle(tester);
      expect(field('Área tratada'), findsOneWidget);
      expect(field('Superficie tratada'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is AdaptiveEntityPicker<Row> &&
              w.items.any((p) => p['name'] == 'Hermana'),
        ),
        findsOneWidget,
      );
      c.read(routerProvider).pop();
      await settle(tester);
      c.read(routerProvider).push('/planificacion/nueva');
      await waitFor(tester, find.byKey(const Key('plan-header')));
      await settle(tester);
      expect(find.byKey(const Key('plan-confirm')), findsOneWidget);
      expect(find.byKey(const Key('plan-continue')), findsNothing);
      expect(find.byKey(const Key('plan-planned-date')), findsNothing);
      expect(field('Área planificada'), findsOneWidget);
    });
  });
}
