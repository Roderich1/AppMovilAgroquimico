// F08-ADR-003 §7: limpieza local de las copias `.previo` (dos copias
// finalizadas como máximo, plazo de siete días, protección de las
// indispensables), con reloj de prueba. Ratificado por Roderich el
// 2026-10-23 para el bloque sintético.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/backup_service.dart';
import 'package:agroquimicos/data/restore_safety_copies.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory workspace;
  late DateTime now;
  DateTime clock() => now;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_f08_previo_');
    now = DateTime.utc(2026, 10, 23, 12);
  });
  tearDown(() async {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows el motor puede retener un archivo; es temporal.
    }
  });

  String databasePath() => p.join(workspace.path, 'agro.db');
  Directory previo() => Directory(p.join(workspace.path, 'previo'));

  RestoreSafetyCopies copies() =>
      RestoreSafetyCopies(() async => databasePath(), clock: clock);

  /// Simula una restauración terminada en [at]: entrada y archivo.
  Future<SafetyCopySlot> finishedAt(
    RestoreSafetyCopies registry,
    DateTime at, {
    bool rolledBack = false,
  }) async {
    now = at;
    final slot = await registry.begin();
    await File(slot.databasePath).writeAsString('copia ${slot.entry.id}');
    if (rolledBack) {
      await registry.markRolledBack(slot);
    } else {
      await registry.markFinalized(slot);
    }
    return slot;
  }

  List<String> filesInPrevio() => previo().existsSync()
      ? (previo().listSync().map((e) => p.basename(e.path)).toList()..sort())
      : const [];

  group('reglas de mantenimiento', () {
    test('cota: con tres finalizadas el mismo día se retira la más antigua, aunque no tenga siete días', () async {
      final registry = copies();
      final day = DateTime.utc(2026, 10, 23, 8);
      final first = await finishedAt(registry, day);
      final second = await finishedAt(
        registry,
        day.add(const Duration(hours: 1)),
      );
      final third = await finishedAt(
        registry,
        day.add(const Duration(hours: 2)),
      );
      now = day.add(const Duration(hours: 3));
      final report = await registry.maintain();
      expect(report.overCap, [first.entry.id]);
      expect(report.expired, isEmpty);
      expect((await registry.entries()).map((e) => e.id), [
        third.entry.id,
        second.entry.id,
      ]);
      expect(File(first.databasePath).existsSync(), isFalse);
      expect(File(second.databasePath).existsSync(), isTrue);
      expect(File(third.databasePath).existsSync(), isTrue);
    });

    test('plazo: una sola finalizada se retira pasados siete días, aunque no se alcance la cota', () async {
      final registry = copies();
      final slot = await finishedAt(registry, DateTime.utc(2026, 10, 1));
      // Exactamente siete días: todavía no.
      now = DateTime.utc(2026, 10, 8);
      expect((await registry.maintain()).expired, isEmpty);
      expect(File(slot.databasePath).existsSync(), isTrue);
      now = DateTime.utc(2026, 10, 8, 0, 0, 1);
      final report = await registry.maintain();
      expect(report.expired, [slot.entry.id]);
      expect(report.overCap, isEmpty);
      expect(await registry.entries(), isEmpty);
      expect(File(slot.databasePath).existsSync(), isFalse);
    });

    test('el plazo cuenta desde que se resolvió, y vale igual para un rollback terminado', () async {
      final registry = copies();
      final slot = await finishedAt(
        registry,
        DateTime.utc(2026, 10, 1),
        rolledBack: true,
      );
      now = DateTime.utc(2026, 10, 7);
      expect((await registry.maintain()).expired, isEmpty);
      now = DateTime.utc(2026, 10, 9);
      expect((await registry.maintain()).expired, [slot.entry.id]);
    });

    test('sin oportunidad de mantenimiento no se borra nada: no hay limpieza en segundo plano', () async {
      final registry = copies();
      final slot = await finishedAt(registry, DateTime.utc(2026, 9, 1));
      now = DateTime.utc(2026, 10, 23);
      // No se llamó a maintain(): la copia sigue.
      expect(File(slot.databasePath).existsSync(), isTrue);
      expect(await registry.entries(), hasLength(1));
    });

    test('una copia en preparación de otro proceso pasa a interrumpida y queda protegida para siempre', () async {
      final first = copies();
      now = DateTime.utc(2026, 9, 1);
      final slot = await first.begin();
      await File(slot.databasePath).writeAsString('datos de entonces');
      // El proceso murió: otra instancia (la app reabierta) la encuentra.
      final reopened = copies();
      now = DateTime.utc(2026, 10, 23);
      final report = await reopened.maintain();
      expect(report.interrupted, [slot.entry.id]);
      expect(report.expired, isEmpty);
      expect(
        (await reopened.entries()).single.state,
        SafetyCopyState.interrupted,
      );
      // Ni el plazo ni la cota la retiran.
      for (var i = 0; i < 3; i++) {
        await finishedAt(reopened, now.add(Duration(minutes: i)));
      }
      now = now.add(const Duration(days: 30));
      await reopened.maintain();
      expect(File(slot.databasePath).existsSync(), isTrue);
      expect((await reopened.entries()).map((e) => e.state), [
        SafetyCopyState.interrupted,
      ]);
    });

    test(
      'una restauración en curso en este proceso no se marca como interrumpida',
      () async {
        final registry = copies();
        final slot = await registry.begin();
        expect((await registry.maintain()).interrupted, isEmpty);
        expect((await registry.entries()).single.id, slot.entry.id);
        expect(
          (await registry.entries()).single.state,
          SafetyCopyState.preparing,
        );
      },
    );

    test('una interrumpida bloquea otra restauración hasta que el titular la resuelve', () async {
      final first = copies();
      final slot = await first.begin();
      final reopened = copies();
      await expectLater(
        reopened.ensureCanStartRestore(),
        throwsA(same(RestoreBlockedException.unresolved)),
      );
      await reopened.keepCurrentData(slot.entry.id);
      expect(
        (await reopened.entries()).single.state,
        SafetyCopyState.rolledBack,
      );
      await reopened.ensureCanStartRestore();
      // Desde que se resolvió, cuenta el plazo normal.
      now = now.add(const Duration(days: 8));
      expect((await reopened.maintain()).expired, [slot.entry.id]);
    });

    test('las copias heredadas y lo ajeno nunca se borran solos; sólo una a una y a petición', () async {
      final registry = copies();
      final legacy = File('${databasePath()}.previo-2026-10-01T10-00-00.db');
      await legacy.writeAsString('heredada');
      final foreign = File(p.join(workspace.path, 'otra_cosa.previo-x.db'));
      await foreign.writeAsString('ajena');
      final active = File(databasePath());
      await active.writeAsString('base activa');
      final stray = File(p.join(previo().path, 'sin_entrada.db'));
      await stray.create(recursive: true);
      await finishedAt(registry, DateTime.utc(2026, 1, 1));
      now = DateTime.utc(2026, 10, 23);
      await registry.maintain();
      expect(legacy.existsSync(), isTrue);
      expect(foreign.existsSync(), isTrue);
      expect(active.existsSync(), isTrue);
      expect(stray.existsSync(), isTrue);

      final found = (await registry.unregistered()).map((e) => e.path).toSet();
      expect(found, {legacy.path, stray.path});
      // Lo que no devuelve unregistered() no se borra aunque se pida.
      await registry.deleteUnregistered(foreign);
      await registry.deleteUnregistered(active);
      expect(foreign.existsSync(), isTrue);
      expect(active.existsSync(), isTrue);
      await registry.deleteUnregistered(legacy);
      expect(legacy.existsSync(), isFalse);
    });

    test(
      'registro ilegible: no se limpia nada y no se restaura hasta apartarlo',
      () async {
        final registry = copies();
        final slot = await finishedAt(registry, DateTime.utc(2026, 1, 1));
        final file = File(p.join(previo().path, 'registro.json'));
        await file.writeAsString('{roto');
        now = DateTime.utc(2026, 10, 23);
        await registry.maintain();
        expect(File(slot.databasePath).existsSync(), isTrue);
        await expectLater(
          registry.ensureCanStartRestore(),
          throwsA(same(RestoreBlockedException.unreadableRegistry)),
        );
        await registry.setAsideUnreadableRegistry();
        await registry.ensureCanStartRestore();
        // La copia sigue, ahora como «sin entrada»: no se borra sola.
        expect(File(slot.databasePath).existsSync(), isTrue);
        expect(
          (await registry.unregistered()).map((e) => p.basename(e.path)),
          contains(p.basename(slot.databasePath)),
        );
        expect(
          filesInPrevio().where((n) => n.startsWith('registro.json.ilegible-')),
          hasLength(1),
        );
      },
    );

    test(
      'el registro se escribe completo (sin .tmp) y es JSON legible',
      () async {
        final registry = copies();
        await finishedAt(registry, now);
        expect(filesInPrevio().where((n) => n.endsWith('.tmp')), isEmpty);
        final json = jsonDecode(
          await File(p.join(previo().path, 'registro.json')).readAsString(),
        ) as Map;
        expect(json['version'], 1);
        expect((json['entries'] as List).single['state'], 'finalized');
      },
    );
  });

  group('con BackupService.restore', () {
    Future<AppDatabase> database() async {
      final db = AppDatabase(factory: databaseFactoryFfi, path: databasePath());
      addTearDown(db.close);
      await AgroRepository(db).addProduct(name: 'Producto actual');
      return db;
    }

    Future<String> legacyBackup(AppDatabase db, String name) async {
      final other = AppDatabase(
        factory: databaseFactoryFfi,
        path: p.join(workspace.path, 'origen_$name.db'),
      );
      await AgroRepository(other).addProduct(name: 'Producto $name');
      final copy = p.join(workspace.path, '$name.db');
      await other.close();
      await File(other.openedPath ?? p.join(workspace.path, 'origen_$name.db'))
          .copy(copy);
      return copy;
    }

    test('tres restauraciones: quedan dos copias previas, en previo/, con su registro', () async {
      final db = await database();
      final registry = copies();
      final backups = BackupService(db, safetyCopies: registry);
      for (var i = 0; i < 3; i++) {
        now = DateTime.utc(2026, 10, 23, 12, i);
        final result = await backups.restore(await legacyBackup(db, 'r$i'));
        expect(p.dirname(result.safetyCopyPath), previo().path);
        expect(File(result.safetyCopyPath).existsSync(), isTrue);
      }
      final entries = await registry.entries();
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.state).toSet(), {SafetyCopyState.finalized});
      expect(filesInPrevio().where((n) => n.endsWith('.db')), hasLength(2));
      // Nada junto a la base con el nombre antiguo.
      expect(
        workspace.listSync().where(
          (e) => p.basename(e.path).startsWith('agro.db.previo-'),
        ),
        isEmpty,
      );
    });

    test('fallo con rollback terminado: la copia queda como rolledBack y no bloquea', () async {
      final db = await database();
      final registry = copies();
      final backups = BackupService(db, safetyCopies: registry);
      await expectLater(
        backups.restore(
          await legacyBackup(db, 'falla'),
          afterReplace: () async => throw const BackupException('simulado'),
        ),
        throwsA(isA<BackupException>()),
      );
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.rolledBack,
      );
      expect(
        await AgroRepository(db).products(),
        contains(
          isA<Map<String, Object?>>().having(
            (r) => r['name'],
            'name',
            'Producto actual',
          ),
        ),
      );
      await registry.ensureCanStartRestore();
    });

    test('rollback que no termina: la copia queda interrumpida y la siguiente restauración se bloquea sin tocar nada', () async {
      final db = await database();
      final registry = copies();
      final backups = BackupService(db, safetyCopies: registry);
      final entries = <SafetyCopyEntry>[];
      await expectLater(
        backups.restore(
          await legacyBackup(db, 'roto'),
          afterReplace: () async {
            entries.addAll(await registry.entries());
            // Lo único que haría fallar el rollback: la copia previa no se
            // puede leer. Se aparta para simularlo.
            final copy = File(
              p.join(previo().path, entries.single.databaseName),
            );
            await copy.rename('${copy.path}.apartada');
            throw const BackupException('simulado');
          },
        ),
        throwsA(anything),
      );
      expect(
        (await registry.entries()).single.state,
        SafetyCopyState.interrupted,
      );
      final copy = File(p.join(previo().path, entries.single.databaseName));
      await File('${copy.path}.apartada').rename(copy.path);

      final activeBefore = await File(databasePath()).readAsBytes();
      await expectLater(
        backups.restore(await legacyBackup(db, 'siguiente')),
        throwsA(same(RestoreBlockedException.unresolved)),
      );
      expect(await File(databasePath()).readAsBytes(), activeBefore);
      expect(copy.existsSync(), isTrue);
    });

    test(
      'rechazo antes de preparar (archivo inválido): ni copia ni entrada',
      () async {
        final db = await database();
        final registry = copies();
        final backups = BackupService(db, safetyCopies: registry);
        final bad = File(p.join(workspace.path, 'malo.db'));
        await bad.writeAsString('no es una base');
        await expectLater(backups.restore(bad.path), throwsA(anything));
        expect(await registry.entries(), isEmpty);
        expect(filesInPrevio().where((n) => n.endsWith('.db')), isEmpty);
      },
    );
  });
}
