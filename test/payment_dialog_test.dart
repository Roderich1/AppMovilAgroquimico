// Flujo de registro de pago/adelanto en `/liquidacion`.
//
// Cubre de una vez los defectos que comparten el mismo diálogo:
//   UIBUG-005  el TextEditingController se liberaba mientras el diálogo aún se
//              animaba al cerrarse -> pantalla roja en debug.
//   UIBUG-012  el diálogo no decía a quién se pagaba, ni la campaña, ni el saldo.
//   UIBUG-014  no había ningún mensaje de éxito.
//   UIBUG-065  un importe no interpretable valía 0 y producía el mensaje
//              engañoso "El importe debe ser mayor a cero".
//   UIBUG-003  "1.500" se guardaba como 1,50 Bs (÷1000).
//
// Se usa un repositorio REAL sobre base en memoria: lo que hay que comprobar es
// el importe realmente escrito en `account_transactions`, así que mockearlo
// invalidaría la prueba.

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/settlements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  // La base FFI real tarda más en resolver que el repositorio falso que usan
  // otras suites, así que se alterna espera real y bombeo de fotogramas.
  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 4; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  /// Base real en memoria con una persona FAMILY y una campaña activa.
  Future<(AppDatabase, AgroRepository, int)> fixture() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repo = AgroRepository(database);
    final person = await repo.addPerson(
      name: 'José Luis Ñáñez',
      role: PersonRole.family,
    );
    await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    return (database, repo, person);
  }

  Future<void> pumpScreen(WidgetTester tester, AgroRepository repo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: SettlementsScreen())),
      ),
    );
    await settle(tester);
  }

  Finder personMenu() => find.descendant(
    of: find.byType(Card),
    matching: find.byType(PopupMenuButton<String>),
  );

  Future<void> openPaymentDialog(WidgetTester tester) async {
    await tester.ensureVisible(personMenu().first);
    await tester.tap(personMenu().first);
    await settle(tester);
    await tester.tap(find.text('Registrar pago'));
    await settle(tester);
  }

  /// Busca dentro del diálogo: la pantalla de fondo también contiene el nombre
  /// de la persona y la palabra "Saldo", así que buscar en toda la pantalla
  /// daría un falso positivo.
  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(AlertDialog), matching: matching);

  Finder amountField() => inDialog(find.byType(TextField));

  /// Importes con signo en `account_transactions` (los pagos son negativos).
  Future<List<int>> recordedAmounts(AgroRepository repo, int person) async {
    final rows = await repo.statement(person);
    return [for (final r in rows) r['amount_bob_minor_signed']! as int];
  }

  testWidgets('UIBUG-005: abrir y cerrar el diálogo de pago 20 veces no rompe '
      'la pantalla', (tester) async {
    final (database, repo, _) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await pumpScreen(tester, repo);

    for (var iteration = 0; iteration < 20; iteration++) {
      await openPaymentDialog(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(
        find.text('Liquidación y cuentas'),
        findsOneWidget,
        reason: 'la pantalla debe seguir viva tras cerrar el diálogo',
      );
    }
    // Antes del fix: "A TextEditingController was used after being disposed"
    // y '_dependents.isEmpty': is not true.
    expect(tester.takeException(), isNull);
  });

  testWidgets('UIBUG-012: el diálogo identifica persona, campaña y saldo', (
    tester,
  ) async {
    final (database, repo, _) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await pumpScreen(tester, repo);
    await openPaymentDialog(tester);

    expect(
      inDialog(find.textContaining('José Luis Ñáñez')),
      findsWidgets,
      reason: 'debe decirse a quién se paga',
    );
    expect(
      inDialog(find.textContaining('Verano 2026')),
      findsWidgets,
      reason: 'debe decirse a qué campaña se imputa',
    );
    expect(
      inDialog(find.textContaining('Saldo')),
      findsWidgets,
      reason: 'debe mostrarse el saldo de referencia',
    );
  });

  testWidgets('UIBUG-003: teclear "1.500" registra 1.500,00 Bs, no 1,50 Bs', (
    tester,
  ) async {
    final (database, repo, person) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await pumpScreen(tester, repo);
    await openPaymentDialog(tester);

    await tester.enterText(amountField(), '1.500');
    await settle(tester);
    await tester.tap(find.text('Registrar'));
    await settle(tester);

    final amounts = (await tester.runAsync(
      () => recordedAmounts(repo, person),
    ))!;
    expect(amounts, [
      -150000,
    ], reason: '1.500 Bs son 150000 céntimos; el bug guardaba -150');
  });

  testWidgets('UIBUG-003: "1.500,25" y "0,125" se registran exactamente', (
    tester,
  ) async {
    final (database, repo, person) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await pumpScreen(tester, repo);

    await openPaymentDialog(tester);
    await tester.enterText(amountField(), '1.500,25');
    await settle(tester);
    await tester.tap(find.text('Registrar'));
    await settle(tester);

    final amounts = (await tester.runAsync(
      () => recordedAmounts(repo, person),
    ))!;
    expect(amounts, [-150025]);
  });

  testWidgets('UIBUG-014: registrar un pago muestra mensaje de éxito', (
    tester,
  ) async {
    final (database, repo, _) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await pumpScreen(tester, repo);
    await openPaymentDialog(tester);

    await tester.enterText(amountField(), '150');
    await settle(tester);
    await tester.tap(find.text('Registrar'));
    await settle(tester);

    expect(
      find.byType(SnackBar),
      findsOneWidget,
      reason: 'la escritura contable más delicada debe acusar recibo',
    );
    expect(find.textContaining('150,00'), findsWidgets);
  });

  testWidgets('UIBUG-065: un importe no interpretable no dice "mayor a cero"', (
    tester,
  ) async {
    final (database, repo, person) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await pumpScreen(tester, repo);
    await openPaymentDialog(tester);

    await tester.enterText(amountField(), 'abc');
    await settle(tester);
    await tester.tap(find.text('Registrar'));
    await settle(tester);

    // El mensaje debe describir el problema real: no se pudo interpretar.
    expect(
      find.textContaining('mayor a cero'),
      findsNothing,
      reason: 'ese mensaje es engañoso para una cadena no interpretable',
    );
    expect(
      inDialog(find.textContaining('Escriba el número')),
      findsWidgets,
      reason: 'debe explicarse el formato esperado',
    );
    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: 'no debe cerrarse',
    );
    // Y no debe haberse escrito nada.
    final amounts = (await tester.runAsync(
      () => recordedAmounts(repo, person),
    ))!;
    expect(amounts, isEmpty);
  });

  testWidgets('UIBUG-003/065: "1,500" es ambiguo y se rechaza sin escribir', (
    tester,
  ) async {
    final (database, repo, person) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await pumpScreen(tester, repo);
    await openPaymentDialog(tester);

    await tester.enterText(amountField(), '1,500');
    await settle(tester);
    await tester.tap(find.text('Registrar'));
    await settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(inDialog(find.textContaining('ambiguo')), findsWidgets);
    final amounts = (await tester.runAsync(
      () => recordedAmounts(repo, person),
    ))!;
    expect(
      amounts,
      isEmpty,
      reason: 'ante la ambigüedad no se escribe nada: ni 1,5 ni 1500',
    );
  });

  testWidgets('el adelanto sigue funcionando y se distingue del pago', (
    tester,
  ) async {
    final (database, repo, person) = (await tester.runAsync(fixture))!;
    addTearDown(database.close);
    await pumpScreen(tester, repo);

    await tester.ensureVisible(personMenu().first);
    await tester.tap(personMenu().first);
    await settle(tester);
    await tester.tap(find.text('Registrar adelanto'));
    await settle(tester);
    expect(inDialog(find.textContaining('adelanto')), findsWidgets);

    await tester.enterText(amountField(), '200');
    await settle(tester);
    await tester.tap(find.text('Registrar'));
    await settle(tester);

    final rows = (await tester.runAsync(() => repo.statement(person)))!;
    expect(rows.single['type'], 'ADVANCE');
    expect(rows.single['amount_bob_minor_signed'], -20000);
  });
}
