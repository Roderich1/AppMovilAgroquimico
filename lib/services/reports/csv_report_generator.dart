/// Generador CSV (EVO-005).
///
/// Dart puro: no toca SQLite, ni widgets, ni el sistema de archivos. Recibe un
/// [ReportTable] y devuelve bytes. Quien los guarde es otro.
///
/// No se añade una dependencia de CSV porque el formato que exige la
/// especificación —BOM, `;`, CRLF, comillas dobladas y neutralización de
/// fórmulas— son unas pocas decenas de líneas, y cualquier paquete habría que
/// configurarlo igual para la última parte, que además no suelen traer.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../domain/reports/report_table.dart';

/// Marca de orden de bytes UTF-8.
///
/// Sin ella Excel abre el archivo en la página de códigos del sistema y
/// "Campaña" se lee "CampaÃ±a".
const List<int> utf8Bom = [0xEF, 0xBB, 0xBF];

/// Separador de campos.
///
/// `;` y no `,` porque el decimal es coma: con `,` las dos cosas colisionan.
const String csvFieldSeparator = ';';

/// Fin de registro. El formato CSV lo define así (RFC 4180) y es lo que
/// esperan las hojas de cálculo de Windows.
const String csvRecordSeparator = '\r\n';

/// Prefijo que desactiva la interpretación de una celda como fórmula.
const String csvFormulaGuard = "'";

/// Caracteres con los que una hoja de cálculo empieza a leer una fórmula.
const Set<String> csvFormulaTriggers = {'=', '+', '-', '@', '\t', '\r'};

class CsvReportGenerator {
  const CsvReportGenerator();

  /// Bytes del CSV, listos para escribir.
  Uint8List generate(ReportTable table) {
    final buffer = StringBuffer();

    void record(List<String> fields) {
      buffer
        ..write(fields.map(_escape).join(csvFieldSeparator))
        ..write(csvRecordSeparator);
    }

    // Todo lo que no sea una celda numérica generada por la aplicación pasa
    // por `_neutralize`, incluidos título, filtros y cabeceras: el nombre de
    // una persona o de una campaña lo escribe el usuario y puede empezar por
    // `=`.
    record([_neutralize(table.title)]);
    record(['Generado', _timestamp(table.generatedAt)]);
    for (final filter in table.filters) {
      record([_neutralize(filter.label), _neutralize(filter.value)]);
    }
    record(const ['']);

    record(table.columns.map((column) => _neutralize(column.header)).toList());
    if (table.isEmpty) {
      record([_neutralize(table.emptyMessage)]);
    } else {
      for (final row in table.rows) {
        record(row.map(_cell).toList());
      }
    }

    if (table.totals.isNotEmpty) {
      record(const ['']);
      for (final total in table.totals) {
        record([_neutralize(total.label), _cell(total.cell)]);
      }
    }

    return Uint8List.fromList([...utf8Bom, ...utf8.encode(buffer.toString())]);
  }

  /// Fecha y hora de generación en el mismo convenio que el resto de la
  /// aplicación: `dd/mm/aaaa hh:mm`, hora local.
  String _timestamp(DateTime moment) {
    final local = moment.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// Texto de una celda, ya decidido si hay que neutralizarlo.
  ///
  /// Las celdas numéricas NO se neutralizan: las genera esta aplicación y son
  /// literales de número. Un importe negativo empieza por `-`, y anteponerle
  /// un apóstrofo lo convertiría en texto justo en la columna que el usuario
  /// necesita sumar. Sólo se neutraliza lo que proviene de datos escritos por
  /// una persona: nombres, conceptos, notas y etiquetas.
  String _cell(ReportCell cell) =>
      cell.isNumeric ? cell.csvText : _neutralize(cell.csvText);

  String _neutralize(String value) {
    final trimmed = value.trimLeft();
    if (trimmed.isEmpty) return value;
    if (!csvFormulaTriggers.contains(trimmed[0])) return value;
    return '$csvFormulaGuard$value';
  }

  /// Entrecomilla y dobla las comillas cuando hace falta (RFC 4180).
  String _escape(String value) {
    final needsQuotes =
        value.contains('"') ||
        value.contains(csvFieldSeparator) ||
        value.contains('\n') ||
        value.contains('\r') ||
        value.startsWith(csvFormulaGuard) ||
        value != value.trim();
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}
