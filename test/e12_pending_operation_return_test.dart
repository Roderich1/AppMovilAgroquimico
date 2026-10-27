// E-12 (F03 §4 bis.6, A-15): configurar el PIN desde una operación pendiente
// vuelve a su revisión y nunca la ejecuta sola. Revalida la operación y pide
// la autorización con el PIN. Se comprueba con la reversión de una compra y
// con la confirmación de una operación tardía, sobre una base en memoria.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/late_operations_screen.dart';
import 'package:agroquimicos/presentation/screens/owner_credential_screen.dart';
import 'package:agroquimicos/presentation/screens/purchases_screen.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e12_activation_harness.dart';
import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

const _pin = '284917';

/// Cuenta las llamadas a las acciones que exigen la autorización del titular.
class _SpyRepository extends AgroRepository {
  _SpyRepository(super.appDatabase, {super.ownerCredential});

  int reversePurchaseCalls = 0;
  int lateConfirmCalls = 0;
  int lateRejectCalls = 0;

  @override
  Future<void> reversePurchase(
    int purchaseId, {
    required String reason,
    required OwnerAuthorization authorization,
  }) {
    reversePurchaseCalls++;
    return super.reversePurchase(
      purchaseId,
      reason: reason,
      authorization: authorization,
    );
  }

  @override
  Future<LateResolution> confirmLateOperation(
    String draftRef, {
    required OwnerAuthorization authorization,
  }) {
    lateConfirmCalls++;
    return super.confirmLateOperation(draftRef, authorization: authorization);
  }

  @override
  Future<LateResolution> rejectLateOperation(
    String draftRef, {
    required OwnerAuthorization authorization,
    String? note,
  }) {
    lateRejectCalls++;
    return super.rejectLateOperation(
      draftRef,
      authorization: authorization,
      note: note,
    );
  }
}

class _World {
  late AppDatabase database;
  late _SpyRepository repo;
  late int purchase;
  late String lateRef;
  final storage = E12CredentialStorage();
  bool online = true;
  late final OwnerOnlineVerification verification = OwnerOnlineVerification(
    confirmAccount: (_, __) async => online,
    readSessionScope: () async => memberA,
  );
  late final LocalOwnerCredential credential = LocalOwnerCredential(
    storage: storage,
    onlineVerification: verification,
    iterations: 1000,
  );

  Future<void> seed({bool owner = true, bool withLate = false}) async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    if (owner) await seedActivatedInstallation(database);
    repo = _SpyRepository(database, ownerCredential: () => credential);
    final h = await seedHousehold(repo);
    purchase = await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: h.supplier,
        campaignId: h.campaign,
        purchaseDate: DateTime.utc(2026, 1, 5),
        invoiceNumber: 'F-5',
        items: [
          PurchaseItemDraft(
            productId: h.product,
            quantityBase: 500,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [
              AllocationDraft(personId: h.titular, quantityBase: 500),
            ],
          ),
        ],
      ),
    );
    if (withLate) {
      await repo.addHistoricalCampaign(
        name: 'Campaña 2025',
        start: DateTime.utc(2025, 6, 1, 15),
        end: DateTime.utc(2025, 12, 30, 15),
      );
      lateRef = await repo.captureLatePurchase(
        PurchaseDraft(
          supplierId: h.supplier,
          campaignId: h.campaign,
          purchaseDate: DateTime.utc(2025, 8, 10, 15),
          items: [
            PurchaseItemDraft(
              productId: h.product,
              quantityBase: 500,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 10000,
              allocations: [
                AllocationDraft(personId: h.titular, quantityBase: 500),
              ],
            ),
          ],
        ),
        reason: 'Factura encontrada',
      );
    }
  }

  Future<Object?> purchaseReversedAt(WidgetTester tester) async =>
      (await tester.runAsync(
        () async => (await database.database).query(
          'purchases',
          columns: ['reversed_at'],
          where: 'id=?',
          whereArgs: [purchase],
        ),
      ))!.single['reversed_at'];

  Future<Object?> lateStatus(WidgetTester tester) async =>
      (await tester.runAsync(
        () async => (await database.database).query(
          'late_operation_drafts',
          columns: ['status'],
          where: 'draft_ref=?',
          whereArgs: [lateRef],
        ),
      ))!.single['status'];
}

Future<void> _settle(WidgetTester tester, {int rounds = 15}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<GoRouter> _mount(WidgetTester tester, _World world) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: PurchasesScreen()),
      ),
      GoRoute(
        path: '/tardias',
        builder: (_, __) => const LateOperationsScreen(),
      ),
      GoRoute(
        path: '/titular/pin',
        builder: (_, __) => const OwnerCredentialScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.physicalSize = const Size(500, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, __) => null,
      overrides: [
        activatedInstallationForTests(),
        repositoryProvider.overrideWithValue(world.repo),
        ownerOnlineVerificationProvider.overrideWithValue(world.verification),
        localOwnerCredentialProvider.overrideWithValue(world.credential),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
  return router;
}

/// Revertir la compra: menú, motivo y «Continuar».
Future<void> _askToReverse(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>).first);
  await _settle(tester);
  await tester.tap(find.text('Revertir compra').last);
  await _settle(tester);
  await tester.enterText(
    find.byKey(const Key('approval-reason')),
    'Factura duplicada',
  );
  await tester.tap(find.byKey(const Key('approval-continue')));
  await _settle(tester);
}

/// En «PIN del titular» (vía con contraseña): acreditar y guardar el PIN.
Future<void> _configurePin(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('owner-pin-configure')));
  await _settle(tester);
  expect(find.byKey(const Key('pin-email')), findsOneWidget);
  await tester.enterText(
    find.byKey(const Key('pin-email')),
    'agricultor@example.test',
  );
  await tester.enterText(find.byKey(const Key('pin-password')), e12Password);
  await tester.tap(find.byKey(const Key('pin-verify-online')));
  await _settle(tester);
  await tester.enterText(find.byKey(const Key('pin-new')), _pin);
  await tester.enterText(find.byKey(const Key('pin-confirm')), _pin);
  await tester.tap(find.byKey(const Key('pin-save')));
  await _settle(tester);
  expect(find.byKey(const Key('pin-done')), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('pin-back')));
  await tester.tap(find.byKey(const Key('pin-back')));
  await _settle(tester);
}

void main() {
  sqfliteFfiInit();

  testWidgets('W1/E3 en host: reversión → «Configurar PIN» → volver: reaparece '
      'la revisión con el motivo; no se ejecuta hasta poner el PIN y '
      '«Autorizar»', (tester) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(world.database.close);
    await _mount(tester, world);

    await _askToReverse(tester);
    expect(find.byKey(const Key('owner-pin-unavailable')), findsOneWidget);
    await _configurePin(tester);
    expect(world.repo.reversePurchaseCalls, 0);
    await _back(tester);

    // REVISIÓN otra vez: los mismos efectos y el motivo escrito y editable.
    expect(
      find.text(OwnerPinReturnTexts.header),
      findsOneWidget,
      reason: 'encabezado del retorno',
    );
    expect(find.byKey(const Key('approval-return-header')), findsOneWidget);
    final reason = tester.widget<TextField>(
      find.byKey(const Key('approval-reason')),
    );
    expect(reason.controller!.text, 'Factura duplicada');
    expect(world.repo.reversePurchaseCalls, 0);
    expect(await world.purchaseReversedAt(tester), isNull);

    await tester.enterText(
      find.byKey(const Key('approval-reason')),
      'Factura duplicada (revisada)',
    );
    await tester.tap(find.byKey(const Key('approval-continue')));
    await _settle(tester);
    expect(find.byKey(const Key('owner-pin-input')), findsOneWidget);
    expect(find.byKey(const Key('owner-pin-return-header')), findsOneWidget);
    expect(world.repo.reversePurchaseCalls, 0, reason: 'nunca sola');
    expect(await world.purchaseReversedAt(tester), isNull);

    await tester.enterText(find.byKey(const Key('owner-pin-input')), _pin);
    await tester.tap(find.byKey(const Key('owner-pin-submit')));
    await _settle(tester, rounds: 25);
    expect(world.repo.reversePurchaseCalls, 1);
    expect(await world.purchaseReversedAt(tester), isNotNull);
    final audit = (await tester.runAsync(
      () async => (await world.database.database).query('reversal_audit'),
    ))!.single;
    expect(audit['reason'], 'Factura duplicada (revisada)');
  });

  testWidgets(
    'W2: volver sin crear el PIN cancela, con aviso, sin tocar nada',
    (tester) async {
      final world = _World();
      await tester.runAsync(world.seed);
      addTearDown(world.database.close);
      await _mount(tester, world);
      final before = (await tester.runAsync(
        () async => dumpTables(await world.database.database),
      ))!;

      await _askToReverse(tester);
      await tester.tap(find.byKey(const Key('owner-pin-configure')));
      await _settle(tester);
      await _back(tester);
      expect(find.text(OwnerPinReturnTexts.notConfigured), findsOneWidget);
      expect(find.byKey(const Key('approval-reason')), findsNothing);
      expect(find.byKey(const Key('owner-pin-input')), findsNothing);
      expect(world.repo.reversePurchaseCalls, 0);
      expect(
        await tester.runAsync(
          () async => dumpTables(await world.database.database),
        ),
        before,
      );
    },
  );

  testWidgets('W2 (fallo de red): sin acreditación en línea no hay PIN y la '
      'operación se cancela sin cambios', (tester) async {
    final world = _World()..online = false;
    await tester.runAsync(world.seed);
    addTearDown(world.database.close);
    await _mount(tester, world);

    await _askToReverse(tester);
    await tester.tap(find.byKey(const Key('owner-pin-configure')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('pin-email')),
      'agricultor@example.test',
    );
    await tester.enterText(find.byKey(const Key('pin-password')), e12Password);
    await tester.tap(find.byKey(const Key('pin-verify-online')));
    await _settle(tester);
    expect(find.byKey(const Key('pin-message')), findsOneWidget);
    expect(find.byKey(const Key('pin-new')), findsNothing);
    await _back(tester);
    expect(find.text(OwnerPinReturnTexts.notConfigured), findsOneWidget);
    expect(world.repo.reversePurchaseCalls, 0);
    expect(await world.purchaseReversedAt(tester), isNull);
    expect(world.storage.values, isEmpty);
  });

  testWidgets('W3: si la compra se revirtió mientras se configuraba el PIN, '
      'al volver se avisa y no se pide nada', (tester) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(world.database.close);
    await _mount(tester, world);

    await _askToReverse(tester);
    await _configurePin(tester);
    await tester.runAsync(
      () => world.repo.reversePurchaseUnauditedForTesting(
        world.purchase,
        reason: 'Revertida por otro camino',
      ),
    );
    await _back(tester);
    await _settle(tester);
    expect(
      find.text(OwnerPinReturnTexts.stale('ya fue revertida')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('approval-reason')), findsNothing);
    expect(find.byKey(const Key('owner-pin-input')), findsNothing);
    expect(world.repo.reversePurchaseCalls, 0);
  });

  testWidgets('W4/E3 en host: operación tardía: al volver se pide el PIN y '
      'nunca se confirma sola; cancelar la deja pendiente', (tester) async {
    final world = _World();
    await tester.runAsync(() => world.seed(withLate: true));
    addTearDown(world.database.close);
    final router = await _mount(tester, world);
    router.go('/tardias');
    await _settle(tester);

    await tester.tap(find.byKey(Key('late-confirm-${world.lateRef}')));
    await _settle(tester);
    expect(find.byKey(const Key('owner-pin-unavailable')), findsOneWidget);
    await _configurePin(tester);
    await _back(tester);

    expect(find.byKey(const Key('owner-pin-return-header')), findsOneWidget);
    expect(find.byKey(const Key('owner-pin-effects')), findsOneWidget);
    expect(world.repo.lateConfirmCalls, 0);
    expect(await world.lateStatus(tester), 'PENDING');

    await tester.tap(find.text('Cancelar'));
    await _settle(tester);
    expect(world.repo.lateConfirmCalls, 0);
    expect(world.repo.lateRejectCalls, 0);
    expect(await world.lateStatus(tester), 'PENDING');

    // Con el PIN ya creado, el camino normal autoriza y confirma una vez.
    await tester.tap(find.byKey(Key('late-confirm-${world.lateRef}')));
    await _settle(tester);
    expect(find.byKey(const Key('owner-pin-return-header')), findsNothing);
    await tester.enterText(find.byKey(const Key('owner-pin-input')), _pin);
    await tester.tap(find.byKey(const Key('owner-pin-submit')));
    await _settle(tester, rounds: 25);
    expect(world.repo.lateConfirmCalls, 1);
    expect(await world.lateStatus(tester), 'CONFIRMED');
  });

  testWidgets('W5 (H9): sin titular vinculado no se ofrece «Configurar PIN»', (
    tester,
  ) async {
    final world = _World();
    await tester.runAsync(() => world.seed(owner: false));
    addTearDown(world.database.close);
    await _mount(tester, world);

    await _askToReverse(tester);
    expect(find.text(OwnerPinReturnTexts.noOwner), findsOneWidget);
    expect(find.byKey(const Key('owner-pin-configure')), findsNothing);
    await tester.tap(find.text('Cerrar'));
    await _settle(tester);
    expect(world.repo.reversePurchaseCalls, 0);
    expect(await world.purchaseReversedAt(tester), isNull);
  });

  testWidgets('W6/T8: cerrar la app en CONFIGURANDO no ejecuta nada', (
    tester,
  ) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(world.database.close);
    await _mount(tester, world);

    await _askToReverse(tester);
    await _configurePin(tester);
    // La app se cierra con la operación pendiente sólo en memoria.
    await tester.pumpWidget(const SizedBox());
    await _settle(tester, rounds: 4);
    await _mount(tester, world);
    expect(find.byKey(const Key('approval-reason')), findsNothing);
    expect(find.byKey(const Key('owner-pin-input')), findsNothing);
    expect(world.repo.reversePurchaseCalls, 0);
    expect(await world.purchaseReversedAt(tester), isNull);
  });
}
