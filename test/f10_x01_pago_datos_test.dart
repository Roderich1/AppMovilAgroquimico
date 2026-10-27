// Datos del pago al proveedor (ajuste del 2026-10-26, previo al merge de las
// correcciones X01): «¿Pagaste toda esta compra?» sólo dice que se pagó el
// total. El medio y la fecha no se suponen: el medio empieza en «Sin indicar»
// (explícito, `UNSPECIFIED`) y la fecha en el día de la compra; los dos se ven
// y se corrigen antes de confirmar. El pago posterior desde Compras muestra
// los mismos campos (día: hoy). El repositorio rechaza fechas de pago futuras
// (un anticipo anterior a la compra sí se admite: el contrato no lo prohíbe),
// y compra y pago siguen en una transacción.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/es_material_labels.dart';
import 'support/f04_mode_ui_harness.dart';

typedef Row = Map<String, Object?>;

void main() {
  sqfliteFfiInit();

  group('PaymentMethod', () {
    test('códigos guardados y vuelta', () {
      expect(PaymentMethod.cash.code, 'CASH');
      expect(PaymentMethod.transfer.code, 'TRANSFER');
      expect(PaymentMethod.unspecified.code, 'UNSPECIFIED');
      for (final method in PaymentMethod.values) {
        expect(PaymentMethod.fromCode(method.code), method);
      }
      expect(PaymentMethod.fromCode('CHEQUE'), isNull);
      expect(PaymentMethod.unspecified.label, 'Sin indicar');
    });
  });

  group('repositorio', () {
    late AppDatabase database;
    late Household household;

    setUp(() async {
      database = openDb(inMemoryDatabasePath);
      final repo = AgroRepository(database);
      household = await seedHousehold(repo);
      await OwnerBindingStore(database).bindExistingPerson(
        personId: household.titular,
        scope: memberA,
        installationRef: installationHere,
      );
      await OperationModeStore(database)
          .apply(OperationMode.shared, confirmed: true);
    });

    PurchaseDraft draft(DateTime purchaseDate) => PurchaseDraft(
      supplierId: household.supplier,
      campaignId: household.campaign,
      purchaseDate: purchaseDate,
      items: [
        PurchaseItemDraft(
          productId: household.product,
          quantityBase: 1000,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 4500,
          allocations: [
            AllocationDraft(personId: household.titular, quantityBase: 1000),
          ],
        ),
      ],
    );

    Future<void> rejectedWithoutChanges(
      Future<Object?> Function() call,
      String fragment,
    ) async {
      final db = await database.database;
      final before = await dumpTables(db);
      await expectLater(
        call(),
        throwsA(
          isA<BusinessRuleException>().having(
            (e) => e.message,
            'message',
            contains(fragment),
          ),
        ),
      );
      expect(await dumpTables(db), before);
    }

    Future<List<Row>> payments() async =>
        (await database.database).query('provider_payments', orderBy: 'id');

    test(
      'el medio indicado se guarda tal cual, también «Sin indicar»',
      () async {
        final date = DateTime.utc(2026, 1, 20, 14);
        for (final method in PaymentMethod.values) {
          await household.repo.confirmPurchase(
            draft(date),
            paidInFull: ProviderPaymentDetails(method: method, date: date),
          );
        }
        expect(
          [for (final row in await payments()) row['method']],
          ['CASH', 'TRANSFER', 'UNSPECIFIED'],
        );
        expect([
          for (final row in await payments()) row['payment_date'],
        ], everyElement(date.toIso8601String()));
      },
    );

    test(
      'fecha de pago futura: no se escribe ni la compra ni el pago',
      () async {
        await rejectedWithoutChanges(
          () => household.repo.confirmPurchase(
            draft(DateTime.utc(2026, 1, 20, 14)),
            paidInFull: ProviderPaymentDetails(
              method: PaymentMethod.cash,
              date: DateTime.now().add(const Duration(days: 2)),
            ),
          ),
          'posterior a hoy',
        );
      },
    );

    test(
      'fecha de pago anterior a la compra (anticipo): se admite tal cual; el '
      'contrato no la prohíbe',
      () async {
        final date = DateTime.utc(2026, 1, 10, 14);
        await household.repo.confirmPurchase(
          draft(DateTime.utc(2026, 1, 20, 14)),
          paidInFull: ProviderPaymentDetails(
            method: PaymentMethod.cash,
            date: date,
          ),
        );
        final row = (await payments()).single;
        expect(row['payment_date'], date.toIso8601String());
        expect(row['method'], 'CASH');
      },
    );

    test('pago posterior: no futuro; el medio y la fecha se guardan', () async {
      final purchase = await household.buy(
        household.titular,
        1000,
        date: DateTime.utc(2026, 1, 20, 14),
      );
      await rejectedWithoutChanges(
        () => household.repo.addProviderPayment(
          purchaseId: purchase,
          payerPersonId: household.titular,
          amountBobMinor: 1000,
          method: PaymentMethod.transfer,
          date: DateTime.now().add(const Duration(days: 1)),
        ),
        'posterior a hoy',
      );
      await household.repo.addProviderPayment(
        purchaseId: purchase,
        payerPersonId: household.titular,
        amountBobMinor: 1000,
        method: PaymentMethod.transfer,
        date: DateTime.now(),
      );
      final row = (await payments()).single;
      expect(row['method'], 'TRANSFER');
      expect(
        storedLocalDay(row['payment_date']! as String),
        localDay(DateTime.now()),
      );
    });
  });

  group('pantallas', () {
    Finder picker(String label) => find.byWidgetPredicate(
      (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
    );

    Future<void> choose(WidgetTester tester, String label, String name) async {
      final widget = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
      widget.onChanged(
        widget.items.firstWhere((item) => widget.labelOf(item) == name),
      );
      await settle(tester);
    }

    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pump();
      await tester.tap(find.byKey(Key(key)));
      await settle(tester);
    }

    Future<List<Row>> rows(WidgetTester tester, db, String table) async =>
        (await tester.runAsync(
          () async => (await db.database).query(table, orderBy: 'id'),
        ))!;

    /// Paso 1 en compartida: Glifosato 2 L a 45, todo al titular.
    Future<void> fillStep1(WidgetTester tester) async {
      await choose(tester, 'Proveedor', 'Proveedor');
      await choose(tester, 'Producto', 'Glifosato');
      await tester.enterText(field('Cantidad comprada'), '2');
      await tester.enterText(field('Precio BOB/L'), '45');
      await choose(tester, 'Persona', 'Titular');
      await tester.enterText(field('Cantidad'), '2');
      await settle(tester);
      await tapKey(tester, 'purchase-continue');
    }

    bool chipSelected(WidgetTester tester, String key) =>
        tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

    /// Texto dentro de la fila «Fecha del pago»: la revisión muestra aparte
    /// la fecha de la compra, también con «(hoy)».
    Finder inPaymentRow(String text) => find.descendant(
      of: find.byKey(const Key('payment-date')),
      matching: find.text(text),
    );

    /// Elige en el selector de fecha abierto el día [day] y acepta.
    Future<void> pickDayInDialog(WidgetTester tester, int day) async {
      final es = await esMaterial();
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('$day'),
        ),
      );
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text(es.okButtonLabel),
        ),
      );
      await settle(tester);
    }

    testWidgets(
      'compra de hoy, «Sí, pagué todo» sin tocar nada más: medio «Sin '
      'indicar» (visible) y fecha de hoy (visible); así se guarda',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 2800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final s = await activatedHousehold(tester, 'pago-hoy');
        final c = await pumpModeApp(tester, s.database);
        c.read(routerProvider).push('/compras/nueva');
        await waitFor(tester, field('Cantidad comprada'));
        await settle(tester);
        await fillStep1(tester);
        // Antes de responder no hay campos del pago.
        expect(find.byKey(const Key('payment-method')), findsNothing);
        await tester.tap(find.byKey(const Key('purchase-paid-yes')));
        await settle(tester);
        expect(find.text('Pago registrado por: Titular'), findsOneWidget);
        expect(find.text('¿Cómo pagaste?'), findsOneWidget);
        expect(chipSelected(tester, 'payment-method-unspecified'), isTrue);
        expect(chipSelected(tester, 'payment-method-cash'), isFalse);
        expect(chipSelected(tester, 'payment-method-transfer'), isFalse);
        final today = localDay(DateTime.now());
        expect(find.text('Fecha del pago'), findsOneWidget);
        expect(inPaymentRow('${displayDay(today)} (hoy)'), findsOneWidget);
        await tapKey(tester, 'purchase-confirm');
        // Al guardarse, el formulario se cierra (el aviso lo da Inicio).
        expect(find.byKey(const Key('purchase-confirm')), findsNothing);
        final payment = (await rows(
          tester,
          s.database,
          'provider_payments',
        )).single;
        expect(payment['method'], 'UNSPECIFIED');
        expect(payment['amount_bob_minor'], 9000);
        expect(storedLocalDay(payment['payment_date']! as String), today);
        final purchase = (await rows(tester, s.database, 'purchases')).single;
        expect(payment['purchase_id'], purchase['id']);
      },
    );

    testWidgets(
      'compra de un día anterior: la fecha del pago empieza en el día de la '
      'compra y se ve así; medio y fecha se corrigen y se guardan',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 2800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final s = await activatedHousehold(tester, 'pago-otro-dia');
        final c = await pumpModeApp(tester, s.database);
        c.read(routerProvider).push('/compras/nueva');
        await waitFor(tester, field('Cantidad comprada'));
        await settle(tester);
        // Compra del día 1 del mes en curso (o del anterior si hoy es 1):
        // dentro de «Campaña 1», que empieza el 2026-01-01 y sigue abierta.
        await tapKey(tester, 'purchase-date');
        final now = DateTime.now();
        if (now.day == 1) {
          await tester.tap(
            find.descendant(
              of: find.byType(DatePickerDialog),
              matching: find.byTooltip(
                (await esMaterial()).previousMonthTooltip,
              ),
            ),
          );
          await settle(tester);
        }
        await pickDayInDialog(tester, 1);
        final purchaseDay = now.day == 1
            ? localDay(DateTime(now.year, now.month - 1, 1))
            : localDay(DateTime(now.year, now.month, 1));
        await fillStep1(tester);
        await tester.tap(find.byKey(const Key('purchase-paid-yes')));
        await settle(tester);
        expect(
          inPaymentRow('${displayDay(purchaseDay)} (el día de la compra)'),
          findsOneWidget,
        );
        expect(chipSelected(tester, 'payment-method-unspecified'), isTrue);
        await tapKey(tester, 'payment-method-cash');
        expect(chipSelected(tester, 'payment-method-cash'), isTrue);
        expect(chipSelected(tester, 'payment-method-unspecified'), isFalse);
        // Cambiar la fecha del pago a hoy (el selector va del día de la
        // compra a hoy). Si hoy es 1, la compra ya es del mes anterior y el
        // selector abre en ese mes: se avanza al mes en curso.
        var paymentDay = purchaseDay;
        if (now.day != 1) {
          await tapKey(tester, 'payment-date');
          await pickDayInDialog(tester, now.day);
          paymentDay = localDay(now);
          expect(
            inPaymentRow('${displayDay(paymentDay)} (hoy)'),
            findsOneWidget,
          );
        }
        await tapKey(tester, 'purchase-confirm');
        // Al guardarse, el formulario se cierra (el aviso lo da Inicio).
        expect(find.byKey(const Key('purchase-confirm')), findsNothing);
        final payment = (await rows(
          tester,
          s.database,
          'provider_payments',
        )).single;
        expect(payment['method'], 'CASH');
        expect(storedLocalDay(payment['payment_date']! as String), paymentDay);
        final purchase = (await rows(tester, s.database, 'purchases')).single;
        expect(
          storedLocalDay(purchase['purchase_date']! as String),
          purchaseDay,
        );
      },
    );

    testWidgets(
      'pago posterior desde Compras: medio («Sin indicar» por defecto) y '
      'fecha (hoy) visibles; lo elegido se guarda',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final s = await activatedHousehold(tester, 'pago-posterior-datos');
        final h = s.household;
        final purchase = await tester.runAsync(() => h.buy(h.relative, 1000));
        final c = await pumpModeApp(tester, s.database);
        c.read(routerProvider).go('/compras');
        await waitFor(tester, find.byType(PopupMenuButton<String>));
        await settle(tester);
        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await settle(tester);
        await tester.tap(find.text('Registrar pago'));
        await waitFor(tester, find.byKey(const Key('payment-personal-payer')));
        expect(find.text('¿Cómo pagaste?'), findsOneWidget);
        expect(chipSelected(tester, 'payment-method-unspecified'), isTrue);
        final today = localDay(DateTime.now());
        expect(inPaymentRow('${displayDay(today)} (hoy)'), findsOneWidget);
        await tester.tap(find.byKey(const Key('payment-method-transfer')));
        await settle(tester);
        expect(chipSelected(tester, 'payment-method-transfer'), isTrue);
        await tester.tap(find.text('Registrar'));
        await settle(tester);
        final payment = (await rows(
          tester,
          s.database,
          'provider_payments',
        )).single;
        expect(payment['purchase_id'], purchase);
        expect(payment['payer_person_id'], h.titular);
        expect(payment['method'], 'TRANSFER');
        expect(storedLocalDay(payment['payment_date']! as String), today);
      },
    );
  });
}
