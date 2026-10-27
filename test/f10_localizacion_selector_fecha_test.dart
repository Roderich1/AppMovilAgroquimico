// E-13: el selector de fecha salía en inglés («Select date», «OK», «Previous
// month») porque la aplicación no registraba `flutter_localizations`. Ahora
// `AgroApp` fija `Locale('es')` con los delegados globales. Sólo cambian los
// textos de los widgets del sistema: las fechas se siguen interpretando y
// mostrando con `formatDate` / `localDay`, sin zona horaria ni unidades
// distintas.
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/domain/campaign_calendar.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/es_material_labels.dart';
import 'support/f04_app_access.dart';

void main() {
  testWidgets('la aplicación corre en español con los delegados globales', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activatedInstallationForTests()],
        child: const AgroApp(),
      ),
    );
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('es'));
    expect(app.supportedLocales, [const Locale('es')]);
    expect(
      app.localizationsDelegates,
      containsAll([
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ]),
    );
    final context = tester.element(find.byType(Navigator).first);
    expect(Localizations.localeOf(context), const Locale('es'));
  });

  testWidgets(
    'showDatePicker dentro de la aplicación muestra los botones en español',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [activatedInstallationForTests()],
          child: const AgroApp(),
        ),
      );
      await tester.pump();
      final es = await esMaterial();
      final context = tester.element(find.byType(Navigator).first);
      DateTime? picked;
      final pending = showDatePicker(
        context: context,
        initialDate: DateTime(2026, 10, 15),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      ).then((value) => picked = value);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(find.text(es.okButtonLabel), findsOneWidget);
      expect(find.text(es.cancelButtonLabel), findsOneWidget);
      expect(find.byTooltip(es.previousMonthTooltip), findsOneWidget);
      // Los rótulos ingleses del `MaterialApp` sin delegados ya no aparecen.
      expect(find.text('OK'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.byTooltip('Previous month'), findsNothing);

      // Elegir un día devuelve la misma fecha civil de siempre: el selector
      // no cambia cómo se interpreta ni cómo se muestra.
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('20'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text(es.okButtonLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await pending;
      expect(picked, DateTime(2026, 10, 20));
      expect(localDay(picked!), '2026-10-20');
      expect(formatDate(localDay(picked!)), '20/10/2026');
    },
  );

  test('formatDate no depende del locale de los widgets', () async {
    await esMaterial();
    expect(formatDate('2026-10-15'), '15/10/2026');
    expect(formatDate('2026-10-15T23:30:00.000Z'), isNot(contains('T')));
  });
}
