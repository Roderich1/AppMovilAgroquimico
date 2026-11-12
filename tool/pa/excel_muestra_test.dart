// Muestra de los reportes Excel de Mobile para revisarlos ABIERTOS en Excel
// (encabezados, fechas, decimales, filtros, nombres largos y estados). Usa el
// servicio real de reportes (ReportExportService → XlsxReportGenerator) sobre
// una base SQLite temporal con datos SINTÉTICOS. No es un recorrido en el
// teléfono: el archivo lo produce el mismo código que en la app.
//   OUT_DIR=<carpeta> flutter test tool/pa/excel_muestra_test.dart
import 'dart:io';

import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/services/reports/report_export_service.dart';
import 'package:agroquimicos/services/reports/report_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test('muestra de reportes Excel', () async {
    final out = Platform.environment['OUT_DIR'];
    if (out == null) fail('falta OUT_DIR');
    final root = await Directory.systemTemp.createTemp('agro_excel_muestra_');
    final database = AppDatabase(factory: databaseFactoryFfi, path: p.join(root.path, 'agro.db'));
    final repo = AgroRepository(database);
    final storage = LocalReportStorage(directory: () async => Directory(out));
    final service = ReportExportService(repo, storage, clock: () => DateTime.now().toUtc());

    final family = await repo.addPerson(name: 'Ana María Quispe Mamani de la Comunidad San Isidro (sintética)', role: PersonRole.family);
    final supplier = await repo.addSupplier(name: 'Agroservicios del Valle Alto (sintético)');
    final farm = await repo.addFarm(ownerId: family, name: 'Chaco de la loma norte junto al río (sintético)', areaM2: 12500);
    final campaign = await repo.addCampaign(name: 'Invierno 2026 (sintética)', start: DateTime.utc(2026, 5, 1));
    final glifosato = await repo.addProduct(name: 'Herbicida sistémico glifosato 48 % SL concentrado soluble (sintético)');
    final urea = await repo.addProduct(name: 'Urea granulada 46 %', unit: 'KG');
    await repo.confirmPurchase(
      PurchaseDraft(
        supplierId: supplier,
        campaignId: campaign,
        purchaseDate: DateTime.utc(2026, 5, 10),
        items: [
          PurchaseItemDraft(
            productId: glifosato,
            quantityBase: 20750,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 12345,
            allocations: [AllocationDraft(personId: family, quantityBase: 20750)],
          ),
          PurchaseItemDraft(
            productId: urea,
            quantityBase: 50000,
            currency: CurrencyCode.bob,
            originalUnitPriceMinor: 899,
            allocations: [AllocationDraft(personId: family, quantityBase: 50000)],
          ),
        ],
      ),
    );
    await repo.confirmApplication(
      ApplicationDraft(
        personId: family,
        farmId: farm,
        campaignId: campaign,
        appliedAt: DateTime.utc(2026, 6, 2, 14, 30),
        treatedAreaM2: 12500,
        lines: [ApplicationLineDraft(productId: glifosato, quantityBase: 3125)],
      ),
    );
    for (final request in [
      ReportRequest(kind: ReportKind.inventory, format: ReportFormat.xlsx),
      ReportRequest(kind: ReportKind.campaignSummary, format: ReportFormat.xlsx, campaignId: campaign),
      ReportRequest(kind: ReportKind.accountStatement, format: ReportFormat.xlsx, personId: family),
    ]) {
      final stored = await service.export(request);
      // ignore: avoid_print
      print('generado ${p.basename(stored.path)}');
    }
    await database.close();
    await root.delete(recursive: true);
  });
}
