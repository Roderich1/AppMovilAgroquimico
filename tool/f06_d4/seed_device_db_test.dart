// ignore_for_file: avoid_print
// F06 (D4): siembra en el host la base del agricultor 1 para la copia aislada del
// teléfono, desde docs/evidence/F06_DATASET.csv y con el mismo helper que la
// reconciliación automatizada. No publica nada: el titular publica su consumo
// desde el teléfono. Las necesidades declaradas quedan pendientes en la outbox y
// las envía el worker del teléfono.
// La referencia de instalación es la de la propia copia aislada (su client_id),
// de modo que la base no se trata como restaurada de otra instalación.
// Sólo corre con AGRO_F06_DEVICE_DB_OUT (lo invoca tool/f06_d4/device.sh seed).
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/sync/central_references.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/f06_dataset.dart';

void main() {
  sqfliteFfiInit();
  final env = Platform.environment;
  final out = env['AGRO_F06_DEVICE_DB_OUT'];

  test('F06: base local del agricultor 1 para el teléfono', () async {
    expect(File(out!).existsSync(), isFalse, reason: 'una base nueva');
    final references = CentralReferences.fromJson(
      jsonDecode(File(env['AGRO_F06_REFS_JSON']!).readAsStringSync())
          as Map<String, dynamic>,
    );
    final database = AppDatabase(factory: databaseFactoryFfi, path: out);
    final farm = await seedF06Farm(
      database: database,
      farmer: 'F1',
      scope: OwnerScope(
        memberId: env['AGRO_F06_MEMBER_ID']!,
        tenantId: env['AGRO_F06_TENANT_ID']!,
      ),
      installationRef: installationReference(env['AGRO_F06_CLIENT_ID']!),
      references: references,
    );
    final preview = await farm.publisher.preview();
    final expected = f06ExpectedContributions('F1');
    final consumption = expected.entries
        .where((e) => e.key.projection == 'CONSUMPTION_TOTAL')
        .toList();
    expect(preview.rows.length, consumption.length);
    expect(
      {for (final row in preview.rows) row.quantityBase}.toList()..sort(),
      [for (final e in consumption) e.value.quantity!]..sort(),
    );
    for (final row in preview.rows) {
      print(
        '  vista previa: ${row.productName} (${row.campaignName}) '
        '${row.quantityBase} ${row.baseUnit.code} · ${row.change.name}',
      );
    }
    print('  excluidas: ${preview.excludedLines}');
    final pending = await (await database.database).query('sync_outbox');
    print('  outbox: ${pending.length} necesidades pendientes de envío');
    await database.close();
  }, skip: out == null ? 'sin AGRO_F06_DEVICE_DB_OUT' : false);
}
