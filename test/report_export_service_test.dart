import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/services/reports/csv_report_generator.dart';
import 'package:agroquimicos/services/reports/report_export_service.dart';
import 'package:agroquimicos/services/reports/report_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Orquestación completa: leer -> componer -> generar -> guardar.
///
/// Incluye la guarda de regresión que exige la especificación: **generar un
/// reporte no escribe en SQLite**.
void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase database;
  late AgroRepository repo;
  late LocalReportStorage storage;
  late ReportExportService service;
  late String databasePath;
  late int family, campaign1;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agro_export_');
    databasePath = p.join(root.path, 'agro.db');
    database = AppDatabase(factory: databaseFactoryFfi, path: databasePath);
    repo = AgroRepository(database);
    storage = LocalReportStorage(
      directory: () async => Directory(p.join(root.path, 'reportes')),
    );
    service = ReportExportService(
      repo,
      storage,
      clock: () => DateTime.utc(2026, 9, 6, 15, 30),
    );

    family = await repo.addPerson(
      name: 'Ana Familiar',
      role: PersonRole.family,
    );
    final supplier = await repo.addSupplier(name: 'Proveedor');
    final farm = await repo.addFarm(
      ownerId: family,
      name: 'Chaco Uno',
      areaM2: 100000,
    );
    campaign1 = await repo.addCampaign(
      name: 'Campaña 1',
      start: DateTime.utc(2026, 1, 1),
    );
    final glifosato = await repo.addProduct(name: 'Glifosato');

    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign1,
        purchaseDate: DateTime.utc(2026, 1, 10),
        items: [
          PurchaseItemDraft(
            productId: glifosato,
            quantityBase: 20000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 10000,
            allocations: [
              AllocationDraft(personId: family, quantityBase: 20000),
            ],
          ),
        ],
      ),
    );
    await repo.confirmApplication(
      ApplicationDraft(
        personId: family,
        farmId: farm,
        campaignId: campaign1,
        appliedAt: DateTime.utc(2026, 2, 1),
        treatedAreaM2: 100000,
        lines: [ApplicationLineDraft(productId: glifosato, quantityBase: 5000)],
      ),
    );
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  ReportRequest request(
    ReportKind kind,
    ReportFormat format, {
    int? campaignId,
    int? personId,
  }) => ReportRequest(
    kind: kind,
    format: format,
    campaignId: campaignId,
    personId: personId,
  );

  /// Filtros válidos mínimos para cada reporte.
  ReportRequest valid(ReportKind kind, ReportFormat format) => switch (kind) {
    ReportKind.campaignSummary => request(kind, format, campaignId: campaign1),
    ReportKind.accountStatement => request(kind, format, personId: family),
    _ => request(kind, format),
  };

  group('exportación de los cinco reportes', () {
    for (final kind in ReportKind.values) {
      for (final format in ReportFormat.values) {
        test('${kind.label} en ${format.label} produce un archivo', () async {
          final stored = await service.export(valid(kind, format));
          expect(stored.fileName, endsWith('.${format.extension}'));
          expect(stored.fileName, contains(kind.fileBaseName));
          expect(stored.fileName, contains('2026-09-06'));
          final bytes = await File(stored.path).readAsBytes();
          expect(bytes, isNotEmpty);
          expect(bytes.length, stored.byteCount);
          if (format == ReportFormat.pdf) {
            expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
          } else {
            expect(bytes.sublist(0, 3), utf8Bom);
          }
        });
      }
    }

    test('el estado de cuenta lleva el nombre de la persona', () async {
      final stored = await service.export(
        valid(ReportKind.accountStatement, ReportFormat.csv),
      );
      expect(stored.fileName, contains('Ana Familiar'));
    });

    test('dos exportaciones seguidas no se pisan', () async {
      final first = await service.export(
        valid(ReportKind.inventory, ReportFormat.csv),
      );
      final second = await service.export(
        valid(ReportKind.inventory, ReportFormat.csv),
      );
      expect(second.fileName, isNot(first.fileName));
      expect(await File(first.path).exists(), isTrue);
    });
  });

  group('filtros', () {
    test('una campaña inexistente falla ANTES de generar nada', () async {
      await expectLater(
        service.export(
          request(ReportKind.productCost, ReportFormat.csv, campaignId: 9999),
        ),
        throwsA(isA<ReportFilterException>()),
      );
      final directory = Directory(p.join(root.path, 'reportes'));
      expect(
        !await directory.exists() || directory.listSync().isEmpty,
        isTrue,
        reason: 'no debe quedar ningún archivo',
      );
    });

    test('una persona inexistente da un error tipado', () async {
      await expectLater(
        service.export(
          request(
            ReportKind.accountStatement,
            ReportFormat.pdf,
            personId: 9999,
          ),
        ),
        throwsA(isA<ReportFilterException>()),
      );
    });

    test('el resumen de campaña sin campaña da un error tipado', () async {
      await expectLater(
        service.export(request(ReportKind.campaignSummary, ReportFormat.csv)),
        throwsA(isA<ReportFilterException>()),
      );
    });

    test('el estado de cuenta sin persona da un error tipado', () async {
      await expectLater(
        service.export(request(ReportKind.accountStatement, ReportFormat.csv)),
        throwsA(isA<ReportFilterException>()),
      );
    });

    test('el inventario no admite filtro de campaña', () async {
      await expectLater(
        service.export(
          request(
            ReportKind.inventory,
            ReportFormat.csv,
            campaignId: campaign1,
          ),
        ),
        throwsA(isA<ReportFilterException>()),
      );
    });

    test('sin campaña, el reporte declara "Todas las campañas"', () async {
      final table = await service.compose(
        request(ReportKind.farmCost, ReportFormat.csv),
      );
      expect(table.filters.single.value, 'Todas las campañas');
    });

    test('con campaña, el reporte declara su nombre', () async {
      final table = await service.compose(
        request(ReportKind.farmCost, ReportFormat.csv, campaignId: campaign1),
      );
      expect(table.filters.single.value, 'Campaña 1');
    });
  });

  group('cancelación', () {
    test('cancelar antes de empezar no deja ningún archivo', () async {
      final cancellation = ReportCancellation()..cancel();
      await expectLater(
        service.export(
          valid(ReportKind.inventory, ReportFormat.pdf),
          cancellation: cancellation,
        ),
        throwsA(isA<ReportCancelledException>()),
      );
      final directory = Directory(p.join(root.path, 'reportes'));
      expect(!await directory.exists() || directory.listSync().isEmpty, isTrue);
    });

    test('cancelar entre componer y guardar no deja ningún archivo', () async {
      final cancellation = ReportCancellation();
      // Se cancela cuando ya se leyó la base, justo antes de guardar.
      final slow = ReportExportService(
        repo,
        storage,
        csv: _CancellingCsvGenerator(cancellation),
        clock: () => DateTime.utc(2026, 9, 6),
      );
      await expectLater(
        slow.export(
          valid(ReportKind.inventory, ReportFormat.csv),
          cancellation: cancellation,
        ),
        throwsA(isA<ReportCancelledException>()),
      );
      final directory = Directory(p.join(root.path, 'reportes'));
      expect(!await directory.exists() || directory.listSync().isEmpty, isTrue);
    });

    test('una cancelación recién creada no cancela nada', () async {
      final cancellation = ReportCancellation();
      expect(cancellation.isCancelled, isFalse);
      final stored = await service.export(
        valid(ReportKind.inventory, ReportFormat.csv),
        cancellation: cancellation,
      );
      expect(await File(stored.path).exists(), isTrue);
    });
  });

  group('regresión: generar reportes NO escribe en SQLite', () {
    /// Contenido completo de la base, tabla por tabla y fila por fila.
    Future<String> dump() async {
      final db = await database.database;
      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )).map((row) => row['name']! as String).toList();
      final buffer = StringBuffer();
      for (final table in tables) {
        buffer.writeln('== $table');
        for (final row in await db.query(table)) {
          buffer.writeln(row.toString());
        }
      }
      final version = await db.rawQuery('PRAGMA user_version');
      buffer.writeln('user_version=${version.first.values.first}');
      return buffer.toString();
    }

    test('los diez reportes dejan la base byte a byte igual', () async {
      final before = await dump();
      final bytesBefore = await File(databasePath).readAsBytes();

      for (final kind in ReportKind.values) {
        for (final format in ReportFormat.values) {
          await service.export(valid(kind, format));
        }
      }

      expect(await dump(), before, reason: 'ninguna fila puede cambiar');
      expect(
        await File(databasePath).readAsBytes(),
        bytesBefore,
        reason: 'el archivo de la base no debe modificarse',
      );
    });

    test('un fallo de exportación tampoco toca la base', () async {
      final before = await dump();
      await expectLater(
        service.export(
          request(ReportKind.productCost, ReportFormat.csv, campaignId: 9999),
        ),
        throwsA(isA<ReportFilterException>()),
      );
      expect(await dump(), before);
    });

    test('el esquema sigue en la versión 6', () async {
      final db = await database.database;
      await service.export(valid(ReportKind.inventory, ReportFormat.pdf));
      final version = await db.rawQuery('PRAGMA user_version');
      expect(version.first.values.first, 6);
    });
  });

  group('coherencia con la aplicación', () {
    test('el CSV de inventario dice lo mismo que la consulta', () async {
      final stored = await service.export(
        valid(ReportKind.inventory, ReportFormat.csv),
      );
      final content = utf8.decode(
        (await File(stored.path).readAsBytes()).sublist(utf8Bom.length),
      );
      // 15 L de Glifosato tras aplicar 5 de los 20 comprados, valorados en
      // Bs 1.500,00.
      expect(content, contains('Glifosato;L;15;0;15;1500,00'));
      expect(content, contains('Valor total (Bs);1500,00'));
    });

    test('el estado de cuenta cuadra con el saldo de la persona', () async {
      final stored = await service.export(
        valid(ReportKind.accountStatement, ReportFormat.csv),
      );
      final content = utf8.decode(
        (await File(stored.path).readAsBytes()).sublist(utf8Bom.length),
      );
      // Un solo cargo por consumo: 5 L × Bs 100,00 = Bs 500,00.
      expect(content, contains('Total de cargos (Bs);500,00'));
      expect(content, contains('Saldo final (Bs);500,00'));
    });
  });
}

/// Generador que cancela mientras produce los bytes: reproduce que el usuario
/// pulse "Cancelar" cuando la lectura ya terminó pero nada se ha guardado.
class _CancellingCsvGenerator implements CsvReportGenerator {
  const _CancellingCsvGenerator(this._cancellation);

  final ReportCancellation _cancellation;

  @override
  Uint8List generate(table) {
    _cancellation.cancel();
    return const CsvReportGenerator().generate(table);
  }
}
