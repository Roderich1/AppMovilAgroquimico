import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Retirada de la copia de la estimación que no se pudo registrar en SQLite
/// (F12-EST-07-MOB, #164). Si SQLite no admite ni la escritura pequeña de la
/// retirada, la marca queda en el almacenamiento seguro del teléfono, el
/// mismo que guarda la sesión: mientras exista, no se muestra ninguna cifra,
/// tampoco tras cerrar y volver a abrir la app. Se quita al completar la
/// retirada en SQLite. No guarda identificadores ni credenciales: sólo «hay
/// una retirada pendiente».
abstract interface class EstimationRetirementMarker {
  Future<bool> isPending();
  Future<void> setPending();
  Future<void> clear();
}

class SecureStorageEstimationRetirementMarker
    implements EstimationRetirementMarker {
  const SecureStorageEstimationRetirementMarker();

  static const androidNamespace = 'agrocuentas_estimation_v1';
  static const _entry = 'retirement_pending';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: androidNamespace,
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
  );

  @override
  Future<bool> isPending() async => await _storage.read(key: _entry) != null;

  @override
  Future<void> setPending() => _storage.write(key: _entry, value: '1');

  @override
  Future<void> clear() => _storage.delete(key: _entry);
}
