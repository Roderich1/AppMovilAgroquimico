import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/voice/voice_application_draft_screen.dart';
import 'package:agroquimicos/presentation/voice/voice_plan_draft_screen.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import '../voice/support/fake_speech_transcription_port.dart';

/// Aplicación y planificación por voz con la UX del jurado: selectores del
/// formulario con «Crear chaco»/«Crear producto», el aviso de lote vencido en
/// la aplicación y las validaciones de existencias. Base real en memoria y
/// puerto fake: no prueba el reconocimiento real.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late Household household;
  late FakeSpeechTranscriptionPort port;

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      for (var f = 0; f < 6; f++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    required String dictation,
    Future<void> Function(AgroRepository repo, Household h)? seed,
  }) async {
    final repo = (await tester.runAsync(() async {
      database = openDb(inMemoryDatabasePath);
      final created = AgroRepository(database);
      household = await seedHousehold(created);
      await seed?.call(created, household);
      return created;
    }))!;
    port = FakeSpeechTranscriptionPort(
      script: [FakeTurn(segment: dictation, endsOnStop: true)],
      repeatLast: false,
    );
    tester.view.physicalSize = const Size(500, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          speechPortFactoryProvider.overrideWith(
            (ref) =>
                () => port,
          ),
        ],
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
    await drain(tester);
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.byKey(const Key('voz-boton-microfono')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('voz-boton-microfono')));
      await drain(tester);
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await drain(tester);
  }

  Future<List<Map<String, Object?>>> rows(
    WidgetTester tester,
    String table,
  ) async => (await tester.runAsync(
    () async => (await database.database).query(table, orderBy: 'id'),
  ))!;

  bool registerEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('voz-registrar')))
          .onPressed !=
      null;

  Finder dialogField(String label) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    ),
  );

  /// «Crear chaco» desde el selector [key], con dueño Titular.
  Future<void> createFarm(WidgetTester tester, String key) async {
    await tapKey(tester, key);
    await tester.tap(find.byKey(const Key('picker-create')));
    await drain(tester);
    expect(find.text('Nuevo chaco'), findsOneWidget);
    if (find.byType(DropdownButtonFormField<int>).evaluate().isNotEmpty) {
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await drain(tester);
      await tester.tap(find.text('Titular').last);
      await drain(tester);
    }
    await tester.enterText(dialogField('Nombre'), 'Lomas');
    await tester.enterText(dialogField('Superficie (ha)'), '2');
    await tester.tap(find.text('Guardar'));
    await drain(tester);
  }

  group('aplicación', () {
    testWidgets('aviso de lote vencido antes de confirmar; sólo informa', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const VoiceApplicationDraftScreen(),
        dictation: 'apliqué dos litros de Glifosato en el chaco titular',
        seed: (repo, h) async {
          // Lote del titular que venció antes de hoy (la compra lo admite).
          await repo.confirmPurchase(
            PurchaseDraft(
              supplierId: h.supplier,
              campaignId: h.campaign,
              purchaseDate: DateTime.utc(2026, 1, 2),
              items: [
                PurchaseItemDraft(
                  productId: h.product,
                  quantityBase: 5000,
                  currency: CurrencyCode.bob,
                  originalUnitPriceMinor: 10000,
                  expiryDay: '2026-02-01',
                  lotNumber: 'L-7',
                  allocations: [
                    AllocationDraft(personId: h.titular, quantityBase: 5000),
                  ],
                ),
              ],
            ),
          );
        },
      );
      expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
      expect(
        find.byKey(const Key('application-expiry-expired')),
        findsOneWidget,
      );
      expect(find.textContaining('del lote L-7'), findsOneWidget);
      // No bloquea: la regla FIFO no cambia y se registra igual.
      expect(registerEnabled(tester), isTrue);
      expect(await rows(tester, 'applications'), isEmpty);
      await tapKey(tester, 'voz-registrar');
      expect(await rows(tester, 'applications'), hasLength(1));
    });

    testWidgets('sin lotes vencidos no hay aviso', (tester) async {
      await pumpScreen(
        tester,
        const VoiceApplicationDraftScreen(),
        dictation: 'apliqué dos litros de Glifosato en el chaco titular',
        seed: (repo, h) async {
          await h.buy(h.titular, 5000);
        },
      );
      expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
      expect(find.byKey(const Key('application-expiry-expired')), findsNothing);
      expect(registerEnabled(tester), isTrue);
    });

    testWidgets('sin existencias suficientes no se registra', (tester) async {
      await pumpScreen(
        tester,
        const VoiceApplicationDraftScreen(),
        dictation: 'apliqué nueve litros de Glifosato en el chaco titular',
        seed: (repo, h) async {
          await h.buy(h.titular, 5000);
        },
      );
      expect(find.textContaining('no hay stock suficiente'), findsWidgets);
      expect(registerEnabled(tester), isFalse);
    });

    testWidgets('«Crear chaco» desde el selector: lo crea la persona, queda '
        'elegido con su dueño y el borrador se conserva', (tester) async {
      await pumpScreen(
        tester,
        const VoiceApplicationDraftScreen(),
        dictation: 'apliqué dos litros de Glifosato en el chaco Lomas',
        seed: (repo, h) async {
          await h.buy(h.titular, 5000);
        },
      );
      final farmsBefore = (await rows(tester, 'farms')).length;
      expect(find.text('Oído: «Lomas»'), findsNothing);
      expect(registerEnabled(tester), isFalse);

      await createFarm(tester, 'voz-borrador-chaco');
      final farms = await rows(tester, 'farms');
      expect(farms, hasLength(farmsBefore + 1));
      expect(
        find.descendant(
          of: find.byKey(const Key('voz-borrador-chaco')),
          matching: find.text('Lomas'),
        ),
        findsOneWidget,
      );
      expect(find.text('Aplica: Titular'), findsOneWidget);
      expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
      await drain(tester);
      expect(registerEnabled(tester), isTrue);
      await tapKey(tester, 'voz-registrar');
      final applied = await rows(tester, 'applications');
      expect(applied.single['farm_id'], farms.last['id']);
    });
  });

  group('planificación', () {
    testWidgets('«Crear producto» desde el selector y crear el plan una vez', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const VoicePlanDraftScreen(),
        dictation:
            'planificar el chaco titular con un litro por hectárea de Paraquat',
      );
      final productsBefore = (await rows(tester, 'products')).length;
      expect(
        find.textContaining('«paraquat» no está en el catálogo'),
        findsWidgets,
      );
      expect(await rows(tester, 'products'), hasLength(productsBefore));

      await tapKey(tester, 'voz-producto-1');
      await tester.tap(find.byKey(const Key('picker-create')));
      await drain(tester);
      await tester.enterText(dialogField('Producto'), 'Paraquat');
      await tester.tap(find.text('Guardar'));
      await drain(tester);
      final products = await rows(tester, 'products');
      expect(products, hasLength(productsBefore + 1));
      expect(
        find.descendant(
          of: find.byKey(const Key('voz-producto-1')),
          matching: find.text('Paraquat'),
        ),
        findsOneWidget,
      );
      expect(registerEnabled(tester), isTrue);
      await tapKey(tester, 'voz-registrar');
      expect(await rows(tester, 'application_plans'), hasLength(1));
      final items = await rows(tester, 'application_plan_items');
      expect(items.single['product_id'], products.last['id']);
    });

    testWidgets('«Crear chaco» desde el selector', (tester) async {
      await pumpScreen(
        tester,
        const VoicePlanDraftScreen(),
        dictation:
            'planificar el chaco Lomas con un litro por hectárea de Glifosato',
      );
      expect(registerEnabled(tester), isFalse);
      await createFarm(tester, 'voz-borrador-chaco');
      expect(
        find.descendant(
          of: find.byKey(const Key('voz-borrador-chaco')),
          matching: find.text('Lomas'),
        ),
        findsOneWidget,
      );
      // El área se propone desde el chaco creado, como en el formulario.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('voz-area')))
            .controller!
            .text,
        '2',
      );
      expect(registerEnabled(tester), isTrue);
      await tapKey(tester, 'voz-registrar');
      final plans = await rows(tester, 'application_plans');
      expect(plans, hasLength(1));
      expect(household.titularFarm, isNot(plans.single['farm_id']));
    });
  });
}
