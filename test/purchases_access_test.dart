// UIBUG-002: la pantalla de historial de compras era inalcanzable.
//
// La ruta `/compras` estaba declarada en `lib/app.dart` pero **ninguna parte de
// `lib/` navegaba hacia ella**. Con ella quedaban fuera del alcance del usuario:
// el historial, los pagos a proveedor posteriores a la compra, el visor de la
// fotografia de factura y la reversion de compras. Funcionalidad implementada y
// probada que nadie podia usar.
//
// UIBUG-011 va en el mismo lote: confirmar una compra no daba ningun acuse
// porque `OperationsScreen` descartaba el resultado del formulario. La solucion
// natural -- volver a un listado donde la compra aparezca -- exigia que ese
// listado fuese alcanzable.

import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester, {int frames = 15}) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<AgroRepository> fixture() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repo = AgroRepository(database);
    final family = await repo.addPerson(name: 'José', role: PersonRole.family);
    await repo.addPerson(name: 'Administrador', role: PersonRole.admin);
    await repo.addFarm(ownerId: family, name: 'Chaco', areaM2: 100000);
    await repo.addCampaign(name: 'Campaña', start: DateTime.utc(2026));
    await repo.addProduct(name: 'Glifosato');
    await repo.addSupplier(name: 'Proveedor');
    return repo;
  }

  Future<void> pumpApp(WidgetTester tester, AgroRepository repo) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const AgroApp(),
      ),
    );
    await settle(tester);
  }

  testWidgets('UIBUG-002: se llega al historial de compras desde Operaciones', (
    tester,
  ) async {
    final repo = await tester.runAsync(fixture);
    await pumpApp(tester, repo!);

    await tester.tap(find.text('Operaciones').last);
    await settle(tester, frames: 25);

    // La tarjeta de compras debe existir y llevar al LISTADO, igual que las de
    // aplicaciones y transferencias.
    final card = find.textContaining('Compras');
    expect(
      card,
      findsWidgets,
      reason: 'Operaciones debe ofrecer una entrada a Compras',
    );
    await tester.tap(card.first);
    await settle(tester, frames: 30);

    // `PurchasesScreen` se identifica por su boton, que no existe en ninguna
    // otra pantalla del shell.
    expect(
      find.text('Nueva compra'),
      findsOneWidget,
      reason: 'Debe abrirse el historial de compras (PurchasesScreen)',
    );
    // Y no debe haberse abierto directamente el formulario: 'Factura' es el
    // titulo de su primera seccion.
    expect(
      find.text('Factura'),
      findsNothing,
      reason: 'La tarjeta debe abrir el listado, no el formulario',
    );
  });

  testWidgets('UIBUG-002: desde el historial se abre el formulario de compra', (
    tester,
  ) async {
    final repo = await tester.runAsync(fixture);
    await pumpApp(tester, repo!);

    await tester.tap(find.text('Operaciones').last);
    await settle(tester, frames: 25);
    await tester.tap(find.textContaining('Compras').first);
    await settle(tester, frames: 30);

    await tester.tap(find.text('Nueva compra'));
    await settle(tester, frames: 30);
    await settle(tester, frames: 30);

    expect(
      find.text('Factura'),
      findsOneWidget,
      reason: 'Operaciones -> Compras -> Nueva compra debe abrir el formulario',
    );
  });

  test('ninguna ruta declarada queda sin origen en lib/', () {
    // Guardia permanente contra la clase de defecto de UIBUG-002: una ruta
    // declarada a la que nadie navega es funcionalidad inalcanzable.
    final appSource = File('lib/app.dart').readAsStringSync();
    final declared = RegExp(r"path:\s*'([^']+)'")
        .allMatches(appSource)
        .map((m) => m.group(1)!)
        .where((path) => !path.contains(':')) // las rutas con parametro no
        .toSet(); // se citan literalmente

    // Todo el codigo de presentacion, incluido `app_shell.dart`.
    final buffer = StringBuffer();
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        buffer.write(entity.readAsStringSync());
      }
    }
    final sources = buffer.toString();

    final orphans = <String>[];
    for (final route in declared) {
      // Se busca la ruta citada como destino de navegacion, no su declaracion.
      final quoted = "'${RegExp.escape(route)}'";
      final cited = RegExp('(go|push)(<[^>]*>)?\\(\\s*$quoted')
          .hasMatch(sources);
      // `/` es la ruta inicial del router: no necesita que nadie navegue a ella
      // con una cadena literal (la barra de navegacion la usa por indice).
      final isInitial = route == '/';
      // Las rutas se citan tambien desde listas de acciones (`path: '/x'`)
      // fuera de `app.dart`.
      final inActionList =
          RegExp('path:\\s*$quoted').allMatches(sources).length > 1;
      if (!cited && !isInitial && !inActionList) orphans.add(route);
    }

    expect(
      orphans,
      isEmpty,
      reason:
          'Rutas declaradas a las que no navega nadie (funcionalidad '
          'inalcanzable, como UIBUG-002): $orphans',
    );
  });
}
