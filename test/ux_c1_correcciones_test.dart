// Bloque de correcciones de experiencia (2026-10-30), cuatro defectos:
//   A1  Cuentas ofrecía «Registrar pago» y «Registrar adelanto», dos accesos con
//       la misma mecánica (RN-39). Queda un único «Registrar pago». Los
//       adelantos ya guardados se siguen leyendo como «Adelanto».
//   A2  La tarjeta de una compra no se podía tocar: no había detalle.
//   A3  Tras revertir una transferencia, el texto del actor iba en el lateral
//       de la fila y estrechaba el título y el resumen.
//   A4  El importe del pago traía el ejemplo «1.500,25», que parecía un valor
//       ya escrito.
//
// Repositorio REAL sobre base en memoria: lo que importa es lo que se escribe
// (o que no se escribe nada al consultar).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/labels.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/purchases_screen.dart';
import 'package:agroquimicos/presentation/screens/settlements_screen.dart';
import 'package:agroquimicos/presentation/screens/transfers_screen.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

/// Motivo largo y realista: es lo que alarga el texto del actor.
const _reason =
    'Se eligió a la persona equivocada en la lista al registrar la entrega';

class _World {
  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late TestOwnerPin pin;
  late OwnerBindingContext binding;
  late int titular, hermana, supplier, campaign, glifosato;

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
    hermana = await repo.addPerson(
      name: 'María Fernanda Quispe Mamani',
      role: PersonRole.family,
    );
    supplier = await repo.addSupplier(name: 'Agroquímicos del Valle');
    campaign = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato Demo');
  }

  Future<int> buy({int quantity = 4000, int? person}) => repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: campaign,
      purchaseDate: DateTime.utc(2026, 1, 5, 12),
      invoiceNumber: 'F-1029',
      items: [
        PurchaseItemDraft(
          productId: glifosato,
          quantityBase: quantity,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 4500,
          allocations: [
            AllocationDraft(
              personId: person ?? titular,
              quantityBase: quantity,
            ),
          ],
        ),
      ],
    ),
  );

  Future<OwnerAuthorization> authorize(
    AuthorizationPurpose purpose,
    String subjectRef,
  ) => pin.credential.verify(
    pin: '284917',
    purpose: purpose,
    subjectRef: subjectRef,
    binding: binding,
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

/// Teléfono estrecho: 360 dp de ancho (y, si se pide, letra ampliada).
void _narrow(WidgetTester tester, {double width = 360, double height = 1600}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<Override> _overrides(_World world) => [
  repositoryProvider.overrideWithValue(world.repo),
  activatedInstallationForTests(),
  localOwnerCredentialProvider.overrideWithValue(world.pin.credential),
];

Future<void> _pumpHome(
  WidgetTester tester,
  _World world,
  Widget home, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(world),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: home),
      ),
    ),
  );
  await _settle(tester);
}

Finder _inDialog(Finder matching) =>
    find.descendant(of: find.byType(AlertDialog), matching: matching);

void main() {
  sqfliteFfiInit();

  group('A1 · Cuentas: un único «Registrar pago»', () {
    Future<List<String>> menuOf(WidgetTester tester, Finder card) async {
      final menu = find.descendant(
        of: card,
        matching: find.byType(PopupMenuButton<String>),
      );
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await _settle(tester, rounds: 2);
      final labels = [
        for (final item in tester.widgetList<PopupMenuItem<String>>(
          find.byType(PopupMenuItem<String>),
        ))
          if (item.child is Text) (item.child! as Text).data!,
      ];
      await tester.tapAt(const Offset(5, 5));
      await _settle(tester, rounds: 2);
      return labels;
    }

    testWidgets('la tarjeta de una persona y la del titular ofrecen sólo '
        '«Registrar pago»', (tester) async {
      final world = _World();
      await tester.runAsync(world.seed);
      addTearDown(() => world.database.close());
      _narrow(tester, width: 500);
      await _pumpHome(tester, world, const SettlementsScreen());

      final person = find.ancestor(
        of: find.text('María Fernanda Quispe Mamani'),
        matching: find.byType(Card),
      );
      final own = find.byKey(const Key('own-consumption-card'));
      for (final card in [person, own]) {
        final labels = await menuOf(tester, card);
        expect(labels, contains('Registrar pago'));
        expect(labels, isNot(contains('Registrar adelanto')));
      }
    });

    testWidgets('registrar desde Cuentas escribe un PAYMENT, y un adelanto '
        'histórico se sigue leyendo como «Adelanto»', (tester) async {
      final world = _World();
      await tester.runAsync(world.seed);
      addTearDown(() => world.database.close());
      // Adelanto guardado antes de este cambio (sin deuda: queda a favor).
      await tester.runAsync(
        () => world.repo.registerAccountPayment(
          personId: world.hermana,
          campaignId: world.campaign,
          amountBobMinor: 5000,
          advance: true,
        ),
      );
      _narrow(tester, width: 500);
      await _pumpHome(tester, world, const SettlementsScreen());

      final card = find.ancestor(
        of: find.text('María Fernanda Quispe Mamani'),
        matching: find.byType(Card),
      );
      final menu = find.descendant(
        of: card,
        matching: find.byType(PopupMenuButton<String>),
      );
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await _settle(tester, rounds: 2);
      await tester.tap(find.text('Registrar pago'));
      await _settle(tester, rounds: 2);
      await tester.enterText(_inDialog(find.byType(TextField)), '20');
      await tester.tap(_inDialog(find.text('Registrar')));
      await _settle(tester);

      final rows = (await tester.runAsync(
        () => world.db.query(
          'account_transactions',
          columns: ['type', 'reference_type', 'amount_bob_minor_signed'],
          orderBy: 'id',
        ),
      ))!;
      expect(rows, [
        {
          'type': 'ADVANCE',
          'reference_type': 'ADVANCE',
          'amount_bob_minor_signed': -5000,
        },
        {
          'type': 'PAYMENT',
          'reference_type': 'PAYMENT',
          'amount_bob_minor_signed': -2000,
        },
      ]);

      // El detalle cronológico rotula cada asiento con `transactionTypeLabel`
      // (sus filas se construyen al desplazarse): el adelanto histórico sigue
      // siendo «Adelanto».
      final statement = (await tester.runAsync(
        () => world.repo.statement(world.hermana),
      ))!;
      expect(
        [for (final row in statement) transactionTypeLabel(row['type'])],
        ['Adelanto', 'Pago'],
      );
    });
  });

  group('A1 · RN-39: PAYMENT y ADVANCE tienen la misma mecánica', () {
    /// Escribe, en una base nueva, un cargo de un tercero (cobro por compra)
    /// y un pago de 30 Bs del [type] dado; devuelve todo lo que cambia.
    Future<Map<String, Object?>> record({required bool advance}) async {
      // Una base en memoria por llamada: se cierra antes de abrir la otra
      // (comparten la ruta `:memory:`).
      final world = _World();
      await world.seed();
      try {
        final tercero = await world.repo.addPerson(
          name: 'Vecino',
          role: PersonRole.thirdParty,
        );
        await world.buy(person: tercero);
        final result = await world.repo.registerAccountPayment(
          personId: tercero,
          campaignId: world.campaign,
          amountBobMinor: 3000,
          advance: advance,
        );
        final ledger = await world.repo.accountLedger(withDetails: false);
        return {
          'allocations': await world.db.query(
            'payment_allocations',
            columns: ['charge_transaction_id', 'amount_bob_minor'],
          ),
          'imputed': result.imputed,
          'unapplied': result.unappliedMinor,
          'net': ledger.account(tercero).netMinor,
          'received': ledger.receivedMinor(),
          'pending': ledger.pendingForCampaign(world.campaign),
        };
      } finally {
        await world.database.close();
      }
    }

    test(
      'mismas imputaciones, saldos y totales; sólo cambia el tipo',
      () async {
        final payment = await record(advance: false);
        final advance = await record(advance: true);
        expect(advance, payment);
        expect(payment['allocations'], isNotEmpty);
      },
    );
  });

  group('A4 · Importe del pago', () {
    testWidgets('campo vacío, sin «1.500,25», etiqueta clara y moneda Bs', (
      tester,
    ) async {
      final world = _World();
      await tester.runAsync(world.seed);
      addTearDown(() => world.database.close());
      _narrow(tester, width: 500);
      await _pumpHome(tester, world, const SettlementsScreen());

      final card = find.ancestor(
        of: find.text('María Fernanda Quispe Mamani'),
        matching: find.byType(Card),
      );
      final menu = find.descendant(
        of: card,
        matching: find.byType(PopupMenuButton<String>),
      );
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await _settle(tester, rounds: 2);
      await tester.tap(find.text('Registrar pago'));
      await _settle(tester, rounds: 2);

      final field = tester.widget<TextField>(_inDialog(find.byType(TextField)));
      expect(field.controller!.text, isEmpty);
      expect(field.decoration!.hintText, isNull);
      expect(field.decoration!.labelText, 'Importe del pago');
      expect(field.decoration!.suffixText, 'Bs');
      expect(find.textContaining('1.500,25'), findsNothing);

      // La validación numérica se conserva: «1,500» es ambiguo y no se guarda.
      await tester.enterText(_inDialog(find.byType(TextField)), '1,500');
      await tester.tap(_inDialog(find.text('Registrar')));
      await _settle(tester, rounds: 2);
      expect(find.byType(AlertDialog), findsOneWidget);
      final rows = (await tester.runAsync(
        () => world.db.query('account_transactions'),
      ))!;
      expect(rows, isEmpty);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('con el teclado abierto en 360×640 y letra ×$scale el '
          'diálogo no se desborda y «Registrar» sigue a la vista', (
        tester,
      ) async {
        final world = _World();
        await tester.runAsync(world.seed);
        addTearDown(() => world.database.close());
        _narrow(tester, height: 640);
        await _pumpHome(
          tester,
          world,
          const SettlementsScreen(),
          textScale: scale,
        );
        final card = find.ancestor(
          of: find.text('María Fernanda Quispe Mamani'),
          matching: find.byType(Card),
        );
        final menu = find.descendant(
          of: card,
          matching: find.byType(PopupMenuButton<String>),
        );
        // Pantalla baja: la tarjeta queda bajo el pliegue y hay que desplazarse.
        await tester.scrollUntilVisible(
          menu,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester, rounds: 1);
        await tester.tap(menu);
        await _settle(tester, rounds: 2);
        await tester.tap(find.text('Registrar pago'));
        await _settle(tester, rounds: 2);

        // Teclado numérico abierto: 300 dp de la parte inferior.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.enterText(_inDialog(find.byType(TextField)), '1,500');
        await tester.ensureVisible(_inDialog(find.text('Registrar')));
        await tester.tap(_inDialog(find.text('Registrar')));
        await _settle(tester, rounds: 2);

        expect(tester.takeException(), isNull);
        // El error de formato (varias líneas) se ve entero, sin recorte.
        expect(_inDialog(find.textContaining('ambiguo')), findsWidgets);
        final button = tester.getRect(_inDialog(find.text('Registrar')));
        expect(button.bottom, lessThanOrEqualTo(640 - 300));
      });
    }
  });

  group('A2 · Compras: la tarjeta abre el detalle', () {
    testWidgets('tocar una compra confirmada o revertida abre su detalle y '
        'no escribe nada', (tester) async {
      final world = _World();
      await tester.runAsync(world.seed);
      addTearDown(() => world.database.close());
      final confirmed = (await tester.runAsync(() => world.buy()))!;
      final reversed = (await tester.runAsync(
        () => world.buy(quantity: 1000),
      ))!;
      await tester.runAsync(
        () async => world.repo.reversePurchase(
          reversed,
          reason: _reason,
          authorization: await world.authorize(
            AuthorizationPurpose.reversePurchase,
            'purchase:$reversed',
          ),
        ),
      );
      final before = (await tester.runAsync(() => dumpTables(world.db)))!;

      final opened = <String>[];
      final router = GoRouter(
        initialLocation: '/compras',
        routes: [
          GoRoute(
            path: '/compras',
            builder: (_, __) => const Scaffold(body: PurchasesScreen()),
          ),
          GoRoute(
            path: '/compras/detalle/:id',
            builder: (_, state) {
              opened.add(state.pathParameters['id']!);
              return const Scaffold(body: Text('detalle'));
            },
          ),
        ],
      );
      _narrow(tester, width: 500);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(world),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await _settle(tester);

      final cards = find.ancestor(
        of: find.textContaining('Agroquímicos del Valle'),
        matching: find.byType(Card),
      );
      expect(cards, findsNWidgets(2));
      for (final card in tester.widgetList<Card>(cards).toList()) {
        await tester.tap(find.byWidget(card));
        await _settle(tester, rounds: 3);
        router.pop();
        await _settle(tester, rounds: 3);
      }
      expect(opened.toSet(), {'$confirmed', '$reversed'});
      final after = (await tester.runAsync(() => dumpTables(world.db)))!;
      expect(after, before, reason: 'consultar no escribe nada');
    });
  });

  group('A3 · Transferencias revertidas en pantalla estrecha', () {
    Future<int> reversedTransfer(_World world) async {
      await world.buy();
      final id = await world.repo.transferProductsFifo(
        fromPersonId: world.titular,
        toPersonId: world.hermana,
        items: [
          TransferItemDraft(productId: world.glifosato, quantityBase: 1000),
        ],
        date: DateTime.utc(2026, 1, 10, 12),
      );
      await world.repo.reverseTransfer(
        id,
        reason: _reason,
        authorization: await world.authorize(
          AuthorizationPurpose.reverseTransfer,
          'transfer:$id',
        ),
      );
      return id;
    }

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('a 360 dp y letra ×$scale el actor ocupa el ancho de la '
          'fila y el título no se estrecha', (tester) async {
        final world = _World();
        await tester.runAsync(world.seed);
        addTearDown(() => world.database.close());
        final id = (await tester.runAsync(() => reversedTransfer(world)))!;
        _narrow(tester, height: 2400);
        await _pumpHome(
          tester,
          world,
          const TransfersScreen(),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);

        final actor = find.byKey(Key('reversal-actor-TRANSFER-$id'));
        expect(actor, findsOneWidget);
        // Se conserva la auditoría completa: quién, cómo y el motivo.
        final text = tester.widget<Text>(actor).data!;
        expect(text, contains('Autorizada por el titular'));
        expect(text, contains(_reason));

        // El texto del actor no va en el lateral: usa el ancho de la fila
        // salvo el icono inicial y la flecha de desplegar (≈ 128 dp de 328).
        final card = tester.getRect(find.byType(Card));
        final actorRect = tester.getRect(actor);
        expect(actorRect.width, greaterThan(card.width * 0.55));
        // El título conserva el ancho de la fila (no se parte en columnas
        // de pocas letras).
        final title = find.text('Titular → María Fernanda Quispe Mamani');
        expect(tester.getRect(title).width, greaterThan(card.width * 0.5));
        expect(find.text('Revertida'), findsOneWidget);
      });
    }
  });
}
