// Ronda 2 del rediseño, sesión C (P1b): el buscador de personas. La regla
// es una sola (`matchesPersonSearch`) y Personas y Cuentas filtran igual,
// también la tarjeta del titular, con el mismo estado sin resultados.
// Datos sintéticos (`support_rdm2/c_seed.dart`).
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/text_search.dart';
import 'package:agroquimicos/presentation/widgets/rdm2_c_person_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';
import 'support_rdm2/c_seed.dart';

const _names = [rdm2cOwnerName, rdm2cLongName, rdm2cThirdName, rdm2cQuietName];

void main() {
  sqfliteFfiInit();

  group('regla', () {
    test('causa: la regla anterior busca la consulta entera como un trozo '
        'seguido del nombre', () {
      // Lo que usaban Personas y Cuentas hasta la ronda 2.
      expect(matchesSearch(rdm2cLongName, 'maria quispe'), isFalse);
      expect(matchesSearch(rdm2cLongName, 'maria  quispe'), isFalse);
      expect(matchesSearch(rdm2cLongName, ' maria'), isFalse);
      // Y con la regla nueva sí se encuentran.
      expect(matchesPersonSearch(rdm2cLongName, 'maria quispe'), isTrue);
      expect(matchesPersonSearch(rdm2cLongName, 'maria  quispe'), isTrue);
      expect(matchesPersonSearch(rdm2cLongName, ' maria'), isTrue);
    });

    test('coincidencia parcial, sin mayúsculas ni tildes', () {
      expect(matchesPersonSearch('Rosa Vargas', 'ro'), isTrue);
      expect(matchesPersonSearch('Juan Mamani', 'ro'), isFalse);
      expect(matchesPersonSearch('Rosa Vargas', 'ROSA'), isTrue);
      expect(matchesPersonSearch('María Fernanda', 'maria'), isTrue);
      expect(matchesPersonSearch('Maria Fernanda', 'María'), isTrue);
      expect(matchesPersonSearch('José Luis', 'JOSE'), isTrue);
    });

    test('espacios a los lados, dobles y entre nombre y apellido', () {
      expect(matchesPersonSearch(rdm2cLongName, '  maria  '), isTrue);
      expect(matchesPersonSearch(rdm2cLongName, 'maria  quispe'), isTrue);
      expect(matchesPersonSearch(rdm2cLongName, 'maria quispe'), isTrue);
      expect(matchesPersonSearch(rdm2cLongName, 'quispe maria'), isTrue);
      expect(matchesPersonSearch(rdm2cLongName, 'maria vargas'), isFalse);
      expect(matchesPersonSearch('Rosa  Vargas ', 'rosa vargas'), isTrue);
    });

    test('la ñ es una letra (UIBUG-019), también en forma descompuesta', () {
      expect(matchesPersonSearch('José Luis Peña Núñez', 'peña'), isTrue);
      expect(matchesPersonSearch('José Luis Peña Núñez', 'PEÑA nuñez'), isTrue);
      expect(matchesPersonSearch('José Luis Peña Núñez', 'pena'), isFalse);
      // «Peña» y «María» con las marcas sueltas (U+0303, U+0301).
      expect(matchesPersonSearch('Peña', 'peña'), isTrue);
      expect(matchesPersonSearch('María', 'maria'), isTrue);
      expect(matchesPersonSearch('María', 'María'), isTrue);
    });

    test('vacío o sólo espacios no filtra', () {
      expect(matchesPersonSearch('Rosa Vargas', ''), isTrue);
      expect(matchesPersonSearch('Rosa Vargas', '   '), isTrue);
    });
  });

  group('pantallas', () {
    Finder search() => find.byKey(const Key('person-search'));

    /// Nombres de [_names] que se ven en pantalla.
    Set<String> visible() => {
      for (final name in _names)
        if (find.text(name).evaluate().isNotEmpty) name,
    };

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(search(), text);
      await settle(tester);
    }

    Future<Map<String, Set<String>>> resultsOn(
      WidgetTester tester,
      String route,
      List<String> queries,
    ) async {
      final w = await seedRdm2cWorld(tester, 'rdm2-c-buscar-${route.length}');
      final c = await pumpModeApp(tester, w.database);
      c.read(routerProvider).go(route);
      await waitFor(tester, search());
      await settle(tester);
      final results = <String, Set<String>>{};
      for (final query in queries) {
        await type(tester, query);
        results[query] = visible();
      }
      return results;
    }

    const queries = ['ro', 'maria  quispe', ' juan ', 'PEÑA', 'xyz', ''];
    final expected = {
      'ro': {rdm2cOwnerName},
      'maria  quispe': {rdm2cLongName},
      ' juan ': {rdm2cThirdName},
      'PEÑA': {rdm2cQuietName},
      'xyz': <String>{},
      '': _names.toSet(),
    };

    for (final route in ['/personas', '/liquidacion']) {
      testWidgets('$route: filtra la lista entera, también al titular, y '
          'dice cuando no hay resultados', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 4000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final results = await resultsOn(tester, route, queries);
        expect(results, expected);
      });
    }

    testWidgets('sin resultados: mensaje claro; «Borrar búsqueda» vuelve a '
        'mostrar a todos', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final w = await seedRdm2cWorld(tester, 'rdm2-c-buscar-vacio');
      final c = await pumpModeApp(tester, w.database);
      c.read(routerProvider).go('/liquidacion');
      await waitFor(tester, search());
      await settle(tester);
      await type(tester, 'xyz');
      expect(find.byKey(const Key('person-search-empty')), findsOneWidget);
      expect(find.text('Ninguna persona coincide con «xyz».'), findsOneWidget);
      expect(find.byKey(const Key('own-consumption-card')), findsNothing);
      await tester.tap(find.byKey(const Key('person-search-clear')));
      await settle(tester);
      expect(visible(), _names.toSet());
    });

    testWidgets('Cuentas: la búsqueda se conserva al cambiar la campaña y '
        'las cifras siguen el filtro', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final w = await seedRdm2cWorld(tester, 'rdm2-c-buscar-campana');
      final c = await pumpModeApp(tester, w.database);
      c.read(routerProvider).go('/liquidacion');
      await waitFor(tester, search());
      await settle(tester);
      await type(tester, 'juan');
      expect(visible(), {rdm2cThirdName});
      expect(
        find.textContaining('Deuda pendiente por origen · Invierno 2026'),
        findsOneWidget,
      );
      await tester.tap(find.text('Invierno 2026').first);
      await settle(tester);
      await tester.tap(find.text('Todas las campañas').last);
      await settle(tester);
      expect(visible(), {rdm2cThirdName});
      expect(tester.widget<TextField>(search()).controller!.text, 'juan');
      expect(
        find.textContaining('Deuda pendiente por origen · Invierno 2026'),
        findsNothing,
      );
      expect(find.text('Saldo neto · todas las campañas'), findsOneWidget);
    });
  });
}
