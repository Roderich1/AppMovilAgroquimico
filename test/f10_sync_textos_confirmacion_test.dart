// Lenguaje del agricultor en «Sincronización» (bloque X01, ajuste autorizado
// el 2026-10-26): los textos visibles dicen «confirmación» en vez de «ACK».
// El estado real no cambia: la chip lee `lastAcceptedAt` y la fila
// `ackedAt`, como antes. Que no haya confirmación no se presenta como prueba
// de que Central no recibió el envío. Se comprueban las dos variantes (sin y
// con confirmación) y que los textos caben, con la Roboto real, a 360 y
// 392 px de ancho y a escala 1,0 y 1,3: la chip no se trunca (el `Chip` de
// Flutter desvanece el texto sobrante sin lanzar ningún error, así que no
// basta con `takeException`) y la fila no desborda.
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f05_sync_fixtures.dart';

final now = DateTime.utc(2026, 10, 15, 12);

void main() {
  sqfliteFfiInit();

  const widths = [360.0, 392.0];
  const scales = [1.0, 1.3];

  setUpAll(() async {
    // Roboto versionada en test/fonts (como en f10_legibility_97_test): con
    // la fuente de pruebas por defecto cada glifo mide 1 em y la medida no
    // dice nada del teléfono.
    final loader = FontLoader('Roboto');
    for (final name in ['regular', 'medium', 'bold']) {
      final bytes = File('test/fonts/roboto-$name.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 6; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }

  /// Una intención declarada; con [accepted], confirmada por Central.
  Future<SyncFixture> seeded({required bool accepted}) async {
    final f = await seedSyncFixture(
      path: inMemoryDatabasePath,
      clock: () => now,
    );
    await f.needs.declare(
      referenceDate: inCampaign,
      productId: f.litreProductId,
      quantityBase: 1500,
    );
    if (accepted) {
      final entry = (await f.outboxEntries()).single;
      await f.outbox.recordAccepted(
        await f.outbox.markSending(entry),
        '2026-10-15T12:00:00.000Z',
      );
    }
    return f;
  }

  Future<SyncFixture> pump(
    WidgetTester tester, {
    required bool accepted,
    required double width,
    required double scale,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = (await tester.runAsync(() => seeded(accepted: accepted)))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(f.database),
          syncOutboxStoreProvider.overrideWithValue(
            SyncOutboxStore(f.database),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: SyncStatusScreen()),
        ),
      ),
    );
    await settle(tester);
    return f;
  }

  /// Ningún texto visible contiene la sigla «ACK». (Sólo `Text.data`: la
  /// pantalla no usa `Text.rich` ni tooltips con texto.)
  void expectNoAck() {
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('ACK'),
      ),
      findsNothing,
    );
  }

  /// El texto cabe entero: sin truncar ni desvanecer, en una o dos líneas
  /// (la chip admite dos con fuente ampliada) y sin partir ninguna palabra.
  void expectWhole(WidgetTester tester, Finder text, String reason) {
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final plain = paragraph.text.toPlainText();
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plain.length),
    );
    final lines = {for (final box in boxes) box.top.round()};
    expect(paragraph.didExceedMaxLines, isFalse, reason: '$reason: truncado');
    expect(lines.length, lessThanOrEqualTo(2), reason: '$reason: >2 líneas');
    expect(
      paragraph.textSize.width,
      lessThanOrEqualTo(paragraph.size.width + 0.5),
      reason: '$reason: más ancho que su caja',
    );
    // Cada salto de línea cae en un espacio: ninguna palabra se parte.
    for (final word in plain.split(' ')) {
      final start = plain.indexOf(word);
      final wordLines = {
        for (final box in paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + word.length),
        ))
          box.top.round(),
      };
      expect(wordLines, hasLength(1), reason: '$reason: «$word» partida');
    }
  }

  for (final width in widths) {
    for (final scale in scales) {
      testWidgets(
        'sin confirmación ($width px, ×$scale): «Todavía sin confirmación» '
        'entera, sin «ACK», sin desbordes',
        (tester) async {
          await pump(tester, accepted: false, width: width, scale: scale);
          final chip = find.text('Todavía sin confirmación');
          expect(chip, findsOneWidget);
          expectWhole(tester, chip, 'chip sin confirmación');
          expect(find.text('Pendiente: 1'), findsOneWidget);
          expect(find.textContaining('Confirmado:'), findsNothing);
          expectNoAck();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'con confirmación ($width px, ×$scale): «Última confirmación: fecha» '
        'entera y «Confirmado: fecha» en la fila; el estado real es el mismo',
        (tester) async {
          final f = await pump(
            tester,
            accepted: true,
            width: width,
            scale: scale,
          );
          final entry = (await tester.runAsync(f.outboxEntries))!.single;
          expect(entry.ackedAt, isNotNull);
          final chip = find.text(
            'Última confirmación: ${formatDate(entry.ackedAt)}',
          );
          expect(chip, findsOneWidget);
          expectWhole(tester, chip, 'chip con confirmación');
          expect(
            find.textContaining('Confirmado: ${formatDate(entry.ackedAt)}'),
            findsOneWidget,
          );
          expect(find.text('Todavía sin confirmación'), findsNothing);
          expectNoAck();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
