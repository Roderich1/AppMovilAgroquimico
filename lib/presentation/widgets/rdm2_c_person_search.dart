/// Buscador de personas (ronda 2, sesión C): una sola regla y un solo campo
/// para Personas y Cuentas.
///
/// Antes cada pantalla filtraba a su manera con `matchesSearch`, que busca la
/// consulta ENTERA como un trozo seguido del nombre:
///  * «maria quispe» no encontraba a «María Fernanda Quispe …» (las palabras
///    no van seguidas) y «quispe maria» tampoco;
///  * un espacio doble («maria  quispe»), que el teclado deja al corregir, no
///    encontraba nada;
///  * Cuentas no filtraba la tarjeta del titular ni decía «sin resultados»;
///    Personas sí, con otro texto.
///
/// Aquí cada palabra escrita debe aparecer en el nombre, en cualquier orden y
/// como parte de una palabra («ro» encuentra «Rosa» y «Ríos»). Mayúsculas y
/// tildes no cuentan (UIBUG-019: «maria» encuentra «María» y al revés). La
/// «ñ» se conserva como letra propia, como en `normalizeForSearch`.
library;

import 'package:flutter/material.dart';

import '../../domain/text_search.dart';

/// Forma comparable de [text]: minúsculas, sin tildes, con los espacios
/// (también los de los lados y los dobles) reducidos a uno.
///
/// Un nombre puede llegar con las tildes como marcas sueltas (forma
/// descompuesta, p. ej. pegado desde otra aplicación): las marcas se quitan,
/// salvo la virgulilla tras una «n», que forma la «ñ».
String personSearchKey(String text) {
  final buffer = StringBuffer();
  var previous = '';
  for (final rune in text.runes) {
    if (rune >= 0x300 && rune <= 0x36F) {
      if (rune == 0x303 && (previous == 'n' || previous == 'N')) {
        final s = buffer.toString();
        buffer
          ..clear()
          ..write(s.substring(0, s.length - 1))
          ..write(previous == 'n' ? 'ñ' : 'Ñ');
      }
      continue;
    }
    previous = String.fromCharCode(rune);
    buffer.write(previous);
  }
  return normalizeForSearch(buffer.toString())
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .join(' ');
}

/// `true` si cada palabra de [query] aparece en [name] (ver la biblioteca).
/// Una consulta vacía o sólo de espacios no filtra.
bool matchesPersonSearch(String name, String query) {
  final words = personSearchKey(query).split(' ').where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final key = personSearchKey(name);
  return words.every(key.contains);
}

/// Campo «Buscar persona» con su controlador (el texto no se pierde al
/// recargar la lista) y «Borrar búsqueda».
class Rdm2cPersonSearchField extends StatefulWidget {
  const Rdm2cPersonSearchField({
    super.key,
    required this.query,
    required this.onChanged,
  });

  /// Texto vigente (lo guarda la pantalla).
  final String query;
  final ValueChanged<String> onChanged;

  @override
  State<Rdm2cPersonSearchField> createState() => _Rdm2cPersonSearchFieldState();
}

class _Rdm2cPersonSearchFieldState extends State<Rdm2cPersonSearchField> {
  late final _controller = TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(covariant Rdm2cPersonSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) _controller.text = widget.query;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('person-search'),
    controller: _controller,
    onChanged: (value) {
      widget.onChanged(value);
      setState(() {});
    },
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      labelText: 'Buscar persona',
      isDense: true,
      suffixIcon: _controller.text.isEmpty
          ? null
          : IconButton(
              key: const Key('person-search-clear'),
              tooltip: 'Borrar búsqueda',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                widget.onChanged('');
                setState(() {});
              },
            ),
    ),
  );
}

/// Estado sin resultados, el mismo en Personas y en Cuentas: dice qué se
/// buscó. El filtro de campaña no quita personas de la lista (sólo cambia
/// sus cifras), así que no se menciona.
class Rdm2cNoPersonMatches extends StatelessWidget {
  const Rdm2cNoPersonMatches({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('person-search-empty'),
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
    child: Column(
      children: [
        const Icon(Icons.search_off_outlined, size: 40),
        const SizedBox(height: 12),
        Text(
          'Ninguna persona coincide con «${query.trim()}».',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Pruebe con una parte del nombre o del apellido.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
