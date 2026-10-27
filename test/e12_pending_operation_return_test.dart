// E-12 (F03 §4 bis.6, A-15): configurar el PIN desde una operación pendiente
// vuelve a su revisión y nunca la ejecuta sola. Revalida la operación y pide
// la autorización con el PIN. Se comprueba con la reversión de una compra y
// con la confirmación de una operación tardía, sobre una base en memoria.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/applications_screen.dart';
import 'package:agroquimicos/presentation/screens/backup_recovery_key_screen.dart';
import 'package:agroquimicos/presentation/screens/late_operations_screen.dart';
import 'package:agroquimicos/presentation/screens/owner_credential_screen.dart';
import 'package:agroquimicos/presentation/screens/purchases_screen.dart';
import 'package:agroquimicos/presentation/screens/transfers_screen.dart';
import 'package:agroquimicos/services/backup/backup_keyring.dart';
import 'package:agroquimicos/services/backup/remote_backup_providers.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
  int reverseApplicationCalls = 0;
  int reverseTransferCalls = 0;
  int lateConfirmCalls = 0;
  int lateRejectCalls = 0;

  @override
  Future<void> reverseApplication(
    int applicationId, {
    required String reason,
    required OwnerAuthorization authorization,
  }) {
    reverseApplicationCalls++;
    return super.reverseApplication(
      applicationId,
      reason: reason,
      authorization: authorization,
    );
  }

  @override
  Future<void> reverseTransfer(
    int transferId, {
    required String reason,
    required OwnerAuthorization authorization,
  }) {
    reverseTransferCalls++;
    return super.reverseTransfer(
      transferId,
      reason: reason,
      authorization: authorization,
    );
  }

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
  late Household household;
  late int application;
  late int transfer;
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

  Future<void> seed({
    bool owner = true,
    bool withLate = false,
    bool withMovements = false,
  }) async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    if (owner) await seedActivatedInstallation(database);
    repo = _SpyRepository(database, ownerCredential: () => credential);
    final h = household = await seedHousehold(repo);
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
    if (withMovements) {
      application = await repo.confirmApplication(
        ApplicationDraft(
          personId: h.titular,
          farmId: h.titularFarm,
          campaignId: h.campaign,
          appliedAt: DateTime.utc(2026, 1, 20),
          lines: [
            ApplicationLineDraft(productId: h.product, quantityBase: 100),
          ],
        ),
      );
      transfer = await repo.transferProductFifo(
        fromPersonId: h.titular,
        toPersonId: h.relative,
        productId: h.product,
        quantityBase: 100,
      );
    }
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

  Future<Object?> reversedAt(WidgetTester tester, String table, int id) async =>
      (await tester.runAsync(
        () async => (await database.database).query(
          table,
          columns: ['reversed_at'],
          where: 'id=?',
          whereArgs: [id],
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

Future<GoRouter> _mount(
  WidgetTester tester,
  _World world, {
  Widget home = const PurchasesScreen(),
  List<Override> extra = const [],
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(body: home),
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
        ...extra,
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

/// Motivo y «Continuar» en la revisión de una reversión.
Future<void> _giveReason(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('approval-reason')),
    'Registro equivocado',
  );
  await tester.tap(find.byKey(const Key('approval-continue')));
  await _settle(tester);
}

/// Llavero en memoria para F08.
class _MemoryVault implements BackupKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

Future<String> _confirmedKeyring(_MemoryVault vault) async {
  final keyring = BackupKeyring(
    vault,
    consumeAuthorization: (_, __, ___) async {},
  );
  final pending = await keyring.pendingKey();
  await keyring.confirmPending(pending.displayText);
  return (await keyring.activeKey())!.keyId;
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

  testWidgets('W1b: reversión de una aplicación: vuelve a la revisión y no se '
      'ejecuta sola', (tester) async {
    final world = _World();
    await tester.runAsync(() => world.seed(withMovements: true));
    addTearDown(world.database.close);
    await _mount(tester, world, home: const ApplicationsScreen());

    await tester.tap(find.byTooltip('Revertir').first);
    await _settle(tester);
    await _giveReason(tester);
    await _configurePin(tester);
    await _back(tester);
    expect(find.byKey(const Key('approval-return-header')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('approval-reason')))
          .controller!
          .text,
      'Registro equivocado',
    );
    await tester.tap(find.byKey(const Key('approval-continue')));
    await _settle(tester);
    expect(find.byKey(const Key('owner-pin-input')), findsOneWidget);
    expect(world.repo.reverseApplicationCalls, 0);
    expect(
      await world.reversedAt(tester, 'applications', world.application),
      isNull,
    );
    await tester.tap(find.text('Cancelar'));
    await _settle(tester);
    expect(world.repo.reverseApplicationCalls, 0);
    expect(
      await world.reversedAt(tester, 'applications', world.application),
      isNull,
    );
  });

  testWidgets('W1c: reversión de una transferencia: vuelve a la revisión y no '
      'se ejecuta sola', (tester) async {
    final world = _World();
    await tester.runAsync(() => world.seed(withMovements: true));
    addTearDown(world.database.close);
    await _mount(tester, world, home: const TransfersScreen());

    await tester.tap(find.byTooltip('Revertir').first);
    await _settle(tester);
    await _giveReason(tester);
    await _configurePin(tester);
    await _back(tester);
    expect(find.byKey(const Key('approval-return-header')), findsOneWidget);
    await tester.tap(find.byKey(const Key('approval-continue')));
    await _settle(tester);
    expect(find.byKey(const Key('owner-pin-input')), findsOneWidget);
    expect(world.repo.reverseTransferCalls, 0);
    await tester.tap(find.text('Cancelar'));
    await _settle(tester);
    expect(world.repo.reverseTransferCalls, 0);
    expect(await world.reversedAt(tester, 'transfers', world.transfer), isNull);
  });

  testWidgets('W3b: una tardía resuelta mientras se configuraba el PIN no '
      'pide nada al volver', (tester) async {
    final world = _World();
    await tester.runAsync(() => world.seed(withLate: true));
    addTearDown(world.database.close);
    final router = await _mount(tester, world);
    router.go('/tardias');
    await _settle(tester);

    await tester.tap(find.byKey(Key('late-confirm-${world.lateRef}')));
    await _settle(tester);
    await _configurePin(tester);
    // Otro camino la resolvió entretanto (fila completa de un rechazo).
    await tester.runAsync(() async {
      final binding = await OwnerBindingStore(world.database).activeBinding();
      await (await world.database.database).update(
        'late_operation_drafts',
        {
          'status': 'REJECTED',
          'resolved_at': '2026-10-27T18:00:00.000Z',
          'resolver_person_id': binding!.personId,
          'resolver_binding_id': binding.id,
          'resolver_member_id': binding.scope.memberId,
          'resolver_tenant_id': binding.scope.tenantId,
          'resolver_method': 'LOCAL_PIN',
          'resolver_enrolment_ref': 'otro-camino',
        },
        where: 'draft_ref=?',
        whereArgs: [world.lateRef],
      );
    });
    expect(await world.lateStatus(tester), 'REJECTED');
    await _back(tester);
    await _settle(tester);
    expect(
      find.text(OwnerPinReturnTexts.stale('ya se resolvió')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('owner-pin-input')), findsNothing);
    expect(world.repo.lateConfirmCalls, 0);
  });

  testWidgets('W5b: si cambia el titular mientras se configura el PIN, al '
      'volver se cancela', (tester) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(world.database.close);
    await _mount(tester, world);

    await _askToReverse(tester);
    await _configurePin(tester);
    await tester.runAsync(
      () => OwnerBindingStore(world.database).changeOwner(
        newPersonId: world.household.relative,
        sessionScope: memberA,
      ),
    );
    await _back(tester);
    await _settle(tester);
    expect(find.text(OwnerPinReturnTexts.ownerChanged), findsOneWidget);
    expect(find.byKey(const Key('approval-reason')), findsNothing);
    expect(world.repo.reversePurchaseCalls, 0);
    expect(await world.purchaseReversedAt(tester), isNull);
  });

  testWidgets('W3c: si la revalidación lanza, se cancela con su propio aviso', (
    tester,
  ) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(world.database.close);
    OwnerAuthorization? result;
    var finished = false;
    await _mount(
      tester,
      world,
      home: Consumer(
        builder: (context, ref, _) => FilledButton(
          onPressed: () async {
            result = await requestOwnerAuthorization(
              context,
              ref,
              purpose: AuthorizationPurpose.reversePurchase,
              subjectRef: 'purchase:${world.purchase}',
              title: 'Acción de prueba',
              effects: 'Efectos de prueba',
              revalidate: () async => throw StateError('lectura fallida'),
            );
            finished = true;
          },
          child: const Text('Acción'),
        ),
      ),
    );
    await tester.tap(find.text('Acción'));
    await _settle(tester);
    await _configurePin(tester);
    await _back(tester);
    await _settle(tester);
    expect(finished, isTrue);
    expect(result, isNull);
    expect(find.text(OwnerPinReturnTexts.checkFailed), findsOneWidget);
    expect(find.text(OwnerPinReturnTexts.notConfigured), findsNothing);
    expect(find.byKey(const Key('owner-pin-input')), findsNothing);
  });

  testWidgets('W2c: PIN bloqueado (requiresOnlineReset) → «Configurar PIN» → '
      'restablecer con contraseña → vuelve a la revisión sin ejecutar', (
    tester,
  ) async {
    final world = _World();
    await tester.runAsync(() async {
      await world.seed();
      final binding = await OwnerBindingStore(world.database).activeBinding();
      final context = OwnerBindingContext(
        bindingId: binding!.id,
        personId: binding.personId,
        scope: binding.scope,
      );
      await world.credential.enroll(
        pin: '502813',
        pinConfirmation: '502813',
        proof: await world.verification.verify(
          email: 'e',
          password: 'p',
          binding: context,
        ),
        binding: context,
      );
      world.storage.values['attempts'] = '{"failures":10,"lockedUntil":null}';
      expect(
        (await world.credential.status(context)).state,
        CredentialState.requiresOnlineReset,
      );
    });
    addTearDown(world.database.close);
    await _mount(tester, world);

    await _askToReverse(tester);
    expect(
      find.text(
        'El PIN quedó bloqueado. Restablézcalo acreditando al titular en línea.',
      ),
      findsOneWidget,
    );
    await _configurePin(tester);
    await _back(tester);
    expect(find.byKey(const Key('approval-return-header')), findsOneWidget);
    expect(world.repo.reversePurchaseCalls, 0);
    await tester.tap(find.text('Cancelar'));
    await _settle(tester);
    expect(world.repo.reversePurchaseCalls, 0);
    expect(await world.purchaseReversedAt(tester), isNull);
  });

  group('F08: ver la clave de recuperación sin PIN', () {
    Future<(_World, _MemoryVault, String)> prepare(WidgetTester tester) async {
      final world = _World();
      final vault = _MemoryVault();
      late String keyId;
      await tester.runAsync(() async {
        await world.seed();
        keyId = await _confirmedKeyring(vault);
      });
      addTearDown(world.database.close);
      await _mount(
        tester,
        world,
        home: Consumer(
          builder: (context, ref, _) => FilledButton(
            onPressed: () => revealActiveRecoveryKey(context, ref),
            child: const Text('Ver la clave'),
          ),
        ),
        extra: [
          backupKeyringProvider.overrideWith(
            (ref) => BackupKeyring(
              vault,
              consumeAuthorization: ref.watch(
                backupKeyAuthorizationConsumerProvider,
              ),
            ),
          ),
        ],
      );
      return (world, vault, keyId);
    }

    const f08Message =
        'Hace falta la autorización del titular en este teléfono. No se mostró '
        'ni se cambió la clave.';

    testWidgets('C-5: con la misma clave vuelve al diálogo del PIN; cancelar '
        'da un solo aviso, el de F08', (tester) async {
      await prepare(tester);
      await tester.tap(find.text('Ver la clave'));
      await _settle(tester);
      await _configurePin(tester);
      await _back(tester);
      expect(find.byKey(const Key('owner-pin-return-header')), findsOneWidget);
      expect(find.byType(RecoveryKeyDisplay), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await _settle(tester);
      await _settle(tester);
      expect(find.text(f08Message), findsOneWidget);
      expect(find.byType(RecoveryKeyDisplay), findsNothing);
    });

    testWidgets('C-5: si la clave activa cambió mientras se configuraba, no '
        'se pide el PIN y sólo queda el aviso de F08', (tester) async {
      final (_, vault, keyId) = await prepare(tester);
      await tester.tap(find.text('Ver la clave'));
      await _settle(tester);
      await _configurePin(tester);
      final other = _MemoryVault();
      final otherKeyId = (await tester.runAsync(
        () => _confirmedKeyring(other),
      ))!;
      expect(otherKeyId, isNot(keyId));
      vault.value = other.value;
      await _back(tester);
      await _settle(tester);
      expect(find.byKey(const Key('owner-pin-input')), findsNothing);
      expect(find.text(f08Message), findsOneWidget);
      expect(
        find.text(OwnerPinReturnTexts.stale('la clave activa cambió')),
        findsNothing,
      );
      expect(find.byType(RecoveryKeyDisplay), findsNothing);
    });
  });
}
