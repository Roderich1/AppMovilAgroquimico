/// Escritor PDF mínimo, en Dart puro y sin dependencias.
///
/// ## Por qué no se usa el paquete `pdf`
///
/// La especificación proponía `pdf ^3.13.0` **como candidato**, y exigía
/// comprobar la compatibilidad real antes de cerrar la selección. No la hay:
/// todas las versiones publicadas de `pdf` dependen de `archive <4.1.0`,
/// mientras la aplicación usa `archive ^4.2.0`, que es la librería con la que
/// se construye y se lee el contenedor `.agrobackup`.
///
/// La única forma de añadir `pdf` sería degradar `archive` por debajo de
/// 4.1.0, es decir, cambiar la librería del formato de respaldo, que es
/// justamente lo que EVOLUTION-2 tiene prohibido tocar; además arrastraría
/// nueve paquetes nuevos. Escribir el PDF aquí no añade ninguna dependencia,
/// no toca el respaldo y deja el control de la codificación de caracteres,
/// que es lo que hace falta para la ñ y las tildes.
///
/// ## Qué genera
///
/// PDF 1.4 con las fuentes estándar Helvetica y Helvetica-Bold en
/// `WinAnsiEncoding`, que cubre todo el español. Los flujos de contenido van
/// **sin comprimir**: un reporte tabular es pequeño, y así el archivo es
/// inspeccionable y los tests pueden comprobar de verdad lo que dice.
///
/// No conoce SQLite, ni widgets, ni el sistema de archivos.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Medidas de una hoja A4 en puntos PostScript (1/72").
class PdfPageFormat {
  const PdfPageFormat(this.width, this.height);

  static const a4 = PdfPageFormat(595.28, 841.89);

  final double width;
  final double height;
}

/// Una de las dos fuentes estándar que usa el reporte.
///
/// Las anchuras provienen de las métricas AFM de Adobe y permiten alinear a la
/// derecha y recortar por ancho real. Sin ellas un nombre largo se saldría de
/// su columna y pisaría la siguiente.
class PdfFont {
  const PdfFont._(this.baseFont, this._widths);

  static const helvetica = PdfFont._('Helvetica', _helveticaWidths);
  static const helveticaBold = PdfFont._(
    'Helvetica-Bold',
    _helveticaBoldWidths,
  );

  final String baseFont;
  final List<int> _widths;

  /// Ancho de [text] a [size] puntos.
  double measure(String text, double size) {
    var total = 0;
    for (final code in _winAnsiCodes(text)) {
      total += code >= 32 && code <= 255 ? _widths[code - 32] : 556;
    }
    return total * size / 1000;
  }

  /// [text] recortado con `…` para que no supere [maxWidth].
  String ellipsize(String text, double size, double maxWidth) {
    if (measure(text, size) <= maxWidth) return text;
    const ellipsis = '…';
    final ellipsisWidth = measure(ellipsis, size);
    if (ellipsisWidth > maxWidth) return '';
    var end = text.length;
    while (end > 0) {
      end--;
      final candidate = text.substring(0, end);
      if (measure(candidate, size) + ellipsisWidth <= maxWidth) {
        return '$candidate$ellipsis';
      }
    }
    return ellipsis;
  }
}

/// Gris de 0 (negro) a 1 (blanco).
class PdfGray {
  const PdfGray(this.value);
  static const black = PdfGray(0);
  static const text = PdfGray(0.1);
  static const muted = PdfGray(0.42);
  static const rule = PdfGray(0.75);
  static const band = PdfGray(0.91);
  final double value;
}

/// Una página en construcción.
class PdfPage {
  PdfPage(this.format);

  final PdfPageFormat format;
  final StringBuffer _content = StringBuffer();

  /// Escribe [text] con la esquina inferior izquierda en ([x], [y]).
  ///
  /// El origen del PDF está abajo a la izquierda; quien llama trabaja con esa
  /// convención para no duplicar la conversión en cada llamada.
  void text(
    String text, {
    required double x,
    required double y,
    required PdfFont font,
    required double size,
    PdfGray color = PdfGray.text,
  }) {
    if (text.isEmpty) return;
    _content
      ..write('BT ')
      ..write(_number(color.value))
      ..write(' g /')
      ..write(font == PdfFont.helveticaBold ? 'F2' : 'F1')
      ..write(' ')
      ..write(_number(size))
      ..write(' Tf ')
      ..write(_number(x))
      ..write(' ')
      ..write(_number(y))
      ..write(' Td ')
      ..write(_literal(text))
      ..write(' Tj ET\n');
  }

  /// Texto alineado a la derecha de [right].
  void textRight(
    String value, {
    required double right,
    required double y,
    required PdfFont font,
    required double size,
    PdfGray color = PdfGray.text,
  }) => text(
    value,
    x: right - font.measure(value, size),
    y: y,
    font: font,
    size: size,
    color: color,
  );

  /// Rectángulo relleno.
  void fillRect({
    required double x,
    required double y,
    required double width,
    required double height,
    required PdfGray color,
  }) {
    _content
      ..write(_number(color.value))
      ..write(' g ')
      ..write(_number(x))
      ..write(' ')
      ..write(_number(y))
      ..write(' ')
      ..write(_number(width))
      ..write(' ')
      ..write(_number(height))
      ..write(' re f\n');
  }

  /// Línea horizontal de 0,5 pt.
  void horizontalRule({
    required double x,
    required double y,
    required double width,
    PdfGray color = PdfGray.rule,
  }) {
    _content
      ..write(_number(color.value))
      ..write(' G 0.5 w ')
      ..write(_number(x))
      ..write(' ')
      ..write(_number(y))
      ..write(' m ')
      ..write(_number(x + width))
      ..write(' ')
      ..write(_number(y))
      ..write(' l S\n');
  }
}

/// Documento completo.
class PdfDocument {
  PdfDocument({this.format = PdfPageFormat.a4});

  final PdfPageFormat format;
  final List<PdfPage> pages = [];

  PdfPage addPage() {
    final page = PdfPage(format);
    pages.add(page);
    return page;
  }

  /// Serializa el documento.
  ///
  /// Objetos: 1 catálogo, 2 árbol de páginas, 3 y 4 fuentes, y a partir de 5
  /// un par (página, contenido) por hoja.
  Uint8List build() {
    if (pages.isEmpty) addPage();

    final bytes = BytesBuilder();
    final offsets = <int>[];

    void write(String value) => bytes.add(latin1.encode(value));

    write('%PDF-1.4\n');
    // Comentario binario: le dice a cualquier herramienta que el archivo no es
    // de texto plano y evita transferencias que "arreglen" los saltos de línea.
    bytes.add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    final pageObjectIds = [for (var i = 0; i < pages.length; i++) 5 + i * 2];

    void object(int id, String body) {
      while (offsets.length < id) {
        offsets.add(0);
      }
      offsets[id - 1] = bytes.length;
      write('$id 0 obj\n$body\nendobj\n');
    }

    object(1, '<< /Type /Catalog /Pages 2 0 R >>');
    object(
      2,
      '<< /Type /Pages /Kids [${pageObjectIds.map((id) => '$id 0 R').join(' ')}] '
      '/Count ${pages.length} >>',
    );
    object(
      3,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>',
    );
    object(
      4,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
      '/Encoding /WinAnsiEncoding >>',
    );

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pageId = pageObjectIds[i];
      final contentId = pageId + 1;
      final stream = page._content.toString();
      object(
        pageId,
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_number(page.format.width)} '
        '${_number(page.format.height)}] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
        '/Contents $contentId 0 R >>',
      );
      object(
        contentId,
        '<< /Length ${latin1.encode(stream).length} >>\n'
        'stream\n$stream'
        'endstream',
      );
    }

    final xrefOffset = bytes.length;
    write('xref\n0 ${offsets.length + 1}\n');
    write('0000000000 65535 f \n');
    for (final offset in offsets) {
      write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    write(
      'trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xrefOffset\n%%EOF\n',
    );

    return bytes.toBytes();
  }
}

/// Número con la precisión justa y sin notación exponencial, que el formato
/// PDF no admite.
String _number(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e9) {
    return value.toInt().toString();
  }
  var text = value.toStringAsFixed(3);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

/// Cadena literal PDF, con los tres caracteres que hay que escapar.
String _literal(String value) {
  final buffer = StringBuffer('(');
  for (final code in _winAnsiCodes(value)) {
    if (code == 0x28 || code == 0x29 || code == 0x5C) {
      buffer.write('\\');
    }
    buffer.writeCharCode(code);
  }
  return (buffer..write(')')).toString();
}

/// Códigos WinAnsi de [value].
///
/// Latin-1 se mapea directamente, que es lo que cubre el español completo. Los
/// pocos signos tipográficos que WinAnsi coloca en 128-159 se traducen a mano;
/// cualquier otro carácter se sustituye por `?` en vez de romper el archivo.
Iterable<int> _winAnsiCodes(String value) sync* {
  for (final rune in value.runes) {
    if (rune == 0x0A || rune == 0x0D || rune == 0x09) {
      yield 0x20;
    } else if (rune >= 0x20 && rune <= 0x7E) {
      yield rune;
    } else if (rune >= 0xA0 && rune <= 0xFF) {
      yield rune;
    } else {
      yield _winAnsiExtras[rune] ?? 0x3F;
    }
  }
}

const Map<int, int> _winAnsiExtras = {
  0x20AC: 128, // €
  0x201A: 130,
  0x0192: 131,
  0x201E: 132,
  0x2026: 133, // …
  0x2020: 134,
  0x2021: 135,
  0x02C6: 136,
  0x2030: 137,
  0x0160: 138,
  0x2039: 139,
  0x0152: 140,
  0x017D: 142,
  0x2018: 145,
  0x2019: 146, // ’
  0x201C: 147,
  0x201D: 148,
  0x2022: 149, // •
  0x2013: 150, // –
  0x2014: 151, // —
  0x02DC: 152,
  0x2122: 153,
  0x0161: 154,
  0x203A: 155,
  0x0153: 156,
  0x017E: 158,
  0x0178: 159,
};

/// Anchuras AFM de Helvetica para los códigos WinAnsi 32-255, en milésimas de
/// em.
const List<int> _helveticaWidths = [
  278,
  278,
  355,
  556,
  556,
  889,
  667,
  191,
  333,
  333,
  389,
  584,
  278,
  333,
  278,
  278,
  556,
  556,
  556,
  556,
  556,
  556,
  556,
  556,
  556,
  556,
  278,
  278,
  584,
  584,
  584,
  556,
  1015,
  667,
  667,
  722,
  722,
  667,
  611,
  778,
  722,
  278,
  500,
  667,
  556,
  833,
  722,
  778,
  667,
  778,
  722,
  667,
  611,
  722,
  667,
  944,
  667,
  667,
  611,
  278,
  278,
  278,
  469,
  556,
  333,
  556,
  556,
  500,
  556,
  556,
  278,
  556,
  556,
  222,
  222,
  500,
  222,
  833,
  556,
  556,
  556,
  556,
  333,
  500,
  278,
  556,
  500,
  722,
  500,
  500,
  500,
  334,
  260,
  334,
  584,
  556,
  556,
  556,
  222,
  556,
  333,
  1000,
  556,
  556,
  333,
  1000,
  667,
  333,
  1000,
  556,
  611,
  556,
  556,
  222,
  222,
  333,
  333,
  350,
  556,
  1000,
  333,
  1000,
  500,
  333,
  944,
  556,
  500,
  667,
  278,
  333,
  556,
  556,
  556,
  556,
  260,
  556,
  333,
  737,
  370,
  556,
  584,
  333,
  737,
  333,
  400,
  584,
  333,
  333,
  333,
  556,
  537,
  278,
  333,
  333,
  365,
  556,
  834,
  834,
  834,
  611,
  667,
  667,
  667,
  667,
  667,
  667,
  1000,
  722,
  667,
  667,
  667,
  667,
  278,
  278,
  278,
  278,
  722,
  722,
  778,
  778,
  778,
  778,
  778,
  584,
  778,
  722,
  722,
  722,
  722,
  667,
  667,
  611,
  556,
  556,
  556,
  556,
  556,
  556,
  889,
  500,
  556,
  556,
  556,
  556,
  278,
  278,
  278,
  278,
  556,
  556,
  556,
  556,
  556,
  556,
  556,
  584,
  611,
  556,
  556,
  556,
  556,
  500,
  556,
  500,
];

/// Anchuras AFM de Helvetica-Bold para los códigos WinAnsi 32-255.
const List<int> _helveticaBoldWidths = [
  278,
  333,
  474,
  556,
  556,
  889,
  722,
  238,
  333,
  333,
  389,
  584,
  278,
  333,
  278,
  278,
  556,
  556,
  556,
  556,
  556,
  556,
  556,
  556,
  556,
  556,
  333,
  333,
  584,
  584,
  584,
  611,
  975,
  722,
  722,
  722,
  722,
  667,
  611,
  778,
  722,
  278,
  556,
  722,
  611,
  833,
  722,
  778,
  667,
  778,
  722,
  667,
  611,
  722,
  667,
  944,
  667,
  667,
  611,
  333,
  278,
  333,
  584,
  556,
  333,
  556,
  611,
  556,
  611,
  556,
  333,
  611,
  611,
  278,
  278,
  556,
  278,
  889,
  611,
  611,
  611,
  611,
  389,
  556,
  333,
  611,
  556,
  778,
  556,
  556,
  500,
  389,
  280,
  389,
  584,
  556,
  556,
  556,
  278,
  556,
  333,
  1000,
  556,
  556,
  333,
  1000,
  667,
  333,
  1000,
  556,
  611,
  556,
  556,
  278,
  278,
  333,
  333,
  350,
  556,
  1000,
  333,
  1000,
  556,
  333,
  944,
  556,
  500,
  667,
  278,
  333,
  556,
  556,
  556,
  556,
  280,
  556,
  333,
  737,
  370,
  556,
  584,
  333,
  737,
  333,
  400,
  584,
  333,
  333,
  333,
  611,
  556,
  278,
  333,
  333,
  365,
  556,
  834,
  834,
  834,
  611,
  722,
  722,
  722,
  722,
  722,
  722,
  1000,
  722,
  667,
  667,
  667,
  667,
  278,
  278,
  278,
  278,
  722,
  722,
  778,
  778,
  778,
  778,
  778,
  584,
  778,
  722,
  722,
  722,
  722,
  667,
  611,
  611,
  556,
  556,
  556,
  556,
  556,
  556,
  889,
  556,
  556,
  556,
  556,
  556,
  278,
  278,
  278,
  278,
  611,
  611,
  611,
  611,
  611,
  611,
  611,
  584,
  611,
  611,
  611,
  611,
  611,
  556,
  611,
  556,
];
