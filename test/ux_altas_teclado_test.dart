// Presentación móvil (2026-11-05): el teclado y el «+» no tapan las acciones
// de las altas en el selector. En 360×800 con la letra al 100 % y al 200 % y
// el teclado abierto (300 px):
//   (a) el diálogo «Nuevo producto» deja «Guardar» y «Cancelar» por encima
//       del teclado y tocables;
//   (b) la hoja del selector deja «Crear producto» por encima del teclado;
//   (c) en Operaciones el «+» desaparece con el teclado y vuelve sin él.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

typedef Row = Map<String, Object?>;

const _keyboard = 300.0;
const _screen = Size(360, 800);

void main() {
  sqfliteFfiInit();

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  void phone(WidgetTester tester, double textScale) {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> openKeyboard(WidgetTester tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    await tester.pump();
    await settle(tester);
  }

  void expectAboveKeyboard(WidgetTester tester, Finder target, String what) {
    expect(target, findsOneWidget, reason: what);
    final rect = tester.getRect(target);
    expect(
      rect.bottom,
      lessThanOrEqualTo(_screen.height - _keyboard),
      reason: '$what queda bajo el teclado: $rect',
    );
    expect(rect.top, greaterThanOrEqualTo(0), reason: '$what fuera de vista');
    // Lo que se ve también recibe el toque.
    final hit = tester.hitTestOnBinding(rect.center);
    final element = target.evaluate().single;
    final targetRender = element.renderObject!;
    expect(
      hit.path.any((entry) => identical(entry.target, targetRender)),
      isTrue,
      reason: '$what no recibe el toque',
    );
  }

  Future<ProviderContainer> purchaseForm(
    WidgetTester tester,
    String name,
  ) async {
    final s = await activatedHousehold(tester, name);
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, picker('Proveedor'));
    await settle(tester);
    return c;
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('(a) letra ${scale * 100} %: «Guardar» del alta de producto '
        'por encima del teclado', (tester) async {
      phone(tester, scale);
      await purchaseForm(tester, 'kb-a-$scale');
      // Al 200 % la línea queda fuera de lo construido por la lista.
      await tester.scrollUntilVisible(
        picker('Producto'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Entero en pantalla, no a medias bajo la barra de «Continuar».
      await tester.ensureVisible(picker('Producto'));
      await settle(tester);
      await tester.tap(picker('Producto'));
      await settle(tester);
      await tester.tap(find.text('Crear producto'));
      await settle(tester);
      expect(find.text('Nuevo producto'), findsOneWidget);
      await openKeyboard(tester);

      expectAboveKeyboard(tester, find.text('Guardar'), '«Guardar»');
      expectAboveKeyboard(tester, find.text('Cancelar'), '«Cancelar»');
      expect(tester.takeException(), isNull);
    });

    testWidgets('(b) letra ${scale * 100} %: «Crear producto» de la hoja por '
        'encima del teclado', (tester) async {
      phone(tester, scale);
      await purchaseForm(tester, 'kb-b-$scale');
      await tester.ensureVisible(picker('Proveedor'));
      await tester.tap(picker('Proveedor'));
      await settle(tester);
      await openKeyboard(tester);

      expectAboveKeyboard(
        tester,
        find.text('Crear proveedor'),
        '«Crear proveedor»',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('(c) letra ${scale * 100} %: en Operaciones el «+» se va con '
        'el teclado', (tester) async {
      phone(tester, scale);
      final s = await activatedHousehold(tester, 'kb-c-$scale');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/operaciones');
      await settle(tester);
      expect(find.byTooltip('Registrar operación'), findsOneWidget);

      await openKeyboard(tester);
      expect(find.byTooltip('Registrar operación'), findsNothing);

      tester.view.resetViewInsets();
      await tester.pump();
      await settle(tester);
      expect(find.byTooltip('Registrar operación'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
