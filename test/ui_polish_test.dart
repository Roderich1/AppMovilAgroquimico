import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/app_shell.dart';
import 'package:agroquimicos/presentation/screens/catalogs_screen.dart';
import 'package:agroquimicos/presentation/screens/dashboard_screen.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/presentation/screens/transfer_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Cierre del lote de defectos de interfaz que quedaban abiertos tras la
/// auditoría del Pixel 8: 023, 031, 037, 038, 039, 040, 041, 047 y 060.
void main() {
  sqfliteFfiInit();

  /// Ancho útil del Pixel 8 en vertical: 1080 px a densidad 2,625 ≈ 411 dp.
  ///
  /// El **alto** es deliberadamente mayor que el del dispositivo: estas
  /// pantallas son listas perezosas y sólo construyen lo visible, así que con
  /// el alto real habría que desplazarse para que existiera la sección que se
  /// quiere comprobar. Lo que se audita aquí es el ANCHO —de él depende el
  /// diseño responsive—, no cuánto entra sin desplazar.
  const pixel8Portrait = Size(411, 2400);

  /// Deja avanzar el trabajo asíncrono real (SQLite) y luego repinta.
  ///
  /// Las pantallas encadenan varias consultas dentro de un `FutureBuilder`, y
  /// una sola ronda no basta para que todas resuelvan: se repite hasta que el
  /// contenido aparece.
  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var round = 0; round < rounds; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<(AppDatabase, AgroRepository)> fixture({
    bool withStock = false,
  }) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repo = AgroRepository(database);
    final family = await repo.addPerson(name: 'José', role: PersonRole.family);
    await repo.addPerson(name: 'Administrador', role: PersonRole.admin);
    // **Dos personas y dos productos como mínimo.** `AdaptiveEntityPicker`
    // auto-selecciona cuando sólo hay una opción, así que un catálogo de un
    // solo elemento dejaría el formulario ya relleno y haría irreproducibles
    // los defectos del estado inicial (037, 038, 039, 060). El dataset real
    // tiene 22 productos y 7 personas.
    await repo.addPerson(name: 'María Ñandú', role: PersonRole.family);
    await repo.addFarm(ownerId: family, name: 'JoseLimoncito', areaM2: 800000);
    final campaign = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    final product = await repo.addProduct(name: 'Glifosato 48 SL');
    await repo.addProduct(name: 'Urea Granulada', unit: 'KG');
    final supplier = await repo.addSupplier(name: 'Agropecuaria del Norte SRL');
    await repo.addSupplier(name: 'Insumos del Chaco Ltda.');
    if (withStock) {
      await repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: DateTime.utc(2026, 2, 1),
          items: [
            PurchaseItemDraft(
              productId: product,
              quantityBase: 50000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 1600,
              allocations: [
                AllocationDraft(personId: family, quantityBase: 50000),
              ],
            ),
          ],
        ),
      );
    }
    return (database, repo);
  }

  Future<AgroRepository> pump(
    WidgetTester tester,
    Widget screen, {
    bool withStock = false,
    bool inScaffold = true,
  }) async {
    final (database, repo) = (await tester.runAsync(
      () => fixture(withStock: withStock),
    ))!;
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: inScaffold ? Scaffold(body: screen) : screen),
      ),
    );
    await settle(tester);
    return repo;
  }

  group('UIBUG-023 · identidad del producto sin scroll horizontal', () {
    testWidgets('en ancho de móvil no hay tabla desplazable en horizontal', (
      tester,
    ) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const DashboardScreen(), withStock: true);

      // La tabla obligaba a arrastrar en horizontal, y al hacerlo la columna
      // "Producto" abandonaba la pantalla.
      expect(find.byType(DataTable), findsNothing);

      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      expect(horizontal, findsNothing);
    });

    testWidgets('cada fila muestra el nombre junto a sus cifras etiquetadas', (
      tester,
    ) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const DashboardScreen(), withStock: true);

      expect(find.text('Glifosato 48 SL'), findsWidgets);
      // Las cifras dejan de ser columnas anónimas: cada una lleva su rótulo
      // en la propia fila.
      for (final label in const [
        'Físico',
        'Comprometido',
        'Proyección',
        'Valor',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });

    testWidgets('en pantalla ancha se conserva la tabla', (tester) async {
      await resize(tester, const Size(1200, 2400));
      await pump(tester, const DashboardScreen(), withStock: true);
      expect(find.byType(DataTable), findsOneWidget);
    });
  });

  group('UIBUG-031 · guardar un catálogo vacío se explica', () {
    testWidgets('guardar sin nombre muestra el error y no cierra el diálogo', (
      tester,
    ) async {
      await resize(tester, pixel8Portrait);
      final repo = await pump(tester, const CatalogsScreen());

      final before = (await tester.runAsync(repo.suppliers))!.length;

      // Pestaña Proveedores → botón primario → diálogo de nombre.
      await tester.tap(find.text('Proveedores'));
      await settle(tester);
      await tester.tap(find.text('Agregar proveedor'));
      await settle(tester);
      expect(find.text('Nuevo proveedor'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await settle(tester);

      // El diálogo sigue abierto y dice exactamente qué falta.
      expect(find.text('Nuevo proveedor'), findsOneWidget);
      expect(find.text('Escriba nombre del proveedor.'), findsOneWidget);

      // Y no se escribió nada.
      final after = (await tester.runAsync(repo.suppliers))!.length;
      expect(after, before);
    });

    testWidgets('el chaco exige propietario, nombre y superficie válida', (
      tester,
    ) async {
      await resize(tester, pixel8Portrait);
      final repo = await pump(tester, const CatalogsScreen());
      final before = (await tester.runAsync(repo.farms))!.length;

      await tester.tap(find.text('Chacos'));
      await settle(tester);
      await tester.tap(find.text('Agregar chaco'));
      await settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await settle(tester);

      expect(find.text('Elija un propietario.'), findsOneWidget);
      expect(find.text('Escriba el nombre del chaco.'), findsOneWidget);
      expect(find.text('Escriba la superficie.'), findsOneWidget);
      expect((await tester.runAsync(repo.farms))!.length, before);
    });
  });

  group('UIBUG-037/038/039/041 · formulario de compra', () {
    testWidgets('sin producto no se pinta "Precio BOB/" ni "Costo …/"', (
      tester,
    ) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const PurchaseFormScreen(), inScaffold: false);

      // Ninguna etiqueta termina en la barra huérfana.
      final orphan = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.labelText ?? '').endsWith('/'),
      );
      expect(orphan, findsNothing);
      expect(find.text('Precio por unidad'), findsOneWidget);

      final costo = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data ?? '').contains('Costo') &&
            (widget.data ?? '').trimRight().endsWith('/'),
      );
      expect(costo, findsNothing);
    });

    testWidgets('el campo de cantidad de asignación tiene etiqueta', (
      tester,
    ) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const PurchaseFormScreen(), inScaffold: false);

      // Ningún campo del formulario queda como un recuadro sin nombre.
      final unlabelled = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.labelText ?? '').trim().isEmpty,
      );
      expect(unlabelled, findsNothing);

      // Y la asignación se distingue de la cantidad comprada.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'Cantidad',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Cantidad comprada',
        ),
        findsOneWidget,
      );
    });

    testWidgets('una línea vacía no se declara "asignado"', (tester) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const PurchaseFormScreen(), inScaffold: false);

      // Recién abierta: sin cantidad y sin persona.
      expect(find.textContaining('Pendiente de cantidad'), findsOneWidget);
      expect(find.textContaining('· asignado'), findsNothing);
      expect(find.textContaining('· Asignado'), findsNothing);
    });

    testWidgets('con cantidad pero sin persona dice a quién falta', (
      tester,
    ) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const PurchaseFormScreen(), inScaffold: false);

      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Cantidad comprada',
        ),
        '20',
      );
      await tester.pump();

      expect(find.textContaining('Pendiente de persona'), findsOneWidget);
      expect(find.textContaining('· Asignado'), findsNothing);
    });

    testWidgets('la tarjeta reserva espacio sobre su primer campo', (
      tester,
    ) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const PurchaseFormScreen(), inScaffold: false);

      // UIBUG-041: con relleno superior 0 la etiqueta flotante "Producto" se
      // dibujaba sobre la cabecera de la tarjeta. Se comprueba la causa —el
      // contenedor— y no la posición de ese texto concreto.
      final tile = tester.widget<ExpansionTile>(
        find.byType(ExpansionTile).first,
      );
      final padding = tile.childrenPadding! as EdgeInsets;
      expect(padding.top, greaterThan(0));
    });
  });

  group('UIBUG-040 · proveedor y campaña legibles', () {
    testWidgets('en ancho de móvil no comparten fila', (tester) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const PurchaseFormScreen(), inScaffold: false);

      final proveedor = tester.getRect(find.text('Proveedor'));
      final campana = tester.getRect(find.text('Campaña'));

      // Apilados: la campaña queda por debajo del proveedor, no a su lado.
      expect(campana.top, greaterThan(proveedor.bottom));
    });

    testWidgets('cantidad y moneda tampoco se comprimen en móvil', (
      tester,
    ) async {
      // Media fila recortaba la etiqueta a "Cantidad compr…", que es
      // exactamente la compresión artificial que este defecto prohíbe.
      await resize(tester, pixel8Portrait);
      await pump(tester, const PurchaseFormScreen(), inScaffold: false);

      final cantidad = tester.getRect(find.text('Cantidad comprada'));
      final moneda = tester.getRect(find.text('Moneda'));
      expect(moneda.top, greaterThan(cantidad.bottom));
    });

    testWidgets('en pantalla ancha siguen compartiendo fila', (tester) async {
      await resize(tester, const Size(1200, 2400));
      await pump(tester, const PurchaseFormScreen(), inScaffold: false);

      final proveedor = tester.getRect(find.text('Proveedor'));
      final campana = tester.getRect(find.text('Campaña'));
      expect(campana.left, greaterThan(proveedor.left));
      expect((campana.center.dy - proveedor.center.dy).abs(), lessThan(1));
    });
  });

  group('UIBUG-047 · una sola acción primaria en Catálogos', () {
    test('el shell retira el FAB global en /catalogos', () {
      const catalogs = AppShell(
        location: '/catalogos',
        child: SizedBox.shrink(),
      );
      expect(catalogs.hidesGlobalFab, isTrue);

      // Y sólo ahí: el resto de destinos conserva su FAB.
      for (final path in const [
        '/',
        '/operaciones',
        '/planificacion',
        '/compras',
        '/aplicaciones',
        '/inventario',
        '/personas',
        '/liquidacion',
        '/transferencias',
      ]) {
        expect(
          AppShell(
            location: path,
            child: const SizedBox.shrink(),
          ).hidesGlobalFab,
          isFalse,
          reason: path,
        );
      }
    });

    testWidgets('el botón primario dice qué crea en cada sección', (
      tester,
    ) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const CatalogsScreen());

      for (final (chip, label) in const [
        ('Personas', 'Agregar persona'),
        ('Chacos', 'Agregar chaco'),
        ('Productos', 'Agregar producto'),
        ('Proveedores', 'Agregar proveedor'),
        ('Campañas', 'Agregar campaña'),
      ]) {
        await tester.tap(find.text(chip));
        await settle(tester);
        expect(find.text(label), findsOneWidget, reason: chip);
      }
    });
  });

  group('UIBUG-068 · el rail de navegación no desborda', () {
    /// Pone el visor como el Pixel 8 apaisado: 2400×1080 px a 420 dpi, o sea
    /// una densidad de 2,625 y 914×411 dp.
    ///
    /// Aquí NO sirve `setSurfaceSize`: sólo cambia el tamaño del render view, y
    /// `AppShell` decide rail-o-barra con `MediaQuery.sizeOf`, que se calcula a
    /// partir de `view.physicalSize / devicePixelRatio`. Con `setSurfaceSize`
    /// la consulta seguiría diciendo 800×600 y la prueba mediría la barra
    /// inferior creyendo medir el rail. Los 914 son lo que importa: el shell
    /// cambia a `NavigationRail` a partir de 900.
    void landscapePixel8(WidgetTester tester, {double textScale = 1.0}) {
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 2.625;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('en horizontal el shell usa el rail, no la barra', (
      tester,
    ) async {
      // Guarda de la propia prueba: si esto falla, las dos siguientes estarían
      // midiendo la barra inferior y no probarían nada.
      landscapePixel8(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: AppShell(location: '/', child: SizedBox()),
        ),
      );
      await tester.pump();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('con la fuente al 130 % no desborda y caben los 5 destinos', (
      tester,
    ) async {
      // `NavigationRail` reparte su alto entre los destinos y no se desplaza
      // por su cuenta: al 130 % los cinco con etiqueta no caben en 411 dp de
      // alto. En el Pixel 8 se veía "BOTTOM OVERFLOWED BY 90 PIXELS" y
      // "Personas" y "Cuentas" quedaban fuera de la pantalla.
      landscapePixel8(tester, textScale: 1.3);
      await tester.pumpWidget(
        const MaterialApp(
          home: AppShell(location: '/', child: SizedBox()),
        ),
      );
      await tester.pump();

      // Un desbordamiento de layout llega como excepción en los tests.
      expect(tester.takeException(), isNull);
      for (final item in AppShell.destinations) {
        expect(find.text(item.label), findsOneWidget, reason: item.label);
      }
    });

    testWidgets('el rail vive dentro de su propio scroll', (tester) async {
      landscapePixel8(tester, textScale: 1.3);
      await tester.pumpWidget(
        const MaterialApp(
          home: AppShell(location: '/', child: SizedBox()),
        ),
      );
      await tester.pump();

      expect(
        find.ancestor(
          of: find.byType(NavigationRail),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
    });
  });

  group('UIBUG-060 · sin origen no hay cero engañoso', () {
    testWidgets('antes de elegir origen se explica qué falta', (tester) async {
      await resize(tester, pixel8Portrait);
      await pump(tester, const TransferFormScreen(), inScaffold: false);

      expect(
        find.text('Seleccione un origen para ver su inventario.'),
        findsOneWidget,
      );

      // El recuento desaparece: un `0` suelto se leía como un dato real.
      expect(find.text('0'), findsNothing);

      // Y no hay controles de cantidad que rellenar todavía.
      expect(find.byType(ListTile), findsNothing);
    });
  });
}
