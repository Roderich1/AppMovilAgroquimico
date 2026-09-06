import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/presentation/screens/reports_screen.dart';
import 'package:agroquimicos/services/reports/report_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pantalla de reportes (Lote H): selección, filtros, vacío, progreso, éxito,
/// error y navegación atrás.
void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase database;
  late AgroRepository repo;
  late LocalReportStorage storage;
  late int family;
  late int campaign;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agro_reports_ui_');
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(root.path, 'agro.db'),
    );
    repo = AgroRepository(database);
    storage = LocalReportStorage(
      directory: () async => Directory(p.join(root.path, 'reportes')),
    );
    family = await repo.addPerson(
      name: 'Ana Familiar',
      role: PersonRole.family,
    );
    campaign = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    );
    await repo.addProduct(name: 'Glifosato');
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Deja avanzar la E/S real (SQLite y filesystem) y luego pinta unos cuadros.
  ///
  /// Es el mismo patrón que `regression_widget_test.dart`: `pumpAndSettle` no
  /// sirve aquí porque el trabajo ocurre fuera de la zona asíncrona del test y
  /// el indicador de progreso nunca dejaría de girar.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Deja avanzar la pantalla hasta que aparezca [finder].
  ///
  /// Cuánto tarda la E/S real depende de la máquina. Esperar a una CONDICIÓN,
  /// y no a un número fijo de vueltas, evita un test que pasa o falla según lo
  /// ocupado que esté el equipo.
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    int maxRounds = 60,
  }) async {
    for (var round = 0; round < maxRounds; round++) {
      if (finder.evaluate().isNotEmpty) return;
      await settle(tester);
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    ReportKind? kind,
    int? personId,
    ReportStorage? override,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          reportStorageProvider.overrideWithValue(override ?? storage),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ReportsScreen(initialKind: kind, initialPersonId: personId),
          ),
        ),
      ),
    );
    await waitFor(tester, find.text('Formato'));
  }

  /// Pulsa un control de la pantalla, desplazándola primero si hace falta.
  ///
  /// La pantalla es más alta que el viewport de prueba: sin `ensureVisible` el
  /// toque cae fuera del área visible y no llega al botón.
  Future<void> tapOnPage(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  /// Confirma el aviso de datos sensibles y espera a que llegue [expected].
  Future<void> confirmExport(WidgetTester tester, Finder expected) async {
    await tester.tap(find.text('Exportar igualmente'));
    await tester.pump();
    await waitFor(tester, expected);
  }

  group('selección y filtros', () {
    testWidgets('ofrece los cinco reportes y los dos formatos', (tester) async {
      await pump(tester);
      for (final kind in ReportKind.values) {
        expect(find.text(kind.label), findsOneWidget);
      }
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
    });

    testWidgets('el inventario no ofrece filtro de campaña', (tester) async {
      await pump(tester);
      expect(find.text('Inventario global'), findsOneWidget);
      expect(find.text('Todas las campañas'), findsNothing);
    });

    testWidgets('el costo por producto sí ofrece campaña', (tester) async {
      await pump(tester);
      await tapOnPage(tester, 'Costo por producto');
      expect(find.textContaining('Campaña'), findsWidgets);
    });

    testWidgets('el resumen de campaña exige campaña y no admite todas', (
      tester,
    ) async {
      await pump(tester, kind: ReportKind.campaignSummary);
      expect(find.text('Todas las campañas'), findsNothing);
      expect(find.textContaining('Campaña (obligatoria)'), findsOneWidget);
    });

    testWidgets('el estado de cuenta pide persona y bloquea sin ella', (
      tester,
    ) async {
      await pump(tester, kind: ReportKind.accountStatement);
      expect(find.textContaining('Persona (obligatoria)'), findsOneWidget);
      expect(
        find.textContaining('Elija la persona'),
        findsOneWidget,
        reason: 'debe decir qué falta',
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Exportar PDF'),
      );
      expect(button.onPressed, isNull, reason: 'no se puede exportar aún');
    });

    testWidgets('con persona precargada el botón se habilita', (tester) async {
      await pump(tester, kind: ReportKind.accountStatement, personId: family);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Exportar PDF'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('advertencia de datos sensibles', () {
    testWidgets('avisa en la pantalla antes de exportar', (tester) async {
      await pump(tester);
      expect(find.textContaining('NO va cifrado'), findsOneWidget);
    });

    testWidgets('pide confirmación explícita y permite cancelarla', (
      tester,
    ) async {
      await pump(tester);
      await tapOnPage(tester, 'Exportar PDF');
      await waitFor(tester, find.text('El archivo no va cifrado'));
      expect(find.text('El archivo no va cifrado'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      // Cancelar la advertencia no escribe nada.
      final directory = Directory(p.join(root.path, 'reportes'));
      expect(!directory.existsSync() || directory.listSync().isEmpty, isTrue);
    });
  });

  group('éxito', () {
    testWidgets('exportar guarda el archivo y dice nombre y carpeta', (
      tester,
    ) async {
      await pump(tester);
      await tapOnPage(tester, 'Exportar PDF');
      await confirmExport(tester, find.text('Reporte guardado'));

      expect(find.text('Reporte guardado'), findsOneWidget);
      expect(find.textContaining('inventario-'), findsOneWidget);
      expect(find.textContaining('reportes'), findsWidgets);

      final files = Directory(p.join(root.path, 'reportes')).listSync();
      expect(files, hasLength(1));
      expect(p.basename(files.single.path), endsWith('.pdf'));

      await tester.tap(find.text('Entendido'));
      await settle(tester);
      expect(find.text('Reporte guardado'), findsNothing);
    });

    testWidgets('elegir CSV cambia el botón y la extensión', (tester) async {
      await pump(tester);
      await tapOnPage(tester, 'CSV');
      expect(find.text('Exportar CSV'), findsOneWidget);

      await tapOnPage(tester, 'Exportar CSV');
      await confirmExport(tester, find.text('Reporte guardado'));

      final files = Directory(p.join(root.path, 'reportes')).listSync();
      expect(p.basename(files.single.path), endsWith('.csv'));
    });

    testWidgets('un reporte sin filas se exporta igual', (tester) async {
      // La base tiene un producto pero ningún chaco: costo por chaco queda
      // vacío y aun así debe producir un archivo con cabeceras.
      await pump(tester, kind: ReportKind.farmCost);
      await tapOnPage(tester, 'Exportar PDF');
      await confirmExport(tester, find.text('Reporte guardado'));

      expect(find.text('Reporte guardado'), findsOneWidget);
      final files = Directory(p.join(root.path, 'reportes')).listSync();
      expect(files, hasLength(1));
      expect(File(files.single.path).lengthSync(), greaterThan(0));
    });
  });

  group('progreso y cancelación', () {
    testWidgets('mientras genera muestra progreso y ofrece cancelar', (
      tester,
    ) async {
      final gate = _GatedStorage();
      await pump(tester, override: gate);
      await tapOnPage(tester, 'Exportar PDF');
      await waitFor(tester, find.text('El archivo no va cifrado'));
      await tester.tap(find.text('Exportar igualmente'));
      await waitFor(tester, find.byType(LinearProgressIndicator));

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        find.textContaining('Generando Inventario en PDF'),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsOneWidget);
      // El botón de exportar no está disponible mientras se exporta.
      expect(find.text('Exportar PDF'), findsNothing);

      gate.release();
      await waitFor(tester, find.text('Reporte guardado'));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('error', () {
    testWidgets('un fallo de almacenamiento se muestra y no cierra nada', (
      tester,
    ) async {
      await pump(tester, override: _FailingStorage());
      await tapOnPage(tester, 'Exportar PDF');
      await confirmExport(tester, find.textContaining('No se pudo guardar'));

      expect(find.text('Reporte guardado'), findsNothing);
      expect(find.textContaining('No se pudo guardar'), findsOneWidget);
      // La pantalla sigue usable: el botón vuelve a estar disponible.
      expect(find.text('Exportar PDF'), findsOneWidget);
    });

    testWidgets('un fallo deja la pantalla lista para reintentar', (
      tester,
    ) async {
      await pump(tester, override: _FailingStorage());
      await tapOnPage(tester, 'Exportar PDF');
      await confirmExport(tester, find.textContaining('No se pudo guardar'));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('navegación', () {
    testWidgets('se llega desde Operaciones y Atrás vuelve allí', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            reportStorageProvider.overrideWithValue(storage),
          ],
          child: const AgroApp(),
        ),
      );
      await waitFor(tester, find.text('Operaciones').first);

      await tester.tap(find.text('Operaciones').first);
      await waitFor(tester, find.text('Acciones del trabajo diario.'));
      expect(find.text('Reportes'), findsOneWidget);

      await tester.tap(find.text('Reportes'));
      // Se espera a "Formato", que sólo existe cuando la pantalla TERMINÓ de
      // cargar: el subtítulo aparece antes, y volver atrás con la lectura a
      // medias dejaría viva la consulta a SQLite.
      await waitFor(tester, find.text('Formato'));
      expect(
        find.text('Exporta inventario, costos y cuentas a CSV o PDF.'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Volver'));
      await waitFor(tester, find.text('Acciones del trabajo diario.'));
      expect(find.text('Acciones del trabajo diario.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Deja terminar la animación de transición: `waitFor` para en cuanto
      // aparece el texto, y una ruta a medio animar deja un temporizador vivo.
      await tester.pumpAndSettle();
    });

    testWidgets('la ruta nombra el reporte y la persona', (tester) async {
      final router = GoRouter(
        initialLocation:
            '/reportes?tipo=${ReportKind.accountStatement.name}&persona=$family'
            '&campana=$campaign',
        routes: [
          GoRoute(
            path: '/reportes',
            builder: (_, state) => ReportsScreen(
              initialKind: reportKindFromRoute(
                state.uri.queryParameters['tipo'],
              ),
              initialPersonId: int.tryParse(
                state.uri.queryParameters['persona'] ?? '',
              ),
              initialCampaignId: int.tryParse(
                state.uri.queryParameters['campana'] ?? '',
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            reportStorageProvider.overrideWithValue(storage),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await waitFor(tester, find.textContaining('Persona (obligatoria)'));

      // Llega ya en el estado de cuenta, con la persona puesta y exportable.
      expect(find.textContaining('Persona (obligatoria)'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Exportar PDF'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('un tipo desconocido en la ruta no rompe la pantalla', (
      tester,
    ) async {
      expect(reportKindFromRoute('inventado'), isNull);
      expect(reportKindFromRoute(null), isNull);
      expect(
        reportKindFromRoute(ReportKind.farmCost.name),
        ReportKind.farmCost,
      );
    });
  });

  group('accesibilidad', () {
    testWidgets('en horizontal se lee entera y conserva el botón', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      await pump(tester);
      await tester.ensureVisible(find.text('Exportar PDF'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Exportar PDF'), findsOneWidget);
    });

    testWidgets('al 130 % no desborda ni pierde el botón', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            reportStorageProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: 1.3,
              maxScaleFactor: 1.3,
              child: child!,
            ),
            home: const Scaffold(body: ReportsScreen()),
          ),
        ),
      );
      await waitFor(tester, find.text('Exportar PDF'));

      expect(tester.takeException(), isNull);
      expect(find.text('Exportar PDF'), findsOneWidget);
    });
  });
}

/// Almacenamiento que se queda esperando hasta que el test lo suelta.
///
/// Permite comprobar el estado "generando" sin depender de que el equipo tarde
/// lo justo: la exportación no termina hasta que el test decide.
class _GatedStorage implements ReportStorage {
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<String> describeLocation() async => '/ruta/de/prueba';

  @override
  Future<StoredReport> save({
    required String baseName,
    required String extension,
    required Uint8List bytes,
  }) async {
    await _gate.future;
    return StoredReport(
      path: '/ruta/de/prueba/$baseName.$extension',
      fileName: '$baseName.$extension',
      directory: '/ruta/de/prueba',
      byteCount: bytes.length,
    );
  }
}

/// Almacenamiento que siempre falla, para ejercitar el camino de error sin
/// tener que llenar el disco.
class _FailingStorage implements ReportStorage {
  @override
  Future<String> describeLocation() async => '/ruta/de/prueba';

  @override
  Future<StoredReport> save({
    required String baseName,
    required String extension,
    required Uint8List bytes,
  }) async =>
      throw const ReportStorageException('No se pudo guardar el reporte.');
}
