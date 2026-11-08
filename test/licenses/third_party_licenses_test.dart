// Avisos de licencia de la voz local (F09): cada texto declarado existe, está
// en los assets de pubspec, coincide byte a byte con el SHA-256 que registra
// assets/licenses/README.md, y la página de licencias muestra cada componente
// con su texto.
import 'dart:io';

import 'package:agroquimicos/licenses/third_party_licenses.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _components = [
  'Vosk (vosk-android 0.3.75)',
  'JNA (Java Native Access 5.18.1)',
  'whisper.cpp',
  'ggml',
  'Modelo de voz Vosk vosk-model-small-es-0.42',
  'Modelo de voz Whisper (OpenAI), formato ggml',
];

/// Rutas `assets/licenses/...` y su SHA-256 según la tabla del README: la
/// primera columna es la ruta y la columna «SHA-256» es la penúltima.
Map<String, String> _readmeHashes() {
  final hashes = <String, String>{};
  for (final line in File('assets/licenses/README.md').readAsLinesSync()) {
    if (!line.startsWith('| `assets/licenses/')) continue;
    final cells = line.split('|').map((c) => c.trim()).toList();
    // ['', archivo, componente, fuente, versión, sha, bytes, '']
    hashes[cells[1].replaceAll('`', '')] = cells[cells.length - 3].replaceAll(
      '`',
      '',
    );
  }
  return hashes;
}

/// Carpetas de `assets/licenses/` declaradas en pubspec.yaml.
Set<String> _declaredDirs() => {
  for (final line in File('pubspec.yaml').readAsLinesSync())
    if (RegExp(r'^\s+- (assets/licenses/\S+/)\s*$').firstMatch(line)
        case final m?)
      m.group(1)!,
};

Future<void> _pumpLicenses(WidgetTester tester, Finder until) async {
  for (var i = 0; i < 100 && until.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  final assets = [for (final n in thirdPartyNotices) ...n.assets];

  test('los componentes son los de la APK con voz, sin repetir', () {
    expect([for (final n in thirdPartyNotices) n.package], _components);
    expect(assets.toSet().length, assets.length);
  });

  test('cada texto declarado existe, no está vacío y está en pubspec', () {
    final dirs = _declaredDirs();
    for (final path in assets) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: path);
      expect(file.lengthSync(), greaterThan(0), reason: path);
      expect(dirs, contains('${file.parent.path}/'), reason: path);
    }
  });

  test('cada texto coincide con el SHA-256 del README y no sobra ninguno', () {
    final hashes = _readmeHashes();
    expect(hashes.keys.toSet(), assets.toSet());
    for (final path in assets) {
      final digest = sha256.convert(File(path).readAsBytesSync()).toString();
      expect(digest, hashes[path], reason: path);
    }
    final onDisk = Directory('assets/licenses')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where(
          (p) => !p.endsWith('/README.md') && !p.endsWith('.gitattributes'),
        )
        .toSet();
    expect(onDisk, assets.toSet());
  });

  test(
    'JNA: se indica la licencia elegida (Apache 2.0) y se incluye libffi',
    () {
      final jna = thirdPartyNotices.firstWhere(
        (n) => n.package.startsWith('JNA'),
      );
      expect(jna.note, contains('Agrocuentas la usa bajo Apache 2.0'));
      expect(jna.assets, contains('assets/licenses/jna/AL2.0'));
      expect(jna.assets, contains('assets/licenses/jna/libffi/LICENSE'));
      expect(jna.assets.any((a) => a.contains('LGPL')), isFalse);
    },
  );

  group('página de licencias', () {
    setUp(() {
      LicenseRegistry.reset();
      resetThirdPartyLicensesForTest();
    });
    tearDown(LicenseRegistry.reset);

    testWidgets('muestra cada componente y su texto oficial', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAgroLicenses(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await _pumpLicenses(tester, find.text(_components.last));
      expect(find.byType(LicensePage), findsOneWidget);
      for (final name in _components) {
        await tester.scrollUntilVisible(
          find.text(name),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(name), findsOneWidget, reason: name);
      }

      // El texto de JNA: la nota, la licencia doble, Apache 2.0 y libffi.
      await tester.scrollUntilVisible(
        find.text(_components[1]),
        -100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(_components[1]));
      await _pumpLicenses(
        tester,
        find.textContaining('Agrocuentas la usa bajo Apache 2.0'),
      );
      expect(
        find.textContaining('Agrocuentas la usa bajo Apache 2.0'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Apache-2.0 OR LGPL-2.1-or-later'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.textContaining('Version 2.0, January 2004'),
        400,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 200,
      );
      expect(find.textContaining('Version 2.0, January 2004'), findsWidgets);
      // El aviso de libffi va al final: se desplaza el detalle hasta él.
      await tester.scrollUntilVisible(
        find.textContaining('libffi - Copyright'),
        400,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 200,
      );
      expect(find.textContaining('libffi - Copyright'), findsOneWidget);
    });
  });
}
