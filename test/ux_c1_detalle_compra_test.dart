// A2 (bloque de experiencia, 2026-10-30): detalle de sólo lectura de una
// compra. Se comprueba contra lo guardado en la base: importes, destinatarios,
// precio original y tipo de cambio, pagos (también revertidos) y auditoría de
// la reversión; que consultar no escribe nada; y que cabe en un teléfono
// estrecho con la letra ampliada sin reducirla.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/presentation/screens/purchase_detail_screen.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

const _reason = 'Factura duplicada: el proveedor la emitió dos veces';

class _World {
  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late TestOwnerPin pin;
  late OwnerBindingContext binding;
  late int titular, vecino, supplier, campaign, glifosato, mancozeb;

  Future<void> seed() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final bound = await seedActivatedInstallation(database);
    repo = AgroRepository(database, ownerCredential: () => pin.credential);
    db = await database.database;
    titular = bound.personId;
    binding = OwnerBindingContext(
      bindingId: bound.id,
      personId: bound.personId,
      scope: memberA,
    );
    pin = await TestOwnerPin.enrolled(binding);
    vecino = await repo.addPerson(
      name: 'Don Carlos Gutiérrez',
      role: PersonRole.thirdParty,
    );
    supplier = await repo.addSupplier(
      name: 'Comercializadora Agroquímica del Valle Alto S.R.L.',
    );
    campaign = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato Demo');
    mancozeb = await repo.addProduct(name: 'Mancozeb Demo', unit: 'KG');
  }

  /// Glifosato 4 L en bolivianos (3 L al titular, 1 L al vecino) y Mancozeb
  /// 2 kg en dólares para el titular; pagada en parte.
  Future<int> buy() async {
    final id = await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 1, 5, 12),
        invoiceNumber: 'F-1029',
        notes: 'Entregado en la comunidad',
        exchangeRateSource: ExchangeRateSource.agreedWithSupplier,
        items: [
          PurchaseItemDraft(
            productId: glifosato,
            quantityBase: 4000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 4500,
            allocations: [
              AllocationDraft(personId: titular, quantityBase: 3000),
              AllocationDraft(personId: vecino, quantityBase: 1000),
            ],
          ),
          PurchaseItemDraft(
            productId: mancozeb,
            quantityBase: 2000,
            currency: CurrencyCode.usd,
            originalUnitPriceMinor: 650,
            exchangeRateScaled: 6960000,
            allocations: [
              AllocationDraft(personId: titular, quantityBase: 2000),
            ],
          ),
        ],
      ),
    );
    await repo.addProviderPayment(
      purchaseId: id,
      payerPersonId: titular,
      amountBobMinor: 10000,
      method: PaymentMethod.cash,
      date: DateTime.utc(2026, 1, 6, 12),
    );
    return id;
  }

  Future<void> reverse(int id) async => repo.reversePurchase(
    id,
    reason: _reason,
    authorization: await pin.credential.verify(
      pin: '284917',
      purpose: AuthorizationPurpose.reversePurchase,
      subjectRef: 'purchase:$id',
      binding: binding,
    ),
  );
}

Future<void> _settle(WidgetTester tester, {int rounds = 6}) async {
  for (var round = 0; round < rounds; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

Future<void> _pump(
  WidgetTester tester,
  _World world,
  int purchaseId, {
  double width = 500,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(world.repo),
        activatedInstallationForTests(),
        localOwnerCredentialProvider.overrideWithValue(world.pin.credential),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: PurchaseDetailScreen(purchaseId: purchaseId)),
      ),
    ),
  );
  await _settle(tester);
}

/// Texto completo de un `Text` o `Text.rich`.
bool _shows(WidgetTester tester, String expected) => tester
    .widgetList<RichText>(find.byType(RichText))
    .any((text) => text.text.toPlainText() == expected);

void main() {
  sqfliteFfiInit();

  testWidgets('una compra confirmada muestra lo guardado: importes, '
      'destinatarios, precio en dólares y pagos', (tester) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(() => world.database.close());
    final id = (await tester.runAsync(world.buy))!;
    await _pump(tester, world, id);

    final stored = (await tester.runAsync(
      () => world.db.query('purchases', where: 'id=?', whereArgs: [id]),
    ))!.single;
    final items = (await tester.runAsync(
      () => world.db.query(
        'purchase_items',
        where: 'purchase_id=?',
        whereArgs: [id],
        orderBy: 'id',
      ),
    ))!;
    final charges = (await tester.runAsync(
      () => world.db.query(
        'purchase_allocations',
        where: 'amount_bob_minor_if_allocation_charge IS NOT NULL',
      ),
    ))!;

    expect(
      find.text('Comercializadora Agroquímica del Valle Alto S.R.L.'),
      findsOneWidget,
    );
    expect(find.text('Confirmada'), findsOneWidget);
    expect(_shows(tester, 'Factura: F-1029'), isTrue);
    expect(_shows(tester, 'Fecha de compra: 05/01/2026'), isTrue);
    expect(_shows(tester, 'Campaña: Verano 2026'), isTrue);
    expect(
      _shows(tester, 'Total: ${formatBob(stored['total_bob_minor']! as int)}'),
      isTrue,
    );
    expect(_shows(tester, 'Pagado al proveedor: ${formatBob(10000)}'), isTrue);
    expect(
      _shows(tester, 'Origen del tipo de cambio: Acordado con el proveedor'),
      isTrue,
    );
    expect(_shows(tester, 'Notas: Entregado en la comunidad'), isTrue);

    // Líneas: cantidades, precios y subtotales guardados.
    expect(find.text('2 productos'), findsOneWidget);
    expect(find.text('Glifosato Demo · 4 L'), findsOneWidget);
    expect(_shows(tester, 'Precio: ${formatBob(4500).trim()} por L'), isTrue);
    expect(
      _shows(
        tester,
        'Subtotal: ${formatBob(items[0]['subtotal_bob_minor']! as int)}',
      ),
      isTrue,
    );
    expect(find.text('Mancozeb Demo · 2 KG'), findsOneWidget);
    expect(
      _shows(
        tester,
        'Precio: ${formatUsd(650)} por KG · tipo de cambio 6,96 = '
        '${formatBob(items[1]['converted_unit_price_bob_minor']! as int).trim()} '
        'por KG',
      ),
      isTrue,
    );

    // Destinatarios: a quién se asignó cada cantidad y cómo se le cobra.
    expect(_shows(tester, 'Para Titular: 3 L · se cobra al aplicar'), isTrue);
    expect(
      _shows(
        tester,
        'Para Don Carlos Gutiérrez: 1 L · cargo por compra '
        '${formatBob(charges.single['amount_bob_minor_if_allocation_charge']! as int)}',
      ),
      isTrue,
    );
    expect(_shows(tester, 'Para Titular: 2 KG · se cobra al aplicar'), isTrue);

    expect(
      find.text(
        '06/01/2026 · Efectivo · pagó Titular · ${formatBob(10000).trim()}',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una compra revertida muestra el estado, la auditoría y los '
      'pagos revertidos', (tester) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(() => world.database.close());
    final id = (await tester.runAsync(world.buy))!;
    await tester.runAsync(() => world.reverse(id));
    await _pump(tester, world, id);

    final stored = (await tester.runAsync(
      () => world.db.query('purchases', where: 'id=?', whereArgs: [id]),
    ))!.single;
    final payment = (await tester.runAsync(
      () => world.db.query('provider_payments'),
    ))!.single;
    expect(find.text('Revertida'), findsOneWidget);
    expect(
      _shows(tester, 'Revertida el: ${formatDate(stored['reversed_at'])}'),
      isTrue,
    );
    final actor = tester.widget<Text>(
      find.byKey(Key('reversal-actor-PURCHASE-$id')),
    );
    expect(actor.data, contains('Autorizada por el titular'));
    expect(actor.data, contains(_reason));
    expect(_shows(tester, 'Pagado y no revertido: ${formatBob(0)}'), isTrue);
    expect(
      find.text(
        '06/01/2026 · Efectivo · pagó Titular · ${formatBob(10000).trim()} '
        '(revertido el ${formatDate(payment['reversed_at'])})',
      ),
      findsOneWidget,
    );
  });

  testWidgets('consultar el detalle, volver a construirlo y abrir otro no '
      'escribe nada', (tester) async {
    final world = _World();
    await tester.runAsync(world.seed);
    addTearDown(() => world.database.close());
    final confirmed = (await tester.runAsync(world.buy))!;
    final reversed = (await tester.runAsync(world.buy))!;
    await tester.runAsync(() => world.reverse(reversed));
    final before = (await tester.runAsync(() => dumpTables(world.db)))!;

    await _pump(tester, world, confirmed);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, world, reversed);
    await _pump(tester, world, 9999);
    expect(find.text('Esta compra ya no está en el teléfono.'), findsOneWidget);

    final after = (await tester.runAsync(() => dumpTables(world.db)))!;
    expect(after, before);
  });

  for (final (width, scale) in [(320.0, 1.0), (360.0, 1.3), (360.0, 2.0)]) {
    testWidgets('a $width dp con letra ×$scale cabe sin desbordar ni recortar '
        'el texto', (tester) async {
      final world = _World();
      await tester.runAsync(world.seed);
      addTearDown(() => world.database.close());
      final id = (await tester.runAsync(world.buy))!;
      await tester.runAsync(() => world.reverse(id));
      await _pump(tester, world, id, width: width, textScale: scale);

      expect(tester.takeException(), isNull);
      // El texto no se reduce para caber: ninguna línea lleva elipsis ni
      // `FittedBox`, y la escala pedida llega intacta al texto.
      expect(find.byType(FittedBox), findsNothing);
      // Los iconos se dibujan con `RichText` sin escala: no son texto.
      final icons = find.descendant(
        of: find.byType(Icon),
        matching: find.byType(RichText),
      );
      final iconTexts = tester.widgetList<RichText>(icons).toSet();
      for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
        if (iconTexts.contains(text)) continue;
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(text.textScaler, TextScaler.linear(scale));
      }
    });
  }
}
