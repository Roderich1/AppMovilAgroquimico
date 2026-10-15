// Overrides de la política de activación (#76) para pruebas de la app.
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/owner_binding_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/installation_access.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'f04_mode_fixtures.dart';

/// Para pruebas de pantallas que no tratan la activación: fija una
/// instalación ya activada del Member A. Es explícito a propósito; sin este
/// override la app aplica la política real y falla cerrada.
Override activatedInstallationForTests() =>
    installationAccessProvider.overrideWith(
      () => FixedInstallationAccess(
        InstallationAccessState.activated,
        scope: memberA,
      ),
    );

Override fixedInstallationAccess(
  InstallationAccessState state, {
  OwnerScope? scope,
}) => installationAccessProvider.overrideWith(
  () => FixedInstallationAccess(state, scope: scope),
);

/// Overrides del arranque real: ámbito de la sesión legible y referencia de
/// la instalación actual. El controlador real calcula el estado con la base.
List<Override> startupAccessOverrides({
  OwnerScope? sessionScope,
  String? installationRef,
  Future<OwnerScope?> Function()? rereadSession,
}) => [
  startupSessionScopeProvider.overrideWithValue(sessionScope),
  installationRefProvider.overrideWithValue(
    installationRef ?? installationHere,
  ),
  sessionScopeReaderProvider.overrideWithValue(
    rereadSession ?? () async => sessionScope,
  ),
];

/// Deja la base como la de una instalación ya activada en ESTA instalación:
/// titular familiar vinculado al Member A.
Future<OwnerBinding> seedActivatedInstallation(
  AppDatabase database, {
  OwnerScope scope = memberA,
  String? installationRef,
}) => OwnerBindingStore(database).bindNewPerson(
  name: 'Titular',
  scope: scope,
  installationRef: installationRef ?? installationHere,
);
