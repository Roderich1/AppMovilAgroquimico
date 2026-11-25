enum SafetyCopyState {
  /// Se está preparando o usando: protegida.
  preparing,

  /// La restauración terminó y se mantiene.
  finalized,

  /// La restauración falló, el rollback terminó y se comprobó que la base
  /// activa y las fotografías volvieron a ser las anteriores
  /// (`BackupService`, F08-PREV-01). También la que el titular confirmó
  /// expresamente con [RestoreSafetyCopies.confirmRecovery].
  rolledBack,

  /// Encontrada en preparación sin una restauración en curso: el proceso
  /// murió a medias o el rollback falló. También la de un rollback cuyo
  /// estado recuperado no coincide o no se pudo comprobar. Protegida y
  /// bloquea otra restauración hasta una acción expresa.
  interrupted,

  /// Era interrumpida y el titular decidió seguir con los datos actuales
  /// sin confirmar la recuperación ([RestoreSafetyCopies.continueWithCurrentData]):
  /// ya no bloquea otra restauración, pero sigue protegida hasta que la
  /// confirme (F08-PREV-01).
  retained,
}

class SafetyCopyEntry {
  SafetyCopyEntry({
    required this.id,
    required this.createdAt,
    required this.state,
    this.resolvedAt,
  });

  final String id;
  final DateTime createdAt;
  SafetyCopyState state;
  DateTime? resolvedAt;

  /// Nombres relativos a la carpeta `previo/`.
  String get databaseName => '$id.db';
  String get invoicesName => '$id.facturas';

  bool get isProtected =>
      state == SafetyCopyState.preparing ||
      state == SafetyCopyState.interrupted ||
      state == SafetyCopyState.retained;

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'state': state.name,
    'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
  };

  static SafetyCopyEntry fromJson(Map<String, Object?> json) => SafetyCopyEntry(
    id: json['id']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    state: SafetyCopyState.values.byName(json['state']! as String),
    resolvedAt: json['resolvedAt'] == null
        ? null
        : DateTime.parse(json['resolvedAt']! as String),
  );
}

/// Copia preparada para una restauración en curso.
class SafetyCopySlot {
  const SafetyCopySlot(this.entry, this.databasePath, this.invoicesPath);
  final SafetyCopyEntry entry;
  final String databasePath;
  final String invoicesPath;
}

/// No se puede restaurar sin arriesgar una copia indispensable.
class RestoreBlockedException implements Exception {
  const RestoreBlockedException(this.message);
  final String message;

  /// No distingue una restauración cortada de un rollback sin recuperación
  /// comprobada: si no se pudo guardar el estado de éste, el mantenimiento
  /// los deja iguales. Por eso no dice que los datos estén bien. Tampoco
  /// afirma que haya copia: una entrada puede no tenerla (el proceso murió
  /// antes de escribirla, o no había nada que copiar).
  static const unresolved = RestoreBlockedException(
    'Una restauración anterior no terminó o no pudimos confirmar que sus '
    'datos anteriores se recuperaron correctamente. Si se guardó una copia '
    'de sus datos de entonces, sigue protegida. Antes de restaurar otro '
    'respaldo, elija qué hacer en «Copias previas a restauraciones». No se '
    'cambiaron sus datos.',
  );

  static const unreadableRegistry = RestoreBlockedException(
    'No se pudo leer el registro de copias previas a restauraciones, así que '
    'no se puede saber cuáles son indispensables. No se restauró nada; '
    'revíselo en «Copias previas a restauraciones».',
  );

  @override
  String toString() => message;
}

class SafetyCopyMaintenance {
  const SafetyCopyMaintenance({
    this.expired = const [],
    this.overCap = const [],
    this.interrupted = const [],
  });

  /// Retiradas por superar el plazo.
  final List<String> expired;

  /// Retiradas por superar la cota.
  final List<String> overCap;

  /// Pasadas de «en preparación» a «interrumpida» en esta pasada.
  final List<String> interrupted;
}
