// Pestaña «Sindicato» del rediseño (sesión C). Datos sintéticos.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/joint_purchase_store.dart'
    show JointPurchaseNotice;
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/presentation/screens/union_screen.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart' show settle;
import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  Future<SyncFixture> pumpUnion(
    WidgetTester tester, {
    bool declare = false,
    List<Override> overrides = const [],
  }) async {
    final fixture = (await tester.runAsync(() async {
      final f = await seedSyncFixture(path: inMemoryDatabasePath);
      if (declare) {
        await f.needs.declare(
          referenceDate: inCampaign,
          productId: f.litreProductId,
          quantityBase: 20000,
        );
      }
      return f;
    }))!;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const UnionScreen()),
        for (final path in [
          '/sincronizacion',
          '/compras-conjuntas',
          '/planificacion/necesidades',
          '/sincronizacion/consumo',
          '/sindicato/vinculos',
        ])
          GoRoute(path: path, builder: (_, _) => Text('destino $path')),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(fixture.database),
          repositoryProvider.overrideWithValue(fixture.repo),
          declaredNeedStoreProvider.overrideWithValue(fixture.needs),
          centralBindingStoreProvider.overrideWithValue(fixture.bindings),
          syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
          ...overrides,
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => Scaffold(body: child),
        ),
      ),
    );
    await settle(tester);
    return fixture;
  }

  testWidgets('sin envíos: lo dice y no inventa una confirmación', (
    tester,
  ) async {
    await pumpUnion(tester);
    expect(find.text('Nada por enviar'), findsOneWidget);
    expect(find.text('Todavía sin confirmación'), findsOneWidget);
    expect(find.text('Nueva'), findsNothing);
    expect(
      find.text('Convocatorias del sindicato y su participación'),
      findsOneWidget,
    );
  });

  testWidgets('una necesidad guardada cuenta como envío pendiente', (
    tester,
  ) async {
    await pumpUnion(tester, declare: true);
    expect(find.text('1 envío pendiente'), findsOneWidget);
    expect(find.text('Todavía sin confirmación'), findsOneWidget);
  });

  testWidgets('el aviso de convocatoria nueva usa el texto vigente', (
    tester,
  ) async {
    await pumpUnion(
      tester,
      overrides: [
        jointPurchaseNoticeProvider.overrideWith(
          (ref) async => const JointPurchaseNotice(
            callId: 'c-1',
            name: 'Herbicidas invierno',
            deadlineAt: '2026-11-20T23:59:00.000Z',
            total: 1,
          ),
        ),
      ],
    );
    expect(find.text('Nueva'), findsOneWidget);
    expect(
      find.textContaining('Nueva convocatoria: Herbicidas invierno'),
      findsOneWidget,
    );
  });

  // Revisión del autor del 2026-11-12: enviar, consultar novedades y ver el
  // estado son operaciones distintas; consultar no depende de que haya algo
  // pendiente.
  testWidgets('sin envíos pendientes: no ofrece «Enviar», sí «Actualizar» '
      'habilitado y el estado de los envíos', (tester) async {
    await pumpUnion(tester);
    expect(find.text('Enviar pendientes'), findsNothing);
    expect(find.text('Enviar'), findsNothing);
    final refresh = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('union-refresh')),
    );
    expect(refresh.onPressed, isNotNull);
    expect(find.text('Actualizar'), findsOneWidget);
    expect(find.text('Ver estado de los envíos'), findsOneWidget);
  });

  testWidgets('con un envío pendiente: «Enviar pendientes» y «Actualizar» '
      'por separado', (tester) async {
    await pumpUnion(tester, declare: true);
    expect(find.text('Enviar pendientes'), findsOneWidget);
    expect(find.text('Actualizar'), findsOneWidget);
    expect(find.text('Necesidad declarada y consumo'), findsOneWidget);
  });

  testWidgets('el estado de los envíos no repite el menú de Sindicato ni '
      'resume como «sólo totales» lo que envían otras pantallas', (
    tester,
  ) async {
    final fixture = await pumpUnion(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(fixture.database),
          syncOutboxStoreProvider.overrideWithValue(fixture.outbox),
        ],
        child: const MaterialApp(home: Scaffold(body: SyncStatusScreen())),
      ),
    );
    await settle(tester);
    expect(find.text('Envíos'), findsOneWidget);
    expect(find.text('Productos y campañas'), findsNothing);
    expect(find.text('Necesidad declarada'), findsNothing);
    expect(find.text('Consumo para el sindicato'), findsNothing);
    expect(find.textContaining('sólo totales propios'), findsNothing);
    expect(
      find.textContaining('Convocatorias e identificación de productos'),
      findsOneWidget,
    );
  });

  testWidgets('cada entrada abre su pantalla de siempre', (tester) async {
    await pumpUnion(tester);
    for (final (key, path) in [
      ('union-status', '/sincronizacion'),
      ('union-joint-purchases', '/compras-conjuntas'),
      ('union-needs', '/planificacion/necesidades'),
      ('union-consumption', '/sincronizacion/consumo'),
      ('union-links', '/sindicato/vinculos'),
    ]) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await settle(tester);
      expect(find.text('destino $path'), findsOneWidget, reason: key);
      GoRouter.of(tester.element(find.text('destino $path'))).pop();
      await settle(tester);
    }
  });
}
