import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/backup_recovery_key_screen.dart';
import 'package:agroquimicos/presentation/screens/late_operations_screen.dart';
import 'package:agroquimicos/presentation/screens/owner_credential_screen.dart';
import 'package:agroquimicos/presentation/screens/purchases_screen.dart';
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
  int lateConfirmCalls = 0;

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
}

class _World {
  late AppDatabase database;
  late _SpyRepository repo;
  late int purchase;
  late String lateRef;
  late Household household;
  final storage = E12CredentialStorage();
  bool online = true;
  bool sameOwner = true;
  int passwordChecks = 0;
  late final OwnerOnlineVerification verification = OwnerOnlineVerification(
    confirmAccount: (email, password) async {
      passwordChecks++;
      return online &&
          email == 'agricultor@example.test' &&
          password == e12Password;
    },
    readSessionScope: () async => sameOwner ? memberA : null,
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

Future<void> _authorizeWithPassword(
  WidgetTester tester, {
  String password = e12Password,
}) async {
  expect(find.byKey(const Key('owner-pin-input')), findsNothing);
  expect(find.text('Configurar PIN'), findsNothing);
  await tester.enterText(
    find.byKey(const Key('owner-account-email')),
    'agricultor@example.test',
  );
  await tester.enterText(
    find.byKey(const Key('owner-account-password')),
    password,
  );
  await tester.tap(find.byKey(const Key('owner-account-submit')));
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

  testWidgets('el titular sin PIN autoriza una reversión con su cuenta', (
    tester,
  ) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(world.database.close);
    await _mount(tester, world);

    await _askToReverse(tester);
    expect(find.textContaining('Factura duplicada'), findsOneWidget);
    expect(world.repo.reversePurchaseCalls, 0);

    await _authorizeWithPassword(tester, password: 'incorrecta');
    expect(find.byKey(const Key('owner-authorization-error')), findsOneWidget);
    expect(await world.purchaseReversedAt(tester), isNull);

    world.online = false;
    await _authorizeWithPassword(tester);
    expect(find.textContaining('Revise la conexión'), findsOneWidget);
    expect(await world.purchaseReversedAt(tester), isNull);

    world.online = true;
    world.sameOwner = false;
    await _authorizeWithPassword(tester);
    expect(world.repo.reversePurchaseCalls, 0);

    world.sameOwner = true;
    await _authorizeWithPassword(tester);
    expect(world.repo.reversePurchaseCalls, 1);
    expect(await world.purchaseReversedAt(tester), isNotNull);
    final audit = (await tester.runAsync(
      () async => world.repo.reversalAudit('PURCHASE', world.purchase),
    ))!;
    expect(audit['reason'], 'Factura duplicada');
    expect(audit['actor_method'], OwnerVerificationMethod.password);
    expect(world.storage.values, isEmpty);
  });

  testWidgets('un PIN configurado en Ajustes autoriza sin internet', (
    tester,
  ) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(world.database.close);
    final router = await _mount(tester, world);
    router.push('/titular/pin');
    await _settle(tester);
    await _configurePin(tester);
    await _back(tester);
    world.online = false;

    await _askToReverse(tester);
    expect(find.byKey(const Key('owner-account-password')), findsNothing);
    await tester.enterText(find.byKey(const Key('owner-pin-input')), _pin);
    await tester.tap(find.byKey(const Key('owner-pin-submit')));
    await _settle(tester);
    expect(world.repo.reversePurchaseCalls, 1);
    expect(world.passwordChecks, 1);
    final audit = (await tester.runAsync(
      () => world.repo.reversalAudit('PURCHASE', world.purchase),
    ))!;
    expect(audit['actor_method'], OwnerVerificationMethod.pin);
  });

  testWidgets('sin titular vinculado la operación no pide credenciales', (
    tester,
  ) async {
    final world = _World();
    await tester.runAsync(() => world.seed(owner: false));
    addTearDown(world.database.close);
    await _mount(tester, world);
    await _askToReverse(tester);
    expect(find.textContaining('elija al titular'), findsOneWidget);
    expect(find.byKey(const Key('owner-account-password')), findsNothing);
    expect(world.repo.reversePurchaseCalls, 0);
  });

  testWidgets('sin PIN se confirma una operación tardía con la cuenta', (
    tester,
  ) async {
    final world = _World();
    await tester.runAsync(() => world.seed(withLate: true));
    addTearDown(world.database.close);
    final router = await _mount(tester, world);
    router.push('/tardias');
    await _settle(tester);
    await tester.tap(find.byKey(Key('late-confirm-${world.lateRef}')));
    await _settle(tester);
    expect(await world.lateStatus(tester), 'PENDING');
    await _authorizeWithPassword(tester);
    expect(await world.lateStatus(tester), 'CONFIRMED');
    expect(world.repo.lateConfirmCalls, 1);
    final row = (await tester.runAsync(
      () async => (await world.database.database).query(
        'late_operation_drafts',
        where: 'draft_ref = ?',
        whereArgs: [world.lateRef],
      ),
    ))!.single;
    expect(row['resolver_method'], OwnerVerificationMethod.password);
  });

  testWidgets('se protege la clave activa y se puede ver con la contraseña', (
    tester,
  ) async {
    final world = _World();
    final vault = _MemoryVault();
    await tester.runAsync(() async {
      await world.seed();
      await _confirmedKeyring(vault);
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

    await tester.tap(find.text('Ver la clave'));
    await _settle(tester);
    expect(find.text('Clave de recuperación'), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await _settle(tester);
    expect(world.passwordChecks, 0);
    expect(find.text('Clave de recuperación'), findsNothing);

    await tester.tap(find.text('Ver la clave'));
    await _settle(tester);
    await _authorizeWithPassword(tester);
    expect(find.text('Clave de recuperación'), findsOneWidget);
  });
}
