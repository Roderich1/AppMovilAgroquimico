// REC-016 (#52), criterio 4: el contenido EXPORTADO de costo por producto,
// costo por chaco y resumen de campaña coincide con lo que la base contiene.
//
// `report_export_service_test.dart` ya compara el inventario (:328) y el
// estado de cuenta (:341). Aquí se cubren los otros tres, con y sin filtro de
// campaña. El esperado NO sale de leer la base con la misma consulta que usa
// la exportación: está fijado por la fixture y calculado a mano, de modo que
// un error de cableado entre el tipo de reporte, su lectura o su filtro
// (`report_export_service.dart`, `compose`) se detecta.
//
//   Campaña 1 (cerrada el 31/05):
//     C1 10/01  Glifosato 3 L a 100,00 (g1) + Paraquat 4 KG a 50,00 (p1) = 500,00
//     C2 20/01  Glifosato 5 L a 120,00 (g2)                                = 600,00
//     A1 01/02  Chaco Grande  Glifosato 4 L    g1 3 + g2 1         = 420,00
//     A2 15/02  Chaco Grande  Paraquat 1 KG    p1 1                =  50,00
//     A3 01/03  Chaco Grande  Glifosato 0,5 L  g2 0,5  REVERTIDA   =  60,00
//     A5 10/03  Chaco Chico   Glifosato 0,5 L  g2 0,5              =  60,00
//   Campaña 2 (desde el 01/06, activa):
//     C3 10/06  Paraquat 2 KG a 55,00 (p2)                         = 110,00
//     A4 01/07  Chaco Grande  Glifosato 1 L    g2 1                = 120,00
//     A6 05/07  Chaco Chico   Paraquat 3,5 KG  p1 3 + p2 0,5       = 177,50
//     Un plan pendiente en Chaco Grande.
//   Chaco Beto (5 ha, de Beto Tercero) sin aplicaciones.
//
// Todas las aplicaciones son de Ana, que paga por consumo: sus cargos son los
// costos de cada aplicación y la reversión de A3 abona 60,00 en la Campaña 1.

import 'dart:convert';
import 'dart:io';

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

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase database;
  late AgroRepository repo;
  late ReportExportService service;
  late int campaign1;
  late int campaign2;
  late int ana, glifosato, paraquat;

  DateTime day(int month, int dayOfMonth) =>
      DateTime(2026, month, dayOfMonth, 12);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('agro_rec016_');
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(root.path, 'agro.db'),
    );
    repo = AgroRepository(database);
    service = ReportExportService(
      repo,
      LocalReportStorage(
        directory: () async => Directory(p.join(root.path, 'reportes')),
      ),
      clock: () => DateTime.utc(2026, 9, 6, 15, 30),
    );

    ana = await repo.addPerson(name: 'Ana Familiar', role: PersonRole.family);
    final beto = await repo.addPerson(
      name: 'Beto Tercero',
      role: PersonRole.thirdParty,
    );
    final supplier = await repo.addSupplier(name: 'Proveedor');
    final grande = await repo.addFarm(
      ownerId: ana,
      name: 'Chaco Grande',
      areaM2: 100000,
    );
    final chico = await repo.addFarm(
      ownerId: ana,
      name: 'Chaco Chico',
      areaM2: 25000,
    );
    await repo.addFarm(ownerId: beto, name: 'Chaco Beto', areaM2: 50000);
    campaign1 = await repo.addCampaign(name: 'Campaña 1', start: day(1, 1));
    glifosato = await repo.addProduct(name: 'Glifosato');
    paraquat = await repo.addProduct(name: 'Paraquat', unit: 'KG');

    PurchaseItemDraft item(int product, int quantity, int priceMinor) =>
        PurchaseItemDraft(
          productId: product,
          quantityBase: quantity,
          currency: CurrencyCode.bob,
          originalUnitPriceMinor: priceMinor,
          allocations: [AllocationDraft(personId: ana, quantityBase: quantity)],
        );
    Future<int> buy(int campaign, DateTime at, List<PurchaseItemDraft> items) =>
        repo.confirmPurchase(
          PurchaseDraft(
            supplierId: supplier,
            campaignId: campaign,
            purchaseDate: at,
            items: items,
          ),
        );
    Future<int> apply(
      int farm,
      int campaign,
      DateTime at,
      int product,
      int quantity,
    ) => repo.confirmApplication(
      ApplicationDraft(
        personId: ana,
        farmId: farm,
        campaignId: campaign,
        appliedAt: at,
        treatedAreaM2: 10000,
        lines: [
          ApplicationLineDraft(productId: product, quantityBase: quantity),
        ],
      ),
    );

    await buy(campaign1, day(1, 10), [
      item(glifosato, 3000, 10000),
      item(paraquat, 4000, 5000),
    ]);
    await buy(campaign1, day(1, 20), [item(glifosato, 5000, 12000)]);
    await apply(grande, campaign1, day(2, 1), glifosato, 4000);
    await apply(grande, campaign1, day(2, 15), paraquat, 1000);
    final a3 = await apply(grande, campaign1, day(3, 1), glifosato, 500);
    await repo.reverseApplication(a3, reason: 'Registrada por error');
    await apply(chico, campaign1, day(3, 10), glifosato, 500);

    await repo.closeCampaign(campaign1, end: day(5, 31));
    campaign2 = await repo.addCampaign(name: 'Campaña 2', start: day(6, 1));
    if ((await repo.activeCampaign())?['id'] != campaign2) {
      await repo.activateCampaign(campaign2);
    }
    await buy(campaign2, day(6, 10), [item(paraquat, 2000, 5500)]);
    await apply(grande, campaign2, day(7, 1), glifosato, 1000);
    await apply(chico, campaign2, day(7, 5), paraquat, 3500);
    await repo.addPlan(
      farmId: grande,
      campaignId: campaign2,
      productId: glifosato,
      areaM2: 50000,
      doseBasePerHa: 500,
    );
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Registros del CSV exportado, sin el BOM. Se omite el de «Generado»: su
  /// hora local depende de la zona del equipo y no es parte del contenido.
  Future<List<String>> exported(ReportKind kind, {int? campaignId}) async {
    final stored = await service.export(
      ReportRequest(
        kind: kind,
        format: ReportFormat.csv,
        campaignId: campaignId,
      ),
    );
    final bytes = await File(stored.path).readAsBytes();
    expect(bytes.sublist(0, utf8Bom.length), utf8Bom);
    final records = utf8.decode(bytes.sublist(utf8Bom.length)).split('\r\n');
    expect(records[1], startsWith('Generado;'));
    return [records[0], ...records.skip(2)];
  }

  // #46/#51 (cifras netas, ejemplo de §5 a del diseño de MOB #140): la
  // aplicación revertida A3 ya no cuenta como consumo ni su restitución como
  // asignación. Antes daban consumido 6 L y asignado 8,5 L, y 8 − 6 no era el
  // físico de 2,5 L.
  test('inventario de Glifosato y Paraquat con cifras netas', () async {
    expect(await repo.inventoryProductHeader(glifosato), {
      'product_id': glifosato,
      'product_name': 'Glifosato',
      'unit': 'L',
      'purchased_base': 8000, // 3 + 5 L
      'consumed_base': 5500, // 4 + 0,5 − 0,5 (A3) + 0,5 + 1 L
      'physical_base': 2500,
      'value_bob_minor': 30000, // 2,5 L de g2 a 120,00
      'committed_base': 2500, // plan de 5 ha a 0,5 L/ha en la Campaña 2
    });
    expect(await repo.inventoryProductDistribution(glifosato), [
      {
        'person_id': ana,
        'person_name': 'Ana Familiar',
        'assigned_base': 8000,
        'consumed_base': 5500,
        'available_base': 2500,
      },
    ]);
    expect(await repo.inventoryProductHeader(paraquat), {
      'product_id': paraquat,
      'product_name': 'Paraquat',
      'unit': 'KG',
      'purchased_base': 6000, // 4 + 2 kg
      'consumed_base': 4500, // 1 + 3,5 kg, sin reversiones
      'physical_base': 1500,
      'value_bob_minor': 8250, // 1,5 kg de p2 a 55,00
      'committed_base': 0,
    });
    expect(await repo.inventoryProductDistribution(paraquat), [
      {
        'person_id': ana,
        'person_name': 'Ana Familiar',
        'assigned_base': 6000,
        'consumed_base': 4500,
        'available_base': 1500,
      },
    ]);
  });

  group('costo por producto', () {
    const header = 'Producto;Cantidad;Unidad;Costo (Bs)';

    test('todas las campañas: la aplicación revertida no cuenta', () async {
      expect(await exported(ReportKind.productCost), [
        'Costo por producto',
        'Campaña;Todas las campañas',
        '',
        header,
        'Glifosato;5,5;L;600,00',
        'Paraquat;4,5;KG;227,50',
        '',
        'Costo total (Bs);827,50',
        '',
      ]);
    });

    test('Campaña 1', () async {
      expect(await exported(ReportKind.productCost, campaignId: campaign1), [
        'Costo por producto',
        'Campaña;Campaña 1',
        '',
        header,
        'Glifosato;4,5;L;480,00',
        'Paraquat;1;KG;50,00',
        '',
        'Costo total (Bs);530,00',
        '',
      ]);
    });

    test('Campaña 2, con un consumo FIFO de dos lotes', () async {
      expect(await exported(ReportKind.productCost, campaignId: campaign2), [
        'Costo por producto',
        'Campaña;Campaña 2',
        '',
        header,
        'Glifosato;1;L;120,00',
        'Paraquat;3,5;KG;177,50',
        '',
        'Costo total (Bs);297,50',
        '',
      ]);
    });
  });

  group('costo por chaco', () {
    const header = 'Chaco;Propietario;Área (ha);Costo (Bs);Costo/ha (Bs)';

    test('todas las campañas, con el chaco sin aplicaciones en cero', () async {
      expect(await exported(ReportKind.farmCost), [
        'Costo por chaco',
        'Campaña;Todas las campañas',
        '',
        header,
        'Chaco Beto;Beto Tercero;5;0,00;0,00',
        'Chaco Chico;Ana Familiar;2,5;237,50;95,00',
        'Chaco Grande;Ana Familiar;10;590,00;59,00',
        '',
        'Costo total (Bs);827,50',
        '',
      ]);
    });

    test('Campaña 1', () async {
      expect(await exported(ReportKind.farmCost, campaignId: campaign1), [
        'Costo por chaco',
        'Campaña;Campaña 1',
        '',
        header,
        'Chaco Beto;Beto Tercero;5;0,00;0,00',
        'Chaco Chico;Ana Familiar;2,5;60,00;24,00',
        'Chaco Grande;Ana Familiar;10;470,00;47,00',
        '',
        'Costo total (Bs);530,00',
        '',
      ]);
    });

    test('Campaña 2', () async {
      expect(await exported(ReportKind.farmCost, campaignId: campaign2), [
        'Costo por chaco',
        'Campaña;Campaña 2',
        '',
        header,
        'Chaco Beto;Beto Tercero;5;0,00;0,00',
        'Chaco Chico;Ana Familiar;2,5;177,50;71,00',
        'Chaco Grande;Ana Familiar;10;120,00;12,00',
        '',
        'Costo total (Bs);297,50',
        '',
      ]);
    });
  });

  group('resumen de campaña', () {
    const header = 'Concepto;Cantidad;Importe (Bs)';

    test(
      'Campaña 1: la reversión no cuenta ni en aplicaciones ni en el saldo',
      () async {
        expect(
          await exported(ReportKind.campaignSummary, campaignId: campaign1),
          [
            'Resumen de campaña',
            'Campaña;Campaña 1',
            '',
            header,
            'Compras registradas;2;1100,00',
            'Aplicaciones registradas;3;530,00',
            'Planes pendientes;0;',
            'Saldo por cobrar;;530,00',
            '',
            'Compras (Bs);1100,00',
            'Aplicaciones (Bs);530,00',
            'Saldo por cobrar (Bs);530,00',
            '',
          ],
        );
      },
    );

    test('Campaña 2, con su plan pendiente', () async {
      expect(
        await exported(ReportKind.campaignSummary, campaignId: campaign2),
        [
          'Resumen de campaña',
          'Campaña;Campaña 2',
          '',
          header,
          'Compras registradas;1;110,00',
          'Aplicaciones registradas;2;297,50',
          'Planes pendientes;1;',
          'Saldo por cobrar;;297,50',
          '',
          'Compras (Bs);110,00',
          'Aplicaciones (Bs);297,50',
          'Saldo por cobrar (Bs);297,50',
          '',
        ],
      );
    });
  });
}
