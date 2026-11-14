// Decisión C del autor (cierre, 2026-11-13): «Excel/PDF de costo por chaco».
//
// En modo individual, el informe exportado «Costo por chaco» tiene el mismo
// alcance y filtros que «Costos › Por chaco» (los chacos del titular, la
// campaña elegida, las mismas cifras y el costo por hectárea sobre la
// superficie de cada chaco incluido). Los chacos de terceros del historial
// siguen en la base y se exportan en el modo con varias personas, que no
// cambia. Ningún costo se recalcula: el archivo suma los costos guardados.
//
// Hogar sembrado (100 Bs/L, todas las aplicaciones las hizo el titular):
//   Chaco Norte (titular, 3 ha)    C1: 2 L + 6 L = 800,00 · C2: 1 L = 100,00
//   Chaco Loma  (titular, 0,5 ha)  C2: 1 L = 100,00
//   Chaco Sur   (titular, 2 ha)    sin aplicaciones
//   Chaco Viejo (titular, 1 ha)    C1: 1 L = 100,00; archivado después
//   Chaco hermana (familiar, 0,5 ha)  C1: 1 L = 100,00   ← historial ajeno
//   Chaco vecino  (tercero, 1 ha)     C2: 2 L = 200,00   ← historial ajeno
//   Productos: Herbicida (L, aplicado) y Fungicida (KG, nunca aplicado).
//
// Continuación (misma decisión C): «Costo por producto» sigue el mismo
// patrón; «Resumen de campaña» no tiene pantalla individual equivalente y no
// cambia (la prueba deja medida su diferencia con «Costos › Campañas»).
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/data/ind_c_chacos_reads.dart';
import 'package:agroquimicos/data/operation_mode_store.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/operation_mode.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/services/reports/report_export_service.dart';
import 'package:agroquimicos/services/reports/report_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';
import 'support/f04_mode_fixtures.dart';
import 'support/f04_mode_ui_harness.dart';
import 'support/xlsx_reader.dart';

typedef _World = ({
  AppDatabase database,
  AgroRepository repo,
  ReportExportService service,
  int c1,
  int c2,
  int norte,
  int loma,
  int sur,
  int viejo,
  int hermana,
  int vecino,
  int product,
});

const _header = 'Chaco;Propietario;Área (ha);Costo (Bs);Costo/ha (Bs)';

Future<_World> _world(String name) async {
  final path = await tempDbPath(name);
  final database = openDb(path);
  final binding = await seedActivatedInstallation(database);
  final titular = binding.personId;
  final repo = AgroRepository(database);
  final relative = await repo.addPerson(
    name: 'Hermana',
    role: PersonRole.family,
  );
  final neighbour = await repo.addPerson(
    name: 'Vecino',
    role: PersonRole.thirdParty,
  );
  final supplier = await repo.addSupplier(name: 'Proveedor');
  final c1 = await repo.addCampaign(
    name: 'Invierno 2026',
    start: DateTime.utc(2026, 1, 1),
  );
  final product = await repo.addProduct(name: 'Herbicida');
  // Producto registrado y nunca aplicado (sólo figura en el informe global).
  await repo.addProduct(name: 'Fungicida', unit: 'KG');
  final norte = await repo.addFarm(
    ownerId: titular,
    name: 'Chaco Norte',
    areaM2: 30000,
  );
  final loma = await repo.addFarm(
    ownerId: titular,
    name: 'Chaco Loma',
    areaM2: 5000,
  );
  final sur = await repo.addFarm(
    ownerId: titular,
    name: 'Chaco Sur',
    areaM2: 20000,
  );
  final viejo = await repo.addFarm(
    ownerId: titular,
    name: 'Chaco Viejo',
    areaM2: 10000,
  );
  final hermana = await repo.addFarm(
    ownerId: relative,
    name: 'Chaco hermana',
    areaM2: 5000,
  );
  final vecino = await repo.addFarm(
    ownerId: neighbour,
    name: 'Chaco vecino',
    areaM2: 10000,
  );
  // 20 L del titular a 100 Bs/L.
  await repo.confirmPurchase(
    PurchaseDraft(
      supplierId: supplier,
      campaignId: c1,
      purchaseDate: DateTime.utc(2026, 1, 2),
      items: [
        PurchaseItemDraft(
          productId: product,
          quantityBase: 20000,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: 10000,
          allocations: [
            AllocationDraft(personId: titular, quantityBase: 20000),
          ],
        ),
      ],
    ),
  );
  Future<void> apply(int farm, int campaign, DateTime at, int quantity) =>
      repo.confirmApplication(
        ApplicationDraft(
          personId: titular,
          farmId: farm,
          campaignId: campaign,
          appliedAt: at,
          lines: [
            ApplicationLineDraft(productId: product, quantityBase: quantity),
          ],
        ),
      );
  await apply(norte, c1, DateTime.utc(2026, 2, 1), 2000);
  await apply(norte, c1, DateTime.utc(2026, 2, 2), 6000);
  await apply(viejo, c1, DateTime.utc(2026, 2, 3), 1000);
  await apply(hermana, c1, DateTime.utc(2026, 2, 4), 1000);
  await repo.closeCampaign(c1, end: DateTime.utc(2026, 8, 31));
  final c2 = await repo.addCampaign(
    name: 'Verano 2027',
    start: DateTime.utc(2026, 9, 1),
  );
  if ((await repo.activeCampaign())?['id'] != c2) {
    await repo.activateCampaign(c2);
  }
  await apply(norte, c2, DateTime.utc(2026, 9, 10), 1000);
  await apply(loma, c2, DateTime.utc(2026, 9, 11), 1000);
  await apply(vecino, c2, DateTime.utc(2026, 9, 12), 2000);
  await repo.archiveCatalog('farms', viejo);
  final service = ReportExportService(
    repo,
    LocalReportStorage(
      directory: () async => Directory(p.join(p.dirname(path), 'reportes')),
    ),
    clock: () => DateTime.utc(2026, 11, 13, 15, 30),
  );
  return (
    database: database,
    repo: repo,
    service: service,
    c1: c1,
    c2: c2,
    norte: norte,
    loma: loma,
    sur: sur,
    viejo: viejo,
    hermana: hermana,
    vecino: vecino,
    product: product,
  );
}

Future<void> _personal(AppDatabase database) =>
    OperationModeStore(database).apply(OperationMode.personal, confirmed: true);

/// Registros del Excel exportado, sin la línea «Generado».
Future<List<String>> _exported(
  _World w, {
  int? campaignId,
  ReportKind kind = ReportKind.farmCost,
}) async {
  final stored = await w.service.export(
    ReportRequest(
      kind: kind,
      format: ReportFormat.xlsx,
      campaignId: campaignId,
    ),
  );
  final records = xlsxRecords(await File(stored.path).readAsBytes());
  expect(records[1], startsWith('Generado;'));
  return [records[0], ...records.skip(2)];
}

/// Lo que muestra «Costos › Por chaco» con la misma lectura de la pantalla
/// (`indCChacos(campaignId:)`), en el formato de las filas del Excel.
Future<List<String>> _screenRows(_World w, {int? campaignId}) async {
  final chacos = await w.repo.indCChacos(campaignId: campaignId);
  // Mismo texto que las celdas del Excel (sin separador de miles).
  String money(int minor) =>
      (minor / 100).toStringAsFixed(2).replaceAll('.', ',');
  String area(int m2) => (m2 / 10000)
      .toString()
      .replaceAll(RegExp(r'\.0$'), '')
      .replaceAll('.', ',');
  return [
    for (final farm in chacos.farms)
      '${farm.name};${farm.ownerName};${area(farm.areaM2)};'
          '${money(farm.appliedCostMinor)};'
          '${farm.costPerHectareMinor == null ? '' : money(farm.costPerHectareMinor!)}',
    '',
    'Costo total (Bs);${money(chacos.appliedCostMinor)}',
  ];
}

void main() {
  sqfliteFfiInit();

  group('modo individual', () {
    test('todas las campañas: mismos chacos, totales y costo/ha que la '
        'pantalla, sin los chacos de terceros; la base no cambia', () async {
      final w = await _world('cierre_c_personal_all');
      await _personal(w.database);
      final db = await w.database.database;
      final before = await dumpTables(db);

      final file = await _exported(w);
      expect(file, [
        'Costo por chaco',
        'Campaña;Todas las campañas',
        'Chacos;$ownerFarmsScope',
        '',
        _header,
        'Chaco Loma;Titular;0,5;100,00;200,00',
        'Chaco Norte;Titular;3;900,00;300,00',
        // Sin aplicaciones: «No disponible» en la pantalla, celda vacía en el
        // archivo (nunca 0,00).
        'Chaco Sur;Titular;2;0,00;',
        // Archivado con aplicaciones en el alcance: su costo cuenta.
        'Chaco Viejo;Titular;1;100,00;100,00',
        '',
        'Costo total (Bs);1100,00',
      ]);
      expect(file.skip(5), await _screenRows(w));
      expect(file.join('\n'), isNot(contains('hermana')));
      expect(file.join('\n'), isNot(contains('vecino')));

      // El historial de terceros sigue en la base (no se borra ni oculta).
      final third = await db.rawQuery(
        'SELECT farm_id, total_cost_bob_minor FROM applications '
        'WHERE farm_id IN (?, ?) ORDER BY farm_id',
        [w.hermana, w.vecino],
      );
      expect(third.map((r) => r['total_cost_bob_minor']), [10000, 20000]);
      // Exportar no escribe en la base.
      expect(await dumpTables(db), before);
    });

    test(
      'con filtro de campaña: igual que la pantalla de esa campaña',
      () async {
        final w = await _world('cierre_c_personal_campaign');
        await _personal(w.database);

        final c1 = await _exported(w, campaignId: w.c1);
        expect(c1, [
          'Costo por chaco',
          'Campaña;Invierno 2026',
          'Chacos;$ownerFarmsScope',
          '',
          _header,
          'Chaco Loma;Titular;0,5;0,00;',
          // 800,00 ÷ 3 ha (superficie del chaco).
          'Chaco Norte;Titular;3;800,00;266,67',
          'Chaco Sur;Titular;2;0,00;',
          'Chaco Viejo;Titular;1;100,00;100,00',
          '',
          'Costo total (Bs);900,00',
        ]);
        expect(c1.skip(5), await _screenRows(w, campaignId: w.c1));

        final c2 = await _exported(w, campaignId: w.c2);
        expect(c2, [
          'Costo por chaco',
          'Campaña;Verano 2027',
          'Chacos;$ownerFarmsScope',
          '',
          _header,
          'Chaco Loma;Titular;0,5;100,00;200,00',
          'Chaco Norte;Titular;3;100,00;33,33',
          'Chaco Sur;Titular;2;0,00;',
          // Archivado y sin aplicaciones en Verano 2027: no figura, igual que
          // en la pantalla.
          '',
          'Costo total (Bs);200,00',
        ]);
        expect(c2.skip(5), await _screenRows(w, campaignId: w.c2));
      },
    );

    test(
      'Personas › Costos usa las mismas líneas que la exportación',
      () async {
        final w = await _world('cierre_c_personal_lines');
        await _personal(w.database);
        final lines = await w.repo.farmCostLines(campaignId: w.c1);
        expect(lines.ownerOnly, isTrue);
        expect(lines.lines.map((l) => l.farmId), [
          w.loma,
          w.norte,
          w.sur,
          w.viejo,
        ]);
        expect(lines.lines.map((l) => l.costPerHectareMinor), [
          null,
          26667,
          null,
          10000,
        ]);
      },
    );
  });

  group('modo con varias personas: sin cambios', () {
    test(
      'todas las campañas: todos los chacos de la base, como antes',
      () async {
        final w = await _world('cierre_c_shared_all');
        final file = await _exported(w);
        expect(file, [
          'Costo por chaco',
          'Campaña;Todas las campañas',
          '',
          _header,
          'Chaco Loma;Titular;0,5;100,00;200,00',
          'Chaco Norte;Titular;3;900,00;300,00',
          'Chaco Sur;Titular;2;0,00;0,00',
          'Chaco Viejo;Titular;1;100,00;100,00',
          'Chaco hermana;Hermana;0,5;100,00;200,00',
          'Chaco vecino;Vecino;1;200,00;200,00',
          '',
          'Costo total (Bs);1400,00',
        ]);
        // La misma consulta de siempre.
        final report = await w.repo.farmCostReport();
        expect(report.map((r) => r['id']), [
          w.loma,
          w.norte,
          w.sur,
          w.viejo,
          w.hermana,
          w.vecino,
        ]);
        expect((await w.repo.farmCostLines()).ownerOnly, isFalse);
      },
    );

    test('con filtro de campaña', () async {
      final w = await _world('cierre_c_shared_campaign');
      expect(await _exported(w, campaignId: w.c2), [
        'Costo por chaco',
        'Campaña;Verano 2027',
        '',
        _header,
        'Chaco Loma;Titular;0,5;100,00;200,00',
        'Chaco Norte;Titular;3;100,00;33,33',
        'Chaco Sur;Titular;2;0,00;0,00',
        'Chaco Viejo;Titular;1;0,00;0,00',
        'Chaco hermana;Hermana;0,5;0,00;0,00',
        'Chaco vecino;Vecino;1;200,00;200,00',
        '',
        'Costo total (Bs);400,00',
      ]);
    });
  });

  testWidgets('pantalla «Costos» en la app y archivo exportado: mismas cifras '
      '(Invierno 2026)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final w = (await tester.runAsync(() async {
      final w = await _world('cierre_c_ui');
      await _personal(w.database);
      return w;
    }))!;
    final c = await pumpModeApp(tester, w.database);
    c.read(routerProvider).go('/chacos/costos?campana=${w.c1}');
    await settle(tester);

    String text(Key key) => tester.widget<Text>(find.byKey(key)).data!;
    expect(text(const Key('ind-costos-total')), '900,00');
    expect(find.text('Chaco hermana'), findsNothing);
    expect(find.text('Chaco vecino'), findsNothing);
    expect(text(Key('ind-costo-chaco-total-${w.norte}')), '800,00');
    expect(text(Key('ind-costo-ha-${w.norte}')), formatBob(26667));
    expect(text(Key('ind-costo-chaco-total-${w.viejo}')), '100,00');
    expect(text(Key('ind-costo-ha-${w.viejo}')), formatBob(10000));
    expect(text(Key('ind-costo-ha-${w.loma}')), 'No disponible');
    expect(text(Key('ind-costo-ha-${w.sur}')), 'No disponible');

    final file = (await tester.runAsync(() => _exported(w, campaignId: w.c1)))!;
    expect(file.last, 'Costo total (Bs);900,00');
    expect(file, contains('Chaco Norte;Titular;3;800,00;266,67'));
    expect(file, contains('Chaco Viejo;Titular;1;100,00;100,00'));
    expect(file, contains('Chaco Loma;Titular;0,5;0,00;'));
    expect(file, contains('Chaco Sur;Titular;2;0,00;'));
    expect(file.where((r) => r.startsWith('Chaco ')), hasLength(4));
  });

  // --- Costo por producto ---------------------------------------------------

  const productHeader = 'Producto;Cantidad;Unidad;Costo (Bs)';

  /// «Costos › Productos» con la lectura de la pantalla
  /// (`indCProductCosts(campaignId:)`), en el formato de las filas del Excel.
  Future<List<String>> productScreenRows(_World w, {int? campaignId}) async {
    final rows = await w.repo.indCProductCosts(campaignId: campaignId);
    String money(int minor) =>
        (minor / 100).toStringAsFixed(2).replaceAll('.', ',');
    String quantity(int base) => (base / 1000)
        .toString()
        .replaceAll(RegExp(r'\.0$'), '')
        .replaceAll('.', ',');
    return [
      for (final row in rows)
        '${row.name};${quantity(row.quantityBase)};${row.unit};'
            '${money(row.costMinor)}',
      '',
      'Costo total (Bs);'
          '${money(rows.fold(0, (sum, row) => sum + row.costMinor))}',
    ];
  }

  group('costo por producto', () {
    test(
      'modo individual, todas las campañas y con campaña: mismas filas y '
      'total que la pantalla, sin lo aplicado en chacos de terceros',
      () async {
        final w = await _world('cierre_c_product_personal');
        await _personal(w.database);
        final db = await w.database.database;
        final before = await dumpTables(db);

        final all = await _exported(w, kind: ReportKind.productCost);
        expect(all, [
          'Costo por producto',
          'Campaña;Todas las campañas',
          'Aplicaciones;$ownerProductsScope',
          '',
          productHeader,
          'Herbicida;11;L;1100,00',
          '',
          'Costo total (Bs);1100,00',
        ]);
        expect(all.skip(5), await productScreenRows(w));

        final c1 = await _exported(
          w,
          kind: ReportKind.productCost,
          campaignId: w.c1,
        );
        expect(c1.skip(5), [
          'Herbicida;9;L;900,00',
          '',
          'Costo total (Bs);900,00',
        ]);
        expect(c1.skip(5), await productScreenRows(w, campaignId: w.c1));
        expect(await dumpTables(db), before);
      },
    );

    test('modo con varias personas: sin cambios (todos los productos y todas '
        'las aplicaciones)', () async {
      final w = await _world('cierre_c_product_shared');
      expect(await _exported(w, kind: ReportKind.productCost), [
        'Costo por producto',
        'Campaña;Todas las campañas',
        '',
        productHeader,
        'Fungicida;0;KG;0,00',
        'Herbicida;14;L;1400,00',
        '',
        'Costo total (Bs);1400,00',
      ]);
      expect(
        await _exported(w, kind: ReportKind.productCost, campaignId: w.c1),
        [
          'Costo por producto',
          'Campaña;Invierno 2026',
          '',
          productHeader,
          'Fungicida;0;KG;0,00',
          'Herbicida;10;L;1000,00',
          '',
          'Costo total (Bs);1000,00',
        ],
      );
      expect((await w.repo.productCostLines()).ownerOnly, isFalse);
    });
  });

  testWidgets('pantalla «Costos › Productos» en la app y archivo exportado: '
      'mismas cifras (Invierno 2026)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final w = (await tester.runAsync(() async {
      final w = await _world('cierre_c_product_ui');
      await _personal(w.database);
      return w;
    }))!;
    final c = await pumpModeApp(tester, w.database);
    c.read(routerProvider).go('/chacos/costos?campana=${w.c1}');
    await settle(tester);
    await tester.tap(find.byKey(const Key('ind-costos-por-producto')));
    await settle(tester);
    final row = find.byKey(Key('ind-costo-producto-${w.product}'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text(formatBob(90000))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('9 L · en 3 aplicaciones')),
      findsOneWidget,
    );
    expect(find.text('Fungicida'), findsNothing);

    final file = (await tester.runAsync(
      () => _exported(w, kind: ReportKind.productCost, campaignId: w.c1),
    ))!;
    expect(file.skip(5), [
      'Herbicida;9;L;900,00',
      '',
      'Costo total (Bs);900,00',
    ]);
  });

  // --- Resumen de campaña: sin pantalla individual equivalente -------------

  test('resumen de campaña: no cambia; su fila «Aplicaciones registradas» '
      'cuenta todas las de la campaña, a diferencia de «Costos › Campañas» '
      '(limitación declarada)', () async {
    final w = await _world('cierre_c_summary_personal');
    await _personal(w.database);
    final screen = (await w.repo.indCCampaignCosts()).firstWhere(
      (row) => row.campaign.id == w.c1,
    );
    expect(screen.applicationCount, 3);
    expect(screen.costMinor, 90000);
    final file = await _exported(
      w,
      kind: ReportKind.campaignSummary,
      campaignId: w.c1,
    );
    // Sin filtro de alcance: es el resumen global de siempre.
    expect(file[1], 'Campaña;Invierno 2026');
    expect(file, contains('Aplicaciones registradas;4;1000,00'));
    // Igual que en el modo con varias personas.
    final shared = await _world('cierre_c_summary_shared');
    expect(
      await _exported(
        shared,
        kind: ReportKind.campaignSummary,
        campaignId: shared.c1,
      ),
      file,
    );
  });
}
