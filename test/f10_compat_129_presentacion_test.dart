// #129 (RNF-08, INT-01; RU-09, RU-13): legibilidad con fuente grande en
// pantallas estrechas. Reproduce la configuración A4-F de la serie 2 de F10
// (HONOR JDY-LX3P, 720×1612 físicos a densidad 320 → 360×806 lógicos) y la
// del POCO X5 Pro (1080×2400 a 440 dpi → 392,7×872,7 lógicos), ambas con
// barra de estado y barra de navegación de tres botones como insets reales
// del `MediaQuery` (los del POCO leídos en el equipo; los del HONOR,
// supuestos), con la fuente al 100 % y al 130 %.
//
// Comprobaciones:
//   * «Nueva compra»: el nombre del producto elegido («DSV-002 Producto
//     sintético») se lee entero en el campo «Producto»: sin puntos
//     suspensivos y sin partir palabras. La cabecera «Productos (1)» y el
//     botón «Agregar producto» tampoco se parten ni se truncan.
//   * Inicio: las etiquetas de las tarjetas («Pagado proveedores», …), los
//     encabezados de sección y las etiquetas de la barra inferior
//     («Operaciones») no se parten dentro de una palabra; los importes de las
//     tarjetas no quedan bajo el botón flotante «Nuevo» sin desplazar; y, tras
//     desplazar hasta el final, el último elemento queda por encima del botón.
//
// Se mide con Roboto (test/fonts), como en #97: la fuente de prueba por
// defecto dibuja cada glifo como un cuadrado y no representa el teléfono.
// La escala 1,45 (ajuste propio del HONOR) se incluye como exploración, no
// como criterio del protocolo v1.3 (§2.3, A4-F = 1,3).
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/app_shell.dart';
import 'package:agroquimicos/presentation/screens/dashboard_screen.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';

/// Un teléfono físico tal como lo describe el `MediaQuery`: tamaño físico,
/// densidad y insets del sistema (barra de estado y barra de navegación de
/// tres botones), en **píxeles físicos**, como los imprime
/// `dumpsys window` (`InsetsSource … frame=[…]`).
typedef _Device = ({
  String name,
  Size physical,
  double dpr,
  double statusBarPx,
  double navigationBarPx,
});

const _devices = <_Device>[
  // Serie 2 de F10, A4/A4-F: 720×1612 a 320 dpi (DPR 2) → 360×806 lógicos.
  // Insets SUPUESTOS (24 dp y 48 dp, los habituales de Android): no se
  // leyeron en la serie 2 y el equipo no está conectado; se declara.
  (
    name: 'HONOR JDY-LX3P 360×806',
    physical: Size(720, 1612),
    dpr: 2.0,
    statusBarPx: 48,
    navigationBarPx: 96,
  ),
  // Serie 1 de F10, A1/A1-F: 1080×2400 a 440 dpi (DPR 2,75) → 392,7×872,7.
  // Insets LEÍDOS en el equipo el 2026-10-18 (~20:35Z, `dumpsys window`):
  // ITYPE_STATUS_BAR frame=[0,0][1080,94] (34,2 dp) y ITYPE_NAVIGATION_BAR
  // frame=[0,2270][1080,2400] (130 px, 47,3 dp), `navigation_mode` 0.
  (
    name: 'POCO X5 Pro 392,7×872,7',
    physical: Size(1080, 2400),
    dpr: 2.75,
    statusBarPx: 94,
    navigationBarPx: 130,
  ),
];

const _protocolScales = [1.0, 1.3];
const _explorationScales = [1.45];

void main() {
  sqfliteFfiInit();

  setUpAll(() async {
    final loader = FontLoader('Roboto');
    for (final name in ['regular', 'medium', 'bold']) {
      final bytes = File('test/fonts/roboto-$name.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Configura la ventana de prueba como el teléfono [device] con la escala de
  /// fuente del sistema [scale].
  void configure(WidgetTester tester, _Device device, double scale) {
    tester.view.physicalSize = device.physical;
    tester.view.devicePixelRatio = device.dpr;
    tester.view.padding = FakeViewPadding(
      top: device.statusBarPx,
      bottom: device.navigationBarPx,
    );
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Size logicalSize(_Device device) => device.physical / device.dpr;

  Widget app(Widget home) => MaterialApp(
    theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
    home: home,
  );

  /// Ninguna palabra del texto se parte entre dos líneas y el texto no se
  /// trunca con puntos suspensivos. Las líneas pueden cambiar entre palabras.
  void expectWordsWhole(WidgetTester tester, Finder text, String reason) {
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final plain = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: '$reason: truncado');
    for (final word in RegExp(r'\S+').allMatches(plain)) {
      final tops = {
        for (final box in paragraph.getBoxesForSelection(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        ))
          box.top.round(),
      };
      expect(
        tops,
        hasLength(1),
        reason: '$reason: «${word.group(0)}» partida en dos líneas',
      );
    }
  }

  /// El texto ocupa una sola línea.
  void expectOneLine(WidgetTester tester, Finder text, String reason) {
    expectWordsWhole(tester, text, reason);
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final plain = paragraph.text.toPlainText();
    final tops = {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plain.length),
      ))
        box.top.round(),
    };
    expect(tops, hasLength(1), reason: '$reason: en más de una línea');
  }

  void expectOnScreen(WidgetTester tester, Finder finder, Size size) {
    final rect = tester.getRect(finder);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(size.width + 0.01));
  }

  Future<AgroRepository> repository() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repo = AgroRepository(database);
    // Nombres del dataset sintético DS-V de F10 (seed 20261016).
    final family = await repo.addPerson(
      name: 'Agricultor sintético 1',
      role: PersonRole.family,
    );
    await repo.addPerson(name: 'Administrador', role: PersonRole.admin);
    await repo.addPerson(
      name: 'Tercero sintético',
      role: PersonRole.thirdParty,
    );
    final campaign = await repo.addCampaign(
      name: 'Campaña DSV S2',
      start: DateTime.utc(2026, 1, 1),
    );
    final p1 = await repo.addProduct(name: 'DSV-001 Producto sintético');
    await repo.addProduct(name: 'DSV-002 Producto sintético');
    await repo.addProduct(name: 'DSV-003 Producto sintético', unit: 'KG');
    final supplier = await repo.addSupplier(name: 'Proveedor DSV 1');
    await repo.addSupplier(name: 'Proveedor DSV 2');
    // Importes con miles para que las tarjetas del Inicio muestren cifras
    // reales y no «Bs 0,00».
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 2, 1),
        items: [
          PurchaseItemDraft(
            productId: p1,
            quantityBase: 100000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 123456,
            allocations: [
              AllocationDraft(personId: family, quantityBase: 100000),
            ],
          ),
        ],
      ),
    );
    return repo;
  }

  void purchaseFormCases(_Device device, double scale) {
    final label = '${device.name}, fuente ${(scale * 100).round()} %';
    testWidgets('Nueva compra: nombre del producto entero en el campo '
        '«Producto» y cabecera «Productos (1)» sin palabras partidas '
        '($label)', (tester) async {
      configure(tester, device, scale);
      final size = logicalSize(device);
      final repo = (await tester.runAsync(repository))!;
      addTearDown(() => repo.appDatabase.close());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [repositoryProvider.overrideWithValue(repo)],
          child: app(const PurchaseFormScreen()),
        ),
      );
      await settle(tester);

      // Cabecera de la sección de productos, antes de desplazar: la lista es
      // perezosa y lo desplazado fuera de la ventana deja de existir.
      await tester.scrollUntilVisible(
        find.text('Productos (1)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      expectWordsWhole(tester, find.text('Productos (1)'), 'cabecera');
      expectWordsWhole(tester, find.text('Agregar producto'), 'acción');
      expectOnScreen(tester, find.text('Agregar producto'), size);

      final productPicker = find.byWidgetPredicate(
        (w) =>
            w is AdaptiveEntityPicker<Map<String, Object?>> &&
            w.label == 'Producto',
      );
      // La línea puede quedar fuera de la ventana con la fuente ampliada.
      await tester.scrollUntilVisible(
        productPicker,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      expect(productPicker, findsOneWidget);
      final picker = tester.widget<AdaptiveEntityPicker<Map<String, Object?>>>(
        productPicker,
      );
      picker.onChanged(
        picker.items.firstWhere(
          (p) => p['name'] == 'DSV-002 Producto sintético',
        ),
      );
      await settle(tester);

      // El valor del campo, no la cabecera de la tarjeta de la línea.
      expectWordsWhole(
        tester,
        find.descendant(
          of: productPicker,
          matching: find.text('DSV-002 Producto sintético'),
        ),
        'campo Producto',
      );
    });
  }

  void dashboardCases(_Device device, double scale) {
    final label = '${device.name}, fuente ${(scale * 100).round()} %';
    testWidgets('Inicio: tarjetas, encabezados y barra inferior sin palabras '
        'partidas; importes fuera del botón «Nuevo» ($label)', (tester) async {
      configure(tester, device, scale);
      final size = logicalSize(device);
      final repo = (await tester.runAsync(repository))!;
      addTearDown(() => repo.appDatabase.close());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            activatedInstallationForTests(),
          ],
          child: app(const AppShell(location: '/', child: DashboardScreen())),
        ),
      );
      await settle(tester);
      expect(
        // El separador entre cifra y símbolo de `formatBob` es un espacio
        // duro (es_BO).
        find.textContaining(RegExp(r'123\.456,00\s*Bs')),
        findsWidgets,
        reason: 'datos cargados',
      );

      // Etiquetas de las tarjetas de importes.
      for (final card in [
        'Compras',
        'Pagado proveedores',
        'Familias por cobrar',
        'Terceros por cobrar',
        'Pagos recibidos',
      ]) {
        expectWordsWhole(tester, find.text(card), 'tarjeta «$card»');
      }
      // Encabezados de sección con su acción.
      for (final heading in [
        'Inventario proyectado',
        'Aplicaciones recientes',
        'Principales saldos',
      ]) {
        expectWordsWhole(tester, find.text(heading), 'encabezado «$heading»');
      }
      for (final action in ['Ver todos', 'Ver todas']) {
        for (final element in find.text(action).evaluate()) {
          expectOnScreen(
            tester,
            find.byElementPredicate((e) => e == element),
            size,
          );
        }
      }
      // Barra inferior: cada destino en una línea, sin partir.
      final bar = find.byType(NavigationBar);
      for (final item in AppShell.destinations) {
        expectOneLine(
          tester,
          find.descendant(of: bar, matching: find.text(item.label)),
          'barra inferior «${item.label}»',
        );
      }

      // Tras el piloto X01, Inicio no tiene el botón «Nuevo»: los cuatro
      // accesos principales son la acción primaria y ningún importe puede
      // quedar bajo un FAB. Sus etiquetas tampoco se parten dentro de una
      // palabra.
      expect(find.byType(FloatingActionButton), findsNothing);
      for (final access in [
        'Registrar compra',
        'Registrar aplicación',
        'Ver cuánto queda',
        'Enviar al sindicato',
      ]) {
        expectWordsWhole(tester, find.text(access), 'acceso «$access»');
      }

      // Al final del desplazamiento, el último elemento queda entero dentro
      // de la pantalla (sin FAB no hay reserva que comprobar; sí que no quede
      // recortado por el borde ni por la barra inferior).
      final scrollable = find.byType(CustomScrollView);
      for (var i = 0; i < 20; i++) {
        await tester.drag(scrollable, const Offset(0, -2000));
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));
      final last = tester.getRect(find.byType(Card).last);
      final viewport = tester.getRect(scrollable);
      expect(
        last.bottom,
        lessThanOrEqualTo(viewport.bottom + 0.5),
        reason: 'último elemento recortado al final del desplazamiento',
      );
    });
  }

  group('protocolo v1.3 (fuente 1,0 y 1,3)', () {
    for (final device in _devices) {
      for (final scale in _protocolScales) {
        purchaseFormCases(device, scale);
        dashboardCases(device, scale);
      }
    }
  });

  group('exploración (fuente 1,45; no es criterio del protocolo)', () {
    for (final device in _devices) {
      for (final scale in _explorationScales) {
        purchaseFormCases(device, scale);
        dashboardCases(device, scale);
      }
    }
  });
}
