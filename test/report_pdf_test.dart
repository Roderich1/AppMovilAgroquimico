import 'dart:convert';

import 'package:agroquimicos/domain/read_models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/domain/reports/report_table.dart';
import 'package:agroquimicos/services/reports/csv_report_generator.dart';
import 'package:agroquimicos/services/reports/pdf_report_generator.dart';
import 'package:agroquimicos/services/reports/pdf_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Generador PDF (EVO-006).
///
/// El contenido va sin comprimir, así que se puede leer el archivo y comprobar
/// de verdad qué dice, en vez de conformarse con que "pesa algo".
void main() {
  const pdf = PdfReportGenerator();
  const csv = CsvReportGenerator();
  const composer = ReportComposer();
  final now = DateTime.utc(2026, 9, 6, 15, 30);

  /// El PDF como texto latin-1, que es la codificación de las cadenas WinAnsi.
  String read(ReportTable table) => latin1.decode(pdf.generate(table));

  int pageCount(String content) =>
      RegExp(r'/Type /Page[^s]').allMatches(content).length;

  ReportTable inventoryOf(int products) => composer.inventory(
    generatedAt: now,
    lines: [
      for (var i = 0; i < products; i++)
        InventoryLineRead(
          productId: i,
          productName: 'Producto $i',
          unit: 'L',
          purchasedBase: 1000,
          consumedBase: 0,
          availableBase: 1000,
          committedBase: 0,
          projectedBase: 1000,
          availableValueBobMinor: 100,
          peopleCount: 1,
        ),
    ],
  );

  group('estructura del archivo', () {
    test('empieza por %PDF y termina por %%EOF', () {
      final content = read(inventoryOf(1));
      expect(content, startsWith('%PDF-1.4'));
      expect(content.trimRight(), endsWith('%%EOF'));
    });

    test('declara catálogo, árbol de páginas y tabla xref', () {
      final content = read(inventoryOf(1));
      expect(content, contains('/Type /Catalog'));
      expect(content, contains('/Type /Pages'));
      expect(content, contains('xref'));
      expect(content, contains('trailer'));
      expect(content, contains('startxref'));
    });

    test('la hoja es A4', () {
      expect(read(inventoryOf(1)), contains('/MediaBox [0 0 595.28 841.89]'));
    });

    test('usa fuentes estándar con WinAnsiEncoding', () {
      final content = read(inventoryOf(1));
      expect(content, contains('/BaseFont /Helvetica'));
      expect(content, contains('/BaseFont /Helvetica-Bold'));
      expect(content, contains('/Encoding /WinAnsiEncoding'));
    });

    test('cada objeto declarado en xref apunta a su posición real', () {
      final bytes = pdf.generate(inventoryOf(40));
      final content = latin1.decode(bytes);
      final start = content.indexOf('\nxref\n') + 6;
      final lines = content.substring(start).split('\n');
      final count = int.parse(lines.first.split(' ')[1]);
      // lines[0] es la cabecera "0 N" y lines[1] la entrada libre, así que el
      // objeto i está en lines[i + 1].
      for (var i = 1; i < count; i++) {
        final offset = int.parse(lines[i + 1].substring(0, 10));
        expect(
          content.startsWith('$i 0 obj', offset),
          isTrue,
          reason: 'el objeto $i no está en el desplazamiento declarado',
        );
      }
    });
  });

  group('paginación', () {
    test('un reporte corto cabe en una página', () {
      expect(pageCount(read(inventoryOf(5))), 1);
    });

    test('una tabla larga ocupa varias páginas', () {
      final content = read(inventoryOf(200));
      expect(pageCount(content), greaterThan(3));
    });

    test('las cabeceras de columna se repiten en cada página', () {
      final content = read(inventoryOf(200));
      final pages = pageCount(content);
      // "Comprometido" sólo aparece como cabecera de columna.
      expect(RegExp(r'\(Comprometido\)').allMatches(content).length, pages);
    });

    test('el pie numera todas las páginas', () {
      final content = read(inventoryOf(200));
      final pages = pageCount(content);
      for (var i = 1; i <= pages; i++) {
        expect(content, contains('(P\xE1gina $i de $pages)'));
      }
    });

    test('los totales no se parten y salen una sola vez', () {
      final content = read(inventoryOf(200));
      // Los paréntesis del rótulo van escapados dentro de la cadena PDF.
      expect(
        RegExp(r'\(Valor total \\\(Bs\\\)\)').allMatches(content).length,
        1,
      );
    });
  });

  group('contenido', () {
    test('incluye título, fecha y filtros', () {
      final table = composer.productCost(
        generatedAt: now,
        campaignName: 'Campaña 1',
        lines: const [],
      );
      final content = read(table);
      expect(content, contains('(Costo por producto)'));
      expect(content, contains('Generado: 06/09/2026'));
      // "Campaña" lleva ñ, que en WinAnsi es el byte 0xF1.
      expect(content, contains('Campa\xF1a: Campa\xF1a 1'));
    });

    test('escribe los totales al pie', () {
      final table = composer.productCost(
        generatedAt: now,
        lines: const [
          ProductCostRead(
            productId: 1,
            productName: 'Glifosato',
            unit: 'L',
            quantityBase: 5000,
            totalCostBobMinor: 123456,
          ),
        ],
      );
      final content = read(table);
      expect(content, contains('(Costo total \\(Bs\\))'));
      expect(content, contains('(1.234,56)'));
    });

    test('un reporte sin filas dice por qué está vacío', () {
      final table = composer.inventory(generatedAt: now, lines: const []);
      final content = read(table);
      expect(content, contains('(No hay productos registrados.)'));
      expect(content, contains('(0,00)'));
      expect(pageCount(content), 1);
    });
  });

  group('español y casos extremos', () {
    test('ñ y tildes se codifican en WinAnsi, no en UTF-8', () {
      final table = composer.farmCost(
        generatedAt: now,
        lines: const [
          FarmCostRead(
            farmId: 1,
            farmName: 'Chaco Ñuflo de Chávez',
            ownerName: 'José Muñoz Íñiguez',
            areaM2: 100000,
            totalCostBobMinor: 1000,
          ),
        ],
      );
      final content = read(table);
      // Ñ=0xD1, á=0xE1, é=0xE9, í=0xED, ñ=0xF1, ó=0xF3, ú=0xFA.
      expect(content, contains('Chaco \xD1uflo de Ch\xE1vez'));
      expect(content, contains('Jos\xE9 Mu\xF1oz \xCD\xF1iguez'));
    });

    test(
      'un nombre larguísimo se recorta con elipsis y no invade columnas',
      () {
        final long =
            'Chaco de la Comunidad San Juan de la Frontera Norte Alta '
            'Sector Tres Ampliación Segunda';
        final table = composer.farmCost(
          generatedAt: now,
          lines: [
            FarmCostRead(
              farmId: 1,
              farmName: long,
              ownerName: 'Ana',
              areaM2: 100000,
              totalCostBobMinor: 0,
            ),
          ],
        );
        final content = read(table);
        expect(content, isNot(contains(long)));
        // 0x85 es la elipsis en WinAnsi.
        expect(content, contains('\x85'));
      },
    );

    test('un importe grande se escribe entero, sin recortar', () {
      final table = composer.accountStatement(
        personName: 'Ana',
        generatedAt: now,
        entries: [
          StatementEntryRead(
            id: 1,
            transactionDate: '2026-02-01T00:00:00.000Z',
            type: 'USAGE_CHARGE',
            amountBobMinorSigned: 999999999999,
            campaignId: null,
            concept: 'Glifosato',
            farmName: null,
            notes: null,
          ),
        ],
      );
      expect(read(table), contains('(9.999.999.999,99)'));
    });

    test('un paréntesis en un nombre se escapa y no rompe el archivo', () {
      final table = composer.farmCost(
        generatedAt: now,
        lines: const [
          FarmCostRead(
            farmId: 1,
            farmName: r'Chaco (Norte) \ Sur',
            ownerName: 'Ana',
            areaM2: 100000,
            totalCostBobMinor: 0,
          ),
        ],
      );
      final content = read(table);
      expect(content, contains(r'Chaco \(Norte\) \\ Sur'));
      expect(content.trimRight(), endsWith('%%EOF'));
    });
  });

  group('equivalencia entre CSV y PDF', () {
    /// Los dos formatos salen del mismo [ReportTable]; la única diferencia
    /// permitida es el separador de miles, que el CSV no lleva para que una
    /// hoja de cálculo pueda tipar la columna.
    void expectSameValues(ReportTable table) {
      final pdfContent = read(table);
      final csvContent = utf8.decode(
        csv.generate(table).sublist(utf8Bom.length),
      );
      for (final row in table.rows) {
        for (final cell in row) {
          if (cell is ReportBlank) continue;
          expect(
            cell.csvText,
            cell.displayText.replaceAll(groupSeparator, ''),
            reason: 'CSV y PDF deben representar el mismo número',
          );
          if (cell.isNumeric) {
            expect(pdfContent, contains('(${cell.displayText})'));
            expect(csvContent, contains(cell.csvText));
          }
        }
      }
      for (final total in table.totals) {
        expect(
          total.cell.csvText,
          total.cell.displayText.replaceAll(groupSeparator, ''),
        );
      }
    }

    test('inventario', () {
      expectSameValues(
        composer.inventory(
          generatedAt: now,
          lines: const [
            InventoryLineRead(
              productId: 1,
              productName: 'Glifosato',
              unit: 'L',
              purchasedBase: 20000,
              consumedBase: 5000,
              availableBase: 15000,
              committedBase: 2000,
              projectedBase: 13000,
              availableValueBobMinor: 1234567,
              peopleCount: 2,
            ),
          ],
        ),
      );
    });

    test('costo por chaco', () {
      expectSameValues(
        composer.farmCost(
          generatedAt: now,
          lines: const [
            FarmCostRead(
              farmId: 1,
              farmName: 'Chaco Uno',
              ownerName: 'Ana',
              areaM2: 123456,
              totalCostBobMinor: 7654321,
            ),
          ],
        ),
      );
    });

    test('resumen de campaña', () {
      expectSameValues(
        composer.campaignSummary(
          campaignName: 'Campaña 1',
          generatedAt: now,
          summary: const CampaignSummaryRead(
            purchasesCount: 1234,
            purchasesBobMinor: 98765432,
            applicationsCount: 12,
            applicationsBobMinor: 5000,
            pendingPlans: 3,
            receivableBobMinor: 1000000,
          ),
        ),
      );
    });
  });

  group('métricas de fuente', () {
    test('mide el ancho real de cada carácter', () {
      // "iii" es mucho más estrecho que "MMM" en una fuente proporcional.
      final narrow = PdfFont.helvetica.measure('iii', 10);
      final wide = PdfFont.helvetica.measure('MMM', 10);
      expect(narrow, lessThan(wide));
    });

    test('la ñ mide lo mismo que la n', () {
      expect(
        PdfFont.helvetica.measure('ñ', 10),
        PdfFont.helvetica.measure('n', 10),
      );
    });

    test('el recorte respeta el ancho pedido', () {
      const width = 40.0;
      final short = PdfFont.helvetica.ellipsize('Nombre larguísimo', 9, width);
      expect(PdfFont.helvetica.measure(short, 9), lessThanOrEqualTo(width));
      expect(short, endsWith('…'));
    });

    test('un texto que cabe no se toca', () {
      expect(PdfFont.helvetica.ellipsize('Ana', 9, 200), 'Ana');
    });
  });
}
