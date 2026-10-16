// F05-SYNC-01 (MOB #29): identificador global sólo para la intención de
// sincronización (UUID v4), nunca derivado de enteros de SQLite.
import 'dart:math';

import 'package:agroquimicos/domain/sync/operation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('operationId (MOB #29)', () {
    test('UUID v4 en minúsculas: versión 4 y variante 10', () {
      for (var i = 0; i < 1000; i++) {
        final id = newOperationId();
        expect(id, matches(uuidV4Lowercase));
        expect(id[14], '4');
        expect('89ab'.contains(id[19]), isTrue);
      }
    });

    test('10 000 identificadores sin repetidos', () {
      final ids = {for (var i = 0; i < 10000; i++) newOperationId()};
      expect(ids, hasLength(10000));
    });

    test('dos instalaciones con la misma secuencia local no colisionan', () {
      // Cada instalación genera desde su propia fuente aleatoria; ninguna
      // parte del identificador sale del entero de SQLite.
      final a = newOperationId(Random(1));
      final b = newOperationId(Random(2));
      expect(a, isNot(b));
      expect(a, matches(uuidV4Lowercase));
    });
  });
}
