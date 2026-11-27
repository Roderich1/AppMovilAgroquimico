import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/catalogs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart' show waitFor;

void main() {
  sqfliteFfiInit();

  testWidgets('Personas ofrece dos altas y conserva el tipo al editar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = (await tester.runAsync(() async {
      final database = openDb(inMemoryDatabasePath);
      final repo = AgroRepository(database);
      final titular = await repo.addPerson(
        name: 'Alicia',
        role: PersonRole.admin,
      );
      await repo.addPerson(name: 'Ernesto', role: PersonRole.admin);
      await OwnerBindingStore(database).bindExistingPerson(
        personId: titular,
        scope: memberA,
        installationRef: installationHere,
        confirmAdministrator: true,
      );
      return repo;
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: Scaffold(body: CatalogsScreen())),
      ),
    );

    Finder tile(String name) => find.widgetWithText(ListTile, name);
    Finder subtitle(String name, String label) =>
        find.descendant(of: tile(name), matching: find.text(label));
    final dialog = find.byType(AlertDialog);
    await waitFor(tester, tile('Alicia'));
    expect(subtitle('Alicia', 'Titular'), findsOneWidget);
    expect(subtitle('Ernesto', 'Administrador · Manual'), findsOneWidget);

    Future<void> add(String name, String label) async {
      await tester.tap(find.text('Agregar persona'));
      await waitFor(tester, find.text('Nueva persona'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('person-name')), name);
      final dropdown = find.descendant(
        of: dialog,
        matching: find.byType(DropdownButtonFormField<PersonRole>),
      );
      final field = tester.widget<DropdownButtonFormField<PersonRole>>(
        dropdown,
      );
      expect(field.initialValue, PersonRole.family);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Familiar')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tercero'), findsOneWidget);
      expect(find.text('Administrador'), findsNothing);
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await waitFor(tester, tile(name));
      expect(tile(name), findsOneWidget);
    }

    await add('Camila', 'Familiar');
    await add('Daniel', 'Tercero');

    Future<void> rename(String before, String after) async {
      await tester.tap(
        find.descendant(
          of: tile(before),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar nombre'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<PersonRole>), findsNothing);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        after,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await waitFor(tester, tile(after));
      expect(tile(after), findsOneWidget);
    }

    await rename('Ernesto', 'Ernesto actualizado');
    await rename('Camila', 'Camila actualizada');
    await rename('Daniel', 'Daniel actualizado');

    final people = (await tester.runAsync(repo.people))!;
    expect(
      {for (final p in people) p['name']: (p['role'], p['settlement_policy'])},
      {
        'Alicia': ('ADMIN', 'MANUAL'),
        'Ernesto actualizado': ('ADMIN', 'MANUAL'),
        'Camila actualizada': ('FAMILY', 'BY_ACTUAL_USAGE'),
        'Daniel actualizado': ('THIRD_PARTY', 'BY_PURCHASE_ALLOCATION'),
      },
    );
  });
}
