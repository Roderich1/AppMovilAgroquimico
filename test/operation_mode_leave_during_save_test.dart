// Modo de uso (F04-MODE-05, MOB #178): salir de la pantalla mientras se
// guarda el cambio de modalidad. La modalidad global (`operationModeProvider`)
// vive en el contenedor raíz y debe quedar en la realmente guardada aunque la
// pantalla ya no exista, sin reiniciar; sólo el aviso y el estado visual de la
// pantalla dependen de que siga montada. Un guardado rechazado no se anuncia
// ni se muestra.
//
// La escritura se alarga reteniendo una transacción real de la misma base:
// sqflite atiende las transacciones en orden, así que la del cambio espera
// detrás. No hay retrasos ni ganchos en el código de la aplicación. App real,
// sin red.
import 'dart:async';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  final modeChange = find.byKey(const Key('mode-change'));
  final modeConfirm = find.byKey(const Key('mode-confirm'));
  final modeCurrent = find.byKey(const Key('mode-current'));
  final modeBlocked = find.byKey(const Key('mode-blocked'));

  /// Espera, con límite, a que terminen las escrituras ya pedidas a la base:
  /// una transacción de control se pone a la cola y avisa cuando le toca.
  Future<void> waitWrites(
    WidgetTester tester,
    AppDatabase database,
    String what,
  ) async {
    var done = false;
    await tester.runAsync(() async {
      final db = await database.database;
      unawaited(db.transaction((_) async {}).whenComplete(() => done = true));
    });
    await waitUntil(tester, what, () => done);
  }

  /// Retiene las escrituras de [database] hasta llamar a la función devuelta.
  /// Llamarla después de montar la app: su teardown, que suelta y deja
  /// terminar lo pendiente, corre así antes de desechar el contenedor.
  Future<void Function()> holdWrites(
    WidgetTester tester,
    AppDatabase database,
  ) async {
    final release = Completer<void>();
    await tester.runAsync(() async {
      final db = await database.database;
      final started = Completer<void>();
      unawaited(
        db.transaction((_) async {
          started.complete();
          await release.future;
        }),
      );
      await started.future;
    });
    void releaseWrites() {
      if (!release.isCompleted) release.complete();
    }

    addTearDown(() async {
      releaseWrites();
      await waitWrites(tester, database, 'las escrituras al terminar');
    });
    return releaseWrites;
  }

  bool changing(WidgetTester tester) =>
      modeChange.evaluate().isNotEmpty &&
      tester.widget<FilledButton>(modeChange).onPressed == null;

  String? shownMode(WidgetTester tester) => modeCurrent.evaluate().isEmpty
      ? null
      : tester.widget<Text>(modeCurrent).data;

  /// Abre «Modo de uso», pide el cambio y espera el diálogo de confirmación.
  Future<void> openAndAskChange(
    WidgetTester tester,
    ProviderContainer c,
  ) async {
    c.read(routerProvider).push('/modo');
    await settle(tester);
    await tester.tap(modeChange);
    await waitUntil(
      tester,
      'el diálogo de confirmación',
      () => modeConfirm.evaluate().isNotEmpty,
    );
  }

  /// Confirma y espera a que la pantalla empiece a guardar.
  Future<void> confirmAndStartSaving(WidgetTester tester) async {
    await tester.tap(modeConfirm);
    await waitUntil(
      tester,
      'el inicio del guardado («Cambiar…» inactivo)',
      () => changing(tester),
    );
  }

  /// El usuario vuelve atrás: la pantalla de modo de uso se desmonta.
  Future<void> leaveScreen(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).pop();
    await settle(tester);
    expect(modeChange, findsNothing, reason: 'la pantalla ya no está');
  }

  Future<OperationMode?> stored(WidgetTester tester, AppDatabase database) =>
      tester.runAsync(() => OperationModeStore(database).current());

  /// La navegación sigue a la modalidad global: Operaciones ofrece
  /// Transferencias sólo en compartido, y en propio la ruta vuelve atrás.
  Future<void> expectNavigationFor(
    WidgetTester tester,
    ProviderContainer c,
    OperationMode mode,
  ) async {
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    expect(
      find.text('Transferencias'),
      mode == OperationMode.shared ? findsOneWidget : findsNothing,
    );
    c.read(routerProvider).go('/transferencias');
    await settle(tester);
    expect(
      currentPath(c),
      mode == OperationMode.shared ? '/transferencias' : '/operaciones',
    );
  }

  group('salir durante el guardado', () {
    for (final (from, to) in [
      (OperationMode.personal, OperationMode.shared),
      (OperationMode.shared, OperationMode.personal),
    ]) {
      testWidgets('${from.code} → ${to.code}: la modalidad global y la '
          'navegación quedan en la guardada, sin reiniciar', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final s = await activatedHousehold(tester, 'salir_${to.code}');
        await tester.runAsync(
          () => OperationModeStore(s.database).apply(from, confirmed: true),
        );
        final offline = OfflineTransport();
        final c = await pumpModeApp(tester, s.database, transport: offline);
        expect(c.read(operationModeProvider), from);

        await openAndAskChange(tester, c);
        final release = await holdWrites(tester, s.database);
        await confirmAndStartSaving(tester);
        await leaveScreen(tester, c);
        // Con la escritura retenida no se lee la base (esperaría detrás).
        expect(c.read(operationModeProvider), from);

        release();
        await waitWrites(tester, s.database, 'el guardado del cambio');
        expect(await stored(tester, s.database), to);
        await waitUntil(
          tester,
          'la recarga de la modalidad global tras salir',
          () => c.read(operationModeProvider) == to,
          state: () =>
              'operationModeProvider: ${c.read(operationModeProvider)}; '
              'guardada: $to',
        );
        await expectNavigationFor(tester, c, to);
        expect(c.read(operationModeProvider), to);
        expect(offline.requests, 0);
      });
    }

    testWidgets('el guardado se rechaza tras salir: nada cambia ni se '
        'anuncia', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'salir_rechazo');
      final offline = OfflineTransport();
      final c = await pumpModeApp(tester, s.database, transport: offline);
      expect(c.read(operationModeProvider), OperationMode.shared);

      await openAndAskChange(tester, c);
      // Entre la confirmación y la escritura aparecen existencias de un
      // tercero: la transacción del cambio vuelve a evaluar y lo rechaza.
      await tester.runAsync(() => s.household.buy(s.household.relative, 3000));
      final release = await holdWrites(tester, s.database);
      await confirmAndStartSaving(tester);
      await leaveScreen(tester, c);

      release();
      await waitWrites(tester, s.database, 'el intento de guardado');
      await settle(tester);
      expect(await stored(tester, s.database), OperationMode.shared);
      expect(c.read(operationModeProvider), OperationMode.shared);
      expect(find.textContaining('Ahora usa inventario'), findsNothing);
      await expectNavigationFor(tester, c, OperationMode.shared);
      expect(offline.requests, 0);
    });

    testWidgets('el guardado falla tras salir (error de la base): nada '
        'cambia ni se anuncia', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'salir_fallo');
      final offline = OfflineTransport();
      final c = await pumpModeApp(tester, s.database, transport: offline);
      expect(c.read(operationModeProvider), OperationMode.shared);

      await openAndAskChange(tester, c);
      // Un fallo de la base que no es un rechazo de la transición: un
      // disparador temporal (sólo de esta conexión, sólo en la prueba) aborta
      // la escritura de la modalidad. El cambio sale por `on Object catch`.
      await tester.runAsync(() async {
        final db = await s.database.database;
        await db.execute(
          'CREATE TEMP TRIGGER prueba_fallo_modo BEFORE INSERT ON '
          "app_settings BEGIN SELECT RAISE(ABORT, 'fallo de prueba'); END",
        );
      });
      final release = await holdWrites(tester, s.database);
      await confirmAndStartSaving(tester);
      await leaveScreen(tester, c);

      release();
      await waitWrites(tester, s.database, 'el intento de guardado');
      await settle(tester);
      await tester.runAsync(() async {
        final db = await s.database.database;
        await db.execute('DROP TRIGGER temp.prueba_fallo_modo');
      });
      expect(await stored(tester, s.database), OperationMode.shared);
      expect(c.read(operationModeProvider), OperationMode.shared);
      expect(find.textContaining('Ahora usa inventario'), findsNothing);
      await expectNavigationFor(tester, c, OperationMode.shared);
      expect(offline.requests, 0);
    });
  });

  group('quedarse en la pantalla', () {
    testWidgets('compartido → propio: avisa, muestra y aplica la modalidad '
        'guardada', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'quedarse');
      final offline = OfflineTransport();
      final c = await pumpModeApp(tester, s.database, transport: offline);

      await openAndAskChange(tester, c);
      await tester.tap(modeConfirm);
      await waitUntil(
        tester,
        'el cambio de modalidad en pantalla',
        () =>
            !changing(tester) &&
            shownMode(tester) == 'Modalidad actual: inventario propio',
        state: () =>
            'cambio en curso: ${changing(tester)}; '
            'modalidad mostrada: ${shownMode(tester)}',
      );
      expect(
        find.textContaining('Ahora usa inventario propio'),
        findsOneWidget,
      );
      expect(await stored(tester, s.database), OperationMode.personal);
      expect(c.read(operationModeProvider), OperationMode.personal);
      await expectNavigationFor(tester, c, OperationMode.personal);
      expect(offline.requests, 0);
    });

    testWidgets('el guardado se rechaza: muestra el motivo, no anuncia ni '
        'muestra el cambio', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'quedarse_rechazo');
      final offline = OfflineTransport();
      final c = await pumpModeApp(tester, s.database, transport: offline);

      await openAndAskChange(tester, c);
      await tester.runAsync(() => s.household.buy(s.household.relative, 3000));
      await tester.tap(modeConfirm);
      await waitUntil(
        tester,
        'el rechazo en pantalla',
        () => !changing(tester) && modeBlocked.evaluate().isNotEmpty,
        state: () =>
            'cambio en curso: ${changing(tester)}; '
            'modalidad mostrada: ${shownMode(tester)}',
      );
      final blocked = tester.widget<Text>(
        find.descendant(of: modeBlocked, matching: find.byType(Text)),
      );
      expect(blocked.data, contains('Existencias de Hermana'));
      expect(find.textContaining('Ahora usa inventario'), findsNothing);
      expect(shownMode(tester), 'Modalidad actual: inventario compartido');
      expect(await stored(tester, s.database), OperationMode.shared);
      expect(c.read(operationModeProvider), OperationMode.shared);
      expect(offline.requests, 0);
    });

    testWidgets('el guardado falla por una restauración en curso: muestra el '
        'error, no anuncia ni muestra el cambio', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = await activatedHousehold(tester, 'quedarse_error');
      final offline = OfflineTransport();
      final c = await pumpModeApp(tester, s.database, transport: offline);

      await openAndAskChange(tester, c);
      // Una sustitución de la base en curso rechaza toda escritura nueva.
      final replacing = Completer<void>();
      addTearDown(() {
        if (!replacing.isCompleted) replacing.complete();
      });
      unawaited(s.database.replacement.replace(() => replacing.future));
      await tester.tap(modeConfirm);
      await waitUntil(
        tester,
        'el error en pantalla',
        () =>
            !changing(tester) &&
            find.textContaining('Se está restaurando').evaluate().isNotEmpty,
        state: () =>
            'cambio en curso: ${changing(tester)}; '
            'modalidad mostrada: ${shownMode(tester)}',
      );
      expect(find.textContaining('Ahora usa inventario'), findsNothing);
      expect(shownMode(tester), 'Modalidad actual: inventario compartido');
      expect(c.read(operationModeProvider), OperationMode.shared);
      replacing.complete();
      await settle(tester);
      expect(await stored(tester, s.database), OperationMode.shared);
      expect(offline.requests, 0);
    });
  });
}
