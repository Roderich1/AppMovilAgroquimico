import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/voice/voice_purchase_draft_screen.dart';
import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import '../support/f04_mode_ui_harness.dart';
import '../voice/support/fake_speech_transcription_port.dart';

/// Compra por voz completa (F09, sesión B), en la app real con la base en
/// archivo y el puerto de voz fake (no prueba el reconocimiento real):
/// selectores del formulario con «Crear …», la pregunta «¿Ya pagaste al
/// proveedor?», cero escrituras antes de confirmar, una sola escritura con sus
/// efectos y el registro manual cuando la voz no está disponible.
void main() {
  sqfliteFfiInit();

  const dictation =
      'compra de diez litros de Glifosato a 50 bolivianos el litro, '
      'proveedor Agro Norte, todo para Hermana';

  late FakeSpeechTranscriptionPort port;

  Future<({AppDatabase database, Household household})> open(
    WidgetTester tester,
    String name, {
    required List<FakeTurn> script,
    TranscriptionAvailability? availability,
  }) async {
    tester.view.physicalSize = const Size(500, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = await activatedHousehold(tester, name);
    await tester.runAsync(
      () => s.household.repo.addSupplier(name: 'Agro Norte'),
    );
    port = FakeSpeechTranscriptionPort(script: script, repeatLast: false);
    if (availability != null) port.availability = availability;
    final c = await pumpModeApp(
      tester,
      s.database,
      extraOverrides: [
        speechPortFactoryProvider.overrideWith(
          (ref) =>
              () => port,
        ),
      ],
    );
    c.read(routerProvider).go('/compras/voz');
    await settle(tester);
    expect(find.byType(VoicePurchaseDraftScreen), findsOneWidget);
    return (database: s.database, household: s.household);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) =>
      tap(tester, find.byKey(Key(key)));

  /// Elige [option] en la hoja del selector [key] (`AdaptiveEntityPicker`).
  Future<void> pick(WidgetTester tester, String key, String option) async {
    await tapKey(tester, key);
    await tester.tap(
      find
          .descendant(of: find.byType(BottomSheet), matching: find.text(option))
          .last,
    );
    await settle(tester);
  }

  /// «Crear …» del selector [key]: escribe [name] en el primer campo del
  /// diálogo de alta y guarda.
  Future<void> createFrom(WidgetTester tester, String key, String name) async {
    await tapKey(tester, key);
    await tester.tap(find.byKey(const Key('picker-create')));
    await settle(tester);
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          )
          .first,
      name,
    );
    await tester.tap(find.text('Guardar'));
    await settle(tester);
  }

  Future<void> dictate(WidgetTester tester) async {
    await tapKey(tester, 'voz-boton-microfono');
    await tapKey(tester, 'voz-boton-microfono');
  }

  Future<Map<String, List<Map<String, Object?>>>> dump(
    WidgetTester tester,
    AppDatabase database,
  ) async =>
      (await tester.runAsync(() async => dumpTables(await database.database)))!;

  Future<List<Map<String, Object?>>> rows(
    WidgetTester tester,
    AppDatabase database,
    String table,
  ) async => (await tester.runAsync(
    () async => (await database.database).query(table, orderBy: 'id'),
  ))!;

  bool registerEnabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('voz-registrar')))
          .onPressed !=
      null;

  String fieldText(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  testWidgets('«No, todavía no»: cero escrituras antes de confirmar y una sola '
      'compra con su lote, sin pago', (tester) async {
    final s = await open(
      tester,
      'no-pagada',
      script: const [FakeTurn(segment: dictation, endsOnStop: true)],
    );
    final before = await dump(tester, s.database);
    await dictate(tester);
    expect(find.byKey(const Key('voz-linea-1')), findsOneWidget);
    // Sin respuesta por defecto: bloquea y se dice por qué.
    expect(find.byKey(const Key('voz-pago-sin-respuesta')), findsOneWidget);
    expect(find.text('• Indica si ya pagaste al proveedor.'), findsOneWidget);
    expect(registerEnabled(tester), isFalse);

    await tapKey(tester, 'voz-pago-no');
    expect(find.byKey(const Key('voz-pago-pendiente-despues')), findsOneWidget);
    expect(registerEnabled(tester), isTrue);
    // Ni el dictado, ni la edición, ni la respuesta escriben nada.
    expect(await dump(tester, s.database), before);

    await tapKey(tester, 'voz-registrar');
    final purchases = await rows(tester, s.database, 'purchases');
    expect(purchases, hasLength(1));
    expect(purchases.single['total_bob_minor'], 50000);
    expect(await rows(tester, s.database, 'purchase_items'), hasLength(1));
    final lots = await rows(tester, s.database, 'inventory_lots');
    expect(lots.single['owner_person_id'], s.household.relative);
    expect(lots.single['initial_quantity_base'], 10000);
    // Queda debiendo al proveedor: ningún pago.
    expect(await rows(tester, s.database, 'provider_payments'), isEmpty);
  });

  testWidgets('«Sí, pagué todo»: compra y pago del titular por el total, con '
      'el medio elegido', (tester) async {
    final s = await open(
      tester,
      'pagada',
      script: const [FakeTurn(segment: dictation, endsOnStop: true)],
    );
    await dictate(tester);
    await tapKey(tester, 'voz-pago-si');
    expect(find.textContaining('Paga el titular: '), findsOneWidget);
    // El medio empieza en «Sin indicar» y se ve; se corrige a mano.
    await tapKey(tester, 'payment-method-transfer');
    expect(registerEnabled(tester), isTrue);
    expect(await rows(tester, s.database, 'provider_payments'), isEmpty);

    await tapKey(tester, 'voz-registrar');
    final purchases = await rows(tester, s.database, 'purchases');
    expect(purchases, hasLength(1));
    final payments = await rows(tester, s.database, 'provider_payments');
    expect(payments, hasLength(1));
    expect(payments.single['purchase_id'], purchases.single['id']);
    expect(payments.single['payer_person_id'], s.household.titular);
    expect(payments.single['amount_bob_minor'], 50000);
    expect(payments.single['method'], 'TRANSFER');
  });

  testWidgets('«Crear proveedor» desde el selector: el dictado no crea nada, '
      'la persona lo crea, queda elegido y el borrador se conserva', (
    tester,
  ) async {
    final s = await open(
      tester,
      'crear-proveedor',
      script: const [
        FakeTurn(
          segment:
              'compra de diez litros de Glifosato a 50 bolivianos el litro, '
              'proveedor Agro Sur, todo para Hermana',
          endsOnStop: true,
        ),
      ],
    );
    final suppliersBefore = (await rows(
      tester,
      s.database,
      'suppliers',
    )).length;
    await dictate(tester);
    expect(find.text('Oído: «agro sur»'), findsOneWidget);
    expect(
      await rows(tester, s.database, 'suppliers'),
      hasLength(suppliersBefore),
    );
    expect(registerEnabled(tester), isFalse);

    await createFrom(tester, 'voz-borrador-proveedor', 'Agro Sur');
    final suppliers = await rows(tester, s.database, 'suppliers');
    expect(suppliers, hasLength(suppliersBefore + 1));
    final created = suppliers.last;
    expect(created['name'], 'Agro Sur');
    // Elegido en el selector y marcado como corrección manual.
    expect(
      find.descendant(
        of: find.byKey(const Key('voz-borrador-proveedor')),
        matching: find.text('Agro Sur'),
      ),
      findsOneWidget,
    );
    // El borrador sigue: la línea dictada, su cantidad y su precio.
    expect(fieldText(tester, 'voz-cantidad-1'), '10');
    expect(fieldText(tester, 'voz-precio-1'), '50');
    expect(await rows(tester, s.database, 'purchases'), isEmpty);

    await tapKey(tester, 'voz-pago-no');
    await tapKey(tester, 'voz-registrar');
    final purchases = await rows(tester, s.database, 'purchases');
    expect(purchases.single['supplier_id'], created['id']);
  });

  testWidgets('«Crear producto» desde el selector de una línea', (
    tester,
  ) async {
    final s = await open(
      tester,
      'crear-producto',
      script: const [
        FakeTurn(
          segment:
              'compra de veinte litros de Paraquat a 50 bolivianos el litro, '
              'proveedor Agro Norte, todo para Hermana',
          endsOnStop: true,
        ),
      ],
    );
    final productsBefore = (await rows(tester, s.database, 'products')).length;
    await dictate(tester);
    expect(
      find.textContaining('«paraquat» no está en el catálogo'),
      findsWidgets,
    );
    expect(
      await rows(tester, s.database, 'products'),
      hasLength(productsBefore),
    );

    await createFrom(tester, 'voz-producto-1', 'Paraquat');
    final products = await rows(tester, s.database, 'products');
    expect(products, hasLength(productsBefore + 1));
    expect(
      find.descendant(
        of: find.byKey(const Key('voz-producto-1')),
        matching: find.text('Paraquat'),
      ),
      findsOneWidget,
    );
    expect(fieldText(tester, 'voz-cantidad-1'), '20');
    await tapKey(tester, 'voz-pago-no');
    expect(registerEnabled(tester), isTrue);
    await tapKey(tester, 'voz-registrar');
    final items = await rows(tester, s.database, 'purchase_items');
    expect(items.single['product_id'], products.last['id']);
    expect(items.single['quantity_base'], 20000);
  });

  testWidgets('una corrección a mano hecha mientras se escucha no la cambia '
      'el resultado que llega después', (tester) async {
    final s = await open(
      tester,
      'tardio',
      script: const [
        FakeTurn(segment: dictation, endsOnStop: true),
        FakeTurn(
          partials: ['sesenta'],
          segment: 'sesenta litros de Glifosato',
          endsOnStop: true,
        ),
      ],
    );
    await dictate(tester);
    // Segundo turno abierto: se corrige a mano antes de que llegue.
    await tapKey(tester, 'voz-boton-microfono');
    expect(port.microphoneOpen, isTrue);
    await tester.enterText(find.byKey(const Key('voz-cantidad-1')), '30');
    await settle(tester);
    await tapKey(tester, 'voz-boton-microfono'); // llega «sesenta litros…»
    expect(fieldText(tester, 'voz-cantidad-1'), '30');
    expect(find.text('Corregido a mano'), findsWidgets);

    await tapKey(tester, 'voz-pago-no');
    await tapKey(tester, 'voz-registrar');
    final items = await rows(tester, s.database, 'purchase_items');
    expect(items.single['quantity_base'], 30000);
  });

  /// Toda la compra a mano en el borrador, sin ningún dictado.
  Future<void> fillByHand(WidgetTester tester) async {
    await tapKey(tester, 'voz-agregar-linea');
    await pick(tester, 'voz-producto-1', 'Glifosato');
    await tester.enterText(find.byKey(const Key('voz-cantidad-1')), '10');
    await tester.enterText(find.byKey(const Key('voz-precio-1')), '50');
    await settle(tester);
    await tap(
      tester,
      find.descendant(
        of: find.byKey(const Key('voz-moneda-1')),
        matching: find.text('BOB'),
      ),
    );
    await pick(tester, 'voz-borrador-proveedor', 'Agro Norte');
    await pick(tester, 'voz-borrador-persona', 'Hermana');
    await tapKey(tester, 'voz-pago-no');
  }

  testWidgets('con el micrófono denegado la compra se completa a mano', (
    tester,
  ) async {
    final s = await open(
      tester,
      'sin-permiso',
      script: const [
        FakeTurn(failWith: TranscriptionErrorCode.permissionDenied),
      ],
    );
    await tapKey(tester, 'voz-boton-microfono');
    expect(port.microphoneOpen, isFalse);
    expect(find.byKey(const Key('voz-linea-1')), findsNothing);

    await fillByHand(tester);
    expect(registerEnabled(tester), isTrue);
    await tapKey(tester, 'voz-registrar');
    expect(await rows(tester, s.database, 'purchases'), hasLength(1));
    expect(await rows(tester, s.database, 'provider_payments'), isEmpty);
    expect(port.microphoneOpen, isFalse);
  });

  testWidgets('sin motor de voz disponible la compra se completa a mano', (
    tester,
  ) async {
    final s = await open(
      tester,
      'sin-motor',
      script: const [FakeTurn(segment: dictation, endsOnStop: true)],
      availability: const TranscriptionAvailability.none(detail: 'sin-motor'),
    );
    await tapKey(tester, 'voz-boton-microfono');
    expect(port.microphoneOpen, isFalse);
    expect(find.byKey(const Key('voz-linea-1')), findsNothing);

    await fillByHand(tester);
    await tapKey(tester, 'voz-registrar');
    final items = await rows(tester, s.database, 'purchase_items');
    expect(items.single['quantity_base'], 10000);
    expect(port.startRequests, isEmpty);
  });
}
