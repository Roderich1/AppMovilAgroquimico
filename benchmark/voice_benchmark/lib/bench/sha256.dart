/// SHA-256 sobre bytes, en Dart puro.
///
/// ## Por qué no se trae una dependencia
///
/// El banco declara en `THIRD_PARTY.md` cada artefacto de terceros con versión,
/// licencia, tamaño y hash, y `RISK-033` ya documenta lo caro que sale un
/// binario cuya procedencia no se puede cerrar. Añadir un paquete para noventa
/// líneas de aritmética entera —que además se puede comprobar contra vectores
/// publicados— costaría más de lo que ahorra.
///
/// ## Para qué se usa
///
/// Para calcular el digest de los bytes del corpus que el banco acaba de leer y
/// contrastarlo con el que está fijado en `corpus_catalog.dart`. Ese número es
/// lo único que distingue «el corpus A–G» de «un archivo que dice llamarse
/// A–G». Se muestra en la pantalla antes de grabar y viaja en cada resultado
/// exportado, de modo que cualquiera puede repetir `sha256sum` sobre el archivo
/// del repositorio y obtener lo mismo.
///
/// La implementación sigue FIPS 180-4 y está probada contra los vectores
/// publicados en `test/sha256_test.dart`, incluidos los tres largos de mensaje
/// que rompen un relleno mal escrito.
library;

import 'dart:typed_data';

/// Constantes de ronda: parte fraccionaria de la raíz cúbica de los 64 primeros
/// primos.
const List<int> _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

/// Digest SHA-256 de [bytes], en minúsculas y sin separadores.
///
/// Toma los bytes tal cual, sin normalizar nada. Es deliberado: un archivo con
/// otro fin de línea **es** otro archivo, y el `.gitattributes` del repositorio
/// existe justamente para que el mismo commit dé los mismos bytes en Windows y
/// en Linux. Normalizar aquí escondería ese problema en vez de resolverlo.
String sha256Hex(List<int> bytes) {
  // Los ocho valores iniciales: parte fraccionaria de la raíz cuadrada de los
  // ocho primeros primos.
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  final padded = _pad(bytes);
  // Sin signo a propósito: `Int32List` guardaría los valores ya truncados a 32
  // bits con signo y las rotaciones traerían el bit de signo de vuelta.
  final w = Uint32List(64);

  for (var offset = 0; offset < padded.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      final j = offset + i * 4;
      w[i] =
          (padded[j] << 24) |
          (padded[j + 1] << 16) |
          (padded[j + 2] << 8) |
          padded[j + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 =
          _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (_u(w[i - 15]) >> 3);
      final s1 =
          _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (_u(w[i - 2]) >> 10);
      w[i] = _add(_add(w[i - 16], s0), _add(w[i - 7], s1));
    }

    var a = h0, b = h1, c = h2, d = h3;
    var e = h4, f = h5, g = h6, h = h7;

    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & g);
      final temp1 = _add(_add(_add(h, s1), _add(ch, _k[i])), w[i]);
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = _add(s0, maj);

      h = g;
      g = f;
      f = e;
      e = _add(d, temp1);
      d = c;
      c = b;
      b = a;
      a = _add(temp1, temp2);
    }

    h0 = _add(h0, a);
    h1 = _add(h1, b);
    h2 = _add(h2, c);
    h3 = _add(h3, d);
    h4 = _add(h4, e);
    h5 = _add(h5, f);
    h6 = _add(h6, g);
    h7 = _add(h7, h);
  }

  return [h0, h1, h2, h3, h4, h5, h6, h7].map(_hex8).join();
}

/// Relleno de FIPS 180-4: un `0x80`, ceros, y la longitud **en bits** en los
/// últimos ocho bytes big-endian.
///
/// El caso que rompe una implementación descuidada es el mensaje de 56 bytes:
/// el `0x80` y los ocho de longitud ya no caben en el bloque, y hace falta uno
/// entero de más. Está en las pruebas.
Uint8List _pad(List<int> bytes) {
  final lengthInBits = bytes.length * 8;
  final totalBlocks = ((bytes.length + 9) / 64).ceil();
  final out = Uint8List(totalBlocks * 64)..setRange(0, bytes.length, bytes);
  out[bytes.length] = 0x80;
  // La longitud se escribe como 64 bits. Dart maneja enteros de 64 bits con
  // signo en la VM, suficiente para cualquier corpus imaginable.
  for (var i = 0; i < 8; i++) {
    out[out.length - 1 - i] = (lengthInBits >> (8 * i)) & 0xff;
  }
  return out;
}

/// Suma módulo 2^32.
int _add(int a, int b) => (a + b) & 0xffffffff;

/// Interpreta el valor como entero de 32 bits sin signo.
int _u(int value) => value & 0xffffffff;

/// Rotación a la derecha sobre 32 bits.
int _rotr(int value, int bits) {
  final v = _u(value);
  return _u((v >> bits) | (v << (32 - bits)));
}

String _hex8(int value) => _u(value).toRadixString(16).padLeft(8, '0');
