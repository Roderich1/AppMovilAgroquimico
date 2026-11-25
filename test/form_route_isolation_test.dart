import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/screens/application_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('dos rutas de compra mantienen borradores independientes', (
    tester,
  ) async {
    final fixture = await activatedHousehold(tester, 'compra-rutas');
    final container = await pumpModeApp(tester, fixture.database);
    final router = container.read(routerProvider);
    final add = find.byKey(const Key('purchase-add-line'));
    final sheet = find.byKey(const Key('purchase-line-sheet-0'));

    router.push('/compras/nueva');
    await waitFor(tester, add);
    await tester.ensureVisible(add);
    await tester.tap(add);
    await settle(tester);
    expect(sheet, findsOneWidget);

    router.push('/compras/nueva');
    await settle(tester);
    expect(add, findsOneWidget);
    expect(sheet, findsNothing);

    router.pop();
    await settle(tester);
    expect(sheet, findsOneWidget);
  });

  testWidgets('dos rutas de aplicación mantienen borradores independientes', (
    tester,
  ) async {
    final fixture = await activatedHousehold(tester, 'aplicacion-rutas');
    final container = await pumpModeApp(tester, fixture.database);
    final router = container.read(routerProvider);
    final area = find.byKey(const Key('application-area'));
    final popScope = find.descendant(
      of: find.byType(ApplicationFormScreen),
      matching: find.byWidgetPredicate((widget) => widget is PopScope),
    );

    router.push('/aplicaciones/nueva');
    await waitFor(tester, area);
    await tester.enterText(area, '2.5');
    await settle(tester);
    expect(tester.widget<PopScope<Object?>>(popScope).canPop, isFalse);

    router.push('/aplicaciones/nueva');
    await settle(tester);
    expect(tester.widget<PopScope<Object?>>(popScope).canPop, isTrue);

    router.pop();
    await settle(tester);
    expect(tester.widget<TextField>(area).controller!.text, '2.5');
    expect(tester.widget<PopScope<Object?>>(popScope).canPop, isFalse);
  });
}
