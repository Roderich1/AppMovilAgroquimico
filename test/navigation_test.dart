import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pruebas de navegación sobre la aplicación REAL (`AgroApp` + `GoRouter`).
///
/// Existen porque `back_navigation_test.dart` solo prueba una réplica aislada
/// del contrato `PopScope`, y por eso no detectó STAB-001: entrar al formulario
/// de compra desde el FAB o desde Operaciones dejaba la app en pantalla en
/// blanco al volver atrás.
void main() {
  sqfliteFfiInit();

  /// El dashboard mantiene indicadores de progreso animados, por lo que
  /// `pumpAndSettle` nunca converge. Se bombea con duraciones explícitas.
  ///
  /// Los formularios encadenan varias consultas antes de renderizar, así que
  /// tras abrirlos hace falta un número de fotogramas mayor.
  Future<void> settle(WidgetTester tester, {int frames = 15}) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Segundo drenaje en tiempo real: las pantallas que encadenan varias
    // consultas (liquidación encadena cuatro) dejarían temporizadores
    // pendientes al terminar el test si no se les da tiempo real para cerrar.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<AgroRepository> fixture() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repo = AgroRepository(database);
    final family = await repo.addPerson(name: 'José', role: PersonRole.family);
    await repo.addPerson(name: 'Administrador', role: PersonRole.admin);
    await repo.addFarm(ownerId: family, name: 'Chaco', areaM2: 100000);
    await repo.addCampaign(name: 'Campaña', start: DateTime.utc(2026));
    await repo.addProduct(name: 'Glifosato');
    await repo.addSupplier(name: 'Proveedor');
    return repo;
  }

  Future<void> pumpApp(WidgetTester tester, AgroRepository repo) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const AgroApp(),
      ),
    );
    await settle(tester);
  }

  /// Abre el formulario de compra por la vía indicada y comprueba que al
  /// volver atrás se regresa a una pantalla utilizable, sin excepciones.
  Future<void> expectPurchaseFormReturnsCleanly(
    WidgetTester tester, {
    required Future<void> Function() open,
    required String expectedReturnText,
  }) async {
    await open();
    await settle(tester, frames: 30);
    await settle(tester, frames: 30);
    // 'Nueva compra' es ambiguo: es a la vez el título del formulario y la
    // etiqueta del botón de la lista. 'Factura' (título de la primera sección) solo existe en el
    // formulario, así que identifica la pantalla sin ambigüedad.
    expect(
      find.text('Factura'),
      findsOneWidget,
      reason: 'El formulario de compra debería haberse abierto.',
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester, frames: 30);

    // Los selectores autoseleccionan cuando solo hay una opción, así que el
    // formulario se considera "sucio" nada más abrirse y pide confirmación.
    if (find.text('¿Descartar cambios?').evaluate().isNotEmpty) {
      // La etiqueta pasó a "Descartar cambios" al unificar el criterio de
      // acción destructiva de los cuatro formularios (UIBUG-033).
      await tester.tap(find.text('Descartar cambios'));
      await settle(tester, frames: 30);
    }
    await settle(tester, frames: 30);

    expect(
      tester.takeException(),
      isNull,
      reason: 'Volver atrás no debe lanzar ninguna excepción del router.',
    );
    expect(
      find.text('Factura'),
      findsNothing,
      reason: 'El formulario debería haberse cerrado.',
    );
    expect(
      find.text(expectedReturnText),
      findsWidgets,
      reason:
          'Tras volver atrás debe quedar una pantalla utilizable, '
          'no una pantalla en blanco.',
    );
  }

  testWidgets('STAB-001: FAB Nuevo -> Compra -> atrás vuelve al inicio', (
    tester,
  ) async {
    final repo = (await tester.runAsync(fixture))!;
    await pumpApp(tester, repo);

    await expectPurchaseFormReturnsCleanly(
      tester,
      open: () async {
        await tester.tap(find.byType(FloatingActionButton).first);
        await settle(tester);
        await tester.tap(find.text('Compra'));
      },
      expectedReturnText: 'Inicio',
    );
  });

  // El recorrido cambió al corregir UIBUG-002: la tarjeta de Operaciones abre
  // ahora el LISTADO de compras (antes saltaba directamente al formulario, y
  // `/compras` no tenía ninguna puerta de entrada). El invariante de STAB-001 se
  // mantiene intacto y se comprueba con el mismo helper: al volver atrás debe
  // quedar una pantalla utilizable y sin excepciones del router. La prueba cubre
  // ahora un salto más que antes.
  testWidgets(
    'STAB-001: Operaciones -> Compras -> Nueva compra -> atrás vuelve',
    (tester) async {
      final repo = (await tester.runAsync(fixture))!;
      await pumpApp(tester, repo);

      await tester.tap(find.text('Operaciones').first);
      await settle(tester);
      await tester.tap(find.text('Compras'));
      await settle(tester, frames: 30);
      expect(
        find.text('Nueva compra'),
        findsOneWidget,
        reason: 'La tarjeta de Operaciones debe abrir el historial de compras.',
      );

      await expectPurchaseFormReturnsCleanly(
        tester,
        open: () async => tester.tap(find.text('Nueva compra')),
        expectedReturnText: 'Compras',
      );
    },
  );

  testWidgets('Compras -> Nueva compra -> atrás vuelve a la lista', (
    tester,
  ) async {
    final repo = (await tester.runAsync(fixture))!;
    await pumpApp(tester, repo);

    await tester.tap(find.text('Operaciones').first);
    await settle(tester);
    await tester.tap(find.text('Administrar datos'));
    await settle(tester);
    // Se navega a /compras mediante el router, sin depender de la UI de
    // catálogos, para aislar la ruta bajo prueba.
    final context = tester.element(find.byType(Scaffold).first);
    ProviderScope.containerOf(context).read(routerProvider).go('/compras');
    await settle(tester);
    expect(find.text('Compras'), findsWidgets);

    await expectPurchaseFormReturnsCleanly(
      tester,
      open: () async => tester.tap(find.text('Nueva compra')),
      expectedReturnText: 'Compras',
    );
  });

  testWidgets('las 5 pestañas del shell navegan sin excepciones', (
    tester,
  ) async {
    final repo = (await tester.runAsync(fixture))!;
    await pumpApp(tester, repo);

    for (final label in const [
      'Operaciones',
      'Inventario',
      'Personas',
      'Cuentas',
      'Inicio',
    ]) {
      await tester.tap(find.text(label).first);
      await settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Navegar a "$label" no debe lanzar excepciones.',
      );
    }

    // El inicio dispara cinco consultas en cadena. Se les da tiempo real
    // suficiente para cerrar antes de que el framework verifique que no
    // quedan temporizadores pendientes.
    for (var drain = 0; drain < 5; drain++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
