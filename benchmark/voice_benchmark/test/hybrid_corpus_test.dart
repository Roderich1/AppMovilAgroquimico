import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_benchmark/bench/corpus.dart';

/// Corpus de la Fase 0-bis.
///
/// Estas pruebas existen porque un corpus se degrada solo: alguien recorta una
/// categoría incómoda, mueve una frase de aceptación a ajuste para que salga
/// mejor, o borra las muestras sin habla porque «no dan resultado». Cualquiera
/// de esas tres cosas invalidaría la comparación entera, y ninguna se nota
/// leyendo un informe.
void main() {
  final hybridSource = File('assets/corpus_hybrid.json').readAsStringSync();
  final hybrid = Corpus.fromJsonString(hybridSource);
  final raw = jsonDecode(hybridSource) as Map<String, Object?>;

  /// Compara ignorando mayúsculas, tildes y puntuación final: mover una frase
  /// de un split a otro cambiándole una coma seguiría siendo hacer trampa.
  String canonical(String text) {
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
    };
    final folded = text
        .toLowerCase()
        .split('')
        .map((c) => accents[c] ?? c)
        .join();
    return folded.replaceAll(RegExp(r'[^a-z0-9ñ ]'), ' ').trim();
  }

  group('separación de conjuntos', () {
    test('ajuste y aceptación no comparten ninguna frase', () {
      final ajuste = {
        for (final s in hybrid.ajuste)
          if (!s.isNonSpeech) canonical(s.text),
      };
      final aceptacion = {
        for (final s in hybrid.aceptacion)
          if (!s.isNonSpeech) canonical(s.text),
      };

      expect(
        ajuste.intersection(aceptacion),
        isEmpty,
        reason: 'afinar con una frase y luego evaluarse con ella no mide nada',
      );
    });

    test('los dos conjuntos tienen contenido', () {
      expect(hybrid.ajuste, isNotEmpty);
      expect(hybrid.aceptacion, isNotEmpty);
      expect(
        hybrid.aceptacion.length,
        greaterThan(hybrid.ajuste.length),
        reason: 'se evalúa con más de lo que se afina',
      );
    });

    test('cada identificador aparece una sola vez', () {
      final ids = hybrid.samples.map((s) => s.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('cobertura de categorías', () {
    const required = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];

    test('las siete categorías del plan están presentes', () {
      for (final category in required) {
        expect(
          hybrid.byCategory(category),
          isNotEmpty,
          reason: 'falta la categoría $category del plan de benchmark',
        );
      }
    });

    test('cada categoría existe en ajuste y en aceptación', () {
      for (final category in required) {
        final samples = hybrid.byCategory(category);
        expect(
          samples.map((s) => s.split).toSet(),
          containsAll(<String>['ajuste', 'aceptacion']),
          reason: 'la categoría $category no puede vivir en un solo conjunto',
        );
      }
    });
  });

  group('lo adversarial no se puede recortar', () {
    test('hay muestras sin habla y son las que deciden el guardrail', () {
      expect(
        hybrid.nonSpeech.length,
        greaterThanOrEqualTo(6),
        reason: 'cualquier texto aceptado aquí es una falsa afirmación',
      );
    });

    test('están los tres silencios de duración distinta', () {
      final conditions = hybrid.nonSpeech.expand((s) => s.conditions).toSet();
      expect(
        conditions,
        containsAll(<String>['silencio_3s', 'silencio_10s', 'silencio_30s']),
      );
    });

    test('están los ruidos de campo que pide el plan', () {
      final conditions = hybrid.samples.expand((s) => s.conditions).toSet();
      expect(
        conditions,
        containsAll(<String>[
          'ruido_viento',
          'ruido_tractor',
          'ruido_conversacion',
          'ruido_radio',
          'golpe_microfono',
        ]),
      );
    });

    test('hay habla real fuera del dominio, que no es lo mismo que ruido', () {
      final outOfDomain = hybrid.samples.where(
        (s) => s.tags.contains('fuera_de_dominio'),
      );
      expect(outOfDomain, isNotEmpty);
      expect(
        outOfDomain.every((s) => s.expected == 'rechazado'),
        isTrue,
      );
    });

    test('hay negaciones y autocorrecciones', () {
      final corrections = hybrid.samples.where(
        (s) => s.conditions.contains('correccion'),
      );
      expect(corrections.length, greaterThanOrEqualTo(4));
    });

    test('hay pausas largas dentro de una misma frase', () {
      expect(
        hybrid.samples.where((s) => s.tags.contains('pausa_larga')),
        isNotEmpty,
      );
    });
  });

  group('catálogo agrícola del plan', () {
    test('están los siete productos exigidos', () {
      final text = hybrid.samples.map((s) => s.text.toLowerCase()).join(' ');
      for (final product in <String>[
        'bellator',
        'germispa',
        'germi cien',
        'germi uno cero cero',
        'expansiv',
        'paraquat',
        'mancozeb',
        'lambdacialotrina',
      ]) {
        expect(
          text,
          contains(product),
          reason: 'el plan exige medir «$product»',
        );
      }
    });

    test('hay compras de uno, dos, cuatro y ocho productos', () {
      final tags = hybrid.samples.expand((s) => s.tags).toSet();
      expect(
        tags,
        containsAll(<String>[
          'un_producto',
          'dos_productos',
          'cuatro_productos',
          'ocho_productos',
        ]),
      );
    });

    test('hay bolivianos y dólares, enteros y decimales', () {
      final tags = hybrid.samples.expand((s) => s.tags).toSet();
      expect(tags, containsAll(<String>['bob', 'usd']));
      expect(tags, containsAll(<String>['precio_entero', 'precio_decimal']));
    });

    test('hay ambigüedades que deben bloquear, no resolverse solas', () {
      final blocking = hybrid.samples.where((s) => s.hasBlockingAmbiguity);
      expect(blocking.length, greaterThanOrEqualTo(3));
      expect(
        blocking.every((s) => s.expected == 'ambiguo'),
        isTrue,
        reason: 'un dato marcado AMBIGUO no puede esperar resultado «listo»',
      );
    });
  });

  group('honestidad del propio archivo', () {
    test('declara que no contiene grabaciones de personas', () {
      expect(raw['audio'], 'NINGUNO_GRABADO');
      expect(raw['consentimiento'], contains('ficticios'));
    });

    test('los recuentos declarados coinciden con el contenido', () {
      final counts = raw['counts']! as Map<String, Object?>;
      expect(counts['total'], hybrid.samples.length);
      expect(counts['ajuste'], hybrid.ajuste.length);
      expect(counts['aceptacion'], hybrid.aceptacion.length);
      expect(counts['sinHabla'], hybrid.nonSpeech.length);
    });

    test('dice explícitamente que no sustituye al corpus de la Fase 0', () {
      expect(raw['relacionConFase0'], contains('SEPARADO'));
      expect(hybrid.corpusVersion, startsWith('hybrid-'));
    });
  });

  group('el corpus de la Fase 0 sigue intacto', () {
    test('conserva sus cien frases y su versión', () {
      // Si alguien lo tocara, las mediciones del POCO dejarían de ser
      // comparables con las nuevas y nadie se enteraría.
      final phase0 = Corpus.fromJsonString(
        File('assets/corpus.json').readAsStringSync(),
      );
      expect(phase0.samples, hasLength(100));
      expect(phase0.ajuste, hasLength(40));
      expect(phase0.aceptacion, hasLength(60));
      expect(phase0.corpusVersion, '1.0.0');
    });

    test('una frase repetida de la Fase 0 se declara y no cambia de conjunto',
        () {
      // Reutilizar una frase no está prohibido: dos de ellas son las que el
      // propietario quiere poder comparar contra lo medido en el POCO. Lo que
      // sí está prohibido es moverla de conjunto. Una frase con la que ya se
      // afinó, evaluada en aceptación, mediría el ajuste y no el motor.
      final phase0 = Corpus.fromJsonString(
        File('assets/corpus.json').readAsStringSync(),
      );
      final old = {
        for (final s in phase0.samples) canonical(s.text): s,
      };

      final undeclared = <String>[];
      final movedSplit = <String>[];
      for (final sample in hybrid.samples) {
        if (sample.isNonSpeech) continue;
        final previous = old[canonical(sample.text)];
        if (previous == null) continue;
        if (!sample.tags.contains('heredada_fase0')) {
          undeclared.add('${sample.id} repite ${previous.id}');
        } else if (previous.split != sample.split) {
          movedSplit.add('${sample.id} (${previous.id}) cambia de conjunto');
        }
      }

      expect(undeclared, isEmpty);
      expect(movedSplit, isEmpty);
    });

    test('las heredadas están marcadas y son pocas', () {
      final inherited = hybrid.samples.where(
        (s) => s.tags.contains('heredada_fase0'),
      );
      expect(inherited, isNotEmpty);
      expect(
        inherited.length,
        lessThanOrEqualTo(5),
        reason: 'si crecen, el corpus nuevo deja de ser un corpus nuevo',
      );
      expect(
        inherited.every((s) => (s.note ?? '').contains('Fase 0')),
        isTrue,
        reason: 'cada herencia dice de dónde viene',
      );
    });
  });
}
