// Botón flotante global de creación (OE3, 2026-11-03).
//
// En el POCO, el 2026-11-03, el FAB «Nuevo» tapaba «Reintentar con esta
// versión» en Sincronización y el toque abría el menú de creación en vez de
// reanudar los envíos. Decisiones del autor:
//   1. Sincronización no muestra el botón flotante global.
//   2. Donde se muestra, es un FAB normal con sólo el icono «+», sin la
//      etiqueta visible «Nuevo», con el nombre accesible «Registrar
//      operación» (una sola vez) y superficie táctil de al menos 48×48.
// Se comprueba con letra al 100, 130 y 200 % en 360×800 y 412×915 lógicos:
// el «+» se toca y abre su menú, no tapa el último elemento desplazable y no
// hay desbordes.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/presentation/app_shell.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/presentation/widgets/common.dart';
import 'package:agroquimicos/services/auth/api_endpoint_config.dart';
import 'package:agroquimicos/services/auth/auth_http_client.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart' as harness;
import 'support/f05_sync_fixtures.dart';

/// Tamaño lógico de pantalla y densidad con que se simula.
typedef _Screen = ({String name, Size logical, double dpr});

const _screens = <_Screen>[
  (name: '360×800', logical: Size(360, 800), dpr: 2.0),
  (name: '412×915', logical: Size(412, 915), dpr: 2.625),
];

const _scales = [1.0, 1.3, 2.0];

/// Nombre accesible del botón flotante: describe la acción real.
// Rediseño (2026-11-12, lámina «Actividad»): «+ Registrar», con el nombre
// visible, que es también el nombre accesible.
const _fabName = 'Registrar';
const _fabKey = Key('shell-registrar');

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  void configure(WidgetTester tester, _Screen screen, double scale) {
    tester.view.physicalSize = screen.logical * screen.dpr;
    tester.view.devicePixelRatio = screen.dpr;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Tema y textos del sistema como en `AgroApp` (Material 3, densidad
  /// compacta, español).
  Widget app(Widget home) => MaterialApp(
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      listTileTheme: const ListTileThemeData(dense: true),
    ),
    home: home,
  );

  List<Rect> fabRects(WidgetTester tester) => [
    for (final element in find.byType(FloatingActionButton).evaluate())
      tester.getRect(find.byElementPredicate((e) => e == element)),
  ];

  group('Sincronización', () {
    test('la ruta oculta el botón flotante global; las ya excluidas siguen '
        'sin él y las secciones con FAB lo conservan', () {
      for (final path in const [
        '/sincronizacion',
        '/',
        '/catalogos',
        '/voz',
        '/compras/voz',
        '/planificacion/voz',
        '/aplicaciones/voz',
        '/inventario/avisos',
        '/inventario/estimacion',
        '/compras/detalle/7',
        // Rediseño: Personas y Cuentas tienen «Registrar pago» en cada
        // tarjeta (láminas sin flotante).
        '/personas',
        '/liquidacion',
        // Rediseño (recorrido del 2026-11-12): en Convocatorias y su detalle
        // el botón tapaba «Continuar» de la hoja de cantidades (láminas 6.1–6.3
        // sin flotante).
        '/compras-conjuntas',
        '/compras-conjuntas/0e8918ab-0000-4000-8000-000000000000',
      ]) {
        expect(
          AppShell(location: path, child: const SizedBox()).hidesGlobalFab,
          isTrue,
          reason: path,
        );
      }
      for (final path in const ['/operaciones', '/inventario']) {
        expect(
          AppShell(location: path, child: const SizedBox()).hidesGlobalFab,
          isFalse,
          reason: path,
        );
      }
    });

    testWidgets('app real: en /sincronizacion no hay botón flotante; en '
        'Operaciones sí', (tester) async {
      final s = await harness.activatedHousehold(tester, 'fab-sync');
      final c = await harness.pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/operaciones');
      await harness.settle(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      c.read(routerProvider).go('/sincronizacion');
      await harness.waitFor(tester, find.text('Sincronizar ahora'));
      await harness.settle(tester);
      expect(harness.currentPath(c), '/sincronizacion');
      expect(find.byType(SyncStatusScreen), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    for (final screen in _screens) {
      for (final scale in _scales) {
        final label = '${screen.name}, letra ${(scale * 100).round()} %';
        testWidgets('«Reintentar con esta versión» no queda bajo ningún FAB '
            'y su toque abre su confirmación, no el menú de creación '
            '($label)', (tester) async {
          configure(tester, screen, scale);
          final fixture = (await tester.runAsync(() async {
            final f = await seedSyncFixture(path: inMemoryDatabasePath);
            // Una intención pausada por versión (422) y otra restaurada:
            // la pantalla muestra «Liberar» y «Reintentar con esta versión».
            await f.needs.declare(
              referenceDate: inCampaign,
              productId: f.litreProductId,
              quantityBase: 30000,
            );
            await f.outbox.recordVersionMismatch(
              await f.outbox.markSending((await f.outbox.entries()).single),
            );
            await f.needs.declare(
              referenceDate: inCampaign,
              productId: f.kiloProductId,
              quantityBase: 5000,
            );
            await SyncOutboxStore.pauseAfterRestore(
              await f.database.database,
              DateTime.now().toUtc().toIso8601String(),
            );
            return f;
          }))!;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                databaseProvider.overrideWithValue(fixture.database),
                repositoryProvider.overrideWithValue(fixture.repo),
                declaredNeedStoreProvider.overrideWithValue(fixture.needs),
                centralBindingStoreProvider.overrideWithValue(fixture.bindings),
                syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
                syncApiProvider.overrideWithValue(
                  SyncApi(
                    AuthHttpClient(
                      config: ApiEndpointConfig(
                        Uri.parse('https://sindicato.example'),
                      ),
                      client: MockClient(
                        (request) async =>
                            fail('nada debe enviarse: ${request.url}'),
                      ),
                    ),
                  ),
                ),
              ],
              child: app(
                const AppShell(
                  location: '/sincronizacion',
                  child: SyncStatusScreen(),
                ),
              ),
            ),
          );
          await settle(tester);
          final retry = find.widgetWithText(
            TextButton,
            'Reintentar con esta versión',
          );
          // Con la letra al 200 % la cabecera ocupa casi toda la pantalla y
          // el cuerpo de la página sólo se construye al desplazarse.
          final scrollable = find
              .descendant(
                of: find.byType(SyncStatusScreen),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(retry, 100, scrollable: scrollable);
          expect(retry, findsOneWidget);
          expect(find.text('Liberar'), findsOneWidget);

          // Se desplaza la página para dejar el botón donde estaría el FAB
          // (esquina inferior: 16 de margen + 28 de medio FAB), como al
          // recorrer la lista con el dedo; el desplazamiento se acota a lo
          // que la página permite.
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          final position = tester.state<ScrollableState>(scrollable).position;
          final viewport = tester.getRect(scrollable);
          final target = viewport.bottom - 16 - 28;
          // Dos pasadas: la extensión de la página se recalcula al construir
          // lo que entra en pantalla.
          for (var pass = 0; pass < 2; pass++) {
            final delta = tester.getCenter(retry).dy - target;
            position.jumpTo(
              (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
            );
            await tester.pump();
          }
          final center = tester.getCenter(retry);
          expect(
            viewport.contains(center),
            isTrue,
            reason: 'el botón sigue en pantalla',
          );
          final covering = fabRects(tester)
              .where((rect) => rect.contains(center))
              .toList();
          expect(
            covering,
            isEmpty,
            reason:
                'el centro $center de «Reintentar con esta versión» queda '
                'bajo un FAB',
          );

          await tester.tapAt(center);
          await tester.pumpAndSettle();
          expect(
            find.byType(BottomSheet),
            findsNothing,
            reason: 'el toque abrió el menú de creación',
          );
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Reintentar con esta versión'),
            ),
            findsOneWidget,
            reason: 'el toque abre la confirmación de reanudar',
          );
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();

          expect(find.byType(FloatingActionButton), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('«+» en las secciones con FAB', () {
    /// Una página larga con el marco de todas las pantallas del shell: el
    /// relleno inferior sale de [ContentInsets].
    Widget longPage() => PageFrame(
      title: 'Operaciones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 30; i++)
            Card(
              key: Key('fila-$i'),
              child: ListTile(
                title: Text('Fila sintética $i'),
                subtitle: const Text('Importe y estado de la operación'),
              ),
            ),
        ],
      ),
    );

    for (final screen in _screens) {
      for (final scale in _scales) {
        final label = '${screen.name}, letra ${(scale * 100).round()} %';
        testWidgets('«+ Registrar», ≥48×48, nombre accesible único; se '
            'toca y abre su hoja; no tapa la última fila ($label)', (
          tester,
        ) async {
          configure(tester, screen, scale);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            app(AppShell(location: '/operaciones', child: longPage())),
          );
          await tester.pumpAndSettle();

          final fab = find.byType(FloatingActionButton);
          expect(fab, findsOneWidget);
          expect(find.text('Nuevo'), findsNothing);
          expect(tester.widget<FloatingActionButton>(fab).isExtended, isTrue);
          expect(
            find.descendant(of: fab, matching: find.text(_fabName)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: fab, matching: find.byIcon(Icons.add)),
            findsOneWidget,
          );
          final size = tester.getSize(fab);
          expect(size.width, greaterThanOrEqualTo(48), reason: '$size');
          expect(size.height, greaterThanOrEqualTo(48), reason: '$size');
          expect(tester, meetsGuideline(androidTapTargetGuideline));

          // Nombre accesible: «Registrar», una sola vez, en el propio botón;
          // «Nuevo» no se anuncia.
          bool names(SemanticsNode node, String text) =>
              node.label.contains(text) || node.tooltip.contains(text);
          expect(
            find.semantics.byPredicate(
              (node) => node.label == _fabName || node.tooltip == _fabName,
            ),
            findsOne,
          );
          expect(
            find.semantics.byPredicate((node) => names(node, 'Nuevo')),
            findsNothing,
          );
          final data = tester.getSemantics(fab).getSemanticsData();
          expect(data.label, _fabName);
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);

          // La última fila puede subir por encima del «+».
          final scrollable = find.byType(Scrollable).first;
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          final last = tester.getRect(find.byKey(const Key('fila-29')));
          final fabRect = tester.getRect(fab);
          expect(
            last.bottom,
            lessThanOrEqualTo(fabRect.top),
            reason: 'última fila $last, FAB $fabRect',
          );

          // El toque llega al «+» (no a lo que haya debajo) y abre el mismo
          // menú de siempre.
          final hits = tester.hitTestOnBinding(tester.getCenter(fab));
          final fabBox = tester.renderObject(fab);
          expect(
            hits.path.any((entry) => entry.target == fabBox),
            isTrue,
            reason: 'el toque en el centro del «+» llega al botón',
          );
          await tester.tap(fab);
          await tester.pumpAndSettle();
          final sheet = find.byType(BottomSheet);
          expect(sheet, findsOneWidget);
          final sheetRect = tester.getRect(sheet);
          for (final option in const [
            'Compra',
            'Aplicación',
            'Plan de aplicación',
            'Pago',
            'Transferencia',
          ]) {
            final found = find.descendant(
              of: sheet,
              matching: find.text(option),
            );
            expect(found, findsOneWidget, reason: option);
            expect(
              sheetRect.contains(tester.getCenter(found)),
              isTrue,
              reason: '«$option» visible dentro del menú $sheetRect',
            );
          }
          // «Completar por voz» va al final; a 200 % se alcanza desplazando.
          final voice = find.descendant(
            of: sheet,
            matching: find.text('Completar por voz'),
          );
          expect(voice, findsOneWidget);
          await tester.ensureVisible(voice);
          await tester.pumpAndSettle();
          expect(sheetRect.contains(tester.getCenter(voice)), isTrue);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        });
      }
    }

    testWidgets('«Registrar» se recoge a «+» al bajar y vuelve al subir; '
        'recogido sigue llamándose «Registrar»', (tester) async {
      configure(tester, _screens.first, 1);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(AppShell(location: '/operaciones', child: longPage())),
      );
      await tester.pumpAndSettle();
      bool extended() => tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .isExtended;
      expect(extended(), isTrue);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(extended(), isFalse);
      expect(
        find.semantics.byPredicate((node) => node.label == _fabName),
        findsOne,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(extended(), isTrue);
      semantics.dispose();
    });

    testWidgets('app real: «Registrar» de Actividad abre la hoja y «Compra» '
        'lleva al formulario, como antes', (tester) async {
      final s = await harness.activatedHousehold(tester, 'fab-compra');
      final c = await harness.pumpModeApp(tester, s.database);
      c.read(routerProvider).go('/operaciones');
      await harness.settle(tester);
      await tester.tap(find.byKey(_fabKey));
      await harness.settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Compra'),
        ),
      );
      await harness.settle(tester);
      expect(find.byType(PurchaseFormScreen), findsOneWidget);
    });
  });
}
