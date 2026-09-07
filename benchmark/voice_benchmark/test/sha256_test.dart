import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/bench/sha256.dart';

/// El digest es lo que sostiene «este corpus es el que se midió».
///
/// Se implementa aquí en vez de traer una dependencia porque el banco declara
/// cada artefacto de terceros en `THIRD_PARTY.md`, y añadir uno para 90 líneas
/// de aritmética entera cuesta más de lo que ahorra. A cambio, la
/// implementación tiene que probarse contra vectores publicados: un SHA-256
/// casi correcto es peor que ninguno, porque bloquearía corridas buenas y
/// dejaría pasar contenido cambiado sin que nadie sospeche del hash.
void main() {
  group('vectores publicados (FIPS 180-4)', () {
    test('cadena vacía', () {
      expect(
        sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('«abc»', () {
      expect(
        sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('mensaje de 448 bits, justo en el borde del relleno', () {
      expect(
        sha256Hex(
          utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          ),
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
    });

    test('mensaje de 896 bits, que obliga a un bloque de relleno propio', () {
      expect(
        sha256Hex(
          utf8.encode(
            'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn'
            'hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu',
          ),
        ),
        'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1',
      );
    });

    test('un millón de «a»', () {
      expect(
        sha256Hex(List<int>.filled(1000000, 0x61)),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });
  });

  group('longitudes que rompen una implementación descuidada', () {
    test('55, 56, 57 y 64 bytes: los tres casos del relleno', () {
      // 55 cabe con su relleno en un bloque; 56 ya no y obliga a uno extra; 64
      // es un bloque exacto. Una implementación que se equivoque aquí acierta
      // en «abc» y falla en un archivo real.
      const esperados = <int, String>{
        55: '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318',
        56: 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a',
        57: 'f13b2d724659eb3bf47f2dd6af1accc87b81f09f59f2b75e5c0bed6589dfe8c6',
        64: 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb',
      };
      for (final entry in esperados.entries) {
        expect(
          sha256Hex(List<int>.filled(entry.key, 0x61)),
          entry.value,
          reason: '${entry.key} bytes de «a»',
        );
      }
    });
  });

  group('coincide con lo que calcula el sistema operativo', () {
    // Si esta prueba y `sha256sum` no dieran lo mismo, el digest que muestra la
    // pantalla del teléfono no podría comprobarse desde fuera, y la identidad
    // del corpus dejaría de ser verificable por un tercero.
    test('corpus de la Fase 0', () {
      expect(
        sha256Hex(File('assets/corpus.json').readAsBytesSync()),
        '7a891fd1a6aa2d9c4f122cc79a9f7fac646ce52f634bc51dcc59a7c9683f6b6b',
      );
    });

    test('corpus híbrido A–G', () {
      expect(
        sha256Hex(File('assets/corpus_hybrid.json').readAsBytesSync()),
        '52822895357baf2f9d207d346bef22b07970035d66103ec005609dfaefb00bd0',
      );
    });
  });
}
