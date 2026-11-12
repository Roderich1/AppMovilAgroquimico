/// Generador Excel (XLSX) de reportes (2026-11-12, sustituye al CSV de EVO-005).
///
/// Dart puro: no toca SQLite, ni widgets, ni el sistema de archivos. Recibe un
/// [ReportTable] y devuelve los bytes de un libro Office Open XML (SpreadsheetML)
/// con una sola hoja. Quien los guarde es otro.
///
/// No se añade una dependencia de Excel: un libro mínimo son seis partes XML
/// dentro de un ZIP, y el ZIP ya lo da `package:archive`, que usa el respaldo.
///
/// ## Qué conserva del CSV
///
/// La hoja tiene los mismos registros, en el mismo orden, que daba el CSV:
/// título, «Generado», un registro por filtro, una fila en blanco, la cabecera,
/// las filas (o el mensaje de estado vacío), una fila en blanco y los totales.
/// Cada valor va en la misma columna que ocupaba en el CSV.
///
/// ## Decisiones
///
/// - **Números como números.** [ReportTable] no trae texto formateado sino los
///   enteros escalados (centavos, milésimas, m²). La celda se escribe con el
///   decimal exacto que sale de [decimalFromScaled] —división y módulo
///   enteros, sin `double`— y punto decimal, que es lo que exige el formato.
///   El formato de número sólo decide cómo se ve: importes con dos decimales y
///   separador de miles, conteos con separador de miles, cantidades y áreas en
///   «General». La hoja de cálculo pone los separadores de su propio locale.
/// - **Una ausencia nunca es cero.** [ReportBlank] y un texto vacío no escriben
///   celda: queda vacía, igual que el campo vacío del CSV.
/// - **Fechas como fechas.** [ReportDate] se escribe como número de serie con
///   formato `dd/mm/yyyy`, derivado del MISMO texto `dd/mm/aaaa` que muestran
///   la app y el PDF (`formatDate`), así que no puede caer en otro día. Si ese
///   texto no es una fecha válida se escribe tal cual, como texto.
/// - **Textos como texto, nunca como fórmula.** Todo texto va en una celda
///   `inlineStr`, que Excel y LibreOffice leen como cadena: no hay elemento
///   `<f>` en ningún sitio del libro. Por eso aquí no se antepone el apóstrofo
///   del CSV, que habría alterado el dato. Además, los textos que empiezan por
///   un disparador de fórmula llevan el estilo `quotePrefix`, para que siga
///   siendo texto si alguien edita la celda y pulsa Intro.
/// - **«Generado»** se conserva como texto `dd/mm/aaaa hh:mm`, como en el CSV:
///   es un rótulo del reporte, no un dato para operar.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/reports/report_table.dart';

/// Tipo MIME de un libro `.xlsx`.
const String xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Longitud máxima del nombre de una hoja en Excel.
const int xlsxSheetNameMaxLength = 31;

/// Caracteres con los que una hoja de cálculo empieza a leer una fórmula al
/// editar una celda. Sólo deciden el estilo `quotePrefix`: el texto se guarda
/// siempre íntegro.
const Set<String> xlsxFormulaTriggers = {'=', '+', '-', '@', '\t', '\r'};

/// Índices de estilo (`cellXfs` de `styles.xml`).
abstract final class _Style {
  static const int normal = 0;
  static const int bold = 1;
  static const int money = 2;
  static const int count = 3;
  static const int date = 4;
  static const int quoted = 5;
  static const int boldQuoted = 6;
}

class XlsxReportGenerator {
  const XlsxReportGenerator();

  /// Bytes del libro, listos para escribir.
  Uint8List generate(ReportTable table) {
    final sheetName = xlsxSheetName(table.title);
    final rows = <int, List<_Cell?>>{};
    var next = 1;

    void record(List<_Cell?> cells) => rows[next++] = cells;
    void blank() => next++;

    record([_text(table.title, bold: true)]);
    record([_text('Generado'), _text(_timestamp(table.generatedAt))]);
    for (final filter in table.filters) {
      record([_text(filter.label), _text(filter.value)]);
    }
    blank();

    final headerRow = next;
    record([
      for (final column in table.columns) _text(column.header, bold: true),
    ]);
    if (table.isEmpty) {
      // El mensaje queda FUERA del autofiltro: no es un dato que filtrar.
      record([_text(table.emptyMessage)]);
    } else {
      for (final row in table.rows) {
        record([for (final cell in row) _cell(cell)]);
      }
    }
    final lastDataRow = table.isEmpty
        ? headerRow
        : headerRow + table.rows.length;

    if (table.totals.isNotEmpty) {
      blank();
      for (final total in table.totals) {
        record([_text(total.label), _cell(total.cell)]);
      }
    }

    final lastColumn = _columnName(table.columns.length);
    final filterRange = 'A$headerRow:$lastColumn$lastDataRow';

    var widest = table.columns.length;
    for (final cells in rows.values) {
      if (cells.length > widest) widest = cells.length;
    }
    final lastRow = next - 1;

    final sheet = _sheetXml(
      rows: rows,
      table: table,
      headerRow: headerRow,
      filterRange: filterRange,
      dimension: 'A1:${_columnName(widest)}$lastRow',
    );

    final archive = Archive();
    void part(String name, String xml) =>
        archive.addFile(ArchiveFile.bytes(name, utf8.encode(xml)));

    part('[Content_Types].xml', _contentTypes);
    part('_rels/.rels', _rootRels);
    part('xl/workbook.xml', _workbookXml(sheetName, filterRange));
    part('xl/_rels/workbook.xml.rels', _workbookRels);
    part('xl/styles.xml', _stylesXml);
    part('xl/worksheets/sheet1.xml', sheet);

    // La fecha de los miembros del ZIP es la de generación: el mismo reporte
    // produce los mismos bytes.
    return ZipEncoder().encodeBytes(
      archive,
      modified: table.generatedAt.toLocal(),
    );
  }

  String _sheetXml({
    required Map<int, List<_Cell?>> rows,
    required ReportTable table,
    required int headerRow,
    required String filterRange,
    required String dimension,
  }) {
    final b = StringBuffer()
      ..write(_xmlDeclaration)
      ..write('<worksheet xmlns="$_mainNs" xmlns:r="$_relNs">')
      ..write('<dimension ref="$dimension"/>')
      // Inmoviliza todo lo que hay hasta la cabecera incluida: al desplazar
      // las filas, las columnas siguen rotuladas.
      ..write('<sheetViews><sheetView workbookViewId="0">')
      ..write(
        '<pane ySplit="$headerRow" topLeftCell="A${headerRow + 1}" '
        'activePane="bottomLeft" state="frozen"/>',
      )
      ..write(
        '<selection pane="bottomLeft" activeCell="A${headerRow + 1}" '
        'sqref="A${headerRow + 1}"/>',
      )
      ..write('</sheetView></sheetViews>')
      ..write('<sheetFormatPr defaultRowHeight="15"/>')
      ..write('<cols>');
    for (var i = 0; i < table.columns.length; i++) {
      final width = (table.columns[i].weight * 12).clamp(10, 60);
      b.write(
        '<col min="${i + 1}" max="${i + 1}" '
        'width="${width.toStringAsFixed(1)}" customWidth="1"/>',
      );
    }
    b
      ..write('</cols>')
      ..write('<sheetData>');
    final numbers = rows.keys.toList()..sort();
    for (final r in numbers) {
      final cells = rows[r]!;
      if (cells.every((cell) => cell == null)) continue;
      b.write('<row r="$r">');
      for (var c = 0; c < cells.length; c++) {
        final cell = cells[c];
        if (cell == null) continue;
        cell.write(b, '${_columnName(c + 1)}$r');
      }
      b.write('</row>');
    }
    b
      ..write('</sheetData>')
      ..write('<autoFilter ref="$filterRange"/>')
      ..write('</worksheet>');
    return b.toString();
  }

  String _workbookXml(String sheetName, String filterRange) {
    final absolute = filterRange
        .split(':')
        .map(
          (ref) => ref.replaceAllMapped(
            RegExp(r'^([A-Z]+)(\d+)$'),
            (m) => '\$${m[1]}\$${m[2]}',
          ),
        )
        .join(':');
    final quotedName = "'${sheetName.replaceAll("'", "''")}'";
    return '$_xmlDeclaration'
        '<workbook xmlns="$_mainNs" xmlns:r="$_relNs">'
        '<bookViews><workbookView/></bookViews>'
        '<sheets><sheet name="${xmlEscape(sheetName)}" sheetId="1" '
        'r:id="rId1"/></sheets>'
        // Nombre oculto que Excel crea para todo autofiltro; LibreOffice lo usa
        // para reconocer el rango.
        '<definedNames><definedName name="_xlnm._FilterDatabase" '
        'localSheetId="0" hidden="1">'
        '${xmlEscape('$quotedName!$absolute')}</definedName></definedNames>'
        '</workbook>';
  }

  _Cell? _cell(ReportCell cell) => switch (cell) {
    ReportText(:final value) => _text(value),
    ReportMoney(:final minor) => _Number(_number(minor, 2), _Style.money),
    ReportQuantity(:final base) => _Number(_number(base, 3), _Style.normal),
    ReportArea(:final areaM2) => _Number(_number(areaM2, 4), _Style.normal),
    ReportCount(:final value) => _Number(_number(value, 0), _Style.count),
    ReportDate() => _date(cell.csvText),
    ReportBlank() => null,
  };

  /// Decimal exacto con punto, sin separador de miles ni ceros sobrantes.
  String _number(int scaled, int decimals) => decimalFromScaled(
    scaled,
    decimals,
    trimTrailingZeros: decimals != 2,
  ).replaceAll(decimalSeparator, '.');

  /// `dd/mm/aaaa` → número de serie de Excel (días desde 1899-12-30).
  _Cell? _date(String text) {
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(text);
    if (match == null) return _text(text);
    final day = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final year = int.parse(match[3]!);
    final date = DateTime.utc(year, month, day);
    // Antes de marzo de 1900 el calendario de Excel tiene el 29/02/1900 que no
    // existió; una fecha así se deja como texto antes que desplazarla un día.
    if (date.month != month || date.day != day || year < 1901) {
      return _text(text);
    }
    final serial = date.difference(DateTime.utc(1899, 12, 30)).inDays;
    return _Number('$serial', _Style.date);
  }

  _Cell? _text(String value, {bool bold = false}) {
    if (value.isEmpty) return null;
    final quoted = _startsLikeFormula(value);
    final style = switch ((bold, quoted)) {
      (true, true) => _Style.boldQuoted,
      (true, false) => _Style.bold,
      (false, true) => _Style.quoted,
      (false, false) => _Style.normal,
    };
    return _Text(value, style);
  }

  /// Mismo criterio que tenía el CSV: el disparador cuenta aunque vaya detrás
  /// de espacios, y `\t`/`\r` son disparadores por sí mismos.
  bool _startsLikeFormula(String value) {
    final trimmed = value.trimLeft();
    final leading = value.substring(0, value.length - trimmed.length);
    return leading.split('').any(xlsxFormulaTriggers.contains) ||
        (trimmed.isNotEmpty && xlsxFormulaTriggers.contains(trimmed[0]));
  }

  String _timestamp(DateTime moment) {
    final local = moment.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

sealed class _Cell {
  const _Cell(this.style);
  final int style;
  void write(StringBuffer b, String ref);
}

final class _Text extends _Cell {
  const _Text(this.value, super.style);
  final String value;

  @override
  void write(StringBuffer b, String ref) {
    b.write('<c r="$ref" t="inlineStr"');
    if (style != _Style.normal) b.write(' s="$style"');
    b
      ..write('><is><t xml:space="preserve">')
      ..write(xlsxText(value))
      ..write('</t></is></c>');
  }
}

final class _Number extends _Cell {
  const _Number(this.value, super.style);
  final String value;

  @override
  void write(StringBuffer b, String ref) {
    b.write('<c r="$ref"');
    if (style != _Style.normal) b.write(' s="$style"');
    b.write('><v>$value</v></c>');
  }
}

/// Letra de columna: 1 → A, 26 → Z, 27 → AA.
String _columnName(int index) {
  var n = index;
  var letters = '';
  while (n > 0) {
    letters = String.fromCharCode(65 + (n - 1) % 26) + letters;
    n = (n - 1) ~/ 26;
  }
  return letters;
}

/// Nombre de hoja válido para Excel a partir del título del reporte.
///
/// Excel rechaza el libro entero si el nombre tiene `[]:*?/\`, pasa de 31
/// caracteres, empieza o termina por apóstrofo, está vacío o es «History».
String xlsxSheetName(String title) {
  var name = title
      .replaceAll(RegExp(r'[\[\]:*?/\\]'), '-')
      .replaceAll(RegExp(r'[\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  name = name.replaceAll(RegExp(r"^['\s]+|['\s]+$"), '');
  if (name.length > xlsxSheetNameMaxLength) {
    var end = xlsxSheetNameMaxLength;
    // No partir un par sustituto (un emoji, por ejemplo).
    final unit = name.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end--;
    name = name.substring(0, end);
    name = name.replaceAll(RegExp(r"['\s]+$"), '');
  }
  if (name.isEmpty || name.toLowerCase() == 'history') return 'Reporte';
  return name;
}

/// Escapa los cinco caracteres reservados de XML.
String xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Texto de una celda: XML escapado y, además, las reglas de SpreadsheetML.
///
/// - Un carácter de control que XML 1.0 no admite (ni siquiera como
///   referencia) se escribe `_xHHHH_`, la forma que Excel y LibreOffice
///   decodifican.
/// - Un `_xHHHH_` literal escrito por el usuario se protege como
///   `_x005F_xHHHH_` para que no se lea como uno de esos escapes.
/// - El retorno de carro va como `&#13;`: crudo, un lector XML lo convertiría
///   en salto de línea.
String xlsxText(String value) {
  final b = StringBuffer();
  final escapePattern = RegExp(r'_x[0-9A-Fa-f]{4}_');
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    final char = value[i];
    if (char == '_' && escapePattern.matchAsPrefix(value, i) != null) {
      b.write('_x005F_');
    } else if (char == '&') {
      b.write('&amp;');
    } else if (char == '<') {
      b.write('&lt;');
    } else if (char == '>') {
      b.write('&gt;');
    } else if (char == '"') {
      b.write('&quot;');
    } else if (char == "'") {
      b.write('&apos;');
    } else if (unit == 0x0D) {
      b.write('&#13;');
    } else if ((unit < 0x20 && unit != 0x09 && unit != 0x0A) ||
        unit == 0xFFFE ||
        unit == 0xFFFF) {
      b.write('_x${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}_');
    } else {
      b.write(char);
    }
  }
  return b.toString();
}

const String _xmlDeclaration =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const String _mainNs =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _pkgRelNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';

const String _contentTypes =
    '$_xmlDeclaration'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" '
    'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/'
    'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/'
    'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/'
    'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '</Types>';

const String _rootRels =
    '$_xmlDeclaration'
    '<Relationships xmlns="$_pkgRelNs">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/>'
    '</Relationships>';

const String _workbookRels =
    '$_xmlDeclaration'
    '<Relationships xmlns="$_pkgRelNs">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/worksheet" '
    'Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

/// Estilos, en el orden de [_Style]. `numFmtId` 3 y 4 son los integrados
/// `#,##0` y `#,##0.00`; el 164 es la fecha `dd/mm/yyyy`.
const String _stylesXml =
    '$_xmlDeclaration'
    '<styleSheet xmlns="$_mainNs">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/>'
    '</numFmts>'
    '<fonts count="2">'
    '<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
    '</fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
    '</border></borders>'
    '<cellStyleXfs count="1">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="7">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" '
    'quotePrefix="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyFont="1" quotePrefix="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/>'
    '</cellStyles>'
    '</styleSheet>';
