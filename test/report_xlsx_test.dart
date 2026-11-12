import 'dart:convert';

import 'package:agroquimicos/domain/read_models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/domain/reports/report_table.dart';
import 'package:agroquimicos/services/reports/xlsx_report_generator.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/xlsx_reader.dart';

/// Generador Excel (sustituye al CSV de EVO-005 desde el 2026-11-12).
///
/// Cada prueba DESCOMPRIME el libro y lee su XML con un analizador estricto
/// (`support/xlsx_reader.dart`): se comprueba lo que de verdad contiene, no
/// que «pesa algo». Las comprobaciones del antiguo `report_csv_test.dart` se
/// conservan con su equivalente en Excel (codificación, separación de campos,
/// escapado, español, fórmulas, contenido) y se añaden las propias del formato
/// (tipos de celda, autofiltro, encabezado inmovilizado, nombre de hoja).
void main() {
  const generator = XlsxReportGenerator();
  const composer = ReportComposer();
  final now = DateTime.utc(2026, 9, 6, 15, 30);

  ReportTable table({
    List<ReportColumn> columns = const [
      ReportColumn('Producto'),
      ReportColumn('Costo (Bs)', numeric: true),
    ],
    required List<List<ReportCell>> rows,
    List<ReportFilter> filters = const [],
    List<ReportTotal> totals = const [],
    String title = 'Reporte',
  }) => ReportTable(
    title: title,
    generatedAt: now,
    columns: columns,
    rows: rows,
    filters: filters,
    totals: totals,
  );

  XlsxBook book(ReportTable source) => readXlsx(generator.generate(source));

  String generatedText(DateTime moment) {
    final local = moment.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// Registros que daba el CSV para [source] (sin BOM, sin la guarda de
  /// fórmulas, que en Excel no hace falta): el oráculo de que el libro
  /// conserva todos los datos y columnas.
  List<String> csvLayout(ReportTable source) => [
    source.title,
    'Generado;${generatedText(source.generatedAt)}',
    for (final f in source.filters) '${f.label};${f.value}',
    '',
    source.columns.map((c) => c.header).join(';'),
    if (source.isEmpty)
      source.emptyMessage
    else
      for (final row in source.rows) row.map((c) => c.csvText).join(';'),
    if (source.totals.isNotEmpty) ...[
      '',
      for (final t in source.totals) '${t.label};${t.cell.csvText}',
    ],
  ];

  /// Fila de datos de una tabla mínima (cabecera en la fila 4).
  XlsxCell? dataCell(XlsxBook b, String column) => b['${column}5'];

  group('formato del archivo', () {
    test('es un ZIP con las partes de un libro SpreadsheetML', () {
      final bytes = generator.generate(
        table(
          rows: const [
            [ReportText('Glifosato'), ReportMoney(50000)],
          ],
        ),
      );
      // Firma de cabecera local de ZIP.
      expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      final b = readXlsx(bytes);
      expect(
        b.parts.keys,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
        ]),
      );
      expect(
        b.parts['[Content_Types].xml'],
        contains('spreadsheetml.sheet.main+xml'),
      );
    });

    test('el MIME es el de un libro .xlsx', () {
      expect(
        xlsxMimeType,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    });

    test('cada valor ocupa su propia celda (antes: separador «;»)', () {
      final b = book(
        table(
          rows: const [
            [ReportText('Glifosato'), ReportMoney(50000)],
          ],
        ),
      );
      expect(dataCell(b, 'A')!.value, 'Glifosato');
      expect(dataCell(b, 'B')!.value, '500.00');
      expect(dataCell(b, 'B')!.isNumber, isTrue);
      expect(b.records, contains('Glifosato;500,00'));
    });

    test('una fila del reporte es una fila de la hoja (antes: CRLF)', () {
      final b = book(
        table(
          rows: const [
            [ReportText('A'), ReportMoney(1)],
            [ReportText('B'), ReportMoney(2)],
          ],
        ),
      );
      expect(b['A5']!.value, 'A');
      expect(b['A6']!.value, 'B');
      expect(
        b.records.where((r) => r == 'A;0,01' || r == 'B;0,02'),
        hasLength(2),
      );
    });

    test('el encabezado declara título, fecha y filtros', () {
      final b = book(
        table(
          title: 'Costo por producto',
          filters: const [ReportFilter('Campaña', 'Campaña 1')],
          rows: const [],
        ),
      );
      expect(b.records.first, 'Costo por producto');
      expect(b['A1']!.isInlineString, isTrue);
      expect(b.styleOf(b['A1']!).bold, isTrue);
      expect(b.records[1], startsWith('Generado;06/09/2026'));
      expect(b.records[2], 'Campaña;Campaña 1');
    });

    test('todas las partes son XML bien formado, sin fórmulas', () {
      final b = book(
        composer.inventory(
          generatedAt: now,
          lines: const [
            InventoryLineRead(
              productId: 1,
              productName: 'Glifosato & <Cía> "48%" \'SL\'',
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
        ),
      );
      // `readXlsx` ya falló si alguna parte estaba mal formada.
      expect(b.parts, hasLength(6));
      expect(b.hasFormula, isFalse);
    });

    test('el mismo reporte produce los mismos bytes', () {
      final source = table(
        rows: const [
          [ReportText('Glifosato'), ReportMoney(50000)],
        ],
      );
      expect(generator.generate(source), generator.generate(source));
    });
  });

  group('tabla: autofiltro, encabezado inmovilizado y hoja', () {
    test('la fila de cabecera lleva autofiltro sobre cabecera y datos', () {
      final b = book(
        table(
          filters: const [ReportFilter('Campaña', 'Campaña 1')],
          rows: const [
            [ReportText('A'), ReportMoney(1)],
            [ReportText('B'), ReportMoney(2)],
            [ReportText('C'), ReportMoney(3)],
          ],
          totals: const [ReportTotal('Costo total (Bs)', ReportMoney(6))],
        ),
      );
      // Título, Generado, filtro, blanco → cabecera en la fila 5.
      expect(b.autoFilter, 'A5:B8');
      expect(b['A5']!.value, 'Producto');
      expect(b.styleOf(b['A5']!).bold, isTrue);
      expect(b.styleOf(b['B5']!).bold, isTrue);
      // Los totales quedan fuera: filtrar no los esconde.
      expect(b['A10']!.value, 'Costo total (Bs)');
      expect(b.filterDatabase, r"'Reporte'!$A$5:$B$8");
    });

    test('la cabecera queda inmovilizada', () {
      final b = book(
        table(
          filters: const [
            ReportFilter('Persona', 'Ana'),
            ReportFilter('Campaña', 'Todas las campañas'),
          ],
          rows: const [
            [ReportText('A'), ReportMoney(1)],
          ],
        ),
      );
      // Cabecera en la fila 6: se inmovilizan las seis primeras.
      expect(b['A6']!.value, 'Producto');
      expect(b.frozenRows, 6);
      expect(b.frozenTopLeft, 'A7');
    });

    test('sin filas, el autofiltro cubre sólo la cabecera', () {
      final b = book(table(rows: const []));
      expect(b.autoFilter, 'A4:B4');
      expect(b['A5']!.value, 'No hay datos para los filtros elegidos.');
    });

    test('el nombre de la hoja sale del título y es válido', () {
      expect(
        book(table(rows: const [], title: 'Inventario')).sheetName,
        'Inventario',
      );
      expect(
        xlsxSheetName('Movimientos propios del titular'),
        'Movimientos propios del titular',
      );
      expect(xlsxSheetName('a/b\\c[d]e:f*g?h'), 'a-b-c-d-e-f-g-h');
      expect(xlsxSheetName('x' * 40), hasLength(31));
      expect(xlsxSheetName("'citado'"), 'citado');
      expect(xlsxSheetName('   '), 'Reporte');
      expect(xlsxSheetName('History'), 'Reporte');
      // No parte un emoji en dos.
      final emoji = '${'x' * 30}😀';
      expect(xlsxSheetName(emoji), 'x' * 30);
    });

    test('un título con caracteres prohibidos sigue dando un libro válido', () {
      final b = book(table(rows: const [], title: "Costo [2026]: A/B 'x' & y"));
      expect(b.sheetName, "Costo -2026-- A-B 'x' & y");
      expect(b.parts['xl/workbook.xml'], contains('&amp; y'));
      expect(b.records.first, "Costo [2026]: A/B 'x' & y");
    });
  });

  group('tipos de celda', () {
    test('importes, cantidades, áreas y conteos son celdas numéricas', () {
      final b = book(
        table(
          columns: const [
            ReportColumn('Importe', numeric: true),
            ReportColumn('Cantidad', numeric: true),
            ReportColumn('Área', numeric: true),
            ReportColumn('Conteo', numeric: true),
          ],
          rows: const [
            [
              ReportMoney(123456789),
              ReportQuantity(1500),
              ReportArea(15000),
              ReportCount(1234),
            ],
          ],
        ),
      );
      final money = dataCell(b, 'A')!;
      final quantity = dataCell(b, 'B')!;
      final area = dataCell(b, 'C')!;
      final count = dataCell(b, 'D')!;
      for (final cell in [money, quantity, area, count]) {
        expect(cell.isNumber, isTrue, reason: cell.ref);
      }
      // Decimal exacto, con punto y sin separador de miles.
      expect(money.value, '1234567.89');
      expect(quantity.value, '1.5');
      expect(area.value, '1.5');
      expect(count.value, '1234');
      expect(b.numberFormatOf(money), '#,##0.00');
      expect(b.numberFormatOf(count), '#,##0');
      expect(b.numberFormatOf(quantity), 'General');
      expect(b.numberFormatOf(area), 'General');
    });

    test('un importe negativo es un número negativo, no un texto', () {
      final b = book(
        table(
          rows: const [
            [ReportText('Pago'), ReportMoney(-20000)],
          ],
        ),
      );
      final cell = dataCell(b, 'B')!;
      expect(cell.isNumber, isTrue);
      expect(cell.value, '-200.00');
      expect(b.styleOf(cell).quotePrefix, isFalse);
      expect(b.records, contains('Pago;-200,00'));
    });

    test('una celda sin valor queda vacía, nunca en cero', () {
      final b = book(
        composer.farmCost(
          generatedAt: now,
          lines: const [
            FarmCostRead(
              farmId: 1,
              farmName: 'Anómalo',
              ownerName: 'Ana',
              areaM2: 0,
              totalCostBobMinor: 1000,
            ),
          ],
        ),
      );
      // Cabecera en la fila 5; la fila 6 es el chaco. Costo/ha es la E.
      expect(b['A6']!.value, 'Anómalo');
      expect(b['D6']!.value, '10.00');
      expect(b['E6'], isNull);
      expect(b.records, contains('Anómalo;Ana;0;10,00;'));
    });

    test('un cero real sí se escribe como 0', () {
      final b = book(
        table(
          rows: const [
            [ReportText('Nada'), ReportMoney(0)],
          ],
        ),
      );
      expect(dataCell(b, 'B')!.value, '0.00');
      expect(dataCell(b, 'B')!.isNumber, isTrue);
    });

    test('una fecha es una fecha dd/mm/yyyy del mismo día', () {
      final b = book(
        table(
          columns: const [ReportColumn('Fecha'), ReportColumn('Concepto')],
          rows: const [
            [ReportDate('2026-03-01'), ReportText('Pago')],
          ],
        ),
      );
      final cell = dataCell(b, 'A')!;
      expect(cell.isNumber, isTrue);
      // 1 de marzo de 2026 = 46082 días desde el 30/12/1899.
      expect(cell.value, '46082');
      expect(b.numberFormatOf(cell), 'dd/mm/yyyy');
      expect(b.recordOf(cell), '01/03/2026');
    });

    test('una fecha que no se puede interpretar se conserva como texto', () {
      final b = book(
        table(
          columns: const [ReportColumn('Fecha'), ReportColumn('Concepto')],
          rows: const [
            [ReportDate('sin fecha'), ReportText('Pago')],
          ],
        ),
      );
      expect(dataCell(b, 'A')!.isInlineString, isTrue);
      expect(dataCell(b, 'A')!.value, 'sin fecha');
    });
  });

  group('escapado', () {
    String roundTrip(String value) {
      final b = book(
        table(
          rows: [
            [ReportText(value), const ReportMoney(0)],
          ],
        ),
      );
      final cell = dataCell(b, 'A')!;
      expect(cell.isInlineString, isTrue);
      return cell.value;
    }

    test('las comillas viajan tal cual, escapadas en el XML', () {
      expect(roundTrip('Chaco "El Alto"'), 'Chaco "El Alto"');
      final b = generator.generate(
        table(
          rows: const [
            [ReportText('Chaco "El Alto"'), ReportMoney(0)],
          ],
        ),
      );
      final sheet = readXlsx(b).parts['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('Chaco &quot;El Alto&quot;'));
    });

    test('&, <, > y apóstrofo se escapan y vuelven íntegros', () {
      const value = "A & B <script>alert('x')</script>";
      expect(roundTrip(value), value);
      final sheet = readXlsx(
        generator.generate(
          table(
            rows: const [
              [ReportText(value), ReportMoney(0)],
            ],
          ),
        ),
      ).parts['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('A &amp; B &lt;script&gt;alert(&apos;x&apos;)'));
      expect(sheet, isNot(contains('<script>')));
    });

    test('un «;» dentro del texto no parte la celda', () {
      expect(roundTrip('Uno; Dos'), 'Uno; Dos');
    });

    test('un salto de línea no parte la fila', () {
      final b = book(
        table(
          rows: const [
            [ReportText('Primera\nSegunda'), ReportMoney(0)],
            [ReportText('Siguiente'), ReportMoney(0)],
          ],
        ),
      );
      expect(b['A5']!.value, 'Primera\nSegunda');
      expect(b['A6']!.value, 'Siguiente');
    });

    test('los espacios en los extremos se conservan', () {
      expect(roundTrip('  con espacios  '), '  con espacios  ');
    });

    test('un retorno de carro se conserva', () {
      expect(roundTrip('a\rb'), 'a\rb');
      expect(roundTrip('a\r\nb'), 'a\r\nb');
    });

    test('un carácter de control se codifica sin romper el XML', () {
      expect(roundTrip('a\u0001b\u001Fc'), 'a\u0001b\u001Fc');
    });

    test('un «_x0041_» escrito por el usuario no se decodifica', () {
      expect(roundTrip('lote_x0041_final'), 'lote_x0041_final');
    });
  });

  group('español', () {
    test('la ñ y las tildes sobreviven al viaje de ida y vuelta', () {
      final b = book(
        table(
          title: 'Resumen de campaña',
          filters: const [ReportFilter('Campaña', 'Añejo 2026')],
          rows: const [
            [ReportText('Fósforo ácido ñandú Ü'), ReportMoney(0)],
          ],
        ),
      );
      expect(b['A1']!.value, 'Resumen de campaña');
      expect(b['B3']!.value, 'Añejo 2026');
      expect(b['A6']!.value, 'Fósforo ácido ñandú Ü');
      expect(b.sheetName, 'Resumen de campaña');
    });

    test('la ñ se codifica en UTF-8 dentro del XML, no en Latin-1', () {
      final archive = ZipDecoder().decodeBytes(
        generator.generate(
          table(
            rows: const [
              [ReportText('ñ'), ReportMoney(0)],
            ],
          ),
        ),
      );
      final sheet = archive.findFile('xl/worksheets/sheet1.xml')!.content;
      // C3 B1 es "ñ" en UTF-8; F1 sería Latin-1.
      expect(sheet, containsAllInOrder([0xC3, 0xB1]));
      expect(sheet, isNot(contains(0xF1)));
      expect(
        utf8.decode(sheet),
        startsWith('<?xml version="1.0" encoding="UTF-8"'),
      );
    });
  });

  group('fórmulas: el texto se guarda como texto', () {
    XlsxCell first(String value) {
      final b = book(
        table(
          rows: [
            [ReportText(value), const ReportMoney(0)],
          ],
        ),
      );
      expect(b.hasFormula, isFalse);
      return dataCell(b, 'A')!;
    }

    bool quoted(String value) {
      final b = book(
        table(
          rows: [
            [ReportText(value), const ReportMoney(0)],
          ],
        ),
      );
      return b.styleOf(dataCell(b, 'A')!).quotePrefix;
    }

    for (final trigger in ['=', '+', '@', '-']) {
      test('una celda que empieza por "$trigger" es texto íntegro', () {
        final cell = first('${trigger}SUMA(A1:A9)');
        expect(cell.isInlineString, isTrue);
        // Sin apóstrofo añadido: el dato no se altera.
        expect(cell.value, '${trigger}SUMA(A1:A9)');
        expect(quoted('${trigger}SUMA(A1:A9)'), isTrue);
      });
    }

    test('una cadena que empieza por «=» no se escribe como fórmula', () {
      final bytes = generator.generate(
        table(
          rows: const [
            [ReportText('=1+1'), ReportMoney(0)],
          ],
        ),
      );
      final sheet = readXlsx(bytes).parts['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains('t="inlineStr"'));
      expect(sheet, contains('<t xml:space="preserve">=1+1</t>'));
      expect(sheet, isNot(contains('<f>')));
      expect(sheet, isNot(contains('<v>=1+1</v>')));
    });

    test('los espacios iniciales no esconden el disparador', () {
      expect(first('   =1+1').value, '   =1+1');
      expect(quoted('   =1+1'), isTrue);
    });

    test('tabulación y retorno de carro iniciales se marcan como texto', () {
      expect(first('\tABC').value, '\tABC');
      expect(quoted('\tABC'), isTrue);
      expect(first('\rABC').value, '\rABC');
      expect(quoted('\rABC'), isTrue);
      expect(quoted(' \tABC'), isTrue);
      expect(quoted('\t=1+1'), isTrue);
    });

    test('una celda vacía no se escribe y una de espacios no se marca', () {
      final b = book(
        table(
          rows: const [
            [ReportText(''), ReportMoney(0)],
          ],
        ),
      );
      expect(dataCell(b, 'A'), isNull);
      expect(b.records, contains(';0,00'));
      expect(first('   ').value, '   ');
      expect(quoted('   '), isFalse);
    });

    test('un texto corriente no se marca', () {
      expect(first('Glifosato').value, 'Glifosato');
      expect(quoted('Glifosato'), isFalse);
    });

    test('un nombre de persona con fórmula en el filtro es texto', () {
      final b = book(
        table(filters: const [ReportFilter('Persona', '=1+1')], rows: const []),
      );
      expect(b['B3']!.isInlineString, isTrue);
      expect(b['B3']!.value, '=1+1');
      expect(b.styleOf(b['B3']!).quotePrefix, isTrue);
      expect(b.records, contains('Persona;=1+1'));
    });
  });

  group('contenido', () {
    test('escribe cabeceras, filas y totales', () {
      final b = book(
        table(
          rows: const [
            [ReportText('Glifosato'), ReportMoney(50000)],
          ],
          totals: const [ReportTotal('Costo total (Bs)', ReportMoney(50000))],
        ),
      );
      expect(b.records, contains('Producto;Costo (Bs)'));
      expect(b.records, contains('Glifosato;500,00'));
      expect(b.records, contains('Costo total (Bs);500,00'));
      expect(b['B7']!.isNumber, isTrue);
    });

    test('sin filas conserva cabeceras, filtros y estado vacío', () {
      final source = composer.inventory(generatedAt: now, lines: const []);
      final records = xlsxRecords(generator.generate(source));
      expect(
        records,
        contains(
          'Producto;Unidad;Físico;Comprometido;'
          'Proyectado;Valor (Bs)',
        ),
      );
      expect(records, contains(source.emptyMessage));
      expect(records, contains('Valor total (Bs);0,00'));
      expect(records, contains('Alcance;Inventario global'));
    });

    test('cantidad y unidad ocupan columnas distintas', () {
      final source = composer.productCost(
        generatedAt: now,
        lines: const [
          ProductCostRead(
            productId: 1,
            productName: 'Glifosato',
            unit: 'L',
            quantityBase: 5000,
            totalCostBobMinor: 50000,
          ),
        ],
      );
      expect(
        xlsxRecords(generator.generate(source)),
        contains('Glifosato;5;L;500,00'),
      );
    });

    test('un dataset largo produce una fila por línea', () {
      final source = composer.inventory(
        generatedAt: now,
        lines: [
          for (var i = 0; i < 250; i++)
            InventoryLineRead(
              productId: i,
              productName: 'Producto ñ $i',
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
      final b = readXlsx(generator.generate(source));
      expect(
        b.records.where((r) => r.startsWith('Producto ñ ')),
        hasLength(250),
      );
      // 250 × Bs 1,00 = Bs 250,00.
      expect(b.records, contains('Valor total (Bs);250,00'));
      // Cabecera en la fila 5, 250 filas: autofiltro hasta la 255.
      expect(b.autoFilter, 'A5:F255');
    });
  });

  group('conserva todo lo que daba el CSV, reporte por reporte', () {
    final reports = <String, ReportTable>{
      'inventario': composer.inventory(
        generatedAt: now,
        lines: const [
          InventoryLineRead(
            productId: 1,
            productName: 'Glifosato',
            unit: 'L',
            purchasedBase: 20000,
            consumedBase: 5000,
            availableBase: 15000,
            committedBase: 2500,
            projectedBase: 12500,
            availableValueBobMinor: 1234567,
            peopleCount: 2,
          ),
        ],
      ),
      'costo por producto': composer.productCost(
        generatedAt: now,
        campaignName: 'Campaña 1',
        lines: const [
          ProductCostRead(
            productId: 1,
            productName: 'Paraquat',
            unit: 'KG',
            quantityBase: 4500,
            totalCostBobMinor: 22750,
          ),
        ],
      ),
      'costo por chaco': composer.farmCost(
        generatedAt: now,
        lines: const [
          FarmCostRead(
            farmId: 1,
            farmName: 'Chaco Chico',
            ownerName: 'Ana',
            areaM2: 25000,
            totalCostBobMinor: 23750,
          ),
          FarmCostRead(
            farmId: 2,
            farmName: 'Sin área',
            ownerName: 'Beto',
            areaM2: 0,
            totalCostBobMinor: 100,
          ),
        ],
      ),
      'resumen de campaña': composer.campaignSummary(
        generatedAt: now,
        campaignName: 'Campaña 1',
        summary: const CampaignSummaryRead(
          purchasesCount: 2,
          purchasesBobMinor: 110000,
          applicationsCount: 3,
          applicationsBobMinor: 53000,
          pendingPlans: 0,
          receivableBobMinor: 53000,
        ),
      ),
      // Columnas del estado de cuenta desde el libro (D-04 §2.6).
      'estado de cuenta': ReportTable(
        title: 'Estado de cuenta',
        generatedAt: now,
        filters: const [
          ReportFilter('Persona', 'Ana Familiar'),
          ReportFilter('Campaña', 'Todas las campañas'),
        ],
        columns: const [
          ReportColumn('Fecha'),
          ReportColumn('Concepto'),
          ReportColumn('Chaco'),
          ReportColumn('Campaña del asiento'),
          ReportColumn('Cargo (Bs)', numeric: true),
          ReportColumn('Crédito (Bs)', numeric: true),
          ReportColumn('Imputación'),
          ReportColumn('Acumulado (Bs)', numeric: true),
        ],
        rows: const [
          [
            ReportBlank(),
            ReportText('Saldo al inicio del período (01/07/2026)'),
            ReportBlank(),
            ReportBlank(),
            ReportBlank(),
            ReportBlank(),
            ReportBlank(),
            ReportMoney(8100),
          ],
          [
            ReportDate('2026-08-10'),
            ReportText('Consumo'),
            ReportText('Chaco Grande'),
            ReportText('Invierno 2026'),
            ReportMoney(4000),
            ReportBlank(),
            ReportText('Pendiente a hoy Bs 40,00'),
            ReportMoney(12100),
          ],
          [
            ReportDate('2026-10-20'),
            ReportText('Pago'),
            ReportText(''),
            ReportText('registrado sin campaña'),
            ReportBlank(),
            ReportMoney(5000),
            ReportText('Imputado: Verano 2026 Bs 50,00'),
            ReportMoney(7100),
          ],
        ],
        totals: const [
          ReportTotal('Total de cargos (Bs)', ReportMoney(4000)),
          ReportTotal('Saldo a hoy (Bs)', ReportMoney(7100)),
        ],
      ),
    };

    for (final MapEntry(key: name, value: source) in reports.entries) {
      test(name, () {
        final bytes = generator.generate(source);
        expect(xlsxRecords(bytes), csvLayout(source));
        final b = readXlsx(bytes);
        // Cada celda de una columna numérica es número o está vacía.
        final (from, to) = b.filterRows!;
        for (var c = 0; c < source.columns.length; c++) {
          if (!source.columns[c].numeric) continue;
          for (var r = from + 1; r <= to; r++) {
            final cell = b['${String.fromCharCode(65 + c)}$r'];
            if (cell != null) expect(cell.isNumber, isTrue, reason: cell.ref);
          }
        }
      });
    }
  });

  // El lector de pruebas es quien certifica «XML bien formado»: si aceptara
  // cualquier cosa, las pruebas de escapado no demostrarían nada.
  group('el lector de pruebas rechaza XML mal formado', () {
    for (final bad in [
      '<a>&</a>',
      '<a>A & B</a>',
      '<a>&foo;</a>',
      '<a x="<"/>',
      '<a x=1/>',
      '<a><b></a></b>',
      '<a>',
      '<a/><b/>',
      'texto<a/>',
      '<a>\u0001</a>',
    ]) {
      test(bad.replaceAll('\u0001', r'\u0001'), () {
        expect(() => parseXml(bad), throwsA(isA<XmlFormatError>()));
      });
    }

    test('y acepta el XML correcto con sus entidades', () {
      final node = parseXml(
        '<?xml version="1.0"?>\n<a x="&quot;1&quot;"><t>A &amp; &lt;B&gt; '
        '&#13;&#x41;</t></a>',
      );
      expect(node.attributes['x'], '"1"');
      expect(node.first('t')!.text, 'A & <B> \rA');
    });
  });
}
