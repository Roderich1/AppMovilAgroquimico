import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/purchases_screen.dart';
import 'package:agroquimicos/presentation/screens/settlements_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Un error nunca debe presentarse como "cargando" ni como "sin datos".
///
/// STAB-004: `SettlementsScreen` no tenía rama de error y `PurchasesScreen` la
/// tenía después de comprobar `hasData`, lo que la hacía inalcanzable. En ambos
/// casos un fallo dejaba la pantalla girando indefinidamente.
class _FailingRepository extends AgroRepository {
  _FailingRepository(super.appDatabase);

  static const message = 'Fallo simulado de consulta';

  @override
  Future<List<Map<String, Object?>>> campaigns() async =>
      throw BusinessRuleException(message);

  @override
  Future<List<Map<String, Object?>>> purchases({int limit = 200}) async =>
      throw BusinessRuleException(message);
}

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

  Future<AppDatabase> seededDatabase(WidgetTester tester) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repo = AgroRepository(database);
    await repo.addPerson(name: 'Familiar', role: PersonRole.family);
    return database;
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    AgroRepository repo,
  ) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'STAB-004: un fallo en liquidación muestra el error, no un spinner eterno',
    (tester) async {
      final database = (await tester.runAsync(() => seededDatabase(tester)))!;
      await pumpScreen(
        tester,
        const SettlementsScreen(),
        _FailingRepository(database),
      );

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'Un error no debe quedarse mostrando el indicador de carga.',
      );
      expect(
        find.textContaining(_FailingRepository.message),
        findsOneWidget,
        reason: 'El mensaje de negocio debe llegar al usuario.',
      );
    },
  );

  testWidgets(
    'STAB-004: un fallo en compras muestra el error, no un spinner eterno',
    (tester) async {
      final database = (await tester.runAsync(() => seededDatabase(tester)))!;
      await pumpScreen(
        tester,
        const PurchasesScreen(),
        _FailingRepository(database),
      );

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'Un error no debe quedarse mostrando el indicador de carga.',
      );
      expect(
        find.textContaining(_FailingRepository.message),
        findsOneWidget,
        reason: 'El mensaje de negocio debe llegar al usuario.',
      );
    },
  );

  testWidgets(
    'el mensaje mostrado pasa por friendlyError (sin prefijo técnico)',
    (tester) async {
      final database = (await tester.runAsync(() => seededDatabase(tester)))!;
      await pumpScreen(
        tester,
        const PurchasesScreen(),
        _FailingRepository(database),
      );

      expect(
        find.textContaining('BusinessRuleException'),
        findsNothing,
        reason:
            'friendlyError debe retirar el prefijo de la excepción antes de '
            'mostrarla al usuario.',
      );
    },
  );
}
