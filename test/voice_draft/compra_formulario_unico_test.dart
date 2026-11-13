import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';
import '../support/purchase_form_driver.dart';
import '../support_rdm2/a_purchase_sheet.dart';
import '../voice/support/fake_speech_transcription_port.dart';

typedef Row = Map<String, Object?>;

/// «Nueva compra» con «Completar por voz» (F09, formulario único): el mismo
/// formulario, completado a mano, por voz o combinando ambas formas, y un
/// único registro con el procedimiento habitual. El texto del puerto falso
/// es **texto inyectado** (sintético), no reconocimiento real: esto prueba la
/// integración, no la precisión.
void main() {
  sqfliteFfiInit();

  const full =
      'compra de diez litros de Glifosato a 50 bolivianos el litro, '
      'proveedor Agro Norte, todo para Hermana';

  late FakeSpeechTranscriptionPort port;

  Future<({AppDatabase database, ProviderContainer c})> open(
    WidgetTester tester,
    String name,
    List<FakeTurn> script,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(
      () => s.household.repo.addSupplier(name: 'Agro Norte'),
    );
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
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, find.byKey(const Key('compra-completar-voz')));
    await settle(tester);
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

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  /// Rediseño: «Proveedor» está en la página; el resto, en la hoja del
  /// producto [at].
  Future<void> show(WidgetTester tester, String label, int at) async {
    if (label == 'Proveedor') {
      await closePurchaseLine(tester);
    } else {
      await openPurchaseLine(tester, at);
    }
  }

  Future<String?> picked(
    WidgetTester tester,
    String label, [
    int at = 0,
  ]) async {
    await show(tester, label, at);
    return tester
        .widget<AdaptiveEntityPicker<Row>>(picker(label))
        .value?['name']
        ?.toString();
  }

  Future<void> choose(
    WidgetTester tester,
    String label,
    String name, [
    int at = 0,
  ]) async {
    await show(tester, label, at);
    final w = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == name));
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  Future<String> text(WidgetTester tester, String label, [int at = 0]) async {
    await show(tester, label, at);
    return tester.widget<TextField>(field(label)).controller!.text;
  }

  Future<void> enter(
    WidgetTester tester,
    String label,
    String value, [
    int at = 0,
  ]) async {
    await show(tester, label, at);
    await tester.enterText(field(label), value);
    await settle(tester);
  }

  /// «Continuar» está en el panel de abajo, con la hoja y el panel de voz
  /// cerrados.
  Future<bool> continueEnabled(WidgetTester tester) async {
    await closePurchaseLine(tester);
    return tester
            .widget<ButtonStyleButton>(
              find.descendant(
                of: find.byKey(const Key('purchase-continue')),
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
                matchRoot: true,
              ),
            )
            .onPressed !=
        null;
  }

  /// Líneas de la compra (tarjetas del paso 1).
  int lineCount() => find
      .byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            RegExp(r'^purchase-line-\d+$')
                .hasMatch((w.key! as ValueKey<String>).value),
        skipOffstage: false,
      )
      .evaluate()
      .length;

  Future<int> count(WidgetTester tester, AppDatabase db, String table) async =>
      (await tester.runAsync(() async => (await db.database).query(table)))!
          .length;

  /// «Hablar» y, si el turno espera a «Terminar», «Terminar».
  Future<void> dictate(WidgetTester tester, {bool terminate = true}) async {
    await tapKey(tester, 'voz-hablar');
    if (terminate) await tapKey(tester, 'voz-terminar');
    await settle(tester);
  }

  Future<String> panelMessage(WidgetTester tester) async {
    await closePurchaseLine(tester);
    return tester
        .widget<Text>(find.byKey(const Key('voz-panel-mensaje')))
        .data!;
  }

  testWidgets('registro completamente manual con el panel abierto: un solo '
      'registro, sin pasar por la voz', (tester) async {
    final w = await open(tester, 'u-manual', const []);
    await tapKey(tester, 'compra-completar-voz');
    expect(find.byKey(const Key('voz-panel')), findsOneWidget);
    expect(port.startRequests, isEmpty, reason: 'el micrófono no se abre solo');
    await choose(tester, 'Proveedor', 'Proveedor');
    await choose(tester, 'Producto', 'Glifosato');
    await enter(tester, 'Cantidad comprada', '2');
    await enter(tester, 'Precio por L', '45');
    await settle(tester);
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Hermana');
    // Rediseño: el panel de voz ocupa el lugar de «Continuar» (como en el
    // prototipo); se cierra con su ✕ y el borrador sigue igual.
    expect(find.byKey(const Key('purchase-continue')), findsNothing);
    await tapKey(tester, 'voz-panel-cerrar');
    await tapKey(tester, 'purchase-continue');
    await tester.tap(find.byKey(const Key('purchase-paid-no')));
    await settle(tester);
    expect(await count(tester, w.database, 'purchases'), 0);
    await tapKey(tester, 'purchase-confirm');
    // La transición de salida tras guardar.
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(await count(tester, w.database, 'purchases'), 1);
    expect(await count(tester, w.database, 'purchase_items'), 1);
  });

  testWidgets('voz en campos vacíos: completa y marca «Por voz»; nada se '
      'escribe hasta confirmar; una sola compra con sus efectos', (
    tester,
  ) async {
    final w = await open(tester, 'u-vacios', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(await picked(tester, 'Proveedor'), 'Agro Norte');
    expect(await picked(tester, 'Producto'), 'Glifosato');
    expect(await text(tester, 'Cantidad comprada'), '10');
    expect(await text(tester, 'Precio por L'), '50');
    expect(lineCount(), 1, reason: 'usa la línea inicial');
    await closePurchaseLine(tester);
    expect(find.byKey(const Key('voz-marca-supplier')), findsOneWidget);
    expect(find.text('Por voz'), findsWidgets);
    expect(await continueEnabled(tester), isTrue);
    expect(await count(tester, w.database, 'purchases'), 0);
    await tapKey(tester, 'purchase-continue');
    await tester.tap(find.byKey(const Key('purchase-paid-no')));
    await settle(tester);
    await tapKey(tester, 'purchase-confirm');
    await settle(tester);
    expect(await count(tester, w.database, 'purchases'), 1);
    final item = (await tester.runAsync(
      () async => (await w.database.database).query('purchase_items'),
    ))!.single;
    expect(item['quantity_base'], 10000);
    final allocations = (await tester.runAsync(
      () async => (await w.database.database).query('purchase_allocations'),
    ))!;
    expect(allocations, hasLength(1));
  });

  testWidgets('mixto: el producto elegido a mano y cantidad y precio '
      'dictados (nombrando el producto) completan la misma línea, sin otra', (
    tester,
  ) async {
    await open(tester, 'u-mixto', [
      const FakeTurn(
        segment: 'diez litros de Glifosato a 50 bolivianos el litro',
        endsOnStop: true,
      ),
    ]);
    await choose(tester, 'Producto', 'Glifosato');
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(lineCount(), 1);
    expect(await picked(tester, 'Producto'), 'Glifosato');
    expect(await text(tester, 'Cantidad comprada'), '10');
    expect(await text(tester, 'Precio por L'), '50');
    expect(find.byKey(const Key('voz-marca-quantity@1')), findsOneWidget);
    expect(
      find.byKey(const Key('voz-marca-product@1')),
      findsNothing,
      reason: 'el producto lo eligió la persona',
    );
  });

  testWidgets('cantidad dictada sin nombrar el producto: no se asigna a '
      'ciegas y se avisa', (tester) async {
    await open(tester, 'u-sin-producto', [
      const FakeTurn(
        segment: 'diez litros a 50 bolivianos el litro',
        endsOnStop: true,
      ),
    ]);
    await choose(tester, 'Producto', 'Glifosato');
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(await text(tester, 'Cantidad comprada'), '');
    await closePurchaseLine(tester);
    expect(find.byKey(const Key('voz-panel-aviso-0')), findsOneWidget);
  });

  testWidgets('conflicto: un valor distinto al que ya hay no se sobrescribe; '
      'se elige y hasta entonces no se puede continuar', (tester) async {
    await open(tester, 'u-conflicto', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await choose(tester, 'Proveedor', 'Proveedor');
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(await picked(tester, 'Proveedor'), 'Proveedor');
    expect(find.byKey(const Key('voz-elegir-supplier')), findsOneWidget);
    expect(await continueEnabled(tester), isFalse);
    expect(find.byKey(const Key('voz-bloqueo-guardar')), findsOneWidget);
    await tapKey(tester, 'voz-usar-supplier');
    expect(await picked(tester, 'Proveedor'), 'Agro Norte');
    expect(find.byKey(const Key('voz-elegir-supplier')), findsNothing);
    expect(find.text('Confirmado'), findsOneWidget);
    expect(await continueEnabled(tester), isTrue);
  });

  testWidgets('edición manual mientras se procesa: el resultado tardío no '
      'pisa lo editado', (tester) async {
    await open(tester, 'u-edicion', [
      const FakeTurn(segment: full, delay: Duration(seconds: 2)),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await tester.tap(find.byKey(const Key('voz-hablar')));
    await tester.pump();
    await choose(tester, 'Proveedor', 'Proveedor');
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(await picked(tester, 'Proveedor'), 'Proveedor');
    expect(find.byKey(const Key('voz-elegir-supplier')), findsNothing);
    expect(await panelMessage(tester), contains('Se conservó lo que editó'));
    // Lo demás del dictado sí se incorporó.
    expect(await text(tester, 'Cantidad comprada'), '10');
  });

  testWidgets('producto repetido: no se suma ni se fusiona; la línea nueva '
      'queda con el producto por revisar', (tester) async {
    await open(tester, 'u-repetido', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await choose(tester, 'Producto', 'Glifosato');
    await enter(tester, 'Cantidad comprada', '3');
    await enter(tester, 'Precio por L', '40');
    await settle(tester);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(lineCount(), 2);
    expect(
      await text(tester, 'Cantidad comprada'),
      '3',
      reason: 'línea 1 intacta',
    );
    expect(await text(tester, 'Cantidad comprada', 1), '10');
    expect(await picked(tester, 'Producto', 1), isNull);
    expect(
      reachable(find.byKey(const Key('voz-revisar-product@2'))),
      findsOneWidget,
    );
    // En la tarjeta de la línea 2 también, con «Elegir otro» para escribirlo.
    await closePurchaseLine(tester);
    expect(find.byKey(const Key('voz-revisar-product@2')), findsOneWidget);
    expect(find.byKey(const Key('voz-escribir-product@2')), findsOneWidget);
    expect(await continueEnabled(tester), isFalse);
  });

  testWidgets('deshacer el último dictado no pierde una edición posterior', (
    tester,
  ) async {
    await open(tester, 'u-deshacer', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(await picked(tester, 'Proveedor'), 'Agro Norte');
    await enter(tester, 'Cantidad comprada', '12');
    await settle(tester);
    await tapKey(tester, 'voz-deshacer');
    expect(await picked(tester, 'Proveedor'), isNull);
    expect(await picked(tester, 'Producto'), isNull);
    // Sin producto, el campo vuelve a llamarse «Precio por unidad».
    expect(await text(tester, 'Precio por unidad'), '');
    expect(
      await text(tester, 'Cantidad comprada'),
      '12',
      reason: 'editada después',
    );
    expect(
      await panelMessage(tester),
      contains('Se conservó lo que editó después'),
    );
    expect(find.byKey(const Key('voz-deshacer')), findsNothing);
  });

  // Regresión (2026-11-12, rediseño bloque 1): con el precio por revisar,
  // «Deshacer último dictado» decía «Se conservó lo que editó después (línea
  // 1: moneda)» sin que nadie tocara la moneda, la tarjeta seguía «Por voz» y
  // la revisión del precio de ese dictado seguía pendiente.
  testWidgets('deshacer con el precio por revisar: no inventa una edición, '
      'quita las marcas y la revisión de ese dictado', (tester) async {
    await open(tester, 'u-deshacer-revision', [
      const FakeTurn(
        segment: 'compra de diez litros de Glifosato a 50 bolivianos',
        endsOnStop: true,
      ),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(await text(tester, 'Cantidad comprada'), '10');
    await closePurchaseLine(tester);
    expect(find.byKey(const Key('voz-revisar-price@1')), findsOneWidget);
    await tapKey(tester, 'voz-deshacer');
    expect(await panelMessage(tester), 'Se deshizo el último dictado.');
    expect(await picked(tester, 'Producto'), isNull);
    expect(await text(tester, 'Cantidad comprada'), '');
    expect(await text(tester, 'Precio por unidad'), '');
    await closePurchaseLine(tester);
    expect(find.text('Por voz'), findsNothing);
    expect(find.byKey(const Key('voz-revisar-price@1')), findsNothing);
    expect(find.text('Falta: precio'), findsNothing);
  });

  testWidgets('deshacer un dictado en dólares con el precio por revisar '
      'devuelve la moneda a bolivianos', (tester) async {
    await open(tester, 'u-deshacer-usd', [
      const FakeTurn(
        segment: 'compra de diez litros de Glifosato a 50 dólares',
        endsOnStop: true,
      ),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    await openPurchaseLine(tester);
    expect(segmentSelected(tester, 'purchase-currency-usd-0'), isTrue);
    await tapKey(tester, 'voz-deshacer');
    expect(await panelMessage(tester), 'Se deshizo el último dictado.');
    await openPurchaseLine(tester);
    expect(segmentSelected(tester, 'purchase-currency-bob-0'), isTrue);
    expect(await text(tester, 'Cantidad comprada'), '');
  });

  testWidgets('cancelar el dictado conserva el formulario; el resultado '
      'tardío del turno cancelado no lo cambia', (tester) async {
    await open(tester, 'u-cancelar', [
      const FakeTurn(segment: full, delay: Duration(seconds: 2)),
    ]);
    await choose(tester, 'Producto', 'Glifosato');
    await tapKey(tester, 'compra-completar-voz');
    await tester.tap(find.byKey(const Key('voz-hablar')));
    await tester.pump();
    await tapKey(tester, 'voz-cancelar-dictado');
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(await picked(tester, 'Proveedor'), isNull);
    expect(
      await picked(tester, 'Producto'),
      'Glifosato',
      reason: 'lo manual sigue',
    );
    expect(await text(tester, 'Cantidad comprada'), '');
    expect(await panelMessage(tester), contains('cancelado'));
  });

  testWidgets('ambiguo: precio sin «el litro» → revisar; «Total de la línea» '
      'reparte entre la cantidad', (tester) async {
    await open(tester, 'u-ambiguo', [
      const FakeTurn(
        segment: 'compra de diez litros de Glifosato a 50 bolivianos',
        endsOnStop: true,
      ),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(await text(tester, 'Cantidad comprada'), '10');
    expect(await text(tester, 'Precio por L'), '');
    expect(
      reachable(find.byKey(const Key('voz-revisar-price@1'))),
      findsOneWidget,
    );
    expect(reachable(find.text('Falta: precio')), findsOneWidget);
    // Además de las opciones del intérprete, se puede escribir otro valor:
    // lleva a la hoja del producto, con el campo a la vista.
    await closePurchaseLine(tester);
    expect(find.byKey(const Key('voz-escribir-price@1')), findsOneWidget);
    expect(await continueEnabled(tester), isFalse);
    await tapKey(tester, 'voz-opcion-price@1-1'); // «Total de la línea»
    expect(await text(tester, 'Precio por L'), '5');
    expect(find.text('Confirmado'), findsOneWidget);
    expect(await continueEnabled(tester), isTrue);
  });

  testWidgets('negación: el dictado no cambia el formulario', (tester) async {
    await open(tester, 'u-negacion', [
      const FakeTurn(segment: 'no compré Glifosato', endsOnStop: true),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(await picked(tester, 'Producto'), isNull);
    expect(await text(tester, 'Cantidad comprada'), '');
    expect(await panelMessage(tester), contains('No cambió el formulario'));
    expect(find.byKey(const Key('voz-deshacer')), findsNothing);
  });

  testWidgets('salir del formulario libera el micrófono sin aplicar nada', (
    tester,
  ) async {
    await open(tester, 'u-salir', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await tester.tap(find.byKey(const Key('voz-hablar')));
    await settle(tester);
    expect(port.microphoneOpen, isTrue);
    // Atrás del formulario (sin cambios: no pregunta).
    await tester.tap(find.byKey(const Key('purchase-close')));
    await tester.pump();
    // La transición de salida de la ruta.
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.byKey(const Key('voz-panel')), findsNothing);
    expect(port.calls, contains('dispose'));
    expect(port.microphoneOpen, isFalse);
  });
}
