// Hallazgos F-1 y F-2 de la comprobación de C1 en el emulador (2026-10-30,
// `docs/evidence/F10_UX_C1_EMULADOR_2026-10-30.md` §5):
//   F-1  En el diálogo «Estado de cuenta» de un teléfono (411 dp) las filas
//        del cronológico se partían por carácter («Adelant / o»): el importe
//        ocupaba 140 px fijos y al concepto le quedaban ~55 px.
//   F-2  En la tarjeta de Cuentas el nombre de la persona se recortaba con
//        puntos suspensivos («Don Carlos Gutiérrez Villarr…») mientras el
//        importe conservaba su columna, y el importe se reducía de tamaño.
//
// Las pruebas reproducen ambos fallos sobre el código anterior y comprueban la
// corrección: en teléfono el cronológico usa una distribución vertical y la
// tarjeta reorganiza nombre e importe; nada se encoge ni se recorta. Los
// importes, signos, fechas, tipos históricos e imputaciones se comparan con lo
// guardado (repositorio REAL sobre base en memoria).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/settlements_screen.dart';
import 'package:agroquimicos/presentation/widgets/account_statement_view.dart';
import 'package:agroquimicos/services/auth/local_owner_credential.dart';
import 'package:agroquimicos/services/auth/local_owner_credential_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_owner_pin.dart';

const _longName = 'Don Carlos Gutiérrez Villarroel';

class _World {
  late AppDatabase database;
  late AgroRepository repo;
  late Database db;
  late TestOwnerPin pin;
  late int titular, carlos, supplier, campaign, glifosato;

  Future<void> seed() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final bound = await seedActivatedInstallation(database);
    repo = AgroRepository(database, ownerCredential: () => pin.credential);
    db = await database.database;
    titular = bound.personId;
    pin = await TestOwnerPin.enrolled(
      OwnerBindingContext(
        bindingId: bound.id,
        personId: bound.personId,
        scope: memberA,
      ),
    );
    // Tercero: el cargo nace con la compra (RN-37), así el cronológico tiene
    // un cargo y un adelanto desde el principio.
    carlos = await repo.addPerson(name: _longName, role: PersonRole.thirdParty);
    supplier = await repo.addSupplier(name: 'Agroquímicos del Valle');
    campaign = await repo.addCampaign(
      name: 'Verano 2026',
      start: DateTime.utc(2026, 1, 1),
    );
    glifosato = await repo.addProduct(name: 'Glifosato Demo');
  }

  /// Compra con cargo a Don Carlos; [quantity] grande da un importe grande.
  Future<int> buy({required int quantity}) => repo.confirmPurchase(
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
            AllocationDraft(personId: carlos, quantityBase: quantity),
          ],
        ),
      ],
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

void _screen(
  WidgetTester tester, {
  required double width,
  double height = 1600,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<Override> _overrides(_World world) => [
  repositoryProvider.overrideWithValue(world.repo),
  activatedInstallationForTests(),
  localOwnerCredentialProvider.overrideWithValue(world.pin.credential),
];

Future<void> _pumpCuentas(
  WidgetTester tester,
  _World world, {
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
        home: const Scaffold(body: SettlementsScreen()),
      ),
    ),
  );
  await _settle(tester);
}

Finder _card() =>
    find.ancestor(of: find.text(_longName), matching: find.byType(Card)).first;

Finder _inDialog(Finder matching) =>
    find.descendant(of: find.byType(AlertDialog), matching: matching);

Future<void> _openStatement(WidgetTester tester) async {
  final menu = find.descendant(
    of: _card(),
    matching: find.byType(PopupMenuButton<String>),
  );
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await _settle(tester, rounds: 2);
  await tester.tap(find.text('Ver detalle cronológico'));
  await _settle(tester, rounds: 3);
  expect(find.byType(AccountStatementView), findsOneWidget);
}

/// Las filas del cronológico se construyen al desplazarse: lleva [matching] a
/// la vista dentro del diálogo y lo devuelve.
Future<Finder> _row(WidgetTester tester, Finder matching) async {
  final target = _inDialog(matching);
  await tester.scrollUntilVisible(
    target,
    60,
    scrollable: _inDialog(find.byType(Scrollable)).first,
  );
  await _settle(tester, rounds: 1);
  expect(target, findsOneWidget);
  return target;
}

/// Líneas que ocupa un texto tal como se pintó.
int _lines(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder.first);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
  )..layout();
  final one = painter.height;
  painter.dispose();
  return (paragraph.size.height / one).round();
}

/// Líneas que necesitaría el texto completo en el ancho que tiene: si se
/// pintaron menos, está recortado.
int _linesNeeded(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder.first);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  final needed = painter.computeLineMetrics().length;
  painter.dispose();
  return needed;
}

/// Ninguna palabra partida: cada línea termina en un espacio o en el final.
/// Dos comprobaciones: (1) el párrafo dispone de al menos el 40 % del ancho
/// [available] del contenedor (el diálogo o la tarjeta), así una columna
/// estrecha como la de F-1 (~55 px de ~280) se detecta aunque sus cortes sean
/// «inevitables»; (2) sólo se tolera el corte de una palabra que, ella sola,
/// es más ancha que el párrafo (la fuente de las pruebas mide 1 em por glifo,
/// el doble que Roboto; en el EMULADOR se comprueba con la fuente real).
void _expectWholeWords(
  WidgetTester tester,
  Finder finder, {
  required double available,
}) {
  final paragraph = tester.renderObject<RenderParagraph>(finder.first);
  final text = paragraph.text.toPlainText();
  final style = paragraph.text.style;
  expect(
    paragraph.size.width,
    greaterThanOrEqualTo(available * 0.4),
    reason:
        '«$text» tiene ${paragraph.size.width} px de una fila de $available',
  );
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  double wordWidth(String word) {
    final p = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    final width = p.width;
    p.dispose();
    return width;
  }

  var offset = 0;
  while (offset < text.length) {
    final end = painter.getLineBoundary(TextPosition(offset: offset)).end;
    if (end <= offset) {
      offset++;
      continue;
    }
    if (end < text.length &&
        text[end - 1] != ' ' &&
        text[end] != ' ' &&
        text[end] != '\n') {
      final start = text.lastIndexOf(RegExp(r'[ \n]'), end) + 1;
      var stop = text.indexOf(RegExp(r'[ \n]'), end);
      if (stop < 0) stop = text.length;
      final word = text.substring(start, stop);
      expect(
        wordWidth(word),
        greaterThan(paragraph.size.width),
        reason:
            'una línea parte «$word» en «$text» (posición $end) aunque cabía '
            'en ${paragraph.size.width} px',
      );
    }
    offset = end;
  }
  painter.dispose();
}

void main() {
  sqfliteFfiInit();

  group('F-1 · «Estado de cuenta» en teléfono', () {
    for (final (width, scale) in [(411.0, 1.0), (360.0, 1.3), (320.0, 2.0)]) {
      testWidgets(
        'a $width dp y letra ×$scale el concepto, la fecha y el importe se '
        'leen enteros, sin palabras partidas',
        (tester) async {
          final world = _World();
          await tester.runAsync(world.seed);
          addTearDown(() => world.database.close());
          await tester.runAsync(() async {
            await world.buy(quantity: 4000);
            // Adelanto histórico (A1): se sigue leyendo como «Adelanto».
            await world.repo.registerAccountPayment(
              personId: world.carlos,
              campaignId: world.campaign,
              amountBobMinor: 2000,
              advance: true,
            );
          });
          // Alto sobrado: a ×2,0 la tarjeta queda muy abajo y el menú debe
          // poder tocarse sin desplazar la pantalla.
          _screen(tester, width: width, height: 3200);
          await _pumpCuentas(tester, world, textScale: scale);
          await _openStatement(tester);
          double dialogWidth() =>
              tester.getSize(find.byType(AccountStatementView)).width;

          final rows = (await tester.runAsync(
            () => world.db.query(
              'account_transactions',
              columns: ['type', 'amount_bob_minor_signed'],
              orderBy: 'id',
            ),
          ))!;
          final charge = rows[0]['amount_bob_minor_signed']! as int;
          expect(rows[1], {
            'type': 'ADVANCE',
            'amount_bob_minor_signed': -2000,
          });

          // Fila del cargo: fecha y tipo en palabras enteras; importe con
          // signo y acumulado, sin recorte.
          final fecha = await _row(
            tester,
            find.textContaining('05/01/2026 · Cargo'),
          );
          _expectWholeWords(tester, fecha, available: dialogWidth());
          final cargo = await _row(tester, find.text('+${formatBob(charge)}'));
          expect(
            tester.widget<Text>(cargo).overflow,
            isNot(TextOverflow.ellipsis),
          );
          expect(_lines(tester, cargo), _linesNeeded(tester, cargo));
          expect(
            await _row(tester, find.text('Acumulado ${formatBob(charge)}')),
            findsOneWidget,
          );

          // Fila del adelanto histórico: concepto en una sola línea.
          final adelanto = await _row(tester, find.text('Adelanto'));
          _expectWholeWords(tester, adelanto, available: dialogWidth());
          if (scale == 1.0) expect(_lines(tester, adelanto), 1);
          final fechaAdelanto = await _row(
            tester,
            find.textContaining('Adelanto · registrado en Verano 2026'),
          );
          _expectWholeWords(tester, fechaAdelanto, available: dialogWidth());
          final pago = await _row(tester, find.text(formatBob(-2000)));
          expect(
            tester.widget<Text>(pago).overflow,
            isNot(TextOverflow.ellipsis),
          );
          expect(_lines(tester, pago), _linesNeeded(tester, pago));
          expect(
            await _row(
              tester,
              find.text('Acumulado ${formatBob(charge - 2000)}'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('en pantalla ancha el importe conserva su columna lateral', (
      tester,
    ) async {
      final world = _World();
      await tester.runAsync(world.seed);
      addTearDown(() => world.database.close());
      await tester.runAsync(() => world.buy(quantity: 4000));
      _screen(tester, width: 1024, height: 1400);
      await _pumpCuentas(tester, world);
      await _openStatement(tester);
      final acumulado = await _row(tester, find.textContaining('Acumulado'));
      final tile = tester.widget<ListTile>(
        find.ancestor(of: acumulado, matching: find.byType(ListTile)).first,
      );
      expect(tile.trailing, isNotNull);
      expect(_lines(tester, _inDialog(find.textContaining('Cargo'))), 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('F-2 · Tarjeta de persona en Cuentas', () {
    for (final (width, scale) in [(411.0, 1.0), (360.0, 1.3), (320.0, 2.0)]) {
      testWidgets(
        'a $width dp y letra ×$scale el nombre se lee completo y el importe '
        'no se reduce',
        (tester) async {
          final world = _World();
          await tester.runAsync(world.seed);
          addTearDown(() => world.database.close());
          // Cantidad grande: importe de millones.
          await tester.runAsync(() => world.buy(quantity: 30000000));
          _screen(tester, width: width);
          await _pumpCuentas(tester, world, textScale: scale);

          final name = find.descendant(
            of: _card(),
            matching: find.text(_longName),
          );
          expect(name, findsOneWidget);
          final nameWidget = tester.widget<Text>(name);
          expect(nameWidget.overflow, isNot(TextOverflow.ellipsis));
          expect(_lines(tester, name), _linesNeeded(tester, name));
          _expectWholeWords(
            tester,
            name,
            available: tester.getSize(_card()).width,
          );

          final pending = (await tester.runAsync(() async {
            final ledger = await world.repo.accountLedger(withDetails: false);
            return ledger.account(world.carlos).netMinor;
          }))!;
          expect(pending, greaterThan(100000000));
          final amount = find.descendant(
            of: _card(),
            matching: find.text(formatBob(pending)),
          );
          expect(amount, findsOneWidget);
          // Sin `FittedBox`: la letra del importe es la del tema a la escala
          // del sistema, no una reducida para caber.
          expect(
            find.descendant(of: _card(), matching: find.byType(FittedBox)),
            findsNothing,
          );
          final paragraph = tester.renderObject<RenderParagraph>(amount);
          expect(paragraph.textScaler, TextScaler.linear(scale));
          expect(_lines(tester, amount), _linesNeeded(tester, amount));

          // Las acciones siguen en la tarjeta.
          expect(
            find.descendant(
              of: _card(),
              matching: find.byType(PopupMenuButton<String>),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
