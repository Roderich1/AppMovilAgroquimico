import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra la navegación principal', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AgroApp()));
    await tester.pump();
    expect(find.text('Inicio'), findsWidgets);
    expect(find.text('Operaciones'), findsWidgets);
    expect(find.text('Inventario'), findsWidgets);
    expect(find.text('Cuentas'), findsOneWidget);
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
    expect(find.text('Operaciones'), findsOneWidget);
  });
}
