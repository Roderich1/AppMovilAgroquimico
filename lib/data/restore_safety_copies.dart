// Copias `.previo` de la base anterior a cada restauración y su limpieza
// local (F08-ADR-003 §7; parámetros ratificados por Roderich el 2026-10-23).
//
// Cada copia tiene una entrada en un registro durable (`registro.json`,
// escrito con .tmp + flush + rename) dentro de `<databases>/previo/`, la
// carpeta privada de la app, excluida del auto-backup de Android. La
// protección sale sólo de los estados escritos en disco, nunca del nombre de
// un archivo ni de suponer que un proceso anterior terminó.
//
// Reglas de mantenimiento, por separado:
//   - plazo: se retira toda copia finalizada con más de [maxAge] (7 días);
//   - cota: si quedan más de [maxResolved] (2) finalizadas, se retiran las
//     más antiguas.
// La cota no garantiza conservar 7 días y el plazo retira aunque haya menos
// de 2. Nunca se retiran las copias protegidas (en preparación o de una
// restauración interrumpida) ni la base activa. Retirar borra exactamente los
// archivos que nombra la entrada; nunca por patrones.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

enum SafetyCopyState {
  /// Se está preparando o usando: protegida.
  preparing,

  /// La restauración terminó y se mantiene.
  finalized,

  /// La restauración falló y el rollback terminó: la base activa volvió a
  /// ser la anterior.
  rolledBack,

  /// Encontrada en preparación sin una restauración en curso: el proceso
  /// murió a medias o el rollback falló. Protegida hasta una acción expresa.
  interrupted,
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
      state == SafetyCopyState.interrupted;

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

  static const unresolved = RestoreBlockedException(
    'Hay una restauración anterior que no terminó y se conserva la copia de '
    'sus datos de entonces. Lo más probable es que sus datos actuales estén '
    'bien; si es así, elija «Mantener los actuales» en «Copias previas a '
    'restauraciones» y vuelva a intentarlo. No se modificó nada.',
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

class RestoreSafetyCopies {
  RestoreSafetyCopies(
    this._databasePath, {
    DateTime Function()? clock,
    this.maxResolved = 2,
    this.maxAge = const Duration(days: 7),
  }) : _clock = clock ?? DateTime.now;

  /// Ruta de la base activa; `previo/` está en su misma carpeta.
  final Future<String> Function() _databasePath;
  final DateTime Function() _clock;
  final int maxResolved;
  final Duration maxAge;

  /// Estado del proceso por carpeta `previo/`, compartido por todas las
  /// instancias: `BackupService` (y con él esta clase) se vuelve a crear si
  /// cambia su proveedor, y una instancia nueva no debe tomar por
  /// interrumpida la restauración que otra tiene en curso ni pisar sus
  /// escrituras del registro.
  static final Map<String, _ProcessState> _processes = {};

  _ProcessState? _process;

  /// Sólo pruebas: simula que la app se cerró y se volvió a abrir.
  @visibleForTesting
  static void forgetProcessStateForTesting() => _processes.clear();

  /// Entradas en preparación por una restauración de este proceso. Sólo
  /// éstas quedan fuera de la conversión a «interrumpida». Válido dentro de
  /// [_serial].
  Set<String> get _inProcess => _process!.inProcess;

  /// Las operaciones sobre el registro se encadenan, en todo el proceso: un
  /// mantenimiento lanzado por la interfaz nunca pisa la escritura de una
  /// restauración en curso.
  Future<T> _serial<T>(Future<T> Function() run) async {
    final state = _process ??= _processes.putIfAbsent(
      p.normalize((await directory()).path),
      _ProcessState.new,
    );
    final result = state.tail.then((_) => run());
    state.tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  static const _registryName = 'registro.json';
  static const legacyMarker = '.previo-';

  Future<Directory> directory() async =>
      Directory(p.join(p.dirname(await _databasePath()), 'previo'));

  Future<File> _registry() async =>
      File(p.join((await directory()).path, _registryName));

  /// null si el registro existe pero no se puede leer.
  Future<List<SafetyCopyEntry>?> _tryLoad() async {
    final file = await _registry();
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString()) as Map;
      if (json['version'] != 1) return null;
      return [
        for (final item in json['entries']! as List)
          SafetyCopyEntry.fromJson((item as Map).cast<String, Object?>()),
      ];
    } on Object {
      return null;
    }
  }

  Future<List<SafetyCopyEntry>> _load() async {
    final entries = await _tryLoad();
    if (entries == null) throw RestoreBlockedException.unreadableRegistry;
    return entries;
  }

  Future<void> _save(List<SafetyCopyEntry> entries) async {
    final dir = await directory();
    await dir.create(recursive: true);
    final file = await _registry();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': 1,
        'entries': [for (final e in entries) e.toJson()],
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }

  /// Todas las entradas, de la más reciente a la más antigua.
  Future<List<SafetyCopyEntry>> entries() => _serial(() async {
    final list = await _load();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  });

  /// ¿Se puede leer el registro?
  Future<bool> registryReadable() async => await _tryLoad() != null;

  /// Comprueba que se puede empezar otra restauración y aplica antes el
  /// mantenimiento. Lanza [RestoreBlockedException] sin tocar nada si hay
  /// una copia protegida sin resolver o el registro es ilegible.
  Future<void> ensureCanStartRestore() => _serial(() async {
    await _maintain();
    final list = await _load();
    // También una en preparación que no es de una restauración en curso en
    // este proceso: su paso a interrumpida pudo no guardarse.
    if (list.any(
      (e) =>
          e.state == SafetyCopyState.interrupted ||
          (e.state == SafetyCopyState.preparing && !_inProcess.contains(e.id)),
    )) {
      throw RestoreBlockedException.unresolved;
    }
  });

  /// Registra la copia **antes** de escribirla: si el proceso muere a mitad,
  /// la entrada ya existe y queda protegida.
  Future<SafetyCopySlot> begin() => _serial(() async {
    final list = await _load();
    final now = _clock().toUtc();
    var id =
        'copia.previo-${now.toIso8601String().replaceAll(RegExp('[:.]'), '-')}';
    for (var n = 1; list.any((e) => e.id == id); n++) {
      id = '$id-$n';
    }
    final entry = SafetyCopyEntry(
      id: id,
      createdAt: now,
      state: SafetyCopyState.preparing,
    );
    _inProcess.add(id);
    await _save([...list, entry]);
    final dir = (await directory()).path;
    return SafetyCopySlot(
      entry,
      p.join(dir, entry.databaseName),
      p.join(dir, entry.invoicesName),
    );
  });

  /// La preparación falló antes de sustituir nada: la copia sobra.
  Future<void> discard(SafetyCopySlot slot) => _serial(() async {
    await _removeFiles(slot.entry);
    final list = await _load();
    list.removeWhere((e) => e.id == slot.entry.id);
    await _save(list);
    _inProcess.remove(slot.entry.id);
  });

  Future<void> _resolve(String id, SafetyCopyState state) async {
    final list = await _load();
    for (final entry in list) {
      if (entry.id == id) {
        entry
          ..state = state
          ..resolvedAt = _clock().toUtc();
      }
    }
    await _save(list);
    _inProcess.remove(id);
  }

  Future<void> markFinalized(SafetyCopySlot slot) =>
      _serial(() => _resolve(slot.entry.id, SafetyCopyState.finalized));

  Future<void> markRolledBack(SafetyCopySlot slot) =>
      _serial(() => _resolve(slot.entry.id, SafetyCopyState.rolledBack));

  /// El rollback falló: la copia es indispensable.
  /// Aunque no se pueda guardar el estado, deja de contar como restauración
  /// en curso: así bloquea igualmente la siguiente ([ensureCanStartRestore]).
  Future<void> markInterrupted(SafetyCopySlot slot) => _serial(() async {
    try {
      final list = await _load();
      for (final entry in list) {
        if (entry.id == slot.entry.id) {
          entry.state = SafetyCopyState.interrupted;
        }
      }
      await _save(list);
    } finally {
      _inProcess.remove(slot.entry.id);
    }
  });

  /// Acción expresa del titular sobre una copia interrumpida: mantiene los
  /// datos actuales. La copia pasa a las reglas normales desde ahora.
  Future<void> keepCurrentData(String id) => _serial(() async {
    final list = await _load();
    final entry = list.where((e) => e.id == id).firstOrNull;
    if (entry == null || entry.state != SafetyCopyState.interrupted) return;
    await _resolve(id, SafetyCopyState.rolledBack);
  });

  /// Oportunidad de mantenimiento: al abrir los respaldos, antes y después de
  /// restaurar, y en la limpieza expresa. Con el registro ilegible no hace
  /// nada (no se sabe qué es indispensable).
  Future<SafetyCopyMaintenance> maintain() => _serial(_maintain);

  Future<SafetyCopyMaintenance> _maintain() async {
    final list = await _tryLoad();
    if (list == null) return const SafetyCopyMaintenance();
    final now = _clock().toUtc();
    final interrupted = <String>[];
    for (final entry in list) {
      if (entry.state == SafetyCopyState.preparing &&
          !_inProcess.contains(entry.id)) {
        entry.state = SafetyCopyState.interrupted;
        interrupted.add(entry.id);
      }
    }

    final expired = <SafetyCopyEntry>[];
    for (final entry in list) {
      final resolvedAt = entry.resolvedAt;
      if (!entry.isProtected &&
          resolvedAt != null &&
          now.difference(resolvedAt) > maxAge) {
        expired.add(entry);
      }
    }
    final remaining =
        list.where((e) => !e.isProtected && !expired.contains(e)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final overCap = remaining.skip(maxResolved).toList();

    final removed = {...expired, ...overCap};
    if (removed.isEmpty && interrupted.isEmpty) {
      return const SafetyCopyMaintenance();
    }
    // Primero se guarda el registro sin ellas y después se borran sus
    // archivos: un corte entre ambos deja archivos sin entrada, que se
    // tratan como heredados (nunca se borran solos), no entradas sin copia.
    await _save(list.where((e) => !removed.contains(e)).toList());
    for (final entry in removed) {
      await _removeFiles(entry);
    }
    return SafetyCopyMaintenance(
      expired: [for (final e in expired) e.id],
      overCap: [for (final e in overCap) e.id],
      interrupted: interrupted,
    );
  }

  Future<void> _removeFiles(SafetyCopyEntry entry) async {
    final dir = (await directory()).path;
    for (final entity in <FileSystemEntity>[
      File(p.join(dir, entry.databaseName)),
      File(p.join(dir, '${entry.databaseName}.part')),
      Directory(p.join(dir, entry.invoicesName)),
    ]) {
      try {
        if (await entity.exists()) await entity.delete(recursive: true);
      } on FileSystemException {
        // Se reintenta en el siguiente mantenimiento como heredada.
      }
    }
  }

  /// Copias sin entrada en el registro: las `<base>.previo-*.db` que dejaban
  /// las versiones anteriores junto a la base, y archivos de `previo/` que
  /// no nombra ninguna entrada. Nunca se borran solas.
  Future<List<FileSystemEntity>> unregistered() async {
    final database = await _databasePath();
    final found = <FileSystemEntity>[];
    final base = p.basename(database);
    final parent = Directory(p.dirname(database));
    if (await parent.exists()) {
      await for (final entity in parent.list()) {
        final name = p.basename(entity.path);
        if (entity is File &&
            name.startsWith('$base$legacyMarker') &&
            name.endsWith('.db')) {
          found.add(entity);
        }
      }
    }
    final list = await _tryLoad();
    final dir = await directory();
    if (list != null && await dir.exists()) {
      final known = {
        for (final e in list) ...[
          e.databaseName,
          '${e.databaseName}.part',
          e.invoicesName,
        ],
      };
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        // El registro, su temporal y los registros apartados (la única pista
        // de qué copias eran indispensables) nunca se ofrecen para borrar.
        if (known.contains(name) || name.startsWith(_registryName)) continue;
        found.add(entity);
      }
    }
    return found;
  }

  /// Borra una copia sin entrada que la persona eligió expresamente. Sólo
  /// admite lo que devuelve [unregistered].
  Future<void> deleteUnregistered(FileSystemEntity entity) => _serial(() async {
    final allowed = (await unregistered()).map((e) => e.path).toSet();
    if (!allowed.contains(entity.path)) return;
    await entity.delete(recursive: true);
  });

  /// El registro era ilegible y la persona decide empezar uno nuevo: se
  /// aparta (no se borra) y todas las copias pasan a «sin entrada», que
  /// nunca se borran solas.
  Future<void> setAsideUnreadableRegistry() => _serial(() async {
    if (await _tryLoad() != null) return;
    final file = await _registry();
    final stamp = _clock().toUtc().toIso8601String().replaceAll(':', '-');
    await file.rename('${file.path}.ilegible-$stamp');
    await _save([]);
  });
}

class _ProcessState {
  final Set<String> inProcess = {};
  Future<void> tail = Future.value();
}
