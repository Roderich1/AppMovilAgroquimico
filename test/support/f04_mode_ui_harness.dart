// Arnés de la app real para MODE-02 y MODE-03 (#25, #26): base en archivo,
// router, repositorio y controlador de acceso reales. Se sustituyen la sesión
// segura, la identidad, el estado de la sesión remota y el transporte HTTP,
// que falla y cuenta cualquier petición: así se comprueba que la modalidad se
// consulta y se cambia sin conexión.
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:agroquimicos/operation_mode_controller.dart';
import 'package:agroquimicos/services/auth/existing_session_providers.dart';
import 'package:agroquimicos/services/auth/existing_session_startup.dart';
import 'package:agroquimicos/services/auth/first_activation_providers.dart';
import 'package:agroquimicos/services/auth/refresh_guard.dart';
import 'package:agroquimicos/services/auth/remote_session_coordinator.dart';
import 'package:agroquimicos/services/auth/remote_session_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'f04_app_access.dart';
import 'f04_mode_fixtures.dart';

/// Peticiones HTTP intentadas por la app durante una prueba.
class OfflineTransport {
  int requests = 0;

  late final client = MockClient((request) async {
    requests++;
    throw const SocketException('Sin conexión (prueba)');
  });
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
}

/// Avanza con E/S real (sqflite) hasta que no queden indicadores de carga.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (i >= 8 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// Monta la app real sobre [database]. Por defecto, instalación activada con
/// sesión legible de [memberA] en esta instalación.
Future<ProviderContainer> pumpModeApp(
  WidgetTester tester,
  AppDatabase database, {
  OfflineTransport? transport,
  ExistingSessionStartupState session =
      ExistingSessionStartupState.localSessionAvailable,
  OwnerScope? scope = memberA,
}) async {
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      existingSessionStartupProvider.overrideWithValue(session),
      ...startupAccessOverrides(sessionScope: scope),
      refreshGuardProvider.overrideWithValue(_ClearGuard()),
      remoteSessionProvider.overrideWith(_IdleRemote.new),
      if (transport != null)
        authHttpTransportProvider.overrideWithValue(transport.client),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AgroApp()),
  );
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (container.read(installationAccessProvider) != null &&
        container.read(operationModeProvider) != null) {
      break;
    }
  }
  await settle(tester);
  return container;
}

/// Ruta base del router. Con `push`, go_router no la cambia: una pantalla
/// apilada no aparece aquí.
String currentPath(ProviderContainer c) =>
    c.read(routerProvider).routeInformationProvider.value.uri.path;

/// Cambia la modalidad por el almacén, como haría otra pantalla, y avisa a
/// la presentación igual que lo hace la app.
Future<void> switchModeBehindScreen(
  WidgetTester tester,
  ProviderContainer c,
  AppDatabase database,
  OperationMode target,
) async {
  await tester.runAsync(() async {
    await OperationModeStore(database).apply(target, confirmed: true);
    await c.read(operationModeProvider.notifier).reload();
  });
  await settle(tester);
}

/// Hogar activado: titular vinculado a [memberA] en esta instalación, una
/// hermana (familiar) y un vecino (tercero), con un chaco cada familiar.
Future<({AppDatabase database, Household household})> activatedHousehold(
  WidgetTester tester,
  String name,
) async {
  final file = await tester.runAsync(() => tempDbPath(name));
  final database = openDb(file!);
  final household = await tester.runAsync(() async {
    final binding = await seedActivatedInstallation(database);
    final repo = AgroRepository(database);
    final relative = await repo.addPerson(
      name: 'Hermana',
      role: PersonRole.family,
    );
    final third = await repo.addPerson(
      name: 'Vecino',
      role: PersonRole.thirdParty,
    );
    final h = Household(repo, binding.personId, relative, third)
      ..supplier = await repo.addSupplier(name: 'Proveedor')
      ..campaign = await repo.addCampaign(
        name: 'Campaña 1',
        start: DateTime.utc(2026, 1, 1),
      )
      // La primera campaña queda activa.
      ..product = await repo.addProduct(name: 'Glifosato');
    h
      ..titularFarm = await repo.addFarm(
        ownerId: binding.personId,
        name: 'Chaco titular',
        areaM2: 10000,
      )
      ..relativeFarm = await repo.addFarm(
        ownerId: relative,
        name: 'Chaco hermana',
        areaM2: 5000,
      );
    return h;
  });
  return (database: database, household: household!);
}

class _ClearGuard implements RefreshGuard {
  @override
  Future<bool> isQuarantined() async => false;
  @override
  Future<void> quarantine() async {}
  @override
  Future<void> clear() async {}
}

class _IdleRemote extends RemoteSessionController {
  @override
  RemoteSessionState build() =>
      const RemoteSessionState(RemoteSessionPhase.idle);
}
