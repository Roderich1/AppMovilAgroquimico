import 'dart:convert';

import 'package:agroquimicos/domain/read_models.dart';
import 'package:agroquimicos/domain/reports/report_composer.dart';
import 'package:agroquimicos/domain/reports/report_table.dart';
import 'package:agroquimicos/services/reports/csv_report_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Generador CSV (EVO-005): BOM, `;`, CRLF, comillas, saltos, español y
/// neutralización de fórmulas.
void main() {
  const generator = CsvReportGenerator();
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

  /// El CSV sin el BOM, ya decodificado.
  String text(ReportTable source) {
    final bytes = generator.generate(source);
    return utf8.decode(bytes.sublist(utf8Bom.length));
  }

  group('formato del archivo', () {
    test('empieza por el BOM UTF-8', () {
      final bytes = generator.generate(
        table(
          rows: const [
            [ReportText('Glifosato'), ReportMoney(50000)],
          ],
        ),
      );
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    });

    test('separa campos con punto y coma', () {
      final content = text(
        table(
          rows: const [
            [ReportText('Glifosato'), ReportMoney(50000)],
          ],
        ),
      );
      expect(content, contains('Glifosato;500,00'));
    });

    test('termina cada registro con CRLF y ninguno con LF suelto', () {
      final content = text(
        table(
          rows: const [
            [ReportText('A'), ReportMoney(1)],
            [ReportText('B'), ReportMoney(2)],
          ],
        ),
      );
      expect(content, endsWith('\r\n'));
      // Todo `\n` va precedido de `\r`.
      for (var i = 0; i < content.length; i++) {
        if (content[i] == '\n') {
          expect(i > 0 && content[i - 1] == '\r', isTrue);
        }
      }
    });

    test('el encabezado declara título, fecha y filtros', () {
      final content = text(
        table(
          title: 'Costo por producto',
          filters: const [ReportFilter('Campaña', 'Campaña 1')],
          rows: const [],
        ),
      );
      expect(content, startsWith('Costo por producto\r\n'));
      expect(content, contains('Generado;06/09/2026'));
      expect(content, contains('Campaña;Campaña 1\r\n'));
    });
  });

  group('escapado', () {
    test('dobla las comillas y entrecomilla la celda', () {
      final content = text(
        table(
          rows: const [
            [ReportText('Chaco "El Alto"'), ReportMoney(0)],
          ],
        ),
      );
      expect(content, contains('"Chaco ""El Alto"""'));
    });

    test('entrecomilla una celda que contiene el separador', () {
      final content = text(
        table(
          rows: const [
            [ReportText('Uno; Dos'), ReportMoney(0)],
          ],
        ),
      );
      expect(content, contains('"Uno; Dos"'));
    });

    test(
      'entrecomilla una celda con salto de línea, sin partir el registro',
      () {
        final content = text(
          table(
            rows: const [
              [ReportText('Primera\nSegunda'), ReportMoney(0)],
              [ReportText('Siguiente'), ReportMoney(0)],
            ],
          ),
        );
        expect(content, contains('"Primera\nSegunda"'));
        expect(content, contains('Siguiente;0,00'));
      },
    );

    test('entrecomilla una celda con espacios en los extremos', () {
      final content = text(
        table(
          rows: const [
            [ReportText('  con espacios  '), ReportMoney(0)],
          ],
        ),
      );
      expect(content, contains('"  con espacios  "'));
    });
  });

  group('español', () {
    test('la ñ y las tildes sobreviven al viaje de ida y vuelta', () {
      final bytes = generator.generate(
        table(
          title: 'Resumen de campaña',
          filters: const [ReportFilter('Campaña', 'Añejo 2026')],
          rows: const [
            [ReportText('Fósforo ácido ñandú Ü'), ReportMoney(0)],
          ],
        ),
      );
      final content = utf8.decode(bytes.sublist(utf8Bom.length));
      expect(content, contains('Resumen de campaña'));
      expect(content, contains('Añejo 2026'));
      expect(content, contains('Fósforo ácido ñandú Ü'));
    });

    test('la ñ se codifica en dos bytes UTF-8, no en uno de Latin-1', () {
      final bytes = generator.generate(
        table(
          rows: const [
            [ReportText('ñ'), ReportMoney(0)],
          ],
        ),
      );
      // C3 B1 es "ñ" en UTF-8; F1 sería Latin-1.
      expect(bytes, containsAllInOrder([0xC3, 0xB1]));
      expect(bytes, isNot(contains(0xF1)));
    });
  });

  group('neutralización de fórmulas', () {
    String firstDataCell(String value) {
      final content = text(
        table(
          rows: [
            [ReportText(value), const ReportMoney(0)],
          ],
        ),
      );
      return content.split('\r\n').firstWhere((line) => line.contains('0,00'));
    }

    for (final trigger in ['=', '+', '@']) {
      test('una celda que empieza por "$trigger" se neutraliza', () {
        final line = firstDataCell('${trigger}SUMA(A1:A9)');
        expect(line, startsWith('"\'$trigger'));
      });
    }

    test('una celda que empieza por "-" también se neutraliza', () {
      expect(firstDataCell('-1+1'), startsWith('"\'-1+1"'));
    });

    test('los espacios iniciales no esconden el disparador', () {
      // Una hoja de cálculo ignora el espacio y sigue viendo una fórmula.
      expect(firstDataCell('   =1+1'), startsWith('"\'   =1+1"'));
    });

    test('una tabulación inicial también se neutraliza', () {
      expect(firstDataCell('\t=1+1'), contains("'"));
    });

    test('un texto corriente NO se toca', () {
      expect(firstDataCell('Glifosato'), startsWith('Glifosato;'));
    });

    test('un IMPORTE NEGATIVO no se neutraliza: es un número', () {
      // Anteponerle un apóstrofo lo convertiría en texto justo en la columna
      // que hay que sumar.
      final content = text(
        table(
          rows: const [
            [ReportText('Pago'), ReportMoney(-20000)],
          ],
        ),
      );
      expect(content, contains('Pago;-200,00\r\n'));
      expect(content, isNot(contains("'-200,00")));
    });

    test('un nombre de persona con fórmula se neutraliza en el filtro', () {
      final content = text(
        table(filters: const [ReportFilter('Persona', '=1+1')], rows: const []),
      );
      expect(content, contains("Persona;\"'=1+1\""));
    });
  });

  group('contenido', () {
    test('escribe cabeceras, filas y totales', () {
      final content = text(
        table(
          rows: const [
            [ReportText('Glifosato'), ReportMoney(50000)],
          ],
          totals: const [ReportTotal('Costo total (Bs)', ReportMoney(50000))],
        ),
      );
      expect(content, contains('Producto;Costo (Bs)\r\n'));
      expect(content, contains('Glifosato;500,00\r\n'));
      expect(content, contains('Costo total (Bs);500,00\r\n'));
    });

    test('sin filas conserva cabeceras, filtros y estado vacío', () {
      final source = composer.inventory(generatedAt: now, lines: const []);
      final content = text(source);
      expect(content, contains('Producto;Unidad;Físico'));
      expect(content, contains(source.emptyMessage));
      expect(content, contains('Valor total (Bs);0,00'));
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
      expect(text(source), contains('Glifosato;5;L;500,00'));
    });

    test('un dataset largo produce una línea por fila', () {
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
      final lines = text(source).split('\r\n');
      expect(lines.where((l) => l.startsWith('Producto ñ ')), hasLength(250));
      // 250 × Bs 1,00 = Bs 250,00.
      expect(text(source), contains('Valor total (Bs);250,00'));
    });
  });
}
