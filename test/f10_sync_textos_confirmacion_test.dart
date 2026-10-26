// Lenguaje del agricultor en «Sincronización» (bloque X01, ajuste autorizado
// el 2026-10-26): los textos visibles dicen «confirmación» en vez de «ACK».
// El estado real no cambia: la chip lee `lastAcceptedAt` y la fila
// `ackedAt`, como antes. Que no haya confirmación no se presenta como prueba
// de que Central no recibió el envío. Se comprueban las dos variantes (sin y
// con confirmación) y que los textos caben con fuente normal y ampliada.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f05_sync_fixtures.dart';

final now = DateTime.utc(2026, 10, 15, 12);

void main() {
  sqfliteFfiInit();

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
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
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
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const Scaffold(body: SyncStatusScreen()),
          ),
        ),
      ),
    );
    await settle(tester);
    return f;
  }

  /// Ningún texto visible contiene la sigla «ACK».
  void expectNoAck() {
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('ACK'),
      ),
      findsNothing,
    );
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('sin confirmación (escala $scale): «Todavía sin confirmación», '
        'sin «ACK», sin desbordes', (tester) async {
      await pump(tester, accepted: false, textScale: scale);
      expect(find.text('Todavía sin confirmación'), findsOneWidget);
      expect(find.text('Pendiente: 1'), findsOneWidget);
      expect(find.textContaining('Confirmado:'), findsNothing);
      expectNoAck();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'con confirmación (escala $scale): «Última confirmación: fecha» '
      'y «Confirmado: fecha» en la fila; el estado real es el mismo',
      (tester) async {
        final f = await pump(tester, accepted: true, textScale: scale);
        final entry = (await tester.runAsync(f.outboxEntries))!.single;
        expect(entry.ackedAt, isNotNull);
        expect(
          find.text('Última confirmación: ${formatDate(entry.ackedAt)}'),
          findsOneWidget,
        );
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
