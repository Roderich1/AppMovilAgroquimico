// H1 (aprobado por el autor el 2026-11-14): al confirmar un cambio de modo con
// operaciones de compras conjuntas por enviar, el diálogo de confirmación
// avisa que cambiar de modo no las envía ni las cancela y que seguirán
// pendientes hasta el acuse del sindicato. Sólo informa: continuar cambia el
// modo sin tocar la cola, las cantidades ni los consentimientos; cancelar no
// cambia nada; sin pendientes no hay aviso; los bloqueos de siempre siguen.
// App real, sin red.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/presentation/screens/operation_mode_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  const businessOnly = {'app_settings'};
  final modeChange = find.byKey(const Key('mode-change'));
  final modeConfirm = find.byKey(const Key('mode-confirm'));
  final modeCurrent = find.byKey(const Key('mode-current'));
  final notice = find.byKey(const Key('mode-joint-pending'));

  const now = '2026-11-14T12:00:00.000Z';

  /// Una operación de cada cola, con [status] y del miembro [member].
  Future<void> seedOps(
    WidgetTester tester,
    AppDatabase database,
    List<({String table, String id, String status, OwnerScope member})> ops,
  ) => tester.runAsync(() async {
    final db = await database.database;
    for (final (i, op) in ops.indexed) {
      final common = {
        'operation_id': op.id,
        'call_id': 'call-${op.id}',
        'tenant_id': op.member.tenantId,
        'member_id': op.member.memberId,
        'sequence': i + 1,
        'send_status': op.status,
        'attempts': 0,
        'created_at': now,
        'updated_at': now,
      };
      await db.insert(op.table, {
        ...common,
        ...switch (op.table) {
          'joint_purchase_participation_ops' => {
            'kind': 'CONFIRM',
            'lines_json': '[{"product_ref":"p-1","quantity_base":5000}]',
            'consent_version': 'CONV-4',
            'consent_accepted_at': now,
          },
          'joint_purchase_consent_ops' => {
            'scope': 'COLLABORATORS',
            'consent_version': 'CONV-3',
            'decided_at': now,
          },
          _ => {
            'scope': 'ADMINISTRATION',
            'consent_version': 'CONV-4',
            'decided_at': now,
          },
        },
      });
    }
  });

  Future<Map<String, List<Map<String, Object?>>>> business(
    WidgetTester tester,
    AppDatabase database,
  ) async => (await tester.runAsync(
    () async => dumpTables(await database.database, except: businessOnly),
  ))!;

  Future<List<Map<String, Object?>>> queue(
    WidgetTester tester,
    AppDatabase database,
  ) async => (await tester.runAsync(() async {
    final db = await database.database;
    return [
      for (final table in const [
        'joint_purchase_participation_ops',
        'joint_purchase_consent_ops',
        'joint_purchase_access_ops',
      ])
        ...await db.query(table, orderBy: 'operation_id'),
    ];
  }))!;

  String? shownMode(WidgetTester tester) => modeCurrent.evaluate().isEmpty
      ? null
      : tester.widget<Text>(modeCurrent).data;

  Future<void> askChange(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).push('/modo');
    await settle(tester);
    await tester.tap(modeChange);
    await waitUntil(
      tester,
      'el diálogo de confirmación',
      () => modeConfirm.evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> confirmAndWait(
    WidgetTester tester,
    ProviderContainer c,
    OperationMode target,
  ) async {
    await tester.tap(modeConfirm);
    await waitUntil(
      tester,
      'el cambio de modalidad (guardar, recargar y releer)',
      () =>
          c.read(operationModeProvider) == target &&
          find.byKey(const Key('mode-saving')).evaluate().isEmpty &&
          shownMode(tester) == operationModeTitle(target),
      state: () => 'modalidad=${c.read(operationModeProvider)}',
    );
  }

  testWidgets('texto del aviso: singular y plural', (tester) async {
    expect(
      jointPurchasePendingModeNotice(1),
      'Tiene 1 decisión de compras conjuntas pendiente de envío. Cambiar de '
      'modo no la envía ni la cancela: seguirá pendiente hasta que el '
      'sindicato confirme que la recibió.',
    );
    expect(
      jointPurchasePendingModeNotice(3),
      'Tiene 3 decisiones de compras conjuntas pendientes de envío. Cambiar '
      'de modo no las envía ni las cancela: seguirán pendientes hasta que el '
      'sindicato confirme que las recibió.',
    );
  });

  testWidgets('(a) con pendientes: aviso con el número; continuar cambia el '
      'modo y la cola queda igual (mismas filas, mismo estado)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'h1-continuar');
    await seedOps(tester, s.database, [
      // Cuentan: las tres colas, por enviar o pausadas por autorización.
      (
        table: 'joint_purchase_participation_ops',
        id: 'op-1',
        status: 'PENDING_SEND',
        member: memberA,
      ),
      (
        table: 'joint_purchase_consent_ops',
        id: 'op-2',
        status: 'AUTH_PAUSED',
        member: memberA,
      ),
      (
        table: 'joint_purchase_access_ops',
        id: 'op-3',
        status: 'PENDING_SEND',
        member: memberA,
      ),
      // No cuentan: ya recibida y de otro miembro.
      (
        table: 'joint_purchase_access_ops',
        id: 'op-4',
        status: 'RECEIVED',
        member: memberA,
      ),
      (
        table: 'joint_purchase_participation_ops',
        id: 'op-5',
        status: 'PENDING_SEND',
        member: memberB,
      ),
    ]);
    final c = await pumpModeApp(tester, s.database);
    expect(c.read(operationModeProvider), OperationMode.shared);
    final before = await business(tester, s.database);
    final queueBefore = await queue(tester, s.database);
    expect(queueBefore, hasLength(5));

    await askChange(tester, c);
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.text(
          'Tiene 3 decisiones de compras conjuntas pendientes de envío. '
          'Cambiar de modo no las envía ni las cancela: seguirán pendientes '
          'hasta que el sindicato confirme que las recibió.',
        ),
      ),
      findsOneWidget,
    );
    // El texto de siempre sigue en el mismo diálogo, con sus dos botones.
    expect(find.byKey(const Key('mode-consequence')), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    await confirmAndWait(tester, c, OperationMode.personal);
    expect(
      await tester.runAsync(() => OperationModeStore(s.database).current()),
      OperationMode.personal,
    );
    expect(await queue(tester, s.database), queueBefore);
    expect(await business(tester, s.database), before);
  });

  testWidgets('(b) cancelar con un pendiente: no cambia el modo ni la cola', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'h1-cancelar');
    await seedOps(tester, s.database, [
      (
        table: 'joint_purchase_access_ops',
        id: 'op-1',
        status: 'PENDING_SEND',
        member: memberA,
      ),
    ]);
    final c = await pumpModeApp(tester, s.database);
    final before = await business(tester, s.database);

    await askChange(tester, c);
    expect(
      find.descendant(
        of: notice,
        matching: find.text(jointPurchasePendingModeNotice(1)),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(modeConfirm, findsNothing);
    expect(c.read(operationModeProvider), OperationMode.shared);
    expect(shownMode(tester), operationModeTitle(OperationMode.shared));
    expect(
      await tester.runAsync(() => OperationModeStore(s.database).current()),
      OperationMode.shared,
    );
    expect(await business(tester, s.database), before);
  });

  testWidgets('(c) sin pendientes (sólo recibidas o de otro miembro): sin '
      'aviso, y el cambio se hace igual, también de vuelta', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'h1-sin-pendientes');
    await seedOps(tester, s.database, [
      (
        table: 'joint_purchase_access_ops',
        id: 'op-1',
        status: 'RECEIVED',
        member: memberA,
      ),
      (
        table: 'joint_purchase_participation_ops',
        id: 'op-2',
        status: 'SUPERSEDED',
        member: memberA,
      ),
      (
        table: 'joint_purchase_access_ops',
        id: 'op-3',
        status: 'PENDING_SEND',
        member: memberB,
      ),
    ]);
    final c = await pumpModeApp(tester, s.database);

    await askChange(tester, c);
    expect(find.byKey(const Key('mode-consequence')), findsOneWidget);
    expect(notice, findsNothing);
    expect(find.textContaining('compras conjuntas'), findsNothing);
    await confirmAndWait(tester, c, OperationMode.personal);

    // De individual a varias personas, tampoco. El aviso «Ahora usa el modo
    // individual…» (SnackBar) tapa el botón del panel inferior: se retira
    // antes de tocarlo, como haría el usuario al esperar.
    expect(find.textContaining('Ahora usa el modo individual'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(modeChange)).removeCurrentSnackBar();
    await settle(tester);
    expect(tester.widget<OutlinedButton>(modeChange).onPressed, isNotNull);
    await tester.tap(modeChange);
    await waitUntil(
      tester,
      'el diálogo de vuelta',
      () => modeConfirm.evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(notice, findsNothing);
    await confirmAndWait(tester, c, OperationMode.shared);
  });

  testWidgets('(d) los bloqueos de siempre siguen: con productos de otra '
      'persona no hay diálogo ni aviso, aunque haya pendientes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'h1-bloqueo');
    final h = s.household;
    await tester.runAsync(() => h.buy(h.relative, 2000));
    await seedOps(tester, s.database, [
      (
        table: 'joint_purchase_access_ops',
        id: 'op-1',
        status: 'PENDING_SEND',
        member: memberA,
      ),
    ]);
    final c = await pumpModeApp(tester, s.database);
    final before = await business(tester, s.database);

    c.read(routerProvider).push('/modo');
    await settle(tester);
    expect(find.byKey(const Key('mode-blocked')), findsOneWidget);
    expect(find.text('Hermana tiene productos'), findsOneWidget);
    expect(find.byKey(const Key('mode-available')), findsNothing);
    expect(tester.widget<OutlinedButton>(modeChange).onPressed, isNull);
    await tester.tap(modeChange);
    await settle(tester);
    expect(modeConfirm, findsNothing);
    expect(notice, findsNothing);
    expect(c.read(operationModeProvider), OperationMode.shared);
    expect(await business(tester, s.database), before);
  });
}
