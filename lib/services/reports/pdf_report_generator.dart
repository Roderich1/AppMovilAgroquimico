/// Generador PDF (EVO-006).
///
/// Recibe el mismo [ReportTable] que el Excel (XLSX) y devuelve bytes A4. No toca
/// SQLite, ni widgets, ni el sistema de archivos.
///
/// La paginación se calcula antes de dibujar nada para poder escribir
/// "Página 2 de 7" en la primera hoja. Las cabeceras de columna se repiten en
/// todas las páginas (`EVO-006-REQ-002`).
///
/// Ronda 2 del rediseño (2026-11-12, P4): **nada se recorta**. Antes cada
/// texto se cortaba con «…» al ancho de un reparto fijo de columnas, y en el
/// estado de cuenta (ocho columnas en A4 vertical) se perdían fechas,
/// conceptos, cabeceras e imputaciones. Ahora:
///  * el ancho de cada columna sale de lo que contiene: fechas e importes
///    caben enteros en una línea; los textos tienen sitio al menos para su
///    palabra más larga y se parten en líneas entre palabras;
///  * la fila crece con su celda más alta; las cabeceras también se parten;
///  * si las columnas no caben en vertical, la hoja va en horizontal;
///  * filtros, mensaje vacío y totales también se parten, no se recortan.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/reports/report_table.dart';
import 'pdf_writer.dart';

/// Disposición calculada de una tabla: hoja, anchos y líneas de cada celda.
/// Se expone para las pruebas (que ningún texto se corte ni se salga).
class PdfTableLayout {
  const PdfTableLayout({
    required this.format,
    required this.columnWidths,
    required this.headerLines,
    required this.rowLines,
  });

  final PdfPageFormat format;
  final List<double> columnWidths;

  /// Líneas de la cabecera de cada columna.
  final List<List<String>> headerLines;

  /// Por fila y por celda, sus líneas.
  final List<List<List<String>>> rowLines;
}

class PdfReportGenerator {
  const PdfReportGenerator();

  static const double margin = 36;
  static const double cellPadding = 4;
  static const double bodySize = 9;
  static const double headerSize = 9;
  static const double _titleSize = 16;
  static const double _metaSize = 9;
  static const double _lineHeight = 11;
  static const double _rowPadding = 3;

  /// Ancho máximo que una sola palabra puede exigir a su columna; una
  /// palabra más larga se parte por caracteres.
  static const double _maxWordWidth = 120;

  Uint8List generate(ReportTable table) {
    final layout = this.layout(table);
    final format = layout.format;
    final document = PdfDocument(format: format);
    final contentWidth = format.width - margin * 2;
    final widths = layout.columnWidths;

    final metaLines = [
      for (final line in [
        'Generado: ${_timestamp(table.generatedAt)}',
        for (final filter in table.filters) '${filter.label}: ${filter.value}',
      ])
        ...wrapText(line, PdfFont.helvetica, _metaSize, contentWidth),
    ];
    final introHeight =
        _titleSize + 10 + metaLines.length * (_metaSize + 4) + 12;
    final headerHeight = _rowHeight(layout.headerLines.fold(1, _maxLines));
    final rowHeights = [
      for (final row in layout.rowLines) _rowHeight(row.fold(1, _maxLines)),
    ];
    // Totales: el rótulo a la izquierda (se parte si hace falta) y el valor a
    // la derecha, entero.
    final totalLines = [
      for (final total in table.totals)
        wrapText(
          total.label,
          PdfFont.helveticaBold,
          bodySize,
          contentWidth -
              PdfFont.helveticaBold.measure(total.cell.displayText, bodySize) -
              16,
        ),
    ];
    final totalsHeight = table.totals.isEmpty
        ? 0.0
        : 10 +
              totalLines.fold<double>(
                0,
                (sum, lines) => sum + lines.length * _lineHeight + 4,
              ) +
              6;
    final emptyLines = table.isEmpty
        ? wrapText(
            table.emptyMessage,
            PdfFont.helvetica,
            bodySize,
            contentWidth,
          )
        : const <String>[];

    final top = format.height - margin;
    final bottom = margin + 18; // deja sitio al pie de página

    // ── Paginación ──────────────────────────────────────────────────────────
    final pageRows = <List<int>>[];
    var current = <int>[];
    var available = top - introHeight - headerHeight - bottom;
    for (var i = 0; i < table.rows.length; i++) {
      if (available < rowHeights[i] && current.isNotEmpty) {
        pageRows.add(current);
        current = <int>[];
        available = top - headerHeight - bottom;
      }
      current.add(i);
      available -= rowHeights[i];
    }
    final tail =
        totalsHeight + (emptyLines.isEmpty ? 0 : emptyLines.length * 12 + 6);
    // El bloque de totales no se parte: si no cabe tras la última fila, abre
    // una página más.
    if (tail > 0 && available < tail && current.isNotEmpty) {
      pageRows.add(current);
      current = <int>[];
    }
    pageRows.add(current);

    // ── Dibujo ──────────────────────────────────────────────────────────────
    for (var pageIndex = 0; pageIndex < pageRows.length; pageIndex++) {
      final page = document.addPage();
      var y = top;

      if (pageIndex == 0) {
        page.text(
          table.title,
          x: margin,
          y: y - _titleSize,
          font: PdfFont.helveticaBold,
          size: _titleSize,
        );
        y -= _titleSize + 10;
        for (final line in metaLines) {
          page.text(
            line,
            x: margin,
            y: y - _metaSize,
            font: PdfFont.helvetica,
            size: _metaSize,
            color: PdfGray.muted,
          );
          y -= _metaSize + 4;
        }
        y -= 12;
      }

      y = _drawHeader(page, table, layout, y, headerHeight, contentWidth);

      for (final (n, rowIndex) in pageRows[pageIndex].indexed) {
        final height = rowHeights[rowIndex];
        if (n.isOdd) {
          page.fillRect(
            x: margin,
            y: y - height,
            width: contentWidth,
            height: height,
            color: PdfGray.stripe,
          );
        }
        _drawRow(
          page,
          table.rows[rowIndex],
          layout.rowLines[rowIndex],
          widths,
          y,
        );
        y -= height;
      }

      final isLast = pageIndex == pageRows.length - 1;
      if (isLast) {
        if (emptyLines.isNotEmpty) {
          y -= 6;
          for (final line in emptyLines) {
            page.text(
              line,
              x: margin,
              y: y - bodySize,
              font: PdfFont.helvetica,
              size: bodySize,
              color: PdfGray.muted,
            );
            y -= 12;
          }
        }
        if (table.totals.isNotEmpty) {
          y -= 6;
          page.horizontalRule(
            x: margin,
            y: y,
            width: contentWidth,
            color: PdfGray.black,
          );
          y -= 4;
          for (final (i, total) in table.totals.indexed) {
            final lines = totalLines[i];
            for (final (j, line) in lines.indexed) {
              page.text(
                line,
                x: margin,
                y: y - bodySize - j * _lineHeight,
                font: PdfFont.helveticaBold,
                size: bodySize,
              );
            }
            page.textRight(
              total.cell.displayText,
              right: margin + contentWidth,
              y: y - bodySize,
              font: PdfFont.helveticaBold,
              size: bodySize,
            );
            y -= lines.length * _lineHeight + 4;
          }
        }
      }

      final footer = 'Página ${pageIndex + 1} de ${pageRows.length}';
      page.text(
        footer,
        x: margin,
        y: margin,
        font: PdfFont.helvetica,
        size: 8,
        color: PdfGray.muted,
      );
      page.textRight(
        table.title,
        right: margin + contentWidth,
        y: margin,
        font: PdfFont.helvetica,
        size: 8,
        color: PdfGray.muted,
      );
    }

    return document.build();
  }

  /// Hoja, anchos de columna y líneas de cada celda.
  PdfTableLayout layout(ReportTable table) {
    final columns = table.columns;
    final count = columns.length;
    final minimum = List<double>.filled(count, 0);
    final natural = List<double>.filled(count, 0);
    void consider(int i, String text, PdfFont font, {required bool nowrap}) {
      if (text.isEmpty) return;
      final full = font.measure(text, bodySize);
      natural[i] = math.max(natural[i], full);
      final needed = nowrap
          ? full
          : text
                .split(RegExp(r'\s+'))
                .map(
                  (word) =>
                      math.min(font.measure(word, bodySize), _maxWordWidth),
                )
                .fold<double>(0, math.max);
      minimum[i] = math.max(minimum[i], needed);
    }

    for (var i = 0; i < count; i++) {
      consider(i, columns[i].header, PdfFont.helveticaBold, nowrap: false);
    }
    for (final row in table.rows) {
      for (var i = 0; i < count; i++) {
        final cell = row[i];
        consider(i, cell.displayText, PdfFont.helvetica, nowrap: _noWrap(cell));
      }
    }
    const pad = cellPadding * 2 + 1;
    for (var i = 0; i < count; i++) {
      minimum[i] += pad;
      natural[i] += pad;
    }
    final minSum = minimum.fold<double>(0, (a, b) => a + b);
    final naturalSum = natural.fold<double>(0, (a, b) => a + b);
    const portrait = PdfPageFormat.a4;
    const landscape = PdfPageFormat.a4Landscape;
    final portraitWidth = portrait.width - margin * 2;
    // Horizontal si en vertical no caben ni los mínimos, o si una tabla ancha
    // (siete columnas o más) tendría que partir sus textos.
    final format =
        minSum > portraitWidth || (count >= 7 && naturalSum > portraitWidth)
        ? landscape
        : portrait;
    final contentWidth = format.width - margin * 2;
    final widths = _distribute(minimum, natural, [
      for (final column in columns) column.weight,
    ], contentWidth);

    List<String> linesOf(
      String text,
      PdfFont font,
      double width,
      bool nowrap,
    ) => nowrap ? [text] : wrapText(text, font, bodySize, width);
    return PdfTableLayout(
      format: format,
      columnWidths: widths,
      headerLines: [
        for (var i = 0; i < count; i++)
          linesOf(
            columns[i].header,
            PdfFont.helveticaBold,
            widths[i] - cellPadding * 2,
            false,
          ),
      ],
      rowLines: [
        for (final row in table.rows)
          [
            for (var i = 0; i < count; i++)
              linesOf(
                row[i].displayText,
                PdfFont.helvetica,
                widths[i] - cellPadding * 2,
                _noWrap(row[i]),
              ),
          ],
      ],
    );
  }

  /// Importes y fechas no se parten: son el dato que hay que leer entero.
  static bool _noWrap(ReportCell cell) => cell.isNumeric || cell is ReportDate;

  /// Reparte [available]: cada columna recibe su mínimo; lo que sobra va
  /// primero a las columnas que lo necesitan para no partirse (en proporción
  /// a lo que les falta) y el resto, según su peso. Si los mínimos no caben
  /// ni en horizontal, se reducen las columnas que se pueden partir.
  static List<double> _distribute(
    List<double> minimum,
    List<double> natural,
    List<double> weights,
    double available,
  ) {
    final widths = [...minimum];
    var extra = available - widths.fold<double>(0, (a, b) => a + b);
    if (extra < 0) {
      // Último recurso: escalar todo (las palabras largas se parten).
      final factor = available / (available - extra);
      return [for (final w in widths) w * factor];
    }
    final wants = [
      for (var i = 0; i < widths.length; i++) natural[i] - widths[i],
    ];
    final wanted = wants.fold<double>(0, (a, b) => a + b);
    if (wanted > 0) {
      final share = math.min(1.0, extra / wanted);
      for (var i = 0; i < widths.length; i++) {
        widths[i] += wants[i] * share;
      }
      extra -= wanted * share;
    }
    if (extra > 0) {
      final totalWeight = weights.fold<double>(0, (a, b) => a + b);
      for (var i = 0; i < widths.length; i++) {
        widths[i] += extra * weights[i] / totalWeight;
      }
    }
    return widths;
  }

  static int _maxLines(int lines, List<String> cell) =>
      math.max(lines, cell.length);

  static double _rowHeight(int lines) =>
      lines * _lineHeight + _rowPadding * 2 + 1;

  double _drawHeader(
    PdfPage page,
    ReportTable table,
    PdfTableLayout layout,
    double y,
    double height,
    double contentWidth,
  ) {
    page.fillRect(
      x: margin,
      y: y - height,
      width: contentWidth,
      height: height,
      color: PdfGray.band,
    );
    var x = margin;
    for (var i = 0; i < table.columns.length; i++) {
      final column = table.columns[i];
      final width = layout.columnWidths[i];
      for (final (j, line) in layout.headerLines[i].indexed) {
        final baseline = y - _rowPadding - headerSize - j * _lineHeight;
        if (column.numeric) {
          page.textRight(
            line,
            right: x + width - cellPadding,
            y: baseline,
            font: PdfFont.helveticaBold,
            size: headerSize,
          );
        } else {
          page.text(
            line,
            x: x + cellPadding,
            y: baseline,
            font: PdfFont.helveticaBold,
            size: headerSize,
          );
        }
      }
      x += width;
    }
    final bottom = y - height;
    page.horizontalRule(x: margin, y: bottom, width: contentWidth);
    return bottom;
  }

  void _drawRow(
    PdfPage page,
    List<ReportCell> row,
    List<List<String>> lines,
    List<double> widths,
    double y,
  ) {
    var x = margin;
    for (var i = 0; i < row.length; i++) {
      final cell = row[i];
      for (final (j, line) in lines[i].indexed) {
        final baseline = y - _rowPadding - bodySize - j * _lineHeight;
        if (cell.isNumeric) {
          page.textRight(
            line,
            right: x + widths[i] - cellPadding,
            y: baseline,
            font: PdfFont.helvetica,
            size: bodySize,
          );
        } else {
          page.text(
            line,
            x: x + cellPadding,
            y: baseline,
            font: PdfFont.helvetica,
            size: bodySize,
          );
        }
      }
      x += widths[i];
    }
  }

  String _timestamp(DateTime moment) {
    final local = moment.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// Parte [text] en líneas que no superan [maxWidth] a [size] puntos, entre
/// palabras. Una palabra que no cabe sola se parte por caracteres. No
/// recorta nada: unir las líneas devuelve el texto (con los espacios
/// normalizados).
List<String> wrapText(String text, PdfFont font, double size, double maxWidth) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final lines = <String>[];
  var current = '';
  for (var word in words) {
    final candidate = current.isEmpty ? word : '$current $word';
    if (font.measure(candidate, size) <= maxWidth) {
      current = candidate;
      continue;
    }
    if (current.isNotEmpty) {
      lines.add(current);
      current = '';
    }
    // Palabra más ancha que la columna: por caracteres.
    while (font.measure(word, size) > maxWidth && word.length > 1) {
      var end = word.length - 1;
      while (end > 1 && font.measure(word.substring(0, end), size) > maxWidth) {
        end--;
      }
      lines.add(word.substring(0, end));
      word = word.substring(end);
    }
    current = word;
  }
  if (current.isNotEmpty || lines.isEmpty) lines.add(current);
  return lines;
}
