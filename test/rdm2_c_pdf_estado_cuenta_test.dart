// Ronda 2 del rediseño, sesión C (P4): el PDF del estado de cuenta no corta
// ningún texto. Antes cada celda se recortaba con «…» al ancho de un reparto
// fijo en A4 vertical: fechas, conceptos, cabeceras e imputaciones. Ahora el
// generador parte los textos en líneas, deja fechas e importes enteros y,
// si una tabla ancha no cabe, usa la hoja en horizontal. El generador expone
// su disposición (`layout`), así que se comprueba la medida de cada línea.
import 'dart:convert';

import 'package:agroquimicos/domain/read_models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/domain/reports/report_table.dart';
import 'package:agroquimicos/services/reports/pdf_report_generator.dart';
import 'package:agroquimicos/services/reports/pdf_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/e15_world.dart';

const _longPerson = 'María Fernanda Quispe de los Ángeles Huanca';
const _longFarm = 'Chaco Comunidad San Juan de la Frontera Norte, Sector Tres';
const _longProduct = 'Herbicida sistémico selectivo de amplio espectro 480 SL';

void main() {
  sqfliteFfiInit();
  const pdf = PdfReportGenerator();
  const composer = ReportComposer();
  final now = DateTime(2026, 11, 12, 10, 30);

  /// Cada celda: sus líneas caben en su columna y, unidas, son el texto
  /// entero (sin contar espacios). Fechas e importes, en una sola línea.
  void expectNothingCut(ReportTable table) {
    final layout = pdf.layout(table);
    String compact(String text) => text.replaceAll(RegExp(r'\s+'), '');
    for (final (r, row) in table.rows.indexed) {
      for (final (c, cell) in row.indexed) {
        final lines = layout.rowLines[r][c];
        final inner =
            layout.columnWidths[c] - PdfReportGenerator.cellPadding * 2;
        expect(
          compact(lines.join()),
          compact(cell.displayText),
          reason: 'fila $r, columna ${table.columns[c].header}',
        );
        for (final line in lines) {
          expect(
            PdfFont.helvetica.measure(line, PdfReportGenerator.bodySize),
            lessThanOrEqualTo(inner + 0.01),
            reason: '«$line» se sale de ${table.columns[c].header}',
          );
        }
        if (cell.isNumeric || cell is ReportDate) {
          expect(lines, hasLength(1), reason: cell.displayText);
        }
      }
    }
    for (final (c, column) in table.columns.indexed) {
      expect(compact(layout.headerLines[c].join()), compact(column.header));
    }
    final total = layout.columnWidths.fold<double>(0, (a, b) => a + b);
    expect(
      total,
      lessThanOrEqualTo(
        layout.format.width - PdfReportGenerator.margin * 2 + 0.01,
      ),
    );
    // Y en el archivo no hay elipsis (0x85 en WinAnsi).
    expect(latin1.decode(pdf.generate(table)), isNot(contains('\x85')));
  }

  test(
    'estado de cuenta con nombres largos, importes grandes y más de una '
    'página: nada se corta, cabeceras en cada página, hoja horizontal',
    () async {
      final e = await E15World.create();
      addTearDown(e.close);
      final w = e.w;
      await (await w.db).update(
        'persons',
        {'name': _longPerson},
        where: 'id=?',
        whereArgs: [w.familiar],
      );
      e.products[_longProduct] = await w.repo.addProduct(name: _longProduct);
      final farm = await w.repo.addFarm(
        ownerId: w.familiar,
        name: _longFarm,
        areaM2: 125000,
      );
      await e.buy(w.familiar, _longProduct, 4000000, 98765);
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
      for (final campaign in [null, w.invierno]) {
        final table = composer.ledgerStatement(
          statement: await w.repo.accountStatement(
            w.familiar,
            campaignId: campaign,
          ),
          generatedAt: now,
        );
        expectNothingCut(table);
        final layout = pdf.layout(table);
        expect(layout.format.width, greaterThan(layout.format.height));
        final content = latin1.decode(pdf.generate(table));
        final pages = RegExp(r'/Type /Page[^s]').allMatches(content).length;
        expect(pages, greaterThan(1));
        // «Campaña del asiento» puede partirse; «Imputación» es una palabra.
        expect(RegExp(r'\(Imputaci\xF3n\)').allMatches(content).length, pages);
        expect(content, contains('/MediaBox [0 0 841.89 595.28]'));
        // El nombre de la persona va entero en los filtros.
        expect(content, contains(latin1.decode(latin1.encode(_longPerson))));
      }
    },
  );

  test('movimientos propios del titular: nada se corta', () async {
    final e = await E15World.create();
    addTearDown(e.close);
    await e.seedE1501();
    final table = composer.ownStatement(
      statement: await e.w.repo.accountStatement(e.titular),
      generatedAt: now,
    );
    expectNothingCut(table);
  });

  test('una tabla estrecha sigue en A4 vertical, también con un nombre '
      'larguísimo, que se parte en líneas', () {
    final long =
        'Chaco de la Comunidad San Juan de la Frontera Norte Alta '
        'Sector Tres Ampliación Segunda';
    final table = composer.farmCost(
      generatedAt: now,
      lines: [
        FarmCostRead(
          farmId: 1,
          farmName: long,
          ownerName: _longPerson,
          areaM2: 100000,
          totalCostBobMinor: 999999999999,
        ),
      ],
    );
    expect(pdf.layout(table).format.height, greaterThan(800));
    expectNothingCut(table);
  });

  test('una palabra más ancha que su columna se parte, no se recorta', () {
    final lines = wrapText(
      'Supercalifragilisticoespialidoso' * 3,
      PdfFont.helvetica,
      9,
      60,
    );
    expect(lines.length, greaterThan(1));
    expect(lines.join(), 'Supercalifragilisticoespialidoso' * 3);
    for (final line in lines) {
      expect(PdfFont.helvetica.measure(line, 9), lessThanOrEqualTo(60));
    }
  });
}
