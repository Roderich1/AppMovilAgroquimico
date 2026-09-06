/// Generador PDF (EVO-006).
///
/// Recibe el mismo [ReportTable] que el CSV y devuelve bytes A4. No toca
/// SQLite, ni widgets, ni el sistema de archivos.
///
/// La paginación se calcula antes de dibujar nada para poder escribir
/// "Página 2 de 7" en la primera hoja. Las cabeceras de columna se repiten en
/// todas las páginas (`EVO-006-REQ-002`).
library;

import 'dart:typed_data';

import '../../domain/reports/report_table.dart';
import 'pdf_writer.dart';

class PdfReportGenerator {
  const PdfReportGenerator();

  static const double _margin = 36;
  static const double _titleSize = 16;
  static const double _metaSize = 9;
  static const double _headerSize = 9;
  static const double _bodySize = 9;
  static const double _rowHeight = 15;
  static const double _headerRowHeight = 18;
  static const double _cellPadding = 4;

  Uint8List generate(ReportTable table) {
    final document = PdfDocument();
    final format = document.format;
    final contentWidth = format.width - _margin * 2;
    final widths = _columnWidths(table, contentWidth);

    // Alto que ocupa la portada del reporte en la primera página.
    final introHeight =
        _titleSize + 10 + (table.filters.length + 1) * (_metaSize + 4) + 12;
    // Alto del bloque de totales al final.
    final totalsHeight = table.totals.isEmpty
        ? 0.0
        : 10 + table.totals.length * (_bodySize + 6) + 6;

    final top = format.height - _margin;
    final bottom = _margin + 18; // deja sitio al pie de página

    // ── Paginación ──────────────────────────────────────────────────────────
    final pageRows = <List<int>>[];
    var current = <int>[];
    var available = top - introHeight - _headerRowHeight - bottom;
    for (var i = 0; i < table.rows.length; i++) {
      if (available < _rowHeight) {
        pageRows.add(current);
        current = <int>[];
        available = top - _headerRowHeight - bottom;
      }
      current.add(i);
      available -= _rowHeight;
    }
    // El bloque de totales no se parte: si no cabe tras la última fila, abre
    // una página más.
    if (table.totals.isNotEmpty && available < totalsHeight) {
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
          x: _margin,
          y: y - _titleSize,
          font: PdfFont.helveticaBold,
          size: _titleSize,
        );
        y -= _titleSize + 10;
        for (final line in [
          'Generado: ${_timestamp(table.generatedAt)}',
          for (final filter in table.filters)
            '${filter.label}: ${filter.value}',
        ]) {
          page.text(
            PdfFont.helvetica.ellipsize(line, _metaSize, contentWidth),
            x: _margin,
            y: y - _metaSize,
            font: PdfFont.helvetica,
            size: _metaSize,
            color: PdfGray.muted,
          );
          y -= _metaSize + 4;
        }
        y -= 12;
      }

      y = _drawHeader(page, table, widths, y, contentWidth);

      for (final rowIndex in pageRows[pageIndex]) {
        _drawRow(page, table.rows[rowIndex], widths, y);
        y -= _rowHeight;
      }

      final isLast = pageIndex == pageRows.length - 1;
      if (isLast) {
        if (table.isEmpty) {
          page.text(
            PdfFont.helvetica.ellipsize(
              table.emptyMessage,
              _bodySize,
              contentWidth,
            ),
            x: _margin,
            y: y - _bodySize - 6,
            font: PdfFont.helvetica,
            size: _bodySize,
            color: PdfGray.muted,
          );
          y -= _rowHeight + 6;
        }
        if (table.totals.isNotEmpty) {
          y -= 6;
          page.horizontalRule(
            x: _margin,
            y: y,
            width: contentWidth,
            color: PdfGray.black,
          );
          y -= 4;
          for (final total in table.totals) {
            page.text(
              total.label,
              x: _margin,
              y: y - _bodySize,
              font: PdfFont.helveticaBold,
              size: _bodySize,
            );
            page.textRight(
              total.cell.displayText,
              right: _margin + contentWidth,
              y: y - _bodySize,
              font: PdfFont.helveticaBold,
              size: _bodySize,
            );
            y -= _bodySize + 6;
          }
        }
      }

      final footer = 'Página ${pageIndex + 1} de ${pageRows.length}';
      page.text(
        footer,
        x: _margin,
        y: _margin,
        font: PdfFont.helvetica,
        size: 8,
        color: PdfGray.muted,
      );
      page.textRight(
        table.title,
        right: _margin + contentWidth,
        y: _margin,
        font: PdfFont.helvetica,
        size: 8,
        color: PdfGray.muted,
      );
    }

    return document.build();
  }

  /// Reparte el ancho disponible según el peso declarado por cada columna.
  List<double> _columnWidths(ReportTable table, double contentWidth) {
    final totalWeight = table.columns.fold<double>(
      0,
      (sum, column) => sum + column.weight,
    );
    return [
      for (final column in table.columns)
        contentWidth * column.weight / totalWeight,
    ];
  }

  double _drawHeader(
    PdfPage page,
    ReportTable table,
    List<double> widths,
    double y,
    double contentWidth,
  ) {
    page.fillRect(
      x: _margin,
      y: y - _headerRowHeight + 4,
      width: contentWidth,
      height: _headerRowHeight,
      color: PdfGray.band,
    );
    var x = _margin;
    for (var i = 0; i < table.columns.length; i++) {
      final column = table.columns[i];
      final inner = widths[i] - _cellPadding * 2;
      final label = PdfFont.helveticaBold.ellipsize(
        column.header,
        _headerSize,
        inner,
      );
      if (column.numeric) {
        page.textRight(
          label,
          right: x + widths[i] - _cellPadding,
          y: y - _headerSize - 4,
          font: PdfFont.helveticaBold,
          size: _headerSize,
        );
      } else {
        page.text(
          label,
          x: x + _cellPadding,
          y: y - _headerSize - 4,
          font: PdfFont.helveticaBold,
          size: _headerSize,
        );
      }
      x += widths[i];
    }
    final bottom = y - _headerRowHeight + 4;
    page.horizontalRule(x: _margin, y: bottom, width: contentWidth);
    return bottom - 2;
  }

  void _drawRow(
    PdfPage page,
    List<ReportCell> row,
    List<double> widths,
    double y,
  ) {
    var x = _margin;
    for (var i = 0; i < row.length; i++) {
      final cell = row[i];
      final inner = widths[i] - _cellPadding * 2;
      // Los números NO se recortan: son el dato que hay que leer entero. Si no
      // cupieran se verían pegados a la columna vecina, que es preferible a
      // publicar una cifra amputada. Los textos sí se recortan con elipsis.
      final value = cell.isNumeric
          ? cell.displayText
          : PdfFont.helvetica.ellipsize(cell.displayText, _bodySize, inner);
      if (cell.isNumeric) {
        page.textRight(
          value,
          right: x + widths[i] - _cellPadding,
          y: y - _bodySize - 3,
          font: PdfFont.helvetica,
          size: _bodySize,
        );
      } else {
        page.text(
          value,
          x: x + _cellPadding,
          y: y - _bodySize - 3,
          font: PdfFont.helvetica,
          size: _bodySize,
        );
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
