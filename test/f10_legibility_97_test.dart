// #97 (RNF-08, A1-F): con la fuente al 100 % y al 130 %, en el ancho del POCO
// (392 dp) y en 360 dp, los títulos de «Sincronización» y «Nueva compra» y el
// nombre de la persona de una asignación se leen enteros: sin cortes dentro de
// una palabra ni puntos suspensivos. Las acciones siguen visibles y con su
// texto; no se reduce la escala.
//
// Se mide con Roboto, la fuente de Material en Android, tomada del SDK de
// Flutter: con la fuente de prueba por defecto cada glifo es un cuadrado del
// tamaño de la letra y «Sincronización» no cabría en ninguna disposición.
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/sync/sync_outbox_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/purchase_form_screen.dart';
import 'package:agroquimicos/presentation/screens/sync_status_screen.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:agroquimicos/services/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f05_sync_fixtures.dart';

void main() {
  sqfliteFfiInit();

  const widths = [360.0, 392.0];
  const scales = [1.0, 1.3];

  /// Carpeta de fuentes de Material del SDK de Flutter.
  Directory materialFonts() {
    final candidates = <Directory>[
      if (Platform.environment['FLUTTER_ROOT'] case final root?)
        Directory('$root/bin/cache/artifacts/material_fonts'),
    ];
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      candidates.add(Directory('${dir.path}/artifacts/material_fonts'));
      candidates.add(
        Directory('${dir.path}/bin/cache/artifacts/material_fonts'),
      );
      dir = dir.parent;
    }
    return candidates.firstWhere(
      (d) => File('${d.path}/roboto-regular.ttf').existsSync(),
      orElse: () => throw StateError(
        'No se encontró Roboto en el SDK de Flutter (material_fonts).',
      ),
    );
  }

  setUpAll(() async {
    final dir = materialFonts();
    final loader = FontLoader('Roboto');
    for (final name in ['regular', 'medium', 'bold']) {
      final bytes = File('${dir.path}/roboto-$name.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Widget scaled(double scale, Widget home) => MaterialApp(
    theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  );

  /// El texto ocupa una sola línea (no se parte, ni dentro de una palabra) y
  /// no se trunca con puntos suspensivos.
  void expectWhole(WidgetTester tester, Finder text, String reason) {
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final length = paragraph.text.toPlainText().length;
    final lines = {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: length),
      ))
        box.top.round(),
    };
    expect(paragraph.didExceedMaxLines, isFalse, reason: '$reason: truncado');
    expect(lines, hasLength(1), reason: '$reason: partido en varias líneas');
  }

  void expectOnScreen(WidgetTester tester, Finder finder, double width) {
    final rect = tester.getRect(finder);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(width));
  }

  for (final width in widths) {
    for (final scale in scales) {
      final label = '${width.toInt()} dp, fuente ${(scale * 100).round()} %';

      testWidgets('Sincronización: título entero y «Sincronizar ahora» '
          'visible ($label)', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final seeded = (await tester.runAsync(
          () => seedSyncFixture(path: inMemoryDatabasePath),
        ))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(seeded.database),
              syncOutboxStoreProvider.overrideWithValue(
                SyncOutboxStore(seeded.database),
              ),
            ],
            child: scaled(scale, const Scaffold(body: SyncStatusScreen())),
          ),
        );
        await settle(tester);
        expectWhole(tester, find.text('Sincronización'), 'título');
        expectWhole(tester, find.text('Sincronizar ahora'), 'acción');
        expectOnScreen(tester, find.text('Sincronizar ahora'), width);
        await tester.runAsync(seeded.database.close);
      });

      testWidgets('Nueva compra: título entero, «Confirmar compra» visible y '
          'el nombre de la asignación sin truncar ($label)', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repo = (await tester.runAsync(() async {
          final database = AppDatabase(
            factory: databaseFactoryFfi,
            path: inMemoryDatabasePath,
          );
          final repo = AgroRepository(database);
          await repo.addPerson(
            name: 'Titular F1 Mamani',
            role: PersonRole.family,
          );
          await repo.addPerson(name: 'Administrador', role: PersonRole.admin);
          await repo.addCampaign(
            name: 'Invierno 2026',
            start: DateTime.utc(2026, 1, 1),
          );
          await repo.addProduct(name: 'Glifosato');
          await repo.addSupplier(name: 'Chicho');
          return repo;
        }))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [repositoryProvider.overrideWithValue(repo)],
            child: scaled(scale, const PurchaseFormScreen()),
          ),
        );
        await settle(tester);
        expectWhole(tester, find.text('Nueva compra'), 'título');
        expectWhole(tester, find.text('Confirmar compra'), 'acción');
        expectOnScreen(tester, find.text('Confirmar compra'), width);

        final person = find.byWidgetPredicate(
          (w) =>
              w is AdaptiveEntityPicker<Map<String, Object?>> &&
              w.label == 'Persona',
        );
        final picker = tester
            .widget<AdaptiveEntityPicker<Map<String, Object?>>>(person);
        picker.onChanged(
          picker.items.firstWhere((p) => p['name'] == 'Titular F1 Mamani'),
        );
        await settle(tester);
        expectWhole(
          tester,
          find.descendant(of: person, matching: find.text('Titular F1 Mamani')),
          'persona',
        );
        await tester.runAsync(repo.appDatabase.close);
      });
    }
  }
}
