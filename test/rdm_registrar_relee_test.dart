// Rediseño (2026-11-12, recorrido del emulador): lo registrado desde la hoja
// «+ Registrar» del shell aparece en Actividad al volver.
//
// Defecto visto en `emulator-5556` con la candidata 6b397c9: tras guardar un
// plan (y una transferencia) desde la hoja, Actividad seguía diciendo «No hay
// planes pendientes» hasta cambiar de pestaña. Actividad sólo releía al
// volver de las pantallas que abría ella misma; la hoja del shell abre los
// formularios por su cuenta. En la base (01b2576) Operaciones era un menú sin
// historial, así que no pasaba.
//
// App real (router, base en archivo, repositorio). El guardado se simula con
// el repositorio mientras el formulario está abierto: lo que se comprueba es
// que, al cerrarse el formulario abierto desde la hoja, Actividad relee.
import 'package:agroquimicos/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('un plan guardado desde la hoja «Registrar» aparece en '
      'Actividad al volver, sin cambiar de pestaña', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final s = await activatedHousehold(tester, 'rdm_registrar_relee');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    expect(find.textContaining('Plan · Chaco titular'), findsNothing);

    await tester.tap(find.byKey(const Key('shell-registrar')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('register-plan')));
    await settle(tester);
    expect(find.text('Guardar plan'), findsOneWidget);

    // Guardado mientras el formulario está abierto (lo que hace «Guardar
    // plan»), y el formulario se cierra.
    await tester.runAsync(
      () => s.household.repo.addPlan(
        farmId: s.household.titularFarm,
        campaignId: s.household.campaign,
        productId: s.household.product,
        areaM2: 10000,
        doseBasePerHa: 500,
      ),
    );
    c.read(routerProvider).pop(true);
    await settle(tester);

    expect(currentPath(c), '/operaciones');
    expect(find.textContaining('Plan · Chaco titular'), findsOneWidget);
  });
}
