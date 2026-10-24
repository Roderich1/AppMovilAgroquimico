// RF-03 en pantalla: el titular confirma un borrador tardío con su PIN desde
// «Operaciones tardías» y se aplica en su campaña cerrada.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/late_operations_screen.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';

class _Storage implements CredentialStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets('a pending late purchase is confirmed with the PIN and applied in its closed campaign', (tester) async {
    late AppDatabase database;
    late AgroRepository repo;
    late LocalOwnerCredential credential;
    late String ref;
    late OwnerBindingContext binding;
    await tester.runAsync(() async {
      database = openDb(inMemoryDatabasePath);
      final bound = await seedActivatedInstallation(database);
      repo = AgroRepository(database);
      final h = await seedHousehold(repo);
      await repo.addHistoricalCampaign(
        name: 'Campaña 2025',
        start: DateTime.utc(2025, 6, 1, 15),
        end: DateTime.utc(2025, 12, 30, 15),
      );
      binding = OwnerBindingContext(bindingId: bound.id, personId: bound.personId, scope: memberA);
      credential = LocalOwnerCredential(storage: _Storage(), iterations: 1000);
      await credential.enroll(
        pin: '284917',
        pinConfirmation: '284917',
        proof: await OwnerOnlineVerification(
          reauthenticate: (_, __) async => true,
          readSessionScope: () async => memberA,
        ).verify(email: 'e', password: 'p', binding: binding),
        binding: binding,
      );
      ref = await repo.captureLatePurchase(
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
              allocations: [AllocationDraft(personId: h.titular, quantityBase: 500)],
            ),
          ],
        ),
        reason: 'Factura encontrada',
      );
    });
    addTearDown(database.close);
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          localOwnerCredentialProvider.overrideWithValue(credential),
          ownerBindingContextReaderProvider.overrideWithValue(() async => binding),
        ],
        child: const MaterialApp(home: LateOperationsScreen()),
      ),
    );
    await settle(tester);
    expect(find.textContaining('Pendiente de revisión'), findsOneWidget);

    await tester.tap(find.byKey(Key('late-confirm-$ref')));
    await settle(tester);
    expect(find.byKey(const Key('owner-pin-effects')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('owner-pin-input')), '284917');
    await tester.tap(find.byKey(const Key('owner-pin-submit')));
    await settle(tester);

    final db = await tester.runAsync(() => database.database);
    final draft = (await tester.runAsync(() => db!.query('late_operation_drafts')))!.single;
    expect(draft['status'], 'CONFIRMED');
    final purchases = (await tester.runAsync(() => db!.query('purchases')))!;
    expect(purchases, hasLength(1));
    expect(find.textContaining('Confirmada por el titular'), findsOneWidget);
    expect(find.textContaining('no se actualiza'), findsOneWidget);
  });

  testWidgets('only a closed-campaign date offers review, and the reason is required', (tester) async {
    final captured = <String>[];
    final results = <bool>[];
    Object error = CampaignDateException(CampaignDateProblem.none, 'Sin campaña');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await offerLateRegistration(
                  context,
                  error: error,
                  what: 'esta compra',
                  capture: (reason) async {
                    captured.add(reason);
                    return 'ref';
                  },
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('late-reason')), findsNothing);
    expect(results, [false]);

    error = CampaignDateException(CampaignDateProblem.closed, 'La campaña está cerrada.');
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sin efecto en existencias'), findsOneWidget);
    await tester.tap(find.byKey(const Key('late-register')));
    await tester.pumpAndSettle();
    expect(find.text('Indique el motivo.'), findsOneWidget);
    expect(captured, isEmpty);
    await tester.enterText(find.byKey(const Key('late-reason')), 'Factura encontrada');
    await tester.tap(find.byKey(const Key('late-register')));
    await tester.pumpAndSettle();
    expect(captured, ['Factura encontrada']);
    expect(results, [false, true]);
  });
}
