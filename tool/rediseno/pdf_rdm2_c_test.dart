// Ronda 2, sesión C (P4): genera PDF REALES del «Estado de cuenta» y de
// «Movimientos propios del titular» con el compositor y el generador de la
// app, sobre una base SINTÉTICA en memoria: nombres largos, muchas filas
// (más de una página) e importes grandes. Sirve para el «antes» (código
// base) y el «después»; las páginas se renderizan a PNG aparte (PyMuPDF).
//
//   RDM_PDF_OUT=<carpeta> flutter test tool/rediseno/pdf_rdm2_c_test.dart
//
// No es parte de la suite: vive en tool/ y sólo escribe archivos.
import 'dart:io';

import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/services/reports/pdf_report_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/support/e15_world.dart';

const _longPerson = 'María Fernanda Quispe de los Ángeles Huanca';
const _longFarm = 'Chaco Comunidad San Juan de la Frontera Norte, Sector Tres';
const _longProduct = 'Herbicida sistémico selectivo de amplio espectro 480 SL';

void main() {
  sqfliteFfiInit();
  final out = Directory(
    Platform.environment['RDM_PDF_OUT'] ?? 'build/rediseno_pdf_rdm2_c',
  )..createSync(recursive: true);

  test('estado de cuenta y movimientos propios en PDF', () async {
    final e = await E15World.create();
    final w = e.w;
    final db = await w.db;
    await db.update(
      'persons',
      {'name': _longPerson},
      where: 'id=?',
      whereArgs: [w.familiar],
    );
    await db.update(
      'persons',
      {'name': 'Rosa Vargas'},
      where: 'id=?',
      whereArgs: [e.titular],
    );
    final product = await w.repo.addProduct(name: _longProduct);
    e.products[_longProduct] = product;
    final farm = await w.repo.addFarm(
      ownerId: w.familiar,
      name: _longFarm,
      areaM2: 125000,
    );
    // Compras grandes para que el costo FIFO dé importes grandes.
    await e.buy(w.familiar, _longProduct, 4000000, 98765);
    await e.buy(e.titular, _longProduct, 400000, 98765);
    // 48 aplicaciones del familiar (cargo por consumo) y pagos intercalados.
    for (var i = 0; i < 48; i++) {
      final day = DateTime(2026, 7 + i ~/ 12, 2 + (i % 12) * 2, 8);
      await e.apply(w.familiar, i.isEven ? farm : e.chacoFamiliar, day, {
        _longProduct: 50000 + i * 1250,
      });
      if (i % 5 == 4) {
        await w.pay(
          w.familiar,
          12345678 + i * 1000,
          campaign: w.invierno,
          date: day.add(const Duration(hours: 4)).toUtc().toIso8601String(),
        );
      }
    }
    // 30 aplicaciones del titular (consumo propio).
    for (var i = 0; i < 30; i++) {
      final day = DateTime(2026, 7 + i ~/ 10, 3 + (i % 10) * 2, 9);
      await e.apply(e.titular, e.chacoNorte, day, {_longProduct: 9000 + i});
    }

    const composer = ReportComposer();
    const pdf = PdfReportGenerator();
    final now = DateTime(2026, 11, 12, 10, 30);
    for (final (name, campaign) in [
      ('estado_cuenta_todas', null),
      ('estado_cuenta_invierno', w.invierno),
    ]) {
      final statement = await w.repo.accountStatement(
        w.familiar,
        campaignId: campaign,
      );
      final table = composer.ledgerStatement(
        statement: statement,
        generatedAt: now,
      );
      File('${out.path}/$name.pdf').writeAsBytesSync(pdf.generate(table));
    }
    final own = await w.repo.accountStatement(e.titular);
    File('${out.path}/movimientos_propios_todas.pdf').writeAsBytesSync(
      pdf.generate(composer.ownStatement(statement: own, generatedAt: now)),
    );
    await e.close();
  });
}
