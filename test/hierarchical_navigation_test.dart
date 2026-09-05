// UIBUG-004A / 004B / 062: jerarquia de navegacion.
//
// 004A (CRITICAL): entrar en un detalle usaba `context.go`, que REEMPLAZA la
//   pila. No quedaba nada que desapilar, Atras cerraba la aplicacion y
//   `PageFrame` no dibujaba flecha de volver: callejon sin salida.
// 004B (decision de diseno): Atras desde un destino RAIZ no inicial debe
//   volver primero a Inicio, no salir de la aplicacion (guia de Material 3).
// 062: la barra inferior resaltaba "Inicio" estando en la bitacora de un chaco.
//
// La distincion es deliberada: cambiar de seccion (destinos raiz) NO es lo
// mismo que bajar en la jerarquia (detalles y formularios).

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/app_shell.dart';
import 'package:agroquimicos/presentation/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  // El detalle de persona encadena cinco consultas antes de renderizar, asi que
  // hace falta alternar espera real y bombeo de fotogramas varias veces.
  Future<void> settle(WidgetTester tester, {int frames = 20}) async {
    for (var round = 0; round < 4; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      for (var frame = 0; frame < frames ~/ 2; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
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
    await repo.addFarm(ownerId: family, name: 'Lote 2', areaM2: 800000);
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

  /// Simula el boton Atras del sistema.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  String currentLocation(WidgetTester tester) {
    final context = tester.element(find.byType(Scaffold).first);
    return ProviderScope.containerOf(context)
        .read(routerProvider)
        .state
        .uri
        .path;
  }

  group('UIBUG-004A · la navegación jerárquica permite volver', () {
    testWidgets('Personas -> detalle -> Atrás vuelve a la lista', (
      tester,
    ) async {
      final repo = (await tester.runAsync(fixture))!;
      await pumpApp(tester, repo);

      await tester.tap(find.text('Personas').last);
      await settle(tester);
      await tester.tap(find.text('José').first);
      await settle(tester, frames: 30);
      expect(currentLocation(tester), '/personas/1');

      await systemBack(tester);
      expect(
        currentLocation(tester),
        '/personas',
        reason: 'Atrás debe devolver a la lista, no cerrar la aplicación',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Inventario -> detalle -> Atrás vuelve a la lista', (
      tester,
    ) async {
      final repo = (await tester.runAsync(fixture))!;
      await pumpApp(tester, repo);

      await tester.tap(find.text('Inventario').last);
      await settle(tester, frames: 30);
      await tester.tap(find.text('Glifosato').first);
      await settle(tester, frames: 30);
      expect(currentLocation(tester), startsWith('/inventario/'));

      await systemBack(tester);
      expect(currentLocation(tester), '/inventario');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Operaciones -> subruta -> Atrás vuelve a Operaciones', (
      tester,
    ) async {
      final repo = (await tester.runAsync(fixture))!;
      await pumpApp(tester, repo);

      await tester.tap(find.text('Operaciones').last);
      await settle(tester);
      await tester.tap(find.text('Administrar datos'));
      await settle(tester, frames: 30);
      expect(currentLocation(tester), '/catalogos');

      await systemBack(tester);
      expect(
        currentLocation(tester),
        '/operaciones',
        reason: 'Las subrutas de Operaciones son jerárquicas',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('UIBUG-004B · política de Atrás desde un destino raíz', () {
    // Decision tomada: Atras desde un destino raiz NO inicial vuelve al destino
    // inicial (Inicio); solo desde Inicio sale de la aplicacion. Es la guia de
    // Material 3 y evita que un toque cierre la app con trabajo a medias.
    testWidgets('Atrás desde un destino raíz vuelve a Inicio', (tester) async {
      final repo = (await tester.runAsync(fixture))!;
      await pumpApp(tester, repo);

      await tester.tap(find.text('Personas').last);
      await settle(tester);
      expect(currentLocation(tester), '/personas');

      await systemBack(tester);
      expect(
        currentLocation(tester),
        '/',
        reason: 'Debe volver al destino inicial antes de salir',
      );
    });

    testWidgets('desde Inicio, Atrás no redirige a ningún sitio', (
      tester,
    ) async {
      final repo = (await tester.runAsync(fixture))!;
      await pumpApp(tester, repo);
      expect(currentLocation(tester), '/');

      await systemBack(tester);
      // La aplicacion cede el gesto al sistema: sigue en Inicio, sin redirigir.
      expect(currentLocation(tester), '/');
      expect(tester.takeException(), isNull);
    });
  });

  group('UIBUG-062 · el destino resaltado corresponde a la ruta', () {
    test('selectedIndex de todas las rutas del shell', () {
      // `/chacos/:id` no coincidia con ningun destino y caia por defecto a 0
      // (Inicio). Se alcanza desde Personas, asi que debe resaltar Personas.
      const cases = <String, int>{
        '/': 0,
        '/operaciones': 1,
        '/catalogos': 1,
        '/planificacion': 1,
        '/compras': 1,
        '/compras/nueva': 1,
        '/aplicaciones': 1,
        '/transferencias': 1,
        '/inventario': 2,
        '/inventario/7': 2,
        '/personas': 3,
        '/personas/4': 3,
        '/chacos/9': 3,
        '/liquidacion': 4,
      };
      cases.forEach((location, expected) {
        expect(
          AppShell(location: location, child: const SizedBox()).selectedIndex,
          expected,
          reason: '$location debe resaltar el destino $expected',
        );
      });
    });
  });

  group('UIBUG-004A · PageFrame ofrece salida cuando se llegó apilando', () {
    // Contrato del componente compartido, aislado de las pantallas: es lo que
    // impide que una pantalla de detalle vuelva a ser un callejón sin salida.
    Widget harness(GoRouter router) => MaterialApp.router(routerConfig: router);

    GoRouter twoPageRouter() => GoRouter(
      initialLocation: '/lista',
      routes: [
        GoRoute(
          path: '/lista',
          builder: (context, _) => Scaffold(
            body: PageFrame(
              title: 'Lista',
              child: TextButton(
                onPressed: () => context.push('/detalle'),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detalle',
          builder: (_, __) => const Scaffold(
            body: PageFrame(title: 'Detalle', child: Text('contenido')),
          ),
        ),
      ],
    );

    testWidgets('sin pila no dibuja flecha', (tester) async {
      await tester.pumpWidget(harness(twoPageRouter()));
      await tester.pumpAndSettle();
      expect(find.text('Lista'), findsOneWidget);
      expect(find.byTooltip('Volver'), findsNothing);
    });

    testWidgets('con pila dibuja flecha y desapila al pulsarla', (
      tester,
    ) async {
      await tester.pumpWidget(harness(twoPageRouter()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle'), findsOneWidget);

      final back = find.byTooltip('Volver');
      expect(
        back,
        findsOneWidget,
        reason: 'una pantalla apilada debe ofrecer salida visible',
      );
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Lista'), findsOneWidget);
    });
  });

  group('UIBUG-008/009 · PageFrame reserva espacio bajo el FAB', () {
    testWidgets('sin ContentInsets no reserva nada (rutas fuera del shell)', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PageFrame(title: 'T', child: SizedBox(height: 10)),
          ),
        ),
      );
      final padding = tester
          .widgetList<SliverPadding>(find.byType(SliverPadding))
          .last;
      expect(padding.padding.resolve(TextDirection.ltr).bottom, 24);
    });

    testWidgets('con ContentInsets reserva el alto del FAB', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContentInsets(
              bottomReserve: AppShell.fabReserve,
              child: PageFrame(title: 'T', child: SizedBox(height: 10)),
            ),
          ),
        ),
      );
      final padding = tester
          .widgetList<SliverPadding>(find.byType(SliverPadding))
          .last;
      expect(
        padding.padding.resolve(TextDirection.ltr).bottom,
        24 + AppShell.fabReserve,
        reason: 'el último elemento debe quedar por encima del FAB',
      );
    });
  });
}
