// Capturas de la sesión C del rediseño en el ARNÉS de pruebas (no en un
// teléfono): las pantallas reales sobre una base sintética, con las
// tipografías empaquetadas, a 390×844 dp. Sirven para compararlas con las
// láminas; la verificación en el emulador la hace el orquestador.
//
//   flutter test tool/rediseno/capturas_c_test.dart
//   RDM_SHOTS=<carpeta> (por defecto build/rediseno_capturas_c)
//   RDM_TEXT_SCALE=1.3 / 2.0 para letra ampliada; RDM_WIDTH=360
//
// No es parte de la suite: vive en tool/ y sólo escribe imágenes. Datos
// sintéticos (titular, productos y campañas de prueba).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/identification_request_store.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart' show ProjectionType;
import 'package:agroquimicos/presentation/screens/central_binding_screen.dart';
import 'package:agroquimicos/presentation/screens/consumption_publish_screen.dart';
import 'package:agroquimicos/presentation/screens/declared_needs_screen.dart';
import 'package:agroquimicos/presentation/theme/agro_theme.dart';
import 'package:agroquimicos/presentation/widgets/label_photo_sheet.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/e1_identification_fixtures.dart';
import '../../test/support/f04_mode_ui_harness.dart' show settle;
import '../../test/support/f05_sync_fixtures.dart';
import '../../test/support/f06_consumption_fixtures.dart';

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final loader = FontLoader(name);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await family('DM Sans', [
    'assets/fonts/DMSans-400.ttf',
    'assets/fonts/DMSans-500.ttf',
    'assets/fonts/DMSans-700.ttf',
  ]);
  await family('Bricolage Grotesque', [
    'assets/fonts/BricolageGrotesque-700.ttf',
    'assets/fonts/BricolageGrotesque-800.ttf',
  ]);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(await icons.readAsBytes())));
  await loader.load();
}

void main() {
  sqfliteFfiInit();
  final out = Directory(
    Platform.environment['RDM_SHOTS'] ?? 'build/rediseno_capturas_c',
  )..createSync(recursive: true);
  final width =
      double.tryParse(Platform.environment['RDM_WIDTH'] ?? '') ?? 390.0;
  final scale =
      double.tryParse(Platform.environment['RDM_TEXT_SCALE'] ?? '') ?? 1.0;
  final tag =
      '${scale == 1.0 ? '' : '_x${scale.toString().replaceAll('.', '')}'}'
      '${width == 390 ? '' : '_w${width.round()}'}';

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    // El límite de toda la app: incluye las hojas modales.
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('rdm-c-shot')),
    );
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('${out.path}/$name$tag.png').writeAsBytesSync(bytes!);
  }

  Future<void> setUpView(WidgetTester tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// La pantalla dentro de un router (para que tenga «Volver») con el tema
  /// y el idioma de la app.
  Future<void> pumpRouted(
    WidgetTester tester,
    Widget screen,
    List<Override> overrides,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(
          path: '/s',
          builder: (_, _) => Scaffold(body: SafeArea(child: screen)),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: RepaintBoundary(
          key: const Key('rdm-c-shot'),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: buildAgroTheme(),
            locale: const Locale('es'),
            supportedLocales: const [Locale('es')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: router,
          ),
        ),
      ),
    );
    router.push('/s');
    await settle(tester);
  }

  testWidgets('vínculos, identificación y foto de la etiqueta', (tester) async {
    await setUpView(tester);
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('rdm_c_'),
    );
    final fixture = (await tester.runAsync(
      () => seedSyncFixture(path: '${dir!.path}/c.db'),
    ))!;
    final workspace = (await tester.runAsync(() => photoWorkspace(fixture)))!;
    final requests = IdentificationRequestStore(fixture.database);
    final lime = (await tester.runAsync(
      () => fixture.repo.addProduct(name: 'Cal agrícola', unit: 'KG'),
    ))!;
    final foliar = (await tester.runAsync(
      () => fixture.repo.addProduct(name: 'Abono foliar casero', unit: 'L'),
    ))!;
    await tester.runAsync(() async {
      // «Cal agrícola»: recibida por el sindicato, esperando identificación.
      final received = await requests.create(
        productId: lime,
        sharePhoto: false,
      );
      await requests.markReceived(received.requestId);
      await requests.applyServerView(
        serverView(received.requestId, localName: 'Cal agrícola', unit: 'KG'),
      );
      // «Abono foliar casero»: con foto, solicitud pendiente de envío y la
      // foto autorizada.
      await workspace.savePhoto(foliar);
      await requests.create(productId: foliar, sharePhoto: true);
      // «Adherente local»: con foto y sin solicitud (para la hoja).
      await workspace.savePhoto(fixture.unboundProductId, seed: 1);
    });

    await pumpRouted(tester, const CentralBindingScreen(), [
      databaseProvider.overrideWithValue(fixture.database),
      repositoryProvider.overrideWithValue(workspace.repo),
      declaredNeedStoreProvider.overrideWithValue(fixture.needs),
      centralBindingStoreProvider.overrideWithValue(fixture.bindings),
      syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
      identificationRequestStoreProvider.overrideWithValue(requests),
    ]);
    await shot(tester, '4.4_vinculos_productos');

    await tester.tap(find.byKey(const Key('binding-tab-campaigns')));
    await settle(tester);
    await shot(tester, '4.4b_vinculos_campanas');
    await tester.tap(find.byKey(const Key('binding-tab-products')));
    await settle(tester);

    final row = find.byKey(Key('product-binding-${fixture.unboundProductId}'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final menu = find.descendant(
      of: row,
      matching: find.byType(PopupMenuButton<String>),
    );
    await tester.ensureVisible(menu);
    await settle(tester);
    await tester.tap(menu);
    await settle(tester);
    await tester.tap(find.text('Pedir identificación al sindicato'));
    await settle(tester);
    await shot(tester, '4.5_identificacion');
    await tester.tap(find.byTooltip('Cerrar'));
    await settle(tester);

    // La hoja de la foto se abre desde Catálogos (del orquestador); aquí se
    // abre directamente sobre la misma pantalla.
    final context = tester.element(find.byType(CentralBindingScreen));
    showLabelPhotoSheet(
      context,
      productId: foliar,
      productName: 'Abono foliar casero',
    );
    await settle(tester);
    await shot(tester, '4.6_etiqueta_con_foto');
    await tester.tap(find.byTooltip('Cerrar'));
    await settle(tester);
    showLabelPhotoSheet(context, productId: lime, productName: 'Cal agrícola');
    await settle(tester);
    await shot(tester, '4.6b_etiqueta_sin_foto');
  });

  testWidgets('necesidad declarada y consumo', (tester) async {
    await setUpView(tester);
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('rdm_c_'),
    );
    final f = (await tester.runAsync(
      () => seedConsumptionFixture(path: '${dir!.path}/c2.db'),
    ))!;
    await tester.runAsync(() async {
      // Necesidades: una aceptada y otra pendiente de envío.
      await f.sync.needs.declare(
        referenceDate: inCampaign,
        productId: f.sync.litreProductId,
        quantityBase: 20000,
      );
      final need = (await f.sync.outboxEntries()).single;
      await f.sync.outbox.recordAccepted(
        await f.sync.outbox.markSending(need),
        '2026-11-11T12:00:00.000Z',
      );
      await f.sync.needs.declare(
        referenceDate: inCampaign,
        productId: f.sync.kiloProductId,
        quantityBase: 5000,
      );
      // Consumo: dos totales publicados (uno aceptado), uno nuevo y una
      // aplicación de un familiar que no se publica.
      await f.apply(f.ownerPersonId, {
        f.sync.litreProductId: 6000,
        f.sync.kiloProductId: 1500,
      });
      await f.apply(f.familyPersonId, {f.sync.litreProductId: 2000});
      await f.publisher.publish(await f.publisher.preview());
      final litre = (await f.sync.outboxEntries()).lastWhere(
        (e) =>
            e.projectionType == ProjectionType.consumptionTotal &&
            e.productRef == litreRef,
      );
      await f.sync.outbox.recordAccepted(
        await f.sync.outbox.markSending(litre),
        '2026-11-11T12:30:00.000Z',
      );
      await f.apply(f.ownerPersonId, {f.extraLitreProductId: 400});
    });
    final overrides = [
      databaseProvider.overrideWithValue(f.sync.database),
      repositoryProvider.overrideWithValue(f.sync.repo),
      declaredNeedStoreProvider.overrideWithValue(f.sync.needs),
      centralBindingStoreProvider.overrideWithValue(f.sync.bindings),
      syncOutboxStoreProvider.overrideWithValue(f.sync.outbox),
      consumptionPublisherProvider.overrideWithValue(f.publisher),
    ];

    await pumpRouted(tester, const DeclaredNeedsScreen(), overrides);
    await shot(tester, '6.4_necesidad');

    await pumpRouted(tester, const ConsumptionPublishScreen(), overrides);
    await shot(tester, '6.5_consumo');
    await tester.scrollUntilVisible(
      find.byKey(const Key('publish-consumption')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await shot(tester, '6.5b_consumo_final');
  });
}
