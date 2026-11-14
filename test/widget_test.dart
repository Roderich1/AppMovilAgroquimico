import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/f04_app_access.dart';

void main() {
  testWidgets('muestra la navegación principal', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activatedInstallationForTests()],
        child: const AgroApp(),
      ),
    );
    await tester.pump();
    expect(find.text('Inicio'), findsWidgets);
    // Barra del rediseño (2026-11-12): Cuentas vive bajo Personas.
    expect(find.text('Actividad'), findsWidgets);
    expect(find.text('Almacén'), findsWidgets);
    expect(find.text('Personas'), findsWidgets);
    expect(find.text('Sindicato'), findsWidgets);
    expect(find.text('Cuentas'), findsNothing);
  });

  testWidgets('navegación no desborda en pantalla angosta y texto grande', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      const MaterialApp(
        home: AppShell(location: '/', child: SizedBox()),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Actividad'), findsOneWidget);
    expect(find.text('Sindicato'), findsOneWidget);
  });
}
