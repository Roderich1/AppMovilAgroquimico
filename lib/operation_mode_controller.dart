// Modalidad vigente para la presentación (MODE-02/MODE-03, #25/#26).
//
// Sólo decide qué se muestra: navegación, atajos y selectores. Las reglas
// siguen en el repositorio, que vuelve a leer la modalidad dentro de la
// transacción de cada escritura. La carga el router de la app al crearse y se
// recarga al cambiar la modalidad (pantalla de modo de uso, elección del
// titular) y al sustituir la base (restauración), de modo que las pantallas
// abiertas reflejan el cambio sin reiniciar.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/operation_mode_store.dart';
import 'domain/operation_mode.dart';

class OperationModeController extends Notifier<OperationMode?> {
  int _generation = 0;

  /// No lee la base por sí mismo: quien monta la app llama a [reload]. Una
  /// pantalla montada sin el router de la app ve `null`.
  @override
  OperationMode? build() => null;

  /// Relee la modalidad de la base actual. `null` mientras no se conoce: la
  /// presentación mantiene entonces la del modo compartido, que es la
  /// modalidad por defecto, y el repositorio sigue aplicando la real.
  Future<OperationMode?> reload() async {
    final generation = ++_generation;
    try {
      final mode = await OperationModeStore(
        ref.read(repositoryProvider).appDatabase,
      ).current();
      // Una lectura anterior que termina después no pisa a la más reciente,
      // y nada se escribe si el proveedor ya se descartó.
      if (ref.mounted && generation == _generation) state = mode;
      return mode;
    } on Object {
      return ref.mounted ? state : null;
    }
  }
}

final operationModeProvider =
    NotifierProvider<OperationModeController, OperationMode?>(
      OperationModeController.new,
    );

/// Rutas que sólo existen en el inventario compartido (RF-11, CU-08).
const sharedOnlyRoutes = {'/transferencias', '/transferencias/nueva'};

/// Compuerta de navegación de la modalidad (#26): en inventario propio una
/// ruta de transferencias, aunque se abra directamente, vuelve a Operaciones.
String? operationModeRedirect(OperationMode? mode, String path) =>
    mode == OperationMode.personal && sharedOnlyRoutes.contains(path)
    ? '/operaciones'
    : null;
