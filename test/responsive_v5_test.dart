import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/plan_form_screen.dart';
import 'package:agroquimicos/presentation/screens/transfer_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  for (final size in const [
    Size(360, 800),
    Size(393, 873),
    Size(600, 960),
    Size(800, 1280),
    Size(800, 420),
  ]) {
    testWidgets('formularios adaptables ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = AppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      final repo = AgroRepository(db);
      final person = await tester.runAsync(
        () => repo.addPerson(
          name: 'Persona con nombre largo',
          role: PersonRole.family,
        ),
      );
      await tester.runAsync(
        () => repo.addPerson(name: 'Otra persona', role: PersonRole.family),
      );
      await tester.runAsync(
        () => repo.addFarm(
          ownerId: person!,
          name: 'Chaco de prueba',
          areaM2: 800000,
        ),
      );
      await tester.runAsync(
        () =>
            repo.addCampaign(name: 'Primavera 2026', start: DateTime.utc(2026)),
      );
      await tester.runAsync(() => repo.addProduct(name: 'Glifosato'));
      Future<void> pump(Widget child) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [repositoryProvider.overrideWithValue(repo)],
            child: MaterialApp(home: child),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
      }

      await pump(const PlanFormScreen());
      await pump(const TransferFormScreen());
    });
  }
}
