// Lector de pruebas para los libros `.xlsx` de reportes.
//
// Descomprime el libro, comprueba que CADA parte XML esté bien formada con un
// analizador estricto (sin dependencias nuevas: el proyecto no tiene
// `package:xml`) y expone la hoja como celdas tipadas y como «registros»
// equivalentes a los del antiguo CSV, para que las pruebas que comparaban
// registros sigan comparando lo mismo.

import 'dart:convert';

import 'package:archive/archive.dart';

/// Elemento XML ya decodificado.
class XmlNode {
  XmlNode(this.name, this.attributes);
  final String name;
  final Map<String, String> attributes;
  final List<XmlNode> children = [];
  final StringBuffer _text = StringBuffer();

  /// Texto directo del elemento, con entidades ya resueltas.
  String get text => _text.toString();

  Iterable<XmlNode> all(String name) sync* {
    for (final child in children) {
      if (child.name == name) yield child;
      yield* child.all(name);
    }
  }

  XmlNode? first(String name) {
    for (final node in all(name)) {
      return node;
    }
    return null;
  }
}

/// La parte no es XML bien formado.
class XmlFormatError implements Exception {
  XmlFormatError(this.message);
  final String message;
  @override
  String toString() => 'XML mal formado: $message';
}

/// Analizador estricto del subconjunto de XML que usa SpreadsheetML:
/// declaración, elementos, atributos entre comillas, texto y referencias.
/// Rechaza `&` sueltos, entidades desconocidas, `<` en atributos, caracteres
/// prohibidos por XML 1.0, etiquetas sin cerrar o cruzadas y más de una raíz.
XmlNode parseXml(String source) {
  var i = 0;
  final stack = <XmlNode>[];
  XmlNode? root;

  Never fail(String why) => throw XmlFormatError('$why (posición $i)');

  void checkChars(String value) {
    for (final unit in value.codeUnits) {
      final allowed =
          unit == 0x09 ||
          unit == 0x0A ||
          unit == 0x0D ||
          (unit >= 0x20 && unit != 0xFFFE && unit != 0xFFFF);
      if (!allowed) fail('carácter prohibido U+${unit.toRadixString(16)}');
    }
  }

  String decode(String raw) {
    checkChars(raw);
    final out = StringBuffer();
    var j = 0;
    while (j < raw.length) {
      final c = raw[j];
      if (c == '<') fail('«<» sin escapar');
      if (c != '&') {
        out.write(c);
        j++;
        continue;
      }
      final end = raw.indexOf(';', j);
      if (end < 0) fail('«&» sin escapar');
      final entity = raw.substring(j + 1, end);
      switch (entity) {
        case 'amp':
          out.write('&');
        case 'lt':
          out.write('<');
        case 'gt':
          out.write('>');
        case 'quot':
          out.write('"');
        case 'apos':
          out.write("'");
        default:
          final hex = RegExp(r'^#x([0-9A-Fa-f]+)$').firstMatch(entity);
          final dec = RegExp(r'^#([0-9]+)$').firstMatch(entity);
          if (hex != null) {
            out.writeCharCode(int.parse(hex[1]!, radix: 16));
          } else if (dec != null) {
            out.writeCharCode(int.parse(dec[1]!));
          } else {
            fail('entidad desconocida «&$entity;»');
          }
      }
      j = end + 1;
    }
    return out.toString();
  }

  final nameChars = RegExp(r'[A-Za-z_:][-A-Za-z0-9_:.]*');

  if (source.startsWith('<?xml')) {
    final end = source.indexOf('?>');
    if (end < 0) fail('declaración sin cerrar');
    i = end + 2;
  }

  while (i < source.length) {
    final lt = source.indexOf('<', i);
    final textEnd = lt < 0 ? source.length : lt;
    final rawText = source.substring(i, textEnd);
    if (stack.isEmpty) {
      if (rawText.trim().isNotEmpty) fail('texto fuera de la raíz');
    } else {
      stack.last._text.write(decode(rawText));
    }
    if (lt < 0) break;
    i = lt;
    if (source.startsWith('</', i)) {
      final match = nameChars.matchAsPrefix(source, i + 2);
      if (match == null) fail('cierre sin nombre');
      final close = source.indexOf('>', match.end);
      if (close < 0 || source.substring(match.end, close).trim().isNotEmpty) {
        fail('cierre mal formado');
      }
      if (stack.isEmpty || stack.last.name != match[0]) {
        fail('cierre «${match[0]}» sin apertura');
      }
      stack.removeLast();
      i = close + 1;
      continue;
    }
    final match = nameChars.matchAsPrefix(source, i + 1);
    if (match == null) fail('etiqueta sin nombre');
    final node = XmlNode(match[0]!, {});
    var j = match.end;
    var selfClosing = false;
    while (true) {
      final ws = RegExp(r'\s*').matchAsPrefix(source, j)!;
      final hadSpace = ws.end > j;
      j = ws.end;
      if (j >= source.length) fail('etiqueta sin cerrar');
      if (source.startsWith('/>', j)) {
        selfClosing = true;
        j += 2;
        break;
      }
      if (source[j] == '>') {
        j++;
        break;
      }
      if (!hadSpace) fail('atributo sin espacio previo');
      final attr = nameChars.matchAsPrefix(source, j);
      if (attr == null) fail('atributo sin nombre');
      j = attr.end;
      if (j >= source.length || source[j] != '=') fail('atributo sin «=»');
      j++;
      final quote = source[j];
      if (quote != '"' && quote != "'") fail('atributo sin comillas');
      final end = source.indexOf(quote, j + 1);
      if (end < 0) fail('atributo sin cerrar');
      if (node.attributes.containsKey(attr[0])) fail('atributo repetido');
      node.attributes[attr[0]!] = decode(source.substring(j + 1, end));
      j = end + 1;
    }
    if (stack.isEmpty) {
      if (root != null) fail('más de una raíz');
      root = node;
    } else {
      stack.last.children.add(node);
    }
    if (!selfClosing) stack.add(node);
    i = j;
  }
  if (stack.isNotEmpty) fail('«${stack.last.name}» sin cerrar');
  if (root == null) fail('sin raíz');
  return root;
}

/// Una celda de la hoja.
class XlsxCell {
  XlsxCell(this.ref, this.type, this.style, this.value);
  final String ref;

  /// `null` o `n` es número; `inlineStr` es cadena.
  final String? type;
  final int style;

  /// `<v>` tal cual para números; el texto decodificado para cadenas.
  final String value;

  bool get isNumber => type == null || type == 'n';
  bool get isInlineString => type == 'inlineStr';

  /// Cómo se escribía en el CSV: número con coma decimal, texto tal cual.
  String get record => isNumber ? value.replaceAll('.', ',') : value;

  int get column => columnIndex(ref);
  int get row => int.parse(RegExp(r'\d+').firstMatch(ref)![0]!);
}

/// Formato de un `xf` de `cellXfs`.
class XlsxStyle {
  XlsxStyle({
    required this.numFmtId,
    required this.bold,
    required this.quotePrefix,
  });
  final int numFmtId;
  final bool bold;
  final bool quotePrefix;
}

/// Columna (1 = A) de una referencia como `AB12`.
int columnIndex(String ref) {
  final letters = RegExp(r'^[A-Z]+').firstMatch(ref)![0]!;
  var n = 0;
  for (final unit in letters.codeUnits) {
    n = n * 26 + (unit - 64);
  }
  return n;
}

/// Libro leído y validado.
class XlsxBook {
  XlsxBook._(
    this.parts,
    this.sheetName,
    this.cells,
    this.styles,
    this.numFmts,
    this.autoFilter,
    this.frozenRows,
    this.frozenTopLeft,
    this.filterDatabase,
    this.hasFormula,
  );

  /// Todas las partes del ZIP, como texto.
  final Map<String, String> parts;
  final String sheetName;
  final Map<String, XlsxCell> cells;
  final List<XlsxStyle> styles;

  /// `numFmtId` → código, de los formatos propios del libro.
  final Map<int, String> numFmts;
  final String? autoFilter;
  final int? frozenRows;
  final String? frozenTopLeft;

  /// Valor del nombre oculto `_xlnm._FilterDatabase`.
  final String? filterDatabase;

  /// Hay algún `<f>` en la hoja.
  final bool hasFormula;

  XlsxCell? operator [](String ref) => cells[ref];

  XlsxStyle styleOf(XlsxCell cell) => styles[cell.style];

  /// Formato numérico efectivo de una celda: `#,##0.00`, `dd/mm/yyyy`…
  String numberFormatOf(XlsxCell cell) {
    final id = styleOf(cell).numFmtId;
    return numFmts[id] ??
        switch (id) {
          0 => 'General',
          3 => '#,##0',
          4 => '#,##0.00',
          14 => 'm/d/yyyy',
          _ => 'id $id',
        };
  }

  int get lastRow =>
      cells.values.fold(0, (max, cell) => cell.row > max ? cell.row : max);

  /// Filas, primera y última, del autofiltro.
  (int, int)? get filterRows {
    final ref = autoFilter;
    if (ref == null) return null;
    final [from, to] = ref.split(':');
    int row(String r) => int.parse(RegExp(r'\d+').firstMatch(r)![0]!);
    return (row(from), row(to));
  }

  int get filterWidth => columnIndex(autoFilter!.split(':').last);

  /// Texto de la celda como lo escribía el CSV: número con coma decimal,
  /// fecha `dd/mm/aaaa`, texto tal cual.
  String recordOf(XlsxCell cell) {
    if (cell.isNumber && numberFormatOf(cell) == 'dd/mm/yyyy') {
      final date = DateTime.utc(
        1899,
        12,
        30,
      ).add(Duration(days: int.parse(cell.value)));
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(date.day)}/${two(date.month)}/${date.year}';
    }
    return cell.record;
  }

  /// La hoja como registros `;` del antiguo CSV: una fila vacía es `''`, las
  /// filas de la tabla (cabecera y datos, el rango del autofiltro) llevan
  /// todas sus columnas aunque las últimas estén vacías, y el resto acaba en
  /// su última celda escrita.
  List<String> get records {
    final byRow = <int, List<XlsxCell>>{};
    for (final cell in cells.values) {
      byRow.putIfAbsent(cell.row, () => []).add(cell);
    }
    final range = filterRows;
    return [
      for (var r = 1; r <= lastRow; r++)
        () {
          final row = byRow[r] ?? const <XlsxCell>[];
          var width = row.fold(0, (m, c) => c.column > m ? c.column : m);
          if (range != null && r >= range.$1 && r <= range.$2) {
            if (width > filterWidth) {
              throw StateError('Fila $r más ancha que la tabla.');
            }
            width = filterWidth;
          }
          final fields = List.filled(width, '');
          for (final cell in row) {
            fields[cell.column - 1] = recordOf(cell);
          }
          return fields.join(';');
        }(),
    ];
  }

  /// Celdas de TEXTO cuyo contenido parece un número: no debería haber
  /// ninguna en un reporte, porque los números se escriben como números.
  List<String> get numberLookingTexts => [
    for (final cell in cells.values)
      if (!cell.isNumber &&
          RegExp(r'^-?\d+([.,]\d+)?$').hasMatch(cell.value.trim()))
        '${cell.ref}=${cell.value}',
  ];
}

/// Decodifica los escapes `_xHHHH_` de SpreadsheetML.
String decodeSpreadsheetEscapes(String value) => value.replaceAllMapped(
  RegExp(r'_x([0-9A-Fa-f]{4})_'),
  (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
);

/// Descomprime, valida y lee el libro de una sola hoja.
XlsxBook readXlsx(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final parts = <String, String>{
    for (final file in archive.files)
      if (file.isFile) file.name: utf8.decode(file.content),
  };
  final xml = <String, XmlNode>{
    for (final entry in parts.entries)
      if (entry.key.endsWith('.xml') || entry.key.endsWith('.rels'))
        entry.key: parseXml(entry.value),
  };

  // Paquete: tipos de contenido y relaciones apuntan a partes que existen.
  final types = xml['[Content_Types].xml']!;
  for (final override in types.all('Override')) {
    final part = override.attributes['PartName']!.substring(1);
    if (!parts.containsKey(part)) throw StateError('Falta la parte $part.');
  }
  final rootRel = xml['_rels/.rels']!.first('Relationship')!;
  final workbookPath = rootRel.attributes['Target']!;
  final workbook = xml[workbookPath]!;
  final sheets = workbook.all('sheet').toList();
  if (sheets.length != 1) throw StateError('Se esperaba una sola hoja.');
  final sheetName = sheets.single.attributes['name']!;
  final rels = xml['xl/_rels/workbook.xml.rels']!;
  final sheetTarget = rels
      .all('Relationship')
      .firstWhere((r) => r.attributes['Id'] == sheets.single.attributes['r:id'])
      .attributes['Target']!;
  final sheet = xml['xl/$sheetTarget']!;

  final cells = <String, XlsxCell>{};
  for (final c in sheet.all('c')) {
    final ref = c.attributes['r']!;
    final type = c.attributes['t'];
    final style = int.parse(c.attributes['s'] ?? '0');
    final String value;
    if (type == 'inlineStr') {
      value = decodeSpreadsheetEscapes(
        c.first('is')!.all('t').map((t) => t.text).join(),
      );
    } else if (type == null || type == 'n') {
      value = c.first('v')!.text;
      if (num.tryParse(value) == null) {
        throw StateError('$ref no es un número: «$value».');
      }
    } else {
      throw StateError('$ref tiene un tipo inesperado: $type.');
    }
    if (cells.containsKey(ref)) throw StateError('$ref repetida.');
    cells[ref] = XlsxCell(ref, type, style, value);
  }

  final styleSheet = xml['xl/styles.xml']!;
  final fonts = styleSheet.first('fonts')!.children;
  final styles = [
    for (final xf in styleSheet.first('cellXfs')!.children)
      XlsxStyle(
        numFmtId: int.parse(xf.attributes['numFmtId'] ?? '0'),
        bold:
            fonts[int.parse(xf.attributes['fontId'] ?? '0')].first('b') != null,
        quotePrefix: xf.attributes['quotePrefix'] == '1',
      ),
  ];
  final numFmts = {
    for (final f in styleSheet.all('numFmt'))
      int.parse(f.attributes['numFmtId']!): f.attributes['formatCode']!,
  };
  for (final cell in cells.values) {
    if (cell.style >= styles.length) {
      throw StateError('${cell.ref} usa un estilo inexistente.');
    }
  }

  final pane = sheet.first('pane');
  final frozen = pane?.attributes['state'] == 'frozen';
  final filterDb = workbook
      .all('definedName')
      .where((d) => d.attributes['name'] == '_xlnm._FilterDatabase')
      .map((d) => d.text)
      .firstOrNull;

  return XlsxBook._(
    parts,
    sheetName,
    cells,
    styles,
    numFmts,
    sheet.first('autoFilter')?.attributes['ref'],
    frozen ? int.parse(pane!.attributes['ySplit']!) : null,
    frozen ? pane!.attributes['topLeftCell'] : null,
    filterDb,
    sheet.first('f') != null,
  );
}

/// Atajo: los registros del libro, comprobando además que ningún número se
/// haya escrito como texto.
List<String> xlsxRecords(List<int> bytes) {
  final book = readXlsx(bytes);
  if (book.numberLookingTexts.isNotEmpty) {
    throw StateError('Números escritos como texto: ${book.numberLookingTexts}');
  }
  return book.records;
}
