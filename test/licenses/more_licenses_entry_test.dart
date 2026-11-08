// «Más › Licencias» (F09): entrada secundaria, sin tarjeta, que abre la página
// de licencias con los componentes de la voz local; Atrás vuelve a «Más».
import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/licenses/third_party_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_ui_harness.dart';

void main() {
  sqfliteFfiInit();

  setUp(() {
    LicenseRegistry.reset();
    resetThirdPartyLicensesForTest();
  });
  tearDown(LicenseRegistry.reset);

  testWidgets('Más › Licencias abre la página con Vosk y lo que incluye, JNA, '
      'whisper.cpp, ggml y los modelos', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final s = await activatedHousehold(tester, 'licencias');
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).go('/operaciones');
    await settle(tester);
    await tester.tap(find.text('Más'));
    await settle(tester);

    final entry = find.byKey(const Key('more-licenses'));
    expect(entry, findsOneWidget);
    expect(find.text('Licencias'), findsOneWidget);
    // Discreta: no es una tarjeta más entre los accesos de «Más».
    expect(find.ancestor(of: entry, matching: find.byType(Card)), findsNothing);

    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await waitFor(tester, find.text('ggml'));
    expect(find.byType(LicensePage), findsOneWidget);
    for (final name in [
      'Vosk (vosk-android 0.3.75)',
      'Kaldi (incluido en Vosk)',
      'OpenFST (incluido en Vosk)',
      'OpenBLAS 0.3.20 (incluido en Vosk)',
      'CLAPACK 3.2.1 y libf2c (incluidos en Vosk)',
      'JNA (Java Native Access 5.18.1)',
      'whisper.cpp',
      'ggml',
      'Modelo de voz Vosk vosk-model-small-es-0.42',
      'Modelo de voz Whisper (OpenAI), formato ggml',
      'JUnit 4.12 (vía integration_test, compilación profile)',
      'AndroidX Test y Espresso (vía integration_test, compilación profile)',
      'Animal Sniffer Annotations 1.18 (vía integration_test, compilación profile)',
    ]) {
      final list = find
          .descendant(
            of: find.byType(LicensePage),
            matching: find.byType(Scrollable),
          )
          .first;
      // La página ordena los paquetes por nombre: cada búsqueda parte de
      // arriba.
      tester.state<ScrollableState>(list).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(find.text(name), 100, scrollable: list);
      expect(find.text(name), findsOneWidget, reason: name);
    }

    // La flecha de la propia página de licencias (la app tiene otras).
    await tester.tap(
      find.descendant(
        of: find.byType(LicensePage),
        matching: find.byType(BackButton),
      ),
    );
    await settle(tester);
    expect(find.byType(LicensePage), findsNothing);
    expect(find.text('Administrar datos'), findsOneWidget);
  });
}
