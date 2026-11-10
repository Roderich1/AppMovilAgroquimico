import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  String? picked(WidgetTester tester, String label, [int at = 0]) => tester
      .widgetList<AdaptiveEntityPicker<Row>>(picker(label))
      .elementAt(at)
      .value?['name']
      ?.toString();

  Future<void> choose(
    WidgetTester tester,
    String label,
    String name, [
    int at = 0,
  ]) async {
    final w = tester
        .widgetList<AdaptiveEntityPicker<Row>>(picker(label))
        .elementAt(at);
    w.onChanged(w.items.firstWhere((i) => w.labelOf(i) == name));
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  String text(WidgetTester tester, String label, [int at = 0]) =>
      tester.widgetList<TextField>(field(label)).elementAt(at).controller!.text;

  bool continueEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('purchase-continue')))
          .onPressed !=
      null;

  Future<int> count(WidgetTester tester, AppDatabase db, String table) async =>
      (await tester.runAsync(() async => (await db.database).query(table)))!
          .length;

  /// «Hablar» y, si el turno espera a «Terminar», «Terminar».
  Future<void> dictate(WidgetTester tester, {bool terminate = true}) async {
    await tapKey(tester, 'voz-hablar');
    if (terminate) await tapKey(tester, 'voz-terminar');
    await settle(tester);
  }

  String panelMessage(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('voz-panel-mensaje'))).data!;

  testWidgets('registro completamente manual con el panel abierto: un solo '
      'registro, sin pasar por la voz', (tester) async {
    final w = await open(tester, 'u-manual', const []);
    await tapKey(tester, 'compra-completar-voz');
    expect(find.byKey(const Key('voz-panel')), findsOneWidget);
    expect(port.startRequests, isEmpty, reason: 'el micrófono no se abre solo');
    await choose(tester, 'Proveedor', 'Proveedor');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '2');
    await tester.enterText(field('Precio BOB/L'), '45');
    await settle(tester);
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Hermana');
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
    expect(picked(tester, 'Proveedor'), 'Agro Norte');
    expect(picked(tester, 'Producto'), 'Glifosato');
    expect(text(tester, 'Cantidad comprada'), '10');
    expect(text(tester, 'Precio BOB/L'), '50');
    expect(
      find.text('Productos (1)'),
      findsOneWidget,
      reason: 'usa la línea inicial',
    );
    expect(find.byKey(const Key('voz-marca-supplier')), findsOneWidget);
    expect(find.text('Por voz'), findsWidgets);
    expect(continueEnabled(tester), isTrue);
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
    expect(find.text('Productos (1)'), findsOneWidget);
    expect(picked(tester, 'Producto'), 'Glifosato');
    expect(text(tester, 'Cantidad comprada'), '10');
    expect(text(tester, 'Precio BOB/L'), '50');
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
    expect(text(tester, 'Cantidad comprada'), '');
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
    expect(picked(tester, 'Proveedor'), 'Proveedor');
    expect(find.byKey(const Key('voz-elegir-supplier')), findsOneWidget);
    expect(continueEnabled(tester), isFalse);
    expect(find.byKey(const Key('voz-bloqueo-guardar')), findsOneWidget);
    await tapKey(tester, 'voz-usar-supplier');
    expect(picked(tester, 'Proveedor'), 'Agro Norte');
    expect(find.byKey(const Key('voz-elegir-supplier')), findsNothing);
    expect(find.text('Confirmado'), findsOneWidget);
    expect(continueEnabled(tester), isTrue);
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
    expect(picked(tester, 'Proveedor'), 'Proveedor');
    expect(find.byKey(const Key('voz-elegir-supplier')), findsNothing);
    expect(panelMessage(tester), contains('Se conservó lo que editó'));
    // Lo demás del dictado sí se incorporó.
    expect(text(tester, 'Cantidad comprada'), '10');
  });

  testWidgets('producto repetido: no se suma ni se fusiona; la línea nueva '
      'queda con el producto por revisar', (tester) async {
    await open(tester, 'u-repetido', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '3');
    await tester.enterText(field('Precio BOB/L'), '40');
    await settle(tester);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(find.text('Productos (2)'), findsOneWidget);
    expect(text(tester, 'Cantidad comprada'), '3', reason: 'línea 1 intacta');
    expect(text(tester, 'Cantidad comprada', 1), '10');
    expect(picked(tester, 'Producto', 1), isNull);
    expect(find.byKey(const Key('voz-revisar-product@2')), findsOneWidget);
    expect(continueEnabled(tester), isFalse);
  });

  testWidgets('deshacer el último dictado no pierde una edición posterior', (
    tester,
  ) async {
    await open(tester, 'u-deshacer', [
      const FakeTurn(segment: full, endsOnStop: true),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(picked(tester, 'Proveedor'), 'Agro Norte');
    await tester.enterText(field('Cantidad comprada'), '12');
    await settle(tester);
    await tapKey(tester, 'voz-deshacer');
    expect(picked(tester, 'Proveedor'), isNull);
    expect(picked(tester, 'Producto'), isNull);
    // Sin producto, el campo vuelve a llamarse «Precio por unidad».
    expect(text(tester, 'Precio por unidad'), '');
    expect(text(tester, 'Cantidad comprada'), '12', reason: 'editada después');
    expect(panelMessage(tester), contains('Se conservó lo que editó después'));
    expect(find.byKey(const Key('voz-deshacer')), findsNothing);
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
    expect(picked(tester, 'Proveedor'), isNull);
    expect(picked(tester, 'Producto'), 'Glifosato', reason: 'lo manual sigue');
    expect(text(tester, 'Cantidad comprada'), '');
    expect(panelMessage(tester), contains('cancelado'));
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
    expect(text(tester, 'Cantidad comprada'), '10');
    expect(text(tester, 'Precio BOB/L'), '');
    expect(find.byKey(const Key('voz-revisar-price@1')), findsOneWidget);
    expect(find.text('Falta: precio'), findsOneWidget);
    expect(continueEnabled(tester), isFalse);
    await tapKey(tester, 'voz-opcion-price@1-1'); // «Total de la línea»
    expect(text(tester, 'Precio BOB/L'), '5');
    expect(find.text('Confirmado'), findsOneWidget);
    expect(continueEnabled(tester), isTrue);
  });

  testWidgets('negación: el dictado no cambia el formulario', (tester) async {
    await open(tester, 'u-negacion', [
      const FakeTurn(segment: 'no compré Glifosato', endsOnStop: true),
    ]);
    await tapKey(tester, 'compra-completar-voz');
    await dictate(tester);
    expect(picked(tester, 'Producto'), isNull);
    expect(text(tester, 'Cantidad comprada'), '');
    expect(panelMessage(tester), contains('No cambió el formulario'));
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
    final back = find.descendant(
      of: find.byType(AppBar).last,
      matching: find.byIcon(Icons.arrow_back),
    );
    await tester.tap(back);
    await tester.pump();
    // La transición de salida de la ruta.
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.byKey(const Key('voz-panel')), findsNothing);
    expect(port.calls, contains('dispose'));
    expect(port.microphoneOpen, isFalse);
  });
}
