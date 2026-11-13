// Modo individual — pantallas de «Chacos» en la app real (sesión C,
// 2026-11-13; láminas I-40 a I-43): lista del titular, detalle, costos,
// estado vacío con alta del primer chaco, y el modo con varias personas sin
// cambios (bitácora en `/chacos/:id` y «Personas» en la barra).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  Finder inBar(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  Future<void> goTo(WidgetTester tester, dynamic c, String path) async {
    c.read(routerProvider).go(path);
    await settle(tester);
  }

  testWidgets('modo individual: Chacos lista sólo los del titular, abre el '
      'detalle y los costos, y Atrás vuelve', (tester) async {
    // Teléfono de 393 × 852 dp.
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'ind_c_ui_personal');
    final h = s.household;
    await tester.runAsync(() async {
      await h.buy(h.titular, 3000);
      await h.repo.confirmApplication(
        ApplicationDraft(
          personId: h.titular,
          farmId: h.titularFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.utc(2026, 2, 1),
          treatedAreaM2: 5000,
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 2000),
          ],
        ),
      );
      await OperationModeStore(s.database)
          .apply(OperationMode.personal, confirmed: true);
    });
    final c = await pumpModeApp(tester, s.database);
    expect(inBar('Chacos'), findsOneWidget);
    expect(inBar('Personas'), findsNothing);

    await goTo(tester, c, '/chacos');
    expect(find.text('Chaco titular'), findsOneWidget);
    expect(find.text('Chaco hermana'), findsNothing);
    expect(find.text('Costos · Campaña 1'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('ind-chacos-costos-total')))
          .data,
      '200,00',
    );
    expect(find.text('1 aplicación'), findsOneWidget);

    await tester.tap(find.byKey(Key('ind-chaco-${h.titularFarm}')));
    await settle(tester);
    expect(find.text('Superficie del chaco: 1 ha'), findsOneWidget);
    expect(find.text('APLICACIONES · 1'), findsOneWidget);
    expect(find.textContaining('superficie tratada 0,5 ha'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('ind-chaco-por-ha-valor'))).data,
      '200,00',
    );

    await tester.ensureVisible(find.byKey(const Key('ind-chaco-ver-costos')));
    await tester.pump();
    // Alcanzable: el enlace queda por encima de la barra inferior.
    expect(
      tester.getRect(find.byKey(const Key('ind-chaco-ver-costos'))).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
    );
    await tester.tap(find.byKey(const Key('ind-chaco-ver-costos')));
    await settle(tester);
    expect(find.text('Costos'), findsOneWidget);
    expect(
      find.text('Costo de productos aplicados · Campaña 1'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Costo por hectárea · sobre 1 ha del chaco'),
      findsOneWidget,
    );
    expect(
      find.text('Superficie tratada acumulada: 0,5 ha en 1 aplicación'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('ind-costos-por-producto')));
    await settle(tester);
    expect(find.text('Glifosato'), findsOneWidget);
    expect(find.textContaining('2 L · en 1 aplicación'), findsOneWidget);

    // Atrás del sistema: vuelve al detalle, dentro de la pestaña Chacos.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Superficie del chaco: 1 ha'), findsOneWidget);
    expect(inBar('Chacos'), findsOneWidget);
  });

  testWidgets('modo individual sin chacos: estado vacío y alta del primero '
      'con el titular como propietario', (tester) async {
    final file = await tester.runAsync(() => tempDbPath('ind_c_ui_empty'));
    final database = openDb(file!);
    final owner = await tester.runAsync(() async {
      final binding = await seedActivatedInstallation(database);
      final repo = AgroRepository(database);
      await repo.addCampaign(name: 'Invierno 2026', start: DateTime.utc(2026));
      await OperationModeStore(database)
          .apply(OperationMode.personal, confirmed: true);
      return binding.personId;
    });
    final c = await pumpModeApp(tester, database);
    await goTo(tester, c, '/chacos');
    expect(find.text('Agregue su primer chaco'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ind-chacos-agregar')));
    await settle(tester);
    expect(find.byKey(const Key('farm-personal-owner')), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre'),
      'Chaco Norte',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Superficie (ha)'),
      '3',
    );
    await tester.tap(find.text('Guardar'));
    await settle(tester);

    final farms = await tester.runAsync(
      () async => (await database.database).query('farms'),
    );
    expect(farms, hasLength(1));
    expect(farms!.single['owner_person_id'], owner);
    expect(farms.single['area_m2'], 30000);
    // La escritura no muestra indicador: se espera a que la lista se relea.
    await waitFor(tester, find.text('Chaco Norte'));
    expect(find.text('Chaco Norte'), findsOneWidget);
    expect(find.text('Agregue su primer chaco'), findsNothing);
    // Sin aplicaciones no se muestra un costo en cero.
    expect(find.byKey(const Key('ind-chacos-costos-total')), findsNothing);
    expect(
      find.text('Todavía no hay aplicaciones en esta campaña'),
      findsOneWidget,
    );
  });

  testWidgets('modo con varias personas: la barra conserva Personas y '
      '/chacos/:id sigue siendo la bitácora', (tester) async {
    final s = await activatedHousehold(tester, 'ind_c_ui_shared');
    final c = await pumpModeApp(tester, s.database);
    expect(inBar('Personas'), findsOneWidget);
    expect(inBar('Chacos'), findsNothing);

    await goTo(tester, c, '/chacos/${s.household.relativeFarm}');
    expect(find.text('Bitácora'), findsOneWidget);
    expect(find.text('Chaco hermana'), findsOneWidget);
    expect(find.text('Superficie del chaco: 0,5 ha'), findsNothing);
  });
}
