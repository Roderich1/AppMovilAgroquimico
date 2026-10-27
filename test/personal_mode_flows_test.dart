// MODE-03 (#26): en inventario propio la navegación y los formularios no
// ofrecen transferencias ni elección de responsables; el titular se aplica
// internamente. En compartido siguen igual. Un solo dominio y una sola base:
// la modalidad sólo cambia lo que se muestra; el repositorio aplica la regla.
// App real (base en archivo, router, repositorio y controlador de acceso).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/presentation/screens/transfers_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  /// Elige en un selector la opción cuyo nombre es [name], como al tocarla.
  Future<void> choose(WidgetTester tester, String label, String name) async {
    final widget = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
    widget.onChanged(
      widget.items.firstWhere((item) => widget.labelOf(item) == name),
    );
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  /// Campos que el agricultor tiene que completar en pantalla: selectores y
  /// cuadros de texto habilitados.
  int inputCount(WidgetTester tester) =>
      tester
          .widgetList<AdaptiveEntityPicker<Row>>(
            find.byWidgetPredicate((w) => w is AdaptiveEntityPicker<Row>),
          )
          .length +
      tester
          .widgetList<TextField>(find.byType(TextField))
          .where((w) => w.enabled ?? true)
          .length;

  Future<void> openNewSheet(WidgetTester tester) async {
    await tester.tap(find.text('Nuevo'));
    await settle(tester);
  }

  group('navegación', () {
    testWidgets('propio: Operaciones y «Nuevo» no ofrecen transferencias; '
        'compartido sí', (tester) async {
      final s = await activatedHousehold(tester, 'nav');
      await tester.runAsync(
        () =>
            OperationModeStore(s.database)
                .apply(OperationMode.personal, confirmed: true),
      );
      final c = await pumpModeApp(tester, s.database);
      expect(c.read(operationModeProvider), OperationMode.personal);

      c.read(routerProvider).go('/operaciones');
      await settle(tester);
      expect(find.text('Transferencias'), findsNothing);
      expect(find.text('Compras'), findsOneWidget);
      expect(find.text('Más'), findsOneWidget);
      await openNewSheet(tester);
      expect(find.text('Transferencia'), findsNothing);
      expect(find.text('Compra'), findsOneWidget);
      expect(find.text('Aplicación'), findsOneWidget);
      Navigator.of(tester.element(find.text('Compra'))).pop();
      await settle(tester);

      await switchModeBehindScreen(tester, c, s.database, OperationMode.shared);
      // La misma pantalla, abierta, cambia sin reiniciar.
      expect(find.text('Transferencias'), findsOneWidget);
      await openNewSheet(tester);
      expect(find.text('Transferencia'), findsOneWidget);
      Navigator.of(tester.element(find.text('Compra'))).pop();
      await settle(tester);
      // La modalidad vigente se lee en Más, Modo de uso (piloto X01).
      c.read(routerProvider).go('/mas');
      await settle(tester);
      expect(find.text('Ahora: inventario compartido'), findsOneWidget);
    });

    testWidgets('propio: abrir directamente una ruta de transferencias '
        'vuelve a Operaciones', (tester) async {
      final s = await activatedHousehold(tester, 'directa');
      await tester.runAsync(
        () =>
            OperationModeStore(s.database)
                .apply(OperationMode.personal, confirmed: true),
      );
      final c = await pumpModeApp(tester, s.database);
      for (final path in ['/transferencias', '/transferencias/nueva']) {
        c.read(routerProvider).go(path);
        await settle(tester);
        expect(currentPath(c), '/operaciones', reason: path);
      }
      expect(find.byType(TransfersScreen), findsNothing);
    });

    testWidgets('compartido → propio con Transferencias abierta, también '
        'debajo de otra pantalla: la app vuelve a Operaciones', (tester) async {
      final s = await activatedHousehold(tester, 'abierta');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/transferencias');
      await settle(tester);
      expect(find.byType(TransfersScreen), findsOneWidget);
      expect(find.text('Nueva'), findsOneWidget);

      await switchModeBehindScreen(
        tester,
        c,
        s.database,
        OperationMode.personal,
      );
      expect(currentPath(c), '/operaciones');
      expect(find.text('Transferencias'), findsNothing);

      // Transferencias debajo de Modo de uso: el router reevalúa la ruta de
      // debajo y también la cierra; no queda nada que desapilar.
      await switchModeBehindScreen(tester, c, s.database, OperationMode.shared);
      c.read(routerProvider).go('/transferencias');
      await settle(tester);
      c.read(routerProvider).push('/modo');
      await settle(tester);
      expect(find.byKey(const Key('mode-current')), findsOneWidget);
      await switchModeBehindScreen(
        tester,
        c,
        s.database,
        OperationMode.personal,
      );
      expect(currentPath(c), '/operaciones');
      expect(find.byType(TransfersScreen), findsNothing);
      expect(c.read(routerProvider).canPop(), isFalse);
    });

    testWidgets('Transferencias abierta desde la tarjeta de Operaciones '
        '(push) al pasar a propio: deja de ofrecer acciones y vuelve a '
        'Operaciones', (tester) async {
      // Con push go_router no cambia la ruta base (/operaciones), así que el
      // redirect no la cierra: es la propia pantalla la que se defiende.
      final s = await activatedHousehold(tester, 'push');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/operaciones');
      await settle(tester);
      await tester.tap(find.text('Transferencias'));
      await settle(tester);
      expect(find.byType(TransfersScreen), findsOneWidget);
      expect(find.text('Nueva'), findsOneWidget);

      await switchModeBehindScreen(
        tester,
        c,
        s.database,
        OperationMode.personal,
      );
      expect(find.byKey(const Key('shared-only-notice')), findsOneWidget);
      expect(find.text('Nueva'), findsNothing);
      await tester.tap(find.text('Volver a Operaciones'));
      await settle(tester);
      expect(currentPath(c), '/operaciones');
      expect(find.byType(TransfersScreen), findsNothing);
      expect(find.text('Más'), findsOneWidget);
    });

    testWidgets('si la pantalla de transferencias llegara a mostrarse en '
        'propio, no ofrece acciones', (tester) async {
      // Defensa de la propia pantalla, independiente del router.
      final s = await activatedHousehold(tester, 'defensa');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(AgroRepository(s.database)),
            operationModeProvider.overrideWith(
              () => _FixedMode(OperationMode.personal),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: TransfersScreen())),
        ),
      );
      await settle(tester);
      expect(find.byKey(const Key('shared-only-notice')), findsOneWidget);
      expect(find.text('Nueva'), findsNothing);
    });
  });

  group('formularios en propio', () {
    testWidgets('compra: sin reparto ni pagador que elegir, menos campos que '
        'en compartido, y todo queda para el titular', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'compra');
      final c = await pumpModeApp(tester, s.database);

      c.read(routerProvider).push('/compras/nueva');
      await waitFor(tester, field('Cantidad comprada'));
      await settle(tester);
      expect(find.text('¿Para quién es?'), findsOneWidget);
      expect(picker('Persona'), findsOneWidget);
      final sharedInputs = inputCount(tester);
      c.read(routerProvider).pop();
      await settle(tester);

      await switchModeBehindScreen(
        tester,
        c,
        s.database,
        OperationMode.personal,
      );
      c.read(routerProvider).push('/compras/nueva');
      await waitFor(tester, field('Cantidad comprada'));
      await settle(tester);
      expect(find.text('¿Para quién es?'), findsNothing);
      expect(picker('Persona'), findsNothing);
      expect(find.text('Para el titular: Titular'), findsOneWidget);
      expect(inputCount(tester), lessThan(sharedInputs));

      await choose(tester, 'Proveedor', 'Proveedor');
      await choose(tester, 'Producto', 'Glifosato');
      await tester.enterText(field('Cantidad comprada'), '4');
      await tester.enterText(field('Precio BOB/L'), '50');
      await settle(tester);
      // Paso 2: la pregunta explícita; paga el titular, sin elegir pagador.
      await tester.ensureVisible(find.byKey(const Key('purchase-continue')));
      await tester.tap(find.byKey(const Key('purchase-continue')));
      await settle(tester);
      expect(find.text('Pagador'), findsNothing);
      await tester.tap(find.byKey(const Key('purchase-paid-yes')));
      await settle(tester);
      expect(find.text('Pago registrado por: Titular'), findsOneWidget);
      await tester.tap(find.byKey(const Key('purchase-confirm')));
      await settle(tester);

      final rows = await tester.runAsync(() async {
        final db = await s.database.database;
        return (
          allocations: await db.query(
            'purchase_allocations',
            columns: ['person_id', 'quantity_base'],
          ),
          payments: await db.query(
            'provider_payments',
            columns: ['payer_person_id'],
          ),
        );
      });
      expect(rows!.allocations, [
        {'person_id': s.household.titular, 'quantity_base': 4000},
      ]);
      expect(rows.payments, [
        {'payer_person_id': s.household.titular},
      ]);
    });

    testWidgets('aplicación: aplica el titular sin elegirlo y sólo se '
        'ofrecen sus chacos', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'aplicacion');
      await tester.runAsync(() async {
        await s.household.buy(s.household.titular, 5000);
        await OperationModeStore(s.database)
            .apply(OperationMode.personal, confirmed: true);
      });
      final c = await pumpModeApp(tester, s.database);

      c.read(routerProvider).push('/aplicaciones/nueva');
      await waitFor(tester, picker('Chaco'));
      await settle(tester);
      expect(picker('Persona'), findsNothing);
      expect(
        find.byKey(const Key('application-personal-owner')),
        findsOneWidget,
      );
      final farms = tester
          .widget<AdaptiveEntityPicker<Row>>(picker('Chaco'))
          .items;
      expect([for (final f in farms) f['name']], ['Chaco titular']);
    });

    testWidgets('planificación: sólo los chacos del titular', (tester) async {
      final s = await activatedHousehold(tester, 'plan');
      await tester.runAsync(
        () =>
            OperationModeStore(s.database)
                .apply(OperationMode.personal, confirmed: true),
      );
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).push('/planificacion/nueva');
      await waitFor(tester, picker('Chaco'));
      await settle(tester);
      expect(
        [
          for (final f
              in tester
                  .widget<AdaptiveEntityPicker<Row>>(picker('Chaco'))
                  .items)
            f['name'],
        ],
        ['Chaco titular'],
      );
    });

    testWidgets('catálogos: no se agregan responsables y el chaco nuevo es '
        'del titular sin elegirlo', (tester) async {
      final s = await activatedHousehold(tester, 'catalogos');
      await tester.runAsync(
        () =>
            OperationModeStore(s.database)
                .apply(OperationMode.personal, confirmed: true),
      );
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/catalogos');
      await settle(tester);
      expect(find.text('Agregar persona'), findsNothing);
      expect(
        find.byKey(const Key('catalogs-personal-persons-notice')),
        findsOneWidget,
      );
      // Las personas ya registradas siguen a la vista.
      expect(find.text('Hermana'), findsOneWidget);

      await tester.tap(find.text('Chacos'));
      await settle(tester);
      await tester.tap(find.text('Agregar chaco'));
      await settle(tester);
      expect(find.text('Propietario'), findsNothing);
      expect(find.byKey(const Key('farm-personal-owner')), findsOneWidget);
    });

    testWidgets('liquidación: pagos y adelantos sólo del titular', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'liquidacion');
      await tester.runAsync(
        () =>
            OperationModeStore(s.database)
                .apply(OperationMode.personal, confirmed: true),
      );
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/liquidacion');
      await settle(tester);

      Future<List<String>> menuOf(String name) async {
        final card = find.ancestor(
          of: find.text(name),
          matching: find.byType(Card),
        );
        await tester.tap(
          find.descendant(
            of: card.first,
            matching: find.byType(PopupMenuButton<String>),
          ),
        );
        await settle(tester);
        final items = [
          for (final item in tester.widgetList<PopupMenuItem<String>>(
            find.byType(PopupMenuItem<String>),
          ))
            if (item.enabled) item.value ?? '',
        ];
        await tester.tapAt(const Offset(5, 5));
        await settle(tester);
        return items;
      }

      expect(await menuOf('Titular'), containsAll(['pay', 'advance']));
      final relative = await menuOf('Hermana');
      expect(relative, containsAll(['detail', 'export']));
      expect(relative, isNot(contains('pay')));
      expect(relative, isNot(contains('advance')));
    });

    testWidgets('liquidación abierta al pasar a propio: deja de ofrecer pagos '
        'a otras personas', (tester) async {
      // Comportamiento visible. La recarga por cambio de modalidad es
      // defensiva y esta prueba no la distingue (revisión de la sesión C).
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'liquidacion_abierta');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/liquidacion');
      await settle(tester);

      Future<List<String>> menuOf(String name) async {
        final card = find.ancestor(
          of: find.text(name),
          matching: find.byType(Card),
        );
        await tester.tap(
          find.descendant(
            of: card.first,
            matching: find.byType(PopupMenuButton<String>),
          ),
        );
        await settle(tester);
        final items = [
          for (final item in tester.widgetList<PopupMenuItem<String>>(
            find.byType(PopupMenuItem<String>),
          ))
            if (item.enabled) item.value ?? '',
        ];
        await tester.tapAt(const Offset(5, 5));
        await settle(tester);
        return items;
      }

      expect(await menuOf('Hermana'), containsAll(['pay', 'advance']));
      await switchModeBehindScreen(
        tester,
        c,
        s.database,
        OperationMode.personal,
      );
      final relative = await menuOf('Hermana');
      expect(relative, isNot(contains('pay')));
      expect(relative, isNot(contains('advance')));
      expect(await menuOf('Titular'), containsAll(['pay', 'advance']));
    });

    testWidgets('un formulario abierto cuando cambia la modalidad avisa y no '
        'confirma con las opciones anteriores', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'cambio');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).push('/compras/nueva');
      await waitFor(tester, field('Cantidad comprada'));
      await settle(tester);
      expect(find.byKey(const Key('mode-changed-notice')), findsNothing);

      await switchModeBehindScreen(
        tester,
        c,
        s.database,
        OperationMode.personal,
      );
      expect(find.byKey(const Key('mode-changed-notice')), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('purchase-continue')),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('compartido conserva sus flujos', () {
    testWidgets('la transferencia ofrece origen y destino entre responsables', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'compartido');
      final c = await pumpModeApp(tester, s.database);
      c.read(routerProvider).push('/transferencias/nueva');
      await waitFor(tester, picker('Persona origen'));
      await settle(tester);
      expect(picker('Persona origen'), findsOneWidget);
      expect(find.byKey(const Key('shared-only-notice')), findsNothing);
    });
  });

  group('reversiones en propio (dominio)', () {
    Future<({Household h, OperationModeStore modes})> setup() async {
      final database = openDb(inMemoryDatabasePath);
      final h = await seedHousehold(AgroRepository(database));
      await OwnerBindingStore(database).bindExistingPerson(
        personId: h.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      return (h: h, modes: OperationModeStore(database));
    }

    Future<void> settleAccount(Household h, int person) async {
      final db = await h.repo.appDatabase.database;
      final debt =
          (await db.rawQuery(
                'SELECT COALESCE(SUM(amount_bob_minor_signed), 0) s '
                'FROM account_transactions WHERE person_id=?',
                [person],
              )).single['s']!
              as int;
      if (debt != 0) {
        await h.repo.addAccountPayment(
          personId: person,
          campaignId: h.campaign,
          amountBobMinor: debt,
        );
      }
    }

    test('revertir la aplicación de otra persona se rechaza sin cambios; la '
        'del titular se revierte', () async {
      final s = await setup();
      final h = s.h;
      await h.buy(h.relative, 3000);
      final relativeApplication = await h.apply(
        h.relative,
        h.relativeFarm,
        3000,
      );
      await h.buy(h.titular, 2000);
      final ownApplication = await h.apply(h.titular, h.titularFarm, 2000);
      await settleAccount(h, h.relative);
      await s.modes.apply(OperationMode.personal, confirmed: true);
      final db = await h.repo.appDatabase.database;
      final before = await dumpTables(db);

      await expectLater(
        h.repo.reverseApplicationUnauditedForTesting(relativeApplication),
        throwsA(isA<PersonalModeRestrictionException>()),
      );
      expect(await dumpTables(db), before);
      expect(
        (await OperationModeStore.thirdPartyActivity(db, h.titular)).isEmpty,
        isTrue,
      );

      await h.repo.reverseApplicationUnauditedForTesting(ownApplication);
      expect(
        (await OperationModeStore.thirdPartyActivity(db, h.titular)).isEmpty,
        isTrue,
      );
      expect((await stockByPersonProduct(db))[(h.titular, h.product)], 2000);
    });

    test('revertir una transferencia se rechaza sin cambios', () async {
      final s = await setup();
      final h = s.h;
      await h.buy(h.relative, 3000);
      final transfer = await h.repo.transferProductFifo(
        fromPersonId: h.relative,
        toPersonId: h.titular,
        productId: h.product,
        quantityBase: 3000,
      );
      await settleAccount(h, h.relative);
      await s.modes.apply(OperationMode.personal, confirmed: true);
      final db = await h.repo.appDatabase.database;
      final before = await dumpTables(db);

      await expectLater(
        h.repo.reverseTransferUnauditedForTesting(transfer),
        throwsA(isA<PersonalModeRestrictionException>()),
      );
      expect(await dumpTables(db), before);

      // En compartido la misma reversión sigue disponible.
      await s.modes.apply(OperationMode.shared, confirmed: true);
      await h.repo.reverseTransferUnauditedForTesting(transfer);
      expect((await stockByPersonProduct(db))[(h.relative, h.product)], 3000);
    });

    // D-02 (revisión del 2026-10-26 sobre a68285c): revertir una compra con
    // asignación a otra persona anulaba sus lotes y le abonaba un
    // CREDIT_ADJUSTMENT también en propio, al contrario que las reversiones
    // de aplicación y de transferencia (#102).
    test('revertir una compra asignada a otra persona se rechaza sin cambios '
        'en propio; en compartido se revierte', () async {
      final s = await setup();
      final h = s.h;
      // El vecino liquida por asignación de compra: la compra le deja un
      // lote y un cargo; se paga para que sólo queden las existencias.
      final purchase = await h.buy(h.thirdParty, 3000);
      await settleAccount(h, h.thirdParty);
      final db = await h.repo.appDatabase.database;
      final charges = await db.query(
        'account_transactions',
        where: "reference_type='PURCHASE_ALLOCATION'",
      );
      expect(charges.single['person_id'], h.thirdParty);
      // La transición a propio bloquea por las existencias del vecino:
      // por la interfaz este estado no se alcanza. Se fuerza la modalidad
      // como en f04_repository_guards_test (base anterior a la compuerta,
      // restaurada o escrita por fuera): el repositorio debe fallar cerrado
      // igual que con la aplicación y la transferencia.
      await expectLater(
        s.modes.apply(OperationMode.personal, confirmed: true),
        throwsA(isA<ModeTransitionException>()),
      );
      await db.insert('app_settings', {
        'key': AppDatabase.operationModeKey,
        'value': OperationMode.personal.code,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final before = await dumpTables(db);

      await expectLater(
        h.repo.reversePurchaseUnauditedForTesting(purchase),
        throwsA(
          isA<PersonalModeRestrictionException>().having(
            (e) => e.message,
            'message',
            contains('cambie a inventario compartido'),
          ),
        ),
      );
      expect(await dumpTables(db), before);

      // En compartido la misma compensación sigue disponible: el lote y el
      // cargo del vecino se compensan, no se reasignan al titular.
      await s.modes.apply(OperationMode.shared, confirmed: true);
      await h.repo.reversePurchaseUnauditedForTesting(purchase);
      expect((await stockByPersonProduct(db))[(h.thirdParty, h.product)], 0);
      expect((await stockByPersonProduct(db))[(h.titular, h.product)], isNull);
      final credit = await db.query(
        'account_transactions',
        where:
            "type='CREDIT_ADJUSTMENT' AND reference_type='PURCHASE_REVERSAL'",
      );
      expect(credit.single['person_id'], h.thirdParty);
    });

    test('en propio, una compra sólo del titular sí se revierte', () async {
      final s = await setup();
      final h = s.h;
      await s.modes.apply(OperationMode.personal, confirmed: true);
      final purchase = await h.buy(h.titular, 2000);
      final db = await h.repo.appDatabase.database;
      expect((await stockByPersonProduct(db))[(h.titular, h.product)], 2000);

      await h.repo.reversePurchaseUnauditedForTesting(purchase);
      expect((await stockByPersonProduct(db))[(h.titular, h.product)], 0);
      final reversed = await db.query(
        'purchases',
        where: 'id=?',
        whereArgs: [purchase],
      );
      expect(reversed.single['status'], 'REVERSED');
      expect(
        (await OperationModeStore.thirdPartyActivity(db, h.titular)).isEmpty,
        isTrue,
      );
    });

    test('compra de otra persona ya consumida: en propio sigue rechazada por '
        'la regla de lotes consumidos, sin cambios', () async {
      final s = await setup();
      final h = s.h;
      final purchase = await h.buy(h.relative, 3000);
      await h.apply(h.relative, h.relativeFarm, 3000);
      await settleAccount(h, h.relative);
      await s.modes.apply(OperationMode.personal, confirmed: true);
      final db = await h.repo.appDatabase.database;
      final before = await dumpTables(db);

      await expectLater(
        h.repo.reversePurchaseUnauditedForTesting(purchase),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            contains('lotes consumidos'),
          ),
        ),
      );
      expect(await dumpTables(db), before);
    });
  });
}

class _FixedMode extends OperationModeController {
  _FixedMode(this.mode);
  final OperationMode mode;
  @override
  OperationMode? build() => mode;
}
